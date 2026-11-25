// 장인 팔로우 화면 3 앞부분 (050, SPEC 6-36): 장인 찾기 검색 칸(6-82부터 상단 바 돋보기) · 팔로우 모아보기 /following
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { AppRoutes } from '../App';
import TopSearch from '../components/TopSearch';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeBuild, fakeLogin, fakeState } from './fakeSupabase';
import { NO_RESULT_TEXT } from '../components/InfluencerSearch';
import { NO_FOLLOW_TEXT } from '../pages/Following';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

function Where() { const l = useLocation(); return <output data-testid="where">{l.pathname}{l.search}</output>; }
const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /><Where /></MemoryRouter>);
// 1-B2: 헤더 돋보기는 없앴다(Layout에서 TopSearch 제거). InfluencerSearch 검색 동작은 그대로 시험하려고 TopSearch를 따로 붙여 연다.
const startWithSearch = (path) => render(<MemoryRouter initialEntries={[path]}><TopSearch /><AppRoutes /><Where /></MemoryRouter>);
const where = () => screen.getByTestId('where').textContent;

const inf = (id, nickname, influencer = 'creator') => TABLES.profiles.push({ id, nickname, role: 'user', level: 3, main_title: null, influencer, email: `${id}@x.com` });
const follow = (who, whom, at = '2026-11-10T00:00:00Z') => TABLES.influencer_follows.push({ follower_id: who, influencer_id: whom, created_at: at });

/** 상단 바 돋보기 [장인 찾기]를 눌러 검색 칸을 연다 (6-82) */
async function openSearch() {
  const btn = await screen.findByRole('button', { name: '장인 찾기' });
  fireEvent.click(btn);
  const panel = within(await screen.findByRole('dialog', { name: '장인 찾기' }));
  return { menu: panel, btn, box: await panel.findByRole('searchbox', { name: '장인 닉네임' }) };
}

// ---------------- 상단 바 돋보기 [장인 찾기] (050 → 6-82) ----------------

test('[장인 찾기] 컴포넌트(TopSearch): 누르면 아래에 검색 칸 / 다시 누르기·Esc·[X]·바깥을 누르면 닫히고 초점은 돋보기로 — 사이트 헤더에는 돋보기가 없고 ☰ 메뉴에도 [장인 찾기]가 없다 (1-B2)', async () => {
  fakeLogin('u-1', { nickname: '팬' });
  startWithSearch('/');
  const { menu, btn, box } = await openSearch();
  expect(btn.getAttribute('aria-expanded')).toBe('true');
  expect(document.activeElement).toBe(box); // 열면 바로 입력
  expect(menu.getByText('장인 닉네임을 한 글자 이상 넣어 주세요.')).toBeTruthy();
  fireEvent.keyDown(box, { key: 'Escape' });
  expect(screen.queryByRole('dialog', { name: '장인 찾기' })).toBeNull();
  expect(btn.getAttribute('aria-expanded')).toBe('false');
  expect(document.activeElement).toBe(btn);
  await openSearch();
  fireEvent.click(screen.getByRole('button', { name: '장인 찾기 닫기' }));
  expect(screen.queryByRole('dialog', { name: '장인 찾기' })).toBeNull();
  await openSearch();
  fireEvent.click(document.querySelector('.top-search-backdrop'));
  expect(screen.queryByRole('dialog', { name: '장인 찾기' })).toBeNull();
  // 사이트 헤더(상단 바)에는 돋보기가 없다 — 위 TopSearch는 시험용으로 따로 붙인 것. ☰ 메뉴에는 [장인 보기]·[내 목록 보기]만
  expect([...document.querySelector('.topbar').querySelectorAll('button')].map((b) => b.getAttribute('aria-label'))).toEqual(['메뉴 열기']);
  fireEvent.click(screen.getByRole('button', { name: '메뉴 열기' }));
  const names = [...document.querySelectorAll('.menu-list > li > .menu-item')].map((el) => el.textContent.trim());
  expect(names).toContain('내 목록 보기');
  expect(names).toContain('장인 보기');
  expect(names.some((n) => n.includes('장인찾기') || n.includes('장인 찾기'))).toBe(false);
});

test('로그인 전에도 검색: 닉네임·유형·팔로워 수, 장인이 아닌 회원·개인정보는 없음, 누르면 장인 페이지로 가며 검색 칸이 닫힘', async () => {
  inf('u-fk', 'Faker', 'pro');
  inf('u-fm', 'Fakeman');
  TABLES.profiles.push({ id: 'u-plain', nickname: 'Fakeplain', role: 'user', level: 1, main_title: null });
  follow('u-a', 'u-fk');
  follow('u-b', 'u-fk');
  startWithSearch('/');
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
  expect(screen.queryByRole('dialog', { name: '장인 찾기' })).toBeNull();
  expect(await screen.findByRole('heading', { level: 1 })).toHaveProperty('textContent', expect.stringContaining('Faker'));
});

test('검색: 입력을 멈춘 뒤 한 번만 요청, 빈칸만이면 요청하지 않음, 결과가 없으면 쉬운 말', async () => {
  inf('u-fk', 'Faker', 'pro');
  startWithSearch('/');
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
  startWithSearch('/');
  const { menu, box } = await openSearch();
  fireEvent.change(box, { target: { value: '검색장' } });
  await waitFor(() => expect(document.querySelectorAll('.inf-search-row')).toHaveLength(20));
  fireEvent.click(menu.getByRole('button', { name: '더보기 (5명 남음)' }));
  await waitFor(() => expect(document.querySelectorAll('.inf-search-row')).toHaveLength(25));
  expect(menu.queryByRole('button', { name: /더보기/ })).toBeNull();
});

test('검색 칸의 [내가 팔로우한 장인의 빌드 보기] → /following (검색 칸 닫힘)', async () => {
  startWithSearch('/');
  const { menu } = await openSearch();
  fireEvent.click(menu.getByRole('link', { name: '내가 팔로우한 장인의 빌드 보기' }));
  await waitFor(() => expect(where()).toBe('/following'));
  expect(screen.queryByRole('dialog', { name: '장인 찾기' })).toBeNull();
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
  fakeLogin('u-m', { nickname: '회원' }); // 063: 비회원은 장인 탭에서 안내만 (followPrivacy.test.jsx)
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
  expect(top.closest('li')).toHaveClass('build-card', 'is-influencer'); // 6-87: 왼쪽 주황선 카드 (장인의 빌드만 모은 목록)
  expect(sec.querySelector('ul')).toHaveClass('build-cards');
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
  const rows = [...sec.querySelectorAll('.inf-row')]; // 6-115: 장인 목록과 같은 카드
  expect(rows.map((r) => r.querySelector('.user-nick').textContent)).toEqual(['칭호없음', '탑고수']); // 최근 팔로우 순
  expect(rows[0].textContent).toMatch(/프로게이머 · 빌드 \d+ · 팔로워 2/);
  expect(rows[0].textContent).not.toContain('2026-11-05'); // 063: 팔로우한 날 없음
  expect(within(rows[0]).getByRole('link', { name: /칭호없음/ }).getAttribute('href')).toBe('/u/u-103');
  fireEvent.click(within(rows[0]).getByRole('button', { name: '칭호없음 팔로우 취소' }));
  const again = await within(rows[0]).findByRole('button', { name: '칭호없음 팔로우' });
  expect(rows[0].querySelector('.muted').textContent).toMatch(/팔로워 1$/);
  expect(TABLES.influencer_follows.some((f) => f.follower_id === 'u-fan' && f.influencer_id === 'u-103')).toBe(false);
  fireEvent.click(again);
  expect(await within(rows[0]).findByRole('button', { name: '칭호없음 팔로우 취소' })).toBeTruthy();
  expect(TABLES.influencer_follows.some((f) => f.follower_id === 'u-fan' && f.influencer_id === 'u-103')).toBe(true);
});
