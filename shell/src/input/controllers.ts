export type Family = 'ds4' | 'dualsense' | 'ds3' | 'xbox' | 'xbox360' | 'switch' | 'steam' | 'generic';

export interface ControllerInfo {
  family: Family;
  name: string;
  vendor?: string;
  product?: string;
}

/** Style des glyphes de boutons (formes PlayStation, lettres Xbox, disposition Nintendo…). */
export type GlyphStyle = 'ps' | 'xbox' | 'nintendo' | 'generic' | 'keyboard';

export function glyphStyle(f: Family | 'keyboard'): GlyphStyle {
  switch (f) {
    case 'ds4':
    case 'dualsense':
    case 'ds3':
      return 'ps';
    case 'xbox':
    case 'xbox360':
    case 'steam':
      return 'xbox';
    case 'switch':
      return 'nintendo';
    case 'keyboard':
      return 'keyboard';
    default:
      return 'generic';
  }
}

const SONY = '054c';
const MICROSOFT = '045e';
const NINTENDO = '057e';
const VALVE = '28de';

/**
 * Identifie une manette à partir de Gamepad.id.
 * Chromium : "DualSense Wireless Controller (STANDARD GAMEPAD Vendor: 054c Product: 0ce6)"
 * Firefox  : "054c-0ce6-DualSense Wireless Controller"
 * Windows XInput : "Xbox 360 Controller (XInput STANDARD GAMEPAD)"
 */
export function identify(id: string): ControllerInfo {
  const m = id.match(/Vendor:\s*([0-9a-f]{4}).*?Product:\s*([0-9a-f]{4})/i) ?? id.match(/^([0-9a-f]{1,4})-([0-9a-f]{1,4})-/i);
  const vendor = m?.[1].toLowerCase().padStart(4, '0');
  const product = m?.[2].toLowerCase().padStart(4, '0');
  const lower = id.toLowerCase();
  const mk = (family: Family, name: string): ControllerInfo => ({ family, name, vendor, product });

  if (vendor === SONY) {
    if (product === '0ce6') return mk('dualsense', 'DualSense');
    if (product === '0df2') return mk('dualsense', 'DualSense Edge');
    if (['05c4', '09cc', '0ba0'].includes(product!)) return mk('ds4', 'DualShock 4');
    if (product === '0268') return mk('ds3', 'DualShock 3');
    return mk('ds4', 'Manette PlayStation');
  }
  if (vendor === MICROSOFT) {
    if (['028e', '028f', '0719', '0291'].includes(product!)) return mk('xbox360', 'Manette Xbox 360');
    if (['02e3', '0b00', '0b05', '0b22'].includes(product!)) return mk('xbox', 'Manette Xbox Elite');
    return mk('xbox', 'Manette Xbox');
  }
  if (vendor === NINTENDO) return mk('switch', product === '2009' ? 'Manette Pro Switch' : 'Joy-Con');
  if (vendor === VALVE) return mk('steam', product === '1205' ? 'Steam Deck' : 'Steam Controller');

  if (lower.includes('dualsense')) return mk('dualsense', 'DualSense');
  if (lower.includes('wireless controller')) return mk('ds4', 'Manette PlayStation');
  if (/xbox|xinput/.test(lower)) return mk('xbox', 'Manette Xbox');
  if (lower.includes('pro controller')) return mk('switch', 'Manette Pro Switch');

  const clean = id.replace(/\(.*?\)/g, '').replace(/^[0-9a-f]+-[0-9a-f]+-/i, '').trim();
  return mk('generic', clean || 'Manette');
}
