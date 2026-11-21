// Catalogue des systèmes émulés. Le « moteur » est un cœur libretro lancé sans interface.
// corePackage = paquet Arch qui fournit le cœur (/usr/lib/libretro/<core>_libretro.so).
// thumbs = dossier du dépôt libretro-thumbnails pour les jaquettes.

export interface SystemDef {
  id: string;
  name: string;
  short: string;
  maker: string;
  extensions: string[];
  /** Noms de sous-dossiers reconnus en détection automatique */
  aliases: string[];
  core: string;
  corePackage: string;
  thumbs: string;
  bios?: string[];
  /** Émulateur autonome (AppImage téléchargée) au lieu d'un cœur libretro */
  standalone?: string;
  /** Extensions reconnues seulement dans le dossier de ce système (roms/switch2/…) */
  folderExtensions?: string[];
}

export const SYSTEMS: SystemDef[] = [
  { id: 'nes', name: 'Nintendo NES', short: 'NES', maker: 'Nintendo', extensions: ['.nes', '.fds', '.unf'], aliases: ['nes', 'famicom'], core: 'mesen', corePackage: 'libretro-mesen', thumbs: 'Nintendo - Nintendo Entertainment System' },
  { id: 'snes', name: 'Super Nintendo', short: 'SNES', maker: 'Nintendo', extensions: ['.sfc', '.smc'], aliases: ['snes', 'superfamicom', 'sfc'], core: 'snes9x', corePackage: 'libretro-snes9x', thumbs: 'Nintendo - Super Nintendo Entertainment System' },
  { id: 'n64', name: 'Nintendo 64', short: 'N64', maker: 'Nintendo', extensions: ['.n64', '.z64', '.v64'], aliases: ['n64'], core: 'mupen64plus_next', corePackage: 'libretro-mupen64plus-next', thumbs: 'Nintendo - Nintendo 64' },
  { id: 'gb', name: 'Game Boy', short: 'GB', maker: 'Nintendo', extensions: ['.gb'], aliases: ['gb', 'gameboy'], core: 'gambatte', corePackage: 'libretro-gambatte', thumbs: 'Nintendo - Game Boy' },
  { id: 'gbc', name: 'Game Boy Color', short: 'GBC', maker: 'Nintendo', extensions: ['.gbc'], aliases: ['gbc'], core: 'gambatte', corePackage: 'libretro-gambatte', thumbs: 'Nintendo - Game Boy Color' },
  { id: 'gba', name: 'Game Boy Advance', short: 'GBA', maker: 'Nintendo', extensions: ['.gba'], aliases: ['gba'], core: 'mgba', corePackage: 'libretro-mgba', thumbs: 'Nintendo - Game Boy Advance' },
  { id: 'nds', name: 'Nintendo DS', short: 'DS', maker: 'Nintendo', extensions: ['.nds'], aliases: ['nds', 'ds'], core: 'melonds', corePackage: 'libretro-melonds', thumbs: 'Nintendo - Nintendo DS' },
  { id: 'gc', name: 'GameCube / Wii', short: 'GC', maker: 'Nintendo', extensions: ['.rvz', '.gcz', '.wbfs'], aliases: ['gc', 'gamecube', 'wii'], core: 'dolphin', corePackage: 'libretro-dolphin', thumbs: 'Nintendo - GameCube' },
  { id: 'mastersystem', name: 'Master System', short: 'SMS', maker: 'Sega', extensions: ['.sms'], aliases: ['mastersystem', 'sms'], core: 'genesis_plus_gx', corePackage: 'libretro-genesis-plus-gx', thumbs: 'Sega - Master System - Mark III' },
  { id: 'megadrive', name: 'Mega Drive', short: 'MD', maker: 'Sega', extensions: ['.md', '.gen', '.smd'], aliases: ['megadrive', 'genesis', 'md'], core: 'genesis_plus_gx', corePackage: 'libretro-genesis-plus-gx', thumbs: 'Sega - Mega Drive - Genesis' },
  { id: 'dreamcast', name: 'Dreamcast', short: 'DC', maker: 'Sega', extensions: ['.gdi', '.cdi'], aliases: ['dreamcast', 'dc'], core: 'flycast', corePackage: 'libretro-flycast', thumbs: 'Sega - Dreamcast', bios: ['dc/dc_boot.bin'] },
  { id: 'psx', name: 'PlayStation', short: 'PS1', maker: 'Sony', extensions: ['.pbp'], aliases: ['psx', 'ps1', 'playstation'], core: 'mednafen_psx_hw', corePackage: 'libretro-beetle-psx-hw', thumbs: 'Sony - PlayStation', bios: ['scph5501.bin'] },
  { id: 'psp', name: 'PlayStation Portable', short: 'PSP', maker: 'Sony', extensions: ['.cso'], aliases: ['psp'], core: 'ppsspp', corePackage: 'libretro-ppsspp', thumbs: 'Sony - PlayStation Portable' },
  { id: 'pcengine', name: 'PC Engine', short: 'PCE', maker: 'NEC', extensions: ['.pce'], aliases: ['pcengine', 'tg16'], core: 'mednafen_pce_fast', corePackage: 'libretro-beetle-pce-fast', thumbs: 'NEC - PC Engine - TurboGrafx 16' },
  { id: 'switch', name: 'Nintendo Switch', short: 'Switch', maker: 'Nintendo', extensions: ['.nsp', '.xci', '.nro'], aliases: ['switch', 'ns', 'nx'], core: 'eden', corePackage: '', standalone: 'eden', thumbs: '', bios: ['switch/prod.keys', 'switch/firmware'] },
  { id: 'switch2', name: 'Nintendo Switch 2 (expérimental)', short: 'Switch 2', maker: 'Nintendo', extensions: [], folderExtensions: ['.nsp', '.xci'], aliases: ['switch2', 'ns2', 'nx2'], core: 'eden-nx2', corePackage: '', standalone: 'eden-nx2', thumbs: '', bios: ['switch2/prod.keys', 'switch2/firmware'] },
  { id: 'arcade', name: 'Arcade (MAME)', short: 'ARC', maker: 'Arcade', extensions: [], aliases: ['arcade', 'fbneo', 'mame'], core: 'mame', corePackage: 'libretro-mame', thumbs: 'MAME' },
];

/**
 * Extensions partagées entre plusieurs systèmes (.cue, .chd, .iso, .zip, .7z, .m3u) :
 * elles ne sont reconnues que dans un dossier dont le système est fixé
 * ou dont le nom de sous-dossier correspond (roms/psx/…).
 */
export const AMBIGUOUS_EXT = ['.cue', '.chd', '.iso', '.zip', '.7z', '.m3u', '.bin'];

export const byId = new Map(SYSTEMS.map((s) => [s.id, s]));

const extIndex = new Map<string, SystemDef>();
for (const s of SYSTEMS) for (const e of s.extensions) extIndex.set(e, s);

const aliasIndex = new Map<string, SystemDef>();
for (const s of SYSTEMS) for (const a of s.aliases) aliasIndex.set(a, s);

export function systemForExt(ext: string): SystemDef | undefined {
  return extIndex.get(ext.toLowerCase());
}

export function systemForFolderName(name: string): SystemDef | undefined {
  return aliasIndex.get(name.toLowerCase().replace(/[^a-z0-9]/g, ''));
}

export function accepts(sys: SystemDef, ext: string): boolean {
  ext = ext.toLowerCase();
  return sys.extensions.includes(ext) || !!sys.folderExtensions?.includes(ext) || AMBIGUOUS_EXT.includes(ext);
}
