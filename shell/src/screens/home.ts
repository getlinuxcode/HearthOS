import { api, type Game } from '../api';
import { esc, fmtPlaytime, h, imgFallbacks } from '../dom';
import { coverImg, heroUrl } from '../images';
import { loadLibrary, onStateChange, state } from '../state';
import { setBackground } from '../ui/chrome';
import { focusFirst, getFocused, setFocus } from '../ui/focus';
import { openModal } from '../ui/modal';
import { router, type Layer } from '../ui/router';
import { sound } from '../ui/sound';
import { toast } from '../ui/toast';
import { emulationScreen } from './emulation';
import { gameScreen } from './game';
import { settingsScreen } from './settings';
import { storeScreen } from './store';

type Filter = 'all' | 'installed' | 'steam' | 'retro';
const FILTERS: { id: Filter; label: string }[] = [
  { id: 'all', label: 'Tous' },
  { id: 'installed', label: 'Installés' },
  { id: 'steam', label: 'Steam' },
  { id: 'retro', label: 'Rétro' },
];

const SYSTEM_SHORT: Record<string, string> = {};

export function homeScreen(): Layer {
  let filter: Filter = 'all';
  const el = h(`
    <section class="home">
      <nav class="filters"></nav>
      <div class="shelf h-scroll" data-focus-memory></div>
      <div class="game-info"></div>
      <div class="quick-row" data-focus-memory>
        <button class="quick" data-focus data-go="store"><span class="q-ico">🛒</span><span>Boutique</span></button>
        <button class="quick" data-focus data-go="retro"><span class="q-ico">👾</span><span>Émulateurs</span></button>
        <button class="quick" data-focus data-go="settings"><span class="q-ico">⚙</span><span>Réglages</span></button>
        <button class="quick" data-focus data-go="power"><span class="q-ico">⏻</span><span>Alimentation</span></button>
      </div>
    </section>`);
  const shelf = el.querySelector<HTMLElement>('.shelf')!;
  const info = el.querySelector<HTMLElement>('.game-info')!;
  const filtersEl = el.querySelector<HTMLElement>('.filters')!;

  const visible = (): Game[] => {
    const all = state.library?.games ?? [];
    switch (filter) {
      case 'installed': return all.filter((g) => g.installed);
      case 'steam': return all.filter((g) => g.source === 'steam');
      case 'retro': return all.filter((g) => g.source === 'rom');
      default: return all;
    }
  };

  const renderFilters = () => {
    filtersEl.innerHTML =
      `<span class="filter-hint lb"></span>` +
      FILTERS.map((f) => `<span class="filter ${f.id === filter ? 'active' : ''}">${f.label}</span>`).join('') +
      (state.library?.demo ? `<button class="demo-chip" data-focus data-go="accounts">Bibliothèque de démonstration · connecter Steam</button>` : '');
  };

  const renderShelf = (keepId?: string) => {
    const games = visible();
    shelf.innerHTML = games.length
      ? games
          .map(
            (g, i) => `
        <button class="tile ${g.installed ? '' : 'not-installed'}" data-focus data-id="${esc(g.id)}" style="--i:${Math.min(i, 12)}">
          ${coverImg(g)}
          ${g.source === 'rom' ? `<span class="tile-tag">${esc(SYSTEM_SHORT[g.system!] ?? g.system?.toUpperCase())}</span>` : ''}
          ${g.installed ? '' : '<span class="tile-dl">⤓</span>'}
        </button>`,
          )
          .join('')
      : `<div class="shelf-empty">${filter === 'retro' ? 'Aucune ROM. Ajoutez un dossier ou déposez des fichiers par FTP dans <b>roms/</b>.' : 'Aucun jeu ici.'}</div>`;
    imgFallbacks(shelf);
    const target = (keepId && shelf.querySelector<HTMLElement>(`[data-id="${CSS.escape(keepId)}"]`)) || shelf.querySelector<HTMLElement>('.tile');
    if (target) setFocus(target, { silent: true, instant: true });
    else focusFirst(el);
  };

  const showInfo = (g: Game | undefined) => {
    if (!g) {
      info.innerHTML = '';
      return;
    }
    const meta = [
      g.source === 'steam' ? 'Steam' : `Rétro · ${esc(g.system?.toUpperCase())}`,
      g.installed ? 'Installé' : 'Non installé',
      fmtPlaytime(g.playtimeMinutes),
    ];
    info.innerHTML = `<h1 class="gi-title">${esc(g.name)}</h1><div class="gi-meta">${meta.map((m) => `<span>${m}</span>`).join('')}</div>`;
    info.firstElementChild?.animate([{ opacity: 0, transform: 'translateY(6px)' }, { opacity: 1, transform: 'none' }], { duration: 220, easing: 'ease-out' });
    setBackground(heroUrl(g));
  };

  const byId = (id: string | undefined) => state.library?.games.find((g) => g.id === id);

  el.addEventListener('focusin-nav', (e) => {
    const t = e.target as HTMLElement;
    if (t.classList.contains('tile')) showInfo(byId(t.dataset.id));
    else if (t.classList.contains('quick') || t.classList.contains('demo-chip')) {
      info.innerHTML = '';
      setBackground(null);
    }
  });

  el.addEventListener('click', (e) => {
    const t = e.target as HTMLElement;
    const tile = t.closest<HTMLElement>('.tile');
    if (tile) {
      const g = byId(tile.dataset.id);
      if (g) router.push(gameScreen(g));
      return;
    }
    const go = t.closest<HTMLElement>('[data-go]')?.dataset.go;
    if (go === 'store') router.push(storeScreen());
    if (go === 'settings') router.push(settingsScreen());
    if (go === 'accounts') router.push(settingsScreen('accounts'));
    if (go === 'retro') router.push(emulationScreen());
    if (go === 'power') powerMenu();
  });

  const cycleFilter = (d: number) => {
    const i = FILTERS.findIndex((f) => f.id === filter);
    filter = FILTERS[(i + d + FILTERS.length) % FILTERS.length].id;
    sound.tick();
    renderFilters();
    renderShelf();
  };

  let off: (() => void) | undefined;
  return {
    el,
    async onEnter() {
      renderFilters();
      renderShelf();
      if (!state.library) {
        try {
          await loadLibrary();
        } catch (e) {
          toast((e as Error).message, 'error');
        }
      }
      off = onStateChange(() => {
        const keep = getFocused()?.dataset.id;
        renderFilters();
        if (keep || !el.contains(getFocused())) renderShelf(keep);
      });
      renderFilters();
      renderShelf();
    },
    onResume() {
      const f = getFocused();
      if (f?.classList.contains('tile')) showInfo(byId(f.dataset.id));
    },
    onLeave: () => off?.(),
    onAction(e, type) {
      if (type !== 'press') return false;
      if (e.action === 'lb') return cycleFilter(-1), true;
      if (e.action === 'rb') return cycleFilter(1), true;
      if (e.action === 'start') return powerMenu(), true;
      if (e.action === 'y') {
        void loadLibrary().then(() => toast('Bibliothèque actualisée', 'success'));
        return true;
      }
      return false;
    },
    hints: () => [
      { action: 'confirm', label: 'Ouvrir' },
      { action: ['lb', 'rb'], label: 'Filtrer' },
      { action: 'y', label: 'Actualiser' },
      { action: 'start', label: 'Alimentation' },
    ],
  };
}

export function powerMenu() {
  const windows = state.info?.windowsDetected;
  const act = (a: string, label: string) => async () => {
    const r = await api.post<{ simulated: boolean }>(`/power/${a}`).catch((e) => (toast(e.message, 'error'), null));
    if (r?.simulated) toast(`${label} (simulation en développement)`, 'info');
  };
  openModal({
    title: 'Alimentation',
    actions: [
      { label: 'Mettre en veille', run: act('suspend', 'Mise en veille') },
      { label: 'Redémarrer', run: act('reboot', 'Redémarrage') },
      ...(windows ? [{ label: 'Redémarrer sous Windows', run: act('reboot-windows', 'Redémarrage sous Windows') }] : []),
      { label: 'Éteindre', danger: true, run: act('poweroff', 'Extinction') },
    ],
  });
}

export function setSystemShorts(map: Record<string, string>) {
  Object.assign(SYSTEM_SHORT, map);
}
