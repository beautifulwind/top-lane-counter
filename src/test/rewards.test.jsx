// 6단계: /me Level·칭호, 대표 칭호 고르기 (022: 경험치 내역 없음, 가진 칭호만), 레벨·칭호 알림, 운영자 비주류 픽 목록
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeLogin, fakeState } from './fakeSupabase';
import { levelProgress } from '../lib/levels';
import { menuUserText, openMenu } from './menu';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /></MemoryRouter>);
const ME = 'u-old';
const asUser = () => {
  Object.assign(TABLES.profiles.find((p) => p.id === ME), { xp: 420, level: 3 }); // 기존유저 (fake 기본 프로필)
  fakeLogin(ME);
};
const ev = (id, type, amount, extra = {}) => ({
  id, user_id: ME, type, amount, change: amount > 0 ? 'grant' : 'revoke', reason: null,
  target_champion: 'Darius', counter_champion: 'Quinn', created_at: `2026-11-0${id}T00:00:00Z`, ...extra,
});

test('레벨 계산: 표 안·Lv.10 이후', () => {
  const levels = TABLES.xp_levels;
  expect(levelProgress(0, levels, 1000)).toMatchObject({ level: 1, from: 0, to: 100, toNext: 100, percent: 0 });
  expect(levelProgress(420, levels, 1000)).toMatchObject({ level: 3, from: 300, to: 600, toNext: 180, percent: 40 });
  expect(levelProgress(4500, levels, 1000)).toMatchObject({ level: 10, from: 4500, to: 5500 });
  expect(levelProgress(6000, levels, 1000)).toMatchObject({ level: 11, from: 5500, to: 6500, toNext: 500 });
});

test('/me Level: 레벨·경험치 막대·다음 레벨까지 (022: 경험치 내역 칸 없음)', async () => {
  TABLES.xp_events.push(ev(1, 'new_counter', 100), ev(3, 'build', 30));
  asUser();
  start('/me');
  expect(await screen.findByRole('heading', { name: 'Level' })).toBeDefined();
  expect(screen.queryByRole('heading', { name: '레벨·경험치' })).toBeNull();
  expect((await screen.findByText(/· 경험치 420/)).textContent).toBe('Lv.3 · 경험치 420');
  const bar = screen.getByRole('progressbar', { name: 'Lv.4까지' });
  expect([bar.getAttribute('aria-valuemin'), bar.getAttribute('aria-valuenow'), bar.getAttribute('aria-valuemax')]).toEqual(['300', '420', '600']);
  expect(screen.getByText(/다음 레벨\(Lv.4\)까지 180 남았어요/)).toBeDefined();
  expect(screen.queryByRole('list', { name: '경험치 내역' })).toBeNull();
  expect(screen.queryByText('경험치 내역')).toBeNull();
});

test('/me 칭호: 가진 칭호만 배지로 보이고 대표로 고를 수 있다 → 메뉴 맨 위 닉네임에 배지로 바로 반영', async () => {
  TABLES.user_titles.push(
    { user_id: ME, title_key: 'top_addict', earned_at: '2026-11-01T00:00:00Z' },
    { user_id: ME, title_key: 'tool_hater', earned_at: '2026-11-02T00:00:00Z' },
  );
  asUser();
  start('/me');
  const picker = await screen.findByRole('group', { name: '대표 칭호 (닉네임 앞에 보여요)' });
  expect(within(picker).getAllByRole('radio').map((r) => r.getAttribute('aria-label') ?? '없음')).toEqual(['없음', '탑신병자', '도구혐오자']);
  expect(within(picker).queryByText('장군')).toBeNull();
  expect(within(picker).queryByText(/아직 없음/)).toBeNull();
  expect(within(picker).getByText('도구혐오자').className).toBe('title-badge tool_hater');
  expect(within(picker).getByText(/카운터 관련 승인 10개/)).toBeDefined();

  fireEvent.click(within(picker).getByRole('radio', { name: '탑신병자' }));
  await vi.waitFor(() => expect(TABLES.profiles.find((p) => p.id === ME).main_title).toBe('top_addict'));
  // ☰ 메뉴 맨 위 닉네임에 바로 반영
  await vi.waitFor(async () => expect(await menuUserText()).toBe('Lv.3 탑신병자 기존유저'));
  const menu = await openMenu();
  expect(document.querySelector('.menu-user .title-badge.top_addict').getAttribute('title')).toBe("칭호 '탑신병자'");
  fireEvent.keyDown(menu.getByRole('button', { name: '메뉴 닫기' }), { key: 'Escape' });
  fireEvent.click(within(picker).getByText('없음'));
  await vi.waitFor(async () => expect(await menuUserText()).toBe('Lv.3 기존유저'));
});

test('/me 칭호: 하나도 없으면 고르기 칸 대신 안내만', async () => {
  asUser();
  start('/me');
  expect(await screen.findByText(/아직 가진 칭호가 없어요/)).toBeDefined();
  expect(screen.queryByRole('group', { name: '대표 칭호 (닉네임 앞에 보여요)' })).toBeNull();
});

test('/me: 메뉴 맨 위 닉네임도 새로 읽은 레벨·대표 칭호로 맞춘다 (로그인 뒤에 바뀐 값)', async () => {
  fakeLogin(ME);
  const p = TABLES.profiles.find((x) => x.id === ME);
  Object.assign(p, { xp: 420, level: 3 }); // 로그인 뒤 DB에서 바뀜
  start('/me');
  await screen.findByText(/· 경험치 420/);
  await vi.waitFor(async () => expect(await menuUserText()).toBe('Lv.3 기존유저'));
});

test('/me: 레벨업·칭호 알림은 레벨 칸 위에 "새 알림"으로 한 번 보이고 읽음 처리', async () => {
  TABLES.notifications.push(
    { id: 1, user_id: ME, kind: 'level_up', message: '레벨이 올랐어요: Lv.3', created_at: '2026-11-02T00:00:00Z', read_at: null },
    { id: 2, user_id: ME, kind: 'title_earned', message: "칭호 '탑신병자'를 얻었어요. [마이페이지]에서 대표 칭호로 고를 수 있어요.", created_at: '2026-11-02T00:00:00Z', read_at: null },
  );
  asUser();
  start('/me');
  expect(await screen.findByText('레벨이 올랐어요: Lv.3')).toBeDefined();
  expect(screen.getByText(/칭호 '탑신병자'를 얻었어요/)).toBeDefined();
  await vi.waitFor(() => expect(TABLES.notifications.every((n) => n.read_at)).toBe(true));
});

test('운영자 /me: 경험치·레벨·칭호 없음 안내', async () => {
  fakeLogin('u-op', { nickname: '영자(운)', role: 'admin', level: 0, main_title: null });
  start('/me');
  expect(await screen.findByText('운영자는 경험치·레벨·칭호가 없어요 (항상 Lv.0).')).toBeDefined();
  expect(screen.queryByRole('progressbar')).toBeNull();
});

test('운영자: 비주류 픽 추가·빼기 (보라 버튼, 이미 승인된 기여는 그대로라는 안내)', async () => {
  fakeLogin('u-op', { nickname: '영자(운)', role: 'admin', level: 0, main_title: null });
  start('/admin');
  expect(await screen.findByText('비주류 픽이 아직 없어요.')).toBeDefined();
  expect(screen.getByText(/목록을 바꿔도 이미 승인된 기여는 그대로예요/)).toBeDefined();
  fireEvent.change(screen.getByLabelText('비주류 픽에 추가할 챔피언 검색'), { target: { value: '퀸' } });
  const add = within(screen.getByRole('list', { name: '검색 결과' })).getByRole('button', { name: '퀸 추가' });
  expect(add.classList.contains('btn-op')).toBe(true);
  fireEvent.click(add);
  expect(await screen.findByText('비주류 픽에 넣었어요: 퀸')).toBeDefined();
  expect(fakeState.rpcCalls).toContainEqual({ name: 'add_offmeta', args: { p_champion: 'Quinn' } });
  fireEvent.click(await within(await screen.findByRole('list', { name: '비주류 픽 목록' })).findByRole('button', { name: '퀸 빼기' }));
  expect(await screen.findByText('비주류 픽에서 뺐어요: 퀸')).toBeDefined();
  expect(fakeState.rpcCalls).toContainEqual({ name: 'remove_offmeta', args: { p_champion: 'Quinn' } });
});
