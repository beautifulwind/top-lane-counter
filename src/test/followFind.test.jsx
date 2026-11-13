// 장인 팔로우 화면 3 앞부분 (050, SPEC 6-36): ☰ [장인찾기] 검색 칸 · 팔로우 모아보기 /following
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeBuild, fakeGuestLogin, fakeLogin, fakeState } from './fakeSupabase';
import { openMenu } from './menu';
import { NO_RESULT_TEXT } from '../components/InfluencerSearch';
import { NO_FOLLOW_TEXT } from '../pages/Following';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

function Where() { const l = useLocation(); return <output data-testid="where">{l.pathname}{l.search}</output>; }
const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /><Where /></MemoryRouter>);
const where = () => screen.getByTestId('where').textContent;

const inf = (id, nickname, influencer = 'creator') => TABLES.profiles.push({ id, nickname, role: 'user', level: 3, main_title: null, influencer, email: `${id}@x.com` });
const follow = (who, whom, at = '2026-11-10T00:00:00Z') => TABLES.influencer_follows.push({ follower_id: who, influencer_id: whom, created_at: at });

async function openSearch() {
  const menu = await openMenu();
  const btn = menu.getByRole('button', { name: '장인찾기' });
  fireEvent.click(btn);
  return { menu, btn, box: await menu.findByRole('searchbox', { name: '장인 닉네임' }) };
}

// ---------------- ☰ [장인찾기] ----------------

test('[장인찾기]: 알림과 탑신병자 커뮤니티 사이, 누르면 아래에 검색 칸 / 다시 누르거나 바깥을 누르면 접힘', async () => {
  fakeLogin('u-1', { nickname: '팬' });
  start('/');
  const { menu, btn, box } = await openSearch();
  const names = [...document.querySelectorAll('.menu-list > li > .menu-item')].map((el) => el.textContent.trim());
  expect(names.indexOf('장인찾기')).toBe(names.indexOf('알림') + 1);
  expect(names.indexOf('탑신병자 커뮤니티')).toBe(names.indexOf('장인찾기') + 1);
  expect(btn.getAttribute('aria-expanded')).toBe('true');
  expect(document.activeElement).toBe(box); // 펼치면 바로 입력
  expect(menu.getByText('장인 닉네임을 한 글자 이상 넣어 주세요.')).toBeTruthy();
  fireEvent.click(btn);
  expect(menu.queryByRole('searchbox')).toBeNull();
  expect(btn.getAttribute('aria-expanded')).toBe('false');
  fireEvent.click(btn);
  await menu.findByRole('searchbox');
  fireEvent.pointerDown(document.querySelector('.menu-account')); // 메뉴 안 다른 곳
  await waitFor(() => expect(menu.queryByRole('searchbox')).toBeNull());
  expect(screen.getByRole('dialog', { name: '메뉴' })).toBeTruthy(); // 메뉴는 그대로
});

test('로그인 전에도 검색: 닉네임·유형·팔로워 수, 장인이 아닌 회원·개인정보는 없음, 누르면 장인 페이지로 가며 메뉴가 닫힘', async () => {
  inf('u-fk', 'Faker', 'pro');
  inf('u-fm', 'Fakeman');
  TABLES.profiles.push({ id: 'u-plain', nickname: 'Fakeplain', role: 'user', level: 1, main_title: null });
  follow('u-a', 'u-fk');
  follow('u-b', 'u-fk');
  start('/');
  const { box } = await openSearch();
  fireEvent.change(box, { target: { value: 'fak' } });
  const list = await waitFor(() => {
    const ul = document.querySelector('.inf-search-list');
    expect(ul).not.toBeNull();
    return ul;
  });
  const rows = [...list.querySelectorAll('.inf-search-row')];
  expect(rows.map((r) => r.querySelector('.user-nick').textContent)).toEqual(['Faker', 'Fakeman']); // 팔로워 많은 순
  expect(rows[0].textContent).toContain('프로게이머 · 팔로워 2명');
  expect(rows[0].querySelector('.inf-tag').textContent).toBe('장인');
  expect(document.body.textContent).not.toContain('Fakeplain');
  expect(document.body.textContent).not.toContain('@x.com');
  fireEvent.click(rows[0]);
  await waitFor(() => expect(where()).toBe('/u/u-fk'));
  expect(screen.queryByRole('dialog', { name: '메뉴' })).toBeNull();
  expect(await screen.findByRole('heading', { level: 1 })).toHaveProperty('textContent', expect.stringContaining('Faker'));
});

test('검색: 입력을 멈춘 뒤 한 번만 요청, 빈칸만이면 요청하지 않음, 결과가 없으면 쉬운 말', async () => {
  inf('u-fk', 'Faker', 'pro');
  start('/');
  const { menu, box } = await openSearch();
  fireEvent.change(box, { target: { value: '   ' } });
  fireEvent.change(box, { target: { value: 'f' } });
  fireEvent.change(box, { target: { value: 'fa' } });
  fireEvent.change(box, { target: { value: 'fak' } });
  await waitFor(() => expect(document.querySelector('.inf-search-list')).not.toBeNull());
  expect(fakeState.searchCalls).toEqual(['fak']);
  fireEvent.change(box, { target: { value: '없는장인' } });
  expect(await menu.findByText(NO_RESULT_TEXT)).toBeTruthy();
  fireEvent.change(box, { target: { value: '  ' } });
  expect(await menu.findByText('장인 닉네임을 한 글자 이상 넣어 주세요.')).toBeTruthy();
  expect(fakeState.searchCalls).toEqual(['fak', '없는장인']);
  expect(box.getAttribute('maxlength')).toBe('20');
});

test('검색: 20개씩 [더보기]', async () => {
  for (let i = 1; i <= 25; i += 1) inf(`u-s${i}`, `검색장${String(i).padStart(2, '0')}`);
  start('/');
  const { menu, box } = await openSearch();
  fireEvent.change(box, { target: { value: '검색장' } });
  await waitFor(() => expect(document.querySelectorAll('.inf-search-row')).toHaveLength(20));
  fireEvent.click(menu.getByRole('button', { name: '더보기 (5명 남음)' }));
  await waitFor(() => expect(document.querySelectorAll('.inf-search-row')).toHaveLength(25));
  expect(menu.queryByRole('button', { name: /더보기/ })).toBeNull();
});

test('검색 칸의 [내가 팔로우한 장인의 빌드 보기] → /following (메뉴 닫힘)', async () => {
  start('/');
  const { menu } = await openSearch();
  fireEvent.click(menu.getByRole('link', { name: '내가 팔로우한 장인의 빌드 보기' }));
  await waitFor(() => expect(where()).toBe('/following'));
  expect(screen.queryByRole('dialog', { name: '메뉴' })).toBeNull();
});

// ---------------- 팔로우 모아보기 /following ----------------

test('모아보기: 로그인 전에는 로그인 안내만', async () => {
  start('/following');
  const note = await screen.findByText(/로그인하면 팔로우한 장인의 빌드를 모아 볼 수 있습니다/);
  expect(within(note).getByRole('link', { name: '로그인' }).getAttribute('href')).toBe('/login');
  expect(screen.queryByRole('tab')).toBeNull();
  expect(document.title).toBe('팔로우한 장인의 빌드 - 탑신병자');
});

test('모아보기: 팔로우한 장인이 없으면 안내 (빌드·장인 탭 모두)', async () => {
  fakeGuestLogin('u-g', { nickname: '손님' });
  start('/following');
  expect(await screen.findByText(NO_FOLLOW_TEXT)).toBeTruthy();
  fireEvent.click(screen.getByRole('tab', { name: '팔로우한 장인' }));
  expect(await screen.findByText(NO_FOLLOW_TEXT)).toBeTruthy();
  expect(where()).toBe('/following?tab=list');
});

test('모아보기 빌드: 팔로우한 장인들의 공개 빌드만, 최근 수정순, 카드에 장인 닉네임·상대법 → 그 빌드, 20개씩 [더보기]', async () => {
  inf('u-102', '탑고수');
  inf('u-103', '칭호없음', 'pro');
  inf('u-zz', '안팔로우');
  TABLES.builds.find((b) => b.id === 102).updated_at = '2026-11-20T00:00:00Z';
  for (let i = 0; i < 22; i += 1) {
    TABLES.builds.push(fakeBuild(300 + i, { nickname: '칭호없음' }, { author_id: 'u-103', name: `묶음${i}`, updated_at: `2026-10-${String(i + 1).padStart(2, '0')}T00:00:00Z` }));
  }
  TABLES.builds.push(fakeBuild(400, { nickname: '칭호없음' }, { author_id: 'u-103', status: 'hidden', name: '숨긴것' }));
  TABLES.builds.push(fakeBuild(401, { nickname: '안팔로우' }, { author_id: 'u-zz', name: '남의것' }));
  fakeLogin('u-fan', { nickname: '팬' });
  follow('u-fan', 'u-102');
  follow('u-fan', 'u-103');
  start('/following');
  const sec = await screen.findByRole('region', { name: '팔로우한 장인의 빌드' });
  const cards = () => [...sec.querySelectorAll('.inf-build-card')];
  expect(cards()).toHaveLength(20);
  const top = cards()[0];
  expect(top.querySelector('.inf-build-author').textContent).toContain('탑고수');
  expect(top.querySelector('.inf-build-author .inf-tag').textContent).toBe('장인');
  expect(top.querySelector('.inf-build-matchup').textContent).toBe('퀸으로 다리우스');
  expect(top.querySelectorAll('img.inf-champ')).toHaveLength(2);
  expect(top.getAttribute('href')).toBe('/champion/Darius/counter/Quinn?build=102');
  expect(cards()[1].querySelector('.inf-build-name').textContent).toBe('빌드 3'); // 103: 11월 3일 수정
  fireEvent.click(within(sec).getByRole('button', { name: '더보기 (4개 남음)' }));
  await waitFor(() => expect(cards()).toHaveLength(24)); // 102 + 103 + 묶음 22개
  expect(sec.textContent).not.toContain('숨긴것');
  expect(sec.textContent).not.toContain('남의것');
  fireEvent.click(top);
  expect(await screen.findByText(/퀸으로 다리우스 이기는 법/)).toBeTruthy();
});

test('모아보기 팔로우한 장인: 목록에서 [팔로우중]을 누르면 취소, 다시 누르면 팔로우', async () => {
  inf('u-102', '탑고수');
  inf('u-103', '칭호없음', 'pro');
  fakeLogin('u-fan', { nickname: '팬' });
  follow('u-fan', 'u-102', '2026-11-01T00:00:00Z');
  follow('u-fan', 'u-103', '2026-11-05T00:00:00Z');
  follow('u-other', 'u-103');
  start('/following?tab=list');
  const sec = await screen.findByRole('region', { name: '내가 팔로우한 장인' });
  const rows = [...sec.querySelectorAll('.following-row')];
  expect(rows.map((r) => r.querySelector('.user-nick').textContent)).toEqual(['칭호없음', '탑고수']); // 최근 팔로우 순
  expect(rows[0].textContent).toContain('프로게이머 · 팔로워 2명 · 2026-11-05 팔로우');
  expect(within(rows[0]).getByRole('link', { name: /칭호없음/ }).getAttribute('href')).toBe('/u/u-103');
  fireEvent.click(within(rows[0]).getByRole('button', { name: '칭호없음 팔로우 취소' }));
  const again = await within(rows[0]).findByRole('button', { name: '칭호없음 팔로우' });
  expect(rows[0].textContent).toContain('팔로워 1명');
  expect(TABLES.influencer_follows.some((f) => f.follower_id === 'u-fan' && f.influencer_id === 'u-103')).toBe(false);
  fireEvent.click(again);
  expect(await within(rows[0]).findByRole('button', { name: '칭호없음 팔로우 취소' })).toBeTruthy();
  expect(TABLES.influencer_follows.some((f) => f.follower_id === 'u-fan' && f.influencer_id === 'u-103')).toBe(true);
});
