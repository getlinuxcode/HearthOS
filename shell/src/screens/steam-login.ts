import { api, type SteamLoginStatus } from '../api';
import { esc, h } from '../dom';
import { router, type Layer } from '../ui/router';
import { sound } from '../ui/sound';
import { toast } from '../ui/toast';

// Connexion Steam par QR code : scanné avec l'application Steam mobile (Steam Guard).

export function steamLoginScreen(onSuccess: () => void | Promise<void>): Layer {
  const el = h(`
    <section class="ob steam-login">
      <div class="ob-split">
        <div class="qr-box"><div class="qr"><div class="spinner"></div></div></div>
        <div class="ob-text">
          <p class="eyebrow">Steam</p>
          <h1 class="ob-title">Scannez avec votre téléphone</h1>
          <ol class="qr-steps">
            <li>Ouvrez l’application <b>Steam</b> sur votre téléphone</li>
            <li>Touchez l’icône <b>Steam Guard</b> (bouclier)</li>
            <li>Choisissez <b>« Scanner un QR code »</b> et visez l’écran</li>
          </ol>
          <div class="qr-status"></div>
          <div class="ob-actions">
            <button class="btn-pill hidden" data-focus data-act="retry">Nouveau QR code</button>
            <button class="btn-pill ghost" data-focus data-act="cancel">Annuler</button>
          </div>
        </div>
      </div>
    </section>`);
  const qr = el.querySelector<HTMLElement>('.qr')!;
  const statusEl = el.querySelector<HTMLElement>('.qr-status')!;
  const retry = el.querySelector<HTMLElement>('[data-act="retry"]')!;
  let poll = 0;
  let finished = false;

  const start = async () => {
    retry.classList.add('hidden');
    qr.classList.remove('expired');
    qr.innerHTML = '<div class="spinner"></div>';
    statusEl.innerHTML = '';
    try {
      const r = await api.post<{ qrSvg: string }>('/steam/login/qr');
      qr.innerHTML = r.qrSvg;
      statusEl.innerHTML = `<span class="pulse"></span>En attente du scan…`;
      clearInterval(poll);
      poll = window.setInterval(check, 2000);
    } catch (e) {
      statusEl.innerHTML = `<span class="err">${esc((e as Error).message)}</span>`;
      retry.classList.remove('hidden');
    }
  };

  const check = async () => {
    const s = await api.get<SteamLoginStatus>('/steam/login/status').catch(() => null);
    if (!s || finished) return;
    if (s.state === 'scanned') statusEl.innerHTML = `<span class="pulse ok"></span>Scanné ! Confirmez la connexion sur votre téléphone.`;
    if (s.state === 'done' && s.account) {
      finished = true;
      clearInterval(poll);
      sound.success();
      qr.innerHTML = s.account.avatarUrl ? `<img class="qr-avatar" src="${esc(s.account.avatarUrl)}" alt="">` : '<div class="qr-ok">✓</div>';
      statusEl.innerHTML = `<b>Bienvenue ${esc(s.account.personaName)} !</b> Import de la bibliothèque…`;
      await onSuccess();
      toast(`Steam connecté : ${s.account.personaName}`, 'success');
      setTimeout(() => router.back(), 900);
    }
    if (s.state === 'timeout' || s.state === 'error') {
      clearInterval(poll);
      qr.classList.add('expired');
      statusEl.innerHTML = s.state === 'timeout' ? 'Le QR code a expiré.' : `<span class="err">${esc(s.error ?? 'Erreur')}</span>`;
      retry.classList.remove('hidden');
      import('../ui/focus').then((f) => f.setFocus(retry));
    }
  };

  el.addEventListener('click', (e) => {
    const act = (e.target as HTMLElement).closest<HTMLElement>('[data-act]')?.dataset.act;
    if (act === 'retry') void start();
    if (act === 'cancel') router.back();
  });

  return {
    el,
    immersive: true,
    onEnter: () => void start(),
    onLeave: () => clearInterval(poll),
  };
}
