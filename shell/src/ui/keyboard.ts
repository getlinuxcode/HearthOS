import { esc, h } from '../dom';
import { input } from '../input/input';
import { state } from '../state';
import { focusFirst, getFocused, setFocus } from './focus';
import { router, type Layer } from './router';
import { sound } from './sound';

// Clavier virtuel piloté à la manette.
//  Ⓐ taper · Ⓧ effacer · Ⓨ espace · L1 majuscules · R1 afficher/masquer · Start valider · Ⓑ effacer / annuler
// Un clavier physique fonctionne aussi pendant que le clavier virtuel est ouvert.

const LAYOUTS = {
  azerty: ['1234567890', 'azertyuiop', 'qsdfghjklm', 'wxcvbn,.-'],
  qwerty: ['1234567890', 'qwertyuiop', 'asdfghjkl@', 'zxcvbnm,.-'],
  symbols: ['1234567890', '@#&_-+()/*', '"\':;!?%=€$', '<>[]{}|~^\\'],
};

export interface KeyboardOpts {
  title: string;
  value?: string;
  password?: boolean;
  placeholder?: string;
  okLabel?: string;
}

export function keyboard(opts: KeyboardOpts): Promise<string | null> {
  return new Promise((resolve) => {
    let value = opts.value ?? '';
    let shift = false;
    let symbols = false;
    let reveal = !opts.password;
    let done = false;
    const layoutName = state.settings?.keyboardLayout ?? 'azerty';

    const el = h(`
      <div class="vk-backdrop">
        <div class="vk">
          <div class="vk-title">${esc(opts.title)}</div>
          <div class="vk-field"><span class="vk-text"></span><span class="vk-caret"></span></div>
          <div class="vk-keys"></div>
          <div class="vk-help"></div>
        </div>
      </div>`);
    const textEl = el.querySelector<HTMLElement>('.vk-text')!;
    const keysEl = el.querySelector<HTMLElement>('.vk-keys')!;

    const renderText = () => {
      const shown = reveal ? value : '•'.repeat(value.length);
      textEl.innerHTML = shown ? esc(shown) : `<span class="vk-ph">${esc(opts.placeholder ?? '')}</span>`;
    };

    const renderKeys = () => {
      const focusedKey = getFocused()?.dataset.key;
      const rows = symbols ? LAYOUTS.symbols : LAYOUTS[layoutName];
      keysEl.innerHTML =
        rows
          .map(
            (row) =>
              `<div class="vk-row">${[...row]
                .map((c) => {
                  const ch = shift ? c.toUpperCase() : c;
                  return `<button class="vk-key" data-focus data-key="${esc(ch)}">${esc(ch)}</button>`;
                })
                .join('')}</div>`,
          )
          .join('') +
        `<div class="vk-row">
          <button class="vk-key vk-wide ${shift ? 'on' : ''}" data-focus data-key="#shift">⇧ Maj</button>
          <button class="vk-key vk-wide" data-focus data-key="#sym">${symbols ? 'abc' : '?123'}</button>
          <button class="vk-key vk-space" data-focus data-key=" ">Espace</button>
          <button class="vk-key vk-wide" data-focus data-key="#del">⌫</button>
          ${opts.password ? `<button class="vk-key vk-wide" data-focus data-key="#reveal">${reveal ? 'Masquer' : 'Afficher'}</button>` : ''}
          <button class="vk-key vk-ok" data-focus data-key="#ok">${esc(opts.okLabel ?? 'OK')}</button>
        </div>`;
      const again = focusedKey ? keysEl.querySelector<HTMLElement>(`[data-key="${CSS.escape(focusedKey)}"]`) : null;
      if (again) focusSet(again);
    };

    const focusSet = (k: HTMLElement) => {
      setFocus(k, { silent: true, instant: true });
    };

    const type = (k: string) => {
      switch (k) {
        case '#shift': shift = !shift; renderKeys(); return;
        case '#sym': symbols = !symbols; renderKeys(); return;
        case '#del': value = value.slice(0, -1); break;
        case '#reveal': reveal = !reveal; renderKeys(); break;
        case '#ok': finish(value); return;
        default:
          value += k;
          if (shift && !symbols) { shift = false; renderKeys(); }
      }
      renderText();
    };

    keysEl.addEventListener('click', (e) => {
      const k = (e.target as HTMLElement).closest<HTMLElement>('[data-key]');
      if (k) type(k.dataset.key!);
    });

    const finish = (v: string | null) => {
      if (done) return;
      done = true;
      removeRaw();
      router.closeModal(layer);
      resolve(v);
    };

    const removeRaw = input.pushRawKeyHandler((e) => {
      if (e.ctrlKey || e.altKey || e.metaKey) return false;
      if (e.key === 'Enter') { finish(value); return true; }
      if (e.key === 'Escape') { finish(null); return true; }
      if (e.key === 'Backspace') { value = value.slice(0, -1); renderText(); return true; }
      if (e.key.length === 1) { value += e.key; renderText(); return true; }
      return false; // flèches → navigation
    });

    const layer: Layer = {
      el,
      onLeave: () => { if (!done) { done = true; removeRaw(); resolve(null); } },
      hints: () => [
        { action: 'confirm', label: 'Taper' },
        { action: 'x', label: 'Effacer' },
        { action: 'y', label: 'Espace' },
        { action: 'lb', label: 'Maj' },
        { action: 'start', label: 'Valider' },
        { action: 'back', label: 'Annuler' },
      ],
      onAction: (e, t) => {
        if (t !== 'press') return true;
        switch (e.action) {
          case 'x': sound.back(); type('#del'); return true;
          case 'y': sound.tick(); type(' '); return true;
          case 'lb': type('#shift'); return true;
          case 'rb': if (opts.password) type('#reveal'); return true;
          case 'start': sound.confirm(); finish(value); return true;
          case 'back':
            if (e.repeat) return true;
            sound.back();
            if (value) type('#del');
            else finish(null);
            return true;
        }
        return false;
      },
    };

    renderText();
    renderKeys();
    router.openModal(layer);
    focusFirst(keysEl);
    const g = keysEl.querySelector<HTMLElement>('[data-key="#ok"]');
    if (value && g) focusSet(g);
  });
}
