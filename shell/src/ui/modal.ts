import { esc, h } from '../dom';
import type { Hint } from './glyphs';
import { router, type Layer } from './router';

export interface ModalAction {
  label: string;
  primary?: boolean;
  danger?: boolean;
  run?: () => void | Promise<void>;
  /** Par défaut l'action ferme la fenêtre. */
  keepOpen?: boolean;
}

export interface ModalOpts {
  title: string;
  body?: string | HTMLElement;
  actions?: ModalAction[];
  wide?: boolean;
  hints?: Hint[];
  onClose?: () => void;
  onAction?: Layer['onAction'];
}

export function openModal(opts: ModalOpts): Layer {
  const el = h(`
    <div class="modal-backdrop">
      <div class="modal ${opts.wide ? 'modal-wide' : ''}">
        <h2 class="modal-title">${esc(opts.title)}</h2>
        <div class="modal-body"></div>
        <div class="modal-actions"></div>
      </div>
    </div>`);
  const body = el.querySelector<HTMLElement>('.modal-body')!;
  if (typeof opts.body === 'string') body.innerHTML = opts.body;
  else if (opts.body) body.appendChild(opts.body);
  const actionsEl = el.querySelector<HTMLElement>('.modal-actions')!;
  const layer: Layer = {
    el,
    hints: opts.hints ? () => opts.hints! : undefined,
    onAction: opts.onAction,
    onLeave: opts.onClose,
  };
  (opts.actions ?? []).forEach((a, i) => {
    const b = h<HTMLButtonElement>(
      `<button class="btn-pill ${a.primary ? 'primary' : ''} ${a.danger ? 'danger' : ''}" data-focus ${i === 0 ? 'data-autofocus' : ''}>${esc(a.label)}</button>`,
    );
    b.addEventListener('click', async () => {
      if (!a.keepOpen) router.closeModal(layer);
      await a.run?.();
    });
    actionsEl.appendChild(b);
  });
  if (!opts.actions?.length) actionsEl.remove();
  router.openModal(layer);
  return layer;
}

export function confirmDialog(title: string, text: string, okLabel = 'Confirmer', danger = false): Promise<boolean> {
  return new Promise((resolve) => {
    let done = false;
    openModal({
      title,
      body: `<p>${esc(text)}</p>`,
      actions: [
        { label: 'Annuler', run: () => { done = true; resolve(false); } },
        { label: okLabel, primary: !danger, danger, run: () => { done = true; resolve(true); } },
      ],
      onClose: () => { if (!done) resolve(false); },
    });
  });
}
