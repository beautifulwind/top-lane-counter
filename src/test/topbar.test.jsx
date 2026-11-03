// 상단 바: [마이페이지] 버튼(로그인했을 때만, 빨간 점), 닉네임은 글자만, 휴대폰 폭에서 빠지는 [관리]·[로그아웃]은 마이페이지 맨 위에
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeLogin } from './fakeSupabase';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

function Where() { const l = useLocation(); return <output data-testid="where">{l.pathname}</output>; }
const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /><Where /></MemoryRouter>);
const where = () => screen.getByTestId('where').textContent;
const topbar = () => within(document.querySelector('.topbar'));

test('로그인 전: [마이페이지] 없이 [로그인 · 가입]', async () => {
  start('/');
  expect(await topbar().findByRole('link', { name: '로그인 · 가입' })).toBeDefined();
  expect(topbar().queryByRole('link', { name: /마이페이지/ })).toBeNull();
});

test('회원: [마이페이지] → /me (지금 화면이면 눌린 모양), 닉네임은 글자만, [관리] 없음', async () => {
  fakeLogin('u-user', { nickname: '탑고수', level: 7, main_title: 'solid_heavy' });
  start('/');
  const mypage = await topbar().findByRole('link', { name: '마이페이지' });
  expect(mypage.getAttribute('href')).toBe('/me');
  expect((await topbar().findByText('탑고수')).closest('a')).toBeNull(); // 닉네임을 눌러도 아무 동작 없음
  expect(document.querySelector('.me-name').className).toContain('wide-only');
  expect(topbar().queryByRole('link', { name: '관리' })).toBeNull();
  fireEvent.click(mypage);
  expect(where()).toBe('/me');
  await screen.findByRole('heading', { level: 1, name: /탑고수/ });
  expect(topbar().getByRole('link', { name: '마이페이지' }).getAttribute('aria-current')).toBe('page');
  await vi.waitFor(() => expect(document.title).toBe('마이페이지 - 탑 카운터 위키'));
});

test('빨간 점은 [마이페이지] 버튼 안에, 개수는 버튼 이름으로 읽힌다', async () => {
  fakeLogin('u-user', { nickname: '탑고수' });
  TABLES.notifications.push(
    { id: 71, user_id: 'u-user', kind: 'title_earned', message: '칭호를 얻었어요', created_at: '2026-11-03T00:00:00Z', read_at: null },
    { id: 72, user_id: 'u-user', kind: 'title_earned', message: '칭호를 또 얻었어요', created_at: '2026-11-03T00:00:00Z', read_at: null },
  );
  start('/');
  const mypage = await topbar().findByRole('link', { name: '마이페이지, 새 알림 2개' });
  expect(mypage.querySelector('.alert-dot')).not.toBeNull();
  expect(document.querySelectorAll('.topbar .alert-dot')).toHaveLength(1);
});

test('마이페이지 맨 위 계정 줄(휴대폰 폭에서만 보임): 회원은 [로그아웃], 운영자는 [관리]도', async () => {
  fakeLogin('u-user', { nickname: '탑고수' });
  start('/me');
  await screen.findByRole('heading', { level: 1, name: /탑고수/ });
  const row = document.querySelector('.account-row');
  expect(row.className).toContain('narrow-only');
  expect(within(row).queryByRole('link', { name: '관리' })).toBeNull();
  fireEvent.click(within(row).getByRole('button', { name: '로그아웃' }));
  expect(await topbar().findByRole('link', { name: '로그인 · 가입' })).toBeDefined();
  cleanup();

  fakeLogin('u-op', { nickname: '영자(운)', role: 'admin', level: 0, main_title: null });
  start('/me');
  await screen.findByRole('heading', { level: 1, name: /영자/ });
  const opRow = document.querySelector('.account-row');
  expect(within(opRow).getByRole('link', { name: '관리' }).getAttribute('href')).toBe('/admin');
  // 넓은 화면용 상단 [관리]·[로그아웃]은 그대로 있다 (CSS로 폭에 따라 하나만 보임)
  expect(topbar().getByRole('link', { name: '관리' }).className).toContain('wide-only');
  expect(topbar().getByRole('button', { name: '로그아웃' }).className).toContain('wide-only');
});

test('닉네임 정하기 전: [마이페이지]는 보이고 누르면 닉네임 정하기로, 닉네임 자리는 없음', async () => {
  fakeLogin('u-fresh', {}, { email: 'fresh@x.com' });
  start('/champion/Darius');
  const mypage = await topbar().findByRole('link', { name: '마이페이지' });
  expect(document.querySelector('.me-name')).toBeNull();
  fireEvent.click(mypage);
  await vi.waitFor(() => expect(where()).toBe('/welcome'));
});
