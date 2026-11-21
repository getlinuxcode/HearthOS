import { execFile, spawn, type ChildProcess } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { DATA_DIR } from './config.js';

export class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

/** Exécute une commande sans shell (pas d'injection possible). */
export function run(cmd: string, args: string[], timeoutMs = 20_000): Promise<string> {
  return new Promise((resolve, reject) => {
    execFile(cmd, args, { timeout: timeoutMs, maxBuffer: 16 * 1024 * 1024 }, (err, stdout, stderr) => {
      if (err) reject(new Error(`${cmd} ${args.join(' ')}: ${stderr || err.message}`.trim()));
      else resolve(stdout);
    });
  });
}

/** Commande nécessitant root : sudo non interactif si on n'est pas root. */
export function runRoot(cmd: string, args: string[], timeoutMs?: number): Promise<string> {
  if (process.getuid?.() === 0) return run(cmd, args, timeoutMs);
  return run('sudo', ['-n', cmd, ...args], timeoutMs);
}

/** Lance un processus détaché (jeu, Steam, RetroArch). */
export function launchDetached(cmd: string, args: string[], env?: Record<string, string>): ChildProcess {
  const child = spawn(cmd, args, { detached: true, stdio: 'ignore', env: env ? { ...process.env, ...env } : process.env });
  child.on('error', (e) => console.error(`[launch] ${cmd}:`, e.message));
  child.unref();
  return child;
}

export function openUri(uri: string): void {
  if (process.platform === 'win32') launchDetached('explorer.exe', [uri]);
  else if (uri.startsWith('steam://')) launchDetached('steam', [uri]);
  else launchDetached('xdg-open', [uri]);
}

export function readJson<T>(name: string, fallback: T): T {
  try {
    return JSON.parse(fs.readFileSync(path.join(DATA_DIR, name), 'utf8')) as T;
  } catch {
    return structuredClone(fallback);
  }
}

export function writeJson(name: string, data: unknown, secret = false): void {
  const file = path.join(DATA_DIR, name);
  fs.writeFileSync(file + '.tmp', JSON.stringify(data, null, 2), { mode: secret ? 0o600 : 0o644 });
  fs.renameSync(file + '.tmp', file);
}

export function lanAddresses(): string[] {
  const out: string[] = [];
  for (const list of Object.values(os.networkInterfaces())) {
    for (const a of list ?? []) {
      if (a.family === 'IPv4' && !a.internal) out.push(a.address);
    }
  }
  return out;
}

export function sleep(ms: number) {
  return new Promise((r) => setTimeout(r, ms));
}
