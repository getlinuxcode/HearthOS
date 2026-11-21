import crypto from 'node:crypto';
import { FtpSrv } from 'ftp-srv';
import { SHARE_DIR } from './config.js';
import type { FtpStatus } from './types.js';
import { lanAddresses, readJson, writeJson } from './util.js';

// Serveur FTP du réseau local. Désactivé par défaut. FTP n'est pas chiffré :
// à n'utiliser que sur son réseau domestique (SFTP/Samba prévus plus tard).

const PORT = Number(process.env.HEARTH_FTP_PORT ?? 2121);
const USER = 'hearth';

interface FtpConf {
  enabled: boolean;
  password: string;
}

let conf = readJson<FtpConf>('ftp.json', { enabled: false, password: newPassword() });
let server: FtpSrv | null = null;
let lastError: string | undefined;

function newPassword() {
  // 8 caractères faciles à taper sur un PC (pas de 0/O/1/l)
  const alphabet = 'abcdefghjkmnpqrstuvwxyz23456789';
  return Array.from(crypto.randomBytes(8), (b) => alphabet[b % alphabet.length]).join('');
}

export function status(): FtpStatus {
  return {
    enabled: !!server,
    port: PORT,
    user: USER,
    password: conf.password,
    root: SHARE_DIR,
    addresses: lanAddresses(),
    error: lastError,
  };
}

async function startServer() {
  const pasvIp = lanAddresses()[0] ?? '127.0.0.1';
  const srv = new FtpSrv({
    url: `ftp://0.0.0.0:${PORT}`,
    pasv_url: pasvIp,
    pasv_min: 50000,
    pasv_max: 50100,
    anonymous: false,
    greeting: ['Hearth — dossiers partagés : roms/, bios/, files/'],
  });
  srv.on('login', ({ username, password }, resolve, reject) => {
    if (username === USER && password === conf.password) resolve({ root: SHARE_DIR });
    else reject(new Error('Identifiants invalides'));
  });
  srv.on('client-error', ({ error }) => console.warn('[ftp]', error?.message ?? error));
  await srv.listen();
  server = srv;
}

export async function setEnabled(enabled: boolean): Promise<FtpStatus> {
  lastError = undefined;
  if (enabled && !server) {
    try {
      await startServer();
    } catch (e) {
      lastError = (e as Error).message;
      server = null;
    }
  } else if (!enabled && server) {
    await server.close();
    server = null;
  }
  conf.enabled = !!server;
  writeJson('ftp.json', conf, true);
  return status();
}

export async function regeneratePassword(): Promise<FtpStatus> {
  conf = { ...conf, password: newPassword() };
  writeJson('ftp.json', conf, true);
  return status();
}

export async function init() {
  if (conf.enabled) await setEnabled(true);
}
