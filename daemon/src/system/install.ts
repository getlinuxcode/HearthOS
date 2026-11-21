import { MOCK } from '../config.js';
import type { InstallPlan, InstallProgress } from '../types.js';
import { HttpError, sleep } from '../util.js';
import { listDisks } from './disks.js';

const GB = 1024 ** 3;
export const MIN_SIZE_GB = 64;

let progress: InstallProgress = { state: 'idle', step: '', percent: 0, simulated: MOCK };

export function getProgress(): InstallProgress {
  return progress;
}

export async function validate(plan: InstallPlan): Promise<void> {
  const disk = (await listDisks()).find((d) => d.path === plan.disk);
  if (!disk) throw new HttpError(400, 'Disque introuvable');
  if (disk.isBootMedia) throw new HttpError(400, "Impossible d'installer sur le support de démarrage");
  if (plan.mode === 'erase') {
    if (disk.size < MIN_SIZE_GB * GB) throw new HttpError(400, 'Disque trop petit');
    return;
  }
  if (plan.sizeGB < MIN_SIZE_GB) throw new HttpError(400, `Taille minimale : ${MIN_SIZE_GB} Go`);
  const max = plan.mode === 'alongside' ? disk.shrinkable?.maxBytes ?? 0 : disk.freeSpace;
  if (plan.sizeGB * GB > max) throw new HttpError(400, 'Pas assez de place disponible');
}

const STEPS = [
  'Vérification du plan',
  'Redimensionnement de la partition Windows',
  'Création des partitions',
  'Formatage btrfs et sous-volumes',
  'Copie du système de base',
  'Installation du noyau linux-cachyos',
  'Pilotes graphiques (Mesa / NVIDIA)',
  'Steam, gamescope et Proton',
  'Chargeur de démarrage systemd-boot',
  'Finalisation',
];

export async function start(plan: InstallPlan): Promise<void> {
  if (progress.state === 'running') throw new HttpError(409, 'Installation déjà en cours');
  await validate(plan);
  if (!MOCK) {
    // Le vrai backend (archinstall + ntfsresize) n'est volontairement PAS branché tant que
    // les garde-fous (BitLocker, hibernation Windows, dry-run) ne sont pas écrits et testés.
    throw new HttpError(501, "L'installation réelle n'est pas encore activée dans cette version");
  }
  progress = { state: 'running', step: STEPS[0], percent: 0, simulated: true };
  void (async () => {
    const steps = plan.mode === 'alongside' ? STEPS : STEPS.filter((s) => !s.includes('Windows'));
    for (let i = 0; i < steps.length; i++) {
      progress = { ...progress, step: steps[i], percent: Math.round((i / steps.length) * 100) };
      await sleep(900 + Math.random() * 900);
    }
    progress = { state: 'done', step: 'Terminé', percent: 100, simulated: true };
  })();
}
