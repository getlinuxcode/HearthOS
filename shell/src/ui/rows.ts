import { esc, h } from '../dom';
import type { InputEvent } from '../input/input';
import { getFocused } from './focus';
import { sound } from './sound';

// Lignes de réglages façon console : interrupteur, choix ◀ valeur ▶, action, info.

export type Row =
  | { kind: 'header'; label: string }
  | { kind: 'info'; label: string; value: string }
  | { kind: 'toggle'; label: string; desc?: string; get(): boolean; set(v: boolean): void | Promise<void> }
  | { kind: 'choice'; label: string; desc?: string; options: { value: any; label: string }[]; get(): any; set(v: any): void | Promise<void> }
  | { kind: 'action'; label: string; desc?: string; value?: string; danger?: boolean; badge?: string; run(): void | Promise<void> }
  | { kind: 'custom'; el: HTMLElement };

type RowEl = HTMLElement & { _row?: Row; _render?: () => void };

export function renderRows(rows: Row[], container: HTMLElement) {
  container.innerHTML = '';
  for (const row of rows) container.appendChild(rowEl(row));
}

function rowEl(row: Row): HTMLElement {
  if (row.kind === 'header') return h(`<div class="row-header">${esc(row.label)}</div>`);
  if (row.kind === 'custom') return row.el;
  if (row.kind === 'info') return h(`<div class="row row-info"><span class="row-label">${esc(row.label)}</span><span class="row-value">${esc(row.value)}</span></div>`);

  const el = h<RowEl>(`<button class="row ${row.kind === 'action' && row.danger ? 'row-danger' : ''}" data-focus></button>`);
  el._row = row;
  const desc = 'desc' in row && row.desc ? `<span class="row-desc">${esc(row.desc)}</span>` : '';
  el._render = () => {
    let right = '';
    if (row.kind === 'toggle') right = `<span class="toggle ${row.get() ? 'on' : ''}"><span></span></span>`;
    if (row.kind === 'choice') {
      const cur = row.options.find((o) => o.value === row.get()) ?? row.options[0];
      right = `<span class="choice"><span class="arrow">◀</span><span class="choice-val">${esc(cur?.label ?? '')}</span><span class="arrow">▶</span></span>`;
    }
    if (row.kind === 'action') {
      right = `${row.badge ? `<span class="badge">${esc(row.badge)}</span>` : ''}${row.value ? `<span class="row-value">${esc(row.value)}</span>` : ''}<span class="chev">›</span>`;
    }
    el.innerHTML = `<span class="row-main"><span class="row-label">${esc(row.label)}</span>${desc}</span><span class="row-right">${right}</span>`;
  };
  el._render();
  el.addEventListener('click', async () => {
    if (row.kind === 'toggle') {
      await row.set(!row.get());
      el._render!();
    } else if (row.kind === 'choice') {
      await cycle(el, row, 1);
    } else if (row.kind === 'action') {
      await row.run();
      el._render?.();
    }
  });
  return el;
}

async function cycle(el: RowEl, row: Extract<Row, { kind: 'choice' }>, delta: number) {
  const idx = row.options.findIndex((o) => o.value === row.get());
  const next = row.options[(idx + delta + row.options.length) % row.options.length];
  await row.set(next.value);
  el._render!();
  el.querySelector('.choice-val')?.animate(
    [{ transform: `translateX(${delta * 12}px)`, opacity: 0.3 }, { transform: 'none', opacity: 1 }],
    { duration: 160, easing: 'ease-out' },
  );
}

/** À appeler depuis onAction : gauche/droite sur une ligne « choix » change la valeur. */
export function rowsOnAction(e: InputEvent, type: 'press' | 'release'): boolean {
  if (type !== 'press' || (e.action !== 'left' && e.action !== 'right')) return false;
  const el = getFocused() as RowEl | null;
  const row = el?._row;
  if (!el || row?.kind !== 'choice') return false;
  sound.tick();
  void cycle(el, row, e.action === 'right' ? 1 : -1);
  return true;
}

/** Re-rend toutes les lignes d'un conteneur (valeurs modifiées ailleurs). */
export function refreshRows(container: HTMLElement) {
  container.querySelectorAll<RowEl>('.row').forEach((r) => r._render?.());
}
