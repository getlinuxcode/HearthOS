import fs from 'node:fs';
import path from 'node:path';
import type { DisplayMode } from '../types.js';

// Modes réellement supportés par l'écran, lus dans son EDID (/sys/class/drm/*/edid) :
// descripteurs détaillés (bloc de base et extension CTA-861) + codes VIC des modes TV (4K120…).

const VIC: Record<number, [number, number, number]> = {
  1: [640, 480, 60], 4: [1280, 720, 60], 16: [1920, 1080, 60], 19: [1280, 720, 50], 31: [1920, 1080, 50],
  32: [1920, 1080, 24], 33: [1920, 1080, 25], 34: [1920, 1080, 30], 47: [1280, 720, 120], 63: [1920, 1080, 120],
  64: [1920, 1080, 100], 93: [3840, 2160, 24], 94: [3840, 2160, 25], 95: [3840, 2160, 30], 96: [3840, 2160, 50],
  97: [3840, 2160, 60], 117: [3840, 2160, 100], 118: [3840, 2160, 120], 98: [4096, 2160, 24], 102: [4096, 2160, 60],
};

function dtd(b: Buffer, o: number): [number, number, number] | null {
  const clock = b.readUInt16LE(o) * 10_000;
  if (!clock) return null;
  const ha = b[o + 2] | ((b[o + 4] >> 4) << 8);
  const hb = b[o + 3] | ((b[o + 4] & 0xf) << 8);
  const va = b[o + 5] | ((b[o + 7] >> 4) << 8);
  const vb = b[o + 6] | ((b[o + 7] & 0xf) << 8);
  if (!ha || !va) return null;
  return [ha, va, Math.round(clock / ((ha + hb) * (va + vb)))];
}

export function parseEdid(b: Buffer): [number, number, number][] {
  const modes: [number, number, number][] = [];
  if (b.length < 128) return modes;
  for (const o of [54, 72, 90, 108]) {
    const m = dtd(b, o);
    if (m) modes.push(m);
  }
  for (let e = 128; e + 128 <= b.length; e += 128) {
    if (b[e] !== 0x02) continue; // extension CTA-861
    const dtdStart = b[e + 2];
    let i = e + 4;
    while (i < e + dtdStart) {
      const tag = b[i] >> 5;
      const len = b[i] & 0x1f;
      if (tag === 2) for (let k = 1; k <= len; k++) {
        const code = b[i + k] & 0x7f;
        const v = b[i + k] >= 129 && b[i + k] <= 192 ? b[i + k] & 0x7f : b[i + k];
        const m = VIC[v] ?? VIC[code];
        if (m) modes.push(m);
      }
      i += len + 1;
    }
    for (let o = e + dtdStart; o + 18 <= e + 127 && dtdStart; o += 18) {
      const m = dtd(b, o);
      if (m) modes.push(m);
    }
  }
  return modes;
}

/** Écran branché : nom du connecteur et modes groupés par résolution (fréquences décroissantes). */
export function connectedModes(): { output: string; modes: DisplayMode[] } | null {
  const base = '/sys/class/drm';
  let entries: string[] = [];
  try {
    entries = fs.readdirSync(base).filter((d) => /^card\d+-/.test(d));
  } catch {
    return null;
  }
  for (const d of entries) {
    try {
      if (fs.readFileSync(path.join(base, d, 'status'), 'utf8').trim() !== 'connected') continue;
      const raw = parseEdid(fs.readFileSync(path.join(base, d, 'edid')));
      // Repli : liste de résolutions du noyau (sans fréquence)
      if (!raw.length) {
        for (const l of fs.readFileSync(path.join(base, d, 'modes'), 'utf8').split('\n')) {
          const m = l.match(/^(\d+)x(\d+)/);
          if (m) raw.push([Number(m[1]), Number(m[2]), 60]);
        }
      }
      const by = new Map<string, Set<number>>();
      for (const [w, h, r] of raw) {
        if (w < 1024) continue;
        const k = `${w}x${h}`;
        if (!by.has(k)) by.set(k, new Set());
        by.get(k)!.add(r);
      }
      const modes: DisplayMode[] = [...by.entries()]
        .map(([k, rs]) => {
          const [w, h] = k.split('x').map(Number);
          return { width: w, height: h, refresh: [...rs].sort((a, c) => c - a) };
        })
        .sort((a, c) => c.width * c.height - a.width * a.height);
      if (modes.length) return { output: d.replace(/^card\d+-/, ''), modes };
    } catch {
      /* connecteur illisible */
    }
  }
  return null;
}
