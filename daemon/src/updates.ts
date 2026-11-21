import { spawn } from 'node:child_process';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { DATA_DIR, MOCK, MODE, UPDATE_URL, VERSION } from './config.js';
import { UPDATE_PUBLIC_KEY } from './update-key.js';
import type { UpdateStatus } from './types.js';
import { HttpError, readJson, run, writeJson } from './util.js';

// Mises à jour de l'application (interface + service) sans refaire d'ISO :
//  1. le mainteneur publie une release GitHub (scripts/publish-update.mjs) :
//     manifest.json + hearth-<version>.tar.gz, signés en Ed25519 ;
//  2. la console lit le manifeste, télécharge l'archive, vérifie SHA-256 + signature,
//     l'extrait dans releases/<version>/ et bascule le lien « current » (atomique) ;
//  3. on redémarre l'interface ; hearth-inner démarre la version « current ».
// Les deux versions précédentes sont gardées pour revenir en arrière.

const RELEASES = path.join(DATA_DIR, 'releases');
const CURRENT = path.join(DATA_DIR, 'current');
const KEEP = 3;

interface Manifest {
  version: string;
  url: string;
  sha256: string;
  size: number;
  signature: string;
  notes?: string;
  date?: string;
}

let status: UpdateStatus = {
  current: VERSION,
  channel: readJson<{ url?: string }>('update-channel.json', {}).url ?? UPDATE_URL,
  state: 'idle',
  progress: 0,
  systemUpdatable: MODE === 'installed' && !MOCK,
};

export function getStatus(): UpdateStatus {
  return { ...status, rollback: previousVersion() };
}

export function setChannel(url: string): UpdateStatus {
  if (!/^https?:\/\//.test(url)) throw new HttpError(400, 'Adresse invalide (http:// ou https://)');
  status.channel = url;
  writeJson('update-channel.json', { url });
  return getStatus();
}

/** Compare deux versions « 1.2.3 » (le suffixe -dev passe avant la version finale). */
export function newer(a: string, b: string): boolean {
  const parse = (v: string) => v.split('-')[0].split('.').map((n) => Number(n) || 0);
  const [x, y] = [parse(a), parse(b)];
  for (let i = 0; i < 3; i++) if ((x[i] ?? 0) !== (y[i] ?? 0)) return (x[i] ?? 0) > (y[i] ?? 0);
  return !a.includes('-') && b.includes('-');
}

export async function check(): Promise<UpdateStatus> {
  status = { ...status, state: 'checking', error: undefined };
  try {
    const r = await fetch(status.channel, { signal: AbortSignal.timeout(15_000), redirect: 'follow' });
    if (r.status === 404) throw new Error('Aucune version publiée sur ce canal');
    if (!r.ok) throw new Error(`Canal de mise à jour injoignable (${r.status})`);
    const m = (await r.json()) as Manifest;
    if (!m.version || !m.url || !m.sha256 || !m.signature) throw new Error('Manifeste incomplet');
    if (!verifySignature(m)) throw new Error('Signature du manifeste invalide : mise à jour refusée');
    status = {
      ...status,
      state: newer(m.version, VERSION) ? 'available' : 'uptodate',
      available: m.version,
      notes: m.notes,
      size: m.size,
      checkedAt: Date.now(),
    };
    manifest = m;
  } catch (e) {
    status = { ...status, state: 'error', error: (e as Error).message };
  }
  return getStatus();
}

let manifest: Manifest | null = null;

function signedPayload(m: Pick<Manifest, 'version' | 'sha256'>) {
  return Buffer.from(`hearth-update\n${m.version}\n${m.sha256}\n`);
}

function verifySignature(m: Manifest): boolean {
  try {
    return crypto.verify(null, signedPayload(m), crypto.createPublicKey(UPDATE_PUBLIC_KEY), Buffer.from(m.signature, 'base64'));
  } catch {
    return false;
  }
}

export async function install(): Promise<UpdateStatus> {
  if (status.state === 'downloading' || status.state === 'installing') throw new HttpError(409, 'Mise à jour déjà en cours');
  if (!manifest || status.state !== 'available') await check();
  if (!manifest || status.state !== 'available') throw new HttpError(409, status.error ?? 'Aucune mise à jour disponible');
  const m = manifest;
  status = { ...status, state: 'downloading', progress: 0, error: undefined };
  void (async () => {
    const tmp = path.join(DATA_DIR, `download-${m.version}.tar.gz`);
    try {
      // Téléchargement avec progression + empreinte
      const r = await fetch(m.url, { redirect: 'follow' });
      if (!r.ok || !r.body) throw new Error(`Téléchargement impossible (${r.status})`);
      const total = Number(r.headers.get('content-length')) || m.size || 0;
      const hash = crypto.createHash('sha256');
      const out = fs.createWriteStream(tmp);
      let got = 0;
      for await (const chunk of r.body as unknown as AsyncIterable<Uint8Array>) {
        hash.update(chunk);
        out.write(chunk);
        got += chunk.length;
        if (total) status.progress = Math.min(99, Math.round((got / total) * 100));
      }
      await new Promise((res) => out.end(res));
      if (hash.digest('hex') !== m.sha256) throw new Error('Archive corrompue (empreinte SHA-256 différente)');

      // Extraction dans releases/<version>/ puis bascule atomique du lien « current »
      status = { ...status, state: 'installing', progress: 100 };
      const dest = path.join(RELEASES, m.version);
      fs.rmSync(dest, { recursive: true, force: true });
      fs.mkdirSync(dest, { recursive: true });
      await run('tar', ['-xzf', tmp, '-C', dest], 120_000);
      if (!fs.existsSync(path.join(dest, 'VERSION'))) throw new Error('Archive invalide (VERSION manquant)');
      switchCurrent(dest);
      prune();
      status = { ...status, state: 'ready', installed: m.version };
    } catch (e) {
      status = { ...status, state: 'error', error: (e as Error).message };
    } finally {
      fs.rmSync(tmp, { force: true });
    }
  })();
  return getStatus();
}

function switchCurrent(target: string) {
  const tmpLink = CURRENT + '.new';
  fs.rmSync(tmpLink, { force: true, recursive: true });
  fs.symlinkSync(target, tmpLink, process.platform === 'win32' ? 'junction' : 'dir');
  fs.renameSync(tmpLink, CURRENT);
}

function installedVersions(): string[] {
  try {
    return fs.readdirSync(RELEASES).sort((a, b) => (newer(a, b) ? -1 : 1));
  } catch {
    return [];
  }
}

function previousVersion(): string | undefined {
  return installedVersions().find((v) => v !== VERSION && v !== status.installed && !newer(v, VERSION));
}

function prune() {
  for (const v of installedVersions().slice(KEEP)) fs.rmSync(path.join(RELEASES, v), { recursive: true, force: true });
}

/** Revient à la version précédente installée, ou à la version d'usine (/opt/hearth). */
export function rollback(): UpdateStatus {
  const prev = previousVersion();
  if (prev) switchCurrent(path.join(RELEASES, prev));
  else fs.rmSync(CURRENT, { force: true, recursive: true });
  status = { ...status, state: 'ready', installed: prev ?? 'version d’origine' };
  return getStatus();
}

// ------------------------------------------------------------------ Système (paquets Arch)

let systemLog: string[] = [];

export function systemUpdate(): UpdateStatus {
  if (!status.systemUpdatable) {
    throw new HttpError(409, MODE === 'live' ? 'Sur la clé USB, le système est en lecture seule : installez Hearth pour le mettre à jour.' : 'Indisponible en développement');
  }
  if (status.system === 'running') throw new HttpError(409, 'Mise à jour système déjà en cours');
  status = { ...status, system: 'running' };
  systemLog = [];
  // Instantané btrfs avant mise à jour (si snapper est configuré), puis pacman.
  const p = spawn('sudo', ['-n', 'sh', '-c', 'command -v snapper >/dev/null && snapper create -d "avant mise à jour Hearth"; pacman -Syu --noconfirm'], { stdio: ['ignore', 'pipe', 'pipe'] });
  const onData = (b: Buffer) => {
    systemLog.push(...b.toString().split('\n').filter(Boolean));
    systemLog = systemLog.slice(-200);
  };
  p.stdout.on('data', onData);
  p.stderr.on('data', onData);
  p.on('close', (code) => {
    status = { ...status, system: code === 0 ? 'done' : 'error', error: code === 0 ? undefined : systemLog.slice(-3).join(' ') };
  });
  return getStatus();
}

export function systemUpdateLog(): string[] {
  return systemLog;
}

/** Vérification automatique au démarrage puis toutes les 6 heures. */
export function init() {
  const tick = () => void check().catch(() => {});
  setTimeout(tick, 20_000);
  setInterval(tick, 6 * 3600_000);
}
