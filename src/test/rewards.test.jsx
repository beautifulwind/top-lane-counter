// 6단계: /me 레벨·칭호판(훈장, 2026-11-04), 대표 칭호 고르기, 레벨·칭호 알림, 운영자 비주류 픽 목록
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

test('/me 레벨: 제목·"경험치" 글자 없이 큰 Lv, 막대 + 작은 숫자 "현재 / 목표" (2026-11-04)', async () => {
  TABLES.xp_events.push(ev(1, 'new_counter', 100), ev(3, 'build', 30));
  asUser();
  start('/me');
  const section = await screen.findByRole('region', { name: '레벨' });
  expect(within(section).queryByRole('heading', { name: 'Level' })).toBeNull();
  expect(section.querySelector('.lv-big').textContent).toBe('Lv.3');
  const bar = screen.getByRole('progressbar', { name: 'Lv.4까지' });
  expect(bar.textContent).toBe('');
  expect([bar.getAttribute('aria-valuemin'), bar.getAttribute('aria-valuenow'), bar.getAttribute('aria-valuemax')]).toEqual(['300', '420', '600']);
  expect(section.querySelector('.xp-nums').textContent).toBe('경험치 420 / 600'); // "경험치"는 화면 읽기용(sr-only)
  expect(section.querySelector('.xp-nums .sr-only').textContent).toBe('경험치 ');
  expect(screen.queryByText(/남았습니다/)).toBeNull();
  expect(screen.queryByText('경험치 내역')).toBeNull();
});

test('/me 프로필 카드 하나에 닉네임·칭호 태그·Lv·경험치 막대 — Lv는 한 번만, 계정 일은 [계정 설정]으로', async () => {
  TABLES.xp_events.push(ev(1, 'new_counter', 100), ev(3, 'build', 30));
  asUser();
  start('/me');
  const card = (await screen.findByRole('region', { name: '레벨' })).closest('.me-hero');
  const h1 = within(card).getByRole('heading', { level: 1 });
  expect(h1.querySelector('.user-lv')).toBeNull();
  expect(h1.querySelector('.user-nick')).not.toBeNull();
  expect(within(card).getByRole('progressbar')).toBeDefined();
  expect(document.querySelectorAll('main .lv-big')).toHaveLength(1);
  expect(within(card).getByRole('link', { name: '계정 설정' }).getAttribute('href')).toBe('/me/settings');
  expect(screen.getByRole('region', { name: '칭호' })).toBeDefined();
  expect(screen.queryByRole('region', { name: '닉네임 바꾸기' })).toBeNull();
  expect(screen.queryByRole('region', { name: '회원 탈퇴' })).toBeNull();
});

const medal = (board, name) => within(board).getByRole('button', { name: new RegExp(`^${name}`) });

test('/me 칭호판: 6개 훈장 전부 — 얻은 것은 칭호색, 못 얻은 것은 회색, 설명 글은 화면에 없음', async () => {
  TABLES.user_titles.push(
    { user_id: ME, title_key: 'top_addict', earned_at: '2026-11-01T00:00:00Z' },
    { user_id: ME, title_key: 'tool_hater', earned_at: '2026-11-02T00:00:00Z' },
  );
  asUser();
  start('/me');
  const board = await screen.findByRole('list', { name: '칭호판' });
  expect(within(board).getAllByRole('button').map((b) => b.getAttribute('aria-label'))).toEqual([
    '탑신병자', '도구혐오자', '단단묵직 (아직 못 얻음)', '백정주인 (아직 못 얻음)', '장군 (아직 못 얻음)', '비주류 (아직 못 얻음)',
  ]);
  expect(medal(board, '도구혐오자').className).toBe('medal tool_hater owned');
  expect(medal(board, '장군').className).toBe('medal general locked');
  // 카운터 승인 단계 점: 도구혐오자 1 · 단단묵직 2 · 백정주인 3
  expect(['도구혐오자', '단단묵직', '백정주인', '장군'].map((n) => medal(board, n).querySelectorAll('svg > g > circle').length)).toEqual([1, 2, 3, 0]);
  expect(screen.queryByText(/카운터 관련 승인/)).toBeNull();
  expect(screen.queryByRole('radio')).toBeNull();
});

test('/me 칭호판: 마우스를 올리면 이름·조건·날짜 말풍선(버튼 없음), 못 얻은 칭호는 "아직 못 얻음"', async () => {
  TABLES.user_titles.push({ user_id: ME, title_key: 'tool_hater', earned_at: '2026-11-02T00:00:00Z' });
  asUser();
  start('/me');
  const board = await screen.findByRole('list', { name: '칭호판' });
  fireEvent.mouseEnter(medal(board, '도구혐오자'));
  const tip = screen.getByRole('tooltip');
  expect(tip.textContent).toMatch(/도구혐오자카운터 관련 승인 10개.*얻음$/);
  expect(within(tip).queryByRole('button')).toBeNull();
  fireEvent.mouseLeave(medal(board, '도구혐오자'));
  expect(screen.queryByRole('tooltip')).toBeNull();
  fireEvent.mouseEnter(medal(board, '장군'));
  expect(screen.getByRole('tooltip').textContent).toMatch(/추천 합계 100아직 못 얻음$/);
});

test('/me 칭호판: 얻은 훈장을 누르면 [대표로 설정] → 훈장에 "대표" + 메뉴 닉네임 배지 반영, 다시 누르면 [대표 해제]', async () => {
  TABLES.user_titles.push(
    { user_id: ME, title_key: 'top_addict', earned_at: '2026-11-01T00:00:00Z' },
    { user_id: ME, title_key: 'tool_hater', earned_at: '2026-11-02T00:00:00Z' },
  );
  asUser();
  start('/me');
  const board = await screen.findByRole('list', { name: '칭호판' });

  fireEvent.click(medal(board, '탑신병자'));
  expect(medal(board, '탑신병자').getAttribute('aria-expanded')).toBe('true');
  const pop = screen.getByRole('group', { name: '칭호 탑신병자' });
  fireEvent.click(within(pop).getByRole('button', { name: '대표로 설정' }));
  await vi.waitFor(() => expect(TABLES.profiles.find((p) => p.id === ME).main_title).toBe('top_addict'));
  await vi.waitFor(() => expect(medal(board, '탑신병자').getAttribute('aria-label')).toBe('탑신병자 (대표 칭호)'));
  expect(medal(board, '탑신병자').className).toBe('medal top_addict owned main');
  expect(within(medal(board, '탑신병자')).getByText('대표')).toBeDefined();
  expect(within(pop).getByRole('button', { name: '대표 해제' })).toBeDefined();
  await vi.waitFor(async () => expect(await menuUserText()).toBe('Lv.3 탑신병자 기존유저'));
  const menu = await openMenu();
  expect(document.querySelector('.menu-user .title-badge.top_addict').getAttribute('title')).toBe("칭호 '탑신병자'");
  fireEvent.keyDown(menu.getByRole('button', { name: '메뉴 닫기' }), { key: 'Escape' });

  // 다른 훈장으로 바꾸기
  fireEvent.click(medal(board, '도구혐오자'));
  fireEvent.click(within(screen.getByRole('group', { name: '칭호 도구혐오자' })).getByRole('button', { name: '대표로 설정' }));
  await vi.waitFor(() => expect(TABLES.profiles.find((p) => p.id === ME).main_title).toBe('tool_hater'));

  // 대표 해제
  fireEvent.click(within(screen.getByRole('group', { name: '칭호 도구혐오자' })).getByRole('button', { name: '대표 해제' }));
  await vi.waitFor(async () => expect(await menuUserText()).toBe('Lv.3 기존유저'));
  expect(TABLES.profiles.find((p) => p.id === ME).main_title).toBeNull();
});

test('/me 칭호판: 못 얻은 훈장은 눌러도 버튼 없음, 다시 누르기·바깥·Esc로 닫힘', async () => {
  asUser();
  start('/me');
  const board = await screen.findByRole('list', { name: '칭호판' });
  fireEvent.click(medal(board, '장군'));
  const pop = screen.getByRole('group', { name: '칭호 장군' });
  expect(within(pop).queryByRole('button')).toBeNull();
  fireEvent.click(medal(board, '장군'));
  expect(screen.queryByRole('group', { name: '칭호 장군' })).toBeNull();

  fireEvent.click(medal(board, '비주류'));
  fireEvent.pointerDown(document.body);
  expect(screen.queryByRole('group', { name: '칭호 비주류' })).toBeNull();

  fireEvent.click(medal(board, '비주류'));
  fireEvent.keyDown(document, { key: 'Escape' });
  expect(screen.queryByRole('group', { name: '칭호 비주류' })).toBeNull();
  expect(document.activeElement).toBe(medal(board, '비주류'));
});

test('/me: 메뉴 맨 위 닉네임도 새로 읽은 레벨·대표 칭호로 맞춘다 (로그인 뒤에 바뀐 값)', async () => {
  fakeLogin(ME);
  const p = TABLES.profiles.find((x) => x.id === ME);
  Object.assign(p, { xp: 420, level: 3 }); // 로그인 뒤 DB에서 바뀜
  start('/me');
  await screen.findByText('Lv.3', { selector: '.lv-big' });
  await vi.waitFor(async () => expect(await menuUserText()).toBe('Lv.3 기존유저'));
});

test('운영자 /me: 경험치·레벨·칭호 없음 안내', async () => {
  fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0, main_title: null });
  start('/me');
  expect(await screen.findByText('운영자는 경험치·레벨·칭호가 없습니다 (항상 Lv.0).')).toBeDefined();
  expect(screen.queryByRole('progressbar')).toBeNull();
  expect(screen.queryByRole('heading', { name: 'Level' })).toBeNull();
  expect(screen.queryByRole('list', { name: '칭호판' })).toBeNull();
});

test('운영자: 비주류 픽 추가·빼기 (보라 버튼, 이미 승인된 기여는 그대로라는 안내)', async () => {
  fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0, main_title: null });
  start('/admin');
  expect(await screen.findByText('비주류 픽이 아직 없습니다.')).toBeDefined();
  expect(screen.getByText(/목록을 바꿔도 이미 승인된 기여는 그대로입니다/)).toBeDefined();
  fireEvent.change(screen.getByLabelText('비주류 픽에 추가할 챔피언 검색'), { target: { value: '퀸' } });
  const add = within(screen.getByRole('list', { name: '검색 결과' })).getByRole('button', { name: '퀸 추가' });
  expect(add.classList.contains('btn-op')).toBe(true);
  fireEvent.click(add);
  expect(await screen.findByText('비주류 픽에 넣었습니다: 퀸')).toBeDefined();
  expect(fakeState.rpcCalls).toContainEqual({ name: 'add_offmeta', args: { p_champion: 'Quinn' } });
  fireEvent.click(await within(await screen.findByRole('list', { name: '비주류 픽 목록' })).findByRole('button', { name: '퀸 빼기' }));
  expect(await screen.findByText('비주류 픽에서 뺐습니다: 퀸')).toBeDefined();
  expect(fakeState.rpcCalls).toContainEqual({ name: 'remove_offmeta', args: { p_champion: 'Quinn' } });
});
