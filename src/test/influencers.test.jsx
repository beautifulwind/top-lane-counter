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

test('기본(칩 꺼짐): 팔로워 많은 순(같으면 최신순) — 따로 표시 없음, 사진 없는 장인은 맨 뒤, 줄(닉네임·인증·빌드 N · 팔로워 N), 인원수 칩 7명, 쪽 번호 줄 없음', async () => {
  seven();
  start();
  expect(await screen.findByRole('heading', { level: 1, name: '장인' })).toBeDefined();
  expect(await screen.findByText('7명', { selector: '.count-badge' })).toBeDefined();
  // 서버(followers): 비이(3, 11-20) 에이(3, 11-01) 지이(3, 활동 없음) 씨이(2) 디이(1) Foxy·이이(0) → 사진 있는 이이가 맨 앞, 나머지는 서버 순서 그대로
  await waitFor(() => expect(names()).toEqual(['이이', '비이', '에이', '지이', '씨이', '디이', 'Foxy']));
  expect(screen.queryByText(/팔로워 순|팔로워 많은 순/)).toBeNull(); // 기본 정렬은 화면에 표시하지 않는다
  const rows = within(screen.getByRole('list', { name: '장인 목록' })).getAllByRole('listitem');
  expect(rows[0].textContent).toContain('빌드 0 · 팔로워 0'); // 빌드·팔로워 0도 표시
  expect(rows[1].textContent).toContain('인증');
  expect(rows[1].textContent).toContain('빌드 2 · 팔로워 3');
  expect(within(rows[1]).getByRole('link', { name: /비이/ }).getAttribute('href')).toBe('/u/i-b');
  expect(rows[1].querySelector('.inf-row-initial').textContent).toBe('비'); // 사진 없으면 닉네임 첫 글자 원
  expect(screen.queryByRole('navigation', { name: '쪽 이동' })).toBeNull(); // 한 쪽(10명 이하)이면 쪽 번호 줄 숨김
  // 한 번에 50명까지 받아 웹에서 나눈다 (쪽마다 요청하지 않음)
  expect(fakeState.directoryCalls).toEqual([{ p_query: '', p_sort: 'followers', p_page: 1, p_size: 50 }]);
});

test('「최신순」 칩: 하나뿐인 토글(꺼짐 aria-pressed=false) — 켜면 recent로 새로 받아 ?sort=recent·1쪽·사진 없는 장인 맨 뒤, 끄면 followers로 돌아오고 주소에서 sort가 사라진다', async () => {
  seven();
  start();
  await screen.findByText('7명');
  expect(screen.getAllByRole('button', { name: '최신순' })).toHaveLength(1);
  expect(screen.queryByRole('button', { name: /팔로워/ })).toBeNull();
  const chip = screen.getByRole('button', { name: '최신순' });
  expect(chip.getAttribute('aria-pressed')).toBe('false');
  expect(chip.querySelector('svg')).not.toBeNull(); // 시계 아이콘
  fireEvent.click(chip);
  // 서버(recent): 씨이(11-22) 비이(11-20) 디이(11-10) 에이(11-01) 지이 Foxy 이이 → 이이가 맨 앞
  await waitFor(() => expect(names()).toEqual(['이이', '씨이', '비이', '디이', '에이', '지이', 'Foxy']));
  expect(where()).toBe('/influencers?sort=recent');
  expect(screen.getByRole('button', { name: '최신순' }).getAttribute('aria-pressed')).toBe('true');
  expect(screen.getByRole('button', { name: '최신순' })).toHaveClass('on');
  expect(fakeState.directoryCalls.at(-1)).toEqual({ p_query: '', p_sort: 'recent', p_page: 1, p_size: 50 });
  fireEvent.click(screen.getByRole('button', { name: '최신순' }));
  await waitFor(() => expect(names()).toEqual(['이이', '비이', '에이', '지이', '씨이', '디이', 'Foxy']));
  expect(where()).toBe('/influencers');
  expect(screen.getByRole('button', { name: '최신순' }).getAttribute('aria-pressed')).toBe('false');
  expect(fakeState.directoryCalls.at(-1).p_sort).toBe('followers');
});

test('주소의 ?sort=: recent만 켜짐, 그 밖의 값·잘못된 값은 followers(꺼짐)로 오류 없이 — 칩을 바꾸면 1쪽으로 돌아가고 검색어는 유지', async () => {
  seven();
  start('/influencers?sort=recent&q=이이');
  await waitFor(() => expect(names()).toEqual(['이이']));
  expect(screen.getByRole('button', { name: '최신순' }).getAttribute('aria-pressed')).toBe('true');
  expect(fakeState.directoryCalls.at(-1)).toEqual({ p_query: '이이', p_sort: 'recent', p_page: 1, p_size: 50 });
  cleanup();
  for (const bad of ['followers', 'nope', 'RECENT', '']) {
    start(`/influencers?sort=${bad}`);
    await screen.findByText('7명');
    expect(screen.getByRole('button', { name: '최신순' }).getAttribute('aria-pressed')).toBe('false');
    expect(fakeState.directoryCalls.at(-1).p_sort).toBe('followers');
    expect(screen.queryByRole('alert')).toBeNull();
    cleanup();
  }
  // 검색 중에 칩을 바꿔도 검색어 유지 / 칩을 바꾸면 1쪽으로
  for (let i = 1; i <= 11; i++) inf(`q-${i}`, `검색장${String(i).padStart(2, '0')}`);
  start('/influencers?q=검색장&page=2');
  await waitFor(() => expect(names()).toEqual(['검색장11']));
  fireEvent.click(screen.getByRole('button', { name: '최신순' }));
  await waitFor(() => expect(where()).toBe('/influencers?q=%EA%B2%80%EC%83%89%EC%9E%A5&sort=recent'));
  expect(screen.getByRole('searchbox', { name: '장인 닉네임' })).toHaveValue('검색장');
  await waitFor(() => expect(names()).toHaveLength(10));
  fireEvent.click(screen.getByRole('button', { name: '최신순' }));
  await waitFor(() => expect(where()).toBe('/influencers?q=%EA%B2%80%EC%83%89%EC%9E%A5'));
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

test('쪽 번호: 11명이면 2쪽(10명 + 1명) — 웹에서 나누므로 쪽을 넘겨도 새 요청 없음, 1쪽이면 주소에서 사라짐, 끝을 넘긴 주소는 끝 쪽으로', async () => {
  for (let i = 1; i <= 11; i++) { const id = `p-${String(i).padStart(2, '0')}`; inf(id, `장인${String(i).padStart(2, '0')}`); follow(20 - i, id); }
  start();
  await screen.findByText('11명');
  const nav = await screen.findByRole('navigation', { name: '쪽 이동' });
  expect(names()).toHaveLength(INFLUENCER_PAGE_SIZE);
  expect(names()[0]).toBe('장인01');
  fireEvent.click(within(nav).getByRole('button', { name: '2쪽' }));
  await waitFor(() => expect(names()).toEqual(['장인11']));
  expect(where()).toBe('/influencers?page=2');
  expect(fakeState.directoryCalls).toHaveLength(1); // 처음 한 번(50명까지)만 받았다
  fireEvent.click(within(screen.getByRole('navigation', { name: '쪽 이동' })).getByRole('button', { name: '1쪽' }));
  await waitFor(() => expect(names()).toHaveLength(10));
  expect(where()).toBe('/influencers');
  cleanup();
  start('/influencers?page=9');
  await waitFor(() => expect(where()).toBe('/influencers?page=2'));
  await waitFor(() => expect(names()).toEqual(['장인11']));
});

test('사진 없는 장인은 쪽을 가로질러 항상 맨 뒤: 사진 있는 장인이 2쪽에 있어도 1쪽 앞으로 오고, 각 묶음은 서버 순서 그대로', async () => {
  // 서버(최근 활동순 = 팔로워 순, 활동 없음): 장인01(19) … 장인12(8). 사진은 장인11·장인12만
  for (let i = 1; i <= 12; i++) {
    const id = `p-${String(i).padStart(2, '0')}`;
    inf(id, `장인${String(i).padStart(2, '0')}`, i >= 11 ? { photo_path: `u/${id}.jpg` } : {});
    follow(20 - i, id);
  }
  start();
  await screen.findByText('12명');
  await waitFor(() => expect(names()).toEqual(['장인11', '장인12', '장인01', '장인02', '장인03', '장인04', '장인05', '장인06', '장인07', '장인08']));
  fireEvent.click(within(await screen.findByRole('navigation', { name: '쪽 이동' })).getByRole('button', { name: '2쪽' }));
  await waitFor(() => expect(names()).toEqual(['장인09', '장인10']));
});

test('검색어가 있어도 같은 방식(50명까지 받아 웹에서 사진 순서·쪽 나누기), 차단한 장인은 빼고 쪽을 나눈다', async () => {
  inf('s-1', '검색가', { photo_path: null }); inf('s-2', '검색나', { photo_path: 'u/s2.jpg' }); inf('s-3', '검색다'); inf('s-x', '딴사람');
  follow(3, 's-1'); follow(2, 's-2'); follow(1, 's-3');
  start('/influencers?q=검색');
  await waitFor(() => expect(names()).toEqual(['검색나', '검색가', '검색다']));
  expect(fakeState.directoryCalls).toEqual([{ p_query: '검색', p_sort: 'followers', p_page: 1, p_size: 50 }]);
  cleanup();
  fakeLogin('u-me', { nickname: '나' });
  TABLES.user_blocks.push({ blocker_id: 'u-me', blocked_id: 's-2', blocked: { nickname: '검색나' } });
  start('/influencers?q=검색');
  await waitFor(() => expect(names()).toEqual(['검색가', '검색다']));
  expect(screen.getByText('2명', { selector: '.count-badge' })).toBeDefined();
});

test('장인이 50명을 넘으면 사진 순서를 못 맞추므로 서버 쪽 나누기로 되돌린다 (쪽마다 10명 요청, 화면 깨짐 없음)', async () => {
  for (let i = 1; i <= 51; i++) { const id = `p-${String(i).padStart(2, '0')}`; inf(id, `장인${String(i).padStart(2, '0')}`, i === 51 ? { photo_path: 'u/p51.jpg' } : {}); follow(100 - i, id); }
  start();
  await screen.findByText('51명');
  await waitFor(() => expect(names()).toHaveLength(10));
  expect(names()[0]).toBe('장인01'); // 사진 있는 장인51이 앞으로 오지 않는다 (서버 순서 그대로)
  expect(fakeState.directoryCalls).toEqual([
    { p_query: '', p_sort: 'followers', p_page: 1, p_size: 50 },
    { p_query: '', p_sort: 'followers', p_page: 1, p_size: INFLUENCER_PAGE_SIZE },
  ]);
  fireEvent.click(within(await screen.findByRole('navigation', { name: '쪽 이동' })).getByRole('button', { name: '6쪽' }));
  await waitFor(() => expect(names()).toEqual(['장인51']));
  expect(fakeState.directoryCalls.at(-1)).toEqual({ p_query: '', p_sort: 'followers', p_page: 6, p_size: INFLUENCER_PAGE_SIZE });
  expect(where()).toBe('/influencers?page=6');
  // 최신순 칩을 켜도 50명 초과면 서버 쪽 나누기(recent), 1쪽으로
  fireEvent.click(screen.getByRole('button', { name: '최신순' }));
  await waitFor(() => expect(fakeState.directoryCalls.at(-1)).toEqual({ p_query: '', p_sort: 'recent', p_page: 1, p_size: INFLUENCER_PAGE_SIZE }));
  expect(fakeState.directoryCalls.some((c) => c.p_sort === 'recent' && c.p_size === 50)).toBe(true);
  expect(where()).toBe('/influencers?sort=recent');
});

test('알약 검색창: 글자가 있을 때만 [지우기], 누르면 입력·주소의 q·page를 비우고 입력창으로 초점이 돌아온다 (16px·type=search·enterkeyhint=search)', async () => {
  for (let i = 1; i <= 11; i++) inf(`p-${i}`, `장인${String(i).padStart(2, '0')}`);
  start('/influencers?q=장인&page=2');
  const box = await screen.findByRole('searchbox', { name: '장인 닉네임' });
  expect(box).toHaveValue('장인');
  expect(box.getAttribute('type')).toBe('search');
  expect(box.getAttribute('enterkeyhint')).toBe('search');
  expect(box.getAttribute('maxlength')).toBe('20');
  expect(box.closest('.pill-search')).not.toBeNull();
  const clear = await screen.findByRole('button', { name: '지우기' });
  fireEvent.click(clear);
  expect(box).toHaveValue('');
  expect(document.activeElement).toBe(box);
  await waitFor(() => expect(where()).toBe('/influencers')); // q·page 모두 초기화
  expect(screen.queryByRole('button', { name: '지우기' })).toBeNull(); // 비면 사라짐
  await waitFor(() => expect(fakeState.directoryCalls.at(-1).p_query).toBe(''));
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
