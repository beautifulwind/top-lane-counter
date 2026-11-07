import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeLogin, fakeProposal, fakeState } from './fakeSupabase';

const COUNTERS = TABLES.counters.map((c) => ({ ...c }));
beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); TABLES.counters = COUNTERS.map((c) => ({ ...c })); });

function Where() { const l = useLocation(); return <output data-testid="where">{l.pathname}</output>; }
const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /><Where /></MemoryRouter>);
const where = () => screen.getByTestId('where').textContent;
const asOperator = () => fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0, main_title: null });
const op = { nickname: '영자', role: 'admin', level: 0, main_title: null };

/** 운영자가 숨긴 "가렌 → 다리우스" 카운터 (id 3) + 숨김 기록 */
function hiddenGaren() {
  TABLES.counters.push({
    id: 3, target_champion: 'Darius', counter_champion: 'Garen', sort_order: 2, status: 'hidden',
    matchup_docs: { counter_id: 3, summary: '가렌 요약', level_notes: { 1: 'a', 2: 'b', 3: 'c', 6: 'd', 9: 'e', 11: 'f' }, lane_cautions: '', updated_at: null, revision_id: 9 },
  });
  TABLES.counter_status_log.push(
    { id: 2, counter_id: 3, action: 'hide', reason: '잘못 승인했습니다', created_at: '2026-11-03T00:00:00Z', actor: op },
    { id: 1, counter_id: 3, action: 'restore', reason: null, created_at: '2026-11-02T00:00:00Z', actor: op },
  );
}

test('일반 유저: 매치업 문서의 [카운터 숨기기]와 챔피언 목록의 [숨기기]가 안 보인다', async () => {
  fakeLogin('u-old');
  start('/champion/Darius/counter/Quinn');
  await screen.findByRole('link', { name: '문서 수정 제안' });
  expect(screen.queryByRole('button', { name: '카운터 숨기기' })).toBeNull();
  cleanup();
  start('/champion/Darius');
  await screen.findByRole('link', { name: /퀸/ });
  expect(screen.queryByRole('button', { name: /숨기기/ })).toBeNull();
});

test('운영자: 매치업 문서 [카운터 숨기기] → 그 자리에 사유 입력, 사유를 써야 [숨기기 확정] → 챔피언 문서로 (확인 창 없음)', async () => {
  asOperator();
  vi.spyOn(window, 'confirm');
  start('/champion/Darius/counter/Quinn');
  fireEvent.click(await screen.findByRole('button', { name: '카운터 숨기기' }));
  const ok = screen.getByRole('button', { name: '숨기기 확정' });
  expect(ok.disabled).toBe(true);
  fireEvent.change(screen.getByLabelText(/숨기는 사유/), { target: { value: '  ' } });
  expect(ok.disabled).toBe(true);
  fireEvent.change(screen.getByLabelText(/숨기는 사유/), { target: { value: ' 잘못 승인했습니다 ' } });
  fireEvent.click(ok);
  expect(await screen.findByText('숨겼습니다: 퀸으로 다리우스 이기는 법')).toBeDefined();
  expect(where()).toBe('/champion/Darius');
  expect(fakeState.rpcCalls).toEqual([{ name: 'hide_counter', args: { p_counter_id: 1, p_reason: '잘못 승인했습니다' } }]);
  expect(window.confirm).not.toHaveBeenCalled();
});

test('운영자: 챔피언 문서 목록 줄의 [숨기기] → 사유 입력 → 확정하면 hide_counter, [취소]·Esc로 닫힘', async () => {
  asOperator();
  start('/champion/Darius');
  const hideBtn = await screen.findByRole('button', { name: '퀸 숨기기' });
  fireEvent.click(hideBtn);
  expect(hideBtn.getAttribute('aria-expanded')).toBe('true');
  fireEvent.click(screen.getByRole('button', { name: '취소' }));
  expect(screen.queryByRole('button', { name: '숨기기 확정' })).toBeNull();
  fireEvent.click(hideBtn);
  fireEvent.keyDown(screen.getByLabelText(/퀸 숨기는 사유/), { key: 'Escape' });
  expect(screen.queryByRole('button', { name: '숨기기 확정' })).toBeNull();

  fireEvent.click(hideBtn);
  fireEvent.change(screen.getByLabelText(/퀸 숨기는 사유/), { target: { value: '중복' } });
  fireEvent.click(screen.getByRole('button', { name: '숨기기 확정' }));
  expect(await screen.findByText('숨겼습니다: 퀸으로 다리우스 이기는 법')).toBeDefined();
  expect(where()).toBe('/champion/Darius');
  expect(fakeState.rpcCalls).toEqual([{ name: 'hide_counter', args: { p_counter_id: 1, p_reason: '중복' } }]);
});

test('숨기기를 DB가 거부하면 이유를 보여 주고 입력창이 그대로 남는다', async () => {
  asOperator();
  fakeState.rpcError = '이미 숨긴 카운터입니다.';
  start('/champion/Darius/counter/Quinn');
  fireEvent.click(await screen.findByRole('button', { name: '카운터 숨기기' }));
  fireEvent.change(screen.getByLabelText(/숨기는 사유/), { target: { value: '실수' } });
  fireEvent.click(screen.getByRole('button', { name: '숨기기 확정' }));
  expect(await screen.findByText('이미 숨긴 카운터입니다.')).toBeDefined();
  expect(where()).toBe('/champion/Darius/counter/Quinn');
  expect(screen.getByLabelText(/숨기는 사유/).value).toBe('실수');
});

test('운영자 페이지: 숨긴 카운터와 사유·기록이 보이고, [다시 공개]는 메모를 써야 확정 → restore_counter(메모)', async () => {
  hiddenGaren();
  asOperator();
  vi.spyOn(window, 'confirm');
  start('/admin');
  const row = await screen.findByRole('listitem', { name: '가렌으로 다리우스 이기는 법' });
  expect(within(row).getByText('사유: 잘못 승인했습니다')).toBeDefined();
  expect(within(row).getByText('숨김·공개 기록 2개')).toBeDefined();
  expect(row.querySelector('.log-list').textContent).toMatch(/숨김 · Lv\.0 \(운\)영자 · 잘못 승인했습니다/);
  expect(within(row).queryByLabelText(/다시 공개 메모/)).toBeNull(); // 누를 때만 열림

  fireEvent.click(within(row).getByRole('button', { name: '다시 공개' }));
  const ok = within(row).getByRole('button', { name: '다시 공개 확정' });
  expect(ok.disabled).toBe(true);
  fireEvent.change(within(row).getByLabelText('다시 공개 메모 (필수)'), { target: { value: ' 확인해 보니 맞음 ' } });
  fireEvent.click(ok);
  await vi.waitFor(() => expect(fakeState.rpcCalls).toEqual([{ name: 'restore_counter', args: { p_counter_id: 3, p_note: '확인해 보니 맞음' } }]));
  expect(await screen.findByText('다시 공개했습니다: 가렌으로 다리우스 이기는 법')).toBeDefined();
  expect(window.confirm).not.toHaveBeenCalled();
});

test('/me: 승인 취소된 제안은 "승인 취소"와 사유를 보여 주고 링크는 없다', async () => {
  TABLES.edit_proposals.push(fakeProposal({
    id: 7, type: 'new_counter', counter_champion: 'Garen', counter_id: 3, status: 'revoked',
    reviewed_at: '2026-11-02T00:00:00Z', revoke_reason: '잘못 승인했습니다', revoked_at: '2026-11-03T00:00:00Z',
  }));
  fakeLogin('u-old');
  start('/me');
  const row = (await screen.findByText('승인 취소')).closest('li');
  expect(within(row).getByText(/승인 취소 사유: 잘못 승인했습니다/)).toBeDefined();
  expect(within(row).queryByRole('link', { name: '문서 보기' })).toBeNull();
  expect(within(row).queryByRole('link', { name: '고치기' })).toBeNull();
  expect(within(row).getByRole('link', { name: '자세히' }).getAttribute('href')).toBe('/me/proposals/7');
});

test('제안 검토: 숨긴 카운터의 수정 제안·같은 매치업 새 카운터 제안은 경고 + 승인 잠금 (거절은 가능)', async () => {
  hiddenGaren();
  TABLES.edit_proposals.push(
    fakeProposal({ id: 701, counter_champion: 'Garen', counter_id: 3, base_revision_id: 9 }),
    fakeProposal({ id: 702, type: 'new_counter', counter_champion: 'Garen', counter_id: null }),
    fakeProposal({ id: 703, type: 'new_counter', counter_champion: 'Garen', counter_id: 3, status: 'revoked', revoke_reason: '잘못 승인했습니다', revoked_at: '2026-11-03T00:00:00Z' }),
  );
  asOperator();
  start('/admin/proposals/701');
  expect(await screen.findByText('숨긴 카운터의 제안입니다. 승인할 수 없으니 거절해 주세요.')).toBeDefined();
  expect(screen.getByRole('button', { name: '승인' }).disabled).toBe(true);
  fireEvent.click(screen.getByRole('button', { name: '거절' }));
  fireEvent.change(screen.getByLabelText(/거절 사유/), { target: { value: '숨긴 카운터' } });
  expect(screen.getByRole('button', { name: '거절 확정' }).disabled).toBe(false);
  cleanup();
  start('/admin/proposals/702');
  expect(await screen.findByText(/운영자가 숨긴 카운터입니다. 살리려면/)).toBeDefined();
  expect(screen.getByRole('button', { name: '승인' }).disabled).toBe(true);
  expect(screen.queryByText(/이미 같은 카운터가 공개돼 있습니다/)).toBeNull();
  cleanup();
  start('/admin/proposals/703');
  expect(await screen.findByText(/승인 취소 사유: 잘못 승인했습니다/)).toBeDefined();
  expect(screen.queryByRole('button', { name: '승인' })).toBeNull();
  expect(screen.queryByText(/운영자가 숨긴 카운터입니다/)).toBeNull(); // 처리 끝난 제안엔 경고 없음
});
