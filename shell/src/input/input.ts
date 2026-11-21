import { identify, type ControllerInfo, type Family } from './controllers';

export type Action =
  | 'up' | 'down' | 'left' | 'right'
  | 'confirm' | 'back' | 'x' | 'y'
  | 'lb' | 'rb' | 'lt' | 'rt'
  | 'select' | 'start' | 'home' | 'l3' | 'r3';

export interface InputEvent {
  action: Action;
  repeat: boolean;
  source: 'gamepad' | 'keyboard';
}

export type InputListener = (e: InputEvent, type: 'press' | 'release') => void;

export interface Pad extends ControllerInfo {
  index: number;
  raw: Gamepad;
}

// Index des boutons du « standard mapping » W3C → action
const BUTTON_ACTIONS: Action[] = [
  'confirm', 'back', 'x', 'y', 'lb', 'rb', 'lt', 'rt',
  'select', 'start', 'l3', 'r3', 'up', 'down', 'left', 'right', 'home',
];
const REPEATABLE = new Set<Action>(['up', 'down', 'left', 'right', 'lb', 'rb']);
const REPEAT_DELAY = 380;
const REPEAT_RATE = 85;
const STICK = 0.55;

const KEYMAP: Record<string, Action> = {
  ArrowUp: 'up', ArrowDown: 'down', ArrowLeft: 'left', ArrowRight: 'right',
  Enter: 'confirm', Escape: 'back', Backspace: 'back',
  x: 'x', y: 'y', PageUp: 'lb', PageDown: 'rb', '[': 'lb', ']': 'rb',
  m: 'start', v: 'select', h: 'home', Home: 'home',
};

interface HeldState {
  since: number;
  last: number;
}

class InputManager {
  private listeners = new Set<InputListener>();
  private padListeners = new Set<() => void>();
  private rawKeyHandlers: ((e: KeyboardEvent) => boolean)[] = [];
  private padState = new Map<number, Map<Action, HeldState>>();
  private known = new Map<number, ControllerInfo>();

  /** Dernier périphérique utilisé : pilote les glyphes affichés. */
  family: Family | 'keyboard' = 'keyboard';
  lastPadIndex: number | null = null;

  start() {
    window.addEventListener('gamepadconnected', () => this.refreshPads());
    window.addEventListener('gamepaddisconnected', () => this.refreshPads());
    window.addEventListener('keydown', (e) => this.onKey(e, 'press'));
    window.addEventListener('keyup', (e) => this.onKey(e, 'release'));
    const loop = () => {
      this.poll();
      requestAnimationFrame(loop);
    };
    requestAnimationFrame(loop);
  }

  on(fn: InputListener) {
    this.listeners.add(fn);
    return () => this.listeners.delete(fn);
  }

  onPadsChange(fn: () => void) {
    this.padListeners.add(fn);
    return () => this.padListeners.delete(fn);
  }

  /** Le clavier virtuel capture les touches physiques en priorité. */
  pushRawKeyHandler(fn: (e: KeyboardEvent) => boolean) {
    this.rawKeyHandlers.push(fn);
    return () => {
      this.rawKeyHandlers = this.rawKeyHandlers.filter((f) => f !== fn);
    };
  }

  pads(): Pad[] {
    const out: Pad[] = [];
    for (const gp of navigator.getGamepads()) {
      if (!gp) continue;
      out.push({ ...identify(gp.id), index: gp.index, raw: gp });
    }
    return out;
  }

  activePad(): Pad | null {
    const all = this.pads();
    return all.find((p) => p.index === this.lastPadIndex) ?? all[0] ?? null;
  }

  rumble(index?: number, ms = 300) {
    const gp = navigator.getGamepads()[index ?? this.lastPadIndex ?? 0];
    const act = (gp as any)?.vibrationActuator;
    act?.playEffect?.('dual-rumble', { duration: ms, strongMagnitude: 0.8, weakMagnitude: 0.6 }).catch(() => {});
  }

  private refreshPads() {
    const now = new Map<number, ControllerInfo>();
    for (const p of this.pads()) now.set(p.index, p);
    const changed = now.size !== this.known.size || [...now].some(([i, c]) => this.known.get(i)?.name !== c.name);
    this.known = now;
    if (!now.has(this.lastPadIndex ?? -1)) this.lastPadIndex = now.keys().next().value ?? null;
    if (this.lastPadIndex === null && this.family !== 'keyboard') this.family = 'keyboard';
    if (changed) this.padListeners.forEach((f) => f());
  }

  private emit(e: InputEvent, type: 'press' | 'release') {
    this.listeners.forEach((l) => l(e, type));
  }

  private setFamily(f: Family | 'keyboard', padIndex: number | null) {
    if (this.family === f && this.lastPadIndex === padIndex) return;
    this.family = f;
    if (padIndex !== null) this.lastPadIndex = padIndex;
    this.padListeners.forEach((fn) => fn());
  }

  private onKey(e: KeyboardEvent, type: 'press' | 'release') {
    if (type === 'press') {
      for (let i = this.rawKeyHandlers.length - 1; i >= 0; i--) {
        if (this.rawKeyHandlers[i](e)) {
          e.preventDefault();
          return;
        }
      }
    }
    const action = KEYMAP[e.key] ?? KEYMAP[e.key.toLowerCase()];
    if (!action) return;
    e.preventDefault();
    if (type === 'press') this.setFamily('keyboard', null);
    this.emit({ action, repeat: e.repeat, source: 'keyboard' }, type);
  }

  private poll() {
    const now = performance.now();
    for (const gp of navigator.getGamepads()) {
      if (!gp || !gp.connected) continue;
      if (!this.known.has(gp.index)) this.refreshPads();
      let state = this.padState.get(gp.index);
      if (!state) this.padState.set(gp.index, (state = new Map()));

      const pressed = new Set<Action>();
      gp.buttons.forEach((b, i) => {
        const a = BUTTON_ACTIONS[i];
        if (a && (b.pressed || b.value > 0.5)) pressed.add(a);
      });
      const [ax = 0, ay = 0] = gp.axes;
      if (ax < -STICK) pressed.add('left');
      if (ax > STICK) pressed.add('right');
      if (ay < -STICK) pressed.add('up');
      if (ay > STICK) pressed.add('down');

      for (const a of pressed) {
        const held = state.get(a);
        if (!held) {
          state.set(a, { since: now, last: now });
          this.setFamily(identify(gp.id).family, gp.index);
          this.emit({ action: a, repeat: false, source: 'gamepad' }, 'press');
        } else if (REPEATABLE.has(a) && now - held.since > REPEAT_DELAY && now - held.last > REPEAT_RATE) {
          held.last = now;
          this.emit({ action: a, repeat: true, source: 'gamepad' }, 'press');
        }
      }
      for (const a of [...state.keys()]) {
        if (!pressed.has(a)) {
          state.delete(a);
          this.emit({ action: a, repeat: false, source: 'gamepad' }, 'release');
        }
      }
    }
  }
}

export const input = new InputManager();
