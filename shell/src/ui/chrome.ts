import { esc, h } from '../dom';
import { input } from '../input/input';
import { onStateChange, state } from '../state';
import { controllerArt } from './controller-art';

// Éléments permanents : fond animé, barre du haut, barre d'aide en bas, notifications.

let bgA: HTMLElement;
let bgB: HTMLElement;
let bgFlip = false;
let bgCurrent = '';

export function mountChrome(app: HTMLElement) {
  app.innerHTML = `
    <div id="bg">
      <div class="bg-aurora"></div>
      <div class="bg-img" id="bg-a"></div>
      <div class="bg-img" id="bg-b"></div>
      <div class="bg-shade"></div>
    </div>
    <header id="topbar"></header>
    <main id="screens"></main>
    <footer id="hints"></footer>
    <div id="modals"></div>
    <div id="toasts"></div>`;
  bgA = app.querySelector('#bg-a')!;
  bgB = app.querySelector('#bg-b')!;
  const top = app.querySelector<HTMLElement>('#topbar')!;
  const render = () => renderTopbar(top);
  render();
  setInterval(render, 15_000);
  onStateChange(render);
  input.onPadsChange(render);
  return {
    screens: app.querySelector<HTMLElement>('#screens')!,
    modals: app.querySelector<HTMLElement>('#modals')!,
    hints: app.querySelector<HTMLElement>('#hints')!,
  };
}

/** Fond plein écran avec fondu enchaîné (illustration du jeu sélectionné). */
export function setBackground(url: string | null) {
  if (url === bgCurrent) return;
  bgCurrent = url ?? '';
  const next = bgFlip ? bgA : bgB;
  const prev = bgFlip ? bgB : bgA;
  bgFlip = !bgFlip;
  if (!url) {
    prev.classList.remove('show');
    next.classList.remove('show');
    return;
  }
  const img = new Image();
  img.onload = () => {
    if (bgCurrent !== url) return;
    next.style.backgroundImage = `url("${url}")`;
    next.classList.add('show');
    prev.classList.remove('show');
  };
  img.src = url;
}

const WIFI_ICON = (s = 100) =>
  `<svg viewBox="0 0 24 24" class="ico"><path d="M2 9a15 15 0 0 1 20 0" opacity="${s > 66 ? 1 : 0.3}"/><path d="M5.5 12.5a10 10 0 0 1 13 0" opacity="${s > 33 ? 1 : 0.3}"/><path d="M9 16a5 5 0 0 1 6 0"/><circle cx="12" cy="19" r="1.2" fill="currentColor"/></svg>`;
const ETH_ICON = `<svg viewBox="0 0 24 24" class="ico"><rect x="5" y="9" width="14" height="10" rx="1.5"/><path d="M9 9V6h6v3M9 13v2M12 13v2M15 13v2"/></svg>`;
const OFFLINE_ICON = `<svg viewBox="0 0 24 24" class="ico"><path d="M2 9a15 15 0 0 1 20 0M5.5 12.5a10 10 0 0 1 13 0M9 16a5 5 0 0 1 6 0" opacity=".3"/><path d="M4 4l16 16"/></svg>`;

function renderTopbar(el: HTMLElement) {
  const acc = state.library?.account;
  const pads = input.pads();
  const now = new Date();
  const clock = now.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit', hour12: state.settings?.clock24h === false });
  const net = state.network;
  const netIcon = !net || !net.connected ? OFFLINE_ICON : net.type === 'wifi' ? WIFI_ICON(net.signal) : ETH_ICON;
  el.innerHTML = `
    <div class="tb-left">
      ${
        acc
          ? `<div class="avatar">${acc.avatarUrl ? `<img src="${esc(acc.avatarUrl)}" alt="">` : esc(acc.personaName[0] ?? '?')}</div><span class="tb-name">${esc(acc.personaName)}</span>`
          : `<div class="avatar avatar-guest">?</div><span class="tb-name dim">Invité</span>`
      }
    </div>
    <div class="tb-right">
      ${pads.map((p) => `<span class="tb-pad" title="${esc(p.name)}">${controllerArt(p.family, 'mini')}</span>`).join('')}
      <span class="tb-net">${netIcon}</span>
      <span class="tb-clock">${clock}</span>
    </div>`;
}
