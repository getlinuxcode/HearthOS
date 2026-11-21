import { api, type Disk, type InstallMode, type InstallProgress } from '../api';
import { esc, fmtGB, GB, h } from '../dom';
import { state } from '../state';
import { focusFirst } from '../ui/focus';
import { router, type Layer } from '../ui/router';
import { sound } from '../ui/sound';
import { toast } from '../ui/toast';
import { stepper } from './onboarding';

// Installateur à la manette : disque → mode → taille → confirmation maintenue → progression.

const MIN_GB = 64;
const STEP_GB = 16;
const HOLD_MS = 2500;

export function installScreen(onDone: () => void): Layer {
  const simulated = state.info?.mock ?? true;
  const el = h(`
    <section class="ob ob-install">
      ${stepper('install')}
      ${simulated ? '<div class="sim-banner">Mode simulation : aucun disque ne sera modifié</div>' : ''}
      <div class="ob-center install-body"></div>
    </section>`);
  const body = el.querySelector<HTMLElement>('.install-body')!;

  let disks: Disk[] = [];
  let disk: Disk | null = null;
  let mode: InstallMode = 'alongside';
  let sizeGB = 256;
  let stage: 'disk' | 'mode' | 'size' | 'confirm' | 'progress' = 'disk';
  let holdStart = 0;
  let holdTimer = 0;
  let pollTimer = 0;

  const maxGB = () => {
    if (!disk) return 0;
    const bytes = mode === 'alongside' ? disk.shrinkable?.maxBytes ?? 0 : mode === 'free' ? disk.freeSpace : disk.size;
    return Math.floor(bytes / GB);
  };

  const go = (s: typeof stage) => {
    stage = s;
    sound.move();
    render();
  };

  const render = () => {
    switch (stage) {
      case 'disk': return renderDisks();
      case 'mode': return renderMode();
      case 'size': return renderSize();
      case 'confirm': return renderConfirm();
      case 'progress': return renderProgress();
    }
  };

  // --- 1. disque
  const renderDisks = () => {
    body.innerHTML = `
      <h1 class="ob-title">Où installer ?</h1>
      <p class="ob-sub">Vous pourrez aussi l’essayer depuis la clé USB sans rien installer.</p>
      <div class="disk-list"></div>
      <div class="ob-actions center"><button class="btn-pill ghost" data-focus data-act="skip">Passer (rester en mode live)</button></div>`;
    const list = body.querySelector<HTMLElement>('.disk-list')!;
    for (const d of disks) {
      const b = h(`
        <button class="disk-card" data-focus ${d.isBootMedia ? 'disabled' : ''}>
          <div class="disk-ico">${d.transport === 'usb' ? 'USB' : d.transport.toUpperCase()}</div>
          <div class="disk-info">
            <b>${esc(d.model)}</b>
            <span>${fmtGB(d.size)} · ${esc(d.path)}</span>
            <div class="disk-bar">${diskBar(d)}</div>
          </div>
          <div class="disk-tags">
            ${d.detectedOS.map((o) => `<span class="badge win">${esc(o)} détecté</span>`).join('')}
            ${d.isBootMedia ? '<span class="badge">Support de démarrage</span>' : ''}
            ${d.freeSpace > MIN_GB * GB ? `<span class="badge">${fmtGB(d.freeSpace)} libres</span>` : ''}
          </div>
        </button>`);
      b.addEventListener('click', () => {
        disk = d;
        mode = d.shrinkable ? 'alongside' : d.freeSpace >= MIN_GB * GB ? 'free' : 'erase';
        go('mode');
      });
      list.appendChild(b);
    }
    body.querySelector('[data-act="skip"]')!.addEventListener('click', onDone);
    focusFirst(body);
  };

  // --- 2. mode
  const renderMode = () => {
    const d = disk!;
    const opt = (m: InstallMode, title: string, text: string, ok: boolean, danger = false) =>
      `<button class="mode-card ${danger ? 'danger' : ''}" data-focus data-mode="${m}" ${ok ? '' : 'disabled'}>
        <b>${title}</b><span>${text}</span>${ok ? '' : '<em>Indisponible sur ce disque</em>'}</button>`;
    body.innerHTML = `
      <h1 class="ob-title">${esc(d.model)}</h1>
      <p class="ob-sub">Comment voulez-vous utiliser ce disque ?</p>
      <div class="mode-list">
        ${opt('alongside', 'À côté de Windows', 'Garde Windows intact. Au démarrage, vous choisissez : jouer ici, ou travailler sous Windows.', !!d.shrinkable && d.shrinkable.maxBytes >= MIN_GB * GB)}
        ${opt('free', 'Dans l’espace libre', `Utilise ${fmtGB(d.freeSpace)} non partitionnés, sans toucher au reste.`, d.freeSpace >= MIN_GB * GB)}
        ${opt('erase', 'Effacer tout le disque', 'Supprime TOUT le contenu du disque (Windows compris) pour ne garder que la console.', d.size >= MIN_GB * GB, true)}
      </div>`;
    body.querySelectorAll<HTMLElement>('[data-mode]').forEach((b) =>
      b.addEventListener('click', () => {
        mode = b.dataset.mode as InstallMode;
        if (mode === 'erase') {
          sizeGB = Math.floor(d.size / GB);
          go('confirm');
        } else {
          sizeGB = Math.min(Math.max(MIN_GB, Math.round(maxGB() * 0.5 / STEP_GB) * STEP_GB), maxGB());
          go('size');
        }
      }),
    );
    focusFirst(body);
  };

  // --- 3. taille
  const renderSize = () => {
    const d = disk!;
    const winPart = d.partitions.find((p) => p.path === d.shrinkable?.partition);
    body.innerHTML = `
      <h1 class="ob-title">Quelle place pour les jeux ?</h1>
      <p class="ob-sub">${glyphless('◀ ▶')} pour ajuster · les jeux modernes pèsent souvent 50 à 150 Go.</p>
      <div class="size-visual card">
        <div class="split-bar">
          <div class="seg seg-other"><span>${mode === 'alongside' ? 'Windows' : 'Existant'}</span><b class="other-size"></b></div>
          <div class="seg seg-new"><span>Console</span><b class="new-size"></b></div>
        </div>
        <div class="size-slider" data-focus data-autofocus>
          <span class="arrow">◀</span><span class="size-val"></span><span class="arrow">▶</span>
        </div>
        ${mode === 'alongside' && winPart?.used ? `<p class="dim small">Windows utilise ${fmtGB(winPart.used)} ; une marge de sécurité lui est conservée.</p>` : ''}
      </div>
      <div class="ob-actions center"><button class="btn-pill primary" data-focus data-act="next">Continuer</button></div>`;
    const update = () => {
      const max = maxGB();
      const totalGB = mode === 'alongside' ? Math.floor((winPart?.size ?? d.size) / GB) : Math.floor(d.size / GB);
      const pct = Math.max(8, Math.min(92, (sizeGB / totalGB) * 100));
      body.querySelector<HTMLElement>('.seg-new')!.style.flexBasis = `${pct}%`;
      body.querySelector<HTMLElement>('.size-val')!.textContent = `${sizeGB} Go`;
      body.querySelector<HTMLElement>('.new-size')!.textContent = `${sizeGB} Go`;
      body.querySelector<HTMLElement>('.other-size')!.textContent = `${totalGB - sizeGB} Go`;
      body.querySelector('.size-slider')!.classList.toggle('at-max', sizeGB >= max);
    };
    body.querySelector('[data-act="next"]')!.addEventListener('click', () => go('confirm'));
    (body as any)._adjust = (dir: number) => {
      const next = Math.min(maxGB(), Math.max(MIN_GB, sizeGB + dir * STEP_GB));
      if (next !== sizeGB) {
        sizeGB = next;
        sound.tick();
        update();
      } else sound.error();
    };
    update();
    focusFirst(body);
  };

  // --- 4. confirmation
  const renderConfirm = () => {
    const d = disk!;
    const lines =
      mode === 'erase'
        ? [`<li class="warn">Toutes les données de <b>${esc(d.model)}</b> seront effacées.</li>`]
        : mode === 'alongside'
          ? [`<li>Windows sera réduit de <b>${sizeGB} Go</b>, ses fichiers sont conservés.</li>`, '<li>Un menu de démarrage permettra de choisir le système.</li>']
          : [`<li><b>${sizeGB} Go</b> d’espace libre seront utilisés.</li>`];
    body.innerHTML = `
      <h1 class="ob-title">Prêt à installer</h1>
      <div class="card summary">
        <ul>
          <li>Disque : <b>${esc(d.model)}</b> (${esc(d.path)})</li>
          ${lines.join('')}
          <li>Système : Arch Linux · noyau linux-cachyos · btrfs avec instantanés</li>
        </ul>
        ${mode === 'alongside' ? '<p class="dim small">Avant de continuer : désactivez BitLocker et le « démarrage rapide » de Windows.</p>' : ''}
      </div>
      <button class="hold-btn ${mode === 'erase' ? 'danger' : ''}" data-focus data-autofocus>
        <span class="hold-fill"></span><span class="hold-label">Maintenir pour installer</span>
      </button>`;
    focusFirst(body);
  };

  const holdTick = () => {
    const btn = body.querySelector<HTMLElement>('.hold-btn');
    if (!btn || !holdStart) return;
    const p = Math.min(1, (performance.now() - holdStart) / HOLD_MS);
    btn.style.setProperty('--p', String(p));
    if (p >= 1) {
      holdStart = 0;
      clearInterval(holdTimer);
      void launch();
    }
  };
  const holdCancel = () => {
    holdStart = 0;
    clearInterval(holdTimer);
    body.querySelector<HTMLElement>('.hold-btn')?.style.setProperty('--p', '0');
  };

  const launch = async () => {
    try {
      await api.post<InstallProgress>('/install/start', { disk: disk!.path, mode, sizeGB });
      sound.confirm();
      go('progress');
    } catch (e) {
      holdCancel();
      toast((e as Error).message, 'error');
    }
  };

  // --- 5. progression
  const renderProgress = () => {
    body.innerHTML = `
      <h1 class="ob-title">Installation en cours</h1>
      <div class="progress-ring"><svg viewBox="0 0 120 120"><circle cx="60" cy="60" r="52" class="track"/><circle cx="60" cy="60" r="52" class="bar"/></svg><b class="pct">0 %</b></div>
      <p class="ob-sub step-label">Préparation…</p>`;
    const poll = async () => {
      const p = await api.get<InstallProgress>('/install/progress').catch(() => null);
      if (!p) return;
      const bar = body.querySelector<SVGCircleElement>('.bar');
      if (bar) bar.style.strokeDashoffset = String(327 * (1 - p.percent / 100));
      body.querySelector('.pct')!.textContent = `${p.percent} %`;
      body.querySelector('.step-label')!.textContent = p.step;
      if (p.state === 'done') {
        clearInterval(pollTimer);
        sound.success();
        body.insertAdjacentHTML(
          'beforeend',
          `<p class="dim">${p.simulated ? 'Simulation terminée.' : 'Retirez la clé USB puis redémarrez.'}</p>
           <div class="ob-actions center"><button class="btn-pill primary" data-focus data-autofocus>Continuer</button></div>`,
        );
        body.querySelector('.ob-actions button')!.addEventListener('click', onDone);
        focusFirst(body);
      } else if (p.state === 'error') {
        clearInterval(pollTimer);
        toast(p.error ?? 'Échec de l’installation', 'error', 8000);
      }
    };
    pollTimer = window.setInterval(poll, 700);
    void poll();
  };

  return {
    el,
    immersive: true,
    async onEnter() {
      body.innerHTML = '<div class="loading">Analyse des disques…</div>';
      try {
        disks = await api.get<Disk[]>('/disks');
      } catch (e) {
        toast((e as Error).message, 'error');
      }
      render();
    },
    onLeave() {
      clearInterval(pollTimer);
      clearInterval(holdTimer);
    },
    onAction(e, type) {
      if (stage === 'progress' && e.action === 'back') return true;
      if (stage === 'size' && type === 'press' && (e.action === 'left' || e.action === 'right')) {
        if (document.querySelector('.size-slider.focused')) {
          (body as any)._adjust(e.action === 'right' ? 1 : -1);
          return true;
        }
      }
      if (stage === 'confirm' && e.action === 'confirm' && document.querySelector('.hold-btn.focused')) {
        if (type === 'press' && !e.repeat && !holdStart) {
          holdStart = performance.now();
          holdTimer = window.setInterval(holdTick, 16);
        } else if (type === 'release') holdCancel();
        return true;
      }
      if (e.action === 'back' && type === 'press' && stage !== 'disk') {
        go(stage === 'confirm' ? (mode === 'erase' ? 'mode' : 'size') : stage === 'size' ? 'mode' : 'disk');
        sound.back();
        return true;
      }
      return false;
    },
    hints: () =>
      stage === 'progress'
        ? []
        : stage === 'confirm'
        ? [{ action: 'confirm', label: 'Maintenir pour installer' }, { action: 'back', label: 'Retour' }]
        : stage === 'size'
          ? [{ action: ['left', 'right'], label: 'Ajuster' }, { action: 'confirm', label: 'Continuer' }, { action: 'back', label: 'Retour' }]
          : [{ action: 'confirm', label: 'Sélectionner' }, { action: 'back', label: 'Retour' }],
  };

  function glyphless(s: string) {
    return `<b>${s}</b>`;
  }
}

function diskBar(d: Disk): string {
  const colors: Record<string, string> = { windows: '#3d8cf5', efi: '#8a8f9c', linux: '#f2a33a', data: '#5b6170' };
  const used = d.partitions.map((p) => `<i style="flex:${Math.max(p.size / d.size, 0.004)};background:${colors[p.os ?? 'data']}" title="${esc(p.label ?? p.path)}"></i>`);
  const rest = Math.max(0, 1 - d.partitions.reduce((a, p) => a + p.size, 0) / d.size);
  if (rest > 0.002) used.push(`<i class="free" style="flex:${rest}"></i>`);
  return used.join('');
}

void router;
