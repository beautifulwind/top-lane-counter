// 031: 이미 다른 분이 처리했습니다 안내 + "검토 중" 표시 (운영자·감독관만, 일반 회원에게는 절대 안 보임)
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeLogin, fakeProposal, fakeState } from './fakeSupabase';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

function Where() { const l = useLocation(); return <output data-testid="where">{l.pathname}</output>; }
const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /><Where /></MemoryRouter>);
const where = () => screen.getByTestId('where').textContent;
const asOp = () => fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0, main_title: null });
const asMod = () => fakeLogin('u-mod', { nickname: '감독', role: 'moderator', level: 3, main_title: null });
const names = (n) => fakeState.reviewCalls.filter((c) => c.name === n);
const newCounter = (id, extra = {}) => fakeProposal({
  id, type: 'new_counter', counter_id: null, counter_champion: 'Vayne',
  proposer: { nickname: '기존유저', role: 'user', level: 1, main_title: null }, ...extra,
});
const rowOf = async () => within(await screen.findByRole('listitem', { name: /\[문서 수정\]/ }));
const only = (...rows) => { TABLES.edit_proposals.splice(0, TABLES.edit_proposals.length, ...rows); };
const handledError = () => { fakeState.rpcError = '이미 다른 분이 처리했습니다.'; fakeState.rpcErrorCode = 'TL409'; };

test('목록 줄 [승인]: 다른 분이 먼저 처리했으면 오류 대신 안내하고 목록을 다시 불러온다', async () => {
  only(fakeProposal());
  asOp();
  start('/admin');
  fireEvent.click((await rowOf()).getByRole('button', { name: '승인' }));
  fireEvent.change(screen.getByLabelText(/승인 메모/), { target: { value: '확인' } });
  handledError();
  const before = names('proposal_reviewers').length;
  fireEvent.click(screen.getByRole('button', { name: '승인 확정' }));
  expect(await screen.findByText(/이미 다른 분이 처리했습니다\. 목록을 새로고침했습니다/)).toBeDefined();
  expect(screen.queryByRole('alert')).toBeNull(); // 폼 아래 빨간 오류가 아니다
  await waitFor(() => expect(names('proposal_reviewers').length).toBeGreaterThan(before)); // 목록을 다시 불러옴
});

test('목록 줄 [거절]도 같은 안내', async () => {
  only(fakeProposal());
  asOp();
  start('/admin');
  fireEvent.click((await rowOf()).getByRole('button', { name: '거절' }));
  fireEvent.change(screen.getByLabelText(/거절 사유/), { target: { value: '사유' } });
  handledError();
  fireEvent.click(screen.getByRole('button', { name: '거절 확정' }));
  expect(await screen.findByText(/이미 다른 분이 처리했습니다\. 목록을 새로고침했습니다/)).toBeDefined();
});

test('[자세히]에서 승인: 다른 분이 먼저 처리했으면 목록으로 돌아가 안내한다', async () => {
  TABLES.edit_proposals.push(fakeProposal());
  asOp();
  start('/admin/proposals/501');
  fireEvent.click(await screen.findByRole('button', { name: '승인' }));
  fireEvent.change(screen.getByLabelText(/승인 메모/), { target: { value: '확인' } });
  handledError();
  fireEvent.click(screen.getByRole('button', { name: '승인 확정' }));
  expect(await screen.findByText(/이미 다른 분이 처리했습니다\. 목록을 새로고침했습니다/)).toBeDefined();
  expect(where()).toBe('/admin');
});

test('다른 종류의 오류는 예전처럼 폼 아래에 그대로 보인다', async () => {
  only(fakeProposal());
  asOp();
  start('/admin');
  fireEvent.click((await rowOf()).getByRole('button', { name: '승인' }));
  fireEvent.change(screen.getByLabelText(/승인 메모/), { target: { value: '확인' } });
  fakeState.rpcError = '숨긴 카운터의 제안이라 승인할 수 없습니다. 거절해 주세요.';
  fireEvent.click(screen.getByRole('button', { name: '승인 확정' }));
  expect(await screen.findByRole('alert')).toBeDefined();
  expect(screen.queryByText(/목록을 새로고침했습니다/)).toBeNull();
});

test('[자세히]를 열면 검토 중 표시를 남기고 다른 운영진 경고를 보인다. 닫으면 지운다', async () => {
  TABLES.edit_proposals.push(fakeProposal());
  fakeState.reviewers[501] = [{ nickname: '감독', role: 'moderator', level: 3, started_at: '2026-11-08T01:00:00Z' }];
  asOp();
  const { unmount } = start('/admin/proposals/501');
  expect(await screen.findByText('(운)감독 검토 중')).toBeDefined();
  expect(names('start_proposal_review')).toEqual([{ name: 'start_proposal_review', args: { p_id: 501 } }]);
  // 막지 않는다: 승인 버튼은 그대로 눌린다
  expect(screen.getByRole('button', { name: '승인' }).disabled).toBe(false);
  unmount();
  await waitFor(() => expect(names('end_proposal_review')).toEqual([{ name: 'end_proposal_review', args: { p_id: 501 } }]));
});

test('나 혼자면 경고가 없다', async () => {
  TABLES.edit_proposals.push(fakeProposal());
  asOp();
  start('/admin/proposals/501');
  await screen.findByRole('button', { name: '승인' });
  expect(screen.queryByText(/검토 중/)).toBeNull();
});

test('승인 대기 목록 줄에 "(운)닉네임 검토 중"이 보인다 (감독관 화면에서 운영자 표시)', async () => {
  TABLES.edit_proposals.push(newCounter(601));
  fakeState.reviewers[601] = [{ nickname: '영자', role: 'admin', level: 0, started_at: '2026-11-08T01:00:00Z' }];
  asMod();
  start('/admin');
  const row = await screen.findByRole('listitem', { name: /새 카운터/ });
  expect(within(row).getByText('(운)영자 검토 중')).toBeDefined();
  // 목록만 봐서는 내 표시를 남기지 않는다
  expect(names('start_proposal_review')).toEqual([]);
});

test('감독관이 처리할 수 없는 제안(문서 수정)에는 검토 중 표시를 시작하지 않는다', async () => {
  TABLES.edit_proposals.push(fakeProposal());
  asMod();
  start('/admin/proposals/501');
  await screen.findByText(/운영자가 처리하는 제안입니다/);
  expect(names('start_proposal_review')).toEqual([]);
});

test('일반 회원: /admin에 못 들어가고 표시 함수도 부르지 않으며, 거부당한다', async () => {
  TABLES.edit_proposals.push(fakeProposal());
  fakeState.reviewers[501] = [{ nickname: '영자', role: 'admin', level: 0, started_at: '2026-11-08T01:00:00Z' }];
  fakeLogin('u-old');
  start('/admin/proposals/501');
  expect(await screen.findByText('운영자만 볼 수 있습니다.')).toBeDefined();
  expect(screen.queryByText(/검토 중/)).toBeNull();
  expect(fakeState.reviewCalls).toEqual([]);
  // DB 함수도 같은 답 (권한 검사는 DB)
  const { api } = await import('./reviewApi');
  expect(await api()).toMatch(/운영진만/);
});
