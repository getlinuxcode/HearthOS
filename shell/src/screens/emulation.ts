import { api, type EmuSystem, type FtpStatus, type RomFolder } from '../api';
import { esc, h } from '../dom';
import { loadLibrary } from '../state';
import { setBackground } from '../ui/chrome';
import { focusFirst, setFocus } from '../ui/focus';
import { confirmDialog, openModal } from '../ui/modal';
import { router, type Layer } from '../ui/router';
import { toast } from '../ui/toast';
import { setSystemShorts } from './home';
import { settingsScreen } from './settings';

// Émulation : les moteurs (cœurs libretro) s'installent ici ; leur interface n'est jamais montrée.
// Les dossiers ROM sont surveillés : un fichier déposé (FTP, clé USB…) apparaît tout seul.

export function emulationScreen(): Layer {
  const el = h(`
    <section class="emu v-scroll">
      <h1 class="page-title">Émulateurs</h1>
      <h2 class="section-title">Dossiers de jeux</h2>
      <div class="folders"></div>
      <h2 class="section-title">Systèmes</h2>
      <div class="sys-grid" data-focus-memory></div>
      <div class="ftp-card card"></div>
    </section>`);
  const foldersEl = el.querySelector<HTMLElement>('.folders')!;
  const sysEl = el.querySelector<HTMLElement>('.sys-grid')!;
  const ftpEl = el.querySelector<HTMLElement>('.ftp-card')!;
  let systems: EmuSystem[] = [];
  const installing = new Set<string>();

  const sysName = (id: string) => (id === 'auto' ? 'Détection automatique' : systems.find((s) => s.id === id)?.name ?? id);

  const renderFolders = (folders: RomFolder[]) => {
    foldersEl.innerHTML = `
      ${folders
        .map(
          (f) => `
        <button class="row folder-row" data-focus data-folder="${esc(f.id)}">
          <span class="row-main"><span class="row-label">${esc(f.path)}</span>
          <span class="row-desc">${esc(sysName(f.system))} · ${f.romCount} jeu(x) ${f.watching ? '· <span class="live">● surveillé</span>' : ''}</span></span>
          <span class="row-right"><span class="chev">›</span></span>
        </button>`,
        )
        .join('')}
      <button class="row add-row" data-focus data-act="add-folder"><span class="row-main"><span class="row-label">＋ Ajouter un dossier</span><span class="row-desc">Disque, clé USB, dossier réseau…</span></span></button>`;
  };

  const renderSystems = () => {
    sysEl.innerHTML = systems
      .map((s) => {
        const missingBios = s.bios?.filter((b) => !b.present) ?? [];
        const status = installing.has(s.id)
          ? '<span class="sys-status busy"><span class="spinner small"></span>Installation…</span>'
          : s.coreInstalled
            ? `<span class="sys-status ok">Prêt</span>`
            : `<span class="sys-status">Installer</span>`;
        return `
        <button class="sys-card ${s.coreInstalled ? 'ready' : ''}" data-focus data-sys="${s.id}">
          <span class="sys-short">${esc(s.short)}</span>
          <span class="sys-name">${esc(s.name)}</span>
          <span class="sys-meta">${s.romCount} jeu(x) · ${esc(s.maker)}</span>
          ${status}
          ${missingBios.length ? `<span class="sys-bios">BIOS manquant</span>` : ''}
        </button>`;
      })
      .join('');
  };

  const renderFtp = (f: FtpStatus | null) => {
    ftpEl.innerHTML = f
      ? `<div><b>Transfert depuis un PC (FTP)</b>
          <p class="dim small">${
            f.enabled
              ? `Actif · ftp://${esc(f.addresses[0] ?? '?')}:${f.port} · utilisateur <b>${esc(f.user)}</b> · déposez vos ROM dans <b>roms/</b>, vos BIOS dans <b>bios/</b>.`
              : 'Désactivé. Activez-le pour envoyer ROM, BIOS et fichiers depuis votre PC.'
          }</p></div>
         <button class="btn-pill" data-focus data-act="ftp">${f.enabled ? 'Gérer' : 'Activer'}</button>`
      : '';
  };

  const reload = async () => {
    const [sys, folders, ftp] = await Promise.all([
      api.get<EmuSystem[]>('/emu/systems'),
      api.get<RomFolder[]>('/emu/folders'),
      api.get<FtpStatus>('/ftp').catch(() => null),
    ]);
    systems = sys;
    setSystemShorts(Object.fromEntries(sys.map((s) => [s.id, s.short])));
    renderFolders(folders);
    renderSystems();
    renderFtp(ftp);
  };

  const systemDialog = (s: EmuSystem) => {
    const bios = s.bios?.length
      ? `<p><b>BIOS :</b> ${s.bios.map((b) => `${esc(b.file)} ${b.present ? '✓' : '<span class="err">manquant</span>'}`).join(', ')}<br><span class="dim small">À déposer dans le dossier <b>bios/</b> (par FTP par exemple).</span></p>`
      : '';
    openModal({
      title: s.name,
      body: `
        <p>Moteur : <b>${esc(s.core)}</b> (libretro) · ${s.coreInstalled ? 'installé' : 'non installé'}</p>
        <p class="dim small">Formats reconnus : ${esc(s.extensions.join(' ') || '.zip (jeux d’arcade)')} — ainsi que .cue/.chd/.iso/.zip dans un dossier attribué à ce système.</p>
        ${bios}`,
      actions: s.coreInstalled
        ? [{ label: 'Fermer', primary: true }]
        : [
            { label: 'Annuler' },
            {
              label: 'Installer le moteur',
              primary: true,
              run: async () => {
                installing.add(s.id);
                renderSystems();
                try {
                  systems = await api.post<EmuSystem[]>(`/emu/systems/${s.id}/install`);
                  toast(`${s.name} prêt`, 'success');
                } catch (e) {
                  toast((e as Error).message, 'error');
                } finally {
                  installing.delete(s.id);
                  renderSystems();
                  const again = sysEl.querySelector<HTMLElement>(`[data-sys="${s.id}"]`);
                  if (again) setFocus(again, { silent: true });
                }
              },
            },
          ],
    });
  };

  const chooseSystem = (current: string): Promise<string | null> =>
    new Promise((resolve) => {
      let picked: string | null = null;
      const box = h(`<div class="sys-pick">${[{ id: 'auto', short: 'AUTO', name: 'Détection automatique' }, ...systems]
        .map((s) => `<button class="sys-chip ${s.id === current ? 'on' : ''}" data-focus data-id="${s.id}"><b>${esc(s.short)}</b><span>${esc(s.name)}</span></button>`)
        .join('')}</div>`);
      const layer = openModal({ title: 'Ce dossier contient…', wide: true, body: box, onClose: () => resolve(picked) });
      box.addEventListener('click', (e) => {
        const id = (e.target as HTMLElement).closest<HTMLElement>('[data-id]')?.dataset.id;
        if (!id) return;
        picked = id;
        router.closeModal(layer);
      });
      setFocus(box.querySelector<HTMLElement>('.on') ?? box.querySelector<HTMLElement>('[data-focus]'), { silent: true });
    });

  const folderDialog = (id: string) => {
    openModal({
      title: 'Dossier de jeux',
      actions: [
        {
          label: 'Changer le système',
          run: async () => {
            const folders = await api.get<RomFolder[]>('/emu/folders');
            const f = folders.find((x) => x.id === id);
            const sys = await chooseSystem(f?.system ?? 'auto');
            if (sys) renderFolders(await api.post<RomFolder[]>(`/emu/folders/${id}`, { system: sys }));
            await loadLibrary();
          },
        },
        {
          label: 'Rescanner',
          run: async () => {
            renderFolders(await api.post<RomFolder[]>('/emu/rescan'));
            await loadLibrary();
            toast('Dossiers rescannés', 'success');
          },
        },
        {
          label: 'Retirer de la bibliothèque',
          danger: true,
          run: async () => {
            if (!(await confirmDialog('Retirer ce dossier ?', 'Les fichiers ne sont pas supprimés, ils ne seront juste plus affichés.', 'Retirer', true))) return;
            renderFolders(await api.post<RomFolder[]>(`/emu/folders/${id}/remove`));
            await loadLibrary();
          },
        },
      ],
    });
  };

  const addFolder = async () => {
    const dir = await browseFolder();
    if (!dir) return;
    const sys = await chooseSystem('auto');
    if (!sys) return;
    try {
      renderFolders(await api.post<RomFolder[]>('/emu/folders', { path: dir, system: sys }));
      await loadLibrary();
      toast('Dossier ajouté et surveillé', 'success');
    } catch (e) {
      toast((e as Error).message, 'error');
    }
  };

  el.addEventListener('click', (e) => {
    const t = e.target as HTMLElement;
    const sys = t.closest<HTMLElement>('[data-sys]')?.dataset.sys;
    if (sys) return systemDialog(systems.find((s) => s.id === sys)!);
    const folder = t.closest<HTMLElement>('[data-folder]')?.dataset.folder;
    if (folder) return folderDialog(folder);
    const act = t.closest<HTMLElement>('[data-act]')?.dataset.act;
    if (act === 'add-folder') void addFolder();
    if (act === 'ftp') router.push(settingsScreen('files'));
  });

  return {
    el,
    async onEnter() {
      setBackground(null);
      try {
        await reload();
      } catch (e) {
        toast((e as Error).message, 'error');
      }
      focusFirst(el);
    },
    onResume: () => void reload(),
  };
}

/** Navigateur de dossiers à la manette. */
function browseFolder(start?: string): Promise<string | null> {
  return new Promise((resolve) => {
    let result: string | null = null;
    const box = h(`<div class="browser"><div class="br-path"></div><div class="br-list v-scroll"></div></div>`);
    const pathEl = box.querySelector<HTMLElement>('.br-path')!;
    const list = box.querySelector<HTMLElement>('.br-list')!;
    let current = '';

    const load = async (p?: string) => {
      const r = await api.get<{ path: string; parent: string | null; dirs: string[] }>(`/fs/browse${p ? `?path=${encodeURIComponent(p)}` : ''}`);
      current = r.path;
      pathEl.textContent = r.path;
      list.innerHTML =
        `<button class="row br-pick" data-focus data-pick><span class="row-label">✓ Choisir ce dossier</span></button>` +
        (r.parent ? `<button class="row" data-focus data-dir="${esc(r.parent)}"><span class="row-label">↰ Dossier parent</span></button>` : '') +
        r.dirs.map((d) => `<button class="row" data-focus data-dir="${esc(r.path.replace(/[\\/]$/, '') + (r.path.includes('\\') ? '\\' : '/') + d)}"><span class="row-label">📁 ${esc(d)}</span></button>`).join('');
      focusFirst(list);
    };

    const layer = openModal({
      title: 'Choisir un dossier',
      wide: true,
      body: box,
      onClose: () => resolve(result),
      onAction: (e, t) => {
        if (t === 'press' && e.action === 'y') {
          result = current;
          router.closeModal(layer);
          return true;
        }
        return false;
      },
      hints: [{ action: 'confirm', label: 'Ouvrir' }, { action: 'y', label: 'Choisir ce dossier' }, { action: 'back', label: 'Annuler' }],
    });
    list.addEventListener('click', (e) => {
      const t = (e.target as HTMLElement).closest<HTMLElement>('button');
      if (!t) return;
      if (t.hasAttribute('data-pick')) {
        result = current;
        router.closeModal(layer);
      } else if (t.dataset.dir) void load(t.dataset.dir);
    });
    void load(start);
  });
}
