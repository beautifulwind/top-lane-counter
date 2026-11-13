// 장인 팔로우 화면 1 (050, SPEC 6-36): 장인 페이지 /u/:id (빌드 중심·팔로우·팔로워 목록) · 상대법 화면 작성자 옆 [+]
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeBuild, fakeGuestLogin, fakeLogin, fakeState } from './fakeSupabase';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /></MemoryRouter>);
const MATCHUP = '/champion/Darius/counter/Quinn';
const rpcCalls = (name) => fakeState.rpcCalls.filter((c) => c.name === name).map((c) => c.args);

/** 빌드 102(탑고수, 처음 고르는 빌드)를 만든 분 u-102를 장인으로 */
function influencer() {
  const b = TABLES.builds.find((x) => x.id === 102);
  b.author = { ...b.author, influencer: 'creator' };
  TABLES.profiles.push({ id: 'u-102', nickname: '탑고수', role: 'user', level: 7, main_title: null, influencer: 'creator', email: 'secret@x.com' });
}
const fan = () => fakeLogin('u-fan', { nickname: '팬', level: 2 });
const followers = (n) => {
  for (let i = 1; i <= n; i += 1) {
    const id = `u-f${i}`;
    TABLES.profiles.push({ id, nickname: `팔로워${String(i).padStart(2, '0')}`, role: 'user', level: 1, main_title: null });
    TABLES.influencer_follows.push({ follower_id: id, influencer_id: 'u-102', created_at: `2026-11-${String(i).padStart(2, '0')}T00:00:00Z` });
  }
};

// ---------------- 장인 페이지 ----------------

test('장인 페이지: 위쪽에 닉네임·장인 표시·팔로워 수, 본문은 공개 빌드(상대법 이름, 누르면 그 빌드로)', async () => {
  influencer();
  start('/u/u-102');
  const h1 = await screen.findByRole('heading', { level: 1 });
  expect(h1.querySelector('.inf-tag').textContent).toBe('장인');
  expect(screen.getByText('인증된 크리에이터')).toBeTruthy();
  expect(document.querySelector('.follower-count').textContent).toBe('0');
  const builds = screen.getByRole('heading', { name: '처음 만든 빌드' }).closest('section');
  const card = within(builds).getByRole('link', { name: /퀸으로 다리우스\s*빌드 2/ });
  expect(card.getAttribute('href')).toBe('/champion/Darius/counter/Quinn?build=102');
  expect(card.querySelectorAll('img.inf-champ')).toHaveLength(2); // 챔피언 아이콘 2개
  expect(document.body.textContent).not.toContain('secret@x.com');
  fireEvent.click(card);
  expect(await screen.findByText(/퀸으로 다리우스 이기는 법/)).toBeTruthy();
});

test('장인 페이지: 빌드는 최근 수정순, 20개씩 [더보기]', async () => {
  influencer();
  for (let i = 0; i < 24; i += 1) {
    TABLES.builds.push(fakeBuild(200 + i, { nickname: '탑고수', influencer: 'creator' }, {
      author_id: 'u-102', name: `빌드이름${i}`, seq: 10 + i, updated_at: `2026-10-${String(i + 1).padStart(2, '0')}T00:00:00Z`,
    }));
  }
  start('/u/u-102');
  const builds = (await screen.findByRole('heading', { name: '처음 만든 빌드' })).closest('section');
  const names = () => within(builds).getAllByRole('link').map((a) => a.querySelector('.inf-build-name').textContent);
  expect(names()).toHaveLength(20);
  expect(names()[0]).toBe('빌드 2'); // 102는 11월에 수정 → 맨 위
  expect(names()[1]).toBe('빌드이름23');
  fireEvent.click(within(builds).getByRole('button', { name: '더보기 (5개 남음)' }));
  await waitFor(() => expect(names()).toHaveLength(25));
  expect(names()[24]).toBe('빌드이름0');
  expect(within(builds).queryByRole('button', { name: /더보기/ })).toBeNull();
});

test('장인 페이지: [팔로우] → "팔로우중"·팔로워 수 +1, 한 번 더 누르면 취소', async () => {
  influencer();
  fan();
  start('/u/u-102');
  const btn = await screen.findByRole('button', { name: '탑고수 팔로우' });
  expect(btn.textContent).toBe('팔로우');
  fireEvent.click(btn);
  const on = await screen.findByRole('button', { name: '탑고수 팔로우 취소' });
  expect(on.textContent).toBe('팔로우중');
  expect(on.getAttribute('aria-pressed')).toBe('true');
  expect(document.querySelector('.follower-count').textContent).toBe('1');
  expect(rpcCalls('follow_influencer')).toEqual([{ p_user: 'u-102' }]);
  fireEvent.click(on);
  expect((await screen.findByRole('button', { name: '탑고수 팔로우' })).textContent).toBe('팔로우');
  expect(document.querySelector('.follower-count').textContent).toBe('0');
  expect(rpcCalls('unfollow_influencer')).toEqual([{ p_user: 'u-102' }]);
  cleanup();
  // 다시 들어오면 팔로우 상태를 DB에서 읽는다
  TABLES.influencer_follows.push({ follower_id: 'u-fan', influencer_id: 'u-102', created_at: '2026-11-13T00:00:00Z' });
  start('/u/u-102');
  expect((await screen.findByRole('button', { name: '탑고수 팔로우 취소' })).textContent).toBe('팔로우중');
});

test('장인 페이지: 비로그인은 팔로워 수만(목록 버튼 없음), [팔로우]를 누르면 로그인 안내', async () => {
  influencer();
  followers(3);
  start('/u/u-102');
  await screen.findByRole('heading', { level: 1 });
  expect(document.querySelector('.follower-count').textContent).toBe('3');
  expect(screen.queryByRole('button', { name: '팔로워 목록' })).toBeNull();
  fireEvent.click(screen.getByRole('button', { name: '탑고수 팔로우' }));
  const hint = await screen.findByText(/로그인하면 팔로우할 수 있습니다/);
  expect(within(hint).getByRole('link', { name: '로그인' }).getAttribute('href')).toBe('/login');
  expect(rpcCalls('follow_influencer')).toEqual([]);
  expect(fakeState.followStatusCalls).toEqual([]); // 로그인 전에는 상태를 묻지 않는다
});

test('장인 페이지: 로그인하면 [팔로워 목록] — 닉네임·팔로우한 날, 20개씩 [더보기]', async () => {
  influencer();
  followers(22);
  fan();
  start('/u/u-102');
  fireEvent.click(await screen.findByRole('button', { name: '팔로워 목록' }));
  const box = (await screen.findByRole('heading', { name: '팔로워' })).closest('section');
  await waitFor(() => expect(box.querySelectorAll('.follower-list li')).toHaveLength(20));
  const first = box.querySelector('.follower-list li');
  expect(first.textContent).toContain('팔로워22'); // 최근 팔로우가 위
  expect(first.textContent).toContain('2026-11-22 팔로우');
  fireEvent.click(within(box).getByRole('button', { name: '더보기 (2명 남음)' }));
  await waitFor(() => expect(box.querySelectorAll('.follower-list li')).toHaveLength(22));
  fireEvent.click(screen.getByRole('button', { name: '팔로워 목록 닫기' }));
  expect(screen.queryByRole('heading', { name: '팔로워' })).toBeNull();
});

test('장인 페이지: 내 페이지에는 [팔로우]가 없다 / 장인이 아니면 없는 페이지', async () => {
  influencer();
  fakeLogin('u-102', { nickname: '탑고수', influencer: 'creator' });
  start('/u/u-102');
  await screen.findByRole('heading', { level: 1 });
  expect(screen.queryByRole('button', { name: /팔로우/ })).toBeNull();
  cleanup();
  start('/u/u-old');
  expect(await screen.findByText('문서를 찾을 수 없습니다')).toBeTruthy();
});

// ---------------- 상대법 화면 [+] ----------------

test('[+]: 장인이 만든 빌드의 작성자 옆에만, 상태는 follow_status 한 번으로 / 누르면 "팔로우중", 다시 누르면 취소', async () => {
  influencer();
  fan();
  start(MATCHUP);
  const head = (await screen.findByRole('button', { name: '탑고수 팔로우' })).closest('.build-author');
  expect(head.querySelector('a.inf-link').getAttribute('href')).toBe('/u/u-102'); // 닉네임 → 장인 페이지 그대로
  expect(fakeState.followStatusCalls).toEqual([['u-102']]); // 장인 작성자만 모아 한 번
  const plus = screen.getByRole('button', { name: '탑고수 팔로우' });
  expect(plus.textContent).toBe('+');
  fireEvent.click(plus);
  const on = await screen.findByRole('button', { name: '탑고수 팔로우 취소' });
  expect(on.textContent).toBe('팔로우중');
  expect(TABLES.influencer_follows).toEqual([expect.objectContaining({ follower_id: 'u-fan', influencer_id: 'u-102' })]);
  fireEvent.click(on);
  expect((await screen.findByRole('button', { name: '탑고수 팔로우' })).textContent).toBe('+');
  expect(TABLES.influencer_follows).toEqual([]);
  // 장인이 아닌 작성자(103 칭호없음)는 [+] 없음
  fireEvent.click(screen.getByRole('tab', { name: /빌드 3/ }));
  await screen.findByRole('article', { name: '빌드: 칭호없음' });
  expect(screen.queryByRole('button', { name: /팔로우/ })).toBeNull();
  expect(fakeState.followStatusCalls).toHaveLength(1); // 빌드를 바꿔도 다시 묻지 않는다
});

test('[+]: 이미 팔로우 중이면 처음부터 "팔로우중" / 내 빌드에는 없음', async () => {
  influencer();
  fan();
  TABLES.influencer_follows.push({ follower_id: 'u-fan', influencer_id: 'u-102', created_at: '2026-11-13T00:00:00Z' });
  start(MATCHUP);
  expect((await screen.findByRole('button', { name: '탑고수 팔로우 취소' })).textContent).toBe('팔로우중');
  cleanup();
  fakeLogin('u-102', { nickname: '탑고수', influencer: 'creator' });
  start(MATCHUP);
  await screen.findByRole('article', { name: '빌드: 탑고수' });
  expect(screen.queryByRole('button', { name: /팔로우/ })).toBeNull();
});

test('[+]: 비로그인은 로그인 안내, 게스트는 팔로우하고 "게스트는 기록이 사라질 수 있습니다" 한 줄', async () => {
  influencer();
  start(MATCHUP);
  fireEvent.click(await screen.findByRole('button', { name: '탑고수 팔로우' }));
  expect(await screen.findByText(/로그인하면 팔로우할 수 있습니다/)).toBeTruthy();
  expect(fakeState.followStatusCalls).toEqual([]);
  cleanup();
  fakeGuestLogin('u-guest', { nickname: '손님' });
  start(MATCHUP);
  fireEvent.click(await screen.findByRole('button', { name: '탑고수 팔로우' }));
  expect(await screen.findByText(/게스트는 기록이 사라질 수 있습니다\./)).toBeTruthy();
  expect(screen.getByRole('button', { name: '탑고수 팔로우 취소' }).textContent).toBe('팔로우중');
  expect(TABLES.influencer_follows).toEqual([expect.objectContaining({ follower_id: 'u-guest' })]);
});

test('[+]: 실패하면 쉬운 말로 이유 (호출이 너무 잦음 / 알 수 없는 오류)', async () => {
  influencer();
  fan();
  fakeState.rpcError = '팔로우를 너무 자주 눌렀습니다. 1분 뒤에 다시 해 주세요.';
  fakeState.rpcErrorCode = '23514';
  start(MATCHUP);
  fireEvent.click(await screen.findByRole('button', { name: '탑고수 팔로우' }));
  expect((await screen.findByRole('alert')).textContent).toBe('팔로우를 너무 자주 눌렀습니다. 1분 뒤에 다시 해 주세요.');
  expect(screen.getByRole('button', { name: '탑고수 팔로우' }).textContent).toBe('+');
  fakeState.rpcError = 'TypeError: Failed to fetch';
  fireEvent.click(screen.getByRole('button', { name: '탑고수 팔로우' }));
  await waitFor(() => expect(screen.getByRole('alert').textContent).toBe('팔로우하지 못했습니다. 인터넷 연결을 확인한 뒤 다시 해 주세요.'));
  fakeState.rpcError = 'something odd';
  fireEvent.click(screen.getByRole('button', { name: '탑고수 팔로우' }));
  await waitFor(() => expect(screen.getByRole('alert').textContent).toBe('팔로우하지 못했습니다. 잠시 뒤 다시 해 주세요.'));
});
