// 1.3 패치 1-F (SPEC 6-99): 앱 업데이트 안내 — 웹에서는 숨김, 숫자별 버전 비교, 같거나 낮은 버전에서 숨김, [나중에] 24시간, 요청 실패 시 무음
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { readFileSync } from 'node:fs';

const cap = vi.hoisted(() => ({ native: true, platform: 'android', installed: '1.2' }));
vi.mock('@capacitor/core', () => ({ Capacitor: { isNativePlatform: () => cap.native, getPlatform: () => cap.platform } }));
vi.mock('@capacitor/app', () => ({ App: { getInfo: async () => ({ version: cap.installed }), addListener: vi.fn() } }));

import AppUpdateBanner from '../components/AppUpdateBanner';
import {
  SNOOZE_KEY, SNOOZE_MS, VERSION_URL, checkAppUpdate, compareVersions, isSnoozed, resetSnoozeMemory, snooze,
} from '../lib/appUpdate';
import { APP_STORE_URL, storeUrlFor } from '../lib/storeLinks';

const json = (body) => ({ ok: true, json: async () => body });
let fetchMock;
beforeEach(() => {
  cap.native = true; cap.platform = 'android'; cap.installed = '1.2';
  localStorage.clear();
  resetSnoozeMemory();
  fetchMock = vi.fn(async () => json({ ios: '1.3.0', android: '1.3.0' }));
  vi.stubGlobal('fetch', fetchMock);
});
afterEach(() => { cleanup(); vi.unstubAllGlobals(); vi.restoreAllMocks(); });

test('버전 비교: 숫자별(1.10 > 1.9), 1.2 = 1.2.0, 읽을 수 없으면 null', () => {
  expect(compareVersions('1.10', '1.9')).toBe(1);
  expect(compareVersions('1.9', '1.10')).toBe(-1);
  expect(compareVersions('1.2', '1.2.0')).toBe(0);
  expect(compareVersions('2.0.0', '1.99.99')).toBe(1);
  expect(compareVersions('abc', '1.0')).toBeNull();
  expect(compareVersions(undefined, '1.0')).toBeNull();
});

test('웹 브라우저·PWA에서는 아무것도 하지 않는다 (요청도 없음)', async () => {
  cap.native = false;
  expect(await checkAppUpdate()).toBeNull();
  expect(fetchMock).not.toHaveBeenCalled();
  render(<AppUpdateBanner />);
  await new Promise((r) => setTimeout(r, 20));
  expect(screen.queryByText('새 버전이 나왔습니다')).toBeNull();
});

test('최신이 더 높으면 배너(문구·[업데이트]·[나중에]), 캐시 방지 쿼리·no-store로 한 번만 요청', async () => {
  render(<AppUpdateBanner />);
  expect(await screen.findByText('새 버전이 나왔습니다')).toBeTruthy();
  expect(screen.getByRole('button', { name: '나중에' })).toBeTruthy();
  expect(screen.getByRole('link', { name: '업데이트' }).getAttribute('href')).toBe('https://play.google.com/store/apps/details?id=com.topsinbyeongja.app');
  expect(fetchMock).toHaveBeenCalledTimes(1);
  const [url, opts] = fetchMock.mock.calls[0];
  expect(url.startsWith(`${VERSION_URL}?t=`)).toBe(true);
  expect(opts.cache).toBe('no-store');
});

test('[업데이트]는 플랫폼에 맞는 스토어: iOS는 App Store', async () => {
  cap.platform = 'ios';
  render(<AppUpdateBanner />);
  expect((await screen.findByRole('link', { name: '업데이트' })).getAttribute('href')).toBe(APP_STORE_URL);
  expect(storeUrlFor('web')).toBe('');
});

test('같은 버전·낮은 버전·내 플랫폼 값이 없으면 숨김', async () => {
  for (const body of [{ android: '1.2.0' }, { android: '1.1.9' }, { ios: '9.0.0' }]) {
    fetchMock.mockResolvedValueOnce(json(body));
    expect(await checkAppUpdate()).toBeNull();
  }
  cap.installed = '1.10';
  fetchMock.mockResolvedValueOnce(json({ android: '1.9' }));
  expect(await checkAppUpdate()).toBeNull(); // 1.9 < 1.10
});

test('요청 실패·시간 초과·이상한 형식은 조용히 넘어간다 (던지지 않고 배너도 없음)', async () => {
  fetchMock.mockRejectedValueOnce(new Error('network'));
  expect(await checkAppUpdate()).toBeNull();
  fetchMock.mockResolvedValueOnce({ ok: false, json: async () => ({}) });
  expect(await checkAppUpdate()).toBeNull();
  fetchMock.mockResolvedValueOnce({ ok: true, json: async () => { throw new Error('bad json'); } });
  expect(await checkAppUpdate()).toBeNull();
  for (const body of [null, 'x', [], { android: 5 }, { android: 'latest' }]) {
    fetchMock.mockResolvedValueOnce(json(body));
    expect(await checkAppUpdate()).toBeNull();
  }
  fetchMock.mockRejectedValue(new Error('network'));
  render(<AppUpdateBanner />);
  await new Promise((r) => setTimeout(r, 20));
  expect(screen.queryByText('새 버전이 나왔습니다')).toBeNull();
});

test('시간 초과: 응답이 없으면 신호로 끊고 조용히 넘어간다', async () => {
  vi.useFakeTimers();
  try {
    fetchMock.mockImplementation((_u, { signal }) => new Promise((_res, rej) => signal.addEventListener('abort', () => rej(new Error('aborted')))));
    const p = checkAppUpdate();
    await vi.advanceTimersByTimeAsync(5000);
    expect(await p).toBeNull();
  } finally {
    vi.useRealTimers();
  }
});

test('[나중에]: 닫고 24시간 숨김 → 24시간 뒤에는 다시, 더 높은 새 버전이면 24시간 안에도 다시', async () => {
  const first = render(<AppUpdateBanner />);
  fireEvent.click(await screen.findByRole('button', { name: '나중에' }));
  expect(screen.queryByText('새 버전이 나왔습니다')).toBeNull();
  const saved = JSON.parse(localStorage.getItem(SNOOZE_KEY));
  expect(saved.version).toBe('1.3.0');
  expect(saved.until - Date.now()).toBeGreaterThan(SNOOZE_MS - 5000);
  first.unmount();
  render(<AppUpdateBanner />); // 다시 켠 앱 — 아직 숨김
  await waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2));
  await new Promise((r) => setTimeout(r, 20));
  expect(screen.queryByText('새 버전이 나왔습니다')).toBeNull();
  const t = Date.now();
  expect(isSnoozed('1.3.0', t + SNOOZE_MS - 1000)).toBe(true);
  expect(isSnoozed('1.3.0', t + SNOOZE_MS + 1000)).toBe(false); // 24시간 뒤
  expect(isSnoozed('1.4.0', t + 1000)).toBe(false); // 더 높은 새 버전
  expect(isSnoozed('1.2.5', t + 1000)).toBe(true); // 낮은 쪽은 계속 숨김
});

test('저장이 안 되는 기기: 이번 실행 동안만 숨기고 오류는 없다', () => {
  vi.spyOn(Storage.prototype, 'setItem').mockImplementation(() => { throw new Error('quota'); });
  vi.spyOn(Storage.prototype, 'getItem').mockImplementation(() => { throw new Error('denied'); });
  expect(() => snooze('1.3.0')).not.toThrow();
  expect(isSnoozed('1.3.0')).toBe(true);
});

test('version.json: 스토어 출시 전이라 1.2.0 그대로 — 앱 1.3보다 낮아 배너가 뜨지 않고, _headers에 CORS·no-cache가 있다 (6-105)', async () => {
  const v = JSON.parse(readFileSync('public/version.json', 'utf8'));
  expect(v).toEqual({ ios: '1.2.0', android: '1.2.0' }); // 출시 뒤에만 올린다
  expect(compareVersions(v.android, '1.3')).toBe(-1);
  expect(compareVersions(v.ios, '1.3')).toBe(-1);
  expect(compareVersions('1.3', '1.2.0')).toBe(1);
  cap.installed = '1.3';
  fetchMock.mockResolvedValueOnce(json(v));
  expect(await checkAppUpdate()).toBeNull();
  const gradle = readFileSync('android/app/build.gradle', 'utf8');
  expect(gradle).toMatch(/versionName "1\.3"/);
  expect(Number(gradle.match(/versionCode (\d+)/)[1])).toBeGreaterThan(2); // 1.2의 versionCode
  const pbx = readFileSync('ios/App/App.xcodeproj/project.pbxproj', 'utf8');
  expect(pbx.match(/MARKETING_VERSION = 1\.3;/g)).toHaveLength(2);
  const headers = readFileSync('public/_headers', 'utf8');
  const block = headers.split('\n').slice(headers.split('\n').indexOf('/version.json'));
  expect(block.join('\n')).toMatch(/Access-Control-Allow-Origin: \*/);
  expect(block.join('\n')).toMatch(/Cache-Control: no-cache/);
  expect(headers).toMatch(/\/assets\/\*\n  Cache-Control: public, max-age=31536000, immutable/); // 기존 규칙 그대로
});
