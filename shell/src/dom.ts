export function h<T extends HTMLElement = HTMLElement>(html: string): T {
  const t = document.createElement('template');
  t.innerHTML = html.trim();
  return t.content.firstElementChild as T;
}

export function esc(s: unknown): string {
  return String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);
}

export function qs<T extends HTMLElement = HTMLElement>(root: ParentNode, sel: string): T {
  const el = root.querySelector<T>(sel);
  if (!el) throw new Error(`élément introuvable : ${sel}`);
  return el;
}

/**
 * Images avec repli : data-fallback-src (2e URL) puis data-fallback-text (tuile texte).
 * À appeler après chaque rendu contenant des <img>.
 */
export function imgFallbacks(root: ParentNode) {
  root.querySelectorAll<HTMLImageElement>('img[data-fallback-text]').forEach((img) => {
    if ((img as any)._fb) return;
    (img as any)._fb = true;
    img.addEventListener('error', () => {
      const alt = img.dataset.fallbackSrc;
      if (alt && !img.dataset.triedAlt) {
        img.dataset.triedAlt = '1';
        img.src = alt;
        return;
      }
      const div = document.createElement('div');
      div.className = `img-fallback ${img.className}`;
      div.textContent = img.dataset.fallbackText ?? '';
      img.replaceWith(div);
    });
  });
}

export const GB = 1024 ** 3;
export const fmtGB = (bytes: number) => (bytes >= 1024 * GB ? `${(bytes / 1024 / GB).toFixed(1)} To` : `${Math.round(bytes / GB)} Go`);

export function fmtPlaytime(min: number) {
  if (!min) return 'Jamais joué';
  if (min < 60) return `${min} min`;
  return `${Math.round(min / 60)} h de jeu`;
}

export function fmtPrice(cents: number | undefined, currency = 'EUR') {
  if (cents === undefined) return '';
  if (cents === 0) return 'Gratuit';
  return new Intl.NumberFormat('fr-FR', { style: 'currency', currency }).format(cents / 100);
}
