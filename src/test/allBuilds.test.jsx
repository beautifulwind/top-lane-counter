// 6-81: 첫 화면 "지금까지 N개의 빌드" 배지 → 전체 빌드 목록 /builds
// 누구나 봄, 정렬(장인 → 추천 → 최신), 줄 내용, 상대법으로 이동, 20개씩 [더보기](주소에 기억), 차단 숨김 안내, 숨긴 상대법 제외, 배지 = 목록 개수
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { MemoryRouter, useLocation, useNavigate } from 'react-router-dom';
import { AppRoutes } from '../App';
import { resetCountUp } from '../components/BuildCountBadge';
import { getPublicBuildCount, invalidateBuildCount } from '../api/buildCount';
import { compareAllBuilds } from '../lib/wikiBuild';
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
  expect(screen.getByText(/공개된 빌드 6개/)).toBeDefined();
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

test('20개씩 [더보기] — 펼친 개수는 주소에 남아 상대법에 갔다 와도 그대로, 다 보이면 버튼이 없다', async () => {
  many(45);
  start('/builds');
  await waitFor(() => expect(rows()).toHaveLength(20));
  fireEvent.click(screen.getByRole('button', { name: '더보기 (20/45)' }));
  await waitFor(() => expect(rows()).toHaveLength(40));
  expect(where()).toBe('/builds?n=40');
  expect(document.activeElement).toBe(rows()[20].querySelector('a')); // 새로 보인 첫 줄로 초점
  fireEvent.click(rows()[25].querySelector('a'));
  expect(where()).toMatch(/^\/champion\/Darius\/counter\/Garen\?build=/);
  nav(-1);
  await waitFor(() => expect(rows()).toHaveLength(40));
  fireEvent.click(screen.getByRole('button', { name: '더보기 (40/45)' }));
  await waitFor(() => expect(rows()).toHaveLength(45));
  expect(screen.queryByRole('button', { name: /더보기/ })).toBeNull();
});

test('23개(지금 정도)면 20개 + [더보기 (20/23)] 한 번', async () => {
  many(23);
  start('/builds');
  await waitFor(() => expect(rows()).toHaveLength(20));
  fireEvent.click(screen.getByRole('button', { name: '더보기 (20/23)' }));
  await waitFor(() => expect(rows()).toHaveLength(23));
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
  expect(screen.getByText(/공개된 빌드 6개/)).toBeDefined();
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
