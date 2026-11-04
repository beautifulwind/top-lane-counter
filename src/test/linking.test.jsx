import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { fakeLogin, fakeState } from './fakeSupabase';
import { clickMenu } from './menu';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
  sessionStorage.clear();
  window.history.replaceState(null, '', '/');
});

function Where() { const l = useLocation(); return <output data-testid="where">{l.pathname}</output>; }
const render_ = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /><Where /></MemoryRouter>);
const where = () => screen.getByTestId('where').textContent;

const ago = (min) => new Date(Date.now() - min * 60 * 1000).toISOString();
const identity = (provider, createdAt, email = 'me@example.com') => ({ provider, created_at: createdAt, identity_data: { email } });

/** 로그인/연결 버튼을 눌러 떠났다가(pending 기록) ?code=...로 돌아온 상황 */
function returnFrom(kind, provider, query, path) {
  sessionStorage.setItem('auth:pending', JSON.stringify({ kind, provider }));
  window.history.replaceState(null, '', path + query);
  return render_(path);
}

test('카카오 첫 로그인인데 같은 이메일의 구글 계정이 있었으면: 합쳐졌다고 알려 주고, 닉네임 설정 없이 그대로 들어간다', async () => {
  fakeLogin('u-old', {}, { created_at: ago(60 * 24), identities: [identity('google', ago(60 * 24)), identity('kakao', ago(0))] });
  returnFrom('signIn', 'kakao', '?code=abc', '/champion/Darius');
  expect(await screen.findByText(/이미 가입된 계정\(구글\)이 있어서, 카카오 로그인을 그 계정에 연결했습니다/)).toBeDefined();
  expect(where()).toBe('/champion/Darius');
  expect(sessionStorage.getItem('auth:pending')).toBeNull();

  fireEvent.click(screen.getByRole('button', { name: '닫기' }));
  expect(screen.queryByText(/카카오 로그인을 그 계정에 연결했습니다/)).toBeNull();
});

test('완전히 새로 가입한 카카오 계정이면 합쳐짐 안내 없이 닉네임 설정으로 간다', async () => {
  const now = ago(0);
  fakeLogin('u-new', {}, { created_at: now, identities: [identity('kakao', now)] });
  returnFrom('signIn', 'kakao', '?code=abc', '/');
  expect(await screen.findByRole('heading', { name: '닉네임 정하기' })).toBeDefined();
  expect(screen.queryByText(/연결했습니다/)).toBeNull();
});

test('예전에 이미 합쳐진 계정으로 평소처럼 로그인하면 안내를 다시 띄우지 않는다', async () => {
  fakeLogin('u-old', {}, { created_at: ago(60 * 48), identities: [identity('google', ago(60 * 48)), identity('kakao', ago(60 * 24))] });
  returnFrom('signIn', 'kakao', '?code=abc', '/');
  expect(await screen.findByText(/다리우스/)).toBeDefined();
  expect(screen.queryByText(/연결했습니다/)).toBeNull();
});

test('/me: 로그인 안 했으면 로그인 화면으로 보낸다', async () => {
  render_('/me');
  expect(await screen.findByRole('heading', { name: '로그인 · 가입' })).toBeDefined();
  expect(where()).toBe('/login');
});

test('/me: 연결된 방식은 "연결됨", 안 된 방식은 [연결하기] → linkIdentity를 /me로 돌아오게 부른다', async () => {
  fakeLogin('u-old', {}, { identities: [identity('google', ago(10), 'old@gmail.com')] });
  render_('/');
  await clickMenu('마이페이지'); // ☰ 메뉴 [마이페이지] → /me
  expect(where()).toBe('/me');

  const google = (await screen.findByText('구글')).closest('li');
  expect(within(google).getByText('연결됨')).toBeDefined();
  expect(within(google).getByText('old@gmail.com')).toBeDefined();

  fireEvent.click(screen.getByRole('button', { name: '카카오 연결하기' }));
  expect((await screen.findByRole('button', { name: '카카오로 이동 중…' })).disabled).toBe(true);
  expect(fakeState.linkCalls).toEqual([
    { provider: 'kakao', options: { redirectTo: `${window.location.origin}/me`, queryParams: { prompt: 'login' } } },
  ]);
  expect(JSON.parse(sessionStorage.getItem('auth:pending'))).toEqual({ kind: 'link', provider: 'kakao' });
});

test('/me: Supabase에서 수동 연결이 꺼져 있으면 어떻게 켜는지 알려 준다', async () => {
  fakeState.linkError = 'Manual linking is disabled';
  fakeLogin('u-old', {}, { identities: [identity('google', ago(10))] });
  render_('/me');
  fireEvent.click(await screen.findByRole('button', { name: '카카오 연결하기' }));
  expect(await screen.findByText(/Allow manual linking을 켜야 합니다/)).toBeDefined();
  expect(screen.getByRole('button', { name: '카카오 연결하기' }).disabled).toBe(false);
  expect(sessionStorage.getItem('auth:pending')).toBeNull();
});

test('/me에서 연결하고 돌아오면 연결했다고 알려 주고, 카카오도 "연결됨"이 된다', async () => {
  fakeLogin('u-old', {}, { identities: [identity('google', ago(60)), identity('kakao', ago(0))] });
  returnFrom('link', 'kakao', '?code=abc', '/me');
  expect(await screen.findByText(/카카오 로그인을 이 계정에 연결했습니다/)).toBeDefined();
  const kakao = (await screen.findByText('카카오')).closest('li');
  expect(within(kakao).getByText('연결됨')).toBeDefined();
});

test('이미 다른 회원 계정에 붙은 카카오를 연결하려 하면 쉬운 말로 알려 주고, [다시 연결하기]는 /me로 간다', async () => {
  fakeLogin('u-old', {}, { identities: [identity('google', ago(60))] });
  returnFrom('link', 'kakao', '?error=server_error&error_code=identity_already_exists&error_description=Identity+is+already+linked+to+another+user', '/me');
  expect(await screen.findByText('계정을 연결하지 못했습니다.')).toBeDefined();
  expect(screen.getByText(/이 카카오 계정은 이미 다른 회원 계정에 연결돼 있습니다/)).toBeDefined();
  fireEvent.click(screen.getByRole('link', { name: '다시 연결하기' }));
  expect(where()).toBe('/me');
  expect(screen.queryByText(/이미 다른 회원 계정에/)).toBeNull();
});
