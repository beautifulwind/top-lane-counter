import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';

// iOS 앱에서만 쓰는 Apple 로그인 (SPEC 6-58): iOS 시트 → id token(nonce) → signInWithIdToken / linkIdentity(token)
const cap = vi.hoisted(() => ({
  native: true,
  platform: 'ios',
  app: { addListener: vi.fn(async () => ({ remove: () => {} })), getLaunchUrl: vi.fn(async () => undefined), exitApp: vi.fn() },
  browser: { open: vi.fn(async () => {}), close: vi.fn(async () => {}), addListener: vi.fn(async () => ({ remove: () => {} })) },
  apple: { signIn: vi.fn() },
}));
vi.mock('@capacitor/core', () => ({
  Capacitor: { isNativePlatform: () => cap.native, getPlatform: () => (cap.native ? cap.platform : 'web') },
}));
vi.mock('@capacitor/app', () => ({ App: cap.app }));
vi.mock('@capacitor/browser', () => ({ Browser: cap.browser }));
vi.mock('@capawesome/capacitor-apple-sign-in', () => ({ AppleSignIn: cap.apple }));

const { AppRoutes } = await import('../App');
const { db } = await import('../api/supabase');
const { fakeGuestLogin, fakeLogin, fakeState } = await import('./fakeSupabase');
const { fakeFetch } = await import('./fakeDdragon');
const { canUseProvider, linkProvider, loginProviders, signIn } = await import('../api/auth');
const { isIosApp } = await import('../lib/native');
const { resetNativeAuthForTest } = await import('../lib/nativeAuth');
const {
  APPLE_ONLY_TEXT, APPLE_SCOPES, displayEmail, isAppleCancel, isAppleOnly, isRelayEmail, makeNonce, signInWithAppleSheet, userProviders,
} = await import('../lib/appleAuth');
const { ALREADY_MEMBER_TEXT } = await import('../lib/guest');

const sha256 = async (text) => [...new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text)))]
  .map((b) => b.toString(16).padStart(2, '0')).join('');
const now = () => new Date().toISOString();
const appleIdentity = (email = 'me@example.com') => ({ provider: 'apple', created_at: now(), identity_data: { email } });

let idTokenCalls;
let linkCalls;

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
  cap.native = true;
  cap.platform = 'ios';
  cap.browser.open.mockClear();
  cap.apple.signIn.mockReset().mockResolvedValue({ idToken: 'apple-id-token', authorizationCode: 'code', user: 'apple-sub', email: null, givenName: null, familyName: null });
  resetNativeAuthForTest();
  idTokenCalls = [];
  linkCalls = [];
  const auth = db().auth;
  // 기본: Apple로 처음 가입 (닉네임 없음, 로그인 방식은 Apple뿐)
  auth.signInWithIdToken = vi.fn(async (args) => {
    idTokenCalls.push(args);
    fakeLogin('u-apple', {}, { identities: [appleIdentity()], app_metadata: { providers: ['apple'] } });
    return { data: { user: fakeState.session.user, session: fakeState.session }, error: null };
  });
  vi.spyOn(auth, 'linkIdentity').mockImplementation(async (args) => {
    linkCalls.push(args);
    const user = { ...fakeState.session.user, is_anonymous: false, identities: [...(fakeState.session.user.identities ?? []), appleIdentity()] };
    return { data: { user, session: { ...fakeState.session, user } }, error: null };
  });
  vi.spyOn(auth, 'signInWithOAuth');
});
afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
  delete db().auth.signInWithIdToken;
});

function Where() { const l = useLocation(); return <output data-testid="where">{l.pathname}</output>; }
const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /><Where /></MemoryRouter>);
const where = () => screen.getByTestId('where').textContent;

describe('어디서 보이나 (iOS 앱에서만)', () => {
  test.each([
    ['iOS 앱', true, 'ios', true],
    ['안드로이드 앱', true, 'android', false],
    ['웹', false, 'web', false],
  ])('%s: isIosApp·Apple 버튼', async (_name, native, platform, shown) => {
    cap.native = native;
    cap.platform = platform;
    expect(isIosApp()).toBe(shown);
    expect(canUseProvider('apple')).toBe(shown);
    expect(loginProviders().map(([p]) => p)).toEqual(shown ? ['google', 'kakao', 'apple'] : ['google', 'kakao']);
    start('/login');
    expect(await screen.findByRole('button', { name: '구글로 시작하기' })).toBeDefined();
    expect(screen.queryByRole('button', { name: 'Apple로 시작하기' }) !== null).toBe(shown);
  });

  test('웹·안드로이드에서 Apple 로그인·연결을 부르면 막는다 (플러그인을 부르지 않음)', async () => {
    for (const platform of ['web', 'android']) {
      cap.native = platform !== 'web';
      cap.platform = platform;
      await expect(signIn('apple')).rejects.toThrow('지원하지 않는 로그인 방식입니다. (apple)');
      await expect(linkProvider('apple')).rejects.toThrow('지원하지 않는 로그인 방식입니다. (apple)');
    }
    expect(cap.apple.signIn).not.toHaveBeenCalled();
  });

  test('플러그인은 동적으로만 불러온다 (웹 번들에 정적으로 들어가지 않게)', () => {
    const files = [];
    const walk = (dir) => readdirSync(dir).forEach((f) => {
      const p = join(dir, f);
      if (statSync(p).isDirectory()) { if (f !== 'test') walk(p); } else if (/\.(js|jsx)$/.test(f)) files.push(p);
    });
    walk(join(process.cwd(), 'src'));
    const staticImports = files.filter((f) => /^\s*import[^(]*['"]@capawesome\/capacitor-apple-sign-in['"]/m.test(readFileSync(f, 'utf8')));
    expect(staticImports).toEqual([]);
    expect(readFileSync(join(process.cwd(), 'src/lib/appleAuth.js'), 'utf8')).toContain("import('@capawesome/capacitor-apple-sign-in')");
  });
});

describe('도우미', () => {
  test('nonce: raw는 64자 hex, hashed = SHA-256(raw), 매번 다르다', async () => {
    const a = await makeNonce();
    const b = await makeNonce();
    expect(a.raw).toMatch(/^[0-9a-f]{64}$/);
    expect(a.hashed).toBe(await sha256(a.raw));
    expect(a.raw).not.toBe(b.raw);
  });

  test('시트: 이메일만 요청하고 Apple에는 해시, 돌려주는 nonce는 원문', async () => {
    const plugin = { signIn: vi.fn(async () => ({ idToken: 't-1' })) };
    const { idToken, nonce } = await signInWithAppleSheet({ load: async () => plugin });
    expect(APPLE_SCOPES).toEqual(['EMAIL']);
    expect(plugin.signIn).toHaveBeenCalledWith({ scopes: ['EMAIL'], nonce: await sha256(nonce) });
    expect(idToken).toBe('t-1');
  });

  test('시트: 취소는 cancelled, id token이 없으면 실패', async () => {
    const cancel = { signIn: vi.fn(async () => { throw Object.assign(new Error('canceled'), { code: 'SIGN_IN_CANCELED' }); }) };
    await expect(signInWithAppleSheet({ load: async () => cancel })).rejects.toMatchObject({ cancelled: true });
    const empty = { signIn: vi.fn(async () => ({})) };
    await expect(signInWithAppleSheet({ load: async () => empty })).rejects.toThrow('Apple에서 로그인 정보를 받지 못했습니다.');
    expect(isAppleCancel({ code: 1001 })).toBe(true);
    expect(isAppleCancel({ code: '1000' })).toBe(false);
  });

  test('릴레이 이메일·Apple만 연결됐는지', () => {
    expect(isRelayEmail('abc123@privaterelay.appleid.com')).toBe(true);
    expect(isRelayEmail('me@icloud.com')).toBe(false);
    expect(displayEmail('abc123@privaterelay.appleid.com')).toBe('이메일 숨김 (Apple)');
    expect(displayEmail('me@icloud.com')).toBe('me@icloud.com');
    expect(isAppleOnly(['apple'])).toBe(true);
    expect(isAppleOnly(['anonymous', 'apple'])).toBe(true);
    expect(isAppleOnly(['apple', 'google'])).toBe(false);
    expect(isAppleOnly(['kakao'])).toBe(false);
    expect(isAppleOnly([])).toBe(false);
    expect(userProviders({ identities: [], app_metadata: { providers: ['apple'] } })).toEqual(['apple']);
    expect(userProviders({ identities: [{ provider: 'kakao' }] })).toEqual(['kakao']);
  });
});

describe('iOS 앱 Apple 로그인', () => {
  test('처음 가입: 시트(nonce 해시) → signInWithIdToken(nonce 원문) → 닉네임 정하기 + "다른 기기" 안내 → 원래 페이지', async () => {
    start('/login');
    fireEvent.click(await screen.findByRole('button', { name: 'Apple로 시작하기' }));
    await vi.waitFor(() => expect(idTokenCalls).toHaveLength(1));
    const [{ nonce: hashed, scopes }] = cap.apple.signIn.mock.calls[0];
    expect(scopes).toEqual(['EMAIL']);
    expect(idTokenCalls[0]).toEqual({ provider: 'apple', token: 'apple-id-token', nonce: expect.stringMatching(/^[0-9a-f]{64}$/) });
    expect(hashed).toBe(await sha256(idTokenCalls[0].nonce));
    // 시스템 브라우저·OAuth 주소는 쓰지 않는다
    expect(cap.browser.open).not.toHaveBeenCalled();
    expect(db().auth.signInWithOAuth).not.toHaveBeenCalled();

    expect(await screen.findByRole('heading', { name: '닉네임 정하기' })).toBeDefined();
    expect(where()).toBe('/welcome');
    expect(screen.getByText(APPLE_ONLY_TEXT, { exact: false })).toBeDefined();
    fireEvent.change(screen.getByLabelText('닉네임'), { target: { value: '사과탑' } });
    fireEvent.click(screen.getByRole('button', { name: '시작하기' }));
    await vi.waitFor(() => expect(where()).toBe('/'));
    expect(screen.queryByRole('alert')).toBeNull();
  });

  test('같은 이메일의 구글 계정에 합쳐지면: "다른 기기" 안내 없이 합쳐짐 안내', async () => {
    db().auth.signInWithIdToken = vi.fn(async () => {
      fakeLogin('u-old', { nickname: '탑장인' }, {
        created_at: '2026-01-01T00:00:00Z',
        identities: [{ provider: 'google', created_at: '2026-01-01T00:00:00Z' }, appleIdentity()],
      });
      return { data: { user: fakeState.session.user, session: fakeState.session }, error: null };
    });
    start('/login');
    fireEvent.click(await screen.findByRole('button', { name: 'Apple로 시작하기' }));
    expect((await screen.findByText(/같은 이메일로 이미 가입된 계정\(구글\)이 있어서, Apple 로그인을 그 계정에 연결했습니다/)).closest('.login-notice')).not.toBeNull();
    expect(screen.queryByText(APPLE_ONLY_TEXT, { exact: false })).toBeNull();
  });

  test('시트를 닫음: 로그인하지 않고 안내 + 버튼 다시 열림', async () => {
    cap.apple.signIn.mockRejectedValue(Object.assign(new Error('The user canceled.'), { code: 'SIGN_IN_CANCELED' }));
    start('/login');
    fireEvent.click(await screen.findByRole('button', { name: 'Apple로 시작하기' }));
    expect((await screen.findByRole('alert')).textContent).toContain('로그인 창을 닫아서 로그인하지 않았습니다. 다시 시도해 주세요.');
    expect(idTokenCalls).toEqual([]);
    expect(screen.getByRole('button', { name: 'Apple로 시작하기' }).disabled).toBe(false);
  });

  test('시트 실패(Apple 계정 없음 등)·Supabase 거절: 안내 + 버튼 다시 열림', async () => {
    cap.apple.signIn.mockRejectedValueOnce(Object.assign(new Error('AuthorizationError error 1000'), { code: '1000' }));
    start('/login');
    fireEvent.click(await screen.findByRole('button', { name: 'Apple로 시작하기' }));
    expect((await screen.findByRole('alert')).textContent).toContain('Apple 로그인을 마치지 못했습니다. 다시 시도해 주세요.');
    expect(screen.getByRole('button', { name: 'Apple로 시작하기' }).disabled).toBe(false);

    db().auth.signInWithIdToken = vi.fn(async () => ({ data: { user: null, session: null }, error: { message: 'Nonces mismatch', code: 'bad_jwt' } }));
    fireEvent.click(screen.getByRole('button', { name: 'Apple로 시작하기' }));
    await vi.waitFor(() => expect(db().auth.signInWithIdToken).toHaveBeenCalled());
    expect((await screen.findByRole('alert')).textContent).toContain('로그인을 마치지 못했습니다. 다시 시도해 주세요.');
    expect(fakeState.session).toBeNull();
  });
});

describe('iOS 앱 Apple 연결', () => {
  test('비회원 /me → [Apple 연결하기] → [지금 계정에 연결하기]: linkIdentity(token, nonce), 비회원 세션 유지 → 정식 계정 안내', async () => {
    fakeGuestLogin('g-1', { nickname: '손님' });
    start('/me');
    const box = await screen.findByRole('region', { name: '구글·카카오·Apple 연결하기' });
    fireEvent.click(within(box).getByRole('button', { name: 'Apple 연결하기' }));
    fireEvent.click(within(screen.getByRole('dialog', { name: 'Apple로 계속하기' })).getByRole('button', { name: /지금 계정에 연결하기/ }));
    await vi.waitFor(() => expect(linkCalls).toHaveLength(1));
    expect(linkCalls[0]).toEqual({ provider: 'apple', token: 'apple-id-token', nonce: expect.stringMatching(/^[0-9a-f]{64}$/) });
    expect(idTokenCalls).toEqual([]); // 새 계정으로 로그인하지 않는다
    expect(fakeState.signOutCalls).toEqual([]);
    expect((await screen.findByText(/Apple 로그인을 연결해서 정식 계정이 됐습니다/)).closest('.login-notice')).not.toBeNull();
    expect(where()).toBe('/me');
  });

  test('비회원이 고른 Apple이 이미 다른 회원 계정이면: 기존 계정으로 로그인할지 묻는다', async () => {
    fakeGuestLogin('g-2', { nickname: '손님2' });
    db().auth.linkIdentity.mockImplementation(async () => ({ data: { user: null, session: null }, error: { message: 'Identity is already linked to another user', code: 'identity_already_exists' } }));
    start('/me');
    const box = await screen.findByRole('region', { name: '구글·카카오·Apple 연결하기' });
    fireEvent.click(within(box).getByRole('button', { name: 'Apple 연결하기' }));
    fireEvent.click(within(screen.getByRole('dialog', { name: 'Apple로 계속하기' })).getByRole('button', { name: /지금 계정에 연결하기/ }));
    expect(await screen.findByText(ALREADY_MEMBER_TEXT)).toBeDefined();
  });

  test('/me/settings: Apple만 연결된 회원에게 안내 + 릴레이 이메일은 "이메일 숨김" + [구글·카카오 연결하기]', async () => {
    fakeLogin('u-apple', { nickname: '사과탑' }, { identities: [appleIdentity('x1y2@privaterelay.appleid.com')] });
    start('/me/settings');
    const section = await screen.findByRole('region', { name: '로그인 연결' });
    expect(await within(section).findByText(APPLE_ONLY_TEXT)).toBeDefined();
    expect(within(section).getByText('이메일 숨김 (Apple)')).toBeDefined();
    expect(within(section).queryByText(/privaterelay/)).toBeNull();
    expect(within(section).getByRole('button', { name: '구글 연결하기' })).toBeDefined();
    expect(within(section).getByRole('button', { name: '카카오 연결하기' })).toBeDefined();
  });

  test('/me/settings [Apple 연결하기] (구글 회원): linkIdentity → 연결 안내, "다른 기기" 안내는 없음', async () => {
    fakeLogin('u-g', { nickname: '구글탑' }, { identities: [{ provider: 'google', created_at: now() }] });
    start('/me/settings');
    const section = await screen.findByRole('region', { name: '로그인 연결' });
    fireEvent.click(await within(section).findByRole('button', { name: 'Apple 연결하기' }));
    await vi.waitFor(() => expect(linkCalls).toHaveLength(1));
    expect((await screen.findByText(/Apple 로그인을 이 계정에 연결했습니다/)).closest('.login-notice')).not.toBeNull();
    expect(screen.queryByText(APPLE_ONLY_TEXT)).toBeNull();
    expect(where()).toBe('/me/settings');
  });
});

describe('웹·안드로이드에서 Apple 가입자', () => {
  test.each([['웹', false, 'web'], ['안드로이드 앱', true, 'android']])('%s /me/settings: Apple은 "연결됨"만 보이고 연결 버튼은 없다 + 안내', async (_n, native, platform) => {
    cap.native = native;
    cap.platform = platform;
    fakeLogin('u-apple', { nickname: '사과탑' }, { identities: [appleIdentity()] });
    start('/me/settings');
    const section = await screen.findByRole('region', { name: '로그인 연결' });
    expect(await within(section).findByText('Apple')).toBeDefined();
    expect(within(section).getByText(/연결됨/)).toBeDefined();
    expect(within(section).queryByRole('button', { name: 'Apple 연결하기' })).toBeNull();
    expect(within(section).getByText(APPLE_ONLY_TEXT)).toBeDefined();
  });

  test('웹: 구글 회원의 /me/settings에는 Apple 줄이 없다', async () => {
    cap.native = false;
    fakeLogin('u-g', { nickname: '구글탑' }, { identities: [{ provider: 'google', created_at: now() }] });
    start('/me/settings');
    const section = await screen.findByRole('region', { name: '로그인 연결' });
    expect(await within(section).findByRole('button', { name: '카카오 연결하기' })).toBeDefined();
    expect(within(section).queryByText('Apple')).toBeNull();
  });
});
