import { api, type DisplayInfo, type FtpStatus, type NetworkStatus, type WifiNetwork } from '../api';
import { esc, h } from '../dom';
import { input } from '../input/input';
import { refreshNetwork, saveSettings, state } from '../state';
import { setBackground } from '../ui/chrome';
import { controllerArt, updateArt } from '../ui/controller-art';
import { focusFirst, getFocused, setFocus } from '../ui/focus';
import { keyboard } from '../ui/keyboard';
import { openModal } from '../ui/modal';
import { router, type Layer } from '../ui/router';
import { refreshRows, renderRows, rowsOnAction, type Row } from '../ui/rows';
import { sound } from '../ui/sound';
import { toast } from '../ui/toast';
import { powerMenu } from './home';
import { accountsGrid, displayRows, pairingHelp, startOnboarding } from './onboarding';

type Cat = 'network' | 'display' | 'controllers' | 'accounts' | 'files' | 'sound' | 'datetime' | 'system' | 'power';
const CATS: { id: Cat; label: string; icon: string }[] = [
  { id: 'network', label: 'Réseau', icon: '📶' },
  { id: 'display', label: 'Affichage', icon: '🖥' },
  { id: 'controllers', label: 'Manettes', icon: '🎮' },
  { id: 'accounts', label: 'Comptes', icon: '👤' },
  { id: 'files', label: 'Fichiers et FTP', icon: '📂' },
  { id: 'sound', label: 'Son', icon: '🔊' },
  { id: 'datetime', label: 'Date et heure', icon: '🕒' },
  { id: 'system', label: 'Système', icon: 'ℹ' },
  { id: 'power', label: 'Alimentation', icon: '⏻' },
];

const TIMEZONES = ['Europe/Paris', 'Europe/Brussels', 'Europe/Zurich', 'America/Montreal', 'Europe/London', 'America/New_York', 'Asia/Tokyo', 'UTC'];

export function settingsScreen(initial: Cat = 'network'): Layer {
  let cat: Cat = initial;
  const el = h(`
    <section class="settings">
      <nav class="set-menu" data-focus-memory>
        <h1 class="page-title">Réglages</h1>
        ${CATS.map((c) => `<button class="set-cat" data-focus data-cat="${c.id}"><span class="ci">${c.icon}</span>${c.label}</button>`).join('')}
      </nav>
      <div class="set-panel v-scroll"></div>
    </section>`);
  const menu = el.querySelector<HTMLElement>('.set-menu')!;
  const panel = el.querySelector<HTMLElement>('.set-panel')!;
  let cleanup: (() => void) | undefined;

  const select = async (c: Cat) => {
    cat = c;
    cleanup?.();
    cleanup = undefined;
    menu.querySelectorAll('.set-cat').forEach((b) => b.classList.toggle('active', (b as HTMLElement).dataset.cat === c));
    panel.innerHTML = `<h2 class="panel-title">${CATS.find((x) => x.id === c)!.label}</h2><div class="panel-body"></div>`;
    const body = panel.querySelector<HTMLElement>('.panel-body')!;
    cleanup = (await PANELS[c](body)) ?? undefined;
  };

  el.addEventListener('focusin-nav', (e) => {
    const c = (e.target as HTMLElement).dataset.cat as Cat | undefined;
    if (c && c !== cat) void select(c);
  });
  menu.addEventListener('click', (e) => {
    if ((e.target as HTMLElement).closest('.set-cat')) focusFirst(panel);
  });

  return {
    el,
    async onEnter() {
      setBackground(null);
      await select(cat);
      const btn = menu.querySelector<HTMLElement>(`[data-cat="${cat}"]`)!;
      setFocus(btn, { silent: true, instant: true });
      if (initial !== 'network') focusFirst(panel);
    },
    onResume: () => void select(cat),
    onLeave: () => cleanup?.(),
    onAction(e, type) {
      if (rowsOnAction(e, type)) return true;
      // Ⓑ dans le panneau → retour au menu
      if (type === 'press' && e.action === 'back' && panel.contains(getFocused())) {
        sound.back();
        setFocus(menu.querySelector<HTMLElement>(`[data-cat="${cat}"]`));
        return true;
      }
      return false;
    },
    hints: () =>
      panel.contains(getFocused())
        ? [{ action: 'confirm', label: 'Sélectionner' }, { action: ['left', 'right'], label: 'Modifier' }, { action: 'back', label: 'Menu' }]
        : [{ action: 'confirm', label: 'Ouvrir' }, { action: 'back', label: 'Retour' }],
  };
}

type Panel = (body: HTMLElement) => Promise<(() => void) | void> | (() => void) | void;

const PANELS: Record<Cat, Panel> = {
  async network(body) {
    await refreshNetwork();
    const s = state.network;
    const rows: Row[] = [
      { kind: 'info', label: 'État', value: s?.connected ? (s.type === 'wifi' ? `Wi-Fi · ${s.name}` : 'Ethernet') : 'Déconnecté' },
      { kind: 'info', label: 'Internet', value: s?.internet ? 'OK' : 'Indisponible' },
      { kind: 'info', label: 'Adresse IP', value: s?.addresses.join(', ') || '—' },
      { kind: 'header', label: 'Réseaux Wi-Fi' },
    ];
    renderRows(rows, body);
    const list = h('<div><div class="loading">Recherche…</div></div>');
    body.appendChild(list);
    const nets = await api.get<WifiNetwork[]>('/network/wifi').catch(() => []);
    renderRows(
      nets.map((n) => ({
        kind: 'action',
        label: n.ssid,
        desc: `Signal ${n.signal}%${n.secure ? ' · sécurisé' : ''}`,
        badge: n.active ? 'Connecté' : undefined,
        run: async () => {
          const pw = n.secure ? await keyboard({ title: `Mot de passe de « ${n.ssid} »`, password: true, okLabel: 'Se connecter' }) : '';
          if (pw === null) return;
          try {
            state.network = await api.post<NetworkStatus>('/network/wifi/connect', { ssid: n.ssid, password: pw || undefined });
            toast(`Connecté à ${n.ssid}`, 'success');
          } catch (e) {
            toast((e as Error).message, 'error');
          }
        },
      })),
      list,
    );
  },

  async display(body) {
    const info = await api.get<DisplayInfo>('/display');
    renderRows(displayRows(info, () => refreshRows(body)), body);
    body.insertAdjacentHTML('beforeend', '<p class="dim small pad">Appliqué par gamescope au prochain lancement de session.</p>');
  },

  controllers(body) {
    const render = () => {
      const pads = input.pads();
      body.innerHTML = `<div class="pad-list">${
        pads.length
          ? pads.map((p) => `<div class="pad-card">${controllerArt(p.family, 'mid')}<b>${esc(p.name)}</b><span class="dim small">${p.vendor ? `USB ${p.vendor}:${p.product}` : 'Manette'} · joueur ${p.index + 1}</span></div>`).join('')
          : '<p class="dim">Aucune manette connectée.</p>'
      }</div><div class="rows"></div>`;
      renderRows(
        [
          { kind: 'action', label: 'Tester la manette', desc: 'Boutons, sticks et gâchettes', run: () => router.push(controllerTestScreen()) },
          { kind: 'action', label: 'Tester les vibrations', run: () => input.rumble(undefined, 600) },
          { kind: 'action', label: 'Appairer une manette Bluetooth', run: pairingHelp },
          {
            kind: 'choice',
            label: 'Clavier virtuel',
            options: [{ value: 'azerty', label: 'AZERTY' }, { value: 'qwerty', label: 'QWERTY' }],
            get: () => state.settings?.keyboardLayout,
            set: (v) => saveSettings({ keyboardLayout: v }),
          },
        ],
        body.querySelector<HTMLElement>('.rows')!,
      );
    };
    render();
    return input.onPadsChange(() => {
      const hadFocus = body.contains(getFocused());
      render();
      if (hadFocus) focusFirst(body);
    }) as () => void;
  },

  accounts(body) {
    body.appendChild(accountsGrid(() => {}));
    body.insertAdjacentHTML('beforeend', '<p class="dim small pad">Les achats se finalisent chez Steam (client ou téléphone) : aucune donnée de paiement ne transite par cette console.</p>');
  },

  async files(body) {
    let f = await api.get<FtpStatus>('/ftp');
    const render = () => {
      renderRows(
        [
          {
            kind: 'toggle',
            label: 'Serveur FTP',
            desc: 'Accès aux dossiers roms/, bios/ et files/ depuis un PC du réseau local',
            get: () => f.enabled,
            set: async (v) => {
              f = await api.post<FtpStatus>('/ftp', { enabled: v });
              if (f.error) toast(`FTP : ${f.error}`, 'error');
              else toast(v ? 'Serveur FTP activé' : 'Serveur FTP désactivé', 'success');
              render();
              focusFirst(body);
            },
          },
          ...(f.enabled
            ? ([
                { kind: 'info', label: 'Adresse', value: f.addresses.map((a) => `ftp://${a}:${f.port}`).join('  ·  ') || 'aucune adresse réseau' },
                { kind: 'info', label: 'Utilisateur', value: f.user },
                { kind: 'info', label: 'Mot de passe', value: f.password },
                {
                  kind: 'action',
                  label: 'Générer un nouveau mot de passe',
                  run: async () => {
                    f = await api.post<FtpStatus>('/ftp/password');
                    render();
                  },
                },
              ] as Row[])
            : []),
          { kind: 'header', label: 'Dossiers partagés' },
          { kind: 'info', label: 'roms/', value: 'Un sous-dossier par système (snes, gba, psx…) ou en vrac' },
          { kind: 'info', label: 'bios/', value: 'Fichiers BIOS demandés par certains émulateurs' },
          { kind: 'info', label: 'files/', value: 'Tout le reste' },
        ],
        body,
      );
      body.insertAdjacentHTML(
        'beforeend',
        `<p class="dim small pad">Depuis Windows : tapez l’adresse dans l’Explorateur de fichiers, ou utilisez FileZilla. FTP n’est pas chiffré : à n’activer que sur votre réseau domestique.<br>Racine : ${esc(f.root)}</p>`,
      );
    };
    render();
  },

  sound(body) {
    renderRows(
      [
        {
          kind: 'toggle',
          label: 'Sons de l’interface',
          get: () => state.settings?.sounds ?? true,
          set: async (v) => {
            sound.setEnabled(v);
            await saveSettings({ sounds: v });
            if (v) sound.confirm();
          },
        },
        { kind: 'info', label: 'Sortie audio', value: 'Automatique (PipeWire) — choix de la sortie en phase 2' },
      ],
      body,
    );
  },

  datetime(body) {
    renderRows(
      [
        { kind: 'choice', label: 'Fuseau horaire', options: TIMEZONES.map((t) => ({ value: t, label: t })), get: () => state.settings?.timezone, set: (v) => saveSettings({ timezone: v }) },
        { kind: 'toggle', label: 'Format 24 heures', get: () => state.settings?.clock24h ?? true, set: (v) => saveSettings({ clock24h: v }) },
        { kind: 'info', label: 'Synchronisation', value: 'Automatique (NTP)' },
      ],
      body,
    );
  },

  async system(body) {
    const i = state.info!;
    renderRows(
      [
        { kind: 'info', label: 'Version', value: i.version },
        { kind: 'info', label: 'Mode', value: i.mode === 'dev' ? 'Développement' : i.mode === 'live' ? 'Live USB' : 'Installé' },
        { kind: 'info', label: 'Processeur', value: i.cpu },
        { kind: 'info', label: 'Carte graphique', value: i.gpu.join(', ') || 'inconnue' },
        { kind: 'info', label: 'Mémoire', value: `${i.memoryGB} Go` },
        { kind: 'info', label: 'Noyau', value: i.kernel },
        { kind: 'header', label: 'Compatibilité' },
        { kind: 'info', label: 'Proton par défaut', value: 'Proton-CachyOS' },
        { kind: 'action', label: 'Relancer la configuration initiale', run: () => startOnboarding() },
      ],
      body,
    );
  },

  power(body) {
    renderRows([{ kind: 'action', label: 'Options d’alimentation', run: powerMenu }], body);
  },
};

// ------------------------------------------------------------------ Test manette

function controllerTestScreen(): Layer {
  const el = h(`
    <section class="pad-test">
      <h1 class="page-title">Test de la manette</h1>
      <div class="pt-stage"></div>
      <p class="dim">Appuyez sur les boutons. Maintenez <b>Ⓑ / ○</b> + <b>Start</b> pour quitter, ou Échap au clavier.</p>
    </section>`);
  const stage = el.querySelector<HTMLElement>('.pt-stage')!;
  let raf = 0;
  let family = '';
  const loop = () => {
    const pad = input.activePad();
    if (pad) {
      if (pad.family !== family) {
        family = pad.family;
        stage.innerHTML = controllerArt(pad.family, 'big test') + `<b>${esc(pad.name)}</b>`;
      }
      const svg = stage.querySelector('svg');
      if (svg) updateArt(svg, pad.raw);
      const b = pad.raw.buttons;
      if (b[1]?.pressed && b[9]?.pressed) {
        router.back();
        return;
      }
    } else if (family !== 'none') {
      family = 'none';
      stage.innerHTML = '<p class="dim">Aucune manette.</p>';
    }
    raf = requestAnimationFrame(loop);
  };
  return {
    el,
    onEnter: () => {
      raf = requestAnimationFrame(loop);
    },
    onLeave: () => cancelAnimationFrame(raf),
    // Toutes les entrées manette sont capturées pour le test ; le clavier permet de sortir.
    onAction: (e, type) => {
      if (e.source === 'keyboard' && e.action === 'back' && type === 'press') {
        router.back();
      }
      return true;
    },
    hints: () => [{ action: 'back', label: 'Quitter (Échap)' }],
  };
}

void openModal;
