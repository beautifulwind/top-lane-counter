// 앱 속도 개선 (2026-11-14, DB·화면 모양 그대로): 상대법 화면 요청 동시에 보내기, 고치기 규칙 한 번만 읽기,
// 안 읽은 알림 수는 개수만 세고(count+head) 앱 열 때·푸시·읽음 처리 때만, 알림 화면의 칭호 도감은 세션에 한 번만 (SPEC 6-46)
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeLogin, fakeState } from './fakeSupabase';
import { getEditRules, resetEditRulesCache } from '../api/board';
import { getUnreadCount, announceNotificationsChanged } from '../api/notifications';
import { resetTitleBookOnce } from '../api/rewards';

const MATCHUP = '/champion/Darius/counter/Quinn';
const ME = 'u-old';
let realFetch;
beforeEach(() => {
  realFetch = fakeFetch();
  vi.spyOn(globalThis, 'fetch').mockImplementation(realFetch);
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
  resetEditRulesCache();
  resetTitleBookOnce();
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /></MemoryRouter>);
const asked = (table) => fakeState.queryLog.filter((q) => q.table === table);
let nextId = 800;
const noti = (kind, extra = {}) => ({
  id: nextId++, user_id: ME, kind, message: '알림', proposal_id: null, build_id: null, post_id: null, counter_id: null,
  created_at: '2026-11-02T00:00:00Z', read_at: null, ...extra,
});

test('상대법 화면: Data Dragon·편집자 수·링크·댓글·규칙이 빌드 읽기를 기다리지 않고 함께 나간다', async () => {
  // Data Dragon item.json을 붙잡아 두어도 (아직 안 끝나도) 나머지 요청이 이미 나가 있어야 한다
  let release;
  const gate = new Promise((r) => { release = r; });
  globalThis.fetch.mockImplementation(async (url, ...rest) => {
    if (String(url).includes('item.json')) await gate;
    return realFetch(url, ...rest);
  });
  start(MATCHUP);
  await waitFor(() => {
    expect(asked('build_links')).toHaveLength(1);
    expect(asked('build_editor_counts')).toHaveLength(1);
    expect(asked('doc_comments')).toHaveLength(1);
    expect(asked('xp_rules')).toHaveLength(1);
  });
  expect(screen.queryByRole('heading', { name: /1\. 빌드/ })).toBeNull(); // 아직 로딩 중 (Data Dragon을 기다린다)
  release();
  expect(await screen.findByRole('heading', { name: /1\. 빌드/ })).toBeDefined();
  expect(await screen.findByRole('heading', { name: /4\. 댓글/ })).toBeDefined();
  // 댓글 칸은 미리 보낸 요청 결과를 쓴다 — 다시 읽지 않는다
  expect(asked('doc_comments')).toHaveLength(1);
  expect(asked('xp_rules')).toHaveLength(1);
});

test('상대법 화면: 읽기가 실패하면 예전처럼 오류 상자 + 다시 시도', async () => {
  fakeState.error = '서버가 바쁩니다';
  start(MATCHUP);
  expect(await screen.findByRole('button', { name: /다시 시도/ })).toBeDefined();
});

test('내 표는 상대법 단위로 좁혀 읽고(builds 관계), 내 표 표시는 그대로', async () => {
  fakeLogin(ME);
  TABLES.build_votes.push({ build_id: 102, user_id: ME, value: 1 }, { build_id: 102, user_id: 'u-other', value: -1 }, { build_id: 101, user_id: ME, value: -1 });
  start(MATCHUP);
  expect(await screen.findByRole('heading', { name: /1\. 빌드/ })).toBeDefined();
  await waitFor(() => expect(asked('build_votes').length).toBeGreaterThan(0));
  const { getBuilds } = await import('../api/builds');
  const builds = await getBuilds(1, ME);
  expect(Object.fromEntries(builds.map((b) => [b.id, b.mine]))).toMatchObject({ 101: -1, 102: 1, 103: null });
});

test('고치기 규칙(xp_rules)은 세션에서 한 번만 읽고 재사용, 실패하면 다음에 다시', async () => {
  const a = await getEditRules();
  const b = await getEditRules();
  expect(b).toBe(a);
  expect(asked('xp_rules')).toHaveLength(1);
  resetEditRulesCache();
  fakeState.error = '일시 오류';
  await expect(getEditRules()).rejects.toThrow();
  fakeState.error = null;
  await expect(getEditRules()).resolves.toBeDefined(); // 실패를 기억하지 않는다
});

test('안 읽은 알림 수: id 목록이 아니라 개수만 (count + head, user_id·read_at is null)', async () => {
  fakeLogin(ME);
  TABLES.notifications.push(noti('level_up'), noti('level_up'), noti('level_up', { read_at: '2026-11-02T01:00:00Z' }));
  expect(await getUnreadCount(ME)).toBe(2);
});

test('빨간 점: 앱을 열 때 한 번 세고, 화면을 옮겨도 다시 세지 않는다. 푸시가 오면 다시 센다', async () => {
  fakeLogin(ME, { nickname: '기존유저' });
  TABLES.notifications.push(noti('level_up'));
  start('/');
  const dot = () => document.querySelectorAll('.menu-dot, .noti-dot, [data-unread]').length;
  await waitFor(() => expect(asked('notifications')).toHaveLength(1));
  fireEvent.click(await screen.findByRole('button', { name: /메뉴/ }));
  fireEvent.click(await screen.findByRole('link', { name: /마이페이지/ }));
  await screen.findByRole('link', { name: /알림 보기/ });
  await waitFor(() => expect(screen.getByRole('link', { name: '알림 보기 (새 알림 1개)' })).toBeDefined());
  expect(asked('notifications')).toHaveLength(1); // 앱 열 때 1번뿐 — 마이페이지 [알림 보기]도 같은 값을 쓴다
  expect(dot).toBeDefined();
  // 푸시 도착 → 새 알림 하나 더 → 다시 센다
  TABLES.notifications.push(noti('level_up'));
  act(() => announceNotificationsChanged());
  await waitFor(() => expect(screen.getByRole('link', { name: '알림 보기 (새 알림 2개)' })).toBeDefined());
  expect(asked('notifications')).toHaveLength(2);
});

test('알림 화면: 열면 읽음 처리 → 점이 꺼진다 (세기는 앱 열 때 1 + 읽음 처리 직후 1)', async () => {
  fakeLogin(ME, { nickname: '기존유저' });
  TABLES.notifications.push(noti('level_up'));
  start('/notifications');
  await waitFor(() => expect(TABLES.notifications.every((n) => n.read_at)).toBe(true));
  await waitFor(() => expect(fakeState.rpcCalls.some((c) => c.name === 'mark_all_notifications_read')).toBe(true));
  // 개수 세기 2번(처음 + 읽음 처리 뒤) + 목록 1번
  await waitFor(() => expect(asked('notifications')).toHaveLength(3));
});

test('알림 화면의 칭호 도감: 같은 세션에서 한 번만 읽고, 칭호를 새로 받은 알림이 있으면 새로 읽는다', async () => {
  fakeLogin(ME, { nickname: '기존유저' });
  const book = () => asked('my_title_book').length;
  TABLES.notifications.push(noti('level_up', { read_at: '2026-11-02T01:00:00Z' }));
  const first = start('/notifications');
  await screen.findByRole('list', { name: '알림 목록' });
  expect(book()).toBe(1);
  first.unmount();
  start('/notifications'); // 다시 열기 — 도감을 다시 읽지 않는다
  await screen.findByRole('list', { name: '알림 목록' });
  expect(book()).toBe(1);
  cleanup();
  // 칭호를 새로 받음(안 읽은 칭호 알림) → 최신 도감
  TABLES.notifications.push(noti('title_earned', { message: "칭호 '장군'을 얻었습니다." }));
  start('/notifications');
  await screen.findByText(/칭호 '장군'을 얻었습니다/);
  await waitFor(() => expect(book()).toBe(2));
});

// ---------------- 앱이 다시 보일 때 세기 (30초 제한) ----------------

const setVisibility = (v) => {
  Object.defineProperty(document, 'visibilityState', { value: v, configurable: true });
  document.dispatchEvent(new Event('visibilitychange'));
};
afterEach(() => { delete document.visibilityState; });

test('앱이 다시 보이면 센다: 30초 안이면 건너뛰고, 지나면 센다 (푸시 없는 기기도 점이 맞음)', async () => {
  vi.useFakeTimers({ toFake: ['Date'] });
  try {
    vi.setSystemTime(new Date('2026-11-14T10:00:00Z'));
    fakeLogin(ME, { nickname: '기존유저' });
    TABLES.notifications.push(noti('level_up'));
    start('/');
    await waitFor(() => expect(asked('notifications')).toHaveLength(1)); // 앱 열 때
    TABLES.notifications.push(noti('level_up')); // 푸시 없이 새 알림이 쌓임
    setVisibility('hidden');
    expect(asked('notifications')).toHaveLength(1); // 가려질 때는 안 센다
    vi.setSystemTime(new Date('2026-11-14T10:00:20Z'));
    setVisibility('visible'); // 20초 만에 돌아옴 → 건너뜀
    await new Promise((r) => setTimeout(r, 30));
    expect(asked('notifications')).toHaveLength(1);
    vi.setSystemTime(new Date('2026-11-14T10:00:31Z'));
    setVisibility('visible'); // 센 지 31초 → 센다
    await waitFor(() => expect(asked('notifications')).toHaveLength(2));
    // 센 값이 점에 반영된다
    fireEvent.click((await screen.findAllByRole('button', { name: /메뉴/ }))[0]);
    expect(await screen.findAllByRole('link', { name: /알림/ })).not.toHaveLength(0);
  } finally { vi.useRealTimers(); }
});

test('푸시 신호와 읽음 처리는 30초 제한 없이 바로 센다', async () => {
  fakeLogin(ME, { nickname: '기존유저' });
  start('/');
  await waitFor(() => expect(asked('notifications')).toHaveLength(1));
  act(() => announceNotificationsChanged()); // 방금 센 직후여도
  await waitFor(() => expect(asked('notifications')).toHaveLength(2));
});

test('로그아웃 상태에서는 다시 보여도 세지 않는다', async () => {
  start('/');
  await screen.findAllByRole('button', { name: /메뉴/ });
  setVisibility('visible');
  await new Promise((r) => setTimeout(r, 30));
  expect(asked('notifications')).toHaveLength(0);
});

// ---------------- 상대법 화면: 로그인 확인을 기다렸다가 한 번만 불러오기 (SPEC 6-48) ----------------

test('로그인한 사용자: 인증이 정해질 때까지 로딩만 보이고, 상대법 요청은 한 번만 나간다', async () => {
  fakeLogin(ME, { nickname: '기존유저' });
  TABLES.build_votes.push({ build_id: 102, user_id: ME, value: 1 });
  start(`${MATCHUP}?build=103`);
  expect(screen.getByRole('status').textContent).toBe('불러오는 중…'); // 비어 보이지 않고 같은 로딩 표시
  expect(asked('counters')).toHaveLength(0); // 인증 확인 전에는 시작하지 않는다
  expect(await screen.findByRole('heading', { name: /4\. 댓글/ })).toBeDefined();
  await new Promise((r) => setTimeout(r, 100));
  for (const t of ['counters', 'builds', 'build_votes', 'build_editor_counts', 'build_links', 'doc_comments']) expect(asked(t)).toHaveLength(1);
  expect(screen.getByRole('tab', { selected: true }).textContent).toMatch(/빌드 3/); // ?build= 지정 그대로
  expect(screen.queryByText('불러오는 중…')).toBeNull();
});

test('비로그인 사용자: 예전처럼 바로 한 번 불러온다', async () => {
  start(MATCHUP);
  expect(await screen.findByRole('heading', { name: /4\. 댓글/ })).toBeDefined();
  await new Promise((r) => setTimeout(r, 100));
  for (const t of ['counters', 'builds', 'build_editor_counts', 'build_links', 'doc_comments']) expect(asked(t)).toHaveLength(1);
  expect(asked('build_votes')).toHaveLength(0);
});
