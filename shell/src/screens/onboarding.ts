import { api, type DisplayInfo, type DisplaySettings, type NetworkStatus, type WifiNetwork } from '../api';
import { BRAND } from '../brand';
import { esc, h } from '../dom';
import type { Family } from '../input/controllers';
import { input } from '../input/input';
import { saveSettings, state, refreshNetwork, loadLibrary } from '../state';
import { setBackground } from '../ui/chrome';
import { controllerArt } from '../ui/controller-art';
import { focusFirst, setFocus } from '../ui/focus';
import { glyph } from '../ui/glyphs';
import { keyboard } from '../ui/keyboard';
import { openModal } from '../ui/modal';
import { router, type Layer } from '../ui/router';
import { renderRows, rowsOnAction, type Row } from '../ui/rows';
import { sound } from '../ui/sound';
import { toast } from '../ui/toast';
import { homeScreen } from './home';
import { installScreen } from './install';
import { steamLoginScreen } from './steam-login';

type StepId = 'controller' | 'network' | 'install' | 'accounts' | 'display' | 'done';
const LABELS: Record<StepId, string> = {
  controller: 'Manette',
  network: 'Réseau',
  install: 'Installation',
  accounts: 'Comptes',
  display: 'Affichage',
  done: 'Terminé',
};

function steps(): StepId[] {
  const withInstall = state.info?.mode !== 'installed';
  return ['controller', 'network', ...(withInstall ? (['install'] as StepId[]) : []), 'accounts', 'display', 'done'];
}

export function startOnboarding() {
  setBackground(null);
  router.reset(makeStep('controller'));
}

export function nextStep(from: StepId) {
  const list = steps();
  const next = list[list.indexOf(from) + 1];
  if (next) router.push(makeStep(next));
}

function makeStep(id: StepId): Layer {
  switch (id) {
    case 'controller': return controllerStep();
    case 'network': return networkStep();
    case 'install': return installScreen(() => nextStep('install'));
    case 'accounts': return accountsStep();
    case 'display': return displayStep();
    case 'done': return doneStep();
  }
}

export function stepper(current: StepId): string {
  const list: StepId[] = steps().filter((s) => s !== 'done');
  const idx = list.indexOf(current);
  return `<ol class="stepper">${list
    .map((s, i) => `<li class="${i < idx ? 'done' : i === idx ? 'current' : ''}"><span class="dot">${i < idx ? '✓' : i + 1}</span>${LABELS[s]}</li>`)
    .join('')}</ol>`;
}

// ------------------------------------------------------------------ 1. Manette

const CYCLE: Family[] = ['dualsense', 'xbox', 'ds4', 'switch', 'xbox360', 'generic'];

function controllerStep(): Layer {
  const el = h(`
    <section class="ob ob-controller">
      ${stepper('controller')}
      <div class="ob-split">
        <div class="ob-art"><div class="art-stage"></div><div class="art-glow"></div></div>
        <div class="ob-text">
          <p class="eyebrow">Bienvenue sur ${esc(BRAND.name)}</p>
          <h1 class="ob-title">Connectez votre manette</h1>
          <p class="ob-sub">Branchez-la en USB ou allumez-la en Bluetooth, puis <b>appuyez sur n'importe quel bouton</b>.</p>
          <div class="pad-status"></div>
          <div class="ob-actions">
            <button class="btn-pill primary hidden" data-focus data-act="continue">Continuer</button>
            <button class="btn-pill" data-focus data-act="pair">Appairer une manette Bluetooth</button>
            <button class="btn-pill ghost" data-focus data-act="keyboard">Continuer au clavier</button>
          </div>
        </div>
      </div>
    </section>`);
  const stage = el.querySelector<HTMLElement>('.art-stage')!;
  const status = el.querySelector<HTMLElement>('.pad-status')!;
  const cont = el.querySelector<HTMLElement>('[data-act="continue"]')!;
  let cycleIdx = 0;
  let timer: number | undefined;
  let detectedName = '';

  const showArt = (f: Family, detected: boolean) => {
    stage.innerHTML = controllerArt(f, detected ? 'big detected' : 'big');
  };

  const render = () => {
    const pad = input.activePad();
    if (pad) {
      clearInterval(timer);
      timer = undefined;
      if (detectedName !== pad.name) {
        detectedName = pad.name;
        showArt(pad.family, true);
        sound.success();
        input.rumble(pad.index, 250);
      }
      status.innerHTML = `<div class="pad-found"><span class="check">✓</span><div><b>${esc(pad.name)}</b> détectée${
        pad.vendor ? `<small>USB ${pad.vendor}:${pad.product}</small>` : ''
      }</div></div>`;
      cont.classList.remove('hidden');
      setFocus(cont, { silent: true });
    } else {
      detectedName = '';
      status.innerHTML = `<div class="pad-wait"><span class="pulse"></span>En attente d'une manette…</div>`;
      cont.classList.add('hidden');
      if (!timer) {
        showArt(CYCLE[cycleIdx], false);
        timer = window.setInterval(() => {
          cycleIdx = (cycleIdx + 1) % CYCLE.length;
          stage.firstElementChild?.classList.add('fade-out');
          setTimeout(() => showArt(CYCLE[cycleIdx], false), 250);
        }, 2200);
      }
    }
  };

  el.addEventListener('click', (e) => {
    const act = (e.target as HTMLElement).closest<HTMLElement>('[data-act]')?.dataset.act;
    if (act === 'continue' || act === 'keyboard') nextStep('controller');
    if (act === 'pair') pairingHelp();
  });

  let off: (() => void) | undefined;
  return {
    el,
    immersive: true,
    onEnter() {
      render();
      off = input.onPadsChange(render);
    },
    onResume: render,
    onLeave() {
      off?.();
      clearInterval(timer);
    },
    hints: () => [{ action: 'confirm', label: 'Sélectionner' }],
  };
}

export function pairingHelp() {
  const item = (f: Family, title: string, text: string) =>
    `<div class="pair-item">${controllerArt(f, 'mini')}<div><b>${title}</b><p>${text}</p></div></div>`;
  openModal({
    title: 'Appairer en Bluetooth',
    wide: true,
    body: `
      <p class="dim">Mettez la manette en mode appairage : elle apparaîtra automatiquement.</p>
      <div class="pair-grid">
        ${item('dualsense', 'DualSense / DualShock 4', 'Maintenez <b>Create/Share</b> + le bouton central 3 secondes, jusqu’à ce que la barre lumineuse clignote.')}
        ${item('xbox', 'Manette Xbox', 'Allumez-la, puis maintenez le petit bouton d’appairage sur la tranche jusqu’à ce que le bouton central clignote vite.')}
        ${item('switch', 'Manette Pro Switch', 'Maintenez le bouton de synchronisation sur la tranche supérieure.')}
        ${item('generic', 'Autre manette', 'Consultez sa notice. En cas de doute, le mode « X-input » est le plus compatible.')}
      </div>
      <p class="dim small">Sur la distribution, la recherche Bluetooth est assurée par BlueZ (phase 2). Une manette USB fonctionne toujours.</p>`,
    actions: [{ label: 'Compris', primary: true }],
  });
}

// ------------------------------------------------------------------ 2. Réseau

function networkStep(): Layer {
  const el = h(`
    <section class="ob">
      ${stepper('network')}
      <div class="ob-center">
        <h1 class="ob-title">Connexion à Internet</h1>
        <p class="ob-sub">Nécessaire pour Steam, les mises à jour et les jaquettes.</p>
        <div class="net-status card"></div>
        <div class="wifi-list v-scroll"></div>
        <div class="ob-actions center">
          <button class="btn-pill" data-focus data-act="rescan">Actualiser</button>
          <button class="btn-pill primary" data-focus data-act="next">Continuer</button>
        </div>
      </div>
    </section>`);
  const statusEl = el.querySelector<HTMLElement>('.net-status')!;
  const listEl = el.querySelector<HTMLElement>('.wifi-list')!;

  const renderStatus = (s: NetworkStatus | null) => {
    if (!s) {
      statusEl.innerHTML = `<span class="dot-state warn"></span>Service réseau injoignable`;
      return;
    }
    statusEl.innerHTML = s.connected
      ? `<span class="dot-state ok"></span><div><b>Connecté ${s.type === 'wifi' ? `au Wi-Fi « ${esc(s.name)} »` : 'en Ethernet'}</b><small>${s.internet ? 'Accès Internet OK' : 'Pas d’accès Internet'}${s.addresses[0] ? ` · ${s.addresses[0]}` : ''}</small></div>`
      : `<span class="dot-state warn"></span><div><b>Non connecté</b><small>Choisissez un réseau Wi-Fi ci-dessous ou branchez un câble.</small></div>`;
  };

  const renderWifi = async () => {
    listEl.innerHTML = `<div class="loading">Recherche des réseaux Wi-Fi…</div>`;
    try {
      const nets = await api.get<WifiNetwork[]>('/network/wifi');
      listEl.innerHTML = nets.length ? '' : `<div class="dim">Aucun réseau Wi-Fi trouvé.</div>`;
      for (const n of nets) {
        const b = h(`
          <button class="row wifi-row" data-focus>
            <span class="row-main"><span class="row-label">${esc(n.ssid)}</span>${n.active ? '<span class="row-desc">Connecté</span>' : ''}</span>
            <span class="row-right"><span class="bars">${[25, 50, 75].map((t) => `<i class="${n.signal >= t ? 'on' : ''}"></i>`).join('')}</span>${n.secure ? '🔒' : ''}</span>
          </button>`);
        b.addEventListener('click', () => connect(n));
        listEl.appendChild(b);
      }
    } catch (e) {
      listEl.innerHTML = `<div class="dim">${esc((e as Error).message)}</div>`;
    }
  };

  const connect = async (n: WifiNetwork) => {
    let password: string | undefined;
    if (n.secure) {
      const pw = await keyboard({ title: `Mot de passe de « ${n.ssid} »`, password: true, okLabel: 'Se connecter' });
      if (pw === null) return;
      password = pw;
    }
    statusEl.innerHTML = `<span class="spinner"></span>Connexion à « ${esc(n.ssid)} »…`;
    try {
      state.network = await api.post<NetworkStatus>('/network/wifi/connect', { ssid: n.ssid, password });
      renderStatus(state.network);
      toast(`Connecté à ${n.ssid}`, 'success');
      setFocus(el.querySelector<HTMLElement>('[data-act="next"]'));
      void renderWifi();
    } catch (e) {
      toast((e as Error).message, 'error');
      renderStatus(state.network);
    }
  };

  el.addEventListener('click', (e) => {
    const act = (e.target as HTMLElement).closest<HTMLElement>('[data-act]')?.dataset.act;
    if (act === 'next') nextStep('network');
    if (act === 'rescan') void renderWifi();
  });

  return {
    el,
    immersive: true,
    async onEnter() {
      setFocus(el.querySelector<HTMLElement>('[data-act="next"]'), { silent: true });
      await refreshNetwork();
      renderStatus(state.network);
      await renderWifi();
    },
  };
}

// ------------------------------------------------------------------ 4. Comptes

const STEAM_LOGO = `<svg viewBox="0 0 24 24" class="svc-ico"><circle cx="12" cy="12" r="10" fill="#1b2838"/><circle cx="15" cy="9.5" r="3" fill="none" stroke="#c7d5e0" stroke-width="1.6"/><circle cx="8.5" cy="15" r="2.2" fill="#c7d5e0"/><path d="M8.5 15l5-4" stroke="#c7d5e0" stroke-width="1.6"/></svg>`;

export function accountsGrid(onChange: () => void): HTMLElement {
  const grid = h(`<div class="svc-grid" data-focus-memory></div>`);
  const render = () => {
    const acc = state.library?.account;
    grid.innerHTML = `
      <button class="svc-card ${acc ? 'connected' : ''}" data-focus data-svc="steam">
        ${STEAM_LOGO}
        <b>Steam</b>
        <span>${acc ? `Connecté : ${esc(acc.personaName)}` : 'Se connecter avec un QR code'}</span>
      </button>
      <button class="svc-card soon" data-focus data-svc="epic">
        <span class="svc-ico svc-letter">E</span><b>Epic Games</b><span>Bientôt · code d’appareil</span>
      </button>
      <button class="svc-card soon" data-focus data-svc="gog">
        <span class="svc-ico svc-letter">G</span><b>GOG</b><span>Bientôt</span>
      </button>`;
  };
  grid.addEventListener('click', (e) => {
    const svc = (e.target as HTMLElement).closest<HTMLElement>('[data-svc]')?.dataset.svc;
    if (svc === 'steam') {
      if (state.library?.account) {
        openModal({
          title: 'Compte Steam',
          body: `<p>Connecté en tant que <b>${esc(state.library.account.personaName)}</b>.</p>`,
          actions: [
            { label: 'Fermer', primary: true },
            {
              label: 'Se déconnecter',
              danger: true,
              run: async () => {
                await api.post('/steam/logout');
                await loadLibrary();
                render();
                onChange();
              },
            },
          ],
        });
      } else {
        router.push(
          steamLoginScreen(async () => {
            await loadLibrary();
            render();
            onChange();
          }),
        );
      }
    } else if (svc) {
      toast(svc === 'epic' ? 'Epic Games arrive en phase 2 (connexion par code d’appareil + Legendary).' : 'GOG arrive en phase 2.', 'info');
    }
  });
  render();
  (grid as any).refresh = render;
  return grid;
}

function accountsStep(): Layer {
  const el = h(`
    <section class="ob">
      ${stepper('accounts')}
      <div class="ob-center">
        <h1 class="ob-title">Vos comptes de jeux</h1>
        <p class="ob-sub">Votre bibliothèque est importée automatiquement. Aucune autre application à ouvrir.</p>
        <div class="slot"></div>
        <div class="ob-actions center">
          <button class="btn-pill primary" data-focus data-act="next">Continuer</button>
        </div>
      </div>
    </section>`);
  const grid = accountsGrid(() => {});
  el.querySelector('.slot')!.replaceWith(grid);
  el.querySelector('[data-act="next"]')!.addEventListener('click', () => nextStep('accounts'));
  return {
    el,
    immersive: true,
    onEnter: () => focusFirst(grid),
    onResume: () => (grid as any).refresh(),
  };
}

// ------------------------------------------------------------------ 5. Affichage

export function displayRows(info: DisplayInfo, onChange?: () => void): Row[] {
  const s = () => state.settings!.display;
  const mode = () => info.modes.find((m) => m.width === s().width && m.height === s().height) ?? info.modes[0];
  const set = async (patch: Partial<DisplaySettings>) => {
    await saveSettings({ display: { ...s(), ...patch } });
    onChange?.();
  };
  return [
    {
      kind: 'choice',
      label: 'Résolution',
      desc: info.simulated ? 'Modes simulés en développement' : `Sortie ${info.output}`,
      options: info.modes.map((m) => ({ value: `${m.width}x${m.height}`, label: `${m.width} × ${m.height}${m.width === 3840 ? ' (4K)' : ''}` })),
      get: () => `${s().width}x${s().height}`,
      set: async (v: string) => {
        const [w, hh] = v.split('x').map(Number);
        const m = info.modes.find((x) => x.width === w && x.height === hh)!;
        await set({ width: w, height: hh, refresh: m.refresh.includes(s().refresh) ? s().refresh : m.refresh[0] });
      },
    },
    {
      kind: 'choice',
      label: 'Fréquence de rafraîchissement',
      options: [60, 120, 144, 30].map((r) => ({ value: r, label: `${r} Hz` })),
      get: () => s().refresh,
      set: async (v: number) => {
        if (!mode().refresh.includes(v)) {
          toast(`${v} Hz n’est pas disponible dans cette résolution`, 'error');
          return;
        }
        await set({ refresh: v });
      },
    },
    { kind: 'toggle', label: 'VRR (FreeSync / G-Sync)', desc: 'Fréquence variable si l’écran la gère', get: () => s().vrr, set: (v) => set({ vrr: v }) },
    { kind: 'toggle', label: 'HDR', desc: 'Pour les écrans et jeux compatibles', get: () => s().hdr, set: (v) => set({ hdr: v }) },
    {
      kind: 'choice',
      label: 'Mise à l’échelle (gamescope)',
      desc: 'Upscaling des jeux rendus en plus basse résolution',
      options: [
        { value: 'off', label: 'Désactivée' },
        { value: 'fsr', label: 'AMD FSR' },
        { value: 'nis', label: 'NVIDIA NIS' },
        { value: 'integer', label: 'Entière (pixel art)' },
      ],
      get: () => s().upscaler,
      set: (v) => set({ upscaler: v }),
    },
    {
      kind: 'choice',
      label: 'Limite d’images par seconde',
      options: [0, 30, 40, 60, 90, 120, 144].map((v) => ({ value: v, label: v ? `${v} i/s` : 'Aucune' })),
      get: () => s().fpsLimit,
      set: (v) => set({ fpsLimit: v }),
    },
    {
      kind: 'choice',
      label: 'Taille de l’interface',
      desc: 'Ajustez si les bords sont coupés sur votre TV',
      options: [0.85, 0.9, 1, 1.1, 1.25].map((v) => ({ value: v, label: `${Math.round(v * 100)} %` })),
      get: () => state.settings!.uiScale,
      set: (v) => saveSettings({ uiScale: v }),
    },
  ];
}

function displayStep(): Layer {
  const el = h(`
    <section class="ob">
      ${stepper('display')}
      <div class="ob-center">
        <h1 class="ob-title">Votre écran</h1>
        <p class="ob-sub">Les réglages sont appliqués par gamescope au prochain démarrage de session.</p>
        <div class="rows card v-scroll"></div>
        <div class="ob-actions center"><button class="btn-pill primary" data-focus data-act="next">Continuer</button></div>
      </div>
    </section>`);
  const rows = el.querySelector<HTMLElement>('.rows')!;
  el.querySelector('[data-act="next"]')!.addEventListener('click', () => nextStep('display'));
  return {
    el,
    immersive: true,
    async onEnter() {
      const info = await api.get<DisplayInfo>('/display');
      renderRows(displayRows(info), rows);
      focusFirst(rows);
    },
    onAction: rowsOnAction,
    hints: () => [
      { action: ['left', 'right'], label: 'Modifier' },
      { action: 'confirm', label: 'Sélectionner' },
      { action: 'back', label: 'Retour' },
    ],
  };
}

// ------------------------------------------------------------------ 6. Terminé

function doneStep(): Layer {
  const name = state.library?.account?.personaName;
  const el = h(`
    <section class="ob ob-done">
      <div class="done-burst"></div>
      <h1 class="ob-title big">Tout est prêt${name ? `, ${esc(name)}` : ''} !</h1>
      <p class="ob-sub">Appuyez sur ${glyph('confirm', input.family)} pour entrer.</p>
      <button class="btn-pill primary xl" data-focus data-autofocus>Commencer à jouer</button>
    </section>`);
  el.querySelector('button')!.addEventListener('click', async () => {
    await saveSettings({ onboarded: true });
    router.reset(homeScreen());
  });
  return { el, immersive: true, onEnter: () => sound.success() };
}
