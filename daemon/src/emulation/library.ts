import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { BIOS_DIR, MOCK, ROMS_DIR } from '../config.js';
import type { EmuSystem, Game, RomFolder } from '../types.js';
import { HttpError, launchDetached, pacmanInstall, readJson, sleep, writeJson } from '../util.js';
import { accepts, byId, SYSTEMS, systemForExt, systemForFolderName, type SystemDef } from './systems.js';
import { track } from '../running.js';
import * as standalone from './standalone.js';

const CORE_DIRS = ['/usr/lib/libretro', '/usr/lib64/libretro', path.join(process.env.HOME ?? '', '.config/retroarch/cores')];
const RETROARCH_CFG = '/etc/hearth/retroarch.cfg';
const MAX_DEPTH = 4;

interface FolderConf {
  id: string;
  path: string;
  system: string; // 'auto' ou id
}

interface Stats {
  playtimeMinutes: number;
  lastPlayed: number;
}

let folders: FolderConf[] = readJson<FolderConf[]>('rom-folders.json', [{ id: 'default', path: ROMS_DIR, system: 'auto' }]);
const stats: Record<string, Stats> = readJson('rom-stats.json', {});
/** En mode mock, les cœurs « installés » sont simulés. */
const mockCores = new Set<string>(readJson<string[]>('mock-cores.json', ['snes9x', 'mgba']));

let roms = new Map<string, Game>();
const watchers = new Map<string, fs.FSWatcher>();
let rescanTimer: NodeJS.Timeout | null = null;
const listeners = new Set<() => void>();

export function onChange(fn: () => void) {
  listeners.add(fn);
}

// ---------------------------------------------------------------- Scan

function romId(file: string) {
  return 'rom:' + crypto.createHash('sha1').update(path.resolve(file)).digest('hex').slice(0, 16);
}

/** Nom lisible : "Super Metroid (Japan, USA) (En,Ja).sfc" → "Super Metroid" */
function prettyName(file: string) {
  return path
    .basename(file, path.extname(file))
    .replace(/\s*[([].*?[)\]]/g, '')
    .replace(/_/g, ' ')
    .trim();
}

function thumbUrl(sys: SystemDef, file: string) {
  // libretro-thumbnails : nom exact No-Intro, caractères &*/:`<>?\| remplacés par _
  const name = path.basename(file, path.extname(file)).replace(/[&*/:`<>?\\|]/g, '_');
  return `https://thumbnails.libretro.com/${encodeURIComponent(sys.thumbs)}/Named_Boxarts/${encodeURIComponent(name)}.png`;
}

function walk(dir: string, folder: FolderConf, inherited: SystemDef | undefined, depth: number, out: Map<string, Game>) {
  let entries: fs.Dirent[];
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return;
  }
  const names = new Set(entries.map((e) => e.name.toLowerCase()));
  for (const e of entries) {
    if (e.name.startsWith('.')) continue;
    const full = path.join(dir, e.name);
    if (e.isDirectory()) {
      if (depth < MAX_DEPTH) walk(full, folder, inherited ?? (folder.system === 'auto' ? systemForFolderName(e.name) : undefined), depth + 1, out);
      continue;
    }
    const ext = path.extname(e.name).toLowerCase();
    // piste .bin d'un .cue : on ne garde que le .cue
    if (ext === '.bin' && names.has(e.name.slice(0, -4).toLowerCase() + '.cue')) continue;
    const sys = inherited ? (accepts(inherited, ext) ? inherited : undefined) : systemForExt(ext);
    if (!sys) continue;
    const id = romId(full);
    out.set(id, {
      id,
      name: prettyName(e.name),
      source: 'rom',
      system: sys.id,
      path: full,
      installed: true,
      coverUrl: sys.thumbs ? thumbUrl(sys, e.name) : undefined,
      playtimeMinutes: stats[id]?.playtimeMinutes ?? 0,
      lastPlayed: stats[id]?.lastPlayed ?? 0,
    });
  }
}

export function rescan() {
  const next = new Map<string, Game>();
  for (const f of folders) walk(f.path, f, f.system === 'auto' ? undefined : byId.get(f.system), 0, next);
  roms = next;
  listeners.forEach((l) => l());
}

function scheduleRescan() {
  if (rescanTimer) clearTimeout(rescanTimer);
  rescanTimer = setTimeout(rescan, 1500); // attend la fin d'un transfert FTP en rafale
}

function watch(f: FolderConf) {
  watchers.get(f.id)?.close();
  try {
    // recursive est supporté sous Linux depuis Node 20, et sous Windows.
    const w = fs.watch(f.path, { recursive: true }, scheduleRescan);
    w.on('error', () => watchers.delete(f.id));
    watchers.set(f.id, w);
  } catch (e) {
    console.warn(`[roms] surveillance impossible de ${f.path}:`, (e as Error).message);
  }
}

export function init() {
  for (const f of folders) watch(f);
  rescan();
}

// ---------------------------------------------------------------- Dossiers

export function listFolders(): RomFolder[] {
  return folders.map((f) => ({
    ...f,
    watching: watchers.has(f.id),
    romCount: [...roms.values()].filter((g) => g.path!.startsWith(path.resolve(f.path))).length,
  }));
}

export function addFolder(p: string, system: string): RomFolder[] {
  const abs = path.resolve(p);
  if (!fs.existsSync(abs) || !fs.statSync(abs).isDirectory()) throw new HttpError(400, 'Dossier introuvable');
  if (system !== 'auto' && !byId.has(system)) throw new HttpError(400, 'Système inconnu');
  if (folders.some((f) => path.resolve(f.path) === abs)) throw new HttpError(409, 'Dossier déjà suivi');
  const conf = { id: crypto.randomUUID().slice(0, 8), path: abs, system };
  folders.push(conf);
  writeJson('rom-folders.json', folders);
  watch(conf);
  rescan();
  return listFolders();
}

export function updateFolder(id: string, system: string): RomFolder[] {
  const f = folders.find((x) => x.id === id);
  if (!f) throw new HttpError(404, 'Dossier inconnu');
  if (system !== 'auto' && !byId.has(system)) throw new HttpError(400, 'Système inconnu');
  f.system = system;
  writeJson('rom-folders.json', folders);
  rescan();
  return listFolders();
}

export function removeFolder(id: string): RomFolder[] {
  watchers.get(id)?.close();
  watchers.delete(id);
  folders = folders.filter((f) => f.id !== id);
  writeJson('rom-folders.json', folders);
  rescan();
  return listFolders();
}

/** Navigateur de dossiers pour choisir un dossier à la manette. */
export function browse(dir?: string): { path: string; parent: string | null; dirs: string[] } {
  const roots = process.platform === 'win32' ? [] : ['/'];
  const p = path.resolve(dir || (process.platform === 'win32' ? ROMS_DIR : '/run/media'));
  let dirs: string[] = [];
  try {
    dirs = fs
      .readdirSync(p, { withFileTypes: true })
      .filter((e) => e.isDirectory() && !e.name.startsWith('.') && !e.name.startsWith('$'))
      .map((e) => e.name)
      .sort((a, b) => a.localeCompare(b));
  } catch {
    /* illisible */
  }
  const parent = path.dirname(p) === p || roots.includes(p) ? null : path.dirname(p);
  return { path: p, parent, dirs };
}

// ---------------------------------------------------------------- Systèmes et cœurs

function corePath(core: string): string | null {
  for (const d of CORE_DIRS) {
    const f = path.join(d, `${core}_libretro.so`);
    if (fs.existsSync(f)) return f;
  }
  return null;
}

function coreInstalled(s: SystemDef) {
  if (s.standalone) return standalone.isInstalled(s.standalone);
  return MOCK ? mockCores.has(s.core) : corePath(s.core) !== null;
}

export function systems(): EmuSystem[] {
  const counts = new Map<string, number>();
  for (const g of roms.values()) counts.set(g.system!, (counts.get(g.system!) ?? 0) + 1);
  return SYSTEMS.map((s) => ({
    id: s.id,
    name: s.name,
    short: s.short,
    maker: s.maker,
    extensions: s.extensions,
    core: s.core,
    corePackage: s.corePackage,
    coreInstalled: coreInstalled(s),
    standalone: s.standalone ? { name: standalone.STANDALONE[s.standalone].name, version: standalone.installedVersion(s.standalone) } : undefined,
    bios: s.bios?.map((file) => ({ file, present: fs.existsSync(path.join(BIOS_DIR, file)) })),
    romCount: counts.get(s.id) ?? 0,
  }));
}

export async function installCore(systemId: string): Promise<void> {
  const sys = byId.get(systemId);
  if (!sys) throw new HttpError(404, 'Système inconnu');
  if (sys.standalone) return standalone.install(sys.standalone);
  if (MOCK) {
    await sleep(2000);
    mockCores.add(sys.core);
    writeJson('mock-cores.json', [...mockCores]);
    return;
  }
  // retroarch est installé avec la distribution ; on n'ajoute que le cœur.
  await pacmanInstall([sys.corePackage], 10 * 60_000);
}

// ---------------------------------------------------------------- Jeux

export function games(): Game[] {
  return [...roms.values()];
}

export function launchRom(id: string): { simulated: boolean } {
  const g = roms.get(id);
  if (!g) throw new HttpError(404, 'ROM introuvable');
  const sys = byId.get(g.system!)!;
  stats[id] = { playtimeMinutes: stats[id]?.playtimeMinutes ?? 0, lastPlayed: Date.now() };
  writeJson('rom-stats.json', stats);
  g.lastPlayed = Date.now();
  if (sys.standalone) {
    const child = standalone.launch(sys.standalone, g.path!);
    if (child) track(id, child);
    return { simulated: child === null };
  }
  if (MOCK) {
    console.log(`[roms] simulation : retroarch -L ${sys.core} "${g.path}"`);
    return { simulated: true };
  }
  const core = corePath(sys.core);
  if (!core) throw new HttpError(409, `Émulateur ${sys.short} non installé`);
  const args = ['-L', core, g.path!, '--fullscreen'];
  if (fs.existsSync(RETROARCH_CFG)) args.push('--appendconfig', RETROARCH_CFG);
  const child = launchDetached('retroarch', args);
  track(id, child);
  return { simulated: false };
}
