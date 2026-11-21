import crypto from 'node:crypto';
import fs from 'node:fs';
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import QRCode from 'qrcode';
import type { Game } from './types.js';
import { HttpError, lanAddresses, launchDetached, readJson, writeJson } from './util.js';

// Epic Games, pensé pour la manette :
//  - la TV affiche un QR code qui ouvre une petite page servie par la console sur le réseau local ;
//  - sur le téléphone : « Se connecter à Epic » puis on colle le code obtenu → la console reçoit le code
//    et l'échange contre des jetons (même client OAuth que le lanceur Epic / legendary) ;
//  - bibliothèque : services publics Epic (library + catalog) ; installation et lancement via legendary,
//    qui réutilise nos jetons (~/.config/legendary/user.json).

const CLIENT_ID = '34a02cf8f4414e29b15921876da36f9a';
const CLIENT_SECRET = 'daafbccc737745039dffe53d94fc76cf';
const OAUTH = 'https://account-public-service-prod03.ol.epicgames.com/account/api/oauth/token';
const LIBRARY = 'https://library-service.live.use1a.on.epicgames.com/library/api/public/items';
const CATALOG = 'https://catalog-public-service-prod06.ol.epicgames.com/catalog/api/shared/namespace';
export const LOGIN_URL =
  'https://www.epicgames.com/id/login?redirectUrl=' +
  encodeURIComponent(`https://www.epicgames.com/id/api/redirect?clientId=${CLIENT_ID}&responseType=code`);
const PAIR_PORT = Number(process.env.HEARTH_PAIR_PORT ?? 7301);

interface EpicAuth {
  access_token: string;
  refresh_token: string;
  expires_at: string;
  refresh_expires_at?: string;
  account_id: string;
  displayName: string;
  [k: string]: unknown;
}

export interface EpicLoginStatus {
  state: 'idle' | 'pending' | 'done' | 'error';
  name?: string;
  error?: string;
}

let auth: EpicAuth | null = readJson<EpicAuth | null>('epic-auth.json', null);
let login: { token: string; status: EpicLoginStatus; server: http.Server; timer: NodeJS.Timeout } | null = null;

export function account(): { name: string } | undefined {
  return auth ? { name: auth.displayName } : undefined;
}

// ------------------------------------------------------------------ OAuth

async function tokenRequest(body: Record<string, string>): Promise<EpicAuth> {
  const r = await fetch(OAUTH, {
    method: 'POST',
    headers: {
      Authorization: 'Basic ' + Buffer.from(`${CLIENT_ID}:${CLIENT_SECRET}`).toString('base64'),
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams({ ...body, token_type: 'eg1' }),
    signal: AbortSignal.timeout(15_000),
  });
  const j = (await r.json()) as EpicAuth & { errorMessage?: string };
  if (!r.ok) throw new Error(j.errorMessage ?? `Epic a refusé la connexion (${r.status})`);
  return j;
}

function saveAuth(a: EpicAuth) {
  auth = a;
  writeJson('epic-auth.json', a, true);
  // legendary lit le même format : il pourra installer / lancer sans nouvelle connexion.
  try {
    const dir = path.join(os.homedir(), '.config/legendary');
    fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(path.join(dir, 'user.json'), JSON.stringify(a, null, 2), { mode: 0o600 });
  } catch {
    /* pas bloquant */
  }
}

async function accessToken(): Promise<string> {
  if (!auth) throw new HttpError(401, 'Non connecté à Epic Games');
  if (new Date(auth.expires_at).getTime() > Date.now() + 60_000) return auth.access_token;
  saveAuth(await tokenRequest({ grant_type: 'refresh_token', refresh_token: auth.refresh_token }));
  return auth!.access_token;
}

/** Accepte le code seul, ou tout le JSON affiché par Epic après connexion. */
function extractCode(input: string): string | null {
  const m = input.match(/"authorizationCode"\s*:\s*"([0-9a-f]{32})"/i) ?? input.match(/\b([0-9a-f]{32})\b/i);
  return m ? m[1] : null;
}

export async function loginWithCode(input: string): Promise<string> {
  const code = extractCode(input);
  if (!code) throw new HttpError(400, 'Code Epic introuvable (32 caractères)');
  const a = await tokenRequest({ grant_type: 'authorization_code', code });
  saveAuth(a);
  return a.displayName;
}

export function logout() {
  auth = null;
  writeJson('epic-auth.json', null, true);
}

// ------------------------------------------------------------------ Appairage par téléphone

function page(token: string, state: 'form' | 'ok' | 'error', msg = ''): string {
  const body =
    state === 'ok'
      ? `<div class="ok">✓</div><h1>Connecté !</h1><p>${msg}</p><p class="dim">Vous pouvez fermer cette page, la console a pris le relais.</p>`
      : `<h1>Connecter Epic Games</h1>
        ${state === 'error' ? `<p class="err">${msg}</p>` : ''}
        <ol>
          <li><a class="btn" href="${LOGIN_URL}" target="_blank" rel="noopener">1 · Se connecter à Epic Games</a>
            <p class="dim">Après connexion, Epic affiche un texte contenant <b>authorizationCode</b> : copiez-le entièrement.</p></li>
          <li><form method="post" action="/epic/${token}">
            <textarea name="code" placeholder="Collez ici le texte ou le code" required></textarea>
            <button class="btn primary" type="submit">2 · Envoyer à la console</button></form></li>
        </ol>`;
  return `<!doctype html><html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Hearth · Epic Games</title><style>
body{margin:0;font-family:system-ui,sans-serif;background:#0b0e16;color:#eef1f8;padding:28px 20px;line-height:1.5}
h1{font-size:1.6rem;margin:0 0 18px}ol{padding-left:1.1rem}li{margin-bottom:26px}.dim{color:#98a1b8;font-size:.92rem}
.btn{display:block;text-align:center;padding:16px;border-radius:14px;background:#2a2f3c;color:#fff;text-decoration:none;font-weight:700;border:0;width:100%;font-size:1rem;box-shadow:inset 0 -4px 0 rgba(0,0,0,.35)}
.primary{background:#f2f4fa;color:#0b0e16}textarea{width:100%;box-sizing:border-box;min-height:110px;border-radius:12px;border:2px solid #7c9cff;background:#151a26;color:#fff;padding:12px;font-size:1rem;margin:10px 0}
.err{color:#ff7884}.ok{font-size:4rem;color:#3ddc97}</style></head><body>${body}</body></html>`;
}

export async function startLogin(): Promise<{ qrSvg: string; pairUrl: string }> {
  stopLogin();
  const ip = lanAddresses()[0];
  if (!ip) throw new HttpError(409, 'La console n’est pas connectée au réseau local');
  const token = crypto.randomBytes(12).toString('hex');
  const status: EpicLoginStatus = { state: 'pending' };
  const server = http.createServer(async (req, res) => {
    const url = new URL(req.url ?? '/', 'http://x');
    if (url.pathname !== `/epic/${token}`) {
      res.writeHead(404).end();
      return;
    }
    res.setHeader('content-type', 'text/html; charset=utf-8');
    if (req.method === 'POST') {
      let raw = '';
      for await (const c of req) raw += c;
      const code = new URLSearchParams(raw).get('code') ?? '';
      try {
        const name = await loginWithCode(code);
        status.state = 'done';
        status.name = name;
        res.end(page(token, 'ok', `Bienvenue ${name}. Votre bibliothèque Epic arrive sur la TV.`));
        setTimeout(stopLogin, 3000);
      } catch (e) {
        res.end(page(token, 'error', (e as Error).message));
      }
      return;
    }
    res.end(page(token, 'form'));
  });
  await new Promise<void>((resolve, reject) => server.listen(PAIR_PORT, '0.0.0.0', resolve).once('error', reject));
  const pairUrl = `http://${ip}:${PAIR_PORT}/epic/${token}`;
  login = { token, status, server, timer: setTimeout(stopLogin, 10 * 60_000) };
  const qrSvg = await QRCode.toString(pairUrl, { type: 'svg', margin: 1 });
  return { qrSvg, pairUrl };
}

export function loginStatus(): EpicLoginStatus {
  if (login) return login.status;
  return auth ? { state: 'done', name: auth.displayName } : { state: 'idle' };
}

function stopLogin() {
  if (!login) return;
  clearTimeout(login.timer);
  login.server.close();
  login = null;
}

// ------------------------------------------------------------------ Bibliothèque

interface LibItem {
  namespace: string;
  catalogItemId: string;
  appName: string;
  sandboxType?: string;
}

export async function games(): Promise<Game[]> {
  if (!auth) return [];
  try {
    const token = await accessToken();
    const items: LibItem[] = [];
    let cursor = '';
    do {
      const r = await fetch(`${LIBRARY}?includeMetadata=true${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ''}`, {
        headers: { Authorization: `bearer ${token}` },
        signal: AbortSignal.timeout(15_000),
      });
      if (!r.ok) throw new Error(`Epic library ${r.status}`);
      const j = (await r.json()) as { records?: LibItem[]; responseMetadata?: { nextCursor?: string } };
      items.push(...(j.records ?? []));
      cursor = j.responseMetadata?.nextCursor ?? '';
    } while (cursor);

    // Jeux uniquement (pas les assets Unreal ni les DLC), avec titre et jaquette verticale.
    const wanted = items.filter((i) => i.namespace !== 'ue' && i.sandboxType !== 'PRIVATE');
    const byNs = new Map<string, LibItem[]>();
    for (const i of wanted) byNs.set(i.namespace, [...(byNs.get(i.namespace) ?? []), i]);
    const installed = installedAppNames();
    const out: Game[] = [];
    for (const [ns, list] of byNs) {
      const ids = list.map((i) => `id=${i.catalogItemId}`).join('&');
      const r = await fetch(`${CATALOG}/${ns}/bulk/items?${ids}&includeDLCDetails=false&includeMainGameDetails=true&country=FR&locale=fr`, {
        headers: { Authorization: `bearer ${token}` },
        signal: AbortSignal.timeout(15_000),
      });
      if (!r.ok) continue;
      const cat = (await r.json()) as Record<string, { title: string; keyImages?: { type: string; url: string }[]; categories?: { path: string }[]; mainGameItem?: unknown }>;
      for (const i of list) {
        const c = cat[i.catalogItemId];
        if (!c || c.mainGameItem || c.categories?.some((x) => x.path === 'addons' || x.path.startsWith('digitalextras'))) continue;
        const img = (t: string) => c.keyImages?.find((k) => k.type === t)?.url;
        out.push({
          id: `epic:${i.appName}`,
          appName: i.appName,
          name: c.title,
          source: 'epic',
          installed: installed.has(i.appName),
          playtimeMinutes: 0,
          lastPlayed: 0,
          coverUrl: img('DieselGameBoxTall') ?? img('OfferImageTall') ?? img('Thumbnail') ?? img('DieselGameBox'),
        });
      }
    }
    writeJson('epic-library-cache.json', out);
    return out;
  } catch (e) {
    console.warn('[epic] bibliothèque hors-ligne :', (e as Error).message);
    return readJson<Game[]>('epic-library-cache.json', []);
  }
}

function installedAppNames(): Set<string> {
  try {
    const f = path.join(os.homedir(), '.config/legendary/installed.json');
    return new Set(Object.keys(JSON.parse(fs.readFileSync(f, 'utf8'))));
  } catch {
    return new Set();
  }
}

function legendary(): string {
  const bundled = '/opt/hearth/bin/legendary';
  return fs.existsSync(bundled) ? bundled : 'legendary';
}

export function launch(appName: string) {
  if (process.platform === 'win32') throw new HttpError(409, 'Lancement Epic disponible sur la console (Linux) uniquement');
  launchDetached(legendary(), ['launch', appName]);
}

export function install(appName: string) {
  if (process.platform === 'win32') throw new HttpError(409, 'Installation Epic disponible sur la console (Linux) uniquement');
  launchDetached(legendary(), ['install', appName, '-y', '--skip-sdl']);
}
