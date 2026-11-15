import { beforeEach, describe, expect, test, vi } from 'vitest';

// 앱(Capacitor)일 때만 웹 전용 기능을 끈다 (SPEC 6-55)
const calls = vi.hoisted(() => ({ install: 0, sw: 0, native: false }));
vi.mock('../lib/install', () => ({ captureInstallPrompt: () => { calls.install += 1; } }));
vi.mock('../lib/sw', () => ({ registerServiceWorker: () => { calls.sw += 1; } }));
vi.mock('@capacitor/core', () => ({ Capacitor: { isNativePlatform: () => calls.native } }));

const { startWebOnlyFeatures } = await import('../lib/startup');
const { isNativeApp } = await import('../lib/native');

beforeEach(() => { calls.install = 0; calls.sw = 0; calls.native = false; });

describe('startWebOnlyFeatures', () => {
  test('웹사이트: [앱 설치] 이벤트 잡기와 서비스 워커 등록을 그대로 한다', () => {
    expect(startWebOnlyFeatures()).toBe(true);
    expect(calls).toMatchObject({ install: 1, sw: 1 });
  });
  test('앱: 둘 다 하지 않는다', () => {
    calls.native = true;
    expect(isNativeApp()).toBe(true);
    expect(startWebOnlyFeatures()).toBe(false);
    expect(calls).toMatchObject({ install: 0, sw: 0 });
  });
});
