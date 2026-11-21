import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { MOCK, MODE, PORT, STATIC_DIR, VERSION } from './config.js';
import * as emu from './emulation/library.js';
import * as ftp from './ftp.js';
import { getSettings, updateSettings } from './settings.js';
import * as steam from './steam.js';
import { listDisks } from './system/disks.js';
import * as install from './system/install.js';
import { displayInfo, power, systemInfo, type PowerAction } from './system/misc.js';
import * as net from './system/network.js';
import type { Game, Library } from './types.js';
import { HttpError } from './util.js';
import QRCode from 'qrcode';

type Ctx = { params: Record<string, string>; query: URLSearchParams; body: any };
type Handler = (ctx: Ctx) => unknown | Promise<unknown>;

const routes: { method: string; re: RegExp; keys: string[]; h: Handler }[] = [];
function route(method: string, pattern: string, h: Handler) {
  const keys: string[] = [];
  const re = new RegExp('^/api' + pattern.replace(/:(\w+)/g, (_, k) => (keys.push(k), '([^/]+)')) + '$');
  routes.push({ method, re, keys, h });
}

// ------------------------------------------------------------------ Système
route('GET', '/system/info', () => systemInfo());
route('GET', '/settings', () => getSettings());
route('POST', '/settings', ({ body }) => updateSettings(body));
route('POST', '/power/:action', ({ params }) => power(params.action as PowerAction));
route('GET', '/display', () => displayInfo());
route('GET', '/qr', async ({ query }) => ({ svg: await QRCode.toString(query.get('text') ?? '', { type: 'svg', margin: 1 }) }));

// ------------------------------------------------------------------ Réseau
route('GET', '/network/status', () => net.status());
route('GET', '/network/wifi', () => net.wifiList());
route('POST', '/network/wifi/connect', async ({ body }) => {
  await net.connectWifi(String(body.ssid ?? ''), body.password ? String(body.password) : undefined);
  return net.status();
});

// ------------------------------------------------------------------ Installation
route('GET', '/disks', () => listDisks());
route('GET', '/install/progress', () => install.getProgress());
route('POST', '/install/start', async ({ body }) => {
  await install.start(body);
  return install.getProgress();
});

// ------------------------------------------------------------------ Steam
route('POST', '/steam/login/qr', () => steam.startQrLogin());
route('GET', '/steam/login/status', () => steam.loginStatus());
route('POST', '/steam/logout', () => (steam.logout(), { ok: true }));
route('GET', '/store/featured', () => steam.featured());
route('GET', '/store/search', ({ query }) => steam.search(query.get('q') ?? ''));
route('GET', '/store/app/:appid', ({ params }) => steam.appDetails(Number(params.appid)));
route('POST', '/store/app/:appid/open', ({ params }) => (steam.openStore(Number(params.appid)), { ok: true }));

// ------------------------------------------------------------------ Bibliothèque unifiée
route('GET', '/library', async (): Promise<Library> => {
  const s = await steam.steamGames();
  const games: Game[] = [...s.games, ...emu.games()].sort(
    (a, b) => b.lastPlayed - a.lastPlayed || Number(b.installed) - Number(a.installed) || a.name.localeCompare(b.name),
  );
  return { account: steam.account(), games, demo: s.demo };
});
route('POST', '/games/:id/launch', ({ params }) => {
  const [source, ref] = decodeURIComponent(params.id).split(/:(.*)/);
  if (source === 'steam') {
    steam.launch(Number(ref));
    return { simulated: false };
  }
  return emu.launchRom(decodeURIComponent(params.id));
});
route('POST', '/games/:id/install', ({ params }) => {
  const [, appid] = decodeURIComponent(params.id).split(':');
  steam.install(Number(appid));
  return { ok: true };
});

// ------------------------------------------------------------------ Émulation
route('GET', '/emu/systems', () => emu.systems());
route('POST', '/emu/systems/:id/install', async ({ params }) => {
  await emu.installCore(params.id);
  return emu.systems();
});
route('GET', '/emu/folders', () => emu.listFolders());
route('POST', '/emu/folders', ({ body }) => emu.addFolder(String(body.path ?? ''), String(body.system ?? 'auto')));
route('POST', '/emu/folders/:id', ({ params, body }) => emu.updateFolder(params.id, String(body.system ?? 'auto')));
route('POST', '/emu/folders/:id/remove', ({ params }) => emu.removeFolder(params.id));
route('POST', '/emu/rescan', () => (emu.rescan(), emu.listFolders()));
route('GET', '/fs/browse', ({ query }) => emu.browse(query.get('path') ?? undefined));

// ------------------------------------------------------------------ FTP
route('GET', '/ftp', () => ftp.status());
route('POST', '/ftp', ({ body }) => ftp.setEnabled(!!body.enabled));
route('POST', '/ftp/password', () => ftp.regeneratePassword());

// ------------------------------------------------------------------ HTTP
const MIME: Record<string, string> = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript',
  '.css': 'text/css',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.woff2': 'font/woff2',
  '.json': 'application/json',
};

function serveStatic(urlPath: string, res: http.ServerResponse) {
  if (!fs.existsSync(STATIC_DIR)) {
    res.writeHead(404).end('Shell non compilé (npm run build -w shell)');
    return;
  }
  let file = path.join(STATIC_DIR, path.normalize(decodeURIComponent(urlPath)).replace(/^([/\\])+/, ''));
  if (!file.startsWith(STATIC_DIR) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) file = path.join(STATIC_DIR, 'index.html');
  res.writeHead(200, { 'content-type': MIME[path.extname(file)] ?? 'application/octet-stream' });
  fs.createReadStream(file).pipe(res);
}

async function readBody(req: http.IncomingMessage): Promise<any> {
  const chunks: Buffer[] = [];
  for await (const c of req) chunks.push(c as Buffer);
  const raw = Buffer.concat(chunks).toString();
  return raw ? JSON.parse(raw) : {};
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url ?? '/', 'http://localhost');
  if (!url.pathname.startsWith('/api/')) return serveStatic(url.pathname, res);
  const r = routes.find((x) => x.method === req.method && x.re.test(url.pathname));
  if (!r) {
    res.writeHead(404, { 'content-type': 'application/json' }).end(JSON.stringify({ error: 'Route inconnue' }));
    return;
  }
  try {
    const m = url.pathname.match(r.re)!;
    const params = Object.fromEntries(r.keys.map((k, i) => [k, m[i + 1]]));
    const body = req.method === 'POST' ? await readBody(req) : {};
    const out = await r.h({ params, query: url.searchParams, body });
    res.writeHead(200, { 'content-type': 'application/json' }).end(JSON.stringify(out ?? null));
  } catch (e) {
    const status = e instanceof HttpError ? e.status : 500;
    if (status === 500) console.error(`[api] ${req.method} ${url.pathname}`, e);
    res.writeHead(status, { 'content-type': 'application/json' }).end(JSON.stringify({ error: (e as Error).message }));
  }
});

emu.init();
await ftp.init();
server.listen(PORT, '127.0.0.1', () => {
  console.log(`hearth-daemon ${VERSION} — mode ${MODE}${MOCK ? ' (mock système)' : ''} — http://127.0.0.1:${PORT}`);
});
