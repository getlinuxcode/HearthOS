import { api, type AppDetails, type Game, type GameOptions } from '../api';
import { esc, fmtPlaytime, h, imgFallbacks } from '../dom';
import { heroUrl, steamImg } from '../images';
import { saveSettings, state } from '../state';
import { setBackground } from '../ui/chrome';
import { focusFirst } from '../ui/focus';
import { openModal } from '../ui/modal';
import { router, type Layer } from '../ui/router';
import { renderRows, rowsOnAction, type Row } from '../ui/rows';
import { sound } from '../ui/sound';
import { toast } from '../ui/toast';
import { storeItemScreen } from './store';

const COMPAT_TOOLS = [
  { value: 'proton-cachyos', label: 'Proton-CachyOS (recommandé)' },
  { value: 'proton-ge', label: 'Proton-GE' },
  { value: 'proton-experimental', label: 'Proton Experimental' },
  { value: 'proton-stable', label: 'Proton (stable)' },
  { value: 'native', label: 'Version Linux native' },
];

const DEFAULT_OPTS: GameOptions = { compatTool: 'proton-cachyos', mangohud: false, gamescopeFsr: false };

export function gameScreen(g: Game): Layer {
  const isSteam = g.source === 'steam' && g.appid;
  const last = g.lastPlayed ? new Date(g.lastPlayed).toLocaleDateString('fr-FR', { day: 'numeric', month: 'long', year: 'numeric' }) : null;
  const el = h(`
    <section class="game-page">
      <div class="gp-head">
        ${
          isSteam
            ? `<img class="gp-logo" src="${steamImg.logo(g.appid!)}" data-fallback-text="${esc(g.name)}" alt="">`
            : `<div class="gp-cover-rom"><img src="${esc(g.coverUrl ?? '')}" data-fallback-text="${esc(g.name)}" alt=""></div><h1 class="gp-title">${esc(g.name)}</h1>`
        }
        <div class="gp-meta">
          <span>${isSteam ? 'Steam' : `Rétro · ${esc(g.system?.toUpperCase())}`}</span>
          <span>${fmtPlaytime(g.playtimeMinutes)}</span>
          ${last ? `<span>Dernière partie : ${last}</span>` : ''}
          ${g.demo ? '<span class="badge">Démo</span>' : ''}
        </div>
        <div class="gp-actions" data-focus-memory>
          <button class="btn-pill primary xl" data-focus data-autofocus data-act="play">${g.installed ? '▶  Jouer' : '⤓  Installer'}</button>
          ${isSteam ? '<button class="btn-pill" data-focus data-act="options">Options de lancement</button>' : ''}
          ${isSteam ? '<button class="btn-pill" data-focus data-act="store">Page boutique</button>' : ''}
        </div>
      </div>
      <div class="gp-details"></div>
    </section>`);
  imgFallbacks(el);
  const details = el.querySelector<HTMLElement>('.gp-details')!;

  const play = async () => {
    if (g.demo) {
      toast('Jeu de démonstration : connectez Steam pour lancer vos propres jeux.', 'info');
      return;
    }
    try {
      if (!g.installed && isSteam) {
        await api.post(`/games/${encodeURIComponent(g.id)}/install`);
        toast('Installation lancée dans Steam', 'success');
        return;
      }
      const r = await api.post<{ simulated: boolean }>(`/games/${encodeURIComponent(g.id)}/launch`);
      launchingOverlay(g, r.simulated);
    } catch (e) {
      toast((e as Error).message, 'error');
    }
  };

  const options = () => {
    const key = g.id;
    const get = (): GameOptions => ({ ...DEFAULT_OPTS, ...state.settings?.games[key] });
    const set = (patch: Partial<GameOptions>) => saveSettings({ games: { [key]: { ...get(), ...patch } } });
    const rows: Row[] = [
      { kind: 'choice', label: 'Couche de compatibilité', desc: 'Pour les jeux Windows', options: COMPAT_TOOLS, get: () => get().compatTool, set: (v) => set({ compatTool: v }) },
      { kind: 'toggle', label: 'Afficher les performances (MangoHud)', get: () => get().mangohud, set: (v) => set({ mangohud: v }) },
      { kind: 'toggle', label: 'Upscaling FSR (gamescope)', desc: 'Rendu plus bas puis agrandi : plus d’images par seconde', get: () => get().gamescopeFsr, set: (v) => set({ gamescopeFsr: v }) },
    ];
    const box = h('<div class="rows"></div>');
    renderRows(rows, box);
    openModal({
      title: `Options · ${g.name}`,
      wide: true,
      body: box,
      onAction: rowsOnAction,
      hints: [{ action: ['left', 'right'], label: 'Modifier' }, { action: 'back', label: 'Fermer' }],
    });
    focusFirst(box);
  };

  el.addEventListener('click', (e) => {
    const act = (e.target as HTMLElement).closest<HTMLElement>('[data-act]')?.dataset.act;
    if (act === 'play') void play();
    if (act === 'options') options();
    if (act === 'store' && g.appid) router.push(storeItemScreen(g.appid));
  });

  return {
    el,
    async onEnter() {
      setBackground(heroUrl(g));
      if (!isSteam) return;
      try {
        const d = await api.get<AppDetails>(`/store/app/${g.appid}`);
        details.innerHTML = `
          <p class="gp-desc">${esc(d.description)}</p>
          <div class="chips">${d.genres.map((x) => `<span class="chip">${esc(x)}</span>`).join('')}</div>
          <p class="dim small">${esc(d.developers.join(', '))}${d.releaseDate ? ` · ${esc(d.releaseDate)}` : ''}</p>`;
        details.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 300 });
      } catch {
        /* hors-ligne : on garde la fiche minimale */
      }
    },
    onResume: () => setBackground(heroUrl(g)),
    hints: () => [{ action: 'confirm', label: 'Sélectionner' }, { action: 'back', label: 'Retour' }],
  };
}

function launchingOverlay(g: Game, simulated: boolean) {
  sound.success();
  const el = h(`
    <div class="launching">
      <div class="launch-ring"></div>
      <h2>Lancement de ${esc(g.name)}…</h2>
      ${simulated ? '<p class="dim">Simulation : l’émulateur n’est pas disponible sous Windows.</p>' : ''}
    </div>`);
  document.body.appendChild(el);
  setTimeout(() => {
    el.classList.add('out');
    setTimeout(() => el.remove(), 400);
  }, 2600);
}
