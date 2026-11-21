import type { Family } from '../input/controllers';

// Illustrations stylisées (dessins originaux) : une silhouette commune, déclinée
// par famille (couleurs, pavé tactile, disposition des sticks, symboles).
// Les boutons portent data-b = index du « standard mapping » pour l'écran de test.

const BODY =
  'M110 50 C150 40 250 40 290 50 C340 58 365 90 378 150 C392 210 380 245 350 245 C325 245 310 225 290 195 ' +
  'C280 182 265 178 250 178 L150 178 C135 178 120 182 110 195 C90 225 75 245 50 245 C20 245 8 210 22 150 ' +
  'C35 90 60 58 110 50 Z';

interface Theme {
  body: string;
  stroke: string;
  detail: string;
  center?: string;
  face: 'ps' | 'xbox' | 'nintendo' | 'plain';
  layout: 'ps' | 'xbox';
  touchpad?: boolean;
  light?: string;
  guide?: boolean;
}

const THEMES: Record<Family, Theme> = {
  ds4: { body: '#1c2234', stroke: '#3b4766', detail: '#0f131d', face: 'ps', layout: 'ps', touchpad: true, light: '#3b82f6' },
  dualsense: { body: '#eef1f6', stroke: '#c7cdd8', detail: '#1b1e27', center: '#1b1e27', face: 'ps', layout: 'ps', touchpad: true, light: '#6a95ff' },
  ds3: { body: '#16181e', stroke: '#363b48', detail: '#0b0d12', face: 'ps', layout: 'ps' },
  xbox: { body: '#23272e', stroke: '#3e454f', detail: '#111419', face: 'xbox', layout: 'xbox', guide: true },
  xbox360: { body: '#e8ebee', stroke: '#c2c8ce', detail: '#30353c', face: 'xbox', layout: 'xbox', guide: true },
  switch: { body: '#2a2d34', stroke: '#474c56', detail: '#14161b', face: 'nintendo', layout: 'xbox' },
  steam: { body: '#1f2a37', stroke: '#3c4b5d', detail: '#111821', face: 'xbox', layout: 'xbox' },
  generic: { body: '#2c303b', stroke: '#4b5162', detail: '#14171d', face: 'plain', layout: 'xbox' },
};

const POS = {
  ps: { dpad: [100, 105], ls: [155, 152], rs: [245, 152], select: [138, 66], start: [262, 66], home: [200, 140] },
  xbox: { dpad: [155, 152], ls: [100, 105], rs: [245, 152], select: [172, 104], start: [228, 104], home: [200, 72] },
} as const;

const FACE = [300, 105];
let uid = 0;

function faceSymbol(t: Theme, idx: number, x: number, y: number): string {
  if (t.face === 'ps') {
    const s = 5.5;
    switch (idx) {
      case 0: return `<path d="M${x - s} ${y - s}l${2 * s} ${2 * s}M${x + s} ${y - s}l${-2 * s} ${2 * s}" stroke="#8fb4ff" stroke-width="2.2" stroke-linecap="round"/>`;
      case 1: return `<circle cx="${x}" cy="${y}" r="${s}" fill="none" stroke="#ff7a7a" stroke-width="2.2"/>`;
      case 2: return `<rect x="${x - s}" y="${y - s}" width="${2 * s}" height="${2 * s}" fill="none" stroke="#f49bd6" stroke-width="2.2"/>`;
      default: return `<path d="M${x} ${y - s - 1}l${s + 1} ${2 * s}h${-2 * s - 2}z" fill="none" stroke="#45dcb4" stroke-width="2.2" stroke-linejoin="round"/>`;
    }
  }
  const labels = t.face === 'nintendo' ? ['B', 'A', 'Y', 'X'] : ['A', 'B', 'X', 'Y'];
  const colors = t.face === 'xbox' ? ['#4cc04c', '#ef4b4b', '#3d8cf5', '#f2c330'] : ['#e7eaf0', '#e7eaf0', '#e7eaf0', '#e7eaf0'];
  if (t.face === 'plain') return `<circle cx="${x}" cy="${y}" r="3" fill="#9aa1b2"/>`;
  return `<text x="${x}" y="${y + 4.5}" text-anchor="middle" font-size="13" font-weight="700" fill="${colors[idx]}" font-family="system-ui">${labels[idx]}</text>`;
}

export function controllerArt(family: Family, cls = ''): string {
  const t = THEMES[family];
  const p = POS[t.layout];
  const id = `ca${++uid}`;
  const [dx, dy] = p.dpad;
  const [fx, fy] = FACE;
  const faces: [number, number, number][] = [
    [0, fx, fy + 22],
    [1, fx + 22, fy],
    [2, fx - 22, fy],
    [3, fx, fy - 22],
  ];
  const stick = (c: readonly number[], b: number, side: string) =>
    `<circle cx="${c[0]}" cy="${c[1]}" r="23" fill="${t.detail}" opacity=".9"/>` +
    `<g data-stick="${side}" style="transform-origin:${c[0]}px ${c[1]}px"><circle class="btn" data-b="${b}" cx="${c[0]}" cy="${c[1]}" r="15.5" fill="#3a3f4b" stroke="${t.stroke}" stroke-width="1.5"/><circle cx="${c[0]}" cy="${c[1]}" r="9" fill="none" stroke="#5a606e" stroke-width="1"/></g>`;

  return `
<svg class="controller-art ${cls}" viewBox="0 0 400 260" xmlns="http://www.w3.org/2000/svg" data-family="${family}">
  <defs>
    <clipPath id="${id}"><path d="${BODY}"/></clipPath>
    <linearGradient id="${id}g" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#fff" stop-opacity=".16"/><stop offset=".6" stop-color="#fff" stop-opacity="0"/>
    </linearGradient>
  </defs>
  <rect class="btn" data-b="6" x="82" y="24" width="64" height="26" rx="12" fill="${t.detail}" stroke="${t.stroke}"/>
  <rect class="btn" data-b="7" x="254" y="24" width="64" height="26" rx="12" fill="${t.detail}" stroke="${t.stroke}"/>
  <rect class="btn" data-b="4" x="72" y="38" width="82" height="20" rx="9" fill="${t.body}" stroke="${t.stroke}" stroke-width="1.5"/>
  <rect class="btn" data-b="5" x="246" y="38" width="82" height="20" rx="9" fill="${t.body}" stroke="${t.stroke}" stroke-width="1.5"/>
  <path d="${BODY}" fill="${t.body}" stroke="${t.stroke}" stroke-width="2"/>
  ${t.center ? `<rect x="138" y="30" width="124" height="170" fill="${t.center}" clip-path="url(#${id})"/>` : ''}
  <path d="${BODY}" fill="url(#${id}g)"/>
  ${t.touchpad ? `<rect class="btn" data-b="17" x="150" y="52" width="100" height="58" rx="10" fill="${t.center ? '#eef1f6' : t.detail}" stroke="${t.stroke}" stroke-width="1.2"/>` : ''}
  ${t.light ? `<rect x="${t.center ? 150 : 165}" y="${t.center ? 112 : 46}" width="${t.center ? 100 : 70}" height="3" rx="1.5" fill="${t.light}" class="lightbar"/>` : ''}
  <g>
    <rect class="btn" data-b="12" x="${dx - 9}" y="${dy - 30}" width="18" height="22" rx="4" fill="${t.detail}"/>
    <rect class="btn" data-b="13" x="${dx - 9}" y="${dy + 8}" width="18" height="22" rx="4" fill="${t.detail}"/>
    <rect class="btn" data-b="14" x="${dx - 30}" y="${dy - 9}" width="22" height="18" rx="4" fill="${t.detail}"/>
    <rect class="btn" data-b="15" x="${dx + 8}" y="${dy - 9}" width="22" height="18" rx="4" fill="${t.detail}"/>
    <rect x="${dx - 9}" y="${dy - 9}" width="18" height="18" fill="${t.detail}"/>
  </g>
  ${faces.map(([i, x, y]) => `<circle class="btn" data-b="${i}" cx="${x}" cy="${y}" r="12" fill="${t.detail}"/>${faceSymbol(t, i, x, y)}`).join('')}
  ${stick(p.ls, 10, 'l')}
  ${stick(p.rs, 11, 'r')}
  <rect class="btn" data-b="8" x="${p.select[0] - 7}" y="${p.select[1] - 5}" width="14" height="10" rx="5" fill="${t.detail}"/>
  <rect class="btn" data-b="9" x="${p.start[0] - 7}" y="${p.start[1] - 5}" width="14" height="10" rx="5" fill="${t.detail}"/>
  <circle class="btn" data-b="16" cx="${p.home[0]}" cy="${p.home[1]}" r="${t.guide ? 13 : 9}" fill="${t.detail}" stroke="${t.guide ? '#9bd3a2' : t.stroke}" stroke-width="${t.guide ? 1.5 : 1}"/>
  ${family === 'generic' ? `<text x="200" y="104" text-anchor="middle" font-size="22" font-weight="700" fill="#6c7385" font-family="system-ui">?</text>` : ''}
</svg>`;
}

/** Met à jour l'illustration selon l'état réel de la manette (écran de test). */
export function updateArt(svg: SVGElement, gp: Gamepad) {
  svg.querySelectorAll<SVGElement>('[data-b]').forEach((el) => {
    const b = gp.buttons[Number(el.dataset.b)];
    el.classList.toggle('on', !!b && (b.pressed || b.value > 0.3));
  });
  const [lx = 0, ly = 0, rx = 0, ry = 0] = gp.axes;
  const l = svg.querySelector<SVGElement>('[data-stick="l"]');
  const r = svg.querySelector<SVGElement>('[data-stick="r"]');
  if (l) l.style.transform = `translate(${lx * 8}px, ${ly * 8}px)`;
  if (r) r.style.transform = `translate(${rx * 8}px, ${ry * 8}px)`;
}
