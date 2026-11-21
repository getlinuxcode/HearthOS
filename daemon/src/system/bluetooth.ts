import { MOCK } from '../config.js';
import { HttpError, run, sleep } from '../util.js';

// Appairage Bluetooth réel (BlueZ via bluetoothctl) : recherche, appairage, confiance, connexion.

export interface BtDevice {
  mac: string;
  name: string;
  paired: boolean;
  connected: boolean;
}

export async function adapter(): Promise<{ present: boolean; powered: boolean }> {
  if (MOCK) return { present: false, powered: false };
  try {
    const out = await run('bluetoothctl', ['show'], 8000);
    if (/No default controller/i.test(out) || !out.includes('Controller')) return { present: false, powered: false };
    return { present: true, powered: /Powered:\s*yes/.test(out) };
  } catch {
    return { present: false, powered: false };
  }
}

async function info(mac: string): Promise<{ paired: boolean; connected: boolean }> {
  try {
    const out = await run('bluetoothctl', ['info', mac], 5000);
    return { paired: /Paired:\s*yes/.test(out), connected: /Connected:\s*yes/.test(out) };
  } catch {
    return { paired: false, connected: false };
  }
}

/** Recherche pendant `seconds` puis liste les appareils vus (les manettes en premier). */
export async function scan(seconds = 12): Promise<BtDevice[]> {
  const a = await adapter();
  if (!a.present) throw new HttpError(409, 'Aucun adaptateur Bluetooth détecté sur cette machine');
  if (!a.powered) await run('bluetoothctl', ['power', 'on'], 8000);
  await run('bluetoothctl', ['--timeout', String(seconds), 'scan', 'on'], (seconds + 5) * 1000).catch(() => '');
  const out = await run('bluetoothctl', ['devices'], 5000);
  const list: BtDevice[] = [];
  for (const line of out.split('\n')) {
    const m = line.match(/^Device ([0-9A-F:]{17}) (.+)$/i);
    if (!m || /^([0-9A-F]{2}-){5}[0-9A-F]{2}$/i.test(m[2])) continue; // appareils sans nom : ignorés
    list.push({ mac: m[1], name: m[2], ...(await info(m[1])) });
  }
  const pad = (n: string) => /controller|gamepad|wireless|dualsense|xbox|pro con|joy-con|8bitdo/i.test(n);
  return list.sort((x, y) => Number(pad(y.name)) - Number(pad(x.name)));
}

export async function pair(mac: string): Promise<BtDevice> {
  if (!/^[0-9A-F:]{17}$/i.test(mac)) throw new HttpError(400, 'Adresse invalide');
  if (MOCK) throw new HttpError(409, 'Bluetooth disponible sur la console (Linux)');
  const st = await info(mac);
  if (!st.paired) {
    try {
      await run('bluetoothctl', ['--timeout', '25', 'pair', mac], 30_000);
    } catch (e) {
      throw new HttpError(400, 'Appairage refusé : remettez la manette en mode appairage et réessayez');
    }
  }
  await run('bluetoothctl', ['trust', mac], 8000).catch(() => '');
  await run('bluetoothctl', ['--timeout', '15', 'connect', mac], 20_000).catch(() => '');
  await sleep(1500);
  const after = await info(mac);
  if (!after.paired) throw new HttpError(400, 'Appairage non confirmé');
  return { mac, name: '', ...after };
}
