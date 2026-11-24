import { App } from '@capacitor/app';
import { Capacitor } from '@capacitor/core';
import { isNativeApp } from './native';

// 앱 업데이트 안내 (1.3 패치 1-F, SPEC 6-99). 네이티브 앱에서만. DB 없음 — 배포 사이트의 /version.json 하나만 본다.

/** 앱 안의 화면은 앱 파일이라 상대 주소가 앱 안의 (오래된) 파일을 가리킨다 → 배포 사이트의 주소를 쓴다 */
export const VERSION_URL = 'https://top-lane-counter.pages.dev/version.json';
export const FETCH_TIMEOUT_MS = 4000;
export const SNOOZE_MS = 24 * 60 * 60 * 1000;
export const SNOOZE_KEY = 'app-update-snooze';

/** "1.10.0" → [1, 10, 0]. 숫자로 읽을 수 없으면 null */
export function parseVersion(v) {
  const m = /^\s*v?(\d+(?:\.\d+){0,3})\s*$/i.exec(String(v ?? ''));
  return m ? m[1].split('.').map(Number) : null;
}

/** 숫자별 비교 (1.10 > 1.9, 1.2 = 1.2.0). 하나라도 읽을 수 없으면 null */
export function compareVersions(a, b) {
  const x = parseVersion(a);
  const y = parseVersion(b);
  if (!x || !y) return null;
  for (let i = 0; i < Math.max(x.length, y.length); i += 1) {
    const d = (x[i] ?? 0) - (y[i] ?? 0);
    if (d) return d > 0 ? 1 : -1;
  }
  return 0;
}

/** 이 플랫폼의 최신 버전 문자열 (형식이 이상하면 null) */
export const latestFor = (json, platform) => {
  const v = json && typeof json === 'object' ? json[platform] : null;
  return typeof v === 'string' && parseVersion(v) ? v : null;
};

/** 나중에: { version, until } 저장. 저장이 안 되는 기기는 이번 실행 동안만 숨긴다(메모리) */
let memorySnooze = null;
export function snooze(version, now = Date.now()) {
  const value = { version, until: now + SNOOZE_MS };
  memorySnooze = value;
  try {
    localStorage.setItem(SNOOZE_KEY, JSON.stringify(value));
  } catch { /* 저장 불가 — 메모리 값만 */ }
}
export function resetSnoozeMemory() { memorySnooze = null; }

/** 지금 숨겨야 하는가: 24시간이 안 지났고, 숨긴 때보다 더 높은 새 버전이 아니면 숨긴다 */
export function isSnoozed(latest, now = Date.now()) {
  let saved = memorySnooze;
  try {
    const raw = localStorage.getItem(SNOOZE_KEY);
    if (raw) saved = JSON.parse(raw);
  } catch { /* 읽기 불가 — 메모리 값만 */ }
  if (!saved || typeof saved.until !== 'number' || now >= saved.until) return false;
  return compareVersions(latest, saved.version) !== 1;
}

/**
 * 안내할 새 버전: { platform, installed, latest, url } 또는 null.
 * 웹·PWA, 요청 실패·시간 초과·이상한 형식, 같거나 낮은 버전은 모두 null — 어떤 경우에도 던지지 않는다.
 */
export async function checkAppUpdate({ fetcher = fetch, now = Date.now() } = {}) {
  try {
    if (!isNativeApp()) return null;
    const platform = Capacitor.getPlatform();
    if (platform !== 'ios' && platform !== 'android') return null;
    const { version: installed } = await App.getInfo();
    const ctrl = typeof AbortController === 'function' ? new AbortController() : null;
    const timer = setTimeout(() => ctrl?.abort(), FETCH_TIMEOUT_MS);
    let json;
    try {
      const res = await fetcher(`${VERSION_URL}?t=${now}`, { cache: 'no-store', signal: ctrl?.signal });
      if (!res.ok) return null;
      json = await res.json();
    } finally {
      clearTimeout(timer);
    }
    const latest = latestFor(json, platform);
    if (!latest || compareVersions(latest, installed) !== 1) return null;
    return { platform, installed, latest };
  } catch {
    return null;
  }
}
