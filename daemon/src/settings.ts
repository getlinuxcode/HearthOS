import fs from 'node:fs';
import path from 'node:path';
import { DATA_DIR } from './config.js';
import type { Settings } from './types.js';
import { readJson, writeJson } from './util.js';

export const DEFAULT_SETTINGS: Settings = {
  onboarded: false,
  uiScale: 1,
  sounds: true,
  timezone: 'Europe/Paris',
  clock24h: true,
  keyboardLayout: 'azerty',
  display: { width: 3840, height: 2160, refresh: 60, vrr: true, hdr: false, upscaler: 'off', fpsLimit: 0 },
  games: {},
};

let current: Settings = load();

function load(): Settings {
  const saved = readJson<Partial<Settings>>('settings.json', {});
  return {
    ...DEFAULT_SETTINGS,
    ...saved,
    display: { ...DEFAULT_SETTINGS.display, ...saved.display },
    games: { ...saved.games },
  };
}

export function getSettings(): Settings {
  return current;
}

export function updateSettings(patch: Partial<Settings>): Settings {
  current = {
    ...current,
    ...patch,
    display: { ...current.display, ...patch.display },
    games: { ...current.games, ...patch.games },
  };
  writeJson('settings.json', current);
  if (patch.display) writeDisplayEnv();
  return current;
}

/** Fichier lu par la session (os/airootfs/usr/local/bin/hearth-session) pour lancer gamescope. */
function writeDisplayEnv() {
  const d = current.display;
  const env = [
    `HEARTH_W=${d.width}`,
    `HEARTH_H=${d.height}`,
    `HEARTH_REFRESH=${d.refresh}`,
    `HEARTH_VRR=${d.vrr ? 1 : 0}`,
    `HEARTH_HDR=${d.hdr ? 1 : 0}`,
    `HEARTH_UPSCALER=${d.upscaler}`,
    `HEARTH_FPS_LIMIT=${d.fpsLimit}`,
    '',
  ].join('\n');
  fs.writeFileSync(path.join(DATA_DIR, 'display.env'), env);
}
