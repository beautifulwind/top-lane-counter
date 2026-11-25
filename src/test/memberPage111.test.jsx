// 1.3 패치 3-C·3-D (SPEC 6-111): 일반 사용자 개인 페이지 /u/:id (075 member_page) · 마이페이지 진행 안내 · 칭호 알림 → 칭호판
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import { publicBuildCount } from '../components/MyProgress';
import { resetTitleInfo } from '../lib/titles';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeLogin, fakeState } from './fakeSupabase';

beforeEach(() => {
  resetTitleInfo();
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); delete Element.prototype.scrollIntoView; });

const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /></MemoryRouter>);
const ME = 'u-old';
const main = () => screen.getByRole('main');

/** ME가 쓴 공개 빌드 n개를 더한다 (기준 빌드를 복사) */
function addBuilds(n, extra = {}) {
  const base = TABLES.builds.find((b) => b.id === 102);
  for (let i = 0; i < n; i++) {
    const id = 3000 + TABLES.builds.length;
    TABLES.builds.push({
      ...structuredClone(base), id, author_id: ME, author: { nickname: '기존유저', level: 1, main_title: null }, name: `내 빌드 ${id}`,
      status: 'approved', counter: { ...base.counter, status: 'approved' }, ...extra,
    });
  }
}
const addBuilderTitle = () => TABLES.title_catalog.push({
  key: 'builder', name: '빌드 설계자', description: null, how_to: '공개 빌드 {n}개', kind: 'activity', equippable: true,
  starts_at: null, ends_at: null, secret: false, hidden: false, sort_order: 65, icon: null, color: null,
});
const owns = (key) => TABLES.user_titles.push({ user_id: ME, title_key: key, earned_at: '2026-11-25T03:00:00Z' });
const profileOf = (id) => TABLES.profiles.find((p) => p.id === id);

// ---------------- 개인 페이지 ----------------

test('개인 페이지: 닉네임·기본 아바타·대표 칭호·받은 칭호·공개 빌드. 인증 배지·유튜브·팔로우 없음', async () => {
  addBuilderTitle();
  addBuilds(5);
  addBuilds(1, { status: 'hidden', name: '숨긴 빌드' });
  owns('builder'); owns('top_addict');
  profileOf(ME).main_title = 'builder';
  TABLES.ext_links.push({ id: 900, owner_id: ME, build_id: null, url: 'https://youtube.com/@x', host: 'youtube.com', sort: 0 });
  start(`/u/${ME}`);
  const list = await screen.findByRole('list', { name: '빌드 목록' });
  expect(within(list).getAllByRole('listitem')).toHaveLength(5);
  const h1 = within(main()).getByRole('heading', { level: 1 });
  expect(h1.textContent).toContain('기존유저');
  await waitFor(() => expect(h1.textContent).toContain('빌드 설계자'));
  const titles = within(main()).getByRole('list', { name: '받은 칭호 목록' });
  expect(within(titles).getAllByRole('listitem').map((li) => li.textContent.trim())).toEqual(['탑신병자', '빌드 설계자']);
  expect(main().querySelector('.inf-hero-avatar svg')).not.toBeNull(); // 사진 없음 → 기본 아바타
  expect(main().querySelector('.build-total').textContent).toBe('5');
  expect(main().textContent).not.toMatch(/인증|장인|팔로워|팔로우|유튜브|숨긴 빌드/);
  expect(main().querySelector('.follow, .yt-btn, .inf-tag, .is-influencer')).toBeNull();
  expect(document.title).toBe('기존유저 프로필 - 탑신병자');
});

test('개인 페이지: 20개씩 쪽 번호, 2쪽은 member_page에 다시 묻는다', async () => {
  addBuilds(23);
  start(`/u/${ME}`);
  const list = await screen.findByRole('list', { name: '빌드 목록' });
  expect(within(list).getAllByRole('listitem')).toHaveLength(20);
  fireEvent.click(screen.getByRole('button', { name: '2쪽' }));
  await waitFor(() => expect(within(screen.getByRole('list', { name: '빌드 목록' })).getAllByRole('listitem')).toHaveLength(3));
  expect(fakeState.memberPageCalls.map((a) => a.p_page)).toEqual([1, 2]);
  expect(screen.getByText('받은 칭호가 없습니다.')).toBeTruthy();
});

test('개인 페이지: 없는 id·5개 미만·정지 중·비회원·운영자는 모두 같은 "없는 페이지"', async () => {
  const text = async (path) => {
    start(path);
    expect(await screen.findByText('문서를 찾을 수 없습니다')).toBeTruthy();
    const t = main().textContent;
    cleanup();
    return t;
  };
  const missing = await text('/u/nobody');
  addBuilds(4);
  expect(await text(`/u/${ME}`)).toBe(missing); // 5개 미만
  addBuilds(1);
  TABLES.user_restrictions.push({ id: 1, user_id: ME, reason: '검사', ends_at: '2999-01-01T00:00:00Z', lifted_at: null });
  expect(await text(`/u/${ME}`)).toBe(missing);
  TABLES.user_restrictions.length = 0;
  profileOf(ME).is_guest = true;
  expect(await text(`/u/${ME}`)).toBe(missing);
  profileOf(ME).is_guest = false;
  profileOf(ME).role = 'admin';
  expect(await text(`/u/${ME}`)).toBe(missing);
});

test('장인 /u/:id는 예전 화면 그대로이고 member_page를 부르지 않는다', async () => {
  profileOf(ME).influencer = 'creator';
  addBuilds(6);
  start(`/u/${ME}`);
  expect(await screen.findByText('인증된 크리에이터')).toBeTruthy();
  expect(main().querySelector('.member-profile')).toBeNull();
  expect(fakeState.memberPageCalls).toEqual([]);
});

// ---------------- 마이페이지 진행 안내 ----------------

const progress = () => screen.findByRole('region', { name: '공개 빌드 진행 안내' });

test('공개 빌드 수: 빌드와 상대법이 모두 공개인 것만', () => {
  const b = (status, counter) => ({ status, counter: counter && { status: counter } });
  expect(publicBuildCount([b('approved', 'approved'), b('approved', 'hidden'), b('approved', null), b('hidden', 'approved'), b('pending', 'approved')])).toBe(1);
});

test('진행 안내(달성 전): n/5 · n/10, 내 개인 페이지 링크 없음', async () => {
  addBuilderTitle();
  addBuilds(3);
  addBuilds(2, { status: 'hidden' });
  fakeLogin(ME);
  start('/me');
  const box = await progress();
  expect(box.textContent).toContain('공개 빌드 3/5 — 5개부터 내 개인 페이지가 공개됩니다');
  expect(box.textContent).toContain('공개 빌드 3/10 — 10개를 채우면 칭호 「빌드 설계자」를 받습니다');
  expect(within(box).queryByRole('link')).toBeNull();
});

test('진행 안내(5개 달성): 「달성했습니다」 + 내 개인 페이지 보기', async () => {
  addBuilderTitle();
  addBuilds(7);
  fakeLogin(ME);
  start('/me');
  const box = await progress();
  expect(box.textContent).toContain('공개 빌드 5/5 — 달성했습니다');
  expect(box.textContent).toContain('공개 빌드 7/10');
  expect(within(box).getByRole('link', { name: '내 개인 페이지 보기' }).getAttribute('href')).toBe(`/u/${ME}`);
});

test('진행 안내: 이미 받은 빌드 설계자는 빌드가 줄어도 「달성했습니다」', async () => {
  addBuilderTitle();
  addBuilds(2);
  owns('builder');
  fakeLogin(ME);
  start('/me');
  const box = await progress();
  expect(box.textContent).toContain('공개 빌드 10/10 — 달성했습니다');
  expect(box.textContent).toContain('공개 빌드 2/5');
});

test('진행 안내: 활동 제한 중이면 링크 대신 안내', async () => {
  addBuilds(5);
  fakeState.restriction = { id: 1, reason: '검사', ends_at: '2999-01-01T00:00:00Z' };
  fakeLogin(ME);
  start('/me');
  const box = await progress();
  expect(await within(box).findByText('활동 제한 중에는 개인 페이지가 공개되지 않습니다.')).toBeTruthy();
  expect(within(box).queryByRole('link')).toBeNull();
});

test('진행 안내: 장인에게는 개인 페이지 줄이 없다', async () => {
  addBuilderTitle();
  addBuilds(6);
  profileOf(ME).influencer = 'creator';
  fakeLogin(ME);
  start('/me');
  const box = await progress();
  expect(box.textContent).not.toContain('개인 페이지');
  expect(box.textContent).toContain('공개 빌드 6/10');
});

// ---------------- 칭호 알림 → 칭호판 ----------------

test('칭호 알림에서 온 /me#my-titles는 칭호판까지 내려간다', async () => {
  const scrolled = [];
  Element.prototype.scrollIntoView = function scrollIntoView() { scrolled.push(this); };
  fakeLogin(ME);
  start('/me#my-titles');
  await screen.findByRole('list', { name: '칭호판' });
  await waitFor(() => expect(scrolled.some((el) => el.classList.contains('title-card'))).toBe(true));
});
