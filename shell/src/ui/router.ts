import { input, type InputEvent } from '../input/input';
import { focusFirst, getFocused, move, setFocus, type Dir } from './focus';
import { hintsHtml, type Hint } from './glyphs';
import { sound } from './sound';

/** Un écran ou une fenêtre modale. */
export interface Layer {
  el: HTMLElement;
  /** Retourne true si l'action est consommée. */
  onAction?(e: InputEvent, type: 'press' | 'release'): boolean | void;
  hints?(): Hint[];
  onEnter?(): void;
  onResume?(): void;
  onLeave?(): void;
  /** Masque la barre du haut (onboarding, plein écran). */
  immersive?: boolean;
  modal?: boolean;
  lastFocus?: HTMLElement | null;
}

const ANIM_MS = 260;

class Router {
  private stack: Layer[] = [];
  private modals: Layer[] = [];
  private screensEl!: HTMLElement;
  private modalsEl!: HTMLElement;
  private hintsEl!: HTMLElement;
  homeFactory: (() => Layer) | null = null;

  mount(screens: HTMLElement, modals: HTMLElement, hints: HTMLElement) {
    this.screensEl = screens;
    this.modalsEl = modals;
    this.hintsEl = hints;
    input.on((e, type) => this.dispatch(e, type));
    input.onPadsChange(() => this.refreshHints());
  }

  top(): Layer | undefined {
    return this.modals.at(-1) ?? this.stack.at(-1);
  }

  get depth() {
    return this.stack.length;
  }

  push(layer: Layer) {
    const prev = this.stack.at(-1);
    if (prev) {
      prev.lastFocus = getFocused();
      prev.el.classList.add('screen-out');
      const el = prev.el;
      setTimeout(() => {
        if (this.stack.at(-1) !== prev) el.classList.add('hidden');
        el.classList.remove('screen-out');
      }, ANIM_MS);
    }
    this.stack.push(layer);
    if (prev) sound.transition(true);
    this.show(layer);
  }

  replace(layer: Layer) {
    const prev = this.stack.pop();
    if (prev) this.destroy(prev);
    this.stack.push(layer);
    this.show(layer);
  }

  reset(layer: Layer) {
    while (this.modals.length) this.closeModal(this.modals.at(-1)!);
    for (const l of this.stack) this.destroy(l);
    this.stack = [];
    this.push(layer);
  }

  back() {
    if (this.stack.length <= 1) return;
    const cur = this.stack.pop()!;
    this.destroy(cur);
    const prev = this.stack.at(-1)!;
    sound.transition(false);
    prev.el.classList.remove('hidden');
    prev.el.classList.add('screen-back');
    setTimeout(() => prev.el.classList.remove('screen-back'), ANIM_MS);
    this.applyChrome(prev);
    prev.onResume?.();
    if (prev.lastFocus?.isConnected) setFocus(prev.lastFocus, { silent: true, instant: true });
    else focusFirst(prev.el);
    this.refreshHints();
  }

  openModal(layer: Layer) {
    const top = this.top();
    if (top) top.lastFocus = getFocused();
    layer.modal = true;
    this.modals.push(layer);
    layer.el.classList.add('modal-layer');
    this.modalsEl.appendChild(layer.el);
    sound.open();
    layer.onEnter?.();
    if (!getFocused() || !layer.el.contains(getFocused())) focusFirst(layer.el);
    this.refreshHints();
  }

  closeModal(layer: Layer) {
    this.modals = this.modals.filter((m) => m !== layer);
    layer.onLeave?.();
    layer.el.classList.add('modal-out');
    setTimeout(() => layer.el.remove(), 180);
    const top = this.top();
    if (top?.lastFocus?.isConnected) setFocus(top.lastFocus, { silent: true, instant: true });
    else if (top) focusFirst(top.el);
    this.refreshHints();
  }

  refreshHints() {
    const top = this.top();
    const hints = top?.hints?.() ?? [
      { action: 'confirm', label: 'Sélectionner' },
      ...(this.stack.length > 1 || top?.modal ? [{ action: 'back', label: 'Retour' } as Hint] : []),
    ];
    this.hintsEl.innerHTML = hintsHtml(hints, input.family);
  }

  private show(layer: Layer) {
    layer.el.classList.add('screen', 'screen-in');
    this.screensEl.appendChild(layer.el);
    setTimeout(() => layer.el.classList.remove('screen-in'), ANIM_MS);
    this.applyChrome(layer);
    layer.onEnter?.();
    if (!getFocused() || !layer.el.contains(getFocused())) focusFirst(layer.el);
    this.refreshHints();
  }

  private applyChrome(layer: Layer) {
    document.body.classList.toggle('immersive', !!layer.immersive);
  }

  private destroy(layer: Layer) {
    layer.onLeave?.();
    layer.el.remove();
  }

  private dispatch(e: InputEvent, type: 'press' | 'release') {
    sound.unlock();
    const layer = this.top();
    if (!layer) return;
    if (layer.onAction?.(e, type)) return;
    if (type !== 'press') return;
    switch (e.action) {
      case 'up':
      case 'down':
      case 'left':
      case 'right':
        if (!move(e.action as Dir, layer.el) && !e.repeat) sound.tick();
        break;
      case 'confirm': {
        const f = getFocused();
        if (f && layer.el.contains(f) && !e.repeat) {
          sound.confirm();
          f.click();
        }
        break;
      }
      case 'back':
        if (e.repeat) break;
        if (layer.modal) {
          sound.back();
          this.closeModal(layer);
        } else if (this.stack.length > 1) {
          sound.back();
          this.back();
        }
        break;
      case 'home':
        if (this.homeFactory && !layer.immersive) {
          sound.back();
          this.reset(this.homeFactory());
        }
        break;
    }
  }
}

export const router = new Router();
