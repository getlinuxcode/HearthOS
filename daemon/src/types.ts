// Types partagés entre le daemon et le shell (le shell les importe en `import type`).
// Ce fichier ne doit contenir AUCUN import Node.

export type Mode = 'dev' | 'live' | 'installed';

export interface SystemInfo {
  mode: Mode;
  mock: boolean;
  platform: string;
  hostname: string;
  kernel: string;
  cpu: string;
  gpu: string[];
  memoryGB: number;
  version: string;
  windowsDetected: boolean;
}

export type Upscaler = 'off' | 'fsr' | 'nis' | 'integer';

export interface DisplaySettings {
  width: number;
  height: number;
  refresh: number;
  vrr: boolean;
  hdr: boolean;
  upscaler: Upscaler;
  fpsLimit: number;
}

export interface GameOptions {
  compatTool: string;
  mangohud: boolean;
  gamescopeFsr: boolean;
}

export interface Settings {
  onboarded: boolean;
  uiScale: number;
  sounds: boolean;
  timezone: string;
  clock24h: boolean;
  keyboardLayout: 'azerty' | 'qwerty';
  display: DisplaySettings;
  games: Record<string, GameOptions>;
}

export interface NetworkStatus {
  connected: boolean;
  type: 'ethernet' | 'wifi' | 'none';
  name?: string;
  signal?: number;
  internet: boolean;
  addresses: string[];
}

export interface WifiNetwork {
  ssid: string;
  signal: number;
  secure: boolean;
  active: boolean;
}

export interface Partition {
  path: string;
  size: number;
  fstype?: string;
  label?: string;
  os?: 'windows' | 'linux' | 'efi' | 'data';
  used?: number;
  /** Partition chiffrée BitLocker (non réductible) */
  bitlocker?: boolean;
}

export interface Disk {
  path: string;
  model: string;
  size: number;
  transport: string;
  removable: boolean;
  partitions: Partition[];
  freeSpace: number;
  detectedOS: string[];
  shrinkable?: { partition: string; maxBytes: number };
  isBootMedia?: boolean;
}

export type InstallMode = 'alongside' | 'erase' | 'free' | 'manual';

export interface InstallPlan {
  disk: string;
  mode: InstallMode;
  sizeGB: number;
  /** Mode manuel : partitions existantes à utiliser */
  manual?: { root: string; efi?: string; formatEfi?: boolean };
}

export interface InstallProgress {
  state: 'idle' | 'running' | 'done' | 'error';
  step: string;
  percent: number;
  simulated: boolean;
  error?: string;
}

export interface DisplayMode {
  width: number;
  height: number;
  refresh: number[];
}

export interface DisplayInfo {
  modes: DisplayMode[];
  output: string;
  simulated: boolean;
}

export interface SteamAccount {
  steamId: string;
  accountName: string;
  personaName: string;
  avatarUrl?: string;
}

export interface SteamLoginStatus {
  state: 'idle' | 'pending' | 'scanned' | 'done' | 'timeout' | 'error';
  account?: SteamAccount;
  error?: string;
}

export type GameSource = 'steam' | 'rom' | 'epic';

export interface Game {
  /** Identifiant global : "steam:570", "rom:<hash>" */
  id: string;
  name: string;
  source: GameSource;
  installed: boolean;
  playtimeMinutes: number;
  lastPlayed: number;
  /** Steam uniquement */
  appid?: number;
  /** Epic uniquement (nom technique utilisé par legendary) */
  appName?: string;
  /** ROM uniquement */
  system?: string;
  path?: string;
  coverUrl?: string;
  demo?: boolean;
}

export interface Library {
  account?: SteamAccount;
  epic?: { name: string };
  games: Game[];
  demo: boolean;
}

export interface StoreItem {
  appid: number;
  name: string;
  image: string;
  priceFinal?: number;
  priceInitial?: number;
  discount?: number;
  currency?: string;
}

export interface StoreSection {
  id: string;
  title: string;
  items: StoreItem[];
}

export interface AppDetails {
  appid: number;
  name: string;
  description: string;
  headerImage: string;
  developers: string[];
  genres: string[];
  releaseDate?: string;
  price?: string;
  isFree: boolean;
  screenshots: string[];
  metacritic?: number;
}

// ---- Émulation ----

export interface EmuSystem {
  id: string;
  name: string;
  short: string;
  maker: string;
  extensions: string[];
  core: string;
  corePackage: string;
  coreInstalled: boolean;
  /** Émulateur autonome téléchargé (Eden…) : nom et version installée */
  standalone?: { name: string; version?: string };
  bios?: { file: string; present: boolean }[];
  romCount: number;
}

export interface RomFolder {
  id: string;
  path: string;
  /** "auto" = détection par extension / nom de sous-dossier */
  system: string;
  watching: boolean;
  romCount: number;
}

export interface UpdateStatus {
  current: string;
  channel: string;
  state: 'idle' | 'checking' | 'uptodate' | 'available' | 'downloading' | 'installing' | 'ready' | 'error';
  progress: number;
  available?: string;
  installed?: string;
  notes?: string;
  size?: number;
  checkedAt?: number;
  error?: string;
  rollback?: string;
  systemUpdatable: boolean;
  system?: 'running' | 'done' | 'error';
}

export interface FtpStatus {
  enabled: boolean;
  port: number;
  user: string;
  password: string;
  root: string;
  addresses: string[];
  error?: string;
}
