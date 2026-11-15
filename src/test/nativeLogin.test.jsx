import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import { act, cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';

// 앱(Capacitor)에서 구글·카카오 로그인 (SPEC 6-57): 시스템 브라우저 → com.topsinbyeongja.app://auth-callback → code 교환
const cap = vi.hoisted(() => {
  const listeners = {};
  const add = (name, cb) => { (listeners[name] ??= []).push(cb); return Promise.resolve({ remove: () => {} }); };
  return {
    native: true,
    listeners,
    fire: (name, arg) => (listeners[name] ?? []).forEach((cb) => cb(arg)),
    app: { addListener: vi.fn(add), getLaunchUrl: vi.fn(async () => undefined), exitApp: vi.fn() },
    browser: { open: vi.fn(async () => {}), close: vi.fn(async () => {}), addListener: vi.fn(add) },
  };
});
vi.mock('@capacitor/core', () => ({ Capacitor: { isNativePlatform: () => cap.native } }));
vi.mock('@capacitor/app', () => ({ App: cap.app }));
vi.mock('@capacitor/browser', () => ({ Browser: cap.browser }));

const { AppRoutes } = await import('../App');
const { db } = await import('../api/supabase');
const { fakeGuestLogin, fakeLogin, fakeState } = await import('./fakeSupabase');
const { fakeFetch } = await import('./fakeDdragon');
const { clickMenu } = await import('./menu');
const { signIn, startNativeLogin } = await import('../api/auth');
const { NATIVE_REDIRECT, claimCode, listenAuthCallbacks, parseAuthCallback, resetNativeAuthForTest } = await import('../lib/nativeAuth');

const CALLBACK = `${NATIVE_REDIRECT}?code=code-1`;
let exchange;

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
  cap.native = true;
  Object.keys(cap.listeners).forEach((k) => delete cap.listeners[k]);
  cap.app.addListener.mockClear();
  cap.app.getLaunchUrl.mockReset().mockResolvedValue(undefined);
  cap.browser.open.mockClear();
  cap.browser.close.mockClear();
  resetNativeAuthForTest();
  localStorage.removeItem('auth:pending');
  const auth = db().auth;
  vi.spyOn(auth, 'signInWithOAuth').mockImplementation(async (args) => {
    fakeState.oauthCalls.push(args);
    return { data: { provider: args.provider, url: `https://example.supabase.co/auth/v1/authorize?provider=${args.provider}`, flowId: 'flow-1' }, error: null };
  });
  vi.spyOn(auth, 'linkIdentity').mockImplementation(async (args) => {
    fakeState.linkCalls.push(args);
    return { data: { provider: args.provider, url: `https://example.supabase.co/link?provider=${args.provider}`, flowId: 'flow-2' }, error: null };
  });
  // 기본: code를 받으면 처음 가입한 사람(닉네임 없음)으로 로그인된다
  exchange = vi.fn(async () => {
    fakeLogin('u-app', {}, { identities: [] });
    return { data: { session: fakeState.session }, error: null };
  });
  auth.exchangeCodeForSession = exchange;
});
afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
  delete db().auth.exchangeCodeForSession;
  vi.useRealTimers();
});

function Where() { const l = useLocation(); return <output data-testid="where">{l.pathname}</output>; }
const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /><Where /></MemoryRouter>);
const where = () => screen.getByTestId('where').textContent;
const openUrl = async (url) => { await act(async () => { cap.fire('appUrlOpen', { url }); await new Promise((r) => setTimeout(r, 0)); }); };

describe('parseAuthCallback', () => {
  test('code와 sb_flow_id를 꺼낸다', () => {
    expect(parseAuthCallback(`${NATIVE_REDIRECT}?code=abc&sb_flow_id=f1`)).toEqual({
      code: 'abc', flowId: 'f1', error: null, errorCode: null, errorDescription: null,
    });
  });
  test('오류는 ?와 # 둘 다 읽는다', () => {
    expect(parseAuthCallback(`${NATIVE_REDIRECT}?error=access_denied&error_description=User%20denied`)).toMatchObject({
      code: null, error: 'access_denied', errorDescription: 'User denied',
    });
    expect(parseAuthCallback(`${NATIVE_REDIRECT}#error=server_error&error_code=bad_oauth&error_description=x`)).toMatchObject({
      error: 'server_error', errorCode: 'bad_oauth', errorDescription: 'x',
    });
  });
  test('다른 스킴·다른 경로·깨진 주소는 로그인 콜백이 아니다', () => {
    expect(parseAuthCallback('https://example.com/auth-callback?code=1')).toBeNull();
    expect(parseAuthCallback('com.topsinbyeongja.app://other?code=1')).toBeNull();
    expect(parseAuthCallback('not a url')).toBeNull();
  });
  test('같은 code는 한 번만 쓸 수 있다', () => {
    expect(claimCode('c-1')).toBe(true);
    expect(claimCode('c-1')).toBe(false);
    expect(claimCode('c-2')).toBe(true);
  });
});

describe('웹 / 앱 분기', () => {
  test('웹: 리스너를 등록하지 않고, 로그인 요청은 예전 그대로(origin + 경로, skipBrowserRedirect 없음) — 시스템 브라우저도 열지 않는다', async () => {
    cap.native = false;
    expect(startNativeLogin()).toBe(false);
    expect(cap.app.addListener).not.toHaveBeenCalled();
    expect(await signIn('google', '/board')).toBeUndefined();
    expect(fakeState.oauthCalls).toEqual([
      { provider: 'google', options: { redirectTo: `${window.location.origin}/board`, queryParams: { prompt: 'select_account' } } },
    ]);
    expect(cap.browser.open).not.toHaveBeenCalled();
    expect(sessionStorage.getItem('auth:pending')).toBe('{"kind":"signIn","provider":"google"}');
  });

  test('앱: 리스너는 한 번만 등록된다 (두 번 불러도)', () => {
    expect(startNativeLogin()).toBe(true);
    expect(startNativeLogin()).toBe(false);
    expect(listenAuthCallbacks({ onCallback: vi.fn(), onCancel: vi.fn() })).toBe(false);
    expect(cap.app.addListener.mock.calls.filter(([n]) => n === 'appUrlOpen')).toHaveLength(1);
    expect(cap.browser.addListener.mock.calls.filter(([n]) => n === 'browserFinished').length).toBeGreaterThan(0);
  });
});

describe('앱 로그인 화면', () => {
  test('구글: 시스템 브라우저로 열고 → 돌아온 code를 한 번만 교환 → 닉네임 정하기 → 원래 페이지', async () => {
    startNativeLogin();
    start('/champion/Darius');
    await clickMenu('로그인 · 가입');
    expect(where()).toBe('/login');
    fireEvent.click(screen.getByRole('button', { name: '구글로 시작하기' }));
    await screen.findByRole('button', { name: '구글로 이동 중…' });
    expect(fakeState.oauthCalls).toEqual([{
      provider: 'google',
      options: { redirectTo: 'com.topsinbyeongja.app://auth-callback', queryParams: { prompt: 'select_account' }, skipBrowserRedirect: true },
    }]);
    expect(cap.browser.open).toHaveBeenCalledWith({ url: 'https://example.supabase.co/auth/v1/authorize?provider=google' });
    expect(JSON.parse(localStorage.getItem('auth:pending'))).toMatchObject({ kind: 'signIn', provider: 'google', returnTo: '/champion/Darius', flowId: 'flow-1' });

    await openUrl(CALLBACK);
    await openUrl(CALLBACK); // 같은 콜백이 두 번 와도
    expect(exchange).toHaveBeenCalledTimes(1);
    expect(exchange).toHaveBeenCalledWith('code-1', { flowId: 'flow-1' });
    expect(cap.browser.close).toHaveBeenCalled();
    expect(localStorage.getItem('auth:pending')).toBeNull();

    // 처음 가입: 닉네임 정하기 → 저장하면 원래 페이지 (웹과 같은 흐름)
    expect(await screen.findByRole('heading', { name: '닉네임 정하기' })).toBeDefined();
    expect(where()).toBe('/welcome');
    fireEvent.change(screen.getByLabelText('닉네임'), { target: { value: '앱탑' } });
    fireEvent.click(screen.getByRole('button', { name: '시작하기' }));
    await vi.waitFor(() => expect(where()).toBe('/champion/Darius'));
    expect(screen.queryByRole('alert')).toBeNull();
  });

  test('앱이 꺼져 있다가 딥링크로 켜져도(getLaunchUrl) appUrlOpen과 합쳐 한 번만 교환한다', async () => {
    localStorage.setItem('auth:pending', JSON.stringify({ kind: 'signIn', provider: 'kakao', returnTo: '/', flowId: 'flow-1', at: Date.now() }));
    cap.app.getLaunchUrl.mockResolvedValue({ url: CALLBACK });
    startNativeLogin();
    start('/');
    await openUrl(CALLBACK);
    await vi.waitFor(() => expect(exchange).toHaveBeenCalledTimes(1));
    expect(await screen.findByRole('heading', { name: '닉네임 정하기' })).toBeDefined();
  });

  test('구글·카카오에서 취소·거절(error 파라미터): 교환하지 않고 로그인 화면에 안내 + 버튼 다시 열림', async () => {
    startNativeLogin();
    start('/login');
    fireEvent.click(await screen.findByRole('button', { name: '카카오로 시작하기' }));
    await screen.findByRole('button', { name: '카카오로 이동 중…' });
    await openUrl(`${NATIVE_REDIRECT}?error=access_denied&error_description=User%20denied%20access`);
    expect(exchange).not.toHaveBeenCalled();
    const alert = await screen.findByRole('alert');
    expect(alert.textContent).toContain('로그인이 취소됐거나 거절됐습니다. 다시 시도해 주세요.');
    expect(within(alert).getByRole('link', { name: '다시 로그인' })).toBeDefined();
    expect(where()).toBe('/login');
    expect((await screen.findByRole('button', { name: '카카오로 시작하기' })).disabled).toBe(false);
  });

  test('code 교환 실패(만료·이미 사용): 안내를 보여 주고 멈추지 않는다', async () => {
    exchange.mockResolvedValue({ data: { session: null }, error: { message: 'invalid flow state, flow state has expired' } });
    startNativeLogin();
    start('/login');
    fireEvent.click(await screen.findByRole('button', { name: '구글로 시작하기' }));
    await screen.findByRole('button', { name: '구글로 이동 중…' });
    await openUrl(CALLBACK);
    expect((await screen.findByRole('alert')).textContent).toContain('로그인 코드가 만료됐거나 이미 사용됐습니다');
    expect(screen.getByRole('button', { name: '구글로 시작하기' }).disabled).toBe(false);
  });

  test('로그인 창을 그냥 닫음: 잠시 뒤 취소 안내 + 버튼 다시 열림. 그래도 늦게 온 콜백(카카오톡 앱에 다녀옴)은 받아 준다', async () => {
    startNativeLogin(true, { graceMs: 10 });
    start('/login');
    fireEvent.click(await screen.findByRole('button', { name: '구글로 시작하기' }));
    await screen.findByRole('button', { name: '구글로 이동 중…' });
    act(() => cap.fire('browserFinished'));
    const alert = await screen.findByRole('alert');
    expect(alert.textContent).toContain('로그인 창을 닫아서 로그인하지 않았습니다. 다시 시도해 주세요.');
    expect(screen.getByRole('button', { name: '구글로 시작하기' }).disabled).toBe(false);
    expect(exchange).not.toHaveBeenCalled();

    await openUrl(CALLBACK);
    expect(exchange).toHaveBeenCalledWith('code-1', { flowId: 'flow-1' });
    await vi.waitFor(() => expect(screen.queryByRole('alert')).toBeNull());
  });

  test('안드로이드처럼 창 닫힘 이벤트가 콜백보다 먼저 와도 취소로 보지 않는다', async () => {
    startNativeLogin(true, { graceMs: 30 });
    start('/login');
    fireEvent.click(await screen.findByRole('button', { name: '구글로 시작하기' }));
    await screen.findByRole('button', { name: '구글로 이동 중…' });
    act(() => cap.fire('browserFinished'));
    await openUrl(CALLBACK);
    await new Promise((r) => setTimeout(r, 60));
    expect(exchange).toHaveBeenCalledTimes(1);
    expect(screen.queryByText(/로그인 창을 닫아서/)).toBeNull();
  });
});

describe('앱 계정 연결', () => {
  test('/me/settings [카카오 연결하기]: 시스템 브라우저 → 돌아오면 "연결했습니다" 안내', async () => {
    fakeLogin('u-old', { nickname: '탑장인' }, { identities: [{ provider: 'google', created_at: new Date().toISOString() }] });
    exchange.mockImplementation(async () => ({ data: { session: fakeState.session }, error: null }));
    startNativeLogin();
    start('/me/settings');
    fireEvent.click(await screen.findByRole('button', { name: '카카오 연결하기' }));
    await screen.findByRole('button', { name: '카카오로 이동 중…' });
    expect(fakeState.linkCalls[0].options).toEqual({ redirectTo: NATIVE_REDIRECT, queryParams: { prompt: 'login' }, skipBrowserRedirect: true });
    await openUrl(CALLBACK);
    expect(exchange).toHaveBeenCalledWith('code-1', { flowId: 'flow-2' });
    expect((await screen.findByText(/카카오 로그인을 이 계정에 연결했습니다/)).closest('.login-notice')).not.toBeNull();
    expect(where()).toBe('/me/settings');
    expect(screen.getByRole('button', { name: '카카오 연결하기' }).disabled).toBe(false);
  });

  test('비회원 /me [구글 연결하기] → [지금 계정에 연결하기]: 돌아오면 "정식 계정" 안내', async () => {
    fakeGuestLogin('g-1', { nickname: '손님' });
    exchange.mockImplementation(async () => ({ data: { session: fakeState.session }, error: null }));
    startNativeLogin();
    start('/me');
    const box = await screen.findByRole('region', { name: '구글·카카오 연결하기' });
    fireEvent.click(within(box).getByRole('button', { name: '구글 연결하기' }));
    fireEvent.click(within(screen.getByRole('dialog', { name: '구글로 계속하기' })).getByRole('button', { name: /지금 계정에 연결하기/ }));
    await vi.waitFor(() => expect(cap.browser.open).toHaveBeenCalled());
    expect(fakeState.signOutCalls).toEqual([]); // 비회원 세션을 지우지 않는다
    await openUrl(CALLBACK);
    expect((await screen.findByText(/구글 로그인을 연결해서 정식 계정이 됐습니다/)).closest('.login-notice')).not.toBeNull();
    expect(where()).toBe('/me');
  });
});
