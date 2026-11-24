// 1.3 패치 1-C (SPEC 6-98): 장인 프로필 개편 — 상단 카드(빌드 N · 팔로워 N), 버튼 줄(팔로우·유튜브 채널명·공유), 팔로워 목록 권한, 빌드 목록(최신순·인기순 칩, 쪽 번호)
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { AppRoutes } from '../App';
import { isYoutubeHost, youtubeHandle } from '../lib/links';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeBuild, fakeLogin } from './fakeSupabase';

beforeEach(() => {
  window.matchMedia = undefined;
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); delete navigator.share; });

let where = '';
function Where() {
  const l = useLocation();
  where = l.pathname + l.search;
  return null;
}
const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /><Where /></MemoryRouter>);
const addLink = (owner, url, extra = {}) => {
  const host = url.slice(8).split(/[/?#]/)[0];
  TABLES.ext_links.push({ id: 700 + TABLES.ext_links.length, owner_id: owner, build_id: null, url, host, sort: TABLES.ext_links.length, ...extra });
};
const makeInfluencer = () => {
  const b = TABLES.builds.find((x) => x.id === 102);
  b.author = { ...b.author, influencer: 'creator' };
  TABLES.profiles.push({ id: 'u-102', nickname: '탑고수', role: 'user', level: 7, main_title: null, influencer: 'creator' });
};
const manyBuilds = (n) => {
  for (let i = 0; i < n; i += 1) {
    TABLES.builds.push(fakeBuild(200 + i, { nickname: '탑고수', influencer: 'creator' }, {
      author_id: 'u-102', name: `빌드이름${i}`, seq: 10 + i, up_count: i % 5, updated_at: `2026-10-${String(i + 1).padStart(2, '0')}T00:00:00Z`,
    }));
  }
};
const names = () => [...document.querySelectorAll('.build-cards .inf-build-name')].map((e) => e.textContent);
const chip = (name) => screen.getByRole('button', { name });

test('유튜브 채널명: 인코딩된 @이름을 한글로, 채널명이 없는 주소·깨진 주소는 null', () => {
  expect(youtubeHandle('https://www.youtube.com/@%ED%8E%98%EC%9D%B4%EC%BB%A4')).toBe('@페이커');
  expect(youtubeHandle('https://www.youtube.com/@toptop/videos')).toBe('@toptop');
  expect(youtubeHandle('https://www.youtube.com/channel/UC123')).toBeNull();
  expect(youtubeHandle('https://youtu.be/abc')).toBeNull();
  expect(youtubeHandle('https://www.youtube.com/@%E0%A4%A')).toBeNull(); // 디코딩 실패
  expect(isYoutubeHost('m.youtube.com') && isYoutubeHost('youtu.be') && !isYoutubeHost('notyoutube.com')).toBe(true);
});

test('상단 카드: 닉네임·장인 표시·「빌드 N · 팔로워 N」(공개 빌드만), 사진이 없으면 첫 글자 원, 받은 추천 수는 없다', async () => {
  makeInfluencer();
  TABLES.builds.push(fakeBuild(150, { nickname: '탑고수', influencer: 'creator' }, { author_id: 'u-102', status: 'hidden' }));
  TABLES.builds.push(fakeBuild(151, { nickname: '탑고수', influencer: 'creator' }, { author_id: 'u-102', status: 'pending' }));
  TABLES.influencer_follows.push({ follower_id: 'u-x', influencer_id: 'u-102', created_at: '2026-11-01T00:00:00Z' });
  start('/u/u-102');
  const h1 = await screen.findByRole('heading', { level: 1 });
  expect(h1.querySelector('.inf-tag').textContent).toBe('장인');
  const hero = h1.closest('header');
  expect(hero.querySelector('.inf-meta').textContent).toBe('인증된 크리에이터 · 빌드 1 · 팔로워 1');
  expect(hero.querySelector('.inf-hero-initial').textContent).toBe('탑');
  expect(hero.textContent).not.toMatch(/추천|좋아요/);
  expect(screen.getByRole('heading', { name: '처음 만든 빌드' }).closest('section').querySelector('.count-badge').textContent).toBe('1개');
});

test('버튼 줄: 팔로우 · 유튜브(@한글 채널명) · 공유가 한 줄에, 외부 이동 안내 한 줄', async () => {
  makeInfluencer();
  addLink('u-102', 'https://www.youtube.com/@%ED%8E%98%EC%9D%B4%EC%BB%A4');
  fakeLogin('u-fan', { nickname: '팬', level: 2 });
  start('/u/u-102');
  await screen.findByRole('heading', { level: 1 });
  const row = document.querySelector('.inf-btn-row');
  expect(within(row).getByRole('button', { name: '탑고수 팔로우' })).toBeTruthy();
  expect(row.querySelector('.inf-yt a').textContent).toContain('@페이커');
  expect(within(row).getByRole('button', { name: '공유' })).toBeTruthy();
  expect(document.querySelector('.inf-leave-note').textContent).toMatch(/외부 사이트로 이동/);
  fireEvent.click(within(row).getByRole('button', { name: '탑고수 팔로우' })); // 기존 팔로우 동작 그대로
  expect(await within(row).findByRole('button', { name: '탑고수 팔로우 취소' })).toBeTruthy();
  expect(document.querySelector('.follower-count').textContent).toBe('1');
});

test('유튜브 링크가 없으면 버튼과 안내를 숨긴다 (다른 링크만 있으면 작은 목록으로)', async () => {
  makeInfluencer();
  addLink('u-102', 'https://chzzk.naver.com/live/toptop');
  start('/u/u-102');
  await screen.findByRole('heading', { level: 1 });
  expect(document.querySelector('.inf-yt')).toBeNull();
  expect(document.querySelector('.inf-leave-note')).toBeNull();
  expect(within(screen.getByRole('list', { name: '링크' })).getAllByRole('link')).toHaveLength(1);
  expect(screen.getByRole('button', { name: '공유' })).toBeTruthy(); // 공유는 늘 있다
});

test('공유: 기기 공유 창이 있으면 현재 프로필 주소(쪽·정렬 꼬리 없이), 없으면 주소 복사', async () => {
  makeInfluencer();
  const share = vi.fn().mockResolvedValue(undefined);
  navigator.share = share;
  start('/u/u-102?sort=popular&page=2');
  fireEvent.click(await screen.findByRole('button', { name: '공유' }));
  await waitFor(() => expect(share).toHaveBeenCalled());
  expect(share.mock.calls[0][0]).toEqual({ title: '탑고수 프로필', url: `${window.location.origin}/u/u-102` });
  cleanup();
  delete navigator.share;
  const write = vi.fn().mockResolvedValue(undefined);
  Object.defineProperty(navigator, 'clipboard', { value: { writeText: write }, configurable: true });
  start('/u/u-102');
  fireEvent.click(await screen.findByRole('button', { name: '공유' }));
  expect(await screen.findByText('주소를 복사했습니다.')).toBeTruthy();
  expect(write).toHaveBeenCalledWith(`${window.location.origin}/u/u-102`);
});

test('팔로워 목록: 본인과 운영자에게만, 다른 사람·비로그인에게는 버튼도 목록도 없다', async () => {
  makeInfluencer();
  TABLES.profiles.push({ id: 'u-f1', nickname: '팔로워01', role: 'user', level: 1, main_title: null });
  TABLES.influencer_follows.push({ follower_id: 'u-f1', influencer_id: 'u-102', created_at: '2026-11-01T00:00:00Z' });
  start('/u/u-102');
  await screen.findByRole('heading', { level: 1 });
  expect(screen.queryByRole('button', { name: /팔로워 목록/ })).toBeNull();
  cleanup();
  fakeLogin('u-other', { nickname: '남' });
  start('/u/u-102?followers=1');
  await screen.findByRole('heading', { level: 1 });
  expect(screen.queryByRole('button', { name: /팔로워 목록/ })).toBeNull();
  expect(document.querySelector('#pp-followers')).toBeNull();
  cleanup();
  fakeLogin('u-102', { nickname: '탑고수', level: 7, main_title: null, influencer: 'creator', influencer_at: '2026-11-12T00:00:00Z' });
  start('/u/u-102');
  fireEvent.click(await screen.findByRole('button', { name: '팔로워 목록' }));
  expect(await screen.findByText('팔로워01')).toBeTruthy();
});

test('빌드 목록: 기본은 최신순(최근 수정순) 칩 눌림·주소에 없음, 인기순은 ?sort=popular, 추천 많은 순(같으면 최근 수정순)', async () => {
  makeInfluencer();
  manyBuilds(6); // up_count 0 1 2 3 4 0, 수정일 10-01 … 10-06
  start('/u/u-102');
  await screen.findByRole('heading', { name: '처음 만든 빌드' });
  expect(chip('최신순')).toHaveAttribute('aria-pressed', 'true');
  expect(names().slice(0, 3)).toEqual(['빌드 2', '빌드이름5', '빌드이름4']);
  fireEvent.click(chip('인기순'));
  await waitFor(() => expect(where).toBe('/u/u-102?sort=popular'));
  await waitFor(() => expect(chip('인기순')).toHaveAttribute('aria-pressed', 'true'));
  await waitFor(() => expect(names().slice(0, 3)).toEqual(['빌드 2', '빌드이름4', '빌드이름3'])); // 102는 추천 5로 가장 앞
  fireEvent.click(chip('최신순'));
  await waitFor(() => expect(where).toBe('/u/u-102'));
  expect(names()[0]).toBe('빌드 2');
});

test('빌드 목록: 잘못된 ?sort=는 최신순, 칩을 바꾸면 1쪽으로, 쪽 번호는 정렬을 유지 (인기순은 쪽 전체에 걸쳐 정렬)', async () => {
  makeInfluencer();
  manyBuilds(24); // 102 포함 25개 → 2쪽
  const first = start('/u/u-102?sort=weird');
  await screen.findByRole('heading', { name: '처음 만든 빌드' });
  expect(chip('최신순')).toHaveAttribute('aria-pressed', 'true');
  first.unmount();
  start('/u/u-102?page=2');
  await waitFor(() => expect(names()).toHaveLength(5));
  fireEvent.click(chip('인기순'));
  await waitFor(() => expect(where).toBe('/u/u-102?sort=popular')); // page 삭제 = 1쪽
  await waitFor(() => expect(names()).toHaveLength(20));
  expect(names()[0]).toBe('빌드 2'); // 인기순 1쪽 맨 앞 (추천 5) — 최신순 2쪽에 있던 빌드도 쪽을 가로질러 정렬된다
  fireEvent.click(within(screen.getByRole('navigation', { name: '쪽 이동' })).getByRole('button', { name: '2쪽' }));
  await waitFor(() => expect(where).toBe('/u/u-102?sort=popular&page=2'));
  await waitFor(() => expect(names()).toHaveLength(5));
  expect(chip('인기순')).toHaveAttribute('aria-pressed', 'true');
  expect(names()).not.toContain('빌드 2');
});

test('빌드 목록: 숨김·승인 대기 빌드는 나오지 않고, 영상 링크가 있는 카드에만 영상 버튼', async () => {
  makeInfluencer();
  TABLES.builds.push(
    fakeBuild(150, { nickname: '탑고수', influencer: 'creator' }, { author_id: 'u-102', status: 'hidden', name: '숨긴빌드' }),
    fakeBuild(151, { nickname: '탑고수', influencer: 'creator' }, { author_id: 'u-102', status: 'pending', name: '대기빌드' }),
  );
  addLink('u-102', 'https://www.youtube.com/watch?v=9', { build_id: 102 });
  start('/u/u-102');
  await screen.findByRole('heading', { name: '처음 만든 빌드' });
  expect(names()).toEqual(['빌드 2']);
  expect(document.body.textContent).not.toMatch(/숨긴빌드|대기빌드/);
  expect(screen.getByRole('link', { name: /관련 영상 보기/ })).toBeTruthy();
  expect(screen.queryByRole('navigation', { name: '쪽 이동' })).toBeNull(); // 한 쪽이면 쪽 번호 없음
});
