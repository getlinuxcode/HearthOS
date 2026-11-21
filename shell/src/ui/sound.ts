// Sons d'interface synthétisés en temps réel (aucun fichier audio).
// Esthétique « console moderne » : sons doux, cristallins, avec un léger écho
// et une queue aérienne. Chaîne : voix → filtre doux → [sec + écho filtré] → sortie.

let ctx: AudioContext | null = null;
let master: GainNode | null = null;
let fx: AudioNode | null = null; // entrée de l'écho
let enabled = true;
let lastMove = 0;

function setup(a: AudioContext) {
  master = a.createGain();
  master.gain.value = 0.9;
  const soft = a.createBiquadFilter();
  soft.type = 'lowpass';
  soft.frequency.value = 9000;
  master.connect(soft).connect(a.destination);

  // Écho stéréo léger qui donne l'impression d'espace
  const delayL = a.createDelay(1);
  const delayR = a.createDelay(1);
  delayL.delayTime.value = 0.11;
  delayR.delayTime.value = 0.17;
  const fb = a.createGain();
  fb.gain.value = 0.28;
  const tone = a.createBiquadFilter();
  tone.type = 'lowpass';
  tone.frequency.value = 3200;
  const wet = a.createGain();
  wet.gain.value = 0.35;
  const merger = a.createChannelMerger(2);
  const input = a.createGain();
  input.connect(delayL);
  input.connect(delayR);
  delayL.connect(tone);
  delayR.connect(merger, 0, 1);
  tone.connect(fb).connect(delayL);
  tone.connect(merger, 0, 0);
  merger.connect(wet).connect(master);
  fx = input;
}

function audio(): AudioContext | null {
  if (!enabled) return null;
  try {
    if (!ctx) {
      ctx = new AudioContext();
      setup(ctx);
    }
    if (ctx.state === 'suspended') void ctx.resume();
    return ctx.state === 'running' ? ctx : null;
  } catch {
    return null;
  }
}

interface Voice {
  freq: number;
  dur: number;
  vol?: number;
  delay?: number;
  type?: OscillatorType;
  slideTo?: number;
  attack?: number;
  /** partiels de cloche (ratios de fréquence) */
  bell?: boolean;
  send?: number;
}

function voice(v: Voice) {
  const a = audio();
  if (!a || !master || !fx) return;
  const t = a.currentTime + (v.delay ?? 0);
  const partials = v.bell ? [[1, 1], [2.01, 0.32], [3.98, 0.12], [5.43, 0.05]] : [[1, 1]];
  const out = a.createGain();
  const attack = v.attack ?? 0.006;
  const vol = v.vol ?? 0.05;
  out.gain.setValueAtTime(0, t);
  out.gain.linearRampToValueAtTime(vol, t + attack);
  out.gain.exponentialRampToValueAtTime(0.0001, t + v.dur);
  out.connect(master);
  const send = a.createGain();
  send.gain.value = v.send ?? 0.6;
  out.connect(send).connect(fx);
  for (const [ratio, amp] of partials) {
    const osc = a.createOscillator();
    const g = a.createGain();
    osc.type = v.type ?? 'sine';
    osc.frequency.setValueAtTime(v.freq * ratio, t);
    if (v.slideTo) osc.frequency.exponentialRampToValueAtTime(v.slideTo * ratio, t + v.dur);
    // les partiels aigus s'éteignent plus vite : timbre de cloche
    g.gain.setValueAtTime(amp, t);
    if (ratio > 1) g.gain.exponentialRampToValueAtTime(0.0001, t + v.dur / (ratio * 0.9));
    osc.connect(g).connect(out);
    osc.start(t);
    osc.stop(t + v.dur + 0.05);
  }
}

/** Souffle filtré (transition d'écran). */
function whoosh(up = true, vol = 0.05, dur = 0.42) {
  const a = audio();
  if (!a || !master || !fx) return;
  const t = a.currentTime;
  const len = Math.floor(a.sampleRate * dur);
  const buf = a.createBuffer(1, len, a.sampleRate);
  const data = buf.getChannelData(0);
  for (let i = 0; i < len; i++) data[i] = Math.random() * 2 - 1;
  const src = a.createBufferSource();
  src.buffer = buf;
  const bp = a.createBiquadFilter();
  bp.type = 'bandpass';
  bp.Q.value = 1.4;
  bp.frequency.setValueAtTime(up ? 380 : 2600, t);
  bp.frequency.exponentialRampToValueAtTime(up ? 2600 : 380, t + dur);
  const g = a.createGain();
  g.gain.setValueAtTime(0, t);
  g.gain.linearRampToValueAtTime(vol, t + dur * 0.35);
  g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  src.connect(bp).connect(g);
  g.connect(master);
  g.connect(fx);
  src.start(t);
}

// Notes (Hz)
const N = { C5: 523.25, E5: 659.25, G5: 783.99, A5: 880, B5: 987.77, C6: 1046.5, D6: 1174.66, E6: 1318.5, G6: 1567.98, B6: 1975.5, C7: 2093 };

export const sound = {
  setEnabled(v: boolean) {
    enabled = v;
  },
  unlock() {
    audio();
  },
  /** Déplacement du focus : petit « tic » cristallin, plus discret en répétition rapide. */
  move() {
    const now = performance.now();
    const fast = now - lastMove < 120;
    lastMove = now;
    voice({ freq: N.G6, dur: 0.09, vol: fast ? 0.012 : 0.02, bell: true, send: 0.5 });
  },
  /** Validation : deux notes de cloche montantes. */
  confirm() {
    voice({ freq: N.E6, dur: 0.35, vol: 0.035, bell: true });
    voice({ freq: N.B6, dur: 0.5, vol: 0.028, bell: true, delay: 0.055 });
  },
  /** Retour : note douce descendante. */
  back() {
    voice({ freq: N.D6, dur: 0.22, vol: 0.026, slideTo: N.A5, type: 'triangle', send: 0.4 });
  },
  /** Ouverture d'une fenêtre. */
  open() {
    voice({ freq: N.C6, dur: 0.3, vol: 0.022, bell: true });
    voice({ freq: N.G6, dur: 0.4, vol: 0.016, bell: true, delay: 0.04 });
  },
  /** Changement d'écran (onboarding, navigation) : souffle + note. */
  transition(forward = true) {
    whoosh(forward, 0.045);
    voice({ freq: forward ? N.G5 : N.E5, dur: 0.6, vol: 0.016, bell: true, delay: 0.08, attack: 0.02 });
  },
  error() {
    voice({ freq: 330, dur: 0.16, vol: 0.04, type: 'triangle', send: 0.2 });
    voice({ freq: 262, dur: 0.24, vol: 0.04, type: 'triangle', delay: 0.11, send: 0.2 });
  },
  success() {
    [N.C6, N.E6, N.G6, N.C7].forEach((f, i) => voice({ freq: f, dur: 0.7 - i * 0.08, vol: 0.026, bell: true, delay: i * 0.075 }));
  },
  tick() {
    voice({ freq: N.C7, dur: 0.05, vol: 0.012, send: 0.3 });
  },
  /** Démarrage : accord qui gonfle lentement. */
  boot() {
    [N.C5, N.G5, N.E6].forEach((f, i) => voice({ freq: f, dur: 2.6, vol: 0.022, attack: 0.9, delay: i * 0.12, type: 'sine', send: 0.9 }));
    voice({ freq: N.C7, dur: 1.8, vol: 0.012, bell: true, delay: 0.9 });
    whoosh(true, 0.03, 1.4);
  },
};
