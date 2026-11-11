// 012: 승인 대기 제안·빌드의 처리 = [승인](고쳐서 승인 가능) [재검토 요청] [거절], 재검토 기다리는 중 [요청 취소] [거절]
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
// 승인 제도 화면은 지금 꺼 두었다(lib/features.js). 코드는 남아 있으므로 켠 채로 검사한다 — 끈 상태는 approvalOff.test.jsx
vi.mock('../lib/features', async (importOriginal) => ({ ...(await importOriginal()), APPROVAL_ENABLED: true }));
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { FAKE_PROPOSAL_BUILD, TABLES, fakeBuild, fakeLogin, fakeProposal, fakeState } from './fakeSupabase';
import { pick } from './buildHelpers';
import { sectionCount } from './sectionCount';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

function Where() { const l = useLocation(); return <output data-testid="where">{l.pathname + l.search}</output>; }
const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /><Where /></MemoryRouter>);
const where = () => screen.getByTestId('where').textContent;
const asOperator = () => fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0, main_title: null });
const asProposer = () => fakeLogin('u-old', { nickname: '기존유저' });
const click = (name, root = document.body) => fireEvent.click(within(root).getByRole('button', { name }));
const note = (label, value, root = document.body) => fireEvent.change(within(root).getByLabelText(label), { target: { value } });
const rpcCalls = (name) => fakeState.rpcCalls.filter((c) => c.name === name).map((c) => c.args);
const QUINN_ROW = '[문서 수정] 퀸으로 다리우스 이기는 법';

// ---------------- 운영자: 목록 줄 ----------------

test('/admin 승인 대기 줄: [승인] [재검토 요청] [거절], 줄 [승인]은 그대로 승인 + [내용 고치기]는 [자세히]의 편집기로', async () => {
  TABLES.edit_proposals.push(fakeProposal());
  asOperator();
  start('/admin');
  const row = await screen.findByRole('listitem', { name: QUINN_ROW });
  for (const name of ['승인', '재검토 요청', '거절']) expect(within(row).getByRole('button', { name })).toBeDefined();

  click('승인', row);
  expect(within(row).getByText('제안 그대로 승인합니다.')).toBeDefined();
  fireEvent.click(within(row).getByRole('link', { name: '내용 고치기 (고쳐서 승인)' }));
  expect(where()).toBe('/admin/proposals/501?approve=1');
  // [자세히]에서는 [승인]이 처음부터 고칠 수 있는 상태로 열려 있다
  expect((await screen.findByLabelText('한 줄 요약 (필수)')).value).toBe('고친 요약');
  expect(screen.getByText('고친 곳이 없습니다. 승인하면 제안 그대로 공개됩니다.')).toBeDefined();
});

test('/admin 승인 대기 줄: [재검토 요청]은 메모를 써야 확정 → request_proposal_revision', async () => {
  TABLES.edit_proposals.push(fakeProposal());
  asOperator();
  start('/admin');
  const row = await screen.findByRole('listitem', { name: QUINN_ROW });
  click('재검토 요청', row);
  const confirm = within(row).getByRole('button', { name: '재검토 요청 확정' });
  expect(confirm).toBeDisabled();
  note(/재검토 요청 메모/, '  근거를 더 적어 주세요 ', row);
  fireEvent.click(confirm);
  expect(await screen.findByText(`재검토를 요청했습니다: ${QUINN_ROW}`)).toBeDefined();
  expect(rpcCalls('request_proposal_revision')).toEqual([{ p_id: 501, p_note: '근거를 더 적어 주세요', p_version: 1 }]);
});

test('/admin 빌드 승인 대기 줄: [재검토 요청] → request_build_revision', async () => {
  asOperator();
  start('/admin');
  const row = await screen.findByRole('listitem', { name: '[빌드] 퀸으로 다리우스 이기는 법' });
  click('재검토 요청', row);
  note(/재검토 요청 메모/, '핵심 템을 하나 더', row);
  click('재검토 요청 확정', row);
  expect(await screen.findByText(/빌드 재검토를 요청했습니다: 퀸으로 다리우스 이기는 법 \(대기중\)/)).toBeDefined();
  expect(rpcCalls('request_build_revision')).toEqual([{ p_id: 104, p_note: '핵심 템을 하나 더', p_version: 1 }]);
});

test('/admin 재검토 기다리는 중: 제안·빌드 모두 보이고 [요청 취소] [거절] (숨긴 카운터 재검토는 여기 없음)', async () => {
  TABLES.edit_proposals.push(
    fakeProposal({ status: 'revision_requested', revision_note: '근거 부족', revision_requested_at: '2026-11-03T00:00:00Z' }),
    fakeProposal({ id: 7, type: 'new_counter', counter_champion: 'Garen', counter_id: 3, status: 'revision_requested', revision_note: '숨김 재검토' }),
  );
  Object.assign(TABLES.builds.find((b) => b.id === 104), {
    status: 'revision_requested', revision_note: '룬을 다시', revision_requested_at: '2026-11-04T00:00:00Z',
  });
  asOperator();
  start('/admin');
  await sectionCount('재검토 기다리는 중', 2);
  expect(screen.queryByText('보낸 메모: 숨김 재검토')).toBeNull();

  const p = screen.getByRole('listitem', { name: '[재검토 중 문서 수정] 퀸으로 다리우스 이기는 법' });
  expect(within(p).getByText('보낸 메모: 근거 부족')).toBeDefined();
  click('요청 취소', p);
  expect(within(p).getByText('원래 내용 그대로 승인 대기로 돌아갑니다.')).toBeDefined();
  note(/요청 취소 메모/, '제가 잘못 봤습니다', p);
  click('요청 취소 확정', p);
  expect(await screen.findByText(/재검토 요청을 취소했습니다: \[문서 수정\]/)).toBeDefined();
  expect(rpcCalls('cancel_proposal_revision')).toEqual([{ p_id: 501, p_note: '제가 잘못 봤습니다' }]);

  const b = await screen.findByRole('listitem', { name: '[재검토 중 빌드] 퀸으로 다리우스 이기는 법' }); // 처리 뒤 목록을 다시 불러온다
  click('거절', b);
  note(/거절 사유/, '오래 기다렸습니다', b);
  click('거절 확정', b);
  expect(await screen.findByText(/거절했습니다: \[빌드\]/)).toBeDefined();
  expect(rpcCalls('reject_build')).toEqual([{ p_id: 104, p_reason: '오래 기다렸습니다', p_version: 1 }]);
});

// ---------------- 운영자: [자세히]의 [승인] = 고쳐서 승인 ----------------

test('제안 [자세히] [승인]: 글을 고치면 "제안 → 운영자 수정" 비교가 보이고, 고친 글만 approve_proposal로', async () => {
  TABLES.edit_proposals.push(fakeProposal());
  asOperator();
  start('/admin/proposals/501');
  await screen.findByRole('heading', { name: /\[문서 수정\]/ });
  for (const name of ['승인', '재검토 요청', '거절']) expect(screen.getByRole('button', { name })).toBeDefined();
  click('승인');
  const changes = screen.getByRole('region', { name: '고친 부분' });
  fireEvent.change(screen.getByLabelText('한 줄 요약 (필수)'), { target: { value: ' 운영자가 다듬은 요약 ' } });
  expect(within(changes).getByRole('region', { name: '한 줄 요약 변경' })).toBeDefined();

  note(/승인 메모/, '요약을 다듬었습니다');
  click('고친 내용으로 승인 확정');
  expect(await screen.findByText(`고쳐서 승인했습니다: ${QUINN_ROW}`)).toBeDefined();
  expect(where()).toBe('/admin');
  const p = fakeProposal();
  expect(rpcCalls('approve_proposal')).toEqual([{
    p_id: 501, p_note: '요약을 다듬었습니다', p_build: null, p_version: 1,
    p_content: { ...p.content, summary: '운영자가 다듬은 요약' },
  }]);
});

test('제안 [자세히] [승인]: 고친 글이 규칙에 어긋나면 보내지 않는다', async () => {
  TABLES.edit_proposals.push(fakeProposal());
  asOperator();
  start('/admin/proposals/501');
  click('승인', await screen.findByRole('article'));
  fireEvent.change(screen.getByLabelText('6레벨 (필수)'), { target: { value: '  ' } });
  note(/승인 메모/, '메모');
  click('고친 내용으로 승인 확정');
  expect(await screen.findByText('고친 내용을 확인해 주세요: 6레벨 딜교법은 꼭 적어야 합니다.')).toBeDefined();
  expect(fakeState.rpcCalls).toEqual([]);
});

test('새 카운터 제안 [승인]: 빌드를 고치면 지금 패치로 p_build, 글은 그대로(null)', async () => {
  TABLES.edit_proposals.push(fakeProposal({ type: 'new_counter', counter_champion: 'Garen', counter_id: null, base_revision_id: null }));
  asOperator();
  start('/admin/proposals/501');
  await screen.findByRole('heading', { name: /\[새 카운터\] 가렌/ });
  click('승인');
  pick('선마 (첫 번째로 마스터할 스킬)', '선마 W');
  expect(screen.getByText(/고친 빌드는 지금 패치\(99\.1\)로 기록됩니다/)).toBeDefined();
  expect(screen.getByRole('heading', { name: '고친 빌드' })).toBeDefined();
  note(/승인 메모/, '선마를 바꿨습니다');
  click('고친 내용으로 승인 확정');
  expect(await screen.findByText(/고쳐서 승인했습니다: \[새 카운터\] 가렌/)).toBeDefined();
  expect(rpcCalls('approve_proposal')).toEqual([{
    p_id: 501, p_note: '선마를 바꿨습니다', p_content: null, p_version: 1,
    p_build: { ...FAKE_PROPOSAL_BUILD, max_skill: 'W', patch: '99.1.1' },
  }]);
});

test('빌드 [자세히] [승인]: 고쳐서 승인 → approve_build(고친 빌드, 지금 패치), [재검토 요청]도 있다', async () => {
  asOperator();
  start('/admin/builds/104?approve=1');
  expect(await screen.findByRole('region', { name: '고친 부분' })).toBeDefined();
  expect(screen.getByRole('button', { name: '재검토 요청' })).toBeDefined();
  pick('선마 (첫 번째로 마스터할 스킬)', '선마 W');
  note(/승인 메모/, '선마 정리');
  click('고친 내용으로 승인 확정');
  expect(await screen.findByText(/빌드를 고쳐서 승인했습니다/)).toBeDefined();
  const b = fakeBuild(104, null);
  expect(rpcCalls('approve_build')).toEqual([{
    p_id: 104, p_note: '선마 정리', p_version: 1,
    p_build: {
      runes: b.runes, summoner_spells: b.summoner_spells, starting_items: b.starting_items, core_items: b.core_items,
      max_skill: 'W', patch: '99.1.1',
    },
  }]);
});

test('제안 [자세히]: 재검토 기다리는 중이면 메모와 [요청 취소] [거절]만', async () => {
  TABLES.edit_proposals.push(fakeProposal({ status: 'revision_requested', revision_note: '근거 부족', revision_requested_at: '2026-11-03T00:00:00Z' }));
  asOperator();
  start('/admin/proposals/501');
  expect(await screen.findByText('보낸 메모: 근거 부족')).toBeDefined();
  expect(screen.queryByRole('button', { name: '승인' })).toBeNull();
  click('요청 취소');
  note(/요청 취소 메모/, '다시 보겠습니다');
  click('요청 취소 확정');
  expect(await screen.findByText(`재검토 요청을 취소했습니다: ${QUINN_ROW}`)).toBeDefined();
});

test('제안 [자세히]: 고쳐서 승인된 제안은 원래 제안 → 고친 내용 비교', async () => {
  const p = fakeProposal({ status: 'approved', approve_note: '다듬음' });
  TABLES.edit_proposals.push({ ...p, approved_content: { ...p.content, summary: '운영자 요약' } });
  asOperator();
  start('/admin/proposals/501');
  expect(await screen.findByRole('heading', { name: '운영자가 고쳐서 승인했습니다 (원래 제안 → 고친 내용)' })).toBeDefined();
});

// ---------------- 제안자: /me ----------------

test('/me: 고쳐서 승인된 제안은 원래 제안 → 고친 내용을 펼쳐 볼 수 있다 (승인 메모도)', async () => {
  const p = fakeProposal({ status: 'approved', approve_note: '요약을 다듬었습니다', reviewed_at: '2026-11-03T00:00:00Z' });
  TABLES.edit_proposals.push({ ...p, approved_content: { ...p.content, summary: '운영자 요약' } });
  asProposer();
  start('/me');
  expect(await screen.findByText('승인 메모: 요약을 다듬었습니다')).toBeDefined();
  const details = screen.getByText('운영자가 고쳐서 승인했습니다 — 원래 제안 → 고친 내용 보기').closest('details');
  const diff = within(details).getByRole('region', { name: '한 줄 요약 변경' });
  expect(diff.textContent).toMatch(/− 고친 요약/);
  expect(diff.textContent).toMatch(/\+ 운영자 요약/);
});

test('/me: 대기 중 문서 수정 제안이 재검토 요청을 받으면 글만 고쳐서 다시 보내기 (빌드 칸 없음)', async () => {
  TABLES.edit_proposals.push(fakeProposal({ status: 'revision_requested', revision_note: '근거를 더', revision_requested_at: '2026-11-03T00:00:00Z' }));
  asProposer();
  start('/me');
  const row = (await screen.findByText('운영자 메모: 근거를 더')).closest('li');
  fireEvent.click(within(row).getByRole('link', { name: '고쳐서 다시 보내기' }));
  expect(await screen.findByText(/보낸 글이 채워져 있습니다/)).toBeDefined();
  expect(screen.queryByRole('group', { name: '빌드 (필수)' })).toBeNull();
  click('다시 보내기');
  expect(screen.getByRole('alert').textContent).toBe('고친 내용이 없습니다. 운영자 메모를 보고 글을 고쳐 주세요.');
  fireEvent.change(screen.getByLabelText('특이사항'), { target: { value: 'E 사거리 주의\n근거: 실험해 봄' } });
  click('다시 보내기');
  expect(await screen.findByText(/고친 내용을 다시 보냈습니다/)).toBeDefined();
  const p = fakeProposal();
  expect(rpcCalls('resubmit_proposal')).toEqual([{
    p_id: 501, p_content: { ...p.content, lane_cautions: 'E 사거리 주의\n근거: 실험해 봄' }, p_build: null,
  }]);
});

test('/me: 재검토 요청 받은 빌드 → 고쳐서 다시 보내기 (지금 패치), 그대로면 못 보냄', async () => {
  TABLES.builds.push(fakeBuild(130, { nickname: '기존유저', level: 1, main_title: null }, {
    author_id: 'u-old', status: 'revision_requested', revision_note: '선마를 바꿔 주세요', revision_requested_at: '2026-11-03T00:00:00Z',
  }));
  asProposer();
  start('/me');
  const row = await screen.findByRole('listitem', { name: '내 빌드: 퀸으로 다리우스 이기는 법' });
  expect(within(row).getByText('운영자 메모: 선마를 바꿔 주세요')).toBeDefined();
  fireEvent.click(within(row).getByRole('link', { name: '고쳐서 다시 보내기' }));
  expect(await screen.findByRole('heading', { name: '퀸으로 다리우스 이기는 법 — 빌드 고쳐서 다시 보내기' })).toBeDefined();
  click('다시 보내기');
  expect(screen.getByRole('alert').textContent).toBe('고친 내용이 없습니다. 운영자 메모를 보고 빌드를 고쳐 주세요.');
  pick('선마 (첫 번째로 마스터할 스킬)', '선마 W');
  click('다시 보내기');
  expect(await screen.findByText(/고친 빌드를 다시 보냈습니다/)).toBeDefined();
  const b = fakeBuild(130, null);
  expect(rpcCalls('resubmit_build')).toEqual([{
    p_id: 130,
    p_build: {
      runes: b.runes, summoner_spells: b.summoner_spells, starting_items: b.starting_items, core_items: b.core_items,
      max_skill: 'W', patch: '99.1.1',
    },
  }]);
});

test('/me: 고쳐서 승인된 빌드는 원래 빌드 → 고친 빌드를 볼 수 있다', async () => {
  const b = fakeBuild(131, { nickname: '기존유저', level: 1, main_title: null }, { author_id: 'u-old', approve_note: '선마 정리' });
  TABLES.builds.push({ ...b, original_build: { ...b, max_skill: 'E' } });
  asProposer();
  start('/me');
  const row = await screen.findByRole('listitem', { name: '내 빌드: 퀸으로 다리우스 이기는 법' });
  const details = within(row).getByText('운영자가 고쳐서 승인했습니다 — 원래 제안 → 고친 내용 보기').closest('details');
  expect(within(details).getByRole('heading', { name: '원래 빌드' })).toBeDefined();
  expect(within(details).getByRole('heading', { name: '고친 빌드' })).toBeDefined();
});
