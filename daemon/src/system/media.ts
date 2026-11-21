import fs from 'node:fs';
import path from 'node:path';
import { MOCK, SHARE_DIR } from '../config.js';
import { HttpError, run, runRoot } from '../util.js';

// Son (PipeWire / wpctl), captures d'écran (grim sous cage, gamescope sinon), fuseau horaire (timedatectl).

let mockVolume = { volume: 1, muted: false };

export async function getVolume(): Promise<{ volume: number; muted: boolean }> {
  if (MOCK) return mockVolume;
  const out = await run('wpctl', ['get-volume', '@DEFAULT_AUDIO_SINK@']);
  const m = out.match(/Volume:\s*([\d.]+)/);
  return { volume: m ? Number(m[1]) : 1, muted: out.includes('MUTED') };
}

export async function setVolume(v: number): Promise<{ volume: number; muted: boolean }> {
  const vol = Math.max(0, Math.min(1.5, v));
  if (MOCK) {
    mockVolume = { volume: vol, muted: vol === 0 };
    return mockVolume;
  }
  await run('wpctl', ['set-volume', '@DEFAULT_AUDIO_SINK@', vol.toFixed(2)]);
  await run('wpctl', ['set-mute', '@DEFAULT_AUDIO_SINK@', vol === 0 ? '1' : '0']);
  return getVolume();
}

export const CAPTURES = path.join(SHARE_DIR, 'files', 'captures');

/** Capture de l'écran entier ; le fichier est accessible par FTP (files/captures). */
export async function screenshot(): Promise<{ path: string; name: string }> {
  if (MOCK) throw new HttpError(409, 'Capture disponible sur la console (Linux)');
  fs.mkdirSync(CAPTURES, { recursive: true });
  const stamp = new Date().toISOString().slice(0, 19).replace(/[:T]/g, '-');
  const name = `capture-${stamp}.png`;
  const file = path.join(CAPTURES, name);
  if (process.env.WAYLAND_DISPLAY) {
    await run('grim', [file], 15_000);
  } else {
    // Session gamescope : capture via son outil de contrôle.
    await run('gamescopectl', ['screenshot', file], 15_000);
  }
  if (!fs.existsSync(file)) throw new HttpError(500, 'La capture a échoué');
  return { path: file, name };
}

export async function setTimezone(tz: string): Promise<void> {
  if (MOCK) return;
  if (!/^[A-Za-z_]+(\/[A-Za-z_+-]+)*$/.test(tz) || !fs.existsSync(`/usr/share/zoneinfo/${tz}`)) throw new HttpError(400, 'Fuseau horaire inconnu');
  await runRoot('timedatectl', ['set-timezone', tz]);
}
