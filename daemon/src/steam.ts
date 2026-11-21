import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import QRCode from 'qrcode';
import { EAuthTokenPlatformType, LoginSession } from 'steam-session';
import type { AppDetails, Game, Library, SteamAccount, SteamLoginStatus, StoreItem, StoreSection } from './types.js';
import { HttpError, openUri, readJson, writeJson } from './util.js';

const COUNTRY = 'FR';
const LANG = 'french';

interface SteamAuth {
  refreshToken: string;
  accessToken?: string;
  account: SteamAccount;
}

let auth: SteamAuth | null = readJson<SteamAuth | null>('steam-auth.json', null);
let login: { session: LoginSession; status: SteamLoginStatus } | null = null;

// ---------------------------------------------------------------- Connexion QR

export async function startQrLogin(): Promise<{ qrSvg: string; challengeUrl: string }> {
  login?.session.cancelLoginAttempt();
  const session = new LoginSession(EAuthTokenPlatformType.WebBrowser);
  session.loginTimeout = 180_000;
  const res = await session.startWithQR();
  if (!res.qrChallengeUrl) throw new HttpError(502, 'Steam n’a pas renvoyé de QR code');
  const state = { session, status: { state: 'pending' } as SteamLoginStatus };
  login = state;

  session.on('remoteInteraction', () => {
    state.status = { state: 'scanned' };
  });
  session.on('authenticated', async () => {
    try {
      const steamId = session.steamID.getSteamID64();
      const account = await fetchProfile(steamId, session.accountName);
      auth = { refreshToken: session.refreshToken, accessToken: session.accessToken, account };
      writeJson('steam-auth.json', auth, true);
      state.status = { state: 'done', account };
    } catch (e) {
      state.status = { state: 'error', error: (e as Error).message };
    }
  });
  session.on('timeout', () => {
    state.status = { state: 'timeout' };
  });
  session.on('error', (err: Error) => {
    state.status = { state: 'error', error: err.message };
  });

  const qrSvg = await QRCode.toString(res.qrChallengeUrl, { type: 'svg', margin: 1 });
  return { qrSvg, challengeUrl: res.qrChallengeUrl };
}

export function loginStatus(): SteamLoginStatus {
  return login?.status ?? { state: auth ? 'done' : 'idle', account: auth?.account };
}

export function account(): SteamAccount | undefined {
  return auth?.account;
}

export function logout(): void {
  auth = null;
  login?.session.cancelLoginAttempt();
  login = null;
  writeJson('steam-auth.json', null, true);
}

async function fetchProfile(steamId: string, accountName: string): Promise<SteamAccount> {
  const account: SteamAccount = { steamId, accountName, personaName: accountName };
  try {
    const xml = await (await fetch(`https://steamcommunity.com/profiles/${steamId}?xml=1`, { signal: AbortSignal.timeout(5000) })).text();
    const name = xml.match(/<steamID><!\[CDATA\[(.*?)\]\]><\/steamID>/)?.[1];
    const avatar = xml.match(/<avatarFull><!\[CDATA\[(.*?)\]\]><\/avatarFull>/)?.[1];
    if (name) account.personaName = name;
    if (avatar) account.avatarUrl = avatar;
  } catch {
    /* profil indisponible : on garde le nom de compte */
  }
  return account;
}

function jwtExpiry(token: string): number {
  try {
    const payload = JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString());
    return (payload.exp ?? 0) * 1000;
  } catch {
    return 0;
  }
}

async function accessToken(): Promise<string> {
  if (!auth) throw new HttpError(401, 'Non connecté à Steam');
  if (auth.accessToken && jwtExpiry(auth.accessToken) > Date.now() + 60_000) return auth.accessToken;
  const s = new LoginSession(EAuthTokenPlatformType.WebBrowser);
  s.refreshToken = auth.refreshToken;
  await s.refreshAccessToken();
  auth.accessToken = s.accessToken;
  writeJson('steam-auth.json', auth, true);
  return auth.accessToken;
}

// ---------------------------------------------------------------- Bibliothèque

const DEMO: [number, string][] = [
  [1091500, 'Cyberpunk 2077'],
  [1245620, 'ELDEN RING'],
  [1086940, "Baldur's Gate 3"],
  [1145360, 'Hades'],
  [367520, 'Hollow Knight'],
  [413150, 'Stardew Valley'],
  [292030, 'The Witcher 3: Wild Hunt'],
  [814380, 'Sekiro: Shadows Die Twice'],
  [730, 'Counter-Strike 2'],
  [570, 'Dota 2'],
];

function steamRoots(): string[] {
  const home = os.homedir();
  const candidates =
    process.platform === 'win32'
      ? ['C:/Program Files (x86)/Steam', 'C:/Program Files/Steam']
      : [path.join(home, '.local/share/Steam'), path.join(home, '.steam/steam')];
  return candidates.filter((p) => fs.existsSync(path.join(p, 'steamapps')));
}

/** Lit libraryfolders.vdf + appmanifest_*.acf pour savoir ce qui est installé. */
export function installedAppIds(): Set<number> {
  const ids = new Set<number>();
  const libs = new Set<string>();
  for (const root of steamRoots()) {
    libs.add(root);
    try {
      const vdf = fs.readFileSync(path.join(root, 'steamapps/libraryfolders.vdf'), 'utf8');
      for (const m of vdf.matchAll(/"path"\s+"([^"]+)"/g)) libs.add(m[1].replace(/\\\\/g, '/'));
    } catch {
      /* pas de vdf */
    }
  }
  for (const lib of libs) {
    try {
      for (const f of fs.readdirSync(path.join(lib, 'steamapps'))) {
        const m = f.match(/^appmanifest_(\d+)\.acf$/);
        if (m) ids.add(Number(m[1]));
      }
    } catch {
      /* bibliothèque absente (disque débranché) */
    }
  }
  return ids;
}

export async function steamGames(): Promise<{ games: Game[]; demo: boolean }> {
  const installed = installedAppIds();
  const mk = (appid: number, name: string, extra: Partial<Game> = {}): Game => ({
    id: `steam:${appid}`,
    appid,
    name,
    source: 'steam',
    installed: installed.has(appid),
    playtimeMinutes: 0,
    lastPlayed: 0,
    ...extra,
  });

  if (!auth) return { games: DEMO.map(([id, name]) => mk(id, name, { demo: true })), demo: true };

  try {
    const token = await accessToken();
    const url =
      `https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/?access_token=${encodeURIComponent(token)}` +
      `&steamid=${auth.account.steamId}&include_appinfo=true&include_played_free_games=true`;
    const r = await fetch(url, { signal: AbortSignal.timeout(10_000) });
    if (!r.ok) throw new Error(`Steam API ${r.status}`);
    const j = (await r.json()) as { response?: { games?: { appid: number; name: string; playtime_forever: number; rtime_last_played?: number }[] } };
    const games = (j.response?.games ?? []).map((g) =>
      mk(g.appid, g.name, { playtimeMinutes: g.playtime_forever, lastPlayed: (g.rtime_last_played ?? 0) * 1000 }),
    );
    writeJson('steam-library-cache.json', games);
    return { games, demo: false };
  } catch (e) {
    console.warn('[steam] bibliothèque hors-ligne :', (e as Error).message);
    const cached = readJson<Game[]>('steam-library-cache.json', []);
    return { games: cached.map((g) => ({ ...g, installed: installed.has(g.appid!) })), demo: false };
  }
}

export function launch(appid: number) {
  openUri(`steam://rungameid/${appid}`);
}
export function install(appid: number) {
  openUri(`steam://install/${appid}`);
}
export function openStore(appid: number) {
  openUri(`steam://store/${appid}`);
}

// ---------------------------------------------------------------- Boutique

const cache = new Map<string, { at: number; data: unknown }>();
async function cachedJson<T>(url: string, ttlMs = 10 * 60_000): Promise<T> {
  const hit = cache.get(url);
  if (hit && Date.now() - hit.at < ttlMs) return hit.data as T;
  const r = await fetch(url, { signal: AbortSignal.timeout(10_000), headers: { 'Accept-Language': 'fr-FR' } });
  if (!r.ok) throw new HttpError(502, `Boutique Steam indisponible (${r.status})`);
  const data = (await r.json()) as T;
  cache.set(url, { at: Date.now(), data });
  return data;
}

export const headerImage = (id: number) => `https://cdn.cloudflare.steamstatic.com/steam/apps/${id}/header.jpg`;

interface FeaturedItem {
  id: number;
  type: number;
  name: string;
  discount_percent: number;
  original_price: number | null;
  final_price: number;
  currency: string;
  header_image: string;
}

export async function featured(): Promise<StoreSection[]> {
  const j = await cachedJson<Record<string, { name?: string; items?: FeaturedItem[] }>>(
    `https://store.steampowered.com/api/featuredcategories?cc=${COUNTRY}&l=${LANG}`,
  );
  const sections: [string, string][] = [
    ['specials', 'Promotions'],
    ['top_sellers', 'Meilleures ventes'],
    ['new_releases', 'Nouveautés'],
    ['coming_soon', 'Bientôt disponibles'],
  ];
  return sections
    .map(([id, title]) => {
      const seen = new Set<number>();
      const items: StoreItem[] = (j[id]?.items ?? [])
        .filter((i) => i.type === 0 && !seen.has(i.id) && seen.add(i.id))
        .map((i) => ({
          appid: i.id,
          name: i.name,
          image: i.header_image || headerImage(i.id),
          priceFinal: i.final_price,
          priceInitial: i.original_price ?? undefined,
          discount: i.discount_percent,
          currency: i.currency,
        }));
      return { id, title, items };
    })
    .filter((s) => s.items.length);
}

export async function search(term: string): Promise<StoreItem[]> {
  const j = await cachedJson<{ items?: { id: number; name: string; price?: { currency: string; initial: number; final: number } }[] }>(
    `https://store.steampowered.com/api/storesearch/?term=${encodeURIComponent(term)}&l=${LANG}&cc=${COUNTRY}`,
    60_000,
  );
  return (j.items ?? []).map((i) => ({
    appid: i.id,
    name: i.name,
    image: headerImage(i.id),
    priceFinal: i.price?.final,
    priceInitial: i.price?.initial,
    discount: i.price && i.price.initial ? Math.round((1 - i.price.final / i.price.initial) * 100) : 0,
    currency: i.price?.currency,
  }));
}

export async function appDetails(appid: number): Promise<AppDetails> {
  const j = await cachedJson<Record<string, { success: boolean; data?: any }>>(
    `https://store.steampowered.com/api/appdetails?appids=${appid}&l=${LANG}&cc=${COUNTRY}`,
    60 * 60_000,
  );
  const d = j[appid]?.data;
  if (!j[appid]?.success || !d) throw new HttpError(404, 'Jeu introuvable sur la boutique');
  const strip = (s: string) => s.replace(/<[^>]+>/g, '').replace(/&quot;/g, '"').replace(/&amp;/g, '&').replace(/&#39;/g, "'").trim();
  return {
    appid,
    name: d.name,
    description: strip(d.short_description ?? ''),
    headerImage: d.header_image ?? headerImage(appid),
    developers: d.developers ?? [],
    genres: (d.genres ?? []).map((g: { description: string }) => g.description),
    releaseDate: d.release_date?.date,
    price: d.is_free ? 'Gratuit' : d.price_overview?.final_formatted,
    isFree: !!d.is_free,
    screenshots: (d.screenshots ?? []).slice(0, 8).map((s: { path_full: string }) => s.path_full),
    metacritic: d.metacritic?.score,
  };
}
