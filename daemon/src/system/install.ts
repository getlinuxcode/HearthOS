import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { APP_ROOT, MOCK, MODE } from '../config.js';
import { getSettings } from '../settings.js';
import type { InstallPlan, InstallProgress } from '../types.js';
import { HttpError, sleep } from '../util.js';
import { listDisks } from './disks.js';

// Installation sur disque : le plan est validé ici, puis /usr/local/bin/hearth-install
// (root, via sudo) fait le travail et publie sa progression (« ##PROGRESS 42 étape »).

const GB = 1024 ** 3;
export const MIN_SIZE_GB = 64;
const SCRIPT_ISO = '/usr/local/bin/hearth-install';
/** Version livrée par une mise à jour si présente (l'ISO n'a jamais besoin d'être refaite). */
const script = () => {
  const fromUpdate = path.join(APP_ROOT, 'system', 'hearth-install');
  return fs.existsSync(fromUpdate) ? fromUpdate : SCRIPT_ISO;
};

let progress: InstallProgress = { state: 'idle', step: '', percent: 0, simulated: MOCK };
let lastLines: string[] = [];

export function getProgress(): InstallProgress {
  return progress;
}

export function log(): string[] {
  return lastLines;
}

export async function validate(plan: InstallPlan): Promise<{ shrinkPartition?: string }> {
  const disk = (await listDisks()).find((d) => d.path === plan.disk);
  if (!disk) throw new HttpError(400, 'Disque introuvable');
  if (disk.isBootMedia) throw new HttpError(400, "Impossible d'installer sur le support de démarrage");
  switch (plan.mode) {
    case 'erase':
      if (disk.size < MIN_SIZE_GB * GB) throw new HttpError(400, `Disque trop petit (minimum ${MIN_SIZE_GB} Go)`);
      return {};
    case 'alongside': {
      if (disk.partitions.some((p) => p.bitlocker)) {
        throw new HttpError(400, 'Windows est chiffré par BitLocker : suspendez ou désactivez BitLocker dans Windows avant d’installer à côté.');
      }
      if (!disk.shrinkable) throw new HttpError(400, 'Aucune partition Windows réductible sur ce disque');
      if (plan.sizeGB < MIN_SIZE_GB) throw new HttpError(400, `Taille minimale : ${MIN_SIZE_GB} Go`);
      if (plan.sizeGB * GB > disk.shrinkable.maxBytes) throw new HttpError(400, 'Pas assez de place à prendre sur Windows');
      return { shrinkPartition: disk.shrinkable.partition };
    }
    case 'free':
      if (plan.sizeGB < MIN_SIZE_GB || disk.freeSpace < MIN_SIZE_GB * GB) throw new HttpError(400, `Il faut au moins ${MIN_SIZE_GB} Go d’espace libre`);
      return {};
    case 'manual': {
      const m = plan.manual;
      if (!m?.root) throw new HttpError(400, 'Choisissez la partition système');
      const parts = disk.partitions.map((p) => p.path);
      if (!parts.includes(m.root)) throw new HttpError(400, 'Partition système invalide');
      const efiNeeded = !MOCK && fs.existsSync('/sys/firmware/efi');
      if (efiNeeded && !m.efi) throw new HttpError(400, 'Choisissez une partition EFI (démarrage UEFI)');
      if (m.efi && m.efi === m.root) throw new HttpError(400, 'La partition EFI doit être différente de la partition système');
      const root = disk.partitions.find((p) => p.path === m.root)!;
      if (root.size < 32 * GB) throw new HttpError(400, 'Partition système trop petite (minimum 32 Go)');
      return {};
    }
    default:
      throw new HttpError(400, 'Mode d’installation inconnu');
  }
}

export async function start(plan: InstallPlan): Promise<void> {
  if (progress.state === 'running') throw new HttpError(409, 'Installation déjà en cours');
  const extra = await validate(plan);
  lastLines = [];

  if (MOCK) {
    progress = { state: 'running', step: 'Vérification du plan', percent: 0, simulated: true };
    void simulate(plan);
    return;
  }
  if (MODE !== 'live') throw new HttpError(409, 'L’installation se lance depuis la clé USB Hearth');
  const SCRIPT = script();
  if (!fs.existsSync(SCRIPT)) throw new HttpError(500, 'Script d’installation absent');

  const s = getSettings();
  const planFile = path.join(os.tmpdir(), `hearth-plan-${Date.now()}.json`);
  fs.writeFileSync(planFile, JSON.stringify({ ...plan, ...extra, timezone: s.timezone, keymap: s.keyboardLayout === 'azerty' ? 'fr' : 'us' }));
  progress = { state: 'running', step: 'Démarrage', percent: 0, simulated: false };

  const p = spawn('sudo', ['-n', 'bash', SCRIPT, planFile], { stdio: ['ignore', 'pipe', 'pipe'] });
  let buf = '';
  const onOut = (b: Buffer) => {
    buf += b.toString();
    let i;
    while ((i = buf.indexOf('\n')) >= 0) {
      const line = buf.slice(0, i).trim();
      buf = buf.slice(i + 1);
      if (!line) continue;
      lastLines = [...lastLines, line].slice(-80);
      const m = line.match(/^##PROGRESS (\d+) (.*)$/);
      if (m) progress = { ...progress, percent: Number(m[1]), step: m[2] };
      const e = line.match(/^##ERROR (.*)$/);
      if (e) progress = { ...progress, state: 'error', error: e[1] };
      if (line === '##DONE') progress = { ...progress, state: 'done', percent: 100, step: 'Installation terminée' };
    }
  };
  p.stdout.on('data', onOut);
  p.stderr.on('data', (b: Buffer) => {
    lastLines = [...lastLines, ...b.toString().split('\n').filter(Boolean)].slice(-80);
  });
  p.on('close', (code) => {
    fs.rmSync(planFile, { force: true });
    if (progress.state === 'running') {
      progress = code === 0
        ? { ...progress, state: 'done', percent: 100, step: 'Installation terminée' }
        : { ...progress, state: 'error', error: lastLines.slice(-2).join(' ') || `Code ${code}` };
    }
  });
}

async function simulate(plan: InstallPlan) {
  const steps = [
    'Vérification du plan',
    ...(plan.mode === 'alongside' ? ['Vérification de Windows', 'Réduction de la partition Windows'] : []),
    ...(plan.mode === 'erase' ? ['Effacement du disque'] : []),
    ...(plan.mode === 'manual' ? [] : ['Création de la partition Hearth']),
    'Formatage (btrfs, compression zstd)',
    'Copie du système',
    'Noyau et microcode',
    'Configuration du système',
    'Reprise de vos comptes et réglages',
    'Initramfs',
    'Menu de démarrage GRUB',
    'Finalisation',
  ];
  for (let i = 0; i < steps.length; i++) {
    progress = { ...progress, step: steps[i], percent: Math.round((i / steps.length) * 100) };
    await sleep(800 + Math.random() * 700);
  }
  progress = { state: 'done', step: 'Installation terminée', percent: 100, simulated: true };
}
