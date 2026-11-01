import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { act, cleanup, fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { AppRoutes } from '../App';
import { safePath } from '../pages/Login';
import { fakeFetch } from './fakeDdragon';
import { fakeLogin, fakeState } from './fakeSupabase';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

function Where() { const l = useLocation(); return <output data-testid="where">{l.pathname}</output>; }
const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /><Where /></MemoryRouter>);
const where = () => screen.getByTestId('where').textContent;

test('로그인 전: 상단에 [로그인] → 로그인 화면에서 구글 로그인을 시작하면 원래 페이지로 돌아오게 요청한다', async () => {
  start('/champion/Darius');
  fireEvent.click(await screen.findByRole('link', { name: '로그인' }));
  expect(where()).toBe('/login');
  fireEvent.click(screen.getByRole('button', { name: '구글로 로그인' }));
  await screen.findByRole('button', { name: '구글로 이동 중…' });
  expect(fakeState.oauthCalls).toEqual([
    { provider: 'google', options: { redirectTo: `${window.location.origin}/champion/Darius` } },
  ]);
});

test('첫 로그인(닉네임 없음): 어느 페이지든 닉네임 설정으로 보내고, 저장하면 원래 페이지로 돌아간다', async () => {
  fakeLogin('u-new');
  start('/champion/Darius');
  expect(await screen.findByRole('heading', { name: '닉네임 정하기' })).toBeDefined();
  expect(where()).toBe('/welcome');

  fireEvent.change(screen.getByLabelText('닉네임'), { target: { value: '  탑신병자 ' } });
  fireEvent.click(screen.getByRole('button', { name: '시작하기' }));
  expect(await screen.findByText(/다리우스을\(를\) 이기는 챔피언/)).toBeDefined();
  expect(where()).toBe('/champion/Darius');
  expect(document.querySelector('.me').textContent).toBe('Lv.1 탑신병자'); // 칭호 없으면 칭호 자리 없음
});

test('닉네임 중복(대소문자 무시)이면 안내 문구가 보이고 화면에 머문다', async () => {
  fakeLogin('u-new');
  start('/');
  fireEvent.change(await screen.findByLabelText('닉네임'), { target: { value: '기존유저' } });
  fireEvent.click(screen.getByRole('button', { name: '시작하기' }));
  expect(await screen.findByText(/이미 사용 중인 닉네임/)).toBeDefined();
  expect(where()).toBe('/welcome');
});

test('빈 닉네임, 20자 초과 닉네임은 저장 전에 막는다', async () => {
  fakeLogin('u-new');
  start('/');
  const input = await screen.findByLabelText('닉네임');
  fireEvent.change(input, { target: { value: '   ' } });
  fireEvent.click(screen.getByRole('button', { name: '시작하기' }));
  expect(screen.getByText('닉네임을 입력해 주세요.')).toBeDefined();
  fireEvent.change(input, { target: { value: '가'.repeat(21) } });
  fireEvent.click(screen.getByRole('button', { name: '시작하기' }));
  expect(screen.getByText('닉네임은 20자 이하로 정해 주세요.')).toBeDefined();
});

test('닉네임이 있는 유저: 상단에 "Lv. 닉네임"·관리자 표시, 로그아웃하면 [로그인]으로 바뀐다', async () => {
  fakeLogin('u-admin', { nickname: '운영자', role: 'admin', level: 7, main_title: 'senior_researcher' });
  start('/');
  await screen.findByText('관리자');
  expect(document.querySelector('.me .user-name').textContent).toBe('Lv.7 수석 연구원 · 운영자');
  fireEvent.click(screen.getByRole('button', { name: '로그아웃' }));
  expect(await screen.findByRole('link', { name: '로그인' })).toBeDefined();
  expect(screen.queryByText('관리자')).toBeNull();
});

test('이미 로그인한 상태로 /login에 오면 원래 페이지로 보낸다', async () => {
  fakeLogin('u-old');
  start('/login');
  await screen.findByRole('searchbox');
  expect(where()).toBe('/');
});

test('로그인하지 않고 /welcome에 오면 로그인 화면으로 보낸다', async () => {
  start('/welcome');
  expect(await screen.findByRole('button', { name: '구글로 로그인' })).toBeDefined();
});

test('다른 탭에서 로그인해도(상태 변경 알림) 바로 반영된다', async () => {
  start('/');
  await screen.findByRole('link', { name: '로그인' });
  await act(async () => fakeLogin('u-old'));
  expect(await screen.findByRole('button', { name: '로그아웃' })).toBeDefined();
});

test('돌아갈 경로는 사이트 안 경로만 허용한다', () => {
  expect(safePath('/champion/Darius')).toBe('/champion/Darius');
  expect(safePath('//evil.com')).toBe('/');
  expect(safePath('https://evil.com')).toBe('/');
  expect(safePath(undefined)).toBe('/');
});
