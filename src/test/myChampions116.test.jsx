// 6-116 (1.3 패치, 080): 내 목록 「내 챔피언」 탭 — /lists?tab=champions와 /following?tab=champions가 같은 화면.
// 검색창 하나 → 줄 단위 결과(아이콘 + 이름 + 선택/선택됨), 메인 검색 규칙(초성·영문) 그대로, 선택·해제, 10개 한도 안내(버튼은 그대로),
// 이름 칩 한 줄(새로 고른 것이 맨 앞, 누르면 그 챔피언만 · 한 번 더 누르면 전체, ×로 해제), 빌드 카드(BuildRow)·20개씩 쪽 번호,
// 빈 상태 안내(등록 없음 / 공개 빌드 없음), 비로그인 로그인 안내, 080 전 DB 「준비 중」, 비회원 가능, 차단한 사람의 빌드 숨김.
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeBuild, fakeGuestLogin, fakeLogin, fakeState } from './fakeSupabase';
import { NO_MY_CHAMPION_BUILDS_TEXT, NO_MY_CHAMPION_TEXT } from '../components/MyChampions';
import { MY_CHAMPION_LIMIT_TEXT, MY_CHAMPIONS_NOT_READY } from '../api/myChampions';

const TODAY = new Date('2026-11-25T03:00:00Z'); // 여는 날 — 날짜 차단 없이 바로 열린다 (6-119)
beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.setSystemTime(TODAY);
  window.matchMedia = undefined;
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); vi.useRealTimers(); });

function Where() {
  const l = useLocation();
  return <output data-testid="where">{l.pathname + l.search}</output>;
}
const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /><Where /></MemoryRouter>);
const where = () => screen.getByTestId('where').textContent;
const panel = () => screen.findByRole('region', { name: '내 챔피언' });
const search = (sec, q) => fireEvent.change(within(sec).getByRole('searchbox', { name: '내 챔피언 검색' }), { target: { value: q } });
const results = (sec) => [...sec.querySelectorAll('.mc-results .mc-result')].map((b) => b.getAttribute('aria-label'));
const chips = (sec) => [...sec.querySelectorAll('.mc-chip .mc-chip-name')].map((b) => b.textContent);
const cards = (sec) => [...sec.querySelectorAll('.my-champ-builds > li')];
const matchupOf = (li) => li.querySelector('.inf-build-matchup').textContent;
const calls = (name) => fakeState.rpcCalls.filter((c) => c.name === name);
const register = (who, ids) => ids.forEach((c, i) => TABLES.user_champions.push({ user_id: who, champion: c, created_at: `2026-11-${String(10 + i).padStart(2, '0')}T00:00:00Z` }));

const GAREN_DARIUS = { id: 11, target_champion: 'Darius', counter_champion: 'Garen', status: 'approved' };
const GAREN_HIDDEN = { id: 13, target_champion: 'Kennen', counter_champion: 'Garen', status: 'hidden' };
const inf = (nickname) => ({ nickname, level: 5, main_title: null, influencer: 'streamer' });
const user = (nickname) => ({ nickname, level: 1, main_title: null, influencer: null });

test('검색창 하나: 입력하면 줄 단위 결과(메인 검색 규칙 — 초성·영문), 누르면 선택 → 칩·빌드 카드, 「선택됨」을 다시 누르면 해제', async () => {
  fakeLogin('u-me', { nickname: '나' });
  start('/lists?tab=champions');
  const sec = await panel();
  expect(within(sec).getByText(NO_MY_CHAMPION_TEXT)).toBeTruthy();
  expect(sec.querySelector('.mc-results')).toBeNull(); // 입력 전에는 챔피언 아이콘을 늘어놓지 않는다
  expect(sec.querySelectorAll('img').length).toBe(0);
  search(sec, 'ㄷㄹ');
  await waitFor(() => expect(results(sec)).toEqual(['다리우스 선택']));
  search(sec, 'garen');
  await waitFor(() => expect(results(sec)).toEqual(['가렌 선택']));
  search(sec, 'ㅋ');
  await waitFor(() => expect(results(sec)).toEqual(['퀸 선택', '케넨 선택'])); // 메인 검색과 같은 점수: 통째로 맞는 퀸이 먼저
  const row = within(sec).getByRole('button', { name: '퀸 선택' });
  expect(row.querySelectorAll('img')).toHaveLength(1); // 작은 챔피언 아이콘 하나
  expect(row.querySelector('.mc-result-state').textContent).toBe('선택');
  fireEvent.click(row);
  await waitFor(() => expect(chips(sec)).toEqual(['퀸']));
  expect(within(sec).getByRole('button', { name: '퀸 선택됨' }).getAttribute('aria-pressed')).toBe('true');
  expect(calls('set_my_champion').at(-1).args).toEqual({ p_champion: 'Quinn', p_selected: true });
  expect(TABLES.user_champions).toEqual([expect.objectContaining({ user_id: 'u-me', champion: 'Quinn' })]);
  // 빌드 카드: 퀸 공개 빌드 4개 (대기 빌드 104 제외), 기존 BuildRow 카드
  await waitFor(() => expect(cards(sec)).toHaveLength(4));
  expect(cards(sec).every((li) => li.classList.contains('build-card'))).toBe(true);
  expect(matchupOf(cards(sec)[0])).toBe('퀸 vs 다리우스');
  expect(cards(sec).map((li) => li.querySelector('a').getAttribute('href'))).not.toContain('/champion/Darius/counter/Quinn?build=104');
  // 해제
  fireEvent.click(within(sec).getByRole('button', { name: '퀸 선택됨' }));
  await waitFor(() => expect(chips(sec)).toEqual([]));
  expect(within(sec).getByText(NO_MY_CHAMPION_TEXT)).toBeTruthy();
  expect(within(sec).getByRole('button', { name: '퀸 선택' })).toBeTruthy();
  expect(TABLES.user_champions).toEqual([]);
});

test('10개를 고른 뒤 또 고르면: 버튼은 그대로이고 누를 때 안내 (서버를 부르지 않음), 서버가 11개째를 거절해도 같은 안내', async () => {
  fakeLogin('u-me', { nickname: '나' });
  register('u-me', ['Ahri', 'Zed', 'Jax', 'Fiora', 'Riven', 'Irelia', 'Darius', 'Quinn', 'Vayne', 'Teemo']);
  start('/lists?tab=champions');
  const sec = await panel();
  await waitFor(() => expect(chips(sec)).toHaveLength(10));
  search(sec, '가렌');
  const btn = await within(sec).findByRole('button', { name: '가렌 선택' });
  expect(btn.disabled).toBe(false);
  const before = calls('set_my_champion').length;
  fireEvent.click(btn);
  expect((await within(sec).findByRole('alert')).textContent).toBe(MY_CHAMPION_LIMIT_TEXT);
  expect(MY_CHAMPION_LIMIT_TEXT).toBe('최대 10개까지 선택할 수 있습니다. 하나를 해제한 뒤 선택해 주세요.');
  expect(calls('set_my_champion')).toHaveLength(before);
  expect(chips(sec)).toHaveLength(10);
  // 이미 고른 것은 10개여도 해제 가능 → 그 뒤 선택 가능, 새로 고른 것이 칩 줄 맨 앞
  fireEvent.click(within(sec).getByRole('button', { name: '티모 해제' }));
  await waitFor(() => expect(chips(sec)).toHaveLength(9));
  fireEvent.click(within(sec).getByRole('button', { name: '가렌 선택' }));
  await waitFor(() => expect(chips(sec)[0]).toBe('가렌'));
  expect(chips(sec)).toHaveLength(10);
  expect(within(sec).queryByRole('alert')).toBeNull();
  cleanup();
  // 화면은 9개로 알고 있는데 그 사이 다른 기기에서 10개가 된 경우: 서버의 TL413 → 같은 안내
  TABLES.user_champions = [];
  register('u-me', ['Ahri', 'Zed', 'Jax', 'Fiora', 'Riven', 'Irelia', 'Darius', 'Quinn', 'Vayne']);
  start('/lists?tab=champions');
  const sec2 = await panel();
  await waitFor(() => expect(chips(sec2)).toHaveLength(9));
  register('u-me', ['Kennen']);
  search(sec2, '가렌');
  fireEvent.click(await within(sec2).findByRole('button', { name: '가렌 선택' }));
  expect((await within(sec2).findByRole('alert')).textContent).toBe(MY_CHAMPION_LIMIT_TEXT);
  expect(chips(sec2)).toHaveLength(9);
});

test('칩: 최근 등록이 맨 앞, 누르면 그 챔피언의 빌드만(?champ=, aria-pressed) · 한 번 더 누르면 전체, ×로 해제하면 필터도 풀림', async () => {
  fakeLogin('u-me', { nickname: '나' });
  TABLES.builds.push(
    fakeBuild(301, inf('장인가'), { up_count: 0, created_at: '2026-11-20T00:00:00Z', counter: GAREN_DARIUS, counter_id: 11, name: '가렌장인' }),
    fakeBuild(302, user('일반가'), { up_count: 9, created_at: '2026-11-21T00:00:00Z', counter: GAREN_DARIUS, counter_id: 11 }),
    fakeBuild(303, user('숨긴상대법'), { up_count: 50, counter: GAREN_HIDDEN, counter_id: 13 }),
  );
  register('u-me', ['Quinn', 'Garen']); // 가렌이 더 최근
  start('/lists?tab=champions');
  const sec = await panel();
  await waitFor(() => expect(chips(sec)).toEqual(['가렌', '퀸']));
  await waitFor(() => expect(cards(sec)).toHaveLength(6)); // 퀸 4 + 가렌 2 (숨긴 상대법 밑 빌드 제외)
  // /builds 추천순: 장인 빌드 먼저 → 추천 많은 순
  expect(matchupOf(cards(sec)[0])).toBe('가렌 vs 다리우스');
  expect(cards(sec)[0].classList.contains('is-influencer')).toBe(true);
  const garen = within(sec).getByRole('button', { name: '가렌' });
  fireEvent.click(garen);
  await waitFor(() => expect(cards(sec)).toHaveLength(2));
  expect(garen.getAttribute('aria-pressed')).toBe('true');
  expect(where()).toBe('/lists?tab=champions&champ=Garen');
  expect(cards(sec).map(matchupOf)).toEqual(['가렌 vs 다리우스', '가렌 vs 다리우스']);
  expect(calls('my_champion_builds').at(-1).args).toEqual({ p_champion: 'Garen', p_page: 1 });
  expect(sec.querySelector('.mc-filter, .sort-chips')).toBeNull(); // 별도 필터 줄 없음
  fireEvent.click(garen);
  await waitFor(() => expect(cards(sec)).toHaveLength(6));
  expect(garen.getAttribute('aria-pressed')).toBe('false');
  expect(where()).toBe('/lists?tab=champions');
  // 퀸만 보다가 퀸을 ×로 해제 → 필터가 풀리고 가렌 빌드만 남음
  fireEvent.click(within(sec).getByRole('button', { name: '퀸' }));
  await waitFor(() => expect(cards(sec)).toHaveLength(4));
  fireEvent.click(within(sec).getByRole('button', { name: '퀸 해제' }));
  await waitFor(() => expect(chips(sec)).toEqual(['가렌']));
  await waitFor(() => expect(cards(sec)).toHaveLength(2));
  expect(where()).toBe('/lists?tab=champions');
  // 칩 줄은 한 줄 가로 밀기 목록
  expect(sec.querySelector('.mc-chips-wrap > ul.mc-chips')).not.toBeNull();
});

test('빈 상태: 등록 없음 안내 / 등록은 했는데 공개 빌드 없음 안내 / 칩으로 좁혔는데 없음', async () => {
  fakeLogin('u-me', { nickname: '나' });
  register('u-me', ['Vayne']);
  start('/lists?tab=champions');
  const sec = await panel();
  expect(await within(sec).findByText(NO_MY_CHAMPION_BUILDS_TEXT)).toBeTruthy();
  fireEvent.click(within(sec).getByRole('button', { name: '베인' }));
  expect(await within(sec).findByText('베인의 공개 빌드가 아직 없습니다.')).toBeTruthy();
  fireEvent.click(within(sec).getByRole('button', { name: '베인 해제' }));
  expect(await within(sec).findByText(NO_MY_CHAMPION_TEXT)).toBeTruthy();
});

test('20개씩 쪽 번호(?page=), 차단한 사람의 빌드는 빼고 개수 안내', async () => {
  fakeLogin('u-me', { nickname: '나' });
  TABLES.builds = Array.from({ length: 25 }, (_, i) => fakeBuild(400 + i, user(`유저${i}`), {
    up_count: 30 - i, created_at: '2026-11-01T00:00:00Z', counter: GAREN_DARIUS, counter_id: 11,
  }));
  TABLES.builds.push(fakeBuild(499, user('나쁜'), { author_id: 'u-bad', up_count: 99, counter: GAREN_DARIUS, counter_id: 11 }));
  TABLES.user_blocks.push({ blocker_id: 'u-me', blocked_id: 'u-bad', created_at: '2026-11-01T00:00:00Z' });
  register('u-me', ['Garen']);
  start('/lists?tab=champions');
  const sec = await panel();
  await waitFor(() => expect(cards(sec)).toHaveLength(20));
  expect(within(sec).getByText('차단한 사용자의 빌드 1개는 숨겼습니다.')).toBeTruthy();
  expect(within(sec).getByText(/내 챔피언 1개의 빌드 25개/)).toBeTruthy();
  const first = cards(sec).map((li) => li.querySelector('a').getAttribute('href'));
  fireEvent.click(await within(sec).findByRole('button', { name: '2쪽' }));
  await waitFor(() => expect(cards(sec)).toHaveLength(5));
  expect(where()).toBe('/lists?tab=champions&page=2');
  const second = cards(sec).map((li) => li.querySelector('a').getAttribute('href'));
  expect(new Set([...first, ...second]).size).toBe(25); // 겹침·빠짐 없음
  expect([...first, ...second].some((h) => h.endsWith('build=499'))).toBe(false);
  expect(calls('my_champion_builds').at(-1).args).toEqual({ p_champion: null, p_page: 2 });
});

test('비로그인: 다른 탭과 같은 로그인 안내 (/lists·/following 모두), 함수를 부르지 않음', async () => {
  start('/lists?tab=champions');
  expect(await screen.findByText(/로그인하면 저장한 빌드와 팔로우한 장인을 모아 볼 수 있습니다/)).toBeTruthy();
  expect(screen.queryByRole('region', { name: '내 챔피언' })).toBeNull();
  cleanup();
  start('/following?tab=champions');
  expect(await screen.findByText(/로그인하면 팔로우한 장인의 빌드를 모아 볼 수 있습니다/)).toBeTruthy();
  expect(screen.queryByRole('region', { name: '내 챔피언' })).toBeNull();
  expect(calls('my_champions')).toHaveLength(0);
});

test('탭 순서: /lists = 저장한 빌드 · 팔로우한 장인 · 내 챔피언, /following도 세 번째 탭으로 같은 화면 · 비회원도 쓸 수 있음', async () => {
  fakeLogin('u-me', { nickname: '나' });
  start('/lists');
  const tabs = await screen.findAllByRole('tab');
  expect(tabs.map((t) => t.textContent)).toEqual(['저장한 빌드', '팔로우한 장인', '내 챔피언']);
  fireEvent.click(tabs[2]);
  expect(await panel()).toBeTruthy();
  expect(where()).toBe('/lists?tab=champions');
  expect(screen.getByRole('tab', { name: '내 챔피언' }).getAttribute('aria-selected')).toBe('true');
  expect(screen.getByRole('tabpanel').getAttribute('aria-labelledby')).toBe('ml-champions');
  cleanup();
  start('/following');
  const ftabs = await screen.findAllByRole('tab');
  expect(ftabs.map((t) => t.textContent)).toEqual(['빌드', '팔로우한 장인', '내 챔피언']);
  fireEvent.click(ftabs[2]);
  expect(await panel()).toBeTruthy();
  expect(where()).toBe('/following?tab=champions');
  cleanup();
  fakeGuestLogin('u-guest', { nickname: null });
  start('/following?tab=champions');
  const sec = await panel();
  search(sec, '퀸');
  fireEvent.click(await within(sec).findByRole('button', { name: '퀸 선택' }));
  await waitFor(() => expect(chips(sec)).toEqual(['퀸']));
  expect(TABLES.user_champions).toEqual([expect.objectContaining({ user_id: 'u-guest', champion: 'Quinn' })]);
});

test('080 전 DB: 탭 안에 「준비 중」 안내만 (오류 화면 없음), 다른 탭은 그대로', async () => {
  fakeLogin('u-me', { nickname: '나' });
  fakeState.myChampionsMissing = true;
  start('/lists?tab=champions');
  expect(await screen.findByText(MY_CHAMPIONS_NOT_READY)).toBeTruthy();
  expect(screen.queryByRole('alert')).toBeNull();
  expect(screen.queryByRole('searchbox', { name: '내 챔피언 검색' })).toBeNull();
  fireEvent.click(screen.getByRole('tab', { name: '저장한 빌드' }));
  expect(await screen.findByRole('region', { name: '저장한 빌드' })).toBeTruthy();
});

test('없는 챔피언·활동 제한 등 서버 거절은 그 문장을 그대로 보여 주고 칩은 그대로', async () => {
  fakeLogin('u-me', { nickname: '나' });
  fakeState.unknownChampions = ['Teemo'];
  start('/lists?tab=champions');
  const sec = await panel();
  search(sec, '티모');
  fireEvent.click(await within(sec).findByRole('button', { name: '티모 선택' }));
  expect((await within(sec).findByRole('alert')).textContent).toBe('없는 챔피언입니다. 다시 골라 주세요.');
  expect(chips(sec)).toEqual([]);
});
