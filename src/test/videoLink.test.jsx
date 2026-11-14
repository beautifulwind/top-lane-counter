// 관련 영상 링크 화면 개선 (SPEC 6-45): 상대법 화면 [사이트 이름] 관련 영상 보기 · 입력 칸 안내 · /following 카드 · /u/:id 빈 상태
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, render, screen, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeLogin } from './fakeSupabase';
import { siteName } from '../lib/links';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /></MemoryRouter>);
const MATCHUP = '/champion/Darius/counter/Quinn';
const addLink = (owner, url, extra = {}) => {
  const host = url.slice(8).split(/[/?#]/)[0];
  TABLES.ext_links.push({ id: 700 + TABLES.ext_links.length, owner_id: owner, build_id: null, url, host, sort: TABLES.ext_links.length, ...extra });
};
const makeInfluencer = () => {
  const b = TABLES.builds.find((x) => x.id === 102);
  b.author = { ...b.author, influencer: 'creator' };
  TABLES.profiles.push({ id: 'u-102', nickname: '탑고수', role: 'user', level: 7, main_title: null, influencer: 'creator' });
};

test('사이트 이름은 주소의 도메인으로 판별한다', () => {
  const name = (url) => siteName(url.slice(8).split(/[/?#]/)[0]);
  expect(name('https://www.youtube.com/watch?v=1')).toBe('유튜브');
  expect(name('https://m.youtube.com/watch?v=1')).toBe('유튜브');
  expect(name('https://youtu.be/abc')).toBe('유튜브');
  expect(name('https://chzzk.naver.com/video/1')).toBe('치지직');
  expect(name('https://vod.sooplive.co.kr/player/1')).toBe('숲');
  expect(name('https://vod.afreecatv.com/player/1')).toBe('숲');
  expect(name('https://www.instagram.com/reel/1')).toBe('인스타그램');
  expect(name('https://www.twitch.tv/videos/1')).toBe('트위치');
  expect(name('https://x.com/a/status/1')).toBe('X');
  expect(name('https://twitter.com/a/status/1')).toBe('X');
});

test('상대법 화면: 영상 링크가 있으면 "사이트 이름 + 관련 영상 보기"(새 창), 없으면 아무것도 없다', async () => {
  makeInfluencer();
  addLink('u-102', 'https://chzzk.naver.com/video/77', { build_id: 102 });
  start(MATCHUP);
  await screen.findByText(/퀸으로 다리우스 이기는 법/);
  const row = document.querySelector('.build-panel > .build-link-row');
  expect(row).not.toBeNull();
  const a = within(row).getByRole('link', { name: /관련 영상 보기/ });
  expect(a.className).toContain('video-link');
  expect(a.getAttribute('target')).toBe('_blank');
  expect(a.getAttribute('rel')).toContain('noopener');
  expect(a.querySelector('.ext-site').textContent).toBe('치지직');
  expect(row.className).toContain('build-link-row'); // flex-wrap (좁은 화면 줄바꿈)
  expect(within(row).getByRole('button', { name: '장인 링크 더보기' })).toBeTruthy(); // ⋮ 그대로
  cleanup();
  TABLES.ext_links = [];
  start(MATCHUP);
  await screen.findByText(/퀸으로 다리우스 이기는 법/);
  expect(document.querySelector('.build-link-row')).toBeNull();
  expect(screen.queryByText('관련 영상 보기')).toBeNull();
});

test('입력 칸 안내: 영상이 있으면 달아 보세요 (선택, 1개)', async () => {
  makeInfluencer();
  fakeLogin('u-102', { nickname: '탑고수', level: 7, main_title: null, influencer: 'creator', influencer_at: '2026-11-12T00:00:00Z' });
  start(MATCHUP);
  await screen.findByText(/퀸으로 다리우스 이기는 법/);
  const box = screen.getByRole('heading', { name: /관련 영상 링크/, level: 3 }).closest('section');
  expect(box.textContent).toContain('이 빌드를 설명하는 영상이 있으면 달아 보세요(선택, 1개).');
});

test('팔로우 모아보기 카드: 영상 링크가 있으면 보이고 없으면 안 보인다', async () => {
  makeInfluencer();
  TABLES.influencer_follows.push({ follower_id: 'u-fan', influencer_id: 'u-102', created_at: '2026-11-10T00:00:00Z' });
  addLink('u-102', 'https://www.youtube.com/watch?v=9', { build_id: 102 });
  fakeLogin('u-fan', { nickname: '팬' });
  start('/following');
  const card = (await screen.findByRole('region', { name: '팔로우한 장인의 빌드' }));
  const a = await within(card).findByRole('link', { name: /관련 영상 보기/ });
  expect(a.querySelector('.ext-site').textContent).toBe('유튜브');
  cleanup();
  TABLES.ext_links = [];
  start('/following');
  const card2 = await screen.findByRole('region', { name: '팔로우한 장인의 빌드' });
  await within(card2).findByText(/빌드 2/);
  expect(within(card2).queryByText('관련 영상 보기')).toBeNull();
});

test('장인 페이지: 링크가 없으면 본인에게만 안내와 [링크 관리로 가기], 타인에게는 안 보인다', async () => {
  makeInfluencer();
  fakeLogin('u-102', { nickname: '탑고수', level: 7, main_title: null, influencer: 'creator', influencer_at: '2026-11-12T00:00:00Z' });
  start('/u/u-102');
  await screen.findByRole('heading', { level: 1 });
  expect(screen.getByText('채널 링크를 등록해 보세요.')).toBeTruthy();
  expect(screen.getByRole('link', { name: '링크 관리로 가기' }).getAttribute('href')).toBe('/me/links');
  cleanup();
  fakeLogin('u-other', { nickname: '남' });
  start('/u/u-102');
  await screen.findByRole('heading', { level: 1 });
  expect(screen.queryByText('채널 링크를 등록해 보세요.')).toBeNull();
  expect(screen.queryByRole('link', { name: '링크 관리로 가기' })).toBeNull();
  cleanup();
  addLink('u-102', 'https://www.youtube.com/@toptop');
  fakeLogin('u-102', { nickname: '탑고수', level: 7, main_title: null, influencer: 'creator', influencer_at: '2026-11-12T00:00:00Z' });
  start('/u/u-102');
  await screen.findByRole('heading', { level: 1 });
  expect(screen.queryByText('채널 링크를 등록해 보세요.')).toBeNull(); // 링크가 있으면 본인에게도 안 보임
  expect(within(screen.getByRole('list', { name: '링크' })).getByRole('link').querySelector('.ext-site').textContent).toBe('유튜브');
});
