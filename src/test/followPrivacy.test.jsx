// 팔로우 목록 공개 범위 (063, SPEC 6-74): [팔로워 목록]은 내 페이지(정식 회원)·운영자에게만, 날짜 없음, 장인 본인에게는 차단 관계가 목록·남은 수에서 빠짐(운영자는 전부),
// 팔로우한 장인 목록도 날짜 없음, 비회원은 팔로우한 장인 목록 대신 안내
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeGuestLogin, fakeLogin } from './fakeSupabase';
import { GUEST_FOLLOWING_TEXT } from '../pages/Following';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /></MemoryRouter>);

/** u-102(탑고수)를 장인으로, 팔로워 n명 (u-f1이 가장 오래, u-fn이 가장 최근) */
function setup(n = 3) {
  const b = TABLES.builds.find((x) => x.id === 102);
  b.author = { ...b.author, influencer: 'creator' };
  TABLES.profiles.push({ id: 'u-102', nickname: '탑고수', role: 'user', level: 7, main_title: null, influencer: 'creator' });
  for (let i = 1; i <= n; i += 1) {
    const id = `u-f${i}`;
    TABLES.profiles.push({ id, nickname: `팔로워${String(i).padStart(2, '0')}`, role: 'user', level: 1, main_title: null });
    TABLES.influencer_follows.push({ follower_id: id, influencer_id: 'u-102', created_at: `2026-11-${String(i).padStart(2, '0')}T00:00:00Z` });
  }
}
const owner = () => fakeLogin('u-102', { nickname: '탑고수', influencer: 'creator' });
const listButton = () => screen.queryByRole('button', { name: '팔로워 목록' });
const followerNames = () => [...document.querySelectorAll('.follower-list li')].map((li) => li.textContent);

test('남의 장인 페이지: 정식 회원·다른 장인·감독관·비회원·비로그인 모두 [팔로워 목록]이 없고, ?followers=1이어도 목록이 없다', async () => {
  setup();
  TABLES.profiles.push({ id: 'u-z', nickname: '제트', role: 'user', level: 3, main_title: null, influencer: 'pro' });
  const who = [
    () => fakeLogin('u-fan', { nickname: '팬' }),
    () => fakeLogin('u-z', { nickname: '제트', influencer: 'pro' }),
    () => fakeLogin('u-mod', { nickname: '감독', role: 'moderator' }),
    () => fakeGuestLogin('u-guest', { nickname: '손님' }),
    () => {},
  ];
  for (const login of who) {
    login();
    start('/u/u-102?followers=1');
    await screen.findByRole('heading', { name: '처음 만든 빌드' });
    expect(document.querySelector('.follower-count').textContent).toBe('3'); // 팔로워 수는 누구나
    expect(listButton()).toBeNull();
    expect(screen.queryByRole('button', { name: '팔로워 목록 닫기' })).toBeNull();
    expect(screen.queryByRole('heading', { name: '팔로워' })).toBeNull();
    cleanup();
  }
});

test('내 페이지: [팔로워 목록] — 닉네임만(날짜·「팔로우」 문구 없음), 최근 순', async () => {
  setup(3);
  owner();
  start('/u/u-102');
  fireEvent.click(await screen.findByRole('button', { name: '팔로워 목록' }));
  await waitFor(() => expect(followerNames()).toEqual(['팔로워03', '팔로워02', '팔로워01']));
  const box = screen.getByRole('heading', { name: '팔로워' }).closest('section');
  expect(box.textContent).not.toMatch(/2026-11|팔로우/);
});

test('내 페이지: 내가 차단한 팔로워·나를 차단한 팔로워는 목록과 [더보기] 남은 수에서 빠진다', async () => {
  setup(23);
  TABLES.user_blocks.push(
    { blocker_id: 'u-102', blocked_id: 'u-f23', created_at: '2026-11-20T00:00:00Z' }, // 내가 차단
    { blocker_id: 'u-f22', blocked_id: 'u-102', created_at: '2026-11-20T00:00:00Z' }, // 나를 차단
    { blocker_id: 'u-f21', blocked_id: 'u-f1', created_at: '2026-11-20T00:00:00Z' }, // 나와 무관
  );
  owner();
  start('/u/u-102');
  fireEvent.click(await screen.findByRole('button', { name: '팔로워 목록' }));
  await waitFor(() => expect(followerNames()).toHaveLength(20));
  expect(followerNames()[0]).toBe('팔로워21');
  expect(followerNames()).not.toContain('팔로워23');
  expect(followerNames()).not.toContain('팔로워22');
  const box = screen.getByRole('heading', { name: '팔로워' }).closest('section');
  fireEvent.click(within(box).getByRole('button', { name: '더보기 (1명 남음)' })); // 23 - 2 = 21명
  await waitFor(() => expect(followerNames()).toHaveLength(21));
  expect(followerNames()).toContain('팔로워01');
  expect(within(box).queryByRole('button', { name: /더보기/ })).toBeNull();
});

test('운영자(모드 켜짐)는 남의 장인 페이지에서도 [팔로워 목록] — 차단 관계와 상관없이 전부(날짜 없음), 모드를 끄면 없다', async () => {
  setup(4);
  TABLES.user_blocks.push(
    { blocker_id: 'u-102', blocked_id: 'u-f4', created_at: '2026-11-20T00:00:00Z' }, // 장인이 차단
    { blocker_id: 'u-f3', blocked_id: 'u-102', created_at: '2026-11-20T00:00:00Z' }, // 장인을 차단
    { blocker_id: 'u-op', blocked_id: 'u-f2', created_at: '2026-11-20T00:00:00Z' }, // 운영자 자신이 차단
  );
  fakeLogin('u-op', { nickname: '영자', role: 'admin' });
  start('/u/u-102');
  fireEvent.click(await screen.findByRole('button', { name: '팔로워 목록' }));
  await waitFor(() => expect(followerNames()).toEqual(['팔로워04', '팔로워03', '팔로워02', '팔로워01']));
  expect(screen.getByRole('heading', { name: '팔로워' }).closest('section').textContent).not.toMatch(/2026-11|팔로우/);
  cleanup();
  // 같은 데이터를 장인 본인이 보면 차단 관계(f3·f4)가 빠진다
  owner();
  start('/u/u-102');
  fireEvent.click(await screen.findByRole('button', { name: '팔로워 목록' }));
  await waitFor(() => expect(followerNames()).toEqual(['팔로워02', '팔로워01']));
  cleanup();
  TABLES.profiles.find((p) => p.id === 'u-op').operator_mode = false;
  fakeLogin('u-op', { nickname: '영자', role: 'admin' });
  start('/u/u-102');
  await screen.findByRole('heading', { name: '처음 만든 빌드' });
  expect(listButton()).toBeNull();
});

test('/me/followers 알림 링크: 장인 본인은 그대로 내 팔로워 목록이 펼쳐진다', async () => {
  setup(2);
  owner();
  start('/me/followers');
  expect(await screen.findByRole('heading', { name: '팔로워' })).toBeTruthy();
  expect(screen.getByRole('button', { name: '팔로워 목록 닫기' })).toBeTruthy();
  await waitFor(() => expect(followerNames()).toEqual(['팔로워02', '팔로워01']));
});

test('팔로우한 장인 목록: 유형·팔로워 수만(날짜 없음) / 비회원은 안내만(빌드 탭은 그대로)', async () => {
  setup(1);
  TABLES.influencer_follows.push({ follower_id: 'u-fan', influencer_id: 'u-102', created_at: '2026-11-13T00:00:00Z' });
  fakeLogin('u-fan', { nickname: '팬' });
  start('/following?tab=list');
  const row = (await screen.findByRole('link', { name: /탑고수/ })).closest('li');
  expect(row.textContent).toContain('크리에이터 · 팔로워 2명');
  expect(row.textContent).not.toMatch(/2026-11-13|\d{4}-\d{2}-\d{2}/);
  cleanup();
  TABLES.influencer_follows.push({ follower_id: 'u-guest', influencer_id: 'u-102', created_at: '2026-11-13T00:00:00Z' });
  fakeGuestLogin('u-guest', { nickname: '손님' });
  start('/following?tab=list');
  expect(await screen.findByText(GUEST_FOLLOWING_TEXT)).toBeTruthy();
  expect(document.querySelector('.following-list')).toBeNull();
  fireEvent.click(screen.getByRole('tab', { name: '빌드' }));
  expect(await screen.findByText(/팔로우한 장인이 처음 만든 공개 빌드/)).toBeTruthy();
});
