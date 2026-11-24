import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';

// 앱(iOS·Android) 휴대폰 알림 (1.3 패치 P-3, SPEC 6-103): 권한 → 토큰 → register_device_push_token, 끄기·로그아웃 → unregister,
// 알림 누르면 data.url로. @capacitor/push-notifications·@capacitor/app은 가짜로 바꾼다.
const cap = vi.hoisted(() => {
  const listeners = {};
  const state = {
    native: true,
    platform: 'ios',
    perm: 'prompt', // checkPermissions 결과
    answer: 'granted', // 허용 창에서 누를 답
    token: 'a'.repeat(64),
    registerFails: false,
    version: '1.3.0',
  };
  const fire = (name, arg) => (listeners[name] ?? []).forEach((cb) => cb(arg));
  const push = {
    addListener: vi.fn(async (name, cb) => { (listeners[name] ??= []).push(cb); return { remove: () => {} }; }),
    checkPermissions: vi.fn(async () => ({ receive: state.perm })),
    requestPermissions: vi.fn(async () => { state.perm = state.answer; return { receive: state.answer }; }),
    register: vi.fn(async () => {
      // 실제 플러그인처럼 토큰은 이벤트로 온다 (조금 뒤)
      setTimeout(() => (state.registerFails ? fire('registrationError', { error: 'no' }) : fire('registration', { value: state.token })), 0);
    }),
  };
  const app = {
    addListener: vi.fn(async () => ({ remove: () => {} })),
    getLaunchUrl: vi.fn(async () => undefined),
    getInfo: vi.fn(async () => ({ version: state.version })),
    exitApp: vi.fn(),
  };
  return { state, listeners, fire, push, app };
});
vi.mock('@capacitor/core', () => ({ Capacitor: { isNativePlatform: () => cap.state.native, getPlatform: () => (cap.state.native ? cap.state.platform : 'web') } }));
vi.mock('@capacitor/push-notifications', () => ({ PushNotifications: cap.push }));
vi.mock('@capacitor/app', () => ({ App: cap.app }));
vi.mock('@capacitor/browser', () => ({ Browser: { open: vi.fn(), close: vi.fn(), addListener: vi.fn(async () => ({ remove: () => {} })) } }));

const { AppRoutes } = await import('../App');
const { fakeLogin, fakeState } = await import('./fakeSupabase');
const { fakeFetch } = await import('./fakeDdragon');
const { signOut } = await import('../api/auth');
const np = await import('../lib/nativePush');
const { pushSupport } = await import('../lib/push');

const KEY_DEVICE = 'tsb.appPush.device';
const rpc = (name) => fakeState.rpcCalls.filter((c) => c.name === name);
const tokens = () => fakeState.deviceTokens;

function Where() { const l = useLocation(); return <output data-testid="where">{l.pathname + l.search}</output>; }
const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /><Where /></MemoryRouter>);
const where = () => screen.getByTestId('where').textContent;
const section = () => screen.findByRole('region', { name: '휴대폰 알림' });
// 플러그인은 처음 쓸 때 불러오므로 리스너가 붙을 때까지 기다린다 (실제 플러그인은 붙기 전 누른 알림을 붙을 때 넘긴다)
const listenersReady = () => waitFor(() => expect(cap.listeners.pushNotificationActionPerformed).toHaveLength(1));

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
  Object.assign(cap.state, { native: true, platform: 'ios', perm: 'prompt', answer: 'granted', token: 'a'.repeat(64), registerFails: false, version: '1.3.0' });
  Object.keys(cap.listeners).forEach((k) => delete cap.listeners[k]);
  Object.values(cap.push).forEach((f) => f.mockClear());
  localStorage.clear();
  np.resetNativePushForTest();
  np.startNativePush(true);
});
afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

describe('로그인 직후 (syncAppPush)', () => {
  test('처음: 권한을 한 번 묻고, 허용하면 토큰을 platform·앱 버전과 함께 등록', async () => {
    fakeLogin('u-1', { nickname: '탑고수' });
    expect(await np.syncAppPush('u-1')).toBe('registered');
    expect(cap.push.requestPermissions).toHaveBeenCalledTimes(1);
    expect(rpc('register_device_push_token')).toEqual([{ name: 'register_device_push_token', args: { p_platform: 'ios', p_token: 'a'.repeat(64), p_app_version: '1.3.0' } }]);
    expect(tokens()).toEqual([{ user_id: 'u-1', platform: 'ios', token: 'a'.repeat(64), app_version: '1.3.0' }]);
  });

  test('Android는 platform android (Capacitor.getPlatform 그대로 = 072 허용 값)', async () => {
    cap.state.platform = 'android';
    fakeLogin('u-1', { nickname: '탑고수' });
    await np.syncAppPush('u-1');
    expect(rpc('register_device_push_token')[0].args.p_platform).toBe('android');
  });

  test('거절: 등록하지 않고 앱은 그대로, 다음 로그인 때 다시 묻지 않는다', async () => {
    cap.state.answer = 'denied';
    fakeLogin('u-1', { nickname: '탑고수' });
    expect(await np.syncAppPush('u-1')).toBe('denied');
    expect(cap.push.register).not.toHaveBeenCalled();
    expect(rpc('register_device_push_token')).toEqual([]);
    cap.state.perm = 'prompt'; // (iOS는 거절하면 denied로 남지만, 묻지 않았다고 해도) 다시 묻지 않음
    expect(await np.syncAppPush('u-1')).toBe('prompt');
    expect(cap.push.requestPermissions).toHaveBeenCalledTimes(1);
  });

  test('이미 허용: 묻지 않고 같은 토큰을 다시 등록(갱신) — 줄은 하나', async () => {
    cap.state.perm = 'granted';
    fakeLogin('u-1', { nickname: '탑고수' });
    await np.syncAppPush('u-1');
    await np.syncAppPush('u-1');
    expect(cap.push.requestPermissions).not.toHaveBeenCalled();
    expect(rpc('register_device_push_token')).toHaveLength(2);
    expect(tokens()).toHaveLength(1);
  });

  test('토큰이 바뀌면: 옛 토큰을 지우고 새 토큰 등록', async () => {
    cap.state.perm = 'granted';
    fakeLogin('u-1', { nickname: '탑고수' });
    await np.syncAppPush('u-1');
    cap.state.token = 'b'.repeat(64);
    await np.syncAppPush('u-1');
    expect(rpc('unregister_device_push_token')).toEqual([{ name: 'unregister_device_push_token', args: { p_token: 'a'.repeat(64) } }]);
    expect(tokens().map((t) => t.token)).toEqual(['b'.repeat(64)]);
  });

  test('앱이 열려 있는 동안 토큰이 저절로 바뀌어도(FCM 갱신) 새 토큰으로 등록', async () => {
    cap.state.perm = 'granted';
    cap.state.platform = 'android';
    fakeLogin('u-1', { nickname: '탑고수' });
    await np.syncAppPush('u-1');
    await act(async () => { cap.fire('registration', { value: 'c'.repeat(64) }); });
    await waitFor(() => expect(tokens().map((t) => t.token)).toEqual(['c'.repeat(64)]));
  });

  test('등록 실패(registrationError)는 던지고, 저장 기록도 남기지 않는다', async () => {
    cap.state.perm = 'granted';
    cap.state.registerFails = true;
    fakeLogin('u-1', { nickname: '탑고수' });
    await expect(np.syncAppPush('u-1')).rejects.toThrow('등록하지 못했습니다');
    expect(localStorage.getItem(KEY_DEVICE)).toBeNull();
  });

  test('로그아웃 상태·웹이면 아무것도 하지 않는다', async () => {
    expect(await np.syncAppPush(null)).toBe('skip');
    cap.state.native = false;
    expect(await np.syncAppPush('u-1')).toBe('skip');
    expect(cap.push.checkPermissions).not.toHaveBeenCalled();
  });
});

describe('설정 화면 끄기·켜기, 로그아웃', () => {
  test('끄면 토큰을 지우고, 다음 로그인 때 다시 등록하지 않는다. 켜면 다시 등록', async () => {
    cap.state.perm = 'granted';
    fakeLogin('u-1', { nickname: '탑고수' });
    await np.syncAppPush('u-1');
    await np.disableAppPush('u-1');
    expect(tokens()).toEqual([]);
    expect(await np.syncAppPush('u-1')).toBe('off');
    expect((await np.getAppPushState('u-1')).on).toBe(false);
    await np.enableAppPush('u-1');
    expect(tokens()).toHaveLength(1);
    expect((await np.getAppPushState('u-1')).on).toBe(true);
  });

  test('휴대폰 설정에서 거절된 상태로 켜기: 설정 안내 문장', async () => {
    cap.state.perm = 'denied';
    fakeLogin('u-1', { nickname: '탑고수' });
    await expect(np.enableAppPush('u-1')).rejects.toThrow(np.APP_PUSH_DENIED);
    expect(cap.push.register).not.toHaveBeenCalled();
  });

  test('로그아웃: 로그인이 끊기기 전에 이 기기 토큰을 지운다 → 다른 계정으로 로그인하면 그 계정으로 등록', async () => {
    cap.state.perm = 'granted';
    fakeLogin('u-1', { nickname: '탑고수' });
    await np.syncAppPush('u-1');
    await signOut();
    expect(rpc('unregister_device_push_token')).toHaveLength(1);
    expect(tokens()).toEqual([]);
    fakeLogin('u-2', { nickname: '미드장인' });
    await np.syncAppPush('u-2');
    expect(tokens()).toEqual([expect.objectContaining({ user_id: 'u-2' })]);
  });

  test('로그아웃 때 지우기에 실패해도 로그아웃은 된다', async () => {
    cap.state.perm = 'granted';
    fakeLogin('u-1', { nickname: '탑고수' });
    await np.syncAppPush('u-1');
    fakeState.rpcError = '연결 실패';
    await expect(signOut()).resolves.toBeUndefined();
  });
});

describe('알림을 눌렀을 때', () => {
  test.each([
    ['/builds/12', '/builds/12'],
    ['/notifications?x=1', '/notifications?x=1'],
    ['https://evil.example/', '/notifications'],
    ['//evil.example', '/notifications'],
    ['/\\evil', '/notifications'],
    [undefined, '/notifications'],
    [12, '/notifications'],
  ])('data.url %j → %s', (url, path) => {
    expect(np.pushPath({ url })).toBe(path);
  });

  test('앱이 꺼져 있다가 알림으로 켜져도 화면이 뜬 뒤 그 주소로 간다', async () => {
    // 화면보다 먼저 온 알림 누름
    await listenersReady();
    await act(async () => { cap.fire('pushNotificationActionPerformed', { actionId: 'tap', notification: { data: { url: '/me/settings', notification_id: '7' } } }); });
    fakeLogin('u-1', { nickname: '탑고수' });
    start('/');
    await waitFor(() => expect(where()).toBe('/me/settings'));
  });

  test('보고 있을 때 누른 알림도 그 주소로', async () => {
    fakeLogin('u-1', { nickname: '탑고수' });
    start('/');
    await screen.findAllByRole('link');
    await listenersReady();
    await act(async () => { cap.fire('pushNotificationActionPerformed', { notification: { data: { url: '/notifications' } } }); });
    await waitFor(() => expect(where()).toBe('/notifications'));
  });
});

describe('[계정 설정] 휴대폰 알림 (앱)', () => {
  test('앱이면 "준비 중" 대신 이 기기 켜기 버튼 → 누르면 등록, 받을 알림 종류는 그대로', async () => {
    cap.state.perm = 'denied'; // 로그인 직후 자동 등록이 끼어들지 않게
    localStorage.setItem('tsb.appPush.asked', '1');
    fakeLogin('u-1', { nickname: '탑고수' });
    start('/me/settings');
    const box = await section();
    expect(box.textContent).not.toContain('준비 중');
    expect(await screen.findByText('꺼짐')).toBeTruthy();
    expect(box.textContent).toContain('설정 → 탑신병자 → 알림');
    expect(await screen.findByRole('checkbox', { name: /내 상대법·빌드 다시 공개/ })).toBeChecked();
    cap.state.perm = 'granted';
    fireEvent.click(screen.getByRole('button', { name: '이 기기에서 알림 켜기' }));
    expect(await screen.findByText('켜짐')).toBeTruthy();
    expect(tokens()).toHaveLength(1);
    fireEvent.click(screen.getByRole('button', { name: '이 기기에서 알림 끄기' }));
    expect(await screen.findByText('꺼짐')).toBeTruthy();
    expect(tokens()).toEqual([]);
  });

  test('로그인한 채 앱을 열면 권한을 묻고 등록한다 (AuthProvider)', async () => {
    fakeLogin('u-1', { nickname: '탑고수' });
    start('/');
    await waitFor(() => expect(tokens()).toHaveLength(1));
    expect(cap.push.requestPermissions).toHaveBeenCalledTimes(1);
  });

  test('웹(브라우저)에서는 앱 알림 코드가 아무것도 하지 않는다', async () => {
    cap.state.native = false;
    np.resetNativePushForTest();
    expect(np.startNativePush()).toBe(false);
    fakeLogin('u-1', { nickname: '탑고수' });
    start('/');
    await screen.findAllByRole('link');
    expect(cap.push.checkPermissions).not.toHaveBeenCalled();
    expect(rpc('register_device_push_token')).toEqual([]);
    expect(pushSupport({ native: false, ios: false, standalone: false, hasPush: true, permission: 'default', prod: true })).toBe('ok');
  });
});
