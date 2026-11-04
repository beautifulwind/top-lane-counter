// 상단 바: 왼쪽 로고(사이트 이름), 오른쪽 ☰만. ☰ → 오른쪽 패널: 맨 위 계정, 마이페이지·자유게시판·관리(운영자), 맨 아래 로그아웃
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeGuestLogin, fakeLogin } from './fakeSupabase';
import { NAV_ITEMS, navItemsFor } from '../lib/navItems';
import { menuButton, openMenu } from './menu';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

function Where() { const l = useLocation(); return <output data-testid="where">{l.pathname}</output>; }
const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /><Where /></MemoryRouter>);
const where = () => screen.getByTestId('where').textContent;
const topbar = () => within(document.querySelector('.topbar'));
// 패널 안 링크·버튼 글자를 화면 순서대로 ('' = [X] 닫기)
const menuNames = () => [...document.querySelectorAll('.menu-panel a, .menu-panel button')].map((el) => el.textContent.trim());

test('상단 바에는 로고(사이트 이름 → 홈)와 ☰만', async () => {
  fakeLogin('u-op', { nickname: '영자(운)', role: 'admin', level: 0, main_title: null });
  start('/board');
  await menuButton();
  expect(topbar().getAllByRole('link').map((a) => a.getAttribute('href'))).toEqual(['/']);
  expect(topbar().getAllByRole('button').map((b) => b.getAttribute('aria-label'))).toEqual(['메뉴 열기']);
  expect(topbar().getByRole('link', { name: '탑신병자' })).toBeDefined();
  expect(topbar().getByText('탑은 라인전이 전부')).toBeDefined();
});

test('로그인 전: 맨 위 [로그인 · 가입](보던 페이지로 돌아오게), 자유게시판만, 로그아웃 없음', async () => {
  start('/champion/Darius');
  const menu = await openMenu();
  expect(menuNames()).toEqual(['', '로그인 · 가입', '자유게시판']); // '' = [X] 닫기
  fireEvent.click(menu.getByRole('link', { name: '로그인 · 가입' }));
  expect(where()).toBe('/login');
  expect(screen.queryByRole('dialog')).toBeNull();
});

test('회원: 맨 위 "Lv.7 [칭호] 닉네임"(글자만), 마이페이지·자유게시판·로그아웃, 관리 없음 → 마이페이지로 이동하며 닫힘', async () => {
  fakeLogin('u-user', { nickname: '탑고수', level: 7, main_title: 'solid_heavy' });
  start('/');
  const menu = await openMenu();
  const who = await menu.findByText('탑고수');
  expect(who.closest('.menu-user').textContent).toBe('Lv.7 단단묵직 탑고수');
  expect(who.closest('a')).toBeNull(); // 닉네임을 눌러도 아무 동작 없음
  expect(menu.queryByRole('link', { name: '관리' })).toBeNull();
  expect(menuNames()).toEqual(['', '마이페이지', '자유게시판', '로그아웃']);
  fireEvent.click(menu.getByRole('link', { name: '마이페이지' }));
  expect(where()).toBe('/me');
  expect(screen.queryByRole('dialog')).toBeNull();
  await screen.findByRole('heading', { level: 1, name: /탑고수/ });
  await vi.waitFor(() => expect(document.title).toBe('마이페이지 - 탑신병자'));
  // 지금 보는 페이지 항목은 강조
  const again = await openMenu();
  expect(again.getByRole('link', { name: '마이페이지' }).getAttribute('aria-current')).toBe('page');
  expect(again.getByRole('link', { name: '자유게시판' }).getAttribute('aria-current')).toBeNull();
});

test('운영자: [관리](보라)가 메뉴에, 닉네임은 "Lv.0 닉네임"만 (운영자·관리자 글자 없음)', async () => {
  fakeLogin('u-op', { nickname: '영자(운)', role: 'admin', level: 0, main_title: null });
  start('/');
  const menu = await openMenu();
  expect((await menu.findByText('영자(운)')).closest('.menu-user').textContent).toBe('Lv.0 영자(운)');
  const admin = menu.getByRole('link', { name: '관리' });
  expect(admin.getAttribute('href')).toBe('/admin');
  expect(admin.matches('.op-link')).toBe(true);
  expect(menu.getByRole('link', { name: '마이페이지' }).matches('.op-link')).toBe(false);
  expect(menuNames()).toEqual(['', '마이페이지', '자유게시판', '관리', '로그아웃']);
});

test('비회원: 닉네임 뒤 "비회원", 마이페이지·자유게시판만 — 로그아웃은 없다', async () => {
  fakeGuestLogin('g-1', { nickname: '손님' });
  start('/');
  const menu = await openMenu();
  expect((await menu.findByText('손님')).closest('.menu-user').textContent).toContain('비회원');
  expect(menuNames()).toEqual(['', '마이페이지', '자유게시판']);
});

test('닉네임 정하기 전: 맨 위 [닉네임 정하기](→ /welcome), 로그아웃은 있다', async () => {
  fakeLogin('u-fresh', {}, { email: 'fresh@x.com' });
  start('/champion/Darius');
  const menu = await openMenu();
  expect(await menu.findByText('닉네임을 아직 정하지 않았습니다.')).toBeDefined();
  expect(menuNames()).toEqual(['', '닉네임 정하기', '마이페이지', '자유게시판', '로그아웃']);
  fireEvent.click(menu.getByRole('link', { name: '닉네임 정하기' }));
  await vi.waitFor(() => expect(where()).toBe('/welcome'));
});

test('새 알림 빨간 점: ☰와 메뉴의 마이페이지 둘 다, 개수는 이름으로 읽힌다', async () => {
  fakeLogin('u-user', { nickname: '탑고수' });
  TABLES.notifications.push(
    { id: 71, user_id: 'u-user', kind: 'title_earned', message: '칭호를 얻었습니다', created_at: '2026-11-03T00:00:00Z', read_at: null },
    { id: 72, user_id: 'u-user', kind: 'title_earned', message: '칭호를 또 얻었습니다', created_at: '2026-11-03T00:00:00Z', read_at: null },
  );
  start('/');
  const btn = await screen.findByRole('button', { name: '메뉴 열기, 새 알림 2개' });
  expect(btn.querySelector('.alert-dot')).not.toBeNull();
  fireEvent.click(btn);
  const menu = within(await screen.findByRole('dialog', { name: '메뉴' }));
  expect(menu.getByRole('link', { name: '마이페이지, 새 알림 2개' }).querySelector('.alert-dot')).not.toBeNull();
  expect(menu.getByRole('link', { name: '자유게시판' }).querySelector('.alert-dot')).toBeNull();
});

test('닫기: 바깥 누르기·Esc·[X] — 닫으면 초점은 ☰로, 열면 패널 안 첫 항목으로, 열린 동안 뒤는 스크롤 안 됨', async () => {
  fakeLogin('u-user', { nickname: '탑고수' });
  start('/');
  const btn = await menuButton();

  fireEvent.click(btn);
  const panel = await screen.findByRole('dialog', { name: '메뉴' });
  expect(btn.getAttribute('aria-expanded')).toBe('true');
  await vi.waitFor(() => expect(document.activeElement).toBe(within(panel).getByRole('link', { name: '마이페이지' })));
  expect(document.body.style.overflow).toBe('hidden');
  fireEvent.click(document.querySelector('.menu-backdrop'));
  expect(screen.queryByRole('dialog')).toBeNull();
  expect(document.activeElement).toBe(btn);
  expect(document.body.style.overflow).toBe('');

  fireEvent.click(btn);
  fireEvent.keyDown(await screen.findByRole('dialog', { name: '메뉴' }), { key: 'Escape' });
  expect(screen.queryByRole('dialog')).toBeNull();
  expect(document.activeElement).toBe(btn);

  fireEvent.click(btn);
  fireEvent.click(await screen.findByRole('button', { name: '메뉴 닫기' }));
  expect(screen.queryByRole('dialog')).toBeNull();
});

test('Tab은 패널 안에서만 돈다 (끝 → 처음, 처음 → 끝)', async () => {
  fakeLogin('u-user', { nickname: '탑고수' });
  start('/');
  const menu = await openMenu();
  const close = menu.getByRole('button', { name: '메뉴 닫기' });
  const out = menu.getByRole('button', { name: '로그아웃' });
  out.focus();
  fireEvent.keyDown(out, { key: 'Tab' });
  expect(document.activeElement).toBe(close);
  fireEvent.keyDown(close, { key: 'Tab', shiftKey: true });
  expect(document.activeElement).toBe(out);
});

test('로그아웃: 메뉴가 닫히고 다시 열면 [로그인 · 가입]', async () => {
  fakeLogin('u-user', { nickname: '탑고수' });
  start('/');
  const menu = await openMenu();
  fireEvent.click(menu.getByRole('button', { name: '로그아웃' }));
  expect(screen.queryByRole('dialog')).toBeNull();
  await vi.waitFor(async () => expect((await openMenu()).getByRole('link', { name: '로그인 · 가입' })).toBeDefined());
});

test('마이페이지 맨 위 [관리]·[로그아웃] 줄은 없다 (메뉴로 옮김)', async () => {
  fakeLogin('u-op', { nickname: '영자(운)', role: 'admin', level: 0, main_title: null });
  start('/me');
  await screen.findByRole('heading', { level: 1, name: /영자/ });
  expect(document.querySelector('.account-row')).toBeNull();
  expect(screen.queryByRole('button', { name: '로그아웃' })).toBeNull();
});

test('메뉴 항목은 한 곳(navItems): 메뉴와 나중의 아래 탭 바가 같은 목록을 읽는다', () => {
  expect(NAV_ITEMS.map((it) => it.to)).toEqual(['/', '/me', '/board', '/admin']);
  expect(navItemsFor('menu', 'signedOut').map((it) => it.key)).toEqual(['board']);
  expect(navItemsFor('menu', 'operator').map((it) => it.key)).toEqual(['me', 'board', 'admin']);
  expect(navItemsFor('tab', 'member').map((it) => it.key)).toEqual(['home', 'me', 'board']);
  expect(navItemsFor('bar', 'operator')).toEqual([]); // 상단 바에 꺼낸 항목 없음
});
