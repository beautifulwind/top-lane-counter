// 036: 운영자 [관리]의 "회원" 칸 — 가입자 수, 닉네임 검색(부분 일치·최대 10명), 회원 정보(민감 정보 없음). 감독관·일반 회원·운영자 모드 끈 운영자에게는 안 보인다
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { fakeLogin, fakeState } from './fakeSupabase';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
  fakeState.memberStats = { total: 12, members: 9, guests: 3, google: 6, kakao: 4, both: 1, new_7d: 5, new_7d_members: 2 };
  fakeState.members = [
    { id: 'u-1', nickname: '탑고수', role: 'user', level: 5, main_title: 'tool_hater', is_guest: false, created_at: '2026-11-01T00:00:00Z' },
    { id: 'u-2', nickname: '탑초보', role: 'user', level: 1, main_title: null, is_guest: true, created_at: '2026-11-05T00:00:00Z' },
  ];
  fakeState.memberInfo = {
    'u-1': {
      id: 'u-1', nickname: '탑고수', role: 'user', level: 5, main_title: 'tool_hater', is_guest: false, created_at: '2026-11-01T03:00:00Z',
      providers: ['google', 'kakao'], titles: ['top_addict', 'tool_hater'], proposals: 7, posts: 3, builds: 2, comments: 11,
    },
    'u-2': {
      id: 'u-2', nickname: '탑초보', role: 'user', level: 1, main_title: null, is_guest: true, created_at: '2026-11-05T00:00:00Z',
      providers: [], titles: [], proposals: 0, posts: 0, builds: 0, comments: 0,
    },
  };
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

const start = () => render(<MemoryRouter initialEntries={['/admin']}><AppRoutes /></MemoryRouter>);
const asOp = () => fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0, main_title: null });

test('운영자: 가입자 수 — 총·정식·비회원, 구글·카카오, 최근 7일', async () => {
  asOp();
  start();
  const list = await screen.findByRole('list', { name: '가입자 수' });
  expect(list.textContent).toContain('총 가입자 12명 (정식 회원 9명 · 비회원 3명)');
  expect(list.textContent).toContain('구글 6명 · 카카오 4명');
  expect(list.textContent).toContain('최근 7일 신규 가입 5명 (정식 회원 2명)');
});

test('운영자: 닉네임 일부로 검색 → [정보 보기]에 가입일·가입 방식·레벨·칭호·활동 수만 (이메일·로그인 ID 없음)', async () => {
  asOp();
  start();
  fireEvent.change(await screen.findByLabelText('닉네임으로 회원 검색'), { target: { value: ' 탑 ' } });
  fireEvent.click(screen.getByRole('button', { name: '검색' }));
  const results = await screen.findByRole('list', { name: '검색 결과' });
  expect(within(results).getAllByRole('listitem').length).toBe(2);
  expect(fakeState.memberCalls.find((c) => c.name === 'admin_search_members').args.p_query).toBe(' 탑 ');

  fireEvent.click(within(within(results).getByRole('listitem', { name: '탑고수' })).getByRole('button', { name: '정보 보기' }));
  const info = await screen.findByRole('list', { name: '탑고수 회원 정보' });
  expect(info.textContent).toContain('가입 방식 구글, 카카오');
  expect(info.textContent).toContain('레벨 5');
  expect(info.textContent).toContain('대표 칭호 도구혐오자');
  expect(info.textContent).toContain('얻은 칭호 탑신병자, 도구혐오자');
  expect(info.textContent).toContain('제안 7개 · 글 3개 · 빌드 2개 · 댓글 11개');
  expect(info.textContent).not.toMatch(/@|이메일 주소|로그인 ID:/);

  fireEvent.click(within(results.querySelector('[aria-label="탑초보"]')).getByRole('button', { name: '정보 보기' }));
  const guest = await screen.findByRole('list', { name: '탑초보 회원 정보' });
  expect(guest.textContent).toContain('가입 방식 비회원');
});

test('운영자: 없는 닉네임은 안내만', async () => {
  asOp();
  start();
  fireEvent.change(await screen.findByLabelText('닉네임으로 회원 검색'), { target: { value: '없는사람' } });
  fireEvent.click(screen.getByRole('button', { name: '검색' }));
  expect(await screen.findByText('찾은 회원이 없습니다.')).toBeDefined();
});

test('감독관: 회원 칸이 없고 회원 함수를 부르지도 않는다', async () => {
  fakeLogin('u-mod', { nickname: '감독', role: 'moderator', level: 3, main_title: null });
  start();
  await screen.findByRole('heading', { name: /새 카운터 승인 대기/ });
  expect(screen.queryByRole('heading', { name: /^회원$/ })).toBeNull();
  expect(screen.queryByLabelText('닉네임으로 회원 검색')).toBeNull();
  expect(fakeState.memberCalls.length).toBe(0);
});

test('운영자 모드를 끈 운영자: 일반 회원처럼 /admin을 못 보고 회원 함수도 안 부른다', async () => {
  fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0, main_title: null, operator_mode: false });
  start();
  expect(await screen.findByText('운영자만 볼 수 있습니다.')).toBeDefined();
  expect(fakeState.memberCalls.length).toBe(0);
});
