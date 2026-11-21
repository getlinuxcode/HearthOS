import { api, type AppDetails, type StoreItem, type StoreSection } from '../api';
import { esc, fmtPrice, h, imgFallbacks } from '../dom';
import { steamImg } from '../images';
import { setBackground } from '../ui/chrome';
import { focusFirst } from '../ui/focus';
import { keyboard } from '../ui/keyboard';
import { openModal } from '../ui/modal';
import { router, type Layer } from '../ui/router';
import { toast } from '../ui/toast';

// Boutique Steam affichée dans notre interface. L'achat lui-même se termine dans Steam
// (client ou téléphone) : Valve ne propose pas d'API d'achat aux applications tierces.

function itemTile(i: StoreItem): string {
  const price = i.priceFinal !== undefined ? fmtPrice(i.priceFinal, i.currency) : '';
  return `
    <button class="store-tile" data-focus data-appid="${i.appid}">
      <img src="${esc(i.image)}" data-fallback-text="${esc(i.name)}" alt="" loading="lazy">
      <div class="st-info">
        <span class="st-name">${esc(i.name)}</span>
        <span class="st-price">${i.discount ? `<em>-${i.discount}%</em>` : ''}${i.discount && i.priceInitial ? `<s>${fmtPrice(i.priceInitial, i.currency)}</s>` : ''}<b>${price}</b></span>
      </div>
    </button>`;
}

function sectionsHtml(sections: StoreSection[]) {
  return sections
    .map((s) => `<div class="store-section"><h2>${esc(s.title)}</h2><div class="store-row h-scroll" data-focus-memory>${s.items.map(itemTile).join('')}</div></div>`)
    .join('');
}

export function storeScreen(results?: { term: string; items: StoreItem[] }): Layer {
  const el = h(`
    <section class="store v-scroll">
      <div class="store-head">
        <h1>${results ? `Résultats pour « ${esc(results.term)} »` : 'Boutique Steam'}</h1>
        <button class="search-btn" data-focus data-act="search">🔍  Rechercher un jeu</button>
      </div>
      <div class="store-body"><div class="loading">Chargement de la boutique…</div></div>
    </section>`);
  const body = el.querySelector<HTMLElement>('.store-body')!;

  el.addEventListener('click', async (e) => {
    const t = e.target as HTMLElement;
    const tile = t.closest<HTMLElement>('[data-appid]');
    if (tile) return router.push(storeItemScreen(Number(tile.dataset.appid)));
    if (t.closest('[data-act="search"]')) {
      const term = await keyboard({ title: 'Rechercher dans la boutique', placeholder: 'Nom du jeu', okLabel: 'Rechercher', value: results?.term });
      if (!term?.trim()) return;
      try {
        const items = await api.get<StoreItem[]>(`/store/search?q=${encodeURIComponent(term.trim())}`);
        if (results) router.replace(storeScreen({ term, items }));
        else router.push(storeScreen({ term, items }));
      } catch (err) {
        toast((err as Error).message, 'error');
      }
    }
  });

  el.addEventListener('focusin-nav', (e) => {
    const id = (e.target as HTMLElement).dataset.appid;
    if (id) setBackground(steamImg.hero(Number(id)));
  });

  return {
    el,
    async onEnter() {
      try {
        const sections = results ? [{ id: 'r', title: `${results.items.length} jeu(x)`, items: results.items }] : await api.get<StoreSection[]>('/store/featured');
        body.innerHTML = sections.some((s) => s.items.length) ? sectionsHtml(sections) : '<p class="dim">Aucun résultat.</p>';
        imgFallbacks(body);
        focusFirst(body.querySelector('.store-tile') ? body : el);
      } catch (err) {
        body.innerHTML = `<p class="dim">${esc((err as Error).message)} — vérifiez la connexion Internet.</p>`;
      }
    },
    onAction(e, type) {
      if (type === 'press' && e.action === 'y') {
        (el.querySelector('[data-act="search"]') as HTMLElement).click();
        return true;
      }
      return false;
    },
    hints: () => [{ action: 'confirm', label: 'Voir' }, { action: 'y', label: 'Rechercher' }, { action: 'back', label: 'Retour' }],
  };
}

export function storeItemScreen(appid: number): Layer {
  const el = h(`<section class="store-item"><div class="loading">Chargement…</div></section>`);
  return {
    el,
    async onEnter() {
      setBackground(steamImg.hero(appid));
      let d: AppDetails;
      try {
        d = await api.get<AppDetails>(`/store/app/${appid}`);
      } catch (e) {
        el.innerHTML = `<p class="dim">${esc((e as Error).message)}</p>`;
        return;
      }
      el.innerHTML = `
        <div class="si-main">
          <img class="si-header" src="${esc(d.headerImage)}" data-fallback-text="${esc(d.name)}" alt="">
          <div class="si-text">
            <h1>${esc(d.name)}</h1>
            <p class="si-desc">${esc(d.description)}</p>
            <div class="chips">${d.genres.map((g) => `<span class="chip">${esc(g)}</span>`).join('')}${d.metacritic ? `<span class="chip mc">Metacritic ${d.metacritic}</span>` : ''}</div>
            <p class="dim small">${esc(d.developers.join(', '))}${d.releaseDate ? ` · ${esc(d.releaseDate)}` : ''}</p>
            <div class="si-buy">
              <span class="si-price">${esc(d.price ?? 'Prix indisponible')}</span>
              <button class="btn-pill primary xl" data-focus data-autofocus data-act="buy">${d.isFree ? 'Obtenir' : 'Acheter'}</button>
            </div>
          </div>
        </div>
        <div class="si-shots h-scroll" data-focus-memory>${d.screenshots.map((s) => `<button class="shot" data-focus><img src="${esc(s)}" alt="" loading="lazy"></button>`).join('')}</div>`;
      imgFallbacks(el);
      el.querySelector('[data-act="buy"]')!.addEventListener('click', () => buyDialog(d));
      focusFirst(el);
    },
    onResume: () => setBackground(steamImg.hero(appid)),
  };
}

async function buyDialog(d: AppDetails) {
  const url = `https://store.steampowered.com/app/${d.appid}`;
  const qr = await api.get<{ svg: string }>(`/qr?text=${encodeURIComponent(url)}`).catch(() => null);
  openModal({
    title: d.isFree ? `Obtenir ${d.name}` : `Acheter ${d.name}`,
    wide: true,
    body: `
      <div class="buy-grid">
        <div class="buy-qr">${qr?.svg ?? ''}<span>Finir sur mon téléphone</span></div>
        <div class="buy-text">
          <p>Le paiement se fait chez Steam, de façon sécurisée. Deux possibilités :</p>
          <ul>
            <li><b>Scannez le QR code</b> et payez dans l’application Steam ou le navigateur du téléphone. Le jeu apparaît ensuite ici.</li>
            <li><b>Ouvrir dans Steam</b> : affiche la page d’achat du client Steam sur la TV.</li>
          </ul>
        </div>
      </div>`,
    actions: [
      { label: 'Fermer' },
      {
        label: 'Ouvrir dans Steam',
        primary: true,
        run: async () => {
          await api.post(`/store/app/${d.appid}/open`).catch((e) => toast(e.message, 'error'));
        },
      },
    ],
  });
}
