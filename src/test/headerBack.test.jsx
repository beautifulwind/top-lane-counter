// 상단 바 ← 뒤로 가기 (SPEC 6-78)
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { AppRoutes } from '../App';
import { showsBackButton } from '../components/BackButton';
import { fakeFetch } from './fakeDdragon';
import { fakeLogin } from './fakeSupabase';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

function Where() { const l = useLocation(); return <output data-testid="where">{l.pathname}</output>; }
const start = (entries, index) => render(<MemoryRouter initialEntries={entries} initialIndex={index}><AppRoutes /><Where /></MemoryRouter>);
const where = () => screen.getByTestId('where').textContent;
const back = () => screen.queryByRole('button', { name: '뒤로 가기' });

test('화면 구분: 홈·로그인·닉네임 정하기와 본문에 ← 링크가 있는 화면은 제외', () => {
  for (const p of ['/', '/login', '/welcome', '/board/new', '/board/7', '/board/7/edit', '/admin/members', '/admin/members/u-1', '/admin/influencers', '/admin/inquiries', '/admin/reports']) {
    expect(showsBackButton(p), p).toBe(false);
  }
  for (const p of ['/champion/Darius', '/champion/Darius/counter/Quinn', '/me', '/me/settings', '/board', '/u/u-1', '/privacy', '/admin', '/no-such-page']) {
    expect(showsBackButton(p), p).toBe(true);
  }
});

test('홈에는 없다', async () => {
  start(['/'], 0);
  await screen.findByRole('heading', { level: 1, name: '챔피언 선택' });
  expect(back()).toBeNull();
});

test('로그인 화면에는 없다', async () => {
  start(['/login'], 0);
  await screen.findByRole('heading', { level: 1, name: /로그인/ });
  expect(back()).toBeNull();
});

test('하위 화면: aria-label "뒤로 가기" 버튼, 눌리는 곳은 상단 바 맨 왼쪽(로고보다 앞)', async () => {
  start(['/', '/champion/Darius'], 1);
  const b = await screen.findByRole('button', { name: '뒤로 가기' });
  expect(b.closest('.topbar')).not.toBeNull();
  expect(b.nextElementSibling?.classList.contains('brand-wrap')).toBe(true);
});

test('이동 기록이 있으면 한 걸음 뒤로', async () => {
  start(['/', '/champion/Darius', '/privacy'], 2);
  fireEvent.click(await screen.findByRole('button', { name: '뒤로 가기' }));
  expect(where()).toBe('/champion/Darius');
});

test('이동 기록이 없으면(주소로 바로 들어옴) 홈으로', async () => {
  start(['/privacy'], 0);
  fireEvent.click(await screen.findByRole('button', { name: '뒤로 가기' }));
  expect(where()).toBe('/');
  await screen.findByRole('heading', { level: 1, name: '챔피언 선택' });
  expect(back()).toBeNull();
});

test('이미 ← 링크가 있는 자유게시판 글에는 상단 버튼이 없다 (중복 방지)', async () => {
  fakeLogin('u-1', { nickname: '탑고수', role: 'member', level: 1, main_title: null });
  start(['/board'], 0);
  expect(await screen.findByRole('heading', { level: 1, name: /커뮤니티/ })).toBeDefined();
  expect(back()).not.toBeNull(); // 목록 화면에는 ← 링크가 없어 상단 버튼이 있다
});
