import fs from 'node:fs';
import os from 'node:os';
import { MOCK, MODE, VERSION } from '../config.js';
import type { DisplayInfo, SystemInfo } from '../types.js';
import { HttpError, run } from '../util.js';
import { listDisks } from './disks.js';
import { connectedModes } from './edid.js';

let gpuCache: string[] | null = null;

async function gpus(): Promise<string[]> {
  if (gpuCache) return gpuCache;
  try {
    if (process.platform === 'win32') {
      const out = await run('powershell', ['-NoProfile', '-Command', '(Get-CimInstance Win32_VideoController).Name']);
      gpuCache = out.split(/\r?\n/).map((s) => s.trim()).filter(Boolean);
    } else {
      const out = await run('lspci', []);
      gpuCache = out
        .split('\n')
        .filter((l) => /VGA compatible|3D controller|Display controller/.test(l))
        .map((l) => l.replace(/^.*?: /, ''));
    }
  } catch {
    gpuCache = [];
  }
  return gpuCache;
}

export async function systemInfo(): Promise<SystemInfo> {
  const disks = await listDisks().catch(() => []);
  return {
    mode: MODE,
    mock: MOCK,
    platform: process.platform,
    hostname: os.hostname(),
    kernel: os.release(),
    cpu: os.cpus()[0]?.model.trim() ?? 'inconnu',
    gpu: await gpus(),
    memoryGB: Math.round(os.totalmem() / 1024 ** 3),
    version: VERSION,
    windowsDetected: disks.some((d) => d.detectedOS.some((o) => o.startsWith('Windows'))),
  };
}

export function displayInfo(): DisplayInfo {
  if (!MOCK) {
    const real = connectedModes();
    if (real) return { output: real.output, modes: real.modes, simulated: false };
  }
  // Développement (Windows) : modes d'exemple.
  return {
    output: 'HDMI-A-1',
    simulated: true,
    modes: [
      { width: 3840, height: 2160, refresh: [120, 60, 30] },
      { width: 2560, height: 1440, refresh: [144, 120, 60] },
      { width: 1920, height: 1080, refresh: [144, 120, 60] },
      { width: 1280, height: 720, refresh: [60] },
    ],
  };
}

export type PowerAction = 'poweroff' | 'reboot' | 'suspend' | 'reboot-windows';

export async function power(action: PowerAction): Promise<{ simulated: boolean }> {
  if (MOCK) {
    console.log(`[power] simulation : ${action}`);
    return { simulated: true };
  }
  switch (action) {
    case 'poweroff':
    case 'reboot':
    case 'suspend':
      await run('systemctl', [action]);
      break;
    case 'reboot-windows': {
      // GRUB : on choisit l'entrée Windows pour le prochain démarrage seulement, puis on redémarre.
      const cfg = fs.existsSync('/boot/grub/grub.cfg') ? fs.readFileSync('/boot/grub/grub.cfg', 'utf8') : '';
      const entry = cfg.match(/menuentry '([^']*Windows[^']*)'/)?.[1];
      if (!entry) throw new HttpError(404, 'Windows introuvable dans le menu de démarrage');
      await run('sudo', ['-n', 'grub-reboot', entry]);
      await run('systemctl', ['reboot']);
      break;
    }
    default:
      throw new HttpError(400, 'Action inconnue');
  }
  return { simulated: false };
}
