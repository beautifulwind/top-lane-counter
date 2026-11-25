// 6-115 (1.3 패치 2-G): /lists·/following의 「팔로우한 장인」을 장인 목록(/influencers)과 같은 카드(InfluencerRow)로 —
// 079 my_following_cards(사진·공개 빌드 수), 없으면(079 전 DB) my_following으로 되돌아감. 팔로우 취소 등 기존 동작 그대로.
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeGuestLogin, fakeLogin, fakeState } from './fakeSupabase';
import { GUEST_FOLLOWING_TEXT, NO_FOLLOW_TEXT } from '../pages/Following';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /></MemoryRouter>);
const inf = (id, nickname, extra = {}) => TABLES.profiles.push({ id, nickname, role: 'user', level: 3, main_title: null, influencer: 'creator', email: `${id}@x.com`, ...extra });
const follow = (who, whom, at = '2026-11-10T00:00:00Z') => TABLES.influencer_follows.push({ follower_id: who, influencer_id: whom, created_at: at });
const section = () => screen.findByRole('region', { name: '내가 팔로우한 장인' });
const rows = (sec) => [...sec.querySelectorAll('li.inf-row')];
const nick = (row) => row.querySelector('.user-nick').textContent;

function three() {
  inf('i-a', '사진장인', { influencer: 'pro', photo_path: 'i-a/p.jpg' });
  inf('i-b', '빈사진', { photo_path: null });
  inf('i-c', '정지장인');
  fakeLogin('u-fan', { nickname: '팬' });
  follow('u-fan', 'i-a', '2026-11-12T00:00:00Z');
  follow('u-fan', 'i-b', '2026-11-11T00:00:00Z');
  follow('u-fan', 'i-c', '2026-11-13T00:00:00Z');
  follow('u-other', 'i-a');
  TABLES.user_restrictions.push({ id: 1, user_id: 'i-c', reason: '검사', ends_at: '2099-01-01T00:00:00Z', lifted_at: null });
}

test('/following 팔로우한 장인: 장인 목록과 같은 카드 — 사진·닉네임·「인증」·유형·빌드·팔로워, 사진 없으면 첫 글자 원, 정지 중인 장인은 빠짐', async () => {
  three();
  start('/following?tab=list');
  const sec = await section();
  await waitFor(() => expect(rows(sec).map(nick)).toEqual(['사진장인', '빈사진'])); // 최근 팔로우 순, 정지장인(가장 최근) 제외
  expect(sec.textContent).toContain('팔로우한 장인 2명');
  expect(sec.querySelector('ul.inf-rows')).not.toBeNull();
  const [a, b] = rows(sec);
  await waitFor(() => expect(a.querySelector('img.inf-row-photo')?.getAttribute('src')).toContain('i-a/p.jpg'));
  expect(a.querySelector('.inf-row-photo').getAttribute('alt')).toBe(''); // 닉네임이 바로 옆에 있어 그림 설명은 비움
  expect(b.querySelector('img')).toBeNull();
  expect(b.querySelector('.inf-row-initial').textContent).toBe('빈');
  expect(a.querySelector('.inf-tag').textContent).toBe('인증');
  expect(a.querySelector('.muted').textContent).toMatch(/^프로게이머 · 빌드 \d+ · 팔로워 2$/);
  expect(b.querySelector('.muted').textContent).toBe('크리에이터 · 빌드 0 · 팔로워 1');
  const link = within(a).getByRole('link', { name: /사진장인/ });
  expect(link.getAttribute('href')).toBe('/u/i-a');
  // 팔로우 버튼은 줄 링크 밖 (눌러도 이동하지 않음)
  const btn = within(a).getByRole('button', { name: '사진장인 팔로우 취소' });
  expect(link.contains(btn)).toBe(false);
  expect(fakeState.followCardsCalls).toBe(1);
});

test('/lists [팔로우한 장인] 탭도 같은 카드 · [팔로우중]을 누르면 취소(팔로워 수 줄어듦), 다시 누르면 팔로우', async () => {
  three();
  start('/lists?tab=following');
  const sec = await section();
  await waitFor(() => expect(rows(sec)).toHaveLength(2));
  const a = rows(sec)[0];
  expect(a.querySelector('.inf-row-avatar')).not.toBeNull();
  fireEvent.click(within(a).getByRole('button', { name: '사진장인 팔로우 취소' }));
  const again = await within(a).findByRole('button', { name: '사진장인 팔로우' });
  expect(a.querySelector('.muted').textContent).toMatch(/팔로워 1$/);
  expect(TABLES.influencer_follows.some((f) => f.follower_id === 'u-fan' && f.influencer_id === 'i-a')).toBe(false);
  expect(rows(sec)).toHaveLength(2); // 취소해도 줄은 남아 다시 팔로우할 수 있다
  fireEvent.click(again);
  expect(await within(a).findByRole('button', { name: '사진장인 팔로우 취소' })).toBeTruthy();
  expect(a.querySelector('.muted').textContent).toMatch(/팔로워 2$/);
  expect(screen.getByRole('link', { name: '팔로우한 장인의 빌드 모아 보기' })).toBeTruthy();
});

test('079 전 DB(my_following_cards 없음): my_following으로 되돌아가 닉네임·유형·팔로워는 보이고, 사진은 첫 글자 원·「빌드 N」은 빠짐', async () => {
  three();
  fakeState.followCardsMissing = true;
  start('/following?tab=list');
  const sec = await section();
  await waitFor(() => expect(rows(sec).map(nick)).toEqual(['정지장인', '사진장인', '빈사진'])); // my_following은 정지 중인 장인도 보인다(기존 함수 그대로)
  const a = rows(sec)[1];
  expect(a.querySelector('img')).toBeNull();
  expect(a.querySelector('.inf-row-initial').textContent).toBe('사');
  expect(a.querySelector('.muted').textContent).toBe('프로게이머 · 팔로워 2');
  expect(screen.queryByRole('alert')).toBeNull();
});

test('20명씩 [더보기] (겹침 없음), 팔로우한 장인이 없으면 안내, 비회원은 안내만(함수를 부르지 않음)', async () => {
  fakeLogin('u-fan', { nickname: '팬' });
  for (let i = 1; i <= 23; i++) {
    const id = `i-${String(i).padStart(2, '0')}`;
    inf(id, `장인${String(i).padStart(2, '0')}`);
    follow('u-fan', id, `2026-11-${String(i).padStart(2, '0')}T00:00:00Z`);
  }
  start('/following?tab=list');
  const sec = await section();
  await waitFor(() => expect(rows(sec)).toHaveLength(20));
  expect(nick(rows(sec)[0])).toBe('장인23');
  fireEvent.click(within(sec).getByRole('button', { name: '더보기 (3명 남음)' }));
  await waitFor(() => expect(rows(sec)).toHaveLength(23));
  expect(new Set(rows(sec).map(nick)).size).toBe(23);
  expect(nick(rows(sec)[22])).toBe('장인01');
  cleanup();
  fakeLogin('u-none', { nickname: '새팬' });
  start('/lists?tab=following');
  expect(await screen.findByText(NO_FOLLOW_TEXT)).toBeTruthy();
  cleanup();
  const calls = fakeState.followCardsCalls;
  fakeGuestLogin('u-guest', { nickname: '손님' });
  start('/following?tab=list');
  expect(await screen.findByText(GUEST_FOLLOWING_TEXT)).toBeTruthy();
  expect(document.querySelector('.inf-row')).toBeNull();
  expect(fakeState.followCardsCalls).toBe(calls);
});

test('긴 닉네임도 카드 안에서 줄바꿈 (380px 폭 — 줄·글자·버튼 칸이 줄어들 수 있게 min-width 0, 버튼 칸은 45%까지)', async () => {
  inf('i-long', 'ㅁ'.repeat(20));
  fakeLogin('u-fan', { nickname: '팬' });
  follow('u-fan', 'i-long');
  start('/following?tab=list');
  const sec = await section();
  await waitFor(() => expect(rows(sec)).toHaveLength(1));
  const r = rows(sec)[0];
  expect(r.querySelector('.inf-row-main .inf-row-text .inf-row-name .user-nick').textContent).toHaveLength(20);
  expect(r.querySelector('.inf-row-follow .follow-btn, .inf-row-follow button')).not.toBeNull();
});
