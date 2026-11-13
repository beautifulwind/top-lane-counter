// 비회원으로 시작하기 (020): 로그인 화면 · 캡차 · 비회원 표시 · 로그아웃 없음 · 연결/새 계정 · 이미 가입된 계정 · 투표 막기 · 기록 지우기
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { act, cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeGuestLogin, fakeLogin, fakePost, fakeState } from './fakeSupabase';
import { ALREADY_MEMBER_TEXT } from '../lib/guest';
import { openMenu } from './menu';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
  localStorage.clear();
  sessionStorage.clear();
  vi.stubEnv('VITE_TURNSTILE_SITE_KEY', ''); // .env에 진짜 키가 있어도 기본은 "캡차 없음" (fakeTurnstile이 다시 넣음)
});
afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
  vi.unstubAllEnvs();
  delete window.turnstile;
  window.history.replaceState(null, '', '/');
});

function Where() { const l = useLocation(); return <output data-testid="where">{l.pathname}</output>; }
const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /><Where /></MemoryRouter>);
const where = () => screen.getByTestId('where').textContent;
const MATCHUP = '/champion/Darius/counter/Quinn';
const guestWithName = () => fakeGuestLogin('g-1', { nickname: '손님' });

// ---------------- 로그인 화면 ----------------

test('로그인 화면: 구글·카카오·비회원 버튼, 비회원은 안내 칸을 열고 [비회원으로 시작] → 닉네임 정하기', async () => {
  start('/login');
  expect(await screen.findByRole('button', { name: '구글로 시작하기' })).toBeDefined();
  expect(screen.getByRole('button', { name: /카카오로 시작하기/ })).toBeDefined();
  fireEvent.click(screen.getByRole('button', { name: '비회원으로 시작하기' }));
  const panel = screen.getByRole('region', { name: '비회원으로 시작' });
  expect(within(panel).getByText(/이 기기·브라우저에만 저장됩니다/)).toBeDefined();
  expect(within(panel).getByText(/아이폰 사파리는 7일/)).toBeDefined();
  fireEvent.click(within(panel).getByRole('button', { name: '비회원으로 시작' })); // 사이트 키 없음 = 캡차 없이
  expect(await screen.findByRole('heading', { name: '닉네임 정하기' })).toBeDefined();
  expect(where()).toBe('/welcome');
  expect(fakeState.anonCalls).toEqual([undefined]);
  // 닉네임 없는 비회원은 /me에 못 가므로 여기서 지울 수 있다
  expect(screen.getByRole('region', { name: '비회원 기록 지우기' })).toBeDefined();
});

test('[취소]·Esc로 비회원 안내 칸이 닫힌다', async () => {
  start('/login');
  fireEvent.click(await screen.findByRole('button', { name: '비회원으로 시작하기' }));
  fireEvent.click(within(screen.getByRole('region', { name: '비회원으로 시작' })).getByRole('button', { name: '취소' }));
  expect(screen.queryByRole('region', { name: '비회원으로 시작' })).toBeNull();
  fireEvent.click(screen.getByRole('button', { name: '비회원으로 시작하기' }));
  fireEvent.keyDown(screen.getByRole('button', { name: '비회원으로 시작' }), { key: 'Escape' });
  expect(screen.queryByRole('region', { name: '비회원으로 시작' })).toBeNull();
});

test('캡차: 사이트 키가 있으면 확인을 통과해야 [비회원으로 시작]이 눌리고, 토큰을 Supabase에 넘긴다', async () => {
  vi.stubEnv('VITE_TURNSTILE_SITE_KEY', 'site-key');
  let opts = null;
  window.turnstile = { render: vi.fn((_, o) => { opts = o; return 'w1'; }), remove: vi.fn() };
  start('/login');
  fireEvent.click(await screen.findByRole('button', { name: '비회원으로 시작하기' }));
  const go = screen.getByRole('button', { name: '비회원으로 시작' });
  expect(go.disabled).toBe(true);
  await vi.waitFor(() => expect(opts).not.toBeNull());
  expect(opts.sitekey).toBe('site-key');
  act(() => opts.callback('tok-1'));
  expect(go.disabled).toBe(false);
  act(() => opts['expired-callback']());
  expect(go.disabled).toBe(true);
  act(() => opts.callback('tok-2'));
  fireEvent.click(go);
  await screen.findByRole('heading', { name: '닉네임 정하기' });
  expect(fakeState.anonCalls).toEqual([{ options: { captchaToken: 'tok-2' } }]);
});

/** 가짜 Turnstile: render 옵션을 잡아 두고 reset 호출을 센다 */
function fakeTurnstile() {
  vi.stubEnv('VITE_TURNSTILE_SITE_KEY', 'site-key');
  const ts = { opts: null, render: vi.fn((_, o) => { ts.opts = o; return 'w1'; }), reset: vi.fn(), remove: vi.fn() };
  window.turnstile = ts;
  return ts;
}

test('캡차: 시작에 실패하면 위젯을 reset해 새 토큰을 받고, 쓴 토큰은 다시 보내지 않는다', async () => {
  const ts = fakeTurnstile();
  fakeState.anonError = 'captcha protection: request disallowed (timeout-or-duplicate)';
  start('/login');
  fireEvent.click(await screen.findByRole('button', { name: '비회원으로 시작하기' }));
  await vi.waitFor(() => expect(ts.opts).not.toBeNull());
  act(() => ts.opts.callback('tok-1'));
  fireEvent.click(screen.getByRole('button', { name: '비회원으로 시작' }));
  expect(await screen.findByText('자동 가입 방지 확인을 다시 해 주세요.')).toBeDefined();
  expect(ts.reset).toHaveBeenCalledWith('w1');
  const go = screen.getByRole('button', { name: '비회원으로 시작' });
  expect(go.disabled).toBe(true); // 새 확인을 받을 때까지 잠김
  fireEvent.click(go);
  expect(fakeState.anonCalls).toHaveLength(1);
  fakeState.anonError = null;
  act(() => ts.opts.callback('tok-2'));
  fireEvent.click(go);
  await screen.findByRole('heading', { name: '닉네임 정하기' });
  expect(fakeState.anonCalls.map((c) => c.options.captchaToken)).toEqual(['tok-1', 'tok-2']);
});

test('캡차: 시간 초과(timeout)·오류도 버튼을 다시 잠근다', async () => {
  const ts = fakeTurnstile();
  start('/login');
  fireEvent.click(await screen.findByRole('button', { name: '비회원으로 시작하기' }));
  await vi.waitFor(() => expect(ts.opts).not.toBeNull());
  const go = screen.getByRole('button', { name: '비회원으로 시작' });
  for (const event of ['timeout-callback', 'error-callback', 'expired-callback']) {
    act(() => ts.opts.callback('tok'));
    expect(go.disabled).toBe(false);
    act(() => ts.opts[event]());
    expect(go.disabled).toBe(true);
  }
});

test('[비회원으로 시작]을 빠르게 두 번 눌러도 signInAnonymously는 한 번만', async () => {
  const ts = fakeTurnstile();
  start('/login');
  fireEvent.click(await screen.findByRole('button', { name: '비회원으로 시작하기' }));
  await vi.waitFor(() => expect(ts.opts).not.toBeNull());
  act(() => ts.opts.callback('tok-1'));
  const go = screen.getByRole('button', { name: '비회원으로 시작' });
  fireEvent.click(go);
  fireEvent.click(go);
  await screen.findByRole('heading', { name: '닉네임 정하기' });
  expect(fakeState.anonCalls).toHaveLength(1);
});

test('캡차 없이(사이트 키 없음)도 두 번 눌러 두 번 시작하지 않는다', async () => {
  let release;
  fakeState.anonDelay = new Promise((r) => { release = r; });
  start('/login');
  fireEvent.click(await screen.findByRole('button', { name: '비회원으로 시작하기' }));
  const go = screen.getByRole('button', { name: '비회원으로 시작' });
  fireEvent.click(go);
  fireEvent.click(go);
  expect(await screen.findByRole('button', { name: '시작하는 중…' })).toBeDefined();
  release();
  await screen.findByRole('heading', { name: '닉네임 정하기' });
  expect(fakeState.anonCalls).toHaveLength(1);
});

test('Supabase에서 익명 로그인이 꺼져 있으면 이유를 알려 준다', async () => {
  fakeState.anonError = 'Anonymous sign-ins are disabled';
  start('/login');
  fireEvent.click(await screen.findByRole('button', { name: '비회원으로 시작하기' }));
  fireEvent.click(screen.getByRole('button', { name: '비회원으로 시작' }));
  expect(await screen.findByText(/Allow anonymous sign-ins를 켜야 합니다/)).toBeDefined();
  expect(where()).toBe('/login');
});

// ---------------- 표시 · 로그아웃 없음 ----------------

test('비회원: 메뉴에 [마이페이지]·[탑신병자 커뮤니티]만, 로그아웃은 어디에도 없고 닉네임 옆에 "비회원"', async () => {
  guestWithName();
  start('/me');
  const menu = await openMenu();
  expect(menu.getByRole('link', { name: '마이페이지' })).toBeDefined();
  expect(menu.queryByRole('button', { name: '로그아웃' })).toBeNull();
  expect(document.querySelector('.menu-user .guest-badge')).not.toBeNull();
  fireEvent.keyDown(menu.getByRole('button', { name: '메뉴 닫기' }), { key: 'Escape' });
  expect(screen.queryByRole('button', { name: '로그아웃' })).toBeNull();
  const title = await screen.findByRole('heading', { level: 1 });
  expect(within(title).getByText('비회원')).toBeDefined();
  // 구글·카카오 연결 칸이 맨 위에, 회원용 "로그인 연결"은 없음
  expect(screen.getByRole('region', { name: '구글·카카오 연결하기' })).toBeDefined();
  expect(screen.queryByRole('region', { name: '로그인 연결' })).toBeNull();
  expect(fakeState.touched).toBeGreaterThan(0); // 마지막 접속 기록
});

test('회원 닉네임에는 "비회원"이 붙지 않는다', async () => {
  fakeLogin('u-old');
  start('/me');
  const title = await screen.findByRole('heading', { level: 1 });
  expect(within(title).queryByText('비회원')).toBeNull();
});

// ---------------- 연결 / 새 계정 ----------------

test('/me [구글 연결하기] → [지금 계정에 연결하기] → linkIdentity (돌아오면 "정식 계정" 안내)', async () => {
  guestWithName();
  start('/me');
  const box = await screen.findByRole('region', { name: '구글·카카오 연결하기' });
  fireEvent.click(within(box).getByRole('button', { name: '구글 연결하기' }));
  const dialog = screen.getByRole('dialog', { name: '구글로 계속하기' });
  expect(document.activeElement).toBe(within(dialog).getByRole('button', { name: '취소' }));
  fireEvent.click(within(dialog).getByRole('button', { name: /지금 계정에 연결하기/ }));
  await vi.waitFor(() => expect(fakeState.linkCalls).toHaveLength(1));
  expect(fakeState.linkCalls[0].provider).toBe('google');
  expect(JSON.parse(sessionStorage.getItem('auth:pending'))).toEqual({ kind: 'upgrade', provider: 'google' });
  expect(fakeState.signOutCalls).toEqual([]);
});

test('[새 계정으로 시작하기] → 경고 → 이 기기에서만 비회원 세션을 지우고 카카오 로그인', async () => {
  guestWithName();
  start('/me');
  const box = await screen.findByRole('region', { name: '구글·카카오 연결하기' });
  fireEvent.click(within(box).getByRole('button', { name: '카카오 연결하기' }));
  const dialog = screen.getByRole('dialog', { name: '카카오로 계속하기' });
  fireEvent.click(within(dialog).getByRole('button', { name: '새 계정으로 시작하기' }));
  expect(within(dialog).getByText(/다시 들어올 수 없습니다/)).toBeDefined();
  fireEvent.click(within(dialog).getByRole('button', { name: '카카오 새 계정으로 시작' }));
  await vi.waitFor(() => expect(fakeState.oauthCalls).toHaveLength(1));
  expect(fakeState.signOutCalls).toEqual([{ scope: 'local' }]);
  expect(fakeState.oauthCalls[0].provider).toBe('kakao');
  expect(fakeState.linkCalls).toEqual([]);
});

test('선택 창은 Esc·[취소]로 닫힌다', async () => {
  guestWithName();
  start('/me');
  const box = await screen.findByRole('region', { name: '구글·카카오 연결하기' });
  fireEvent.click(within(box).getByRole('button', { name: '구글 연결하기' }));
  fireEvent.keyDown(screen.getByRole('dialog'), { key: 'Escape' });
  expect(screen.queryByRole('dialog')).toBeNull();
  fireEvent.click(within(box).getByRole('button', { name: '구글 연결하기' }));
  fireEvent.click(within(screen.getByRole('dialog')).getByRole('button', { name: '취소' }));
  expect(screen.queryByRole('dialog')).toBeNull();
});

test('로그인 화면에 온 비회원: 돌려보내지 않고, 구글을 누르면 같은 선택 창', async () => {
  guestWithName();
  start('/login');
  expect(await screen.findByText(/지금은 비회원입니다/)).toBeDefined();
  expect(screen.queryByRole('button', { name: '비회원으로 시작하기' })).toBeNull();
  fireEvent.click(screen.getByRole('button', { name: '구글로 시작하기' }));
  expect(screen.getByRole('dialog', { name: '구글로 계속하기' })).toBeDefined();
  expect(fakeState.oauthCalls).toEqual([]);
});

function returnFrom(query, path) {
  sessionStorage.setItem('auth:pending', JSON.stringify({ kind: 'upgrade', provider: 'kakao' }));
  window.history.replaceState(null, '', path + query);
  return start(path);
}

test('연결하고 돌아오면 정식 계정이 됐다고 알려 준다', async () => {
  fakeLogin('g-1', { nickname: '손님' });
  returnFrom('?code=abc', '/me');
  expect(await screen.findByText(/정식 계정이 됐습니다/)).toBeDefined();
});

test('이미 다른 회원의 카카오면: 합치지 않고 [기존 계정으로 로그인] → 비회원 세션을 지우고 카카오 로그인', async () => {
  guestWithName();
  returnFrom('?error=server_error&error_code=identity_already_exists&error_description=Identity+is+already+linked+to+another+user', '/me');
  const alert = (await screen.findByText(ALREADY_MEMBER_TEXT, { exact: false })).closest('[role=alert]');
  expect(within(alert).queryByRole('link', { name: '다시 연결하기' })).toBeNull();
  fireEvent.click(within(alert).getByRole('button', { name: '기존 계정으로 로그인' }));
  await vi.waitFor(() => expect(fakeState.oauthCalls).toHaveLength(1));
  expect(fakeState.signOutCalls).toEqual([{ scope: 'local' }]);
  expect(fakeState.oauthCalls[0].provider).toBe('kakao');
});

// ---------------- 투표·추천·신고 막기 ----------------

test('비회원이 추천을 누르면 투표 대신 연결 안내', async () => {
  guestWithName();
  start(MATCHUP);
  const card = await screen.findByRole('article', { name: '빌드: 탑고수' });
  fireEvent.click(within(card).getByRole('button', { name: '추천 5' }));
  expect(within(card).getByText(/비회원은 추천·비추천을 누를 수 없습니다/)).toBeDefined();
  expect(within(card).getByRole('link', { name: '구글·카카오 연결하기' }).getAttribute('href')).toBe('/me#upgrade');
  expect(fakeState.rpcCalls.filter((c) => c.name === 'vote_build')).toEqual([]);
});

test('탑신병자 커뮤니티 글: 비회원은 [추천]·[신고] 없이 안내만, 댓글은 쓸 수 있다', async () => {
  TABLES.posts.push(fakePost(1));
  guestWithName();
  start('/board/1');
  expect(await screen.findByText(/비회원은 추천·신고를 할 수 없습니다/)).toBeDefined();
  expect(screen.queryByRole('button', { name: /추천/ })).toBeNull();
  expect(screen.queryByRole('button', { name: '신고' })).toBeNull();
  expect(screen.getByLabelText(/댓글/, { selector: 'textarea' })).toBeDefined();
});

// ---------------- 비회원 기록 지우기 ----------------

test('/me/settings "비회원 기록 지우기": 닉네임을 입력해야 확정, 지우면 홈에서 안내', async () => {
  guestWithName();
  start('/me/settings');
  expect(screen.queryByRole('region', { name: '로그인 연결' })).toBeNull(); // 비회원 연결은 마이페이지 맨 위 칸
  const sec = await screen.findByRole('region', { name: '비회원 기록 지우기' });
  expect(screen.queryByRole('region', { name: '회원 탈퇴' })).toBeNull();
  fireEvent.click(within(sec).getByRole('button', { name: '비회원 기록 지우기' }));
  const go = within(sec).getByRole('button', { name: '지우기 확정' });
  expect(go.disabled).toBe(true);
  fireEvent.change(within(sec).getByRole('textbox'), { target: { value: '손님' } });
  fireEvent.click(go);
  expect(await screen.findByText(/비회원 기록을 지웠습니다/)).toBeDefined();
  expect(where()).toBe('/');
  expect(fakeState.functionCalls).toEqual([{ name: 'delete-account', body: { confirm: '손님' } }]);
});

test('닉네임 없는 비회원: /welcome에서 "지우기"를 입력해 지운다', async () => {
  fakeGuestLogin('g-2');
  start('/welcome');
  const sec = await screen.findByRole('region', { name: '비회원 기록 지우기' });
  fireEvent.click(within(sec).getByRole('button', { name: '비회원 기록 지우기' }));
  fireEvent.change(within(sec).getByRole('textbox'), { target: { value: '지우기' } });
  fireEvent.click(within(sec).getByRole('button', { name: '지우기 확정' }));
  expect(await screen.findByText(/비회원 기록을 지웠습니다/)).toBeDefined();
  expect(fakeState.functionCalls).toEqual([{ name: 'delete-account', body: { confirm: '지우기' } }]);
});
