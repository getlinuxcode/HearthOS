import { sound } from './sound';

// Navigation spatiale : tout élément [data-focus] est atteignable aux flèches / D-pad.
// [data-focus-memory] sur un conteneur : on revient sur le dernier élément focalisé de ce conteneur.

export type Dir = 'up' | 'down' | 'left' | 'right';

let current: HTMLElement | null = null;

export function focusables(root: ParentNode): HTMLElement[] {
  return [...root.querySelectorAll<HTMLElement>('[data-focus]')].filter(
    (el) => !el.hasAttribute('disabled') && el.getClientRects().length > 0,
  );
}

export function getFocused(): HTMLElement | null {
  return current?.isConnected ? current : null;
}

export function setFocus(el: HTMLElement | null, opts: { silent?: boolean; instant?: boolean } = {}) {
  if (current === el) return;
  current?.classList.remove('focused');
  current = el;
  if (!el) return;
  el.classList.add('focused');
  const mem = el.closest<HTMLElement>('[data-focus-memory]');
  if (mem) (mem as any)._last = el;
  scrollToFocus(el, opts.instant);
  el.dispatchEvent(new CustomEvent('focusin-nav', { bubbles: true }));
  if (!opts.silent) sound.move();
}

export function focusFirst(root: ParentNode, opts?: { silent?: boolean }) {
  const el = root.querySelector<HTMLElement>('[data-autofocus]') ?? focusables(root)[0] ?? null;
  setFocus(el, { silent: true, instant: true, ...opts });
}

function scrollToFocus(el: HTMLElement, instant?: boolean) {
  const behavior: ScrollBehavior = instant ? 'auto' : 'smooth';
  const h = el.closest<HTMLElement>('.h-scroll');
  if (h) {
    const pad = parseFloat(getComputedStyle(h).paddingLeft) || 0;
    h.scrollTo({ left: Math.max(0, el.offsetLeft - pad), behavior });
  }
  const v = el.closest<HTMLElement>('.v-scroll');
  if (v) {
    const top = el.offsetTop - v.clientHeight * 0.3;
    const elRect = el.getBoundingClientRect();
    const vRect = v.getBoundingClientRect();
    if (elRect.top < vRect.top + 40 || elRect.bottom > vRect.bottom - 40) v.scrollTo({ top: Math.max(0, top), behavior });
  }
}

function overlap(a1: number, a2: number, b1: number, b2: number) {
  return Math.min(a2, b2) - Math.max(a1, b1) > 0;
}

export function move(dir: Dir, root: HTMLElement): boolean {
  const cur = getFocused();
  const list = focusables(root);
  if (!cur || !root.contains(cur)) {
    if (list[0]) setFocus(list[0]);
    return !!list[0];
  }
  const r = cur.getBoundingClientRect();
  const cx = r.left + r.width / 2;
  const cy = r.top + r.height / 2;
  let best: HTMLElement | null = null;
  let bestScore = Infinity;

  for (const el of list) {
    if (el === cur || el.contains(cur)) continue;
    const b = el.getBoundingClientRect();
    const bx = b.left + b.width / 2;
    const by = b.top + b.height / 2;
    let gap: number;
    let ortho: number;
    if (dir === 'right' || dir === 'left') {
      if (dir === 'right' ? bx <= cx + 2 : bx >= cx - 2) continue;
      gap = dir === 'right' ? b.left - r.right : r.left - b.right;
      ortho = overlap(r.top, r.bottom, b.top, b.bottom) ? 0 : Math.abs(by - cy);
    } else {
      if (dir === 'down' ? by <= cy + 2 : by >= cy - 2) continue;
      gap = dir === 'down' ? b.top - r.bottom : r.top - b.bottom;
      ortho = overlap(r.left, r.right, b.left, b.right) ? 0 : Math.abs(bx - cx);
    }
    const score = Math.max(gap, 0) + ortho * 2.5 + Math.abs(dir === 'left' || dir === 'right' ? by - cy : bx - cx) * 0.05;
    if (score < bestScore) {
      bestScore = score;
      best = el;
    }
  }
  if (!best) return false;
  const mem = best.closest<HTMLElement>('[data-focus-memory]');
  if (mem && !mem.contains(cur)) {
    const last = (mem as any)._last as HTMLElement | undefined;
    if (last?.isConnected && last.getClientRects().length) best = last;
  }
  setFocus(best);
  return true;
}
