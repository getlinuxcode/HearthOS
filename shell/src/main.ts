import './styles.css';
import { api, type Settings, type SystemInfo, type EmuSystem } from './api';
import { BRAND } from './brand';
import { esc, h } from './dom';
import { input } from './input/input';
import { applySettings, loadLibrary, refreshNetwork, state } from './state';
import { mountChrome } from './ui/chrome';
import { setFocus } from './ui/focus';
import { router, type Layer } from './ui/router';
import { sound } from './ui/sound';
import { homeScreen, setSystemShorts } from './screens/home';
import { startOnboarding } from './screens/onboarding';

function bootScreen(): Layer {
  const el = h(`
    <section class="boot">
      <div class="boot-logo">
        <svg viewBox="0 0 120 120" class="boot-mark">
          <defs><linearGradient id="bm" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#7c9cff"/><stop offset="1" stop-color="#b56bff"/></linearGradient></defs>
          <path d="M60 12 L104 36 V84 L60 108 L16 84 V36 Z" fill="none" stroke="url(#bm)" stroke-width="5" stroke-linejoin="round"/>
          <path d="M60 38 C72 52 78 62 78 72 a18 18 0 0 1 -36 0 C42 62 48 52 60 38 Z" fill="url(#bm)"/>
        </svg>
        <h1>${esc(BRAND.name)}</h1>
        <p>${esc(BRAND.tagline)}</p>
      </div>
      <div class="boot-status"></div>
    </section>`);
  return { el, immersive: true, hints: () => [] };
}

async function boot() {
  const app = document.getElementById('app')!;
  const chrome = mountChrome(app);
  router.mount(chrome.screens, chrome.modals, chrome.hints);
  router.homeFactory = homeScreen;
  input.start();

  // Souris : le survol déplace le focus (le clic fonctionne nativement).
  document.addEventListener('mousemove', (e) => {
    const t = (e.target as HTMLElement).closest<HTMLElement>('[data-focus]');
    const top = router.top();
    if (t && top?.el.contains(t) && !t.classList.contains('focused')) setFocus(t, { silent: true });
  });
  // Un premier clic / touche débloque l'audio dans un navigateur.
  window.addEventListener('pointerdown', () => sound.unlock(), { once: true });

  const b = bootScreen();
  router.reset(b);
  sound.boot();
  const status = b.el.querySelector<HTMLElement>('.boot-status')!;
  const started = performance.now();

  for (let attempt = 0; ; attempt++) {
    try {
      [state.info, state.settings] = await Promise.all([api.get<SystemInfo>('/system/info'), api.get<Settings>('/settings')]);
      break;
    } catch {
      status.innerHTML = `<span class="spinner small"></span>Démarrage du service système…${attempt > 3 ? '<br><small>Lancez « npm run dev » à la racine du projet.</small>' : ''}`;
      await new Promise((r) => setTimeout(r, 1000));
    }
  }
  sound.setEnabled(state.settings!.sounds);
  applySettings();
  void refreshNetwork();
  setInterval(refreshNetwork, 30_000);
  api.get<EmuSystem[]>('/emu/systems').then((s) => setSystemShorts(Object.fromEntries(s.map((x) => [x.id, x.short])))).catch(() => {});
  const lib = loadLibrary().catch(() => null);

  // Laisse le temps à l'animation du logo
  await new Promise((r) => setTimeout(r, Math.max(0, 1800 - (performance.now() - started))));
  b.el.classList.add('boot-out');
  await new Promise((r) => setTimeout(r, 450));

  if (!state.settings!.onboarded || state.info!.mode === 'live') startOnboarding();
  else {
    await lib;
    router.reset(homeScreen());
  }
}

void boot();
