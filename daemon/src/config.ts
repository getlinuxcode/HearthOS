import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import type { Mode } from './types.js';

export const BRAND = 'Hearth';

export const PORT = Number(process.env.HEARTH_PORT ?? 7300);

function detectMode(): Mode {
  const env = process.env.HEARTH_MODE;
  if (env === 'dev' || env === 'live' || env === 'installed') return env;
  if (process.platform !== 'linux') return 'dev';
  return fs.existsSync('/run/archiso') ? 'live' : 'installed';
}

export const MODE: Mode = detectMode();

/** Mock = on simule tout ce qui modifie le système (disques, réseau, alimentation). */
export const MOCK = process.env.HEARTH_MOCK === '1' || process.platform !== 'linux';

export const DATA_DIR =
  process.env.HEARTH_DATA ??
  (process.platform === 'win32'
    ? path.join(process.env.APPDATA ?? os.homedir(), 'hearth')
    : path.join(os.homedir(), '.local/share/hearth'));

/** Racine partagée par FTP : roms/, bios/, files/ */
export const SHARE_DIR = path.join(DATA_DIR, 'share');
export const ROMS_DIR = path.join(SHARE_DIR, 'roms');
export const BIOS_DIR = path.join(SHARE_DIR, 'bios');

for (const d of [DATA_DIR, SHARE_DIR, ROMS_DIR, BIOS_DIR, path.join(SHARE_DIR, 'files')]) {
  fs.mkdirSync(d, { recursive: true });
}

const here = path.dirname(fileURLToPath(import.meta.url));

/** Version de l'application : fichier VERSION à la racine du paquet (dépôt, /opt/hearth ou release installée). */
export const APP_ROOT = path.resolve(here, '../..');
export const VERSION = (() => {
  try {
    return fs.readFileSync(path.join(APP_ROOT, 'VERSION'), 'utf8').trim();
  } catch {
    return '0.0.0-dev';
  }
})();

/** Canal de mises à jour : manifeste publié dans les releases GitHub du projet. */
export const UPDATE_URL =
  process.env.HEARTH_UPDATE_URL ?? 'https://github.com/getlinuxcode/HearthOS/releases/latest/download/manifest.json';
export const STATIC_DIR = process.env.HEARTH_STATIC ?? path.resolve(here, '../../shell/dist');
