import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { FAKE_PROPOSAL_BUILD, TABLES, fakeLogin, fakeProposal, fakeState } from './fakeSupabase';

const COUNTERS = TABLES.counters.map((c) => ({ ...c }));
const BUILDS = TABLES.builds.map((b) => ({ ...b }));
beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
  TABLES.counters = COUNTERS.map((c) => ({ ...c }));
  TABLES.builds = BUILDS.map((b) => ({ ...b }));
});

function Where() { const l = useLocation(); return <output data-testid="where">{l.pathname}</output>; }
const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /><Where /></MemoryRouter>);
const where = () => screen.getByTestId('where').textContent;
const asOperator = () => fakeLogin('u-op', { nickname: '영자(운)', role: 'admin', level: 0, main_title: null });
const op = { nickname: '영자(운)', level: 0, main_title: null };
const GAREN_DOC = { summary: '가렌 요약', level_notes: { 1: 'a', 2: 'b', 3: 'c', 6: 'd', 9: 'e', 11: 'f' }, lane_cautions: '숨긴 주의사항' };

/** 운영자가 숨긴 "가렌 → 다리우스" 카운터 (id 3) + 빌드 1개 + 숨김 기록. origin = 그 카운터를 만든 제안(없으면 초기 데이터) */
function hiddenGaren(origin = {}) {
  TABLES.counters.push({
    id: 3, target_champion: 'Darius', counter_champion: 'Garen', sort_order: 2, status: 'hidden',
    matchup_docs: { counter_id: 3, ...GAREN_DOC, updated_at: null, revision_id: 9 },
  });
  TABLES.builds.push({ ...BUILDS[1], id: 301, counter_id: 3 });
  TABLES.counter_status_log.push({ id: 2, counter_id: 3, action: 'hide', reason: '잘못 승인했어요', created_at: '2026-11-03T00:00:00Z', actor: op });
  if (origin) {
    TABLES.edit_proposals.push(fakeProposal({
      id: 7, type: 'new_counter', counter_champion: 'Garen', counter_id: 3, status: 'revoked', content: GAREN_DOC,
      revoke_reason: '잘못 승인했어요', revoked_at: '2026-11-03T00:00:00Z', ...origin,
    }));
  }
}
const row = () => screen.findByRole('listitem', { name: '가렌으로 다리우스 잡는 법' });

test('미리보기: 운영자만 숨긴 문서(딜교·특이사항·빌드)를 읽기 전용으로 본다', async () => {
  hiddenGaren();
  asOperator();
  start('/admin');
  fireEvent.click(within(await row()).getByRole('link', { name: '미리보기' }));
  expect(await screen.findByText('숨긴 카운터 미리보기 — 다른 사람에게는 보이지 않아요.')).toBeDefined();
  expect(where()).toBe('/admin/preview/Darius/Garen');
  expect(screen.getByRole('heading', { name: '가렌으로 다리우스 잡는 법' })).toBeDefined();
  expect(screen.getByText('숨긴 주의사항')).toBeDefined();
  expect(screen.getByText('9레벨').nextSibling.textContent).toBe('e');
  expect(screen.getByText(/탑고수/)).toBeDefined(); // 빌드 작성자
  expect(screen.queryByRole('link', { name: '문서 수정 제안' })).toBeNull();
  cleanup();
  start('/admin/preview/Darius/Quinn'); // 공개 중인 카운터는 미리보기 대상이 아님
  expect(await screen.findByText(/숨긴 카운터가 아니에요/)).toBeDefined();
});

test('미리보기·삭제 화면은 일반 유저에게 막혀 있다', async () => {
  hiddenGaren();
  fakeLogin('u-old');
  start('/admin/preview/Darius/Garen');
  expect(await screen.findByText('운영자만 볼 수 있어요.')).toBeDefined();
  cleanup();
  start('/admin/delete/Darius/Garen');
  expect(await screen.findByText('운영자만 볼 수 있어요.')).toBeDefined();
});

test('재검토 요청: 줄에서 바로 메모를 적어야 확정되고 request_revision으로 보낸다 (확인 창 없음)', async () => {
  hiddenGaren();
  asOperator();
  vi.spyOn(window, 'confirm');
  start('/admin');
  const r = await row();
  expect(within(r).getByText(/제안자:/).textContent).toMatch(/기존유저/);
  fireEvent.click(within(r).getByRole('button', { name: '재검토 요청' }));
  const send = within(r).getByRole('button', { name: '재검토 요청 확정' });
  expect(send.disabled).toBe(true);
  fireEvent.change(within(r).getByLabelText(/재검토 요청 메모/), { target: { value: '  9레벨을 고쳐 주세요 ' } });
  fireEvent.click(send);
  await vi.waitFor(() =>
    expect(fakeState.rpcCalls).toEqual([{ name: 'request_revision', args: { p_counter_id: 3, p_note: '9레벨을 고쳐 주세요' } }]));
  expect(await screen.findByText('재검토를 요청했어요: 가렌으로 다리우스 잡는 법')).toBeDefined();
  expect(window.confirm).not.toHaveBeenCalled();
});

test('제안 없이 생긴 카운터는 재검토 요청 버튼이 잠긴다', async () => {
  hiddenGaren(null);
  asOperator();
  start('/admin');
  const r = await row();
  expect(within(r).getByText('제안 없이 생긴 카운터 (재검토 요청 불가)')).toBeDefined();
  expect(within(r).getByRole('button', { name: '재검토 요청' }).disabled).toBe(true);
  expect(within(r).getByRole('link', { name: '완전 삭제' })).toBeDefined();
});

test('상태 표시: 재검토 요청 중 / 다시 제출돼 승인 대기 중이면 [다시 공개]·[완전 삭제] 잠김', async () => {
  hiddenGaren({ status: 'revision_requested', revision_note: '고쳐 주세요' });
  asOperator();
  start('/admin');
  let r = await row();
  expect(within(r).getByText('재검토 요청 중 (제안자 수정 대기)')).toBeDefined();
  expect(within(r).getByRole('button', { name: '재검토 요청' }).disabled).toBe(true);
  expect(within(r).getByRole('button', { name: '다시 공개' }).disabled).toBe(false);
  cleanup();
  TABLES.edit_proposals[0].status = 'pending';
  TABLES.edit_proposals[0].resubmitted_at = '2026-11-04T00:00:00Z';
  start('/admin');
  r = await row();
  expect(within(r).getByRole('link', { name: '다시 보냄 (승인 대기 목록에 있음)' }).getAttribute('href')).toBe('/admin/proposals/7');
  expect(within(r).getByRole('button', { name: '다시 공개' }).disabled).toBe(true);
  expect(within(r).getByRole('button', { name: '완전 삭제' }).disabled).toBe(true);
  expect(within(r).queryByRole('link', { name: '완전 삭제' })).toBeNull();
  // 승인 대기 목록에도 "재검토 후 다시 낸 제안"으로 보인다
  expect(screen.getByText('재검토 후 다시 낸 제안')).toBeDefined();
});

/** 재검토 요청을 받은 기존유저 + 안 읽은 알림 1개 */
function revisionRequested() {
  hiddenGaren({ proposer_id: 'u-old', status: 'revision_requested', revision_note: '9레벨을 고쳐 주세요', revision_requested_at: '2026-11-04T00:00:00Z' });
  TABLES.notifications.push(
    { id: 41, user_id: 'u-old', kind: 'revision_request', proposal_id: 7, message: '9레벨을 고쳐 주세요', created_at: '2026-11-04T00:00:00Z', read_at: null },
    { id: 40, user_id: 'u-old', kind: 'revision_request', proposal_id: 7, message: '예전', created_at: '2026-11-02T00:00:00Z', read_at: '2026-11-02T01:00:00Z' },
    { id: 42, user_id: 'u-x', kind: 'revision_request', proposal_id: 99, message: '남의 것', created_at: '2026-11-04T00:00:00Z', read_at: null },
  );
  fakeLogin('u-old', { nickname: '기존유저' });
}

test('빨간 점: /me에서 알림을 확인하면 꺼지고, 재검토 요청 내용과 [고쳐서 다시 보내기]은 남는다', async () => {
  revisionRequested();
  start('/');
  // 빨간 점은 [마이페이지] 버튼에 (읽은 것·남의 것은 세지 않음)
  const mypage = await screen.findByRole('link', { name: '마이페이지, 새 알림 1개' });
  expect(mypage.querySelector('.alert-dot')).not.toBeNull();
  fireEvent.click(mypage);
  expect(where()).toBe('/me');
  const r = (await screen.findByText('운영자 메모: 9레벨을 고쳐 주세요')).closest('li');
  expect(within(r).getByText('새 알림')).toBeDefined();
  await vi.waitFor(() => expect(screen.getByRole('link', { name: '마이페이지' }).querySelector('.alert-dot')).toBeNull()); // 확인 → 꺼짐
  expect(fakeState.rpcCalls).toEqual([{ name: 'mark_notifications_read', args: { p_ids: [41] } }]);

  // 다른 페이지에 갔다가 다시 와도 점은 꺼져 있고, 요청 내용과 버튼은 그대로
  fireEvent.click(screen.getByRole('link', { name: '탑신병자' }));
  fireEvent.click(await screen.findByRole('link', { name: '마이페이지' }));
  const again = (await screen.findByText('운영자 메모: 9레벨을 고쳐 주세요')).closest('li');
  expect(within(again).getByText('재검토 요청', { selector: '.status-badge' })).toBeDefined();
  expect(within(again).getByRole('link', { name: '고쳐서 다시 보내기' })).toBeDefined();
  expect(within(again).queryByText('새 알림')).toBeNull();
  expect(screen.getByRole('link', { name: '마이페이지' }).querySelector('.alert-dot')).toBeNull();
  expect(fakeState.rpcCalls).toHaveLength(1); // 읽을 게 없으면 부르지 않음
});

test('제안자: /me의 [고쳐서 다시 보내기] → 숨긴 시점 문서로 채워진 폼 → resubmit_proposal', async () => {
  revisionRequested();
  start('/me');
  const r = (await screen.findByText('운영자 메모: 9레벨을 고쳐 주세요')).closest('li');
  expect(within(r).queryByRole('link', { name: '문서 보기' })).toBeNull(); // 숨긴 카운터라 문서 링크 없음
  fireEvent.click(within(r).getByRole('link', { name: '고쳐서 다시 보내기' }));
  expect(await screen.findByRole('heading', { name: '가렌으로 다리우스 잡는 법 — 고쳐서 다시 보내기' })).toBeDefined();
  expect(screen.getByLabelText('한 줄 요약 (필수)').value).toBe('가렌 요약');
  fakeState.rpcCalls.length = 0;
  fireEvent.click(screen.getByRole('button', { name: '다시 보내기' }));
  expect(screen.getByRole('alert').textContent).toBe('고친 내용이 없어요. 운영자 메모를 보고 글이나 빌드를 고쳐 주세요.');
  expect(fakeState.rpcCalls).toEqual([]);

  fireEvent.change(screen.getByLabelText('9레벨'), { target: { value: ' 9렙 고침 ' } });
  fireEvent.click(screen.getByRole('button', { name: '다시 보내기' }));
  expect(await screen.findByText(/고친 내용을 다시 보냈어요/)).toBeDefined();
  expect(where()).toBe('/me');
  expect(fakeState.rpcCalls[0]).toEqual({
    name: 'resubmit_proposal',
    args: { p_id: 7, p_content: { ...GAREN_DOC, level_notes: { ...GAREN_DOC.level_notes, 9: '9렙 고침' } }, p_build: FAKE_PROPOSAL_BUILD },
  });
});

test('/me: 승인된 제안에는 승인 메모가 보인다', async () => {
  TABLES.edit_proposals.push(fakeProposal({ status: 'approved', approve_note: '좋은 수정이에요', reviewed_at: '2026-11-02T00:00:00Z' }));
  fakeLogin('u-old', { nickname: '기존유저' });
  start('/me');
  expect(await screen.findByText('승인 메모: 좋은 수정이에요')).toBeDefined();
});

test('고칠 수 없는 상태(승인 취소)면 고치기 화면은 안내만 보여 준다 (옛 다시 제출 주소도 새 주소로)', async () => {
  hiddenGaren({ proposer_id: 'u-old' });
  fakeLogin('u-old', { nickname: '기존유저' });
  start('/me/resubmit/7');
  expect(await screen.findByText(/지금은 고칠 수 없는 제안이에요/)).toBeDefined();
  expect(where()).toBe('/me/proposals/7/edit');
  expect(screen.queryByRole('button', { name: '다시 보내기' })).toBeNull();
});

test('제안 검토: 다시 낸 제안은 메모와 "숨긴 문서 → 고친 내용" 비교, 승인 가능', async () => {
  hiddenGaren({ status: 'pending', resubmitted_at: '2026-11-04T00:00:00Z', revision_note: '9레벨을 고쳐 주세요',
    content: { ...GAREN_DOC, summary: '가렌 고친 요약' } });
  asOperator();
  start('/admin/proposals/7');
  expect(await screen.findByRole('heading', { name: '[재검토 후 다시 낸 제안] 가렌으로 다리우스 잡는 법' })).toBeDefined();
  expect(screen.getByText('보낸 재검토 메모: 9레벨을 고쳐 주세요')).toBeDefined();
  expect(screen.getByRole('heading', { name: '바뀐 부분 (숨긴 문서 → 고친 내용)' })).toBeDefined();
  expect(screen.queryByText(/운영자가 숨긴 카운터예요/)).toBeNull();
  const approve = screen.getByRole('button', { name: '승인' });
  expect(approve.disabled).toBe(false);
  fireEvent.click(approve);
  expect(screen.getByText('승인하면 고친 내용으로 다시 공개돼요 (목록 맨 뒤).')).toBeDefined();
  fireEvent.change(screen.getByLabelText(/승인 메모/), { target: { value: '고친 내용 확인' } });
  fireEvent.click(screen.getByRole('button', { name: '승인 확정' }));
  expect(await screen.findByText('승인하고 다시 공개했어요: [재검토 후 다시 낸 제안] 가렌으로 다리우스 잡는 법')).toBeDefined();
  expect(fakeState.rpcCalls).toEqual([{ name: 'approve_proposal', args: { p_id: 7, p_note: '고친 내용 확인', p_content: null, p_build: null, p_version: 1 } }]);
});

test('완전 삭제: 지워지는 개수를 보여 주고, 사유 + 챔피언 이름을 정확히 입력해야 눌리며 delete_counter (확인 창 없음)', async () => {
  hiddenGaren();
  TABLES.doc_revisions.push({ id: 9, counter_id: 3 }, { id: 8, counter_id: 3 });
  TABLES.build_votes.push({ build_id: 301, user_id: 'u-x', value: 1 }, { build_id: 102, user_id: 'u-y', value: 1 });
  asOperator();
  start('/admin');
  fireEvent.click(within(await row()).getByRole('link', { name: '완전 삭제' }));
  expect(await screen.findByRole('heading', { name: '카운터 완전 삭제' })).toBeDefined();
  const list = screen.getByRole('list', { name: '함께 지워지는 것' });
  expect(list.textContent).toMatch(/수정 기록 2개/);
  expect(list.textContent).toMatch(/빌드 1개와 따봉 1개/);
  expect(list.textContent).toMatch(/제안 1개/);

  const del = screen.getByRole('button', { name: '완전 삭제' });
  const reason = screen.getByLabelText('삭제 사유 (필수)');
  const confirmName = screen.getByLabelText(/챔피언 이름/);
  expect(del.disabled).toBe(true);
  fireEvent.change(confirmName, { target: { value: '가렌' } });
  expect(del.disabled).toBe(true); // 사유 없음
  fireEvent.change(reason, { target: { value: '중복 카운터' } });
  expect(del.disabled).toBe(false);
  fireEvent.change(confirmName, { target: { value: 'Garen' } });
  expect(del.disabled).toBe(true); // 영문 ID가 아니라 화면에 보이는 이름 그대로
  fireEvent.change(confirmName, { target: { value: '가렌' } });

  vi.spyOn(window, 'confirm');
  fireEvent.click(del);
  expect(await screen.findByText('삭제했어요: 가렌으로 다리우스 잡는 법')).toBeDefined();
  expect(where()).toBe('/admin');
  expect(fakeState.rpcCalls).toEqual([
    { name: 'delete_counter', args: { p_counter_id: 3, p_confirm: 'Garen', p_reason: '중복 카운터' } },
  ]);
  expect(window.confirm).not.toHaveBeenCalled();
});

test('완전 삭제를 DB가 거부하면 이유를 보여 주고 화면에 머문다 / 숨긴 카운터가 아니면 삭제 화면이 안 열린다', async () => {
  hiddenGaren();
  asOperator();
  fakeState.rpcError = '제안자가 고쳐서 다시 낸 제안이 승인 대기 중이에요. 그 제안부터 승인하거나 거절해 주세요.';
  start('/admin/delete/Darius/Garen');
  fireEvent.change(await screen.findByLabelText('삭제 사유 (필수)'), { target: { value: '중복' } });
  fireEvent.change(screen.getByLabelText(/챔피언 이름/), { target: { value: '가렌' } });
  fireEvent.click(screen.getByRole('button', { name: '완전 삭제' }));
  expect(await screen.findByText(/승인 대기 중이에요/)).toBeDefined();
  expect(where()).toBe('/admin/delete/Darius/Garen');
  cleanup();
  start('/admin/delete/Darius/Quinn');
  expect(await screen.findByText(/숨긴 카운터만 삭제할 수 있어요/)).toBeDefined();
  expect(screen.queryByRole('button', { name: '완전 삭제' })).toBeNull();
});

test('운영자 페이지: 삭제 기록(누가·언제·왜·어떤 매치업·원래 제안자·지운 개수)', async () => {
  TABLES.counter_deletions.push({
    id: 1, target_champion: 'Darius', counter_champion: 'Garen', reason: '중복 카운터', deleted_at: '2026-11-05T00:00:00Z',
    proposals_count: 2, revisions_count: 3, builds_count: 1, votes_count: 4,
    deleter: op, proposer: { nickname: '기존유저', level: 1, main_title: null },
  });
  asOperator();
  start('/admin');
  expect(await screen.findByRole('heading', { name: '삭제 기록 (1)' })).toBeDefined();
  const r = screen.getByText('사유: 중복 카운터').closest('li');
  expect(within(r).getByText('가렌으로 다리우스 잡는 법')).toBeDefined();
  expect(r.textContent).toMatch(/삭제: Lv\.0 영자\(운\)/);
  expect(r.textContent).toMatch(/원래 제안자: Lv\.1 기존유저/);
  expect(r.textContent).toMatch(/제안 2 · 수정 기록 3 · 빌드 1 · 따봉 4/);
});
