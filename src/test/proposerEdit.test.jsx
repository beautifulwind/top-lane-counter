// 013: /me 제안·빌드 자세히, 승인 대기 중 제안자가 직접 고치기, 운영자 화면의 "제안자가 고침"과 [새 내용 불러오기]
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { FAKE_PROPOSAL_BUILD, TABLES, fakeBuild, fakeLogin, fakeProposal, fakeState } from './fakeSupabase';
import { pick } from './buildHelpers';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

function Where() { const l = useLocation(); return <output data-testid="where">{l.pathname + l.search}</output>; }
const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /><Where /></MemoryRouter>);
const where = () => screen.getByTestId('where').textContent;
const asOperator = () => fakeLogin('u-op', { nickname: '영자(운)', role: 'admin', level: 0, main_title: null });
const asProposer = () => fakeLogin('u-old', { nickname: '기존유저' });
const click = (name, root = document.body) => fireEvent.click(within(root).getByRole('button', { name }));
const rpcCalls = (name) => fakeState.rpcCalls.filter((c) => c.name === name).map((c) => c.args);
const STALE = '제안자가 방금 고쳤어요. 다시 확인해 주세요.';
const GAREN = { type: 'new_counter', counter_champion: 'Garen', counter_id: null };

// ---------------- 제안자: 자세히 ----------------

test('/me 제안 제목 → 자세히: 보낸 글·빌드를 문서 모양으로, 승인 대기면 [수정]', async () => {
  TABLES.edit_proposals.push(fakeProposal({ id: 2, ...GAREN }));
  asProposer();
  start('/me');
  fireEvent.click(await screen.findByRole('link', { name: '가렌으로 다리우스 잡는 법' }));
  expect(where()).toBe('/me/proposals/2');
  expect(await screen.findByRole('heading', { name: '[새 카운터] 가렌으로 다리우스 잡는 법' })).toBeDefined();
  expect(screen.getByText('고친 요약')).toBeDefined();
  // 022: 한 줄 요약 → 빌드 → 레벨별 딜교법 → 특이사항
  expect(screen.getAllByRole('heading', { level: 2 }).map((h) => h.textContent).filter((t) => /^\d\./.test(t)))
    .toEqual(['1. 빌드', '2. 레벨별 딜교법', '3. 특이사항']);
  expect(screen.getByText(/승인 대기 중이에요. 운영자가 처리하기 전까지는 직접 고칠 수 있어요/)).toBeDefined();
  expect(screen.getByRole('link', { name: '수정' }).getAttribute('href')).toBe('/me/proposals/2/edit');
  expect(screen.queryByRole('link', { name: '문서 보기' })).toBeNull();
});

test('자세히: 운영자가 고쳐서 승인했으면 [보낸 내용] / [공개된 내용]을 바꿔 보고, 고칠 수 없다는 안내와 [문서 보기]', async () => {
  TABLES.edit_proposals.push(fakeProposal({
    status: 'approved', approve_note: '요약을 다듬었어요', reviewed_at: '2026-11-02T00:00:00Z',
    approved_content: { ...fakeProposal().content, summary: '운영자가 다듬은 요약' },
  }));
  asProposer();
  start('/me/proposals/501');
  expect(await screen.findByText('승인 메모: 요약을 다듬었어요')).toBeDefined();
  expect(screen.getByText(/승인된 제안은 고칠 수 없어요/)).toBeDefined();
  expect(screen.getByRole('link', { name: '문서 보기' }).getAttribute('href')).toBe('/champion/Darius/counter/Quinn');
  expect(screen.queryByRole('link', { name: '수정' })).toBeNull();
  expect(screen.getByRole('button', { name: '보낸 내용' }).getAttribute('aria-pressed')).toBe('true');
  expect(screen.getByText('고친 요약')).toBeDefined();
  click('공개된 내용 (운영자가 고침)');
  expect(screen.getAllByText('운영자가 다듬은 요약').length).toBeGreaterThan(0);
  expect(screen.getByRole('button', { name: '공개된 내용 (운영자가 고침)' }).getAttribute('aria-pressed')).toBe('true');
});

test('자세히: 거절된 문서 수정 제안 [다시 쓰기] → 보낸 글이 채워진 수정 제안 화면', async () => {
  TABLES.edit_proposals.push(fakeProposal({ status: 'rejected', reject_reason: '근거가 부족해요' }));
  asProposer();
  start('/me/proposals/501');
  expect(await screen.findByText('거절 사유: 근거가 부족해요')).toBeDefined();
  fireEvent.click(screen.getByRole('link', { name: '다시 쓰기' }));
  expect(where()).toBe('/champion/Darius/counter/Quinn/edit?from=501');
  expect((await screen.findByLabelText('한 줄 요약 (필수)')).value).toBe('고친 요약');
  expect(screen.getByText(/거절된 내 제안의 글을 채워 뒀어요/)).toBeDefined();
});

test('자세히: 거절된 새 카운터 제안 [다시 쓰기] → 글·빌드가 채워진 새 카운터 제안 화면', async () => {
  TABLES.edit_proposals.push(fakeProposal({ id: 2, ...GAREN, status: 'rejected', reject_reason: '빌드가 이상해요' }));
  asProposer();
  start('/me/proposals/2');
  fireEvent.click(await screen.findByRole('link', { name: '다시 쓰기' }));
  expect(where()).toBe('/champion/Darius/propose?counter=Garen&from=2');
  expect((await screen.findByLabelText('한 줄 요약 (필수)')).value).toBe('고친 요약');
  expect(screen.getByText(/거절된 내 제안의 글과 빌드를 채워 뒀어요/)).toBeDefined();
  fireEvent.click(screen.getByRole('button', { name: '제안' }));
  await vi.waitFor(() => expect(fakeState.inserts.length).toBe(1));
  expect(fakeState.inserts[0].values.build.core_items).toEqual(FAKE_PROPOSAL_BUILD.core_items);
});

// ---------------- 제안자: 승인 대기 중 고치기 ----------------

test('[고치기]: 그대로면 안 보내고, 고치면 edit_my_proposal → 자세히로 (순서 그대로 안내)', async () => {
  TABLES.edit_proposals.push(fakeProposal());
  asProposer();
  start('/me/proposals/501/edit');
  expect(await screen.findByRole('heading', { name: '퀸으로 다리우스 잡는 법 — 고치기' })).toBeDefined();
  expect(screen.queryByText('운영자 메모')).toBeNull();
  click('고친 내용 저장');
  expect(screen.getByRole('alert').textContent).toBe('고친 내용이 없어요.');
  expect(rpcCalls('edit_my_proposal')).toEqual([]);

  fireEvent.change(screen.getByLabelText('한 줄 요약 (필수)'), { target: { value: '다시 고친 요약' } });
  click('고친 내용 저장');
  expect(await screen.findByText('고친 내용을 저장했어요. 승인 대기 순서는 그대로예요.')).toBeDefined();
  expect(where()).toBe('/me/proposals/501');
  expect(rpcCalls('edit_my_proposal')).toEqual([{
    p_id: 501, p_content: { ...fakeProposal().content, summary: '다시 고친 요약' }, p_build: null,
  }]);
});

test('[고치기] 새 카운터 제안: 빌드만 고쳐도 저장, 빌드는 지금 패치로', async () => {
  TABLES.edit_proposals.push(fakeProposal({ id: 2, ...GAREN }));
  asProposer();
  start('/me/proposals/2/edit');
  await screen.findByRole('heading', { name: '가렌으로 다리우스 잡는 법 — 고치기' });
  pick('선마 (첫 번째로 마스터할 스킬)', '선마 W');
  click('고친 내용 저장');
  await screen.findByText(/고친 내용을 저장했어요/);
  expect(rpcCalls('edit_my_proposal')[0].p_build).toEqual({ ...FAKE_PROPOSAL_BUILD, max_skill: 'W', patch: '99.1.1' });
});

test('승인된 제안은 고치기 화면에서 안내만 (문서 수정 제안으로)', async () => {
  TABLES.edit_proposals.push(fakeProposal({ status: 'approved' }));
  asProposer();
  start('/me/proposals/501/edit');
  expect(await screen.findByText(/지금은 고칠 수 없는 제안이에요/)).toBeDefined();
  expect(screen.getByText(/\[문서 수정 제안\]을 보내 주세요/)).toBeDefined();
  expect(screen.queryByRole('button', { name: '고친 내용 저장' })).toBeNull();
});

test('빌드: /me → 자세히 → [수정] → edit_my_build (지금 패치), 옛 다시 제출 주소는 새 주소로', async () => {
  TABLES.builds.push(fakeBuild(111, null, { author_id: 'u-old', status: 'pending' }));
  asProposer();
  start('/me');
  const row = await screen.findByRole('listitem', { name: '내 빌드: 퀸으로 다리우스 잡는 법' });
  fireEvent.click(within(row).getByRole('link', { name: '퀸으로 다리우스 잡는 법' }));
  expect(await screen.findByRole('heading', { name: '[빌드] 퀸으로 다리우스 잡는 법' })).toBeDefined();
  expect(screen.getByRole('heading', { name: '1. 빌드' })).toBeDefined();
  fireEvent.click(screen.getByRole('link', { name: '수정' }));
  expect(await screen.findByRole('heading', { name: '퀸으로 다리우스 잡는 법 — 빌드 고치기' })).toBeDefined();
  pick('선마 (첫 번째로 마스터할 스킬)', '선마 W');
  click('고친 내용 저장');
  expect(await screen.findByText('고친 빌드를 저장했어요. 승인 대기 순서는 그대로예요.')).toBeDefined();
  expect(where()).toBe('/me/builds/111');
  expect(rpcCalls('edit_my_build')[0]).toMatchObject({ p_id: 111, p_build: { max_skill: 'W', patch: '99.1.1' } });

  cleanup();
  start('/me/builds/111/resubmit');
  await screen.findByRole('heading', { name: /빌드 고치기/ });
  expect(where()).toBe('/me/builds/111/edit');
});

// ---------------- 운영자 ----------------

test('운영자: 승인 대기 줄·자세히에 "제안자가 고침 · 시각", 대기 순서는 처음 보낸 때 그대로', async () => {
  TABLES.edit_proposals.push(
    fakeProposal({ id: 501, created_at: '2026-11-01T10:00:00Z', edited_at: '2026-11-03T09:00:00Z', version: 2 }),
    fakeProposal({ id: 502, ...GAREN, created_at: '2026-11-02T10:00:00Z' }),
  );
  asOperator();
  start('/admin');
  const rows = await screen.findAllByRole('listitem', { name: /^\[(문서 수정|새 카운터)\]/ });
  expect(rows[0].getAttribute('aria-label')).toBe('[문서 수정] 퀸으로 다리우스 잡는 법');
  expect(within(rows[0]).getByText(/^제안자가 고침 · /)).toBeDefined();
  expect(within(rows[1]).queryByText(/제안자가 고침/)).toBeNull();
  cleanup();
  start('/admin/proposals/501');
  expect(await screen.findByText(/^제안자가 고침 · /)).toBeDefined();
});

test('운영자: 처리하는 사이 제안자가 고쳤으면 막히고 [새 내용 불러오기] → 새 내용으로 다시 확인', async () => {
  TABLES.edit_proposals.push(fakeProposal());
  asOperator();
  start('/admin/proposals/501');
  await screen.findByRole('heading', { name: /퀸으로 다리우스 잡는 법/ });
  click('승인');
  fireEvent.change(screen.getByLabelText(/승인 메모/), { target: { value: '좋아요' } });
  fakeState.rpcError = STALE;
  click('승인 확정');
  const box = await screen.findByText(/제안자가 방금 내용을 고쳤어요/);
  expect(rpcCalls('approve_proposal')).toEqual([{ p_id: 501, p_note: '좋아요', p_content: null, p_build: null, p_version: 1 }]);
  expect(screen.getByText(/고치던 내용과 쓰던 메모는 사라져요/)).toBeDefined();

  // 그 사이 제안자가 고친 내용
  fakeState.rpcError = null;
  Object.assign(TABLES.edit_proposals[0], { content: { ...fakeProposal().content, summary: '제안자가 다시 고친 요약' }, version: 2, edited_at: '2026-11-03T09:00:00Z' });
  fireEvent.click(within(box.closest('div')).getByRole('button', { name: '새 내용 불러오기' }));
  expect(await screen.findByText(/^제안자가 고침 · /)).toBeDefined();
  expect(screen.getAllByText(/제안자가 다시 고친 요약/).length).toBeGreaterThan(0);
  expect(screen.queryByText(/제안자가 방금 내용을 고쳤어요/)).toBeNull();
  // [승인]은 열린 채로, 편집기는 새 내용으로 다시 채워진다 (고치던 내용은 사라짐)
  expect(screen.getByLabelText('한 줄 요약 (필수)').value).toBe('제안자가 다시 고친 요약');
  fireEvent.change(screen.getByLabelText(/승인 메모/), { target: { value: '확인했어요' } });
  click('승인 확정');
  await vi.waitFor(() => expect(rpcCalls('approve_proposal')).toHaveLength(2));
  expect(rpcCalls('approve_proposal')[1].p_version).toBe(2);
});

test('운영자 목록 줄 거절도 막히면 [새 내용 불러오기]', async () => {
  TABLES.builds.push(fakeBuild(111, { nickname: '기존유저', level: 1, main_title: null }, { author_id: 'u-old', status: 'pending', core_items: ['3071', '3047', '3053'] }));
  asOperator();
  start('/admin');
  const row = (await screen.findAllByRole('listitem', { name: '[빌드] 퀸으로 다리우스 잡는 법' }))
    .find((r) => within(r).queryAllByText('기존유저').length > 0);
  click('거절', row);
  fireEvent.change(within(row).getByLabelText(/거절 사유/), { target: { value: '중복' } });
  fakeState.rpcError = '작성자가 방금 고쳤어요. 다시 확인해 주세요.';
  click('거절 확정', row);
  expect(await within(row).findByText(/작성자가 방금 내용을 고쳤어요/)).toBeDefined();
  expect(within(row).getByRole('button', { name: '새 내용 불러오기' })).toBeDefined();
});
