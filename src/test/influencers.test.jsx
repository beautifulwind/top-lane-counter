// 1.3 패치 1-B1 (SPEC 6-93): 전체 장인 목록 /influencers — 인원수 칩·장인 줄·정렬 칩과 동률·검색·쪽 번호 표시/숨김·주소(?sort ?q ?page)·
// 팔로우 버튼이 줄 이동을 막지 않음·본인 줄·로그인 전·빈 상태·☰ [장인 보기]
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { AppRoutes } from '../App';
import { INFLUENCER_PAGE_SIZE } from '../lib/influencerList';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeBuild, fakeLogin, fakeState } from './fakeSupabase';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

function Where() { const l = useLocation(); return <output data-testid="where">{l.pathname}{l.search}</output>; }
const start = (path = '/influencers') => render(<MemoryRouter initialEntries={[path]}><AppRoutes /><Where /></MemoryRouter>);
const where = () => screen.getByTestId('where').textContent;

const inf = (id, nickname, extra = {}) => TABLES.profiles.push({ id, nickname, role: 'user', level: 3, main_title: null, influencer: 'creator', ...extra });
const follow = (n, whom) => { for (let i = 0; i < n; i++) TABLES.influencer_follows.push({ follower_id: `fan-${whom}-${i}`, influencer_id: whom, created_at: '2026-11-10T00:00:00Z' }); };
let bid = 300;
const publicBuild = (author, updated) => {
  const id = bid++;
  TABLES.builds.push(fakeBuild(id, { nickname: 'x', level: 1, main_title: null }, { author_id: author, updated_at: updated, created_at: updated }));
};
const names = () => within(screen.getByRole('list', { name: '장인 목록' })).getAllByRole('listitem').map((li) => li.querySelector('.user-nick').textContent);

/** 장인 7명: 팔로워 3(A·B 같음) / 2(C) / 1(D) / 0(E·F) + 팔로워 3인 G. 최근 활동은 B가 가장 새롭고 A는 오래됨 */
function seven() {
  inf('i-a', '에이'); inf('i-b', '비이'); inf('i-c', '씨이'); inf('i-d', '디이'); inf('i-e', '이이', { photo_path: 'x/photo.jpg' }); inf('i-f', 'Foxy'); inf('i-g', '지이');
  follow(3, 'i-a'); follow(3, 'i-b'); follow(2, 'i-c'); follow(1, 'i-d'); follow(3, 'i-g');
  publicBuild('i-a', '2026-11-01T00:00:00Z'); publicBuild('i-b', '2026-11-20T00:00:00Z'); publicBuild('i-b', '2026-11-05T00:00:00Z');
  publicBuild('i-c', '2026-11-22T00:00:00Z'); publicBuild('i-d', '2026-11-10T00:00:00Z');
  // F·E·G: 빌드 없음 → 최근 활동 null
}

test('기본: 인원수 칩 7명, 줄(닉네임·인증·빌드 N · 팔로워 N), 팔로워 많은 순 — 같으면 최근 활동이 새로운 순, 빌드·팔로워 0도 표시, 쪽 번호 줄 없음', async () => {
  seven();
  start();
  expect(await screen.findByRole('heading', { level: 1, name: '장인' })).toBeDefined();
  expect(await screen.findByText('7명', { selector: '.count-badge' })).toBeDefined();
  // 팔로워 3: B(최근 11-20) > A(11-01) > G(활동 없음), 2: C, 1: D, 0: 이이·Foxy (닉네임 순)
  await waitFor(() => expect(names()).toEqual(['비이', '에이', '지이', '씨이', '디이', 'Foxy', '이이']));
  const rows = within(screen.getByRole('list', { name: '장인 목록' })).getAllByRole('listitem');
  expect(rows[0].textContent).toContain('인증');
  expect(rows[0].textContent).toContain('빌드 2 · 팔로워 3');
  expect(rows[2].textContent).toContain('빌드 0 · 팔로워 3'); // G: 빌드 없어도 표시
  expect(rows[5].textContent).toContain('빌드 0 · 팔로워 0'); // 팔로워 0도 표시
  expect(within(rows[0]).getByRole('link', { name: /비이/ }).getAttribute('href')).toBe('/u/i-b');
  expect(rows[0].querySelector('.inf-row-initial').textContent).toBe('비'); // 사진 없으면 닉네임 첫 글자 원
  expect(screen.queryByRole('navigation', { name: '쪽 이동' })).toBeNull(); // 한 쪽(10명 이하)이면 쪽 번호 줄 숨김
  expect(fakeState.directoryCalls.at(-1)).toEqual({ p_query: '', p_sort: 'followers', p_page: 1, p_size: INFLUENCER_PAGE_SIZE });
});

test('정렬 칩: 최신순은 최근 활동이 새로운 순(없으면 맨 뒤, 같으면 팔로워 많은 순), 주소 ?sort=recent, 팔로워 칩으로 돌아가면 주소에서 사라짐', async () => {
  seven();
  start();
  await screen.findByText('7명');
  expect(screen.getByRole('button', { name: '팔로워 많은 순' })).toHaveAttribute('aria-pressed', 'true');
  fireEvent.click(screen.getByRole('button', { name: '최신순' }));
  await waitFor(() => expect(names()).toEqual(['씨이', '비이', '디이', '에이', '지이', 'Foxy', '이이'])); // 활동 없는 G·E·F는 팔로워 3 → 0, 0은 닉네임 순
  expect(where()).toBe('/influencers?sort=recent');
  expect(screen.getByRole('button', { name: '최신순' })).toHaveAttribute('aria-pressed', 'true');
  expect(fakeState.directoryCalls.at(-1).p_sort).toBe('recent');
  fireEvent.click(screen.getByRole('button', { name: '팔로워 많은 순' }));
  await waitFor(() => expect(names()[0]).toBe('비이'));
  expect(where()).toBe('/influencers');
});

test('주소에서 시작: ?sort=recent·?q= 가 그대로 적용된다 (새로고침해도 유지), 모르는 정렬은 기본', async () => {
  seven();
  start('/influencers?sort=recent&q=이이');
  await waitFor(() => expect(names()).toEqual(['이이']));
  expect(screen.getByRole('searchbox', { name: '장인 닉네임' })).toHaveValue('이이');
  expect(screen.getByRole('button', { name: '최신순' })).toHaveAttribute('aria-pressed', 'true');
  expect(fakeState.directoryCalls.at(-1)).toMatchObject({ p_query: '이이', p_sort: 'recent' });
  cleanup();
  start('/influencers?sort=nope');
  await screen.findByText('7명');
  expect(screen.getByRole('button', { name: '팔로워 많은 순' })).toHaveAttribute('aria-pressed', 'true');
});

test('검색: 입력을 멈추면 주소 ?q=에 올라가 걸러진다, 20자 제한, 공백뿐이면 빈 검색, 결과가 없으면 한 줄 안내', async () => {
  seven();
  start();
  await screen.findByText('7명');
  const box = screen.getByRole('searchbox', { name: '장인 닉네임' });
  expect(box).toHaveAttribute('maxlength', '20');
  fireEvent.change(box, { target: { value: 'fox' } });
  await waitFor(() => expect(names()).toEqual(['Foxy']));
  expect(where()).toBe('/influencers?q=fox');
  expect(screen.getByText('1명', { selector: '.count-badge' })).toBeDefined();
  expect(fakeState.directoryCalls.at(-1).p_query).toBe('fox');
  fireEvent.change(box, { target: { value: '없는사람' } });
  const none = await screen.findByText('「없는사람」에 맞는 장인이 없습니다.');
  expect(none).toHaveClass('none-line');
  expect(screen.queryByRole('list', { name: '장인 목록' })).toBeNull();
  fireEvent.change(box, { target: { value: '   ' } }); // 공백뿐 = 빈 검색(전체)
  await waitFor(() => expect(names()).toHaveLength(7));
  expect(where()).toBe('/influencers');
  expect(fakeState.directoryCalls.every((c) => c.p_query === c.p_query.trim())).toBe(true);
});

test('쪽 번호: 11명이면 2쪽(10명 + 1명), 번호를 누르면 ?page=2·그 쪽만 요청, 1쪽이면 주소에서 사라짐, 끝을 넘긴 주소는 끝 쪽으로', async () => {
  for (let i = 1; i <= 11; i++) { const id = `p-${String(i).padStart(2, '0')}`; inf(id, `장인${String(i).padStart(2, '0')}`); follow(20 - i, id); }
  start();
  await screen.findByText('11명');
  const nav = await screen.findByRole('navigation', { name: '쪽 이동' });
  expect(names()).toHaveLength(INFLUENCER_PAGE_SIZE);
  expect(names()[0]).toBe('장인01');
  fireEvent.click(within(nav).getByRole('button', { name: '2쪽' }));
  await waitFor(() => expect(names()).toEqual(['장인11']));
  expect(where()).toBe('/influencers?page=2');
  expect(fakeState.directoryCalls.at(-1).p_page).toBe(2);
  fireEvent.click(within(screen.getByRole('navigation', { name: '쪽 이동' })).getByRole('button', { name: '1쪽' }));
  await waitFor(() => expect(names()).toHaveLength(10));
  expect(where()).toBe('/influencers');
  cleanup();
  start('/influencers?page=9');
  await waitFor(() => expect(where()).toBe('/influencers?page=2'));
  await waitFor(() => expect(names()).toEqual(['장인11']));
});

test('팔로우 버튼: 눌러도 줄 이동이 없고(팔로우중으로 바뀜), 팔로우 상태는 한 번에 받고, 본인 줄에는 버튼이 없다. 줄을 누르면 장인 페이지로', async () => {
  seven();
  inf('fan', '팬', { influencer: null });
  follow(0, 'i-a');
  TABLES.influencer_follows.push({ follower_id: 'fan', influencer_id: 'i-c', created_at: '2026-11-11T00:00:00Z' });
  fakeLogin('fan', { nickname: '팬' });
  start();
  await screen.findByText('7명');
  await waitFor(() => expect(fakeState.followStatusCalls).toHaveLength(1)); // 줄마다 따로가 아니라 한 번
  expect(fakeState.followStatusCalls[0]).toHaveLength(7);
  expect(await screen.findByRole('button', { name: '씨이 팔로우 취소' })).toHaveAttribute('aria-pressed', 'true'); // 이미 팔로우 중
  fireEvent.click(screen.getByRole('button', { name: '에이 팔로우' }));
  expect(await screen.findByRole('button', { name: '에이 팔로우 취소' })).toBeDefined();
  expect(where()).toBe('/influencers'); // 이동하지 않음
  expect(fakeState.rpcCalls.map((c) => c.name)).toContain('follow_influencer');
  // 팔로워 수가 서버가 돌려준 값으로 바뀐다 (3 → 4)
  const a = screen.getByRole('link', { name: /에이/ }).closest('li');
  expect(a.textContent).toContain('팔로워 4');
  fireEvent.click(within(a).getByRole('link', { name: /에이/ }));
  await waitFor(() => expect(where()).toBe('/u/i-a'));
});

test('본인이 장인이면 내 줄에는 팔로우 버튼이 없다', async () => {
  seven();
  fakeLogin('i-a', { nickname: '에이', influencer: 'creator' });
  start();
  await screen.findByText('7명');
  const mine = (await screen.findByRole('link', { name: /에이/ })).closest('li');
  expect(within(mine).queryByRole('button')).toBeNull();
  expect(within(screen.getByRole('link', { name: /비이/ }).closest('li')).getByRole('button', { name: '비이 팔로우' })).toBeDefined();
});

test('로그인 전: 목록은 보이고, 팔로우를 누르면 기존 로그인 안내가 나오며 이동하지 않는다 (팔로우 상태는 요청하지 않음)', async () => {
  seven();
  start();
  await screen.findByText('7명');
  fireEvent.click(await screen.findByRole('button', { name: '비이 팔로우' }));
  expect(await screen.findByText(/로그인하면 팔로우할 수 있습니다/)).toBeDefined();
  expect(where()).toBe('/influencers');
  expect(fakeState.followStatusCalls).toHaveLength(0);
  expect(fakeState.rpcCalls.map((c) => c.name)).not.toContain('follow_influencer');
});

test('장인이 0명이면 점선 상자 대신 한 줄 안내, 인원수 칩은 0명', async () => {
  start();
  const line = await screen.findByText('아직 인증된 장인이 없습니다.');
  expect(line).toHaveClass('none-line');
  expect(document.querySelector('.empty')).toBeNull();
  expect(screen.getByText('0명', { selector: '.count-badge' })).toBeDefined();
  expect(screen.queryByRole('navigation', { name: '쪽 이동' })).toBeNull();
});

test('☰ 메뉴에 「장인 보기」(내 목록 보기 근처) → /influencers, 로그인 전에도 보인다. 헤더 돋보기는 1-B2에서 없앴다', async () => {
  start('/');
  fireEvent.click(await screen.findByRole('button', { name: '메뉴 열기' }));
  await screen.findByRole('link', { name: '장인 보기' });
  const items = [...document.querySelectorAll('.menu-list > li > .menu-item')].map((el) => el.textContent.trim());
  expect(items).toContain('장인 보기');
  expect(Math.abs(items.indexOf('장인 보기') - items.indexOf('내 목록 보기'))).toBeLessThanOrEqual(1);
  fireEvent.click(within(document.querySelector('.menu-list')).getByRole('link', { name: '장인 보기' }));
  await waitFor(() => expect(where()).toBe('/influencers'));
  expect(screen.queryByRole('button', { name: '장인 찾기' })).toBeNull(); // 1-B2: 헤더 돋보기 없음
});
