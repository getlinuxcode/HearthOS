import { esc, h } from '../dom';
import { sound } from './sound';

let container: HTMLElement | null = null;

export function toast(message: string, kind: 'info' | 'success' | 'error' = 'info', ms = 3200) {
  container ??= document.getElementById('toasts');
  if (!container) return;
  const el = h(`<div class="toast toast-${kind}">${esc(message)}</div>`);
  container.appendChild(el);
  if (kind === 'error') sound.error();
  if (kind === 'success') sound.success();
  setTimeout(() => {
    el.classList.add('toast-out');
    setTimeout(() => el.remove(), 300);
  }, ms);
}
