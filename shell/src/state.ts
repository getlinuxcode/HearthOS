import { api, type Library, type NetworkStatus, type Settings, type SystemInfo } from './api';

export const state = {
  info: null as SystemInfo | null,
  settings: null as Settings | null,
  library: null as Library | null,
  network: null as NetworkStatus | null,
};

const listeners = new Set<() => void>();
export function onStateChange(fn: () => void) {
  listeners.add(fn);
  return () => listeners.delete(fn);
}
export function notify() {
  listeners.forEach((f) => f());
}

export async function saveSettings(patch: Partial<Settings>) {
  state.settings = await api.post<Settings>('/settings', patch);
  applySettings();
  notify();
}

export function applySettings() {
  const s = state.settings;
  if (!s) return;
  document.documentElement.style.setProperty('--ui-scale', String(s.uiScale));
}

export async function loadLibrary() {
  state.library = await api.get<Library>('/library');
  notify();
  return state.library;
}

export async function refreshNetwork() {
  try {
    state.network = await api.get<NetworkStatus>('/network/status');
  } catch {
    state.network = null;
  }
  notify();
}
