// 042: 운영자 회원 관리(/admin/members) — 가입자 수, 최근 가입 순 목록, 닉네임 검색, 등급 거르기, 회원 정보 페이지(글·댓글·고친 빌드·처리 이력·지운 글), 탈퇴한 이용자. 감독관·일반 회원·운영자 모드 끈 운영자에게는 안 보인다
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
  fakeState.memberDetail = {
    'u-1': {
      info: {
        id: 'u-1', nickname: '탑고수', role: 'user', level: 5, main_title: 'tool_hater', is_guest: false, created_at: '2026-11-01T03:00:00Z',
        providers: ['google', 'kakao'], titles: ['top_addict', 'tool_hater'], proposals: 7, posts: 3, builds: 2, comments: 11, matchups: 4, xp: 640,
        deleted_posts: 1, deleted_comments: 2,
      },
      posts: [{ id: 31, title: '탑 라인 질문', excerpt: '다리우스 어렵다', created_at: '2026-11-08T00:00:00Z', status: 'hidden', comment_count: 2 }],
      comments: [
        { kind: 'post', id: 5, post_id: 31, post_title: '탑 라인 질문', excerpt: '저도 궁금합니다', created_at: '2026-11-08T01:00:00Z', status: 'visible' },
        { kind: 'doc', id: 6, counter_id: 9, target_champion: 'Darius', counter_champion: 'Quinn', excerpt: '사거리가 핵심', created_at: '2026-11-09T01:00:00Z', status: 'visible' },
      ],
      edited_builds: [{ build_id: 77, seq: 2, name: '라인전 빌드', status: 'approved', counter_id: 9, target_champion: 'Darius', counter_champion: 'Quinn', edits: 3, first_at: '2026-11-05T00:00:00Z', last_at: '2026-11-09T00:00:00Z' }],
      moderation: [
        { id: 1, action: 'hide', target_kind: 'post', target_id: '31', note: '광고', created_at: '2026-11-09T05:00:00Z', actor_role: 'moderator', actor_nickname: '탈퇴한 이용자', actor_withdrawn: true },
        { id: 2, action: 'grant_moderator', target_kind: 'user', target_id: 'u-1', note: '맡김', created_at: '2026-11-07T05:00:00Z', actor_role: 'admin', actor_nickname: '영자', actor_withdrawn: false },
      ],
    },
    'u-2': {
      info: { id: 'u-2', nickname: '탑초보', role: 'user', level: 1, main_title: null, is_guest: true, created_at: '2026-11-05T00:00:00Z',
        providers: [], titles: [], proposals: 0, posts: 0, builds: 0, comments: 0, matchups: 0, xp: 0 },
      posts: [], comments: [], edited_builds: [], moderation: [],
    },
  };
  fakeState.deletedWritings = {
    'u-1': {
      keep_days: 365,
      posts: [{ id: 40, title: '지운 글 제목', body: '지운 글 본문', deleted_at: '2026-11-10T00:00:00Z', delete_kind: 'staff', delete_note: '광고', deleted_by: { nickname: '영자', role: 'admin' } }],
      comments: [{ id: 8, post_id: 31, post_title: '탑 라인 질문', body: '지운 댓글 내용', deleted_at: '2026-11-09T00:00:00Z', delete_kind: 'author', delete_note: null, deleted_by: { nickname: '탑고수', role: 'user' } }],
      doc_comments: [],
    },
  };
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

const start = (path = '/admin/members') => render(<MemoryRouter initialEntries={[path]}><AppRoutes /></MemoryRouter>);
const asOp = () => fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0, main_title: null });
const rpc = (name) => fakeState.memberCalls.filter((c) => c.name === name);

test('운영자 /admin: 회원·감독관 관리 칸은 "회원 관리" 링크 하나로 합쳐졌다', async () => {
  asOp();
  start('/admin');
  const link = await screen.findByRole('link', { name: '회원 관리 열기' });
  expect(link.getAttribute('href')).toBe('/admin/members');
  expect(screen.queryByRole('heading', { name: /감독관 관리/ })).toBeNull();
  expect(screen.queryByLabelText('닉네임으로 회원 검색')).toBeNull();
});

test('운영자: 가입자 수 — 총·정식·비회원, 구글·카카오, 최근 7일', async () => {
  asOp();
  start();
  const list = await screen.findByRole('list', { name: '가입자 수' });
  expect(list.textContent).toContain('총 가입자 12명 (정식 회원 9명 · 비회원 3명)');
  expect(list.textContent).toContain('구글 6명 · 카카오 4명');
  expect(list.textContent).toContain('최근 7일 신규 가입 5명 (정식 회원 2명)');
});

test('운영자: 목록은 최근 가입 순, 이메일·로그인 ID 없음, 닉네임 일부로 검색, 등급 거르기', async () => {
  asOp();
  start();
  const list = await screen.findByRole('list', { name: '회원 목록' });
  expect(within(list).getAllByRole('listitem').map((li) => li.getAttribute('aria-label'))).toEqual(['탑초보', '탑고수']); // 11-05가 11-01보다 최근
  expect(list.textContent).not.toMatch(/@|로그인 ID:/);
  expect(fakeState.memberCalls.find((c) => c.name === 'admin_member_list').args).toMatchObject({ p_query: null, p_role: null, p_page: 1, p_size: 20 });

  fireEvent.change(screen.getByLabelText('닉네임으로 회원 검색'), { target: { value: ' 고수 ' } });
  fireEvent.click(screen.getByRole('button', { name: '검색' }));
  await vi.waitFor(() => expect(within(screen.getByRole('list', { name: '회원 목록' })).getAllByRole('listitem').length).toBe(1));
  expect(rpc('admin_member_list').at(-1).args.p_query).toBe('고수');

  fireEvent.change(screen.getByLabelText('등급으로 거르기'), { target: { value: 'moderator' } });
  expect(await screen.findByText('찾은 회원이 없습니다.')).toBeDefined();
});

test('운영자: 없는 닉네임은 안내만', async () => {
  asOp();
  start();
  fireEvent.change(await screen.findByLabelText('닉네임으로 회원 검색'), { target: { value: '없는사람' } });
  fireEvent.click(screen.getByRole('button', { name: '검색' }));
  expect(await screen.findByText('찾은 회원이 없습니다.')).toBeDefined();
});

test('운영자: 회원을 누르면 회원 정보 — 기본 정보·활동 수·글·댓글·고친 빌드·처리 이력 (이메일·로그인 ID 없음)', async () => {
  asOp();
  start();
  fireEvent.click(await screen.findByRole('link', { name: '탑고수 회원 정보' }));
  const info = await screen.findByRole('list', { name: '탑고수 회원 정보' });
  expect(info.textContent).toContain('가입 방식 구글, 카카오');
  expect(info.textContent).toContain('레벨 5 · 경험치 640 · 대표 칭호 도구혐오자');
  expect(info.textContent).toContain('얻은 칭호 탑신병자, 도구혐오자');
  expect(info.textContent).toContain('글 3개 · 댓글 11개 · 상대법 4개 · 빌드 2개');
  expect(info.textContent).not.toMatch(/@|이메일 주소|로그인 ID:/);
  expect(rpc('admin_member_detail')[0].args.p_user).toBe('u-1');

  const posts = screen.getByRole('list', { name: '쓴 글' });
  expect(posts.textContent).toContain('탑 라인 질문');
  expect(posts.textContent).toContain('(숨김)');
  expect(within(posts).getByRole('link', { name: '탑 라인 질문' }).getAttribute('href')).toBe('/board/31');
  const comments = screen.getByRole('list', { name: '쓴 댓글' });
  expect(comments.textContent).toContain('저도 궁금합니다');
  expect(within(comments).getByRole('link', { name: /상대법 「.+이기는 법」/ }).getAttribute('href')).toBe('/champion/Darius/counter/Quinn#comments');
  const builds = screen.getByRole('list', { name: '고친 빌드 목록' });
  expect(builds.textContent).toContain('빌드 2 (라인전 빌드)');
  expect(builds.textContent).toContain('3번 고침');
  expect(within(builds).getByRole('link').getAttribute('href')).toBe('/champion/Darius/counter/Quinn?build=77');
  const log = screen.getByRole('list', { name: '처리 이력 목록' });
  expect(log.textContent).toContain('숨김 · 글 #31');
  expect(log.textContent).toContain('감독관 지정 · 회원');
  expect(log.textContent).toContain('탈퇴한 이용자 (감독관)');
});

test('운영자: 지운 글·댓글은 열었을 때만 불러오고 내용·사유가 보인다', async () => {
  asOp();
  start('/admin/members/u-1');
  await screen.findByRole('list', { name: '탑고수 회원 정보' });
  expect(fakeState.memberCalls.some((c) => c.name === 'admin_deleted_writings')).toBe(false);
  fireEvent.click(screen.getByText(/지운 글·댓글 \(운영자만 볼 수 있음\)/));
  const del = await screen.findByRole('list', { name: '지운 글·댓글' });
  expect(del.textContent).toContain('지운 글 본문');
  expect(del.textContent).toContain('운영진이 지움 (영자) · 사유: 광고');
  expect(del.textContent).toContain('작성자가 지움');
  expect(del.textContent).toContain('지운 댓글 내용');
  expect(screen.getByText(/365일 보관/)).toBeDefined();
});

test('운영자: 탈퇴했거나 없는 회원은 "탈퇴한 이용자"', async () => {
  asOp();
  start('/admin/members/u-gone');
  expect(await screen.findByRole('heading', { name: '탈퇴한 이용자' })).toBeDefined();
  expect(screen.getByText(/탈퇴했거나 없는 회원이라 정보를 볼 수 없습니다/)).toBeDefined();
  expect(screen.getByRole('link', { name: '← 회원 관리' }).getAttribute('href')).toBe('/admin/members');
});

test('감독관: 회원 관리·회원 정보 화면이 없고 회원 함수를 부르지도 않는다', async () => {
  fakeLogin('u-mod', { nickname: '감독', role: 'moderator', level: 3, main_title: null });
  start('/admin/members');
  expect(await screen.findByText('운영자만 볼 수 있습니다.')).toBeDefined();
  cleanup();
  start('/admin/members/u-1');
  expect(await screen.findByText('운영자만 볼 수 있습니다.')).toBeDefined();
  expect(fakeState.memberCalls.length).toBe(0);
  expect(screen.queryByText('지운 글 본문')).toBeNull();
});

test('감독관: /admin에 회원 관리 칸이 없다', async () => {
  fakeLogin('u-mod', { nickname: '감독', role: 'moderator', level: 3, main_title: null });
  start('/admin');
  await screen.findByRole('heading', { name: /자유게시판·댓글/ });
  expect(screen.queryByRole('link', { name: '회원 관리 열기' })).toBeNull();
  expect(fakeState.memberCalls.length).toBe(0);
});

test('운영자 모드를 끈 운영자: 일반 회원처럼 회원 관리를 못 보고 회원 함수도 안 부른다', async () => {
  fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0, main_title: null, operator_mode: false });
  start('/admin/members');
  expect(await screen.findByText('운영자만 볼 수 있습니다.')).toBeDefined();
  expect(fakeState.memberCalls.length).toBe(0);
});
