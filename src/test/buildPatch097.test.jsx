// 6-97 (1.3 패치 1-B3): 커뮤니티 고정 공지 중복 제거 · /builds 정렬 칩(추천순·최신순) · 장인 빌드 카드의 닉네임·사진 · 공용 작성자 닉네임 칸(별점 자리)
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { AppRoutes } from '../App';
import { resetCountUp } from '../components/BuildCountBadge';
import { invalidateBuildCount } from '../api/buildCount';
import BuildAuthorName from '../components/BuildAuthorName';
import { compareRecentBuilds } from '../lib/wikiBuild';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeBuild, fakePost } from './fakeSupabase';

beforeEach(() => {
  invalidateBuildCount();
  resetCountUp();
  window.matchMedia = undefined;
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

let where = '';
function Where() {
  const l = useLocation();
  where = l.pathname + l.search;
  return null;
}
const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /><Where /></MemoryRouter>);

// ---------------- 1. 공지 중복 ----------------
test('커뮤니티: 위에 고정한 공지는 아래 목록에서 빠진다 (고정에 못 든 옛 공지·일반 글은 그대로)', async () => {
  TABLES.posts.push(
    fakePost(1, { title: '공지 하나', is_notice: true }),
    fakePost(2, { title: '일반 글' }),
    fakePost(3, { title: '공지 둘', is_notice: true }),
    fakePost(4, { title: '공지 셋', is_notice: true }),
    fakePost(6, { title: '공지 넷', is_notice: true }),
  );
  start('/board');
  const pinned = await screen.findByRole('list', { name: '공지' });
  const pinnedTitles = within(pinned).getAllByRole('listitem').map((li) => li.querySelector('.post-title').textContent);
  expect(pinnedTitles).toHaveLength(3);
  const list = screen.getByRole('list', { name: '글 목록' });
  const listTitles = within(list).getAllByRole('listitem').map((li) => li.querySelector('.post-title').textContent);
  pinnedTitles.forEach((t) => expect(listTitles).not.toContain(t)); // 중복 없음
  expect(listTitles).toContain('일반 글');
  expect(listTitles.length + pinnedTitles.length).toBe(TABLES.posts.filter((p) => p.status !== 'hidden').length); // 글이 사라지지도 않음 (고정에 못 든 공지 1개는 목록에 [공지]로)
  expect(within(list).getAllByText('공지')).toHaveLength(1);
});

test('커뮤니티: 공지만 있어도 「아직 글이 없습니다」가 나오지 않는다', async () => {
  TABLES.posts.push(fakePost(1, { title: '공지 하나', is_notice: true }));
  start('/board');
  expect(await screen.findByRole('list', { name: '공지' })).toBeDefined();
  expect(screen.queryByText(/아직 글이 없습니다/)).toBeNull();
  expect(screen.queryByRole('list', { name: '글 목록' })).toBeNull();
});

test('커뮤니티 검색 중에는 고정 공지가 없으므로 공지도 목록에 그대로', async () => {
  TABLES.posts.push(fakePost(1, { title: '점검 공지', is_notice: true }));
  start('/board?q=점검');
  const list = await screen.findByRole('list', { name: '글 목록' });
  expect(within(list).getByText('점검 공지')).toBeDefined();
  expect(screen.queryByRole('list', { name: '공지' })).toBeNull();
});

// ---------------- 3. 공용 작성자 닉네임 ----------------
test('작성자 닉네임 공용 칸: 없으면 탈퇴한 이용자, 별점(난이도, 6-104)이 비어 있으면 아무것도 그리지 않는다', () => {
  const { container, rerender } = render(<BuildAuthorName author={null} />);
  expect(container.textContent).toBe('탈퇴한 이용자');
  rerender(<BuildAuthorName author={{ nickname: '일반인', influencer: null }} />);
  expect(container.textContent).toBe('일반인');
  expect(container.querySelector('.author-rating')).toBeNull();
  expect(container.querySelector('.author-avatar')).toBeNull(); // 사진 칸 없음
  rerender(<BuildAuthorName author={{ nickname: '일반인', influencer: null }} rating={4.5} />);
  expect(container.querySelector('.author-rating').textContent).toContain('★ 4.5'); // 값을 넘기면 자리에 그려진다 (6-104: 숫자만 받는다)
});

test('작성자 닉네임 공용 칸: photo는 장인에게만 — 사진이 없으면 첫 글자 원', () => {
  const { container, rerender } = render(<BuildAuthorName photo author={{ nickname: '일반인', influencer: null }} />);
  expect(container.querySelector('.author-avatar')).toBeNull();
  rerender(<BuildAuthorName photo author={{ nickname: '장인가', influencer: 'streamer', photo_path: null }} />);
  expect(container.querySelector('.author-initial').textContent).toBe('장');
  expect(container.querySelector('.inf-tag')).not.toBeNull(); // 장인 표시도 그대로
});

test('상대법 화면·운영자 화면이 쓰는 BuildAuthor도 같은 공용 칸', async () => {
  TABLES.builds = [fakeBuild(101, { nickname: '탑고수', level: 7, main_title: null, influencer: null }, { up_count: 1 })];
  start('/champion/Darius/counter/Quinn');
  expect(await screen.findByText('탑고수')).toBeDefined();
  expect(document.querySelector('.build-head .build-author-name')).not.toBeNull();
});

// ---------------- 4·5. /builds ----------------
const GD = { id: 11, target_champion: 'Darius', counter_champion: 'Garen', status: 'approved' };
const HIDDEN = { id: 13, target_champion: 'Kennen', counter_champion: 'Garen', status: 'hidden' };
const day = (d) => `2026-11-${String(d).padStart(2, '0')}T00:00:00Z`;
const inf = (nickname, photo_path = null) => ({ nickname, level: 5, main_title: null, influencer: 'streamer', photo_path });
const user = (nickname) => ({ nickname, level: 1, main_title: null, influencer: null });
const rows = () => [...document.querySelectorAll('.all-builds > li')];
const ids = () => rows().map((li) => Number(li.querySelector('a').getAttribute('href').split('build=')[1]));

function seed() {
  TABLES.builds = [
    fakeBuild(201, user('일반A'), { up_count: 9, created_at: day(1), counter: GD, counter_id: 11 }),
    fakeBuild(202, inf('장인B', 'u-202/p.jpg'), { up_count: 1, created_at: day(2), counter: GD, counter_id: 11 }),
    fakeBuild(203, inf('장인C'), { up_count: 2, created_at: day(3), counter: GD, counter_id: 11 }),
    fakeBuild(204, user('일반D'), { up_count: 3, created_at: day(4), counter: GD, counter_id: 11 }),
    fakeBuild(207, inf('숨김장인', 'u-207/p.jpg'), { up_count: 50, created_at: day(9), counter: HIDDEN, counter_id: 13 }),
    fakeBuild(208, inf('대기장인'), { status: 'pending', up_count: 99, created_at: day(9), counter: GD, counter_id: 11 }),
  ];
}
const many = (n) => {
  TABLES.builds = Array.from({ length: n }, (_, i) => fakeBuild(300 + i, user(`유저${i}`), { up_count: n - i, created_at: day(1 + (i % 20)), counter: GD, counter_id: 11 }));
};
const chip = (name) => screen.getByRole('button', { name });

test('최신순 비교: 만든 때 최신 먼저, 같으면 id 큰 것 (장인 빌드를 앞세우지 않음)', () => {
  const b = (id, d, influencer) => ({ id, created_at: day(d), author: influencer ? { influencer: 'x' } : null });
  expect([b(1, 5, false), b(2, 2, true), b(3, 5, true)].sort(compareRecentBuilds).map((x) => x.id)).toEqual([3, 1, 2]);
});

test('/builds 정렬 칩: 기본 = 추천순(칩 눌림, 주소에 없음) → 최신순을 누르면 ?sort=recent, 다시 추천순을 누르면 주소에서 사라짐', async () => {
  seed();
  start('/builds');
  await waitFor(() => expect(rows()).toHaveLength(4));
  expect(chip('추천순')).toHaveAttribute('aria-pressed', 'true');
  expect(chip('최신순')).toHaveAttribute('aria-pressed', 'false');
  expect(ids()).toEqual([203, 202, 201, 204]); // 장인 → 추천 → 최신 (기존 기본 그대로)
  fireEvent.click(chip('최신순'));
  await waitFor(() => expect(where).toBe('/builds?sort=recent'));
  expect(ids()).toEqual([204, 203, 202, 201]);
  expect(chip('최신순')).toHaveAttribute('aria-pressed', 'true');
  fireEvent.click(chip('추천순'));
  await waitFor(() => expect(where).toBe('/builds'));
  expect(ids()).toEqual([203, 202, 201, 204]);
});

test('/builds 정렬 칩: 잘못된 ?sort= 값은 추천순, 칩을 바꾸면 1쪽으로(page 삭제)', async () => {
  many(45);
  const first = start('/builds?sort=weird');
  await waitFor(() => expect(rows()).toHaveLength(20));
  expect(chip('추천순')).toHaveAttribute('aria-pressed', 'true');
  first.unmount();
  start('/builds?page=3');
  await waitFor(() => expect(rows()).toHaveLength(5));
  fireEvent.click(chip('최신순'));
  await waitFor(() => expect(where).toBe('/builds?sort=recent'));
  expect(rows()).toHaveLength(20);
  // 쪽 번호는 최신순 상태를 유지한 채 넘어간다
  fireEvent.click(within(screen.getByRole('navigation', { name: '쪽 이동' })).getByRole('button', { name: '2쪽' }));
  await waitFor(() => expect(where).toBe('/builds?sort=recent&page=2'));
});

test('/builds 장인 빌드 카드: 장인 닉네임 + 프로필 사진(없으면 첫 글자 원), 일반 빌드·숨김·대기 빌드는 그대로', async () => {
  seed();
  start('/builds');
  await waitFor(() => expect(rows()).toHaveLength(4));
  const [c203, c202, c201] = rows();
  expect(within(c203).getByText('장인C')).toBeDefined();
  expect(c203.querySelector('.author-initial').textContent).toBe('장'); // 사진 없음 → 기본 원
  expect(within(c202).getByText('장인B')).toBeDefined();
  await waitFor(() => expect(c202.querySelector('img.author-photo')).not.toBeNull());
  expect(c202.querySelector('img.author-photo').getAttribute('src')).toContain('u-202/p.jpg');
  expect(c201.querySelector('.build-author-name')).toBeNull(); // 일반 빌드는 기존대로 (닉네임 없음)
  // 숨긴 상대법 밑 장인 빌드·승인 대기 장인 빌드는 새로 나오지 않는다
  expect(screen.queryByText('숨김장인')).toBeNull();
  expect(screen.queryByText('대기장인')).toBeNull();
  expect(ids()).not.toContain(207);
  expect(ids()).not.toContain(208);
  // 카드 전체가 한 링크 — 닉네임은 링크가 아니다 (링크 안의 링크 없음)
  expect(c203.querySelectorAll('a')).toHaveLength(1);
});

test('최신순에서도 숨김·대기 빌드는 나오지 않고 개수 문장은 그대로', async () => {
  seed();
  start('/builds?sort=recent');
  await waitFor(() => expect(rows()).toHaveLength(4));
  expect(screen.getByRole('list', { name: '공개된 빌드 4개' })).toBeDefined();
  expect(ids()).not.toContain(207);
});
