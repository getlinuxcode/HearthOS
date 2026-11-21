import { glyphStyle, type Family, type GlyphStyle } from '../input/controllers';
import type { Action } from '../input/input';

// Glyphes de boutons dessinés en SVG (pas de logos de marque).

const PS_FACE: Record<string, { color: string; svg: string }> = {
  confirm: { color: '#8fb4ff', svg: '<path d="M7 7l10 10M17 7L7 17" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"/>' },
  back: { color: '#ff7a7a', svg: '<circle cx="12" cy="12" r="5.6" fill="none" stroke="currentColor" stroke-width="2.2"/>' },
  x: { color: '#f49bd6', svg: '<rect x="6.8" y="6.8" width="10.4" height="10.4" rx="1" fill="none" stroke="currentColor" stroke-width="2.2"/>' },
  y: { color: '#45dcb4', svg: '<path d="M12 6.2l6 10.3H6z" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linejoin="round"/>' },
};

const XBOX_FACE: Record<string, { label: string; color: string }> = {
  confirm: { label: 'A', color: '#4cc04c' },
  back: { label: 'B', color: '#ef4b4b' },
  x: { label: 'X', color: '#3d8cf5' },
  y: { label: 'Y', color: '#f2c330' },
};

// Nintendo : le bouton du bas (« confirm » positionnel) s'appelle B, celui de droite A.
const NINTENDO_FACE: Record<string, string> = { confirm: 'B', back: 'A', x: 'Y', y: 'X' };

const SHOULDERS: Record<GlyphStyle, Partial<Record<Action, string>>> = {
  ps: { lb: 'L1', rb: 'R1', lt: 'L2', rt: 'R2', l3: 'L3', r3: 'R3' },
  xbox: { lb: 'LB', rb: 'RB', lt: 'LT', rt: 'RT', l3: 'LS', r3: 'RS' },
  nintendo: { lb: 'L', rb: 'R', lt: 'ZL', rt: 'ZR', l3: 'L3', r3: 'R3' },
  generic: { lb: 'L1', rb: 'R1', lt: 'L2', rt: 'R2', l3: 'L3', r3: 'R3' },
  keyboard: { lb: 'Pg↑', rb: 'Pg↓', lt: '', rt: '', l3: '', r3: '' },
};

const KEYBOARD: Partial<Record<Action, string>> = {
  confirm: 'Entrée', back: 'Échap', x: 'X', y: 'Y', start: 'M', select: 'V', home: 'H',
  up: '↑', down: '↓', left: '←', right: '→',
};

const MENU_ICON = '<path d="M7 8h10M7 12h10M7 16h10" stroke="currentColor" stroke-width="2" stroke-linecap="round"/>';
const VIEW_ICON = '<rect x="6" y="7" width="8" height="7" rx="1.2" fill="none" stroke="currentColor" stroke-width="1.8"/><rect x="10" y="10" width="8" height="7" rx="1.2" fill="none" stroke="currentColor" stroke-width="1.8"/>';
const HOME_ICON = '<path d="M6 12l6-5.5 6 5.5M8 10.5V17h8v-6.5" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linejoin="round"/>';
const DPAD_ICON = '<path d="M10 5h4v5h5v4h-5v5h-4v-5H5v-4h5z" fill="currentColor" opacity=".9"/>';

function circle(inner: string, color = 'currentColor') {
  return `<span class="glyph" style="color:${color}"><svg viewBox="0 0 24 24">${inner}</svg></span>`;
}
function letter(l: string, color = '#e8ecf4') {
  return `<span class="glyph" style="color:${color}"><b>${l}</b></span>`;
}
function pill(label: string) {
  return `<span class="glyph glyph-pill">${label}</span>`;
}

export function glyph(action: Action, family: Family | 'keyboard'): string {
  const style = glyphStyle(family);
  if (style === 'keyboard') {
    const k = KEYBOARD[action] ?? SHOULDERS.keyboard[action] ?? action;
    return `<span class="glyph glyph-key">${k}</span>`;
  }
  if (action === 'confirm' || action === 'back' || action === 'x' || action === 'y') {
    if (style === 'ps') return circle(PS_FACE[action].svg, PS_FACE[action].color);
    if (style === 'xbox') return letter(XBOX_FACE[action].label, XBOX_FACE[action].color);
    if (style === 'nintendo') return letter(NINTENDO_FACE[action]);
    return letter(XBOX_FACE[action].label);
  }
  if (action === 'start') return circle(MENU_ICON, '#e8ecf4');
  if (action === 'select') return circle(VIEW_ICON, '#e8ecf4');
  if (action === 'home') return circle(HOME_ICON, '#e8ecf4');
  if (['up', 'down', 'left', 'right'].includes(action)) return circle(DPAD_ICON, '#e8ecf4');
  return pill(SHOULDERS[style][action] ?? action);
}

export interface Hint {
  action: Action | Action[];
  label: string;
}

export function hintsHtml(hints: Hint[], family: Family | 'keyboard'): string {
  return hints
    .map((h) => {
      const acts = Array.isArray(h.action) ? h.action : [h.action];
      return `<span class="hint">${acts.map((a) => glyph(a, family)).join('')}<span>${h.label}</span></span>`;
    })
    .join('');
}
