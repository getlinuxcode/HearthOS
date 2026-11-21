import { MOCK } from '../config.js';
import type { NetworkStatus, WifiNetwork } from '../types.js';
import { HttpError, lanAddresses, run, sleep } from '../util.js';

/** nmcli -t échappe ':' et '\' avec un antislash. */
function splitNm(line: string): string[] {
  const out: string[] = [];
  let cur = '';
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (c === '\\' && i + 1 < line.length) cur += line[++i];
    else if (c === ':') {
      out.push(cur);
      cur = '';
    } else cur += c;
  }
  out.push(cur);
  return out;
}

async function hasInternet(): Promise<boolean> {
  try {
    const r = await fetch('https://ping.archlinux.org/nm-check.txt', { signal: AbortSignal.timeout(3000) });
    return r.ok;
  } catch {
    return false;
  }
}

// ---------- Mock (Windows / dev) ----------
const mockNetworks: WifiNetwork[] = [
  { ssid: 'Freebox-Salon', signal: 92, secure: true, active: false },
  { ssid: 'Livebox-4A2F', signal: 71, secure: true, active: false },
  { ssid: 'Wifi-Invites', signal: 55, secure: false, active: false },
  { ssid: 'Bbox-Voisin', signal: 30, secure: true, active: false },
];
let mockWifi: string | null = null;

export async function status(): Promise<NetworkStatus> {
  const addresses = lanAddresses();
  if (MOCK) {
    const internet = await hasInternet();
    if (mockWifi) return { connected: true, type: 'wifi', name: mockWifi, signal: 92, internet, addresses };
    return { connected: addresses.length > 0, type: 'ethernet', name: 'Ethernet', internet, addresses };
  }
  const out = await run('nmcli', ['-t', '-f', 'TYPE,STATE,CONNECTION', 'device']);
  const devs = out.split('\n').filter(Boolean).map(splitNm);
  const eth = devs.find((d) => d[0] === 'ethernet' && d[1] === 'connected');
  const wifi = devs.find((d) => d[0] === 'wifi' && d[1] === 'connected');
  if (eth) return { connected: true, type: 'ethernet', name: eth[2], internet: await hasInternet(), addresses };
  if (wifi) {
    const active = (await wifiList()).find((n) => n.active);
    return { connected: true, type: 'wifi', name: wifi[2], signal: active?.signal, internet: await hasInternet(), addresses };
  }
  return { connected: false, type: 'none', internet: false, addresses };
}

export async function wifiList(): Promise<WifiNetwork[]> {
  if (MOCK) {
    await sleep(600);
    return mockNetworks.map((n) => ({ ...n, active: n.ssid === mockWifi }));
  }
  const out = await run('nmcli', ['-t', '-f', 'IN-USE,SSID,SIGNAL,SECURITY', 'device', 'wifi', 'list', '--rescan', 'auto']);
  const bySsid = new Map<string, WifiNetwork>();
  for (const line of out.split('\n').filter(Boolean)) {
    const [inUse, ssid, signal, security] = splitNm(line);
    if (!ssid) continue;
    const net: WifiNetwork = { ssid, signal: Number(signal) || 0, secure: !!security && security !== '--', active: inUse === '*' };
    const prev = bySsid.get(ssid);
    if (!prev || net.signal > prev.signal || net.active) bySsid.set(ssid, { ...net, active: net.active || !!prev?.active });
  }
  return [...bySsid.values()].sort((a, b) => Number(b.active) - Number(a.active) || b.signal - a.signal);
}

export async function connectWifi(ssid: string, password?: string): Promise<void> {
  if (MOCK) {
    await sleep(1500);
    const net = mockNetworks.find((n) => n.ssid === ssid);
    if (!net) throw new HttpError(404, 'Réseau introuvable');
    if (net.secure && (!password || password.length < 8)) throw new HttpError(400, 'Mot de passe incorrect');
    mockWifi = ssid;
    return;
  }
  const args = ['device', 'wifi', 'connect', ssid];
  if (password) args.push('password', password);
  try {
    await run('nmcli', args, 45_000);
  } catch (e) {
    throw new HttpError(400, `Connexion impossible : ${(e as Error).message}`);
  }
}
