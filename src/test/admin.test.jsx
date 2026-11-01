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
const asOperator = () => fakeLogin('u-op', { nickname: '영자(운)', role: 'admin', level: 0, main_title: null });

test('일반 유저: /admin은 "운영자만 볼 수 있어요", 상단 [관리]·[순서 변경]·[수정 기록]도 안 보인다', async () => {
  fakeLogin('u-old');
  start('/admin');
  expect(await screen.findByText('운영자만 볼 수 있어요.')).toBeDefined();
  expect(screen.queryByRole('link', { name: '관리' })).toBeNull();
  cleanup();
  start('/champion/Darius/counter/Quinn');
  await screen.findByRole('link', { name: '문서 수정 제안' });
  expect(screen.queryByRole('link', { name: '수정 기록' })).toBeNull();
  cleanup();
  start('/champion/Darius');
  await screen.findByRole('link', { name: '+ 새 카운터 제안' });
  expect(screen.queryByRole('link', { name: '순서 변경' })).toBeNull();
});

test('운영자: [관리] → 대기 목록 → 제안 열기 → 바뀐 칸만 비교해서 보여 주고 [승인]하면 approve_proposal을 부른다', async () => {
  TABLES.edit_proposals.push(fakeProposal());
  asOperator();
  start('/');
  fireEvent.click(await screen.findByRole('link', { name: '관리' }));
  const row = (await screen.findByRole('link', { name: /문서 수정 퀸\(으\)로 다리우스 잡는 법/ })).closest('li');
  expect(within(row).getByText('기존유저')).toBeDefined();
  fireEvent.click(within(row).getByRole('link'));
  expect(where()).toBe('/admin/proposals/501');

  const summary = await screen.findByRole('region', { name: '한 줄 요약 변경' });
  expect(summary.querySelector('.diff-line.del').textContent).toBe('− 사거리로 일방적인 견제\n');
  expect(summary.querySelector('.diff-line.add').textContent).toBe('+ 고친 요약\n');
  const cautions = screen.getByRole('region', { name: '라인전 주의사항 변경' });
  expect([...cautions.querySelectorAll('.diff-line')].map((l) => l.className)).toEqual(['diff-line same', 'diff-line add']);
  expect(within(screen.getByRole('region', { name: '4레벨 변경' })).getByText('삭제')).toBeDefined(); // 제안에서 4레벨이 빠짐
  expect(screen.getByText(/바뀌지 않은 칸 6개 보기/)).toBeDefined();
  expect(screen.queryByText(/문서가 다른 승인으로 바뀌었어요/)).toBeNull();

  fireEvent.click(screen.getByRole('button', { name: '승인' }));
  expect(await screen.findByText(/승인했어요: \[문서 수정\] 퀸\(으\)로 다리우스 잡는 법/)).toBeDefined();
  expect(fakeState.rpcCalls).toEqual([{ name: 'approve_proposal', args: { p_id: 501 } }]);
  expect(where()).toBe('/admin');
});

test('거절: 사유가 비어 있으면 [거절]이 안 눌리고, 사유를 쓰면 reject_proposal로 보낸다', async () => {
  TABLES.edit_proposals.push(fakeProposal());
  asOperator();
  start('/admin/proposals/501');
  const reject = await screen.findByRole('button', { name: '거절' });
  expect(reject.disabled).toBe(true);
  fireEvent.change(screen.getByLabelText(/거절 사유/), { target: { value: '   ' } });
  expect(reject.disabled).toBe(true);
  fireEvent.change(screen.getByLabelText(/거절 사유/), { target: { value: '근거가 부족해요' } });
  fireEvent.click(reject);
  expect(await screen.findByText(/거절했어요/)).toBeDefined();
  expect(fakeState.rpcCalls).toEqual([{ name: 'reject_proposal', args: { p_id: 501, p_reason: '근거가 부족해요' } }]);
});

test('제안 후 문서가 바뀌었으면 경고, DB가 거부하면 그 이유를 보여 준다', async () => {
  TABLES.edit_proposals.push(fakeProposal({ base_revision_id: 6 }));
  asOperator();
  fakeState.rpcError = '이미 처리된 제안이에요.';
  start('/admin/proposals/501');
  expect(await screen.findByText(/이 제안을 쓴 뒤에 문서가 다른 승인으로 바뀌었어요/)).toBeDefined();
  fireEvent.click(screen.getByRole('button', { name: '승인' }));
  expect(await screen.findByText('이미 처리된 제안이에요.')).toBeDefined();
  expect(where()).toBe('/admin/proposals/501');
});

test('새 카운터 제안: 전체가 "새로 씀"으로 보이고, 이미 공개된 카운터면 승인 버튼이 잠긴다', async () => {
  TABLES.edit_proposals.push(
    fakeProposal({ id: 601, type: 'new_counter', counter_champion: 'Garen', counter_id: null }),
    fakeProposal({ id: 602, type: 'new_counter', counter_champion: 'Quinn', counter_id: null }),
  );
  asOperator();
  start('/admin/proposals/601');
  expect(await screen.findByRole('heading', { name: '[새 카운터] 가렌(으)로 다리우스 잡는 법' })).toBeDefined();
  expect(within(screen.getByRole('region', { name: '한 줄 요약 변경' })).getByText('새로 씀')).toBeDefined();
  expect(screen.getByRole('button', { name: '승인' }).disabled).toBe(false);
  cleanup();
  start('/admin/proposals/602');
  expect(await screen.findByText(/이미 같은 카운터가 공개돼 있어요/)).toBeDefined();
  expect(screen.getByRole('button', { name: '승인' }).disabled).toBe(true);
});

test('순서 변경: [순서 변경] → ▲로 옮기고 [순서 저장]하면 새 순서 전체를 reorder_counters로 보낸다', async () => {
  TABLES.counters.push({
    id: 3, target_champion: 'Darius', counter_champion: 'Garen', sort_order: 2, status: 'approved',
    matchup_docs: { counter_id: 3, summary: '가렌 요약', level_notes: {}, lane_cautions: '', updated_at: null, revision_id: 9 },
  });
  asOperator();
  start('/champion/Darius');
  fireEvent.click(await screen.findByRole('link', { name: '순서 변경' }));
  expect(await screen.findByRole('heading', { name: '다리우스 카운터 순서' })).toBeDefined();
  const names = () => [...document.querySelectorAll('.order-name')].map((n) => n.textContent);
  expect(names()).toEqual(['퀸', '가렌']);
  const save = screen.getByRole('button', { name: '순서 저장' });
  expect(save.disabled).toBe(true);
  expect(screen.getByRole('button', { name: '퀸 위로' }).disabled).toBe(true);

  fireEvent.click(screen.getByRole('button', { name: '가렌 위로' }));
  expect(names()).toEqual(['가렌', '퀸']);
  fireEvent.click(save);
  expect(await screen.findByText('순서를 저장했어요.')).toBeDefined();
  expect(fakeState.rpcCalls).toEqual([{ name: 'reorder_counters', args: { p_target: 'Darius', p_ids: [3, 1] } }]);
  expect(save.disabled).toBe(true);
});

test('수정 기록: 버전 목록과 지금 버전 표시, 예전 버전 비교, 확인 후 revert_doc', async () => {
  TABLES.doc_revisions.push(
    { id: 7, kind: 'edit', content: {}, created_at: '2026-11-01T09:00:00Z', reverted_from: null,
      editor: { nickname: '기존유저', level: 1, main_title: null }, approver: { nickname: '영자(운)', level: 0, main_title: null } },
    { id: 5, kind: 'create', created_at: '2026-10-30T09:00:00Z', reverted_from: null, editor: null, approver: null,
      content: { summary: '처음 요약', level_notes: { 1: '1렙 내용', 2: '2렙', 3: '3렙', 6: '6렙', 9: '9렙', 11: '11렙' }, lane_cautions: 'E 사거리 주의' } },
  );
  TABLES.doc_revisions.forEach((r) => { r.counter_id = 1; });
  asOperator();
  start('/champion/Darius/counter/Quinn');
  fireEvent.click(await screen.findByRole('link', { name: '수정 기록' }));
  const v2 = await screen.findByRole('listitem', { name: '2번 버전' });
  expect(within(v2).getByText('지금 문서')).toBeDefined();
  expect(within(v2).queryByRole('button', { name: '이 버전으로 되돌리기' })).toBeNull();
  const v1 = screen.getByRole('listitem', { name: '1번 버전' });
  expect(v1.textContent).toMatch(/처음 작성/);

  fireEvent.click(within(v1).getByRole('button', { name: '지금 문서와 비교' }));
  const summary = within(v1).getByRole('region', { name: '한 줄 요약 변경' });
  expect(summary.querySelector('.diff-line.add').textContent).toBe('+ 처음 요약\n');

  vi.spyOn(window, 'confirm').mockReturnValueOnce(false).mockReturnValueOnce(true);
  fireEvent.click(within(v1).getByRole('button', { name: '이 버전으로 되돌리기' }));
  expect(fakeState.rpcCalls).toEqual([]);
  fireEvent.click(within(v1).getByRole('button', { name: '이 버전으로 되돌리기' }));
  expect(await screen.findByText('1번 버전으로 되돌렸어요.')).toBeDefined();
  expect(fakeState.rpcCalls).toEqual([{ name: 'revert_doc', args: { p_revision_id: 5 } }]);
});
