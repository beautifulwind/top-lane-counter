// 1.3 패치 1-B2 (SPEC 6-94): 메인 화면 — 장인 줄(표시·「전체」·장인 클릭·실패/0명이면 숨김·차단 제외) · 검색창 위치 · 챔피언 4줄 + 모두 보기/접기 · 헤더 돋보기 없음
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { AppRoutes } from '../App';
import { CHAMP_VISIBLE_ROWS, HOME_INFLUENCER_COUNT } from '../lib/homeLayout';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeLogin, fakeState } from './fakeSupabase';

const ctl = vi.hoisted(() => ({ fail: false, champs: 30 }));
vi.mock('../api/ddragon', async (orig) => ({
  ...(await orig()),
  getChampions: async () => Array.from({ length: ctl.champs }, (_, i) => ({
    id: `C${String(i).padStart(2, '0')}`, name: `챔프${String(i).padStart(2, '0')}`, title: '', tags: [], icon: `/c${i}.png`,
  })),
}));
vi.mock('../api/follow', async (orig) => {
  const real = await orig();
  return { ...real, getInfluencerDirectory: (...a) => (ctl.fail ? Promise.reject(new Error('boom')) : real.getInfluencerDirectory(...a)) };
});

const COLS = 5; // 시험에서 격자는 한 줄 5칸이라고 본다 (진짜 칸 수는 브라우저 CSS가 정함 → homeLayout.gridColumnCount)
let realStyle;
beforeEach(() => {
  ctl.fail = false; ctl.champs = 30;
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
  realStyle = window.getComputedStyle.bind(window);
  vi.spyOn(window, 'getComputedStyle').mockImplementation((el, ...rest) => (
    el?.classList?.contains('champ-grid')
      ? Object.assign(realStyle(el, ...rest), { gridTemplateColumns: Array(COLS).fill('76px').join(' ') }) // 나머지는 진짜 값, 칸 목록만 5칸으로
      : realStyle(el, ...rest)
  ));
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

function Where() { const l = useLocation(); return <output data-testid="where">{l.pathname}{l.search}</output>; }
const start = () => render(<MemoryRouter initialEntries={['/']}><AppRoutes /><Where /></MemoryRouter>);
const where = () => screen.getByTestId('where').textContent;
const inf = (id, nickname, extra = {}) => TABLES.profiles.push({ id, nickname, role: 'user', level: 3, main_title: null, influencer: 'creator', ...extra });
const follow = (n, whom) => { for (let i = 0; i < n; i++) TABLES.influencer_follows.push({ follower_id: `fan-${whom}-${i}`, influencer_id: whom, created_at: '2026-11-10T00:00:00Z' }); };
const cells = () => document.querySelectorAll('.champ-grid li');
const LIMIT = COLS * CHAMP_VISIBLE_ROWS;

test('장인 줄: 팔로워 많은 순 앞 8명만(사진 없으면 첫 글자), 인원수 칩은 전체 수, 「전체」는 목록 밖에 따로, 「상대 챔피언」보다 위', async () => {
  for (let i = 1; i <= 10; i++) { inf(`i-${i}`, `장인${String(i).padStart(2, '0')}`); follow(20 - i, `i-${i}`); }
  start();
  const list = await screen.findByRole('list', { name: '장인 목록' });
  const links = within(list).getAllByRole('link');
  expect(links).toHaveLength(HOME_INFLUENCER_COUNT);
  expect(links.map((a) => a.getAttribute('aria-label'))).toEqual(Array.from({ length: 8 }, (_, i) => `장인${String(i + 1).padStart(2, '0')} 장인 페이지`));
  expect(links[0].getAttribute('href')).toBe('/u/i-1');
  expect(links[0].querySelector('.home-inf-initial').textContent).toBe('장');
  expect(fakeState.directoryCalls.at(-1)).toEqual({ p_query: '', p_sort: 'followers', p_page: 1, p_size: HOME_INFLUENCER_COUNT });
  const section = list.closest('section');
  expect(within(section).getByRole('heading', { name: /장인/ })).toBeDefined();
  expect(section.querySelector('.count-badge').textContent).toBe('10명');
  const all = within(section).getByRole('link', { name: '장인 전체 보기' });
  expect(all.getAttribute('href')).toBe('/influencers');
  expect(list.contains(all)).toBe(false); // 「전체」는 스크롤 목록 밖 = 제자리
  expect(all.textContent).toBe('전체');
  const enemy = await screen.findByRole('heading', { name: /상대 챔피언/ });
  expect(section.compareDocumentPosition(enemy.closest('section')) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  expect(screen.getByRole('heading', { level: 1, name: '챔피언 선택' }).compareDocumentPosition(section) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
});

test('장인 원을 누르면 그 장인 페이지로, 「전체」를 누르면 /influencers로', async () => {
  inf('i-1', '페이커'); follow(2, 'i-1');
  start();
  fireEvent.click(await screen.findByRole('link', { name: '페이커 장인 페이지' }));
  await waitFor(() => expect(where()).toBe('/u/i-1'));
  cleanup();
  start();
  fireEvent.click(await screen.findByRole('link', { name: '장인 전체 보기' }));
  await waitFor(() => expect(where()).toBe('/influencers'));
});

test('불러오기 실패: 장인 줄은 조용히 사라지고(오류 상자 없음) 챔피언 목록·검색은 정상', async () => {
  ctl.fail = true;
  inf('i-1', '페이커');
  start();
  expect(await screen.findByRole('heading', { name: /상대 챔피언/ })).toBeDefined();
  await waitFor(() => expect(document.querySelector('.home-inf')).toBeNull());
  expect(screen.queryByRole('alert')).toBeNull();
  expect(screen.queryByRole('link', { name: '장인 전체 보기' })).toBeNull();
  await waitFor(() => expect(cells().length).toBeGreaterThan(0));
  expect(screen.getByRole('combobox', { name: '챔피언·빌드 검색' })).toBeDefined();
});

test('장인이 0명이면 줄이 없고, 내가 차단한 장인은 줄에서 빠진다', async () => {
  start();
  expect(await screen.findByRole('heading', { name: /상대 챔피언/ })).toBeDefined();
  await waitFor(() => expect(document.querySelector('.home-inf')).toBeNull());
  cleanup();
  inf('i-1', '보이는장인'); inf('i-2', '차단한장인'); follow(1, 'i-1'); follow(1, 'i-2');
  fakeLogin('u-me', { nickname: '나' });
  TABLES.user_blocks.push({ blocker_id: 'u-me', blocked_id: 'i-2', blocked: { nickname: '차단한장인' } });
  start();
  expect(await screen.findByRole('link', { name: '보이는장인 장인 페이지' })).toBeDefined();
  await waitFor(() => expect(screen.queryByRole('link', { name: '차단한장인 장인 페이지' })).toBeNull());
});

test('검색창은 「상대 챔피언」 제목 바로 아래·격자 위에 있고, 헤더에는 돋보기가 없다', async () => {
  start();
  const heading = await screen.findByRole('heading', { name: /상대 챔피언/ });
  const search = screen.getByRole('combobox', { name: '챔피언·빌드 검색' });
  const grid = await waitFor(() => { const g = document.querySelector('.champ-grid'); expect(g).not.toBeNull(); return g; });
  expect(heading.compareDocumentPosition(search) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  expect(search.compareDocumentPosition(grid) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  expect(screen.getByRole('heading', { level: 1 }).compareDocumentPosition(heading) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  expect(screen.queryByRole('button', { name: '장인 찾기' })).toBeNull();
  expect([...document.querySelector('.topbar').querySelectorAll('button')].map((b) => b.getAttribute('aria-label'))).toEqual(['메뉴 열기']);
});

test('챔피언 격자: 4줄(한 줄 칸 수 × 4)만 보이고 「모두 보기」 → 전체 + 「접기」, 다시 누르면 4줄 (aria-expanded)', async () => {
  start();
  await waitFor(() => expect(cells()).toHaveLength(LIMIT));
  const btn = screen.getByRole('button', { name: '모두 보기' });
  expect(btn.getAttribute('aria-expanded')).toBe('false');
  expect(btn.getAttribute('aria-controls')).toBe('champ-grid');
  expect(btn.closest('.champ-more')).not.toBeNull(); // 4번째 줄 아래 가운데
  expect(screen.queryByRole('link', { name: new RegExp(`챔프${String(LIMIT).padStart(2, '0')}`) })).toBeNull(); // 접힌 칸은 아예 없다 = 초점·스크린리더 제외
  expect(screen.getByText('30개', { selector: '.count-badge' })).toBeDefined(); // 칩은 전체 수
  fireEvent.click(btn);
  await waitFor(() => expect(cells()).toHaveLength(30));
  const fold = screen.getByRole('button', { name: '접기' });
  expect(fold.getAttribute('aria-expanded')).toBe('true');
  fireEvent.click(fold);
  await waitFor(() => expect(cells()).toHaveLength(LIMIT));
  expect(screen.getByRole('button', { name: '모두 보기' })).toBeDefined();
});

test('4줄 이하면 「모두 보기」가 없다 / 화면 폭이 바뀌어 칸 수가 늘면 4줄 계산도 따라간다', async () => {
  ctl.champs = LIMIT;
  start();
  await waitFor(() => expect(cells()).toHaveLength(LIMIT));
  expect(screen.queryByRole('button', { name: /모두 보기|접기/ })).toBeNull();
  cleanup();
  ctl.champs = 30;
  start();
  await waitFor(() => expect(cells()).toHaveLength(LIMIT));
  expect(screen.getByRole('button', { name: '모두 보기' })).toBeDefined();
});

test('검색 중에는 4줄 제한 없이 결과를 모두 보여 주고, 지우면 다시 4줄', async () => {
  start();
  await waitFor(() => expect(cells()).toHaveLength(LIMIT));
  const box = screen.getByRole('combobox', { name: '챔피언·빌드 검색' });
  fireEvent.change(box, { target: { value: '챔프' } });
  await waitFor(() => expect(cells()).toHaveLength(30));
  expect(screen.queryByRole('button', { name: /모두 보기|접기/ })).toBeNull();
  fireEvent.change(box, { target: { value: '' } });
  await waitFor(() => expect(cells()).toHaveLength(LIMIT));
  expect(screen.getByRole('button', { name: '모두 보기' })).toBeDefined();
});

test('챔피언을 누르면 상대법 문서로 가는 흐름은 그대로', async () => {
  start();
  const first = await screen.findByRole('link', { name: '챔프00' });
  expect(first.getAttribute('href')).toBe('/champion/C00');
  fireEvent.click(first);
  await waitFor(() => expect(where()).toBe('/champion/C00'));
});
