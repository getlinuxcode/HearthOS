// Émulateurs autonomes (hors libretro) : Switch via Eden, Switch 2 via Eden-NX2.
// Ils ne sont ni dans les dépôts Arch ni livrés avec Hearth : on télécharge l'AppImage
// Linux officielle du projet à la demande. Aucune clé ni firmware n'est fourni :
// le joueur dépose ceux de sa propre console dans bios/switch/ (ou bios/switch2/).
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { BIOS_DIR, DATA_DIR, MOCK } from '../config.js';
import { HttpError, launchDetached, readJson, sleep, writeJson } from '../util.js';
import type { ChildProcess } from 'node:child_process';

interface StandaloneDef {
  name: string;
  /** API des releases (format Gitea/Forgejo ou GitHub, mêmes champs utiles) */
  releasesApi: string;
  /** Choix du fichier Linux x86_64 parmi les assets */
  asset: RegExp;
  /** Dossier de données utilisateur de l'émulateur (~/.local/share/<dir>) */
  dataDir: string;
  /** Sous-dossier de bios/ où le joueur dépose prod.keys, title.keys et firmware/ */
  biosDir: string;
}

export const STANDALONE: Record<string, StandaloneDef> = {
  eden: {
    name: 'Eden',
    releasesApi: 'https://git.eden-emu.dev/api/v1/repos/eden-emu/eden/releases?limit=5',
    asset: /^Eden-Linux-(v[\d.]+-)?amd64-clang-pgo\.AppImage$/,
    dataDir: 'eden',
    biosDir: 'switch',
  },
  'eden-nx2': {
    name: 'Eden-NX2',
    releasesApi: 'https://api.github.com/repos/eden-nx2/eden-nx2/releases?per_page=5',
    asset: /^eden-linux-x86_64\.AppImage$/,
    dataDir: 'eden',
    biosDir: 'switch2',
  },
};

const ROOT = path.join(DATA_DIR, 'emulators');
const mockInstalled = new Set<string>(readJson<string[]>('mock-standalone.json', []));

function binPath(id: string) {
  return path.join(ROOT, id, `${id}.AppImage`);
}

export function isInstalled(id: string): boolean {
  return MOCK ? mockInstalled.has(id) : fs.existsSync(binPath(id));
}

export function installedVersion(id: string): string | undefined {
  try {
    return fs.readFileSync(path.join(ROOT, id, 'version'), 'utf8').trim() || undefined;
  } catch {
    return undefined;
  }
}

interface Release {
  tag_name: string;
  prerelease?: boolean;
  assets: { name: string; browser_download_url: string; size?: number }[];
}

export async function install(id: string): Promise<void> {
  const def = STANDALONE[id];
  if (!def) throw new HttpError(404, 'Émulateur inconnu');
  if (MOCK) {
    await sleep(2000);
    mockInstalled.add(id);
    writeJson('mock-standalone.json', [...mockInstalled]);
    return;
  }
  const res = await fetch(def.releasesApi, { headers: { Accept: 'application/json', 'User-Agent': 'hearth-console' } });
  if (!res.ok) throw new HttpError(502, `${def.name} : liste des versions indisponible (HTTP ${res.status})`);
  const releases = (await res.json()) as Release[];
  let pick: { rel: Release; url: string } | undefined;
  for (const rel of releases) {
    const a = rel.assets?.find((x) => def.asset.test(x.name));
    if (a) {
      pick = { rel, url: a.browser_download_url };
      break;
    }
  }
  if (!pick) throw new HttpError(502, `${def.name} : aucune version Linux trouvée`);

  const dir = path.join(ROOT, id);
  fs.mkdirSync(dir, { recursive: true });
  const tmp = binPath(id) + '.part';
  const dl = await fetch(pick.url, { headers: { 'User-Agent': 'hearth-console' } });
  if (!dl.ok || !dl.body) throw new HttpError(502, `${def.name} : téléchargement impossible (HTTP ${dl.status})`);
  const buf = Buffer.from(await dl.arrayBuffer());
  // Une AppImage commence par un en-tête ELF : on refuse une page d'erreur HTML.
  if (buf.length < 1_000_000 || buf.subarray(0, 4).toString('latin1') !== '\x7fELF')
    throw new HttpError(502, `${def.name} : fichier téléchargé invalide`);
  fs.writeFileSync(tmp, buf, { mode: 0o755 });
  fs.renameSync(tmp, binPath(id));
  fs.writeFileSync(path.join(dir, 'version'), pick.rel.tag_name);
}

/** Fichiers attendus du joueur, relatifs à bios/. */
export function requiredFiles(id: string): string[] {
  const d = STANDALONE[id].biosDir;
  return [`${d}/prod.keys`, `${d}/firmware`];
}

/**
 * Copie clés et firmware du dossier bios/ vers le dossier de l'émulateur :
 * keys/ pour les .keys, nand/system/Contents/registered/ pour les .nca du firmware.
 */
function syncKeys(def: StandaloneDef) {
  const src = path.join(BIOS_DIR, def.biosDir);
  const dst = path.join(os.homedir(), '.local/share', def.dataDir);
  if (!fs.existsSync(src)) return;
  const keysDir = path.join(dst, 'keys');
  fs.mkdirSync(keysDir, { recursive: true });
  for (const f of fs.readdirSync(src)) {
    if (f.endsWith('.keys')) fs.copyFileSync(path.join(src, f), path.join(keysDir, f));
  }
  const fw = path.join(src, 'firmware');
  if (fs.existsSync(fw)) {
    const reg = path.join(dst, 'nand/system/Contents/registered');
    fs.mkdirSync(reg, { recursive: true });
    for (const f of fs.readdirSync(fw)) {
      if (!f.toLowerCase().endsWith('.nca')) continue;
      const to = path.join(reg, f);
      if (!fs.existsSync(to)) fs.copyFileSync(path.join(fw, f), to);
    }
  }
}

export function launch(id: string, rom: string): ChildProcess | null {
  const def = STANDALONE[id];
  if (MOCK) {
    console.log(`[emu] simulation : ${def.name} -f -g "${rom}"`);
    return null;
  }
  if (!isInstalled(id)) throw new HttpError(409, `${def.name} non installé`);
  syncKeys(def);
  // -f plein écran, -g lance directement le jeu (pas d'interface de l'émulateur).
  // APPIMAGE_EXTRACT_AND_RUN évite de dépendre de FUSE.
  return launchDetached(binPath(id), ['-f', '-g', rom], { APPIMAGE_EXTRACT_AND_RUN: '1' });
}
