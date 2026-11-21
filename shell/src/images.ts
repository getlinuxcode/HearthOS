import { esc } from './dom';
import type { Game } from './api';

const CDN = 'https://cdn.cloudflare.steamstatic.com/steam/apps';

export const steamImg = {
  portrait: (id: number) => `${CDN}/${id}/library_600x900.jpg`,
  portrait2x: (id: number) => `${CDN}/${id}/library_600x900_2x.jpg`,
  hero: (id: number) => `${CDN}/${id}/library_hero.jpg`,
  header: (id: number) => `${CDN}/${id}/header.jpg`,
  logo: (id: number) => `${CDN}/${id}/logo.png`,
};

export function coverImg(g: Game, cls = 'cover'): string {
  if (g.source === 'steam' && g.appid) {
    return `<img class="${cls}" src="${steamImg.portrait(g.appid)}" data-fallback-src="${steamImg.header(g.appid)}" data-fallback-text="${esc(g.name)}" alt="" loading="lazy">`;
  }
  return `<img class="${cls} cover-rom" src="${esc(g.coverUrl ?? '')}" data-fallback-text="${esc(g.name)}" alt="" loading="lazy">`;
}

export function heroUrl(g: Game): string | null {
  if (g.source === 'steam' && g.appid) return steamImg.hero(g.appid);
  return null;
}
