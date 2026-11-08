// 034: 운영자 모드 켜기/끄기 (계정 설정), 끄면 일반 회원 화면, 다시 켜기 / 제안자 알림 counter_restored
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import { describeNotification } from '../lib/notifications';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeLogin } from './fakeSupabase';
import { openMenu } from './menu';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /></MemoryRouter>);
const asOp = (extra = {}) => fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0, main_title: null, ...extra });
const me = () => TABLES.profiles.find((p) => p.id === 'u-op');
const closeMenu = async (menu) => fireEvent.keyDown(await menu.findByRole('button', { name: '메뉴 닫기' }), { key: 'Escape' });

test('계정 설정: 운영자에게만 [운영자 모드] 칸 — 일반 회원·감독관에게는 없다', async () => {
  fakeLogin('u-old');
  start('/me/settings');
  expect(await screen.findByRole('heading', { name: /닉네임/ })).toBeDefined();
  expect(screen.queryByRole('heading', { name: '운영자 모드' })).toBeNull();
  cleanup();
  fakeLogin('u-mod', { nickname: '감독', role: 'moderator', level: 3, main_title: null });
  start('/me/settings');
  expect(await screen.findByRole('heading', { name: /닉네임/ })).toBeDefined();
  expect(screen.queryByRole('heading', { name: '운영자 모드' })).toBeNull();
});

test('끄기 → 관리 메뉴가 사라지고 운영진 알림이 안 보임, 같은 자리에서 다시 켜면 돌아온다', async () => {
  TABLES.notifications.push({
    id: 1, user_id: 'u-op', kind: 'proposal_submitted', message: '새 카운터 제안이 들어왔습니다.', proposal_id: null, build_id: null,
    post_id: null, counter_id: null, created_at: '2026-11-08T00:00:00Z', read_at: null,
  });
  asOp();
  start('/me/settings');
  expect(await screen.findByRole('heading', { name: '운영자 모드' })).toBeDefined();
  expect(document.querySelector('.operator-mode-state').textContent).toBe('지금 켜짐');
  let menu = await openMenu();
  expect(await menu.findByRole('link', { name: '관리' })).toBeDefined();
  await closeMenu(menu);

  fireEvent.click(screen.getByRole('button', { name: '운영자 모드 끄기' }));
  expect(await screen.findByRole('button', { name: '운영자 모드 켜기' })).toBeDefined();
  expect(me().operator_mode).toBe(false);
  expect(document.querySelector('.operator-mode-state').textContent).toBe('지금 꺼짐');
  // 탈퇴 불가는 모드와 관계없이 그대로
  expect(screen.getByText('운영자 계정은 탈퇴할 수 없습니다.')).toBeDefined();
  menu = await openMenu();
  await waitFor(() => expect(menu.queryByRole('link', { name: '관리' })).toBeNull());
  await closeMenu(menu);

  fireEvent.click(screen.getByRole('button', { name: '운영자 모드 켜기' }));
  expect(await screen.findByRole('button', { name: '운영자 모드 끄기' })).toBeDefined();
  expect(me().operator_mode).toBe(true);
  menu = await openMenu();
  expect(await menu.findByRole('link', { name: '관리' })).toBeDefined();
});

test('끈 채로 들어오면: 관리 화면은 일반 회원처럼 막히고, 알림 화면에 운영진 알림이 없다', async () => {
  TABLES.notifications.push({
    id: 1, user_id: 'u-op', kind: 'proposal_submitted', message: '새 카운터 제안이 들어왔습니다.', proposal_id: null, build_id: null,
    post_id: null, counter_id: null, created_at: '2026-11-08T00:00:00Z', read_at: null,
  });
  asOp({ operator_mode: false });
  start('/notifications');
  expect(await screen.findByText('아직 받은 알림이 없습니다.')).toBeDefined();
  expect(screen.queryByText('새 카운터 제안이 들어왔습니다.')).toBeNull();
  // 열어도 숨긴 운영진 알림은 읽음 처리되지 않는다 (다시 켜면 새 알림으로 보임)
  expect(TABLES.notifications[0].read_at).toBeNull();
  cleanup();
  start('/admin');
  expect(await screen.findByText('운영자만 볼 수 있습니다.')).toBeDefined();
  cleanup();
  start('/me');
  expect(await screen.findByText(/운영자 모드가 꺼져 있어/)).toBeDefined();
});

test('켜기/끄기가 실패하면 이유를 보여 주고 상태는 그대로', async () => {
  asOp();
  start('/me/settings');
  await screen.findByRole('heading', { name: '운영자 모드' });
  me().role = 'user'; // DB에서 운영자가 아니게 된 경우 → DB가 거부
  fireEvent.click(screen.getByRole('button', { name: '운영자 모드 끄기' }));
  expect((await screen.findByRole('alert')).textContent).toBe('운영자 계정만 운영자 모드를 바꿀 수 있습니다.');
  expect(screen.getByRole('button', { name: '운영자 모드 끄기' })).toBeDefined();
});

test('제안자 알림 counter_restored: 제목·[종류] 매치업·메모, 누르면 내 제안', () => {
  const n = {
    kind: 'counter_restored', message: '확인했습니다', proposal_id: 7, build_id: null,
    proposal: { type: 'new_counter', target_champion: 'Darius', counter_champion: 'Garen' }, build: null,
  };
  const d = describeNotification(n, (id) => ({ Darius: '다리우스', Garen: '가렌' }[id]));
  expect(d.title).toBe('숨겨졌던 내 카운터가 다시 공개됐습니다');
  expect(d.subject).toBe('[새 카운터] 가렌으로 다리우스 이기는 법');
  expect(d.detail).toBe('메모: 확인했습니다');
  expect(d.to).toBe('/me/proposals/7');
  expect(d.icon).toBe('shown');
});

test('034 전 DB(operator_mode 칸 없음)에서도 운영자 화면 그대로', async () => {
  asOp();
  delete me().operator_mode;
  start('/me/settings');
  expect(await screen.findByRole('button', { name: '운영자 모드 끄기' })).toBeDefined();
  const menu = await openMenu();
  expect(await menu.findByRole('link', { name: '관리' })).toBeDefined();
});
