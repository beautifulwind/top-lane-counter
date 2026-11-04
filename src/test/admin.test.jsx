import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeLogin, fakeProposal, fakeState } from './fakeSupabase';
import { clickMenu, openMenu } from './menu';

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
  expect((await openMenu()).queryByRole('link', { name: '관리' })).toBeNull();
  cleanup();
  start('/champion/Darius/counter/Quinn');
  await screen.findByRole('link', { name: '문서 수정 제안' });
  expect(screen.queryByRole('link', { name: '수정 기록' })).toBeNull();
  cleanup();
  start('/champion/Darius');
  await screen.findByRole('link', { name: '+ 카운터 등록' });
  expect(screen.queryByRole('link', { name: '순서 변경' })).toBeNull();
});

test('운영자: [관리] → 대기 목록 → [자세히] → 바뀐 칸만 비교, [승인]은 메모를 써야 확정되고 approve_proposal(메모)', async () => {
  TABLES.edit_proposals.push(fakeProposal());
  asOperator();
  vi.spyOn(window, 'confirm');
  start('/');
  await clickMenu('관리');
  const row = await screen.findByRole('listitem', { name: '[문서 수정] 퀸으로 다리우스 잡는 법' });
  expect(within(row).getByText('기존유저')).toBeDefined();
  fireEvent.click(within(row).getByRole('link', { name: '자세히' }));
  expect(where()).toBe('/admin/proposals/501');

  const summary = await screen.findByRole('region', { name: '한 줄 요약 변경' });
  expect(summary.querySelector('.diff-line.del').textContent).toBe('− 사거리로 일방적인 견제\n');
  expect(summary.querySelector('.diff-line.add').textContent).toBe('+ 고친 요약\n');
  const cautions = screen.getByRole('region', { name: '특이사항 변경' });
  expect([...cautions.querySelectorAll('.diff-line')].map((l) => l.className)).toEqual(['diff-line same', 'diff-line add']);
  expect(within(screen.getByRole('region', { name: '4레벨 변경' })).getByText('삭제')).toBeDefined(); // 제안에서 4레벨이 빠짐
  expect(screen.getByText(/바뀌지 않은 칸 6개 보기/)).toBeDefined();
  expect(screen.queryByText(/문서가 다른 승인으로 바뀌었어요/)).toBeNull();

  fireEvent.click(screen.getByRole('button', { name: '승인' }));
  const ok = screen.getByRole('button', { name: '승인 확정' });
  expect(ok.disabled).toBe(true);
  fireEvent.change(screen.getByLabelText(/승인 메모/), { target: { value: '   ' } });
  expect(ok.disabled).toBe(true);
  fireEvent.change(screen.getByLabelText(/승인 메모/), { target: { value: ' 좋은 수정이에요 ' } });
  fireEvent.click(ok);
  expect(await screen.findByText(/승인했어요: \[문서 수정\] 퀸으로 다리우스 잡는 법/)).toBeDefined();
  expect(fakeState.rpcCalls).toEqual([{ name: 'approve_proposal', args: { p_id: 501, p_note: '좋은 수정이에요', p_content: null, p_build: null, p_version: 1 } }]);
  expect(where()).toBe('/admin');
  expect(window.confirm).not.toHaveBeenCalled();
});

test('거절: [거절] → 사유가 비어 있으면 [거절 확정]이 안 눌리고, 사유를 쓰면 reject_proposal로 보낸다', async () => {
  TABLES.edit_proposals.push(fakeProposal());
  asOperator();
  start('/admin/proposals/501');
  fireEvent.click(await screen.findByRole('button', { name: '거절' }));
  const reject = screen.getByRole('button', { name: '거절 확정' });
  expect(reject.disabled).toBe(true);
  fireEvent.change(screen.getByLabelText(/거절 사유/), { target: { value: '   ' } });
  expect(reject.disabled).toBe(true);
  fireEvent.change(screen.getByLabelText(/거절 사유/), { target: { value: '근거가 부족해요' } });
  fireEvent.click(reject);
  expect(await screen.findByText(/거절했어요/)).toBeDefined();
  expect(fakeState.rpcCalls).toEqual([{ name: 'reject_proposal', args: { p_id: 501, p_reason: '근거가 부족해요', p_version: 1 } }]);
});

test('제안 후 문서가 바뀌었으면 경고, DB가 거부하면 그 이유를 보여 준다', async () => {
  TABLES.edit_proposals.push(fakeProposal({ base_revision_id: 6 }));
  asOperator();
  fakeState.rpcError = '이미 처리된 제안이에요.';
  start('/admin/proposals/501');
  expect(await screen.findByText(/이 제안을 쓴 뒤에 문서가 다른 승인으로 바뀌었어요/)).toBeDefined();
  fireEvent.click(screen.getByRole('button', { name: '승인' }));
  fireEvent.change(screen.getByLabelText(/승인 메모/), { target: { value: '확인함' } });
  fireEvent.click(screen.getByRole('button', { name: '승인 확정' }));
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
  expect(await screen.findByRole('heading', { name: '[새 카운터] 가렌으로 다리우스 잡는 법' })).toBeDefined();
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

test('수정 기록: 버전 목록과 지금 버전 표시, 예전 버전 비교, 메모를 써야 되돌리기 확정 → revert_doc(메모)', async () => {
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

  fireEvent.click(within(v1).getByRole('button', { name: '이 버전으로 되돌리기' }));
  const ok = within(v1).getByRole('button', { name: '되돌리기 확정' });
  expect(ok.disabled).toBe(true);
  fireEvent.click(within(v1).getByRole('button', { name: '취소' })); // 취소하면 닫힘
  expect(within(v1).queryByRole('button', { name: '되돌리기 확정' })).toBeNull();
  fireEvent.click(within(v1).getByRole('button', { name: '이 버전으로 되돌리기' }));
  fireEvent.change(within(v1).getByLabelText(/되돌리기 메모/), { target: { value: '처음 버전이 정확해요' } });
  fireEvent.click(within(v1).getByRole('button', { name: '되돌리기 확정' }));
  expect(await screen.findByText('1번 버전으로 되돌렸어요.')).toBeDefined();
  expect(fakeState.rpcCalls).toEqual([{ name: 'revert_doc', args: { p_revision_id: 5, p_note: '처음 버전이 정확해요' } }]);
});

test('대기 목록 줄에서 바로: [승인]·[거절]은 그 자리에 메모 입력, 메모를 써야 확정 (확인 창 없음)', async () => {
  TABLES.edit_proposals.push(fakeProposal(), fakeProposal({ id: 502, counter_champion: 'Quinn', created_at: '2026-11-01T11:00:00Z' }));
  asOperator();
  vi.spyOn(window, 'confirm');
  start('/admin');
  const [row1] = await screen.findAllByRole('listitem', { name: '[문서 수정] 퀸으로 다리우스 잡는 법' });

  fireEvent.click(within(row1).getByRole('button', { name: '승인' }));
  const ok = within(row1).getByRole('button', { name: '승인 확정' });
  expect(ok.disabled).toBe(true);
  // 다른 버튼을 누르면 입력창이 바뀐다 (한 줄에 하나만)
  fireEvent.click(within(row1).getByRole('button', { name: '거절' }));
  expect(within(row1).queryByRole('button', { name: '승인 확정' })).toBeNull();
  fireEvent.click(within(row1).getByRole('button', { name: '승인' }));
  fireEvent.change(within(row1).getByLabelText(/승인 메모/), { target: { value: '좋아요' } });
  fireEvent.click(within(row1).getByRole('button', { name: '승인 확정' }));
  expect(await screen.findByText('승인했어요: [문서 수정] 퀸으로 다리우스 잡는 법')).toBeDefined();
  expect(where()).toBe('/admin');
  expect(fakeState.rpcCalls).toEqual([{ name: 'approve_proposal', args: { p_id: 501, p_note: '좋아요', p_content: null, p_build: null, p_version: 1 } }]);

  fakeState.rpcCalls.length = 0;
  const again = (await screen.findAllByRole('listitem', { name: '[문서 수정] 퀸으로 다리우스 잡는 법' }))[1];
  fireEvent.click(within(again).getByRole('button', { name: '거절' }));
  fireEvent.change(within(again).getByLabelText(/거절 사유/), { target: { value: '근거 부족' } });
  fireEvent.click(within(again).getByRole('button', { name: '거절 확정' }));
  expect(await screen.findByText('거절했어요: [문서 수정] 퀸으로 다리우스 잡는 법')).toBeDefined();
  expect(fakeState.rpcCalls).toEqual([{ name: 'reject_proposal', args: { p_id: 502, p_reason: '근거 부족', p_version: 1 } }]);
  expect(window.confirm).not.toHaveBeenCalled();
});

test('대기 목록: 바로 승인하면 위험한 제안은 줄에서 [승인]이 잠기고 이유를 보여 준다 (거절은 가능)', async () => {
  TABLES.edit_proposals.push(
    fakeProposal({ id: 701, base_revision_id: 6 }), // 제안 뒤에 문서가 바뀜 (지금 버전 7)
    fakeProposal({ id: 702, type: 'new_counter', counter_id: null, created_at: '2026-11-01T11:00:00Z' }), // 퀸은 이미 공개
    fakeProposal({ id: 703, type: 'new_counter', counter_champion: 'Garen', counter_id: null, created_at: '2026-11-01T12:00:00Z' }), // 정상
  );
  asOperator();
  start('/admin');
  const stale = await screen.findByRole('listitem', { name: '[문서 수정] 퀸으로 다리우스 잡는 법' });
  expect(within(stale).getByText('제안 뒤에 문서가 바뀌었어요. 내용을 [자세히]에서 확인해 주세요.')).toBeDefined();
  expect(within(stale).getByRole('button', { name: '승인' }).disabled).toBe(true);
  expect(within(stale).getByRole('button', { name: '거절' }).disabled).toBe(false);
  expect(within(stale).getByRole('link', { name: '자세히' }).getAttribute('href')).toBe('/admin/proposals/701');
  const dup = screen.getByRole('listitem', { name: '[새 카운터] 퀸으로 다리우스 잡는 법' });
  expect(within(dup).getByText(/같은 카운터가 이미 공개돼 있어요/)).toBeDefined();
  expect(within(dup).getByRole('button', { name: '승인' }).disabled).toBe(true);
  const fine = screen.getByRole('listitem', { name: '[새 카운터] 가렌으로 다리우스 잡는 법' });
  expect(within(fine).getByRole('button', { name: '승인' }).disabled).toBe(false);
  expect(within(fine).queryByText(/자세히\]에서 확인/)).toBeNull();
});
