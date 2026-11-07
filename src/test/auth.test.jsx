import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { act, cleanup, fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { AppRoutes } from '../App';
import { safePath } from '../pages/Login';
import { fakeFetch } from './fakeDdragon';
import { fakeLogin, fakeState } from './fakeSupabase';
import { clickMenu, menuUserText, openMenu } from './menu';

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
  await clickMenu('로그인 · 가입');
  expect(where()).toBe('/login');
  fireEvent.click(screen.getByRole('button', { name: '구글로 시작하기' }));
  await screen.findByRole('button', { name: '구글로 이동 중…' });
  expect(fakeState.oauthCalls).toEqual([
    { provider: 'google', options: { redirectTo: `${window.location.origin}/champion/Darius`, queryParams: { prompt: 'select_account' } } },
  ]);
});

test('로그인 화면에서 카카오 로그인을 시작하면 provider kakao로 요청하고, 이동 중에는 두 버튼 모두 잠긴다', async () => {
  start('/login');
  fireEvent.click(await screen.findByRole('button', { name: '카카오로 시작하기' }));
  expect((await screen.findByRole('button', { name: '카카오로 이동 중…' })).disabled).toBe(true);
  expect(screen.getByRole('button', { name: '구글로 시작하기' }).disabled).toBe(true);
  expect(fakeState.oauthCalls).toEqual([
    { provider: 'kakao', options: { redirectTo: `${window.location.origin}/`, queryParams: { prompt: 'login' } } },
  ]);
});

test('카카오 첫 로그인(이메일 없음)도 쓰기 화면에 가면 닉네임 설정으로 가고, 저장하면 원래 페이지로 돌아간다', async () => {
  fakeLogin('u-kakao', {}, { email: '', app_metadata: { provider: 'kakao' } });
  start('/champion/Darius/propose');
  expect(await screen.findByRole('heading', { name: '닉네임 정하기' })).toBeDefined();
  expect(where()).toBe('/welcome');
  expect(screen.getByLabelText('닉네임').value).toBe(''); // 카카오 닉네임을 미리 채우지 않는다

  fireEvent.change(screen.getByLabelText('닉네임'), { target: { value: '카카오탑' } });
  fireEvent.click(screen.getByRole('button', { name: '시작하기' }));
  expect(await screen.findByRole('heading', { name: '다리우스 카운터 선택' })).toBeDefined();
  expect(where()).toBe('/champion/Darius/propose');
  expect(await menuUserText()).toBe('Lv.1 카카오탑');
});

test('닉네임 없음: 읽기는 그대로 + 위에 [닉네임 정하기] 띠, 정하면 원래 페이지로 돌아간다', async () => {
  fakeLogin('u-new');
  start('/champion/Darius');
  expect(await screen.findByText(/다리우스 카운터/)).toBeDefined();
  expect(where()).toBe('/champion/Darius');
  fireEvent.click(screen.getByRole('link', { name: '닉네임 정하기' }));
  expect(await screen.findByRole('heading', { name: '닉네임 정하기' })).toBeDefined();
  expect(where()).toBe('/welcome');

  fireEvent.change(screen.getByLabelText('닉네임'), { target: { value: '  탑고수 ' } });
  fireEvent.click(screen.getByRole('button', { name: '시작하기' }));
  expect(await screen.findByText(/다리우스 카운터/)).toBeDefined();
  expect(where()).toBe('/champion/Darius');
  expect(await menuUserText()).toBe('Lv.1 탑고수'); // 칭호 없으면 칭호 자리 없음
});

test('닉네임 중복(대소문자 무시)이면 안내 문구가 보이고 화면에 머문다', async () => {
  fakeLogin('u-new');
  start('/welcome');
  fireEvent.change(await screen.findByLabelText('닉네임'), { target: { value: '기존유저' } });
  fireEvent.click(screen.getByRole('button', { name: '시작하기' }));
  expect(await screen.findByText(/이미 사용 중인 닉네임/)).toBeDefined();
  expect(where()).toBe('/welcome');
});

test('빈 닉네임, 20자 초과 닉네임은 저장 전에 막는다', async () => {
  fakeLogin('u-new');
  start('/welcome');
  const input = await screen.findByLabelText('닉네임');
  fireEvent.change(input, { target: { value: '   ' } });
  fireEvent.click(screen.getByRole('button', { name: '시작하기' }));
  expect(screen.getByText('닉네임을 입력해 주세요.')).toBeDefined();
  fireEvent.change(input, { target: { value: '가'.repeat(21) } });
  fireEvent.click(screen.getByRole('button', { name: '시작하기' }));
  expect(screen.getByText('닉네임은 20자 이하로 정해 주세요.')).toBeDefined();
});

test('닉네임에 (운)·(감)과 그 변형은 저장 전에 막는다', async () => {
  fakeLogin('u-new');
  start('/welcome');
  const input = await screen.findByLabelText('닉네임');
  for (const v of ['탑(운)', '（감）탑', '[운]', '( 운 )']) {
    fireEvent.change(input, { target: { value: v } });
    fireEvent.click(screen.getByRole('button', { name: '시작하기' }));
    expect(screen.getByText('닉네임에는 (운)·(감)을 쓸 수 없습니다.')).toBeDefined();
  }
  expect(where()).toBe('/welcome');
});

test('닉네임이 있는 유저: 상단에 "Lv.7 [칭호] 닉네임", 로그아웃하면 [로그인]으로 바뀐다', async () => {
  fakeLogin('u-user', { nickname: '탑고수', level: 7, main_title: 'solid_heavy' });
  start('/');
  expect(await menuUserText()).toBe('Lv.7 단단묵직 탑고수');
  await clickMenu('로그아웃', 'button');
  await vi.waitFor(async () => expect((await openMenu()).getByRole('link', { name: '로그인 · 가입' })).toBeDefined());
});

test('운영자: 상단에 "Lv.0 닉네임"만 보이고 "운영자"·"관리자" 글자는 붙지 않는다', async () => {
  fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0, main_title: null });
  start('/');
  expect(await menuUserText()).toBe('Lv.0 (운)영자');
  expect(document.querySelector('.topbar').textContent).not.toMatch(/운영자|관리자/);
});

test('운영자 페이지(/admin)에도 관리자 지정 기능은 없다 (SPEC: 나중에 정함)', async () => {
  fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0, main_title: null });
  start('/admin');
  expect(await screen.findByRole('heading', { name: '운영자 페이지' })).toBeDefined();
  await screen.findByText('대기 중인 제안이 없습니다.');
  expect(screen.queryByText(/관리자 지정|권한 변경|관리자로/)).toBeNull();
});

test('이미 로그인한 상태로 /login에 오면 원래 페이지로 보낸다', async () => {
  fakeLogin('u-old');
  start('/login');
  await screen.findByRole('searchbox');
  expect(where()).toBe('/');
});

test('로그인하지 않고 /welcome에 오면 로그인 화면으로 보낸다', async () => {
  start('/welcome');
  expect(await screen.findByRole('button', { name: '구글로 시작하기' })).toBeDefined();
});

test('다른 탭에서 로그인해도(상태 변경 알림) 바로 반영된다', async () => {
  start('/');
  const menu = await openMenu();
  expect(menu.getByRole('link', { name: '로그인 · 가입' })).toBeDefined();
  await act(async () => fakeLogin('u-old'));
  expect(await menu.findByRole('button', { name: '로그아웃' })).toBeDefined(); // 열어 둔 메뉴도 바로 바뀐다
});

test('돌아갈 경로는 사이트 안 경로만 허용한다', () => {
  expect(safePath('/champion/Darius')).toBe('/champion/Darius');
  expect(safePath('//evil.com')).toBe('/');
  expect(safePath('https://evil.com')).toBe('/');
  expect(safePath(undefined)).toBe('/');
});
