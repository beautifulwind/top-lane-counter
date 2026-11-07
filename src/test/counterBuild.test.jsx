// 009: 새 카운터 제안 = 글 + 빌드. 다시 제출·운영자 검토·마지막 공개 빌드 잠금
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { FAKE_PROPOSAL_BUILD, TABLES, fakeBuild, fakeLogin, fakeProposal, fakeState } from './fakeSupabase';
import { pick } from './buildHelpers';

const COUNTERS = TABLES.counters.map((c) => ({ ...c }));
beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
  TABLES.counters = COUNTERS.map((c) => ({ ...c }));
});

function Where() { const l = useLocation(); return <output data-testid="where">{l.pathname}</output>; }
const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /><Where /></MemoryRouter>);
const where = () => screen.getByTestId('where').textContent;
const asOperator = () => fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0, main_title: null });
const GAREN_DOC = { summary: '가렌 요약', level_notes: { 1: 'a', 2: 'b', 3: 'c', 6: 'd', 9: 'e', 11: 'f' }, lane_cautions: '' };
const GAREN = { id: 3, target_champion: 'Darius', counter_champion: 'Garen', status: 'hidden' };

/** 숨긴 가렌 카운터 + 그 카운터를 만든 제안(id 7, 빌드 포함) */
function hiddenGaren(proposal = {}) {
  TABLES.counters.push({ ...GAREN, sort_order: 2, matchup_docs: { counter_id: 3, ...GAREN_DOC, updated_at: null, revision_id: 9 } });
  TABLES.edit_proposals.push(fakeProposal({
    id: 7, type: 'new_counter', counter_champion: 'Garen', counter_id: 3, content: GAREN_DOC, ...proposal,
  }));
}
const send = () => fireEvent.click(screen.getByRole('button', { name: '다시 보내기' }));

// ---------------- 다시 제출: 글 + 빌드 ----------------

test('다시 제출: 첫 빌드가 채워져 있고, 빌드만 고쳐도 보낼 수 있다', async () => {
  hiddenGaren({ status: 'revision_requested', revision_note: '빌드를 고쳐 주세요' });
  fakeLogin('u-old', { nickname: '기존유저' });
  start('/me/resubmit/7');
  expect(await screen.findByRole('heading', { name: /고쳐서 다시 보내기/ })).toBeDefined();
  const core = screen.getByRole('list', { name: '고른 핵심 템트리' });
  expect(within(core).getAllByRole('listitem').map((li) => li.textContent)).toEqual(['스테락의 도전', '강철판 장화', '선혈포식자']);
  send();
  expect(screen.getByRole('alert').textContent).toBe('고친 내용이 없습니다. 운영자 메모를 보고 글이나 빌드를 고쳐 주세요.');
  fireEvent.click(screen.getByRole('button', { name: '선혈포식자 빼기' }));
  pick('핵심 템트리 고르기', '칠흑의 양날 도끼');
  send();
  await vi.waitFor(() => expect(where()).toBe('/me'));
  expect(fakeState.rpcCalls.find((c) => c.name === 'resubmit_proposal').args).toEqual({
    p_id: 7, p_content: GAREN_DOC, p_build: { ...FAKE_PROPOSAL_BUILD, core_items: ['3053', '3047', '3071'] },
  });
});

test('다시 제출: 예전 제안이라 빌드가 없으면 빌드를 채워야 보낼 수 있다', async () => {
  hiddenGaren({ status: 'revision_requested', revision_note: '빌드도 넣어 주세요', build: null });
  fakeLogin('u-old', { nickname: '기존유저' });
  start('/me/resubmit/7');
  expect(await screen.findByText(/이 제안에는 빌드가 없습니다/)).toBeDefined();
  fireEvent.change(screen.getByLabelText('9레벨'), { target: { value: '9렙 고침' } });
  send();
  expect(screen.getByRole('alert').textContent).toBe('빌드를 마저 채워 주세요: 주 경로를 골라 주세요.');
  expect(fakeState.rpcCalls.filter((c) => c.name === 'resubmit_proposal')).toEqual([]);
});

// ---------------- 운영자: 새 카운터 제안의 빌드 ----------------

const pendingRow = () => screen.findByRole('listitem', { name: '[새 카운터] 가렌으로 다리우스 이기는 법' });

test('/admin: 새 카운터 제안 줄에서 함께 공개될 첫 빌드를 보고 바로 승인', async () => {
  TABLES.edit_proposals.push(fakeProposal({ id: 8, type: 'new_counter', counter_champion: 'Garen', counter_id: null }));
  asOperator();
  start('/admin');
  const row = await pendingRow();
  expect(within(row).getByText('함께 공개될 첫 빌드 보기')).toBeDefined();
  expect(within(row).getByRole('article', { name: '빌드: 기존유저' })).toBeDefined();
  expect(within(row).getByRole('button', { name: '승인' })).toBeEnabled();
});

test('/admin: 빌드 없는 새 카운터 제안·구버전 빌드는 줄에서 승인 잠금', async () => {
  TABLES.edit_proposals.push(fakeProposal({ id: 8, type: 'new_counter', counter_champion: 'Garen', counter_id: null, build: null }));
  asOperator();
  start('/admin');
  let row = await pendingRow();
  expect(within(row).getByText(/빌드가 없는 새 카운터 제안입니다/)).toBeDefined();
  expect(within(row).getByRole('button', { name: '승인' })).toBeDisabled();
  cleanup();
  TABLES.edit_proposals[0].build = { ...FAKE_PROPOSAL_BUILD, patch: '98.2.1' };
  start('/admin');
  row = await pendingRow();
  expect(within(row).getByText(/빌드가 지금 패치\(99\.1\)와 다른 패치\(98\.2\)로 등록됐습니다/)).toBeDefined();
  expect(within(row).getByRole('button', { name: '승인' })).toBeDisabled();
});

test('제안 자세히: 빌드 없는 새 카운터 제안은 승인 불가, 빌드가 있으면 "함께 공개될 첫 빌드"', async () => {
  TABLES.edit_proposals.push(fakeProposal({ id: 8, type: 'new_counter', counter_champion: 'Garen', counter_id: null, build: null }));
  asOperator();
  start('/admin/proposals/8');
  expect(await screen.findByText(/빌드가 없는 새 카운터 제안입니다. 새 카운터에는 빌드가 꼭 있어야/)).toBeDefined();
  expect(screen.getByRole('button', { name: '승인' })).toBeDisabled();
  cleanup();
  TABLES.edit_proposals[0].build = FAKE_PROPOSAL_BUILD;
  start('/admin/proposals/8');
  expect(await screen.findByRole('heading', { name: '함께 공개될 첫 빌드' })).toBeDefined();
  expect(screen.getByRole('button', { name: '승인' })).toBeEnabled();
});

test('제안 자세히: 다시 낸 제안의 빌드가 바뀌었으면 원래 첫 빌드 ↔ 고친 빌드를 나란히', async () => {
  hiddenGaren({ status: 'pending', resubmitted_at: '2026-11-04T00:00:00Z', revision_note: '빌드를 고쳐 주세요',
    build: { ...FAKE_PROPOSAL_BUILD, core_items: ['3053', '3047', '3071'] } });
  TABLES.builds.push(fakeBuild(130, { nickname: '기존유저', level: 1, main_title: null }, {
    counter_id: 3, proposal_id: 7, author_id: 'u-old', ...FAKE_PROPOSAL_BUILD, up_count: 4,
  }));
  asOperator();
  start('/admin/proposals/7');
  expect(await screen.findByRole('heading', { name: '바뀐 빌드 (원래 첫 빌드 → 고친 빌드)' })).toBeDefined();
  expect(screen.getByText(/원래 첫 빌드는 숨기고\("재검토로 교체"\)/)).toBeDefined();
  expect(screen.getAllByRole('article', { name: '빌드: 기존유저' })).toHaveLength(2);
  expect(screen.getByLabelText('추천 4')).toBeDefined(); // 원래 빌드의 추천
  cleanup();
  TABLES.edit_proposals[0].build = FAKE_PROPOSAL_BUILD; // 빌드는 그대로
  start('/admin/proposals/7');
  expect(await screen.findByRole('heading', { name: '첫 빌드 (그대로)' })).toBeDefined();
});

// ---------------- 마지막 공개 빌드 ----------------

test('매치업 문서: 공개 빌드가 하나뿐이면 [빌드 숨기기]가 잠긴다', async () => {
  TABLES.builds = TABLES.builds.filter((b) => b.id === 102);
  asOperator();
  start('/champion/Darius/counter/Quinn');
  const card = await screen.findByRole('article', { name: '빌드: 탑고수' });
  expect(within(card).getByRole('button', { name: '빌드 숨기기' })).toBeDisabled();
  expect(within(card).getByText(/마지막 공개 빌드라 숨길 수 없습니다/)).toBeDefined();
});

test('빌드 자세히: 마지막 공개 빌드면 숨기기 잠금', async () => {
  TABLES.builds = TABLES.builds.filter((b) => b.id === 102);
  asOperator();
  start('/admin/builds/102');
  expect(await screen.findByText(/마지막 공개 빌드라 숨길 수 없습니다/)).toBeDefined();
  expect(screen.getByRole('button', { name: '빌드 숨기기' })).toBeDisabled();
});

// ---------------- /me ----------------

test('/me: 새 카운터 제안 줄에서 제안한 빌드를 펼쳐 본다 (거절돼도)', async () => {
  TABLES.edit_proposals.push(fakeProposal({ id: 8, type: 'new_counter', counter_champion: 'Garen', counter_id: null, status: 'rejected', reject_reason: '근거 부족' }));
  fakeLogin('u-old', { nickname: '기존유저' });
  start('/me');
  const row = (await screen.findByText('거절 사유: 근거 부족')).closest('li');
  expect(within(row).getByText('제안한 빌드 보기')).toBeDefined();
  expect(within(row).getByRole('article', { name: '빌드: 기존유저' })).toBeDefined();
});
