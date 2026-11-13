// 칭호 도감 2단계(화면, 2026-11-13): /me 칭호 칸이 my_title_book() 하나로 활동·장인·한정판을 읽는다 (SPEC 6-3·6-4)
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeLimitedTitle, fakeLogin } from './fakeSupabase';
import { ModerationLog } from '../components/ModeratorAdmin';
import { describeNotification } from '../lib/notifications';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /></MemoryRouter>);
const ME = 'u-old';
const DAY = 86400000;
const iso = (offset) => new Date(Date.now() + offset * DAY).toISOString();

/** 한정판 3개: 진행 중(색 + 그림 파일, 내가 가짐) / 끝남(색, 못 얻음) / 비밀(못 얻음) */
const addLimited = () => {
  TABLES.title_catalog.push(
    fakeLimitedTitle('s1_launch', { name: '시즌1 개척자', description: '시즌1 첫 주에 함께한 분', how_to: '시즌1 이벤트 참여', color: '#ff8a3d', icon: 'launch.png', starts_at: '2026-11-01T12:00:00Z', ends_at: iso(30), sort_order: 1 }),
    fakeLimitedTitle('s0_beta', { name: '베타 지킴이', how_to: '베타 기간에 제보', color: '#7cc4ff', starts_at: '2026-01-01T12:00:00Z', ends_at: '2026-02-01T12:00:00Z', sort_order: 2 }),
    fakeLimitedTitle('hidden_one', { name: '숨은 칭호', how_to: '아무도 모르는 방법', secret: true, sort_order: 3 }),
  );
};
const owns = (key) => TABLES.user_titles.push({ user_id: ME, title_key: key, earned_at: '2026-11-05T03:00:00Z' });
const asUser = () => fakeLogin(ME);
const tile = async (name) => (await screen.findByRole('list', { name: '칭호판' })) && screen.getByRole('button', { name: new RegExp(`^${name}`) });

test('칭호 칸: 활동 칭호만 "얻은 수 / 전체 수"로 센다, 장인·한정판은 "특별 칭호" 구역', async () => {
  addLimited();
  owns('top_addict'); owns('s1_launch');
  asUser();
  start('/me');
  await screen.findByRole('list', { name: '칭호판' });
  expect(screen.getByLabelText('칭호 6개 중 1개 얻음').textContent).toBe('1 / 6'); // 한정판을 얻어도 그대로
  expect(screen.getByRole('heading', { name: '특별 칭호' })).toBeDefined();
  const special = screen.getByRole('list', { name: '특별 칭호' });
  expect(within(special).getAllByRole('button').map((b) => b.getAttribute('aria-label'))).toEqual([
    '장인 (아직 못 얻음)', '시즌1 개척자', '베타 지킴이 (아직 못 얻음) (종료)', '??? (아직 못 얻음)',
  ]);
});

test('장인 칭호: 인증 여부(auth.profile.influencer)로 켜짐/흐리게만, 장착 버튼 없음', async () => {
  asUser();
  const { unmount } = start('/me');
  expect((await tile('장인')).className).toBe('medal locked');
  unmount();
  cleanup();
  TABLES.profiles.find((p) => p.id === ME).influencer = 'creator';
  TABLES.profiles.find((p) => p.id === ME).influencer_at = '2026-10-20T00:00:00Z';
  start('/me');
  const t = await tile('장인');
  expect(t.className).toBe('medal owned');
  fireEvent.click(t);
  const pop = screen.getByRole('group', { name: '칭호 장인' });
  expect(within(pop).queryByRole('button')).toBeNull();
  expect(pop.textContent).toContain('인증');
  delete TABLES.profiles.find((p) => p.id === ME).influencer;
});

test('한정판: 얻으면 켜짐(그림 파일 + 칭호색), 못 얻으면 흐리게 + 기간, 끝났으면 "종료"', async () => {
  addLimited();
  owns('s1_launch');
  asUser();
  start('/me');
  const on = await tile('시즌1 개척자');
  expect(on.className).toBe('medal limited owned');
  expect(on.style.getPropertyValue('--t')).toBe('#ff8a3d');
  const img = on.querySelector('img.medal-img');
  expect(img.getAttribute('src')).toBe('/titles/launch.png');
  expect(img.getAttribute('alt')).toBe('');

  const off = screen.getByRole('button', { name: /^베타 지킴이/ });
  expect(off.className).toBe('medal limited locked');
  expect(off.querySelector('svg.medal-icon')).not.toBeNull(); // icon이 비면 공통 훈장에 색
  expect(off.style.getPropertyValue('--t')).toBe('#7cc4ff');
  expect(within(off).getByText('종료')).toBeDefined();

  fireEvent.click(off);
  const pop = screen.getByRole('group', { name: '칭호 베타 지킴이' });
  expect(pop.textContent).toContain('종료');
  expect(pop.textContent).toContain('2026-01-01');
  expect(pop.textContent).toContain('2026-02-01'); // 시작일·종료일
  expect(pop.textContent).toContain('베타 기간에 제보');
  expect(pop.textContent).toContain('아직 못 얻음');
  expect(within(pop).queryByRole('button')).toBeNull(); // 한정판은 대표로 못 고른다

  fireEvent.click(on);
  const pop2 = screen.getByRole('group', { name: '칭호 시즌1 개척자' });
  expect(pop2.textContent).toContain('시즌1 첫 주에 함께한 분');
  expect(pop2.textContent).toContain('진행 중');
  expect(pop2.textContent).toContain('얻음');
  expect(within(pop2).queryByRole('button')).toBeNull();
});

test('그림 파일이 없으면(불러오기 실패) 공통 훈장으로', async () => {
  addLimited();
  asUser();
  start('/me');
  const on = await tile('시즌1 개척자');
  fireEvent.error(on.querySelector('img'));
  expect(on.querySelector('img')).toBeNull();
  expect(on.querySelector('svg.medal-icon')).not.toBeNull();
});

test('비밀 칭호: 못 얻었으면 "???"와 비밀 안내만, 얻으면 이름·방법이 보인다', async () => {
  addLimited();
  asUser();
  const { unmount } = start('/me');
  const t = await tile('\\?\\?\\?');
  expect(t.textContent).toBe('???');
  fireEvent.click(t);
  const pop = screen.getByRole('group', { name: '칭호 ???' });
  expect(pop.textContent).not.toContain('아무도 모르는 방법');
  expect(pop.textContent).not.toContain('숨은 칭호');
  expect(pop.textContent).toContain('얻는 방법은 비밀입니다.');
  unmount();
  cleanup();
  owns('hidden_one');
  start('/me');
  const t2 = await tile('숨은 칭호');
  fireEvent.click(t2);
  expect(screen.getByRole('group', { name: '칭호 숨은 칭호' }).textContent).toContain('아무도 모르는 방법');
});

test('눌러서(폰)·Tab(키보드)으로 얻는 방법이 나오고, 활동 칭호의 [대표로 설정]/[대표 해제]는 그대로', async () => {
  owns('tool_hater');
  asUser();
  start('/me');
  const t = await tile('도구혐오자');
  fireEvent.focus(t); // Tab으로 옴 → 보기만
  expect(screen.getByRole('tooltip').textContent).toContain('상대법 관련 승인 10개');
  fireEvent.blur(t);
  expect(screen.queryByRole('tooltip')).toBeNull();
  fireEvent.click(t);
  fireEvent.click(within(screen.getByRole('group', { name: '칭호 도구혐오자' })).getByRole('button', { name: '대표로 설정' }));
  await vi.waitFor(() => expect(t.className).toBe('medal tool_hater owned main'));
  fireEvent.click(within(screen.getByRole('group', { name: '칭호 도구혐오자' })).getByRole('button', { name: '대표 해제' }));
  await vi.waitFor(() => expect(t.className).toBe('medal tool_hater owned'));
});

test('기존 6개 훈장은 색 값 없이 CSS 색 그대로 (칭호 키 클래스 + 공통 훈장)', async () => {
  owns('general');
  asUser();
  start('/me');
  const t = await tile('장군');
  expect(t.className).toBe('medal general owned');
  expect(t.getAttribute('style')).toBeNull();
  expect(t.querySelector('svg.medal-icon')).not.toBeNull();
});

test('접으면 2줄(10개)만, [더보기]/[접기] — 한정판 3개 + 기존 7개 = 10개라 버튼 없음, 11개째부터 버튼', async () => {
  addLimited();
  asUser();
  const { unmount } = start('/me');
  await screen.findByRole('list', { name: '칭호판' });
  expect(document.querySelectorAll('.medal')).toHaveLength(10);
  expect(screen.queryByRole('button', { name: '더보기' })).toBeNull();
  unmount();
  cleanup();
  TABLES.title_catalog.push(fakeLimitedTitle('extra_a', { name: '추가A', sort_order: 4 }), fakeLimitedTitle('extra_b', { name: '추가B', sort_order: 5 }));
  start('/me');
  await screen.findByRole('list', { name: '칭호판' });
  expect(document.querySelectorAll('.medal')).toHaveLength(10);
  expect(screen.queryByRole('button', { name: /^추가A/ })).toBeNull();
  fireEvent.click(screen.getByRole('button', { name: '더보기' }));
  expect(document.querySelectorAll('.medal')).toHaveLength(12);
  expect(screen.getByRole('button', { name: '접기' }).getAttribute('aria-expanded')).toBe('true');
  fireEvent.click(screen.getByRole('button', { name: '접기' }));
  expect(document.querySelectorAll('.medal')).toHaveLength(10);
});

test('한정판이 0개(지금 상태)여도 어색하지 않게: 장인 훈장 + "준비 중" 안내', async () => {
  asUser();
  start('/me');
  await screen.findByRole('list', { name: '칭호판' });
  expect(document.querySelectorAll('.medal')).toHaveLength(7);
  expect(screen.getByRole('heading', { name: '특별 칭호' })).toBeDefined();
  expect(screen.getByText('한정판 칭호는 준비 중입니다.')).toBeDefined();
  expect(screen.getByLabelText('칭호 6개 중 0개 얻음').textContent).toBe('0 / 6');
});

test('운영자 /me에도 도감 — 전부 흐리게, 대표로 설정할 수 없다', async () => {
  addLimited();
  fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0, main_title: null });
  start('/me');
  const board = await screen.findByRole('list', { name: '칭호판' });
  expect(within(board).getAllByRole('button').every((b) => b.className.includes('locked'))).toBe(true);
  expect(screen.getByText('운영자는 경험치·레벨·칭호가 없습니다 (항상 Lv.0).')).toBeDefined();
  expect(screen.getByLabelText('칭호 6개 중 0개 얻음').textContent).toBe('0 / 6');
  fireEvent.click(within(board).getAllByRole('button')[0]);
  expect(within(screen.getByRole('group')).queryByRole('button')).toBeNull();
});

test('알림: 한정판 칭호 알림도 도감을 읽어 훈장(칭호색·그림 파일)이 나온다', async () => {
  addLimited();
  TABLES.notifications.push(
    { id: 9001, user_id: ME, kind: 'title_earned', message: "칭호 '시즌1 개척자'를 얻었습니다. [마이페이지] 칭호 칸에서 볼 수 있습니다.", created_at: '2026-11-02T00:00:00Z', read_at: '2026-11-02T01:00:00Z' },
    { id: 9002, user_id: ME, kind: 'title_earned', message: "칭호 '베타 지킴이'를 얻었습니다. [마이페이지] 칭호 칸에서 볼 수 있습니다.", created_at: '2026-11-02T00:00:00Z', read_at: '2026-11-02T01:00:00Z' },
  );
  asUser();
  start('/notifications');
  const a = (await screen.findByText(/'시즌1 개척자'/)).closest('li');
  expect(a.querySelector('.noti-icon.title-color img.medal-img').getAttribute('src')).toBe('/titles/launch.png');
  expect(a.querySelector('.noti-icon').style.getPropertyValue('--t')).toBe('#ff8a3d');
  const b = (await screen.findByText(/'베타 지킴이'/)).closest('li');
  expect(b.querySelector('.noti-icon.title-color svg.medal-icon')).not.toBeNull();
  // 도감을 못 읽어도(빈 목록) 예전 6개는 그대로
  expect(describeNotification({ kind: 'title_earned', message: "칭호 '장군'을 얻었습니다." }).titleKey).toBe('general');
  expect(describeNotification({ kind: 'title_earned', message: "칭호 '시즌1 개척자'를 얻었습니다." }).titleKey).toBeNull();
});

test('처리 기록: 칭호 지급·회수 이름표', async () => {
  fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0, main_title: null });
  TABLES.moderation_log.unshift(
    { id: 91, actor_nickname: '영자', actor_role: 'admin', action: 'revoke_title', target_kind: 'user', target_id: ME, target_nickname: '기존유저', note: '시즌1 개척자 · 잘못 지급', created_at: '2026-11-13T02:00:00Z' },
    { id: 90, actor_nickname: '영자', actor_role: 'admin', action: 'grant_title', target_kind: 'user', target_id: ME, target_nickname: '기존유저', note: '시즌1 개척자 · 이벤트', created_at: '2026-11-13T01:00:00Z' },
  );
  render(<MemoryRouter><ModerationLog /></MemoryRouter>);
  expect(await screen.findByText(/칭호 지급/)).toBeDefined();
  expect(screen.getByText(/칭호 회수/)).toBeDefined();
  expect(screen.queryByText(/grant_title|revoke_title/)).toBeNull();
});
