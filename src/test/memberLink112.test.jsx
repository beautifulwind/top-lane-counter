// 1.3 패치 2-D·3-E (SPEC 6-112): 운영자(운영자 모드 켜짐)에게만 작성자 닉네임이 회원 정보(/admin/members/:id) 링크
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { MemoryRouter, Route, Routes, useLocation } from 'react-router-dom';
import { AppRoutes } from '../App';
import UserName from '../components/UserName';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeComment, fakeLogin, fakePost } from './fakeSupabase';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

let where = '';
function Where() { where = useLocation().pathname; return null; }
const start = (path) => render(
  <MemoryRouter initialEntries={[path]}>
    <AppRoutes />
    <Routes><Route path="*" element={<Where />} /></Routes>
  </MemoryRouter>,
);
const MATCHUP = '/champion/Darius/counter/Quinn';
const asOp = (extra = {}) => fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0, main_title: null, ...extra });
const VIEWERS = {
  비로그인: () => {},
  '일반 회원': () => fakeLogin('u-old'),
  감독관: () => fakeLogin('u-mod', { nickname: '감독', role: 'moderator' }),
  '운영자 모드를 끈 운영자': () => asOp({ operator_mode: false }),
};
const memberLinks = () => [...document.querySelectorAll('main a[href^="/admin/members/"], [role="dialog"] a[href^="/admin/members/"]')];
const hrefs = () => [...document.querySelectorAll('a.member-link')].map((a) => a.getAttribute('href'));

/** 글 1개 + 댓글 3개(보통 · 탈퇴 · 닉네임 없음) */
function addPost() {
  TABLES.posts.push(fakePost(1, { author_id: 'u-writer', author: { nickname: '글쓴이', level: 2, main_title: null }, comment_count: 3 }));
  TABLES.post_comments.push(
    fakeComment(11, 1, { author_id: 'u-commenter', author: { nickname: '댓글러', level: 1, main_title: null } }),
    fakeComment(12, 1, { author_id: null, author: null }),
    fakeComment(13, 1, { author_id: 'u-noname', author: { nickname: null, level: 1, main_title: null } }),
  );
}
const ready = () => screen.findByText('댓글 11');

test('운영자: 게시글 작성자·댓글 작성자만 링크, 탈퇴·닉네임 없음은 링크 없음, 누르면 회원 정보로', async () => {
  addPost();
  asOp();
  start('/board/1');
  await ready();
  await waitFor(() => expect(hrefs()).toEqual(['/admin/members/u-writer', '/admin/members/u-commenter']));
  const link = document.querySelector('a.member-link');
  expect(link.textContent).toBe('글쓴이 (회원 정보 보기)');
  for (const el of screen.getAllByText('탈퇴한 이용자')) expect(el.closest('a')).toBeNull();
  expect(document.querySelector('a a')).toBeNull();
  fireEvent.click(link);
  await waitFor(() => expect(where).toBe('/admin/members/u-writer'));
});

for (const [who, login] of Object.entries(VIEWERS)) {
  test(`${who}: 게시글·댓글·빌드 작성자에 회원 정보 링크가 없다`, async () => {
    addPost();
    login();
    start('/board/1');
    await ready();
    await screen.findByText('글쓴이');
    expect(memberLinks()).toEqual([]);
    cleanup();
    start(MATCHUP);
    await screen.findByRole('article', { name: /빌드: 탑고수/ });
    expect(memberLinks()).toEqual([]);
    expect(screen.queryByText('(회원 정보 보기)', { exact: false })).toBeNull();
  });
}

test('빌드 작성자: 운영자는 회원 정보로 (일반 닉네임·장인 모두)', async () => {
  asOp();
  start(MATCHUP);
  const card = await screen.findByRole('article', { name: /빌드: 탑고수/ });
  expect(within(card).getByRole('link', { name: /탑고수/ }).getAttribute('href')).toBe('/admin/members/u-102');
  cleanup();
  const b = TABLES.builds.find((x) => x.id === 102);
  b.author = { ...b.author, influencer: 'creator' };
  start(MATCHUP);
  const inf = await screen.findByRole('article', { name: /빌드: 탑고수/ });
  const a = within(inf).getByRole('link', { name: /탑고수/ });
  expect(a.getAttribute('href')).toBe('/admin/members/u-102');
  expect(a.querySelector('.inf-tag')).not.toBeNull(); // 장인 표시는 그대로
  expect(document.querySelector('a a')).toBeNull();
});

test('장인 닉네임: 운영자가 아니면 예전처럼 /u/:id', async () => {
  const b = TABLES.builds.find((x) => x.id === 102);
  b.author = { ...b.author, influencer: 'creator' };
  fakeLogin('u-old');
  start(MATCHUP);
  const card = await screen.findByRole('article', { name: /빌드: 탑고수/ });
  expect(within(card).getByRole('link', { name: /탑고수/ }).getAttribute('href')).toBe('/u/u-102');
});

test('운영 화면의 작성자(memberId): 로그인 전에는 링크 없는 글자 그대로', () => {
  const { container } = render(<UserName profile={{ nickname: '장인가', level: 1, influencer: 'creator' }} memberId="u-1" />);
  expect(container.querySelector('a')).toBeNull();
});

test('회원 정보: 장인이면 [공개 프로필 보기]가 있다', async () => {
  TABLES.profiles.push({ id: 'u-inf', nickname: '장인가', role: 'user', level: 3, xp: 0, main_title: null, influencer: 'creator', created_at: '2026-11-01T00:00:00Z' });
  asOp();
  start('/admin/members/u-inf');
  expect((await screen.findByRole('link', { name: '공개 프로필 보기' })).getAttribute('href')).toBe('/u/u-inf');
});

test('제외: 게시판 목록(줄 전체가 글 링크)·알림 문장·전체 빌드 목록에는 회원 링크가 없다', async () => {
  addPost();
  TABLES.notifications.push({ id: 1, user_id: 'u-op', kind: 'post_created', message: '글쓴이 님이 새 글을 올렸습니다', post_id: 1, created_at: new Date().toISOString(), read_at: null });
  asOp();
  start('/board');
  await screen.findByText('글 1');
  expect(screen.getByText('글쓴이')).toBeTruthy();
  expect(memberLinks()).toEqual([]);
  expect(document.querySelector('a a')).toBeNull();
  cleanup();
  start('/notifications');
  await screen.findByText(/글쓴이 님이 새 글/);
  expect(memberLinks()).toEqual([]);
  cleanup();
  start('/builds');
  await screen.findByRole('list', { name: /빌드/ });
  expect(memberLinks()).toEqual([]);
});

test('운영 화면(신고): 작성자는 운영자에게만 링크, 감독관에게는 없다', async () => {
  addPost();
  TABLES.reports.push({ id: 1, reporter_id: 'u-r', post_id: 1, comment_id: null, reason: 'spam', detail: null, status: 'open', created_at: '2026-11-01T00:00:00Z', reporter: null });
  asOp();
  start('/admin/reports');
  await screen.findByText(/작성자:/);
  await waitFor(() => expect(hrefs()).toEqual(['/admin/members/u-writer']));
  cleanup();
  fakeLogin('u-mod', { nickname: '감독', role: 'moderator' });
  start('/admin/reports');
  await screen.findByText(/작성자:/);
  expect(hrefs()).toEqual([]);
});
