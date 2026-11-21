import type { ChildProcess } from 'node:child_process';
import { MOCK } from './config.js';
import { HttpError, run } from './util.js';

// Suivi du jeu en cours : savoir s'il tourne encore (retour automatique à l'interface quand on le quitte)
// et pouvoir le fermer depuis le menu du bouton PS.
//  - Steam : le client lance le jeu via « reaper SteamLaunch AppId=<id> » → on cherche ce processus.
//  - RetroArch / Epic (legendary) : processus lancé par nous, dans son propre groupe → on tue le groupe.

interface Running {
  id: string;
  appid?: number;
  child?: ChildProcess;
  since: number;
  seen: boolean;
}

let current: Running | null = null;

export function track(id: string, child?: ChildProcess, appid?: number) {
  current = { id, child, appid, since: Date.now(), seen: false };
}

async function steamPids(appid: number): Promise<number[]> {
  try {
    const out = await run('pgrep', ['-f', `AppId=${appid}( |$)`]);
    return out.split('\n').filter(Boolean).map(Number);
  } catch {
    return [];
  }
}

function alive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

export async function status(): Promise<{ running: boolean; id?: string; since?: number }> {
  if (!current) return { running: false };
  if (MOCK) return { running: true, id: current.id, since: current.since };
  let up = false;
  if (current.appid !== undefined) {
    up = (await steamPids(current.appid)).length > 0;
    // Steam peut mettre du temps à démarrer le jeu (mise à jour, synchronisation) : 3 min de grâce.
    if (!up && !current.seen && Date.now() - current.since < 180_000) return { running: true, id: current.id, since: current.since };
  } else if (current.child?.pid) {
    up = alive(current.child.pid);
  }
  if (up) current.seen = true;
  if (!up) {
    const id = current.id;
    current = null;
    return { running: false, id };
  }
  return { running: true, id: current.id, since: current.since };
}

export async function stop(): Promise<{ stopped: boolean }> {
  if (!current) return { stopped: false };
  if (MOCK) {
    current = null;
    return { stopped: true };
  }
  const c = current;
  const kill = (sig: NodeJS.Signals) => {
    if (c.child?.pid) {
      try {
        process.kill(-c.child.pid, sig); // tout le groupe (jeu + Wine/Proton)
      } catch {
        try {
          process.kill(c.child.pid, sig);
        } catch {
          /* déjà fini */
        }
      }
    }
  };
  if (c.appid !== undefined) {
    for (const pid of await steamPids(c.appid)) {
      try {
        process.kill(pid, 'SIGTERM');
      } catch {
        /* déjà fini */
      }
    }
  } else kill('SIGTERM');
  // Si le jeu ne se ferme pas dans les 5 secondes : arrêt forcé.
  setTimeout(async () => {
    if (c.appid !== undefined) for (const pid of await steamPids(c.appid)) try { process.kill(pid, 'SIGKILL'); } catch { /* fini */ }
    else kill('SIGKILL');
  }, 5000);
  current = null;
  return { stopped: true };
}

export function assertNone() {
  if (current && !MOCK) throw new HttpError(409, 'Un jeu est déjà en cours');
}
