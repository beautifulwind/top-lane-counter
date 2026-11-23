// 6-81: 첫 화면 "지금까지 N개의 빌드" 배지 → 전체 빌드 목록 /builds
// 누구나 봄, 정렬(장인 → 추천 → 최신), 줄 내용, 상대법으로 이동, 20개씩 쪽 번호(?page=에 기억), 차단 숨김 안내, 숨긴 상대법 제외, 배지 = 목록 개수
// 6-87: 안내 문장 없음(목록 이름만), 줄 = 왼쪽 강조선 카드(장인 주황 is-influencer·일반 회색), 이전 · 1 2 3 … · 다음
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { MemoryRouter, useLocation, useNavigate } from 'react-router-dom';
import { AppRoutes } from '../App';
import { resetCountUp } from '../components/BuildCountBadge';
import { getPublicBuildCount, invalidateBuildCount } from '../api/buildCount';
import { compareAllBuilds } from '../lib/wikiBuild';
import { pageItems } from '../components/Pagination';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeBuild, fakeLogin, fakeState } from './fakeSupabase';

beforeEach(() => {
  invalidateBuildCount();
  resetCountUp();
  window.matchMedia = undefined;
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

let nav;
function Where() {
  const l = useLocation();
  nav = useNavigate();
  return <output data-testid="where">{l.pathname + l.search}</output>;
}
const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /><Where /></MemoryRouter>);
const where = () => screen.getByTestId('where').textContent;
const rows = () => [...document.querySelectorAll('.all-builds > li')];
const matchupOf = (li) => li.querySelector('.inf-build-matchup').textContent;

const GAREN_DARIUS = { id: 11, target_champion: 'Darius', counter_champion: 'Garen', status: 'approved' };
const TEEMO_VAYNE = { id: 12, target_champion: 'Vayne', counter_champion: 'Teemo', status: 'approved' };
const HIDDEN = { id: 13, target_champion: 'Kennen', counter_champion: 'Garen', status: 'hidden' };
const inf = (nickname) => ({ nickname, level: 5, main_title: null, influencer: 'streamer' });
const user = (nickname) => ({ nickname, level: 1, main_title: null, influencer: null });
const day = (d) => `2026-11-${String(d).padStart(2, '0')}T00:00:00Z`;

/** 장인 2 + 일반 4 + 숨긴 상대법 1 + 승인 대기 1 */
function seed() {
  TABLES.builds = [
    fakeBuild(201, user('일반A'), { up_count: 9, created_at: day(1), counter: GAREN_DARIUS, counter_id: 11, max_skill: 'E', name: '착취' }),
    fakeBuild(202, inf('장인B'), { up_count: 1, created_at: day(2), counter: TEEMO_VAYNE, counter_id: 12, max_skill: 'Q', name: '독버섯' }),
    fakeBuild(203, inf('장인C'), { up_count: 1, created_at: day(5), counter: GAREN_DARIUS, counter_id: 11, max_skill: 'W', name: null, seq: 2 }),
    fakeBuild(204, user('일반D'), { up_count: 3, created_at: day(3), counter: TEEMO_VAYNE, counter_id: 12 }),
    fakeBuild(205, user('일반E'), { up_count: 3, created_at: day(4), counter: TEEMO_VAYNE, counter_id: 12 }),
    fakeBuild(206, null, { up_count: 0, created_at: day(6), counter: GAREN_DARIUS, counter_id: 11 }), // 탈퇴한 작성자
    fakeBuild(207, inf('장인숨김'), { up_count: 50, counter: HIDDEN, counter_id: 13 }),
    fakeBuild(208, user('대기'), { status: 'pending', up_count: 99, counter: GAREN_DARIUS, counter_id: 11 }),
  ];
}
/** 같은 조건의 일반 빌드 n개 */
function many(n) {
  TABLES.builds = Array.from({ length: n }, (_, i) => fakeBuild(300 + i, user(`유저${i}`), {
    up_count: n - i, created_at: day(1), counter: GAREN_DARIUS, counter_id: 11,
  }));
}

test('정렬: 장인 빌드 먼저 → 추천 많은 순 → 같으면 최신순 (일반 빌드도 같은 기준)', () => {
  const b = (id, influencer, up, d) => ({ id, author: influencer ? { influencer: 'streamer' } : null, up, created_at: day(d) });
  const list = [b(1, false, 9, 1), b(2, true, 1, 2), b(3, true, 1, 5), b(4, false, 3, 3), b(5, false, 3, 4), b(6, true, 0, 9)];
  expect(list.sort(compareAllBuilds).map((x) => x.id)).toEqual([3, 2, 6, 1, 5, 4]);
});

test('비로그인도 본다: 공개 빌드만(숨긴 상대법·승인 대기 제외), 장인 → 추천 → 최신 순서, 줄 내용', async () => {
  seed();
  start('/builds');
  expect(await screen.findByRole('heading', { level: 1, name: /전체 빌드/ })).toBeDefined();
  expect(screen.queryByText(/장인 빌드가 먼저|누르면 그 상대법으로 갑니다/)).toBeNull(); // 6-87: 제목 아래 안내 문장 삭제
  expect(screen.getByRole('list', { name: '공개된 빌드 6개' })).toBeDefined(); // 스크린리더용 이름은 남김
  expect(rows().map((li) => li.querySelector('a').getAttribute('href'))).toEqual([
    '/champion/Darius/counter/Garen?build=203', // 장인, 추천 1, 11-05
    '/champion/Vayne/counter/Teemo?build=202', // 장인, 추천 1, 11-02
    '/champion/Darius/counter/Garen?build=201', // 일반, 추천 9
    '/champion/Vayne/counter/Teemo?build=205', // 일반, 추천 3, 11-04
    '/champion/Vayne/counter/Teemo?build=204', // 일반, 추천 3, 11-03
    '/champion/Darius/counter/Garen?build=206', // 탈퇴한 작성자
  ]);
  const [first, , third] = rows();
  expect(matchupOf(first)).toBe('가렌 vs 다리우스'); // 내 챔피언 vs 상대
  expect(within(first).getByText('장인 빌드')).toHaveClass('inf-build-tag'); // 기존 BuildTitle 뱃지
  expect(first.querySelector('.inf-build-name').textContent).toBe('장인 빌드'); // 이름 없는 장인 빌드 = "장인 빌드" (기존 BuildTitle 그대로)
  expect(first.querySelector('.skill-key').textContent).toBe('W');
  expect(first.querySelector('.vote-count').textContent).toBe('추천 1');
  expect(within(third).queryByText('장인 빌드')).toBeNull();
  expect(third.textContent).toContain('착취');
  expect(third.querySelector('.skill-key').textContent).toBe('E');
  expect(third.querySelector('.vote-count').textContent).toBe('추천 9');
  // 강조선 = 장인 빌드 뱃지와 같은 판정 (뱃지가 있는 줄만 주황)
  expect(rows().map((li) => li.classList.contains('is-influencer'))).toEqual([true, true, false, false, false, false]);
  expect(rows().every((li) => li.classList.contains('build-card'))).toBe(true);
  expect(rows().map((li) => !!li.querySelector('.inf-build-tag'))).toEqual(rows().map((li) => li.classList.contains('is-influencer')));
  expect(screen.queryByRole('navigation', { name: '쪽 이동' })).toBeNull(); // 20개 이하면 쪽 번호 없음
});

test('닉네임을 정하기 전인 회원도 본다', async () => {
  seed();
  fakeLogin('u-new', { nickname: null });
  start('/builds');
  await waitFor(() => expect(rows()).toHaveLength(6));
  expect(where()).toBe('/builds');
});

test('줄을 누르면 그 상대법 화면(그 빌드를 고른 채로)', async () => {
  seed();
  start('/builds');
  await waitFor(() => expect(rows()).toHaveLength(6));
  fireEvent.click(rows()[2].querySelector('a'));
  expect(where()).toBe('/champion/Darius/counter/Garen?build=201');
});

const pager = () => screen.getByRole('navigation', { name: '쪽 이동' });
const pagerLabels = () => within(pager()).getAllByRole('listitem').map((li) => li.textContent);

test('20개씩 쪽 번호 — 쪽은 주소(?page=)에 남아 상대법에 갔다 와도 그대로, 쪽을 바꾸면 목록 맨 위로', async () => {
  many(45);
  const scroll = vi.fn();
  Element.prototype.scrollIntoView = scroll;
  start('/builds');
  await waitFor(() => expect(rows()).toHaveLength(20));
  expect(pagerLabels()).toEqual(['이전', '1', '2', '3', '다음']);
  expect(within(pager()).getByRole('button', { name: '1쪽' })).toHaveAttribute('aria-current', 'page');
  expect(within(pager()).getByRole('button', { name: '이전 쪽' })).toBeDisabled();
  fireEvent.click(within(pager()).getByRole('button', { name: '2쪽' }));
  await waitFor(() => expect(where()).toBe('/builds?page=2'));
  expect(rows()).toHaveLength(20);
  expect(rows()[0].querySelector('a').getAttribute('href')).toMatch(/build=320$/); // 21번째 (추천 많은 순)
  expect(within(pager()).getByRole('button', { name: '2쪽' })).toHaveAttribute('aria-current', 'page');
  expect(scroll).toHaveBeenCalled(); // 목록 맨 위로
  expect(document.activeElement).toBe(rows()[0].querySelector('a')); // 새 쪽의 첫 줄로 초점
  fireEvent.click(rows()[5].querySelector('a'));
  expect(where()).toMatch(/^\/champion\/Darius\/counter\/Garen\?build=/);
  nav(-1);
  await waitFor(() => expect(where()).toBe('/builds?page=2'));
  await waitFor(() => expect(rows()[0].querySelector('a').getAttribute('href')).toMatch(/build=320$/)); // 뒤로 와도 같은 쪽
  fireEvent.click(within(pager()).getByRole('button', { name: '다음 쪽' }));
  await waitFor(() => expect(where()).toBe('/builds?page=3'));
  expect(rows()).toHaveLength(5); // 마지막 쪽 45 - 40
  expect(within(pager()).getByRole('button', { name: '다음 쪽' })).toBeDisabled();
  fireEvent.click(within(pager()).getByRole('button', { name: '1쪽' }));
  await waitFor(() => expect(where()).toBe('/builds')); // 1쪽이면 주소에 없음
  delete Element.prototype.scrollIntoView;
});

test('?page=이 이상하면 1쪽, 너무 크면 마지막 쪽 (예전 ?n= 주소도 죽지 않음)', async () => {
  many(45);
  const first = start('/builds?page=abc');
  await waitFor(() => expect(rows()).toHaveLength(20));
  expect(within(pager()).getByRole('button', { name: '1쪽' })).toHaveAttribute('aria-current', 'page');
  first.unmount();
  const second = start('/builds?page=99');
  await waitFor(() => expect(rows()).toHaveLength(5));
  expect(within(pager()).getByRole('button', { name: '3쪽' })).toHaveAttribute('aria-current', 'page');
  second.unmount();
  start('/builds?n=40');
  await waitFor(() => expect(rows()).toHaveLength(20));
});

test('23개(지금 정도)면 20개 + 3개, 쪽 번호 이전 · 1 2 · 다음', async () => {
  many(23);
  start('/builds');
  await waitFor(() => expect(rows()).toHaveLength(20));
  expect(pagerLabels()).toEqual(['이전', '1', '2', '다음']);
  fireEvent.click(within(pager()).getByRole('button', { name: '2쪽' }));
  await waitFor(() => expect(rows()).toHaveLength(3));
});

test('쪽이 많으면 일부만: 1 … 4 5 6 … 12 (폰에서는 1 … 5 … 12), 사이가 한 쪽뿐이면 그 번호', () => {
  const text = (page, pages, compact) => pageItems(page, pages, compact).map((i) => (i.kind === 'gap' ? '…' : i.n)).join(' ');
  expect(text(1, 1)).toBe('');
  expect(text(1, 3)).toBe('1 2 3');
  expect(text(5, 7)).toBe('1 2 3 4 5 6 7');
  expect(text(5, 12)).toBe('1 … 4 5 6 … 12');
  expect(text(1, 12)).toBe('1 2 … 12');
  expect(text(2, 12)).toBe('1 2 3 … 12');
  expect(text(3, 12)).toBe('1 2 3 4 … 12');
  expect(text(4, 12)).toBe('1 2 3 4 5 … 12'); // 사이가 한 쪽(2)뿐이면 점 대신 번호
  expect(text(11, 12)).toBe('1 … 10 11 12');
  expect(text(12, 12)).toBe('1 … 11 12');
  expect(text(5, 12, true)).toBe('1 … 5 … 12');
  expect(text(1, 12, true)).toBe('1 … 12');
  expect(text(2, 12, true)).toBe('1 2 … 12');
  expect(text(12, 12, true)).toBe('1 … 12');
  expect(text(3, 4, true)).toBe('1 2 3 4'); // 4쪽 이하는 폰에서도 전부
  expect(text(3, 5, true)).toBe('1 … 3 … 5');
});

test('내가 차단한 사람의 빌드는 숨기고 몇 개 숨겼는지 알려 준다 (개수 문장은 전체 기준)', async () => {
  seed();
  fakeLogin('u-me', { nickname: '나' });
  const blockedId = TABLES.builds.find((b) => b.id === 201).author_id;
  TABLES.user_blocks.push({ blocker_id: 'u-me', blocked_id: blockedId, blocked: { nickname: '일반A' } });
  start('/builds');
  expect(await screen.findByText('차단한 사용자의 빌드 1개는 숨겼습니다.')).toHaveAttribute('role', 'note');
  await waitFor(() => expect(rows()).toHaveLength(5));
  expect(rows().some((li) => li.querySelector('a').getAttribute('href').endsWith('build=201'))).toBe(false);
  expect(screen.getByRole('list', { name: '공개된 빌드 6개' })).toBeDefined();
});

test('빌드가 없으면 안내, 불러오기 실패면 오류와 다시 시도', async () => {
  TABLES.builds = [];
  const first = start('/builds');
  expect(await screen.findByText('아직 공개된 빌드가 없습니다.')).toBeDefined();
  first.unmount();
  fakeState.error = 'boom';
  start('/builds');
  expect(await screen.findByRole('button', { name: /다시/ })).toBeDefined();
});

test('배지 숫자 = 목록 개수 (같은 조건: 숨긴 상대법 밑 빌드는 배지도 세지 않음, 목록을 받으면 배지도 그 숫자)', async () => {
  seed();
  expect(await getPublicBuildCount()).toBe(6);
  invalidateBuildCount();
  start('/builds');
  await waitFor(() => expect(rows()).toHaveLength(6));
  const before = fakeState.queryLog.length;
  expect(await getPublicBuildCount()).toBe(6); // 목록이 맞춰 둔 값 — 다시 묻지 않음
  expect(fakeState.queryLog.length).toBe(before);
});

test('첫 화면 배지는 /builds로 가는 링크 (스크린리더: 숫자 문장 + "전체 빌드 목록 보기", 눈에 보이는 부분은 aria-hidden)', async () => {
  seed();
  start('/');
  const link = await screen.findByRole('link', { name: '지금까지 6개의 빌드가 등록되었습니다. 전체 빌드 목록 보기' });
  expect(link).toHaveAttribute('href', '/builds');
  expect(link.querySelector('.build-count-visual')).toHaveAttribute('aria-hidden', 'true');
  expect(link.querySelector('.build-count-go')).not.toBeNull(); // 오른쪽 작은 ›
  fireEvent.click(link);
  expect(where()).toBe('/builds');
  await waitFor(() => expect(rows()).toHaveLength(6));
  expect(screen.getByRole('button', { name: '뒤로 가기' })).toBeDefined(); // 상단 ← (6-78 규칙: 그 밖의 모든 화면)
});
