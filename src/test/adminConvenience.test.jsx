// 033 관리자 편의: 제안 입력칸 안내 문구, 운영진 새 제안·빌드·문의 알림 표시, 관리 메뉴 처리 대기 건수, 검토 중 표시 갱신
import { act, cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
// 승인 제도 화면은 지금 꺼 두었다(lib/features.js). 코드는 남아 있으므로 켠 채로 검사한다 — 끈 상태는 approvalOff.test.jsx
vi.mock('../lib/features', async (importOriginal) => ({ ...(await importOriginal()), APPROVAL_ENABLED: true }));
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import { REVIEW_REFRESH_MS } from '../components/ReviewPresence';
import { describeNotification } from '../lib/notifications';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeLogin, fakeProposal, fakeState } from './fakeSupabase';
import { openMenu } from './menu';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.useRealTimers(); vi.restoreAllMocks(); });

const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /></MemoryRouter>);
const asMod = () => fakeLogin('u-mod', { nickname: '감독', role: 'moderator', level: 3, main_title: null });
const asOp = () => fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0, main_title: null });
const newCounter = (id, extra = {}) => fakeProposal({
  id, type: 'new_counter', counter_id: null, proposer_id: 'u-old', counter_champion: 'Vayne',
  proposer: { nickname: '기존유저', role: 'user', level: 1, main_title: null }, ...extra,
});

const HINT = '상대의 스킬별, 상황별로 어떻게 대처해야 하는지 적어 주세요.';

test('제안 입력칸: "레벨별 딜교법" 칸 위에 안내 문구 (새 카운터 제안)', async () => {
  fakeLogin('u-old');
  start('/champion/Darius/propose?counter=Garen');
  const legend = await screen.findByText('레벨별 딜교법', { selector: 'legend' });
  const group = legend.closest('fieldset');
  const hint = within(group).getByText(HINT);
  // 안내 문구는 첫 레벨 입력칸보다 먼저 나온다
  const firstField = group.querySelector('textarea');
  expect(hint.compareDocumentPosition(firstField) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
});

test('운영진 알림 표시: 새 제안·새 빌드·새 문의는 문장 그대로 제목, 누르면 처리 화면', () => {
  const base = { message: null, proposal_id: null, build_id: null, proposal: null, build: null };
  const p = describeNotification({
    ...base, kind: 'proposal_submitted', message: '새 카운터 제안이 들어왔습니다.', proposal_id: 7,
    proposal: { type: 'new_counter', target_champion: 'Darius', counter_champion: 'Garen' },
  });
  expect(p.title).toBe('새 카운터 제안이 들어왔습니다.');
  expect(p.subject).toContain('[새 카운터]');
  expect(p.to).toBe('/admin/proposals/7');
  const b = describeNotification({ ...base, kind: 'build_submitted', message: '새 빌드 제안이 들어왔습니다.', build_id: 9 });
  expect(b.title).toBe('새 빌드 제안이 들어왔습니다.');
  expect(b.to).toBe('/admin/builds/9');
  const q = describeNotification({ ...base, kind: 'inquiry_received', message: '새 문의가 들어왔습니다. (분류: 오류 신고)' });
  expect(q.title).toBe('새 문의가 들어왔습니다. (분류: 오류 신고)');
  expect(q.to).toBe('/admin/inquiries');
});

test('관리 메뉴: 운영자는 처리 대기 합계가 [관리] 옆에 (제안 + 빌드 + 문의)', async () => {
  asOp();
  fakeState.pendingCounts = { proposals: 2, builds: 1, inquiries: 3 };
  start('/');
  const menu = await openMenu();
  const link = await menu.findByRole('link', { name: '관리, 처리 대기 6건' });
  expect(link.querySelector('.menu-count').textContent).toBe('6');
  expect(link.querySelector('.menu-count').getAttribute('title')).toBe('제안 2 · 빌드 1 · 문의 3');
});

test('관리 메뉴: 대기가 없으면 숫자 없이 [관리]만, 일반 회원에게는 묻지도 않는다', async () => {
  asMod();
  start('/');
  const menu = await openMenu();
  expect(await menu.findByRole('link', { name: '관리' })).toBeDefined();
  expect(document.querySelector('.menu-count')).toBeNull();
  expect(fakeState.pendingCountsAsked).toBeGreaterThan(0);
  cleanup();
  fakeState.pendingCountsAsked = 0;
  fakeLogin('u-old');
  start('/');
  await openMenu();
  expect(fakeState.pendingCountsAsked).toBe(0);
});

test('관리 메뉴: 건수를 못 불러와도(아직 033 전) 메뉴는 그대로', async () => {
  asOp();
  fakeState.pendingCounts = 'error';
  start('/');
  const menu = await openMenu();
  expect(await menu.findByRole('link', { name: '관리' })).toBeDefined();
  expect(fakeState.pendingCountsAsked).toBeGreaterThan(0);
  expect(document.querySelector('.menu-count')).toBeNull();
});

test('제안 [자세히]를 열어 두면 "검토 중" 표시를 10분이 되기 전에 다시 남긴다', async () => {
  vi.useFakeTimers({ shouldAdvanceTime: true });
  asMod();
  TABLES.edit_proposals.push(newCounter(1));
  start('/admin/proposals/1');
  await screen.findByRole('button', { name: '승인' });
  const starts = () => fakeState.reviewCalls.filter((c) => c.name === 'start_proposal_review').length;
  const first = starts();
  expect(first).toBeGreaterThan(0);
  expect(REVIEW_REFRESH_MS).toBeLessThan(10 * 60 * 1000); // DB 표시는 10분 뒤 사라진다
  await act(async () => { await vi.advanceTimersByTimeAsync(REVIEW_REFRESH_MS + 1000); });
  expect(starts()).toBe(first + 1);
  fireEvent.click(screen.getByRole('button', { name: '승인' })); // 편집기를 열어 두고 있어도 계속
  await act(async () => { await vi.advanceTimersByTimeAsync(REVIEW_REFRESH_MS); });
  expect(starts()).toBe(first + 2);
});
