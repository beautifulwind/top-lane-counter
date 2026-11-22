// 6-82: 빌드 저장(북마크, 066) + 내 목록 /lists ([저장한 빌드] [팔로우한 장인])
// 저장 버튼(로그인·닉네임 안내는 추천과 같은 방식, 누르면 저장/다시 누르면 해제, 비회원·내 빌드도 저장, 서버 거절 사유),
// 066 전 DB에서도 빌드 화면이 열림, 내 목록(최근 저장순·BuildRow 재사용·20개씩·숨김/차단 안내·팔로우 탭 063 규칙), 메뉴 [내 목록 보기]
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { MemoryRouter, useLocation, useNavigate } from 'react-router-dom';
import { AppRoutes } from '../App';
import { GO_DELAY_MS, SAVE_MSG } from '../lib/voteMessages';
import { BOOKMARKS_NOT_READY } from '../api/bookmarks';
import { NO_SAVED_TEXT } from '../pages/MyLists';
import { GUEST_FOLLOWING_TEXT } from '../pages/Following';
import { closeTopOverlay } from '../lib/backButton';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeBuild, fakeGuestLogin, fakeLogin, fakeState } from './fakeSupabase';
import { openMenu } from './menu';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

let nav;
function Where() { const l = useLocation(); nav = useNavigate(); return <output data-testid="where">{l.pathname + l.search}</output>; }
const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /><Where /></MemoryRouter>);
const where = () => screen.getByTestId('where').textContent;
const MATCHUP = '/champion/Darius/counter/Quinn';
const card = (nickname) => screen.getByRole('article', { name: `빌드: ${nickname}` });
const saveBtn = (nickname) => within(card(nickname)).getByRole('button', { name: '빌드 저장' });
const rpcCalls = (name) => fakeState.rpcCalls.filter((c) => c.name === name);
const info = () => document.querySelector('.vote-notice-info');
const rows = () => [...document.querySelectorAll('.saved-builds > li')];
const save = (userId, buildId, at) => TABLES.build_bookmarks.push({ user_id: userId, build_id: buildId, created_at: at });
const day = (d) => `2026-11-${String(d).padStart(2, '0')}T00:00:00Z`;

// ---------------- 저장 버튼 (상대법 화면 빌드 카드) ----------------

test('로그인 전: 저장 버튼이 보이고 누르면 안내 뒤 로그인 화면으로, 서버 호출 없음', async () => {
  start(MATCHUP);
  await screen.findByText(/퀸으로 다리우스 이기는 법/);
  const btn = saveBtn('탑고수');
  expect(btn).toHaveAttribute('aria-pressed', 'false');
  expect(btn).toHaveTextContent('저장');
  fireEvent.click(btn);
  expect(info()).toHaveTextContent(`${SAVE_MSG.login} 로그인 화면으로 이동합니다.`);
  await waitFor(() => expect(where()).toBe('/login'), { timeout: GO_DELAY_MS + 1500 });
  expect(rpcCalls('save_build')).toEqual([]);
});

test('닉네임 정하기 전: 안내 뒤 닉네임 정하기로', async () => {
  fakeLogin('u-nonick');
  start(MATCHUP);
  await screen.findByText(/퀸으로 다리우스 이기는 법/);
  fireEvent.click(saveBtn('탑고수'));
  expect(info()).toHaveTextContent(`${SAVE_MSG.nickname} 닉네임 정하기로 이동합니다.`);
  await waitFor(() => expect(where()).toBe('/welcome'), { timeout: GO_DELAY_MS + 1500 });
  expect(rpcCalls('save_build')).toEqual([]);
});

test('회원: 누르면 저장(눌림·저장됨·알림 문장), 다시 누르면 해제 — 다른 빌드를 봤다가 돌아와도 그대로, 추천 수는 그대로', async () => {
  fakeLogin('u-me', { nickname: '나' });
  start(MATCHUP);
  await screen.findByText(/퀸으로 다리우스 이기는 법/);
  fireEvent.click(saveBtn('탑고수'));
  await waitFor(() => expect(saveBtn('탑고수')).toHaveAttribute('aria-pressed', 'true'));
  expect(saveBtn('탑고수')).toHaveTextContent('저장됨');
  expect(document.body.textContent).toContain(SAVE_MSG.saved);
  expect(TABLES.build_bookmarks).toEqual([expect.objectContaining({ user_id: 'u-me', build_id: 102 })]);
  expect(within(card('탑고수')).getByRole('button', { name: '추천 5' })).toBeDefined();
  // 다른 빌드 → 돌아오기
  fireEvent.click(document.getElementById('build-tab-103'));
  await screen.findByRole('article', { name: '빌드: 칭호없음' });
  expect(saveBtn('칭호없음')).toHaveAttribute('aria-pressed', 'false');
  fireEvent.click(document.getElementById('build-tab-102'));
  await waitFor(() => expect(saveBtn('탑고수')).toHaveAttribute('aria-pressed', 'true'));
  fireEvent.click(saveBtn('탑고수'));
  await waitFor(() => expect(saveBtn('탑고수')).toHaveAttribute('aria-pressed', 'false'));
  expect(document.body.textContent).toContain(SAVE_MSG.unsaved);
  expect(TABLES.build_bookmarks).toEqual([]);
});

test('다시 열면 저장한 빌드는 처음부터 "저장됨" (내 저장만 — 남의 저장은 상관없음)', async () => {
  fakeLogin('u-me', { nickname: '나' });
  save('u-me', 102, day(3));
  save('u-other', 103, day(3));
  start(MATCHUP);
  await screen.findByText(/퀸으로 다리우스 이기는 법/);
  expect(saveBtn('탑고수')).toHaveAttribute('aria-pressed', 'true');
  fireEvent.click(document.getElementById('build-tab-103'));
  await screen.findByRole('article', { name: '빌드: 칭호없음' });
  expect(saveBtn('칭호없음')).toHaveAttribute('aria-pressed', 'false');
});

test('비회원 계정도 저장 가능 (나만 보는 기능), 내 빌드도 저장 가능', async () => {
  fakeGuestLogin('guest-1', { nickname: '손님' });
  start(MATCHUP);
  await screen.findByText(/퀸으로 다리우스 이기는 법/);
  fireEvent.click(saveBtn('탑고수'));
  await waitFor(() => expect(saveBtn('탑고수')).toHaveAttribute('aria-pressed', 'true'));
  cleanup();
  const mine = TABLES.builds.find((b) => b.id === 103);
  fakeLogin(mine.author_id, { nickname: '칭호없음' });
  start(`${MATCHUP}?build=103`);
  await screen.findByRole('article', { name: '빌드: 칭호없음' });
  fireEvent.click(saveBtn('칭호없음'));
  await waitFor(() => expect(saveBtn('칭호없음')).toHaveAttribute('aria-pressed', 'true'));
});

test('서버가 거절하면(500개 한도) 그 이유를 눈에 띄게, 버튼은 그대로', async () => {
  fakeLogin('u-me', { nickname: '나' });
  for (let i = 0; i < 500; i += 1) save('u-me', 5000 + i, day(1));
  start(MATCHUP);
  await screen.findByText(/퀸으로 다리우스 이기는 법/);
  fireEvent.click(saveBtn('탑고수'));
  const alert = await screen.findByRole('alert');
  expect(alert).toHaveTextContent('저장은 500개까지 할 수 있습니다. 안 보는 빌드를 해제해 주세요.');
  expect(saveBtn('탑고수')).toHaveAttribute('aria-pressed', 'false');
});

test('066 실행 전 DB: 빌드 화면은 그대로 열리고, 저장을 누르면 "준비 중" 안내', async () => {
  fakeState.bookmarksMissing = true;
  fakeLogin('u-me', { nickname: '나' });
  start(MATCHUP);
  await screen.findByText(/퀸으로 다리우스 이기는 법/);
  expect(within(card('탑고수')).getByRole('button', { name: '추천 5' })).toBeDefined();
  fireEvent.click(saveBtn('탑고수'));
  expect(await screen.findByRole('alert')).toHaveTextContent(BOOKMARKS_NOT_READY);
});

// ---------------- 내 목록 /lists ----------------

test('메뉴 [내 목록 보기] → /lists, 로그인 전에는 로그인 안내만', async () => {
  start('/');
  const menu = await openMenu();
  fireEvent.click(menu.getByRole('link', { name: '내 목록 보기' }));
  expect(where()).toBe('/lists');
  const note = await screen.findByText(/로그인하면 저장한 빌드와 팔로우한 장인을 모아 볼 수 있습니다/);
  expect(within(note).getByRole('link', { name: '로그인' })).toHaveAttribute('href', '/login');
  expect(screen.queryByRole('tab')).toBeNull();
  expect(document.title).toBe('내 목록 - 탑신병자');
  expect(screen.getByRole('button', { name: '뒤로 가기' })).toBeDefined(); // 상단 ← (6-78)
});

test('저장한 빌드: 최근 저장순, /builds와 같은 줄(상대법·장인 뱃지·선마·추천 수) → 그 빌드로', async () => {
  fakeLogin('u-me', { nickname: '나' });
  TABLES.builds.push(fakeBuild(301, { nickname: '장인', level: 5, main_title: null, influencer: 'pro' }, { max_skill: 'E', up_count: 7 }));
  save('u-me', 102, day(1));
  save('u-me', 301, day(5));
  save('u-me', 103, day(3));
  save('u-other', 101, day(9));
  start('/lists');
  await waitFor(() => expect(rows()).toHaveLength(3));
  expect(screen.getByRole('tab', { name: '저장한 빌드' })).toHaveAttribute('aria-selected', 'true');
  expect(rows().map((li) => li.querySelector('a').getAttribute('href'))).toEqual([
    '/champion/Darius/counter/Quinn?build=301', '/champion/Darius/counter/Quinn?build=103', '/champion/Darius/counter/Quinn?build=102',
  ]);
  const first = rows()[0];
  expect(first.querySelector('.inf-build-matchup').textContent).toBe('퀸 vs 다리우스');
  expect(within(first).getByText('장인 빌드')).toHaveClass('inf-build-tag');
  expect(first.querySelector('.skill-key').textContent).toBe('E');
  expect(first.querySelector('.vote-count').textContent).toBe('추천 7');
  expect(screen.getByText(/저장한 빌드 3개 \(최대 500개\)/)).toBeDefined();
  fireEvent.click(first.querySelector('a'));
  expect(where()).toBe('/champion/Darius/counter/Quinn?build=301');
});

test('저장한 빌드가 없으면 안내, 닉네임 전이면 저장하려면 닉네임이 필요하다고', async () => {
  fakeLogin('u-nonick');
  start('/lists');
  expect(await screen.findByText(NO_SAVED_TEXT)).toBeDefined();
  expect(screen.getByText('닉네임을 정하면 빌드를 저장할 수 있습니다.')).toBeDefined();
  expect(where()).toBe('/lists'); // 닉네임 정하기로 끌려가지 않음 (/following과 같은 규칙)
});

test('숨겨진 빌드는 빼고 개수 안내, 차단한 사람의 빌드는 숨기고 개수 안내', async () => {
  fakeLogin('u-me', { nickname: '나' });
  save('u-me', 102, day(1));
  save('u-me', 103, day(2));
  save('u-me', 104, day(3)); // 승인 대기(공개 아님)
  const blocked = TABLES.builds.find((b) => b.id === 103).author_id;
  TABLES.user_blocks.push({ blocker_id: 'u-me', blocked_id: blocked, blocked: { nickname: '칭호없음' } });
  start('/lists');
  expect(await screen.findByText(/지금은 볼 수 없는 빌드 1개는 뺐습니다/)).toHaveAttribute('role', 'note');
  expect(await screen.findByText('차단한 사용자의 빌드 1개는 숨겼습니다.')).toHaveAttribute('role', 'note');
  await waitFor(() => expect(rows()).toHaveLength(1));
  expect(rows()[0].querySelector('a').getAttribute('href')).toMatch(/build=102$/);
});

test('20개씩 [더보기] — 펼친 개수는 주소에 남아 빌드를 봤다 와도 그대로', async () => {
  fakeLogin('u-me', { nickname: '나' });
  for (let i = 0; i < 23; i += 1) {
    TABLES.builds.push(fakeBuild(400 + i, null, {}));
    save('u-me', 400 + i, `2026-11-10T00:00:${String(i).padStart(2, '0')}Z`);
  }
  start('/lists');
  await waitFor(() => expect(rows()).toHaveLength(20));
  fireEvent.click(screen.getByRole('button', { name: '더보기 (20/23)' }));
  await waitFor(() => expect(rows()).toHaveLength(23));
  expect(where()).toBe('/lists?n=40');
  expect(document.activeElement).toBe(rows()[20].querySelector('a'));
  fireEvent.click(rows()[21].querySelector('a'));
  nav(-1);
  await waitFor(() => expect(rows()).toHaveLength(23));
});

test('[팔로우한 장인] 탭: 내가 팔로우한 장인 목록(063 — 날짜 없음), 비회원은 안내만, 모아보기 링크', async () => {
  fakeLogin('u-me', { nickname: '나' });
  TABLES.profiles.push({ id: 'u-fk', nickname: 'Faker', role: 'user', level: 3, main_title: null, influencer: 'pro' });
  TABLES.influencer_follows.push({ follower_id: 'u-me', influencer_id: 'u-fk', created_at: '2026-11-10T00:00:00Z' });
  start('/lists');
  fireEvent.click(await screen.findByRole('tab', { name: '팔로우한 장인' }));
  expect(where()).toBe('/lists?tab=following');
  expect(await screen.findByText('Faker')).toBeDefined();
  expect(document.body.textContent).not.toContain('2026-11-10');
  expect(screen.getByRole('link', { name: '팔로우한 장인의 빌드 모아 보기' })).toHaveAttribute('href', '/following');
  cleanup();
  fakeGuestLogin('guest-1', { nickname: '손님' });
  start('/lists?tab=following');
  expect(await screen.findByText(GUEST_FOLLOWING_TEXT)).toBeDefined();
});

test('066 실행 전 DB: 내 목록은 "준비 중" 오류 상자 (화면은 죽지 않음)', async () => {
  fakeState.bookmarksMissing = true;
  fakeLogin('u-me', { nickname: '나' });
  start('/lists');
  expect(await screen.findByText(BOOKMARKS_NOT_READY, { exact: false })).toBeDefined();
});

// ---------------- 상단 바 돋보기: 앱 뒤로가기 ----------------

test('앱 뒤로가기: 열린 [장인 찾기] 검색 칸을 먼저 닫는다 (이전 화면으로 가지 않음)', async () => {
  start('/board');
  fireEvent.click(await screen.findByRole('button', { name: '장인 찾기' }));
  await screen.findByRole('dialog', { name: '장인 찾기' });
  expect(closeTopOverlay(document)).toBe(true);
  await waitFor(() => expect(screen.queryByRole('dialog', { name: '장인 찾기' })).toBeNull());
  expect(where()).toBe('/board');
});
