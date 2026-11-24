// 6-85: 활동 제한 (068) — 모든 화면 위 띠(사유·풀리는 시각·[문의하기]), 흐린 쓰기 버튼(누르면 동작 대신 같은 이유),
// 막지 않는 것(팔로우 취소·저장 해제·읽기), 기간 지나면 띠 없음, 068 전 DB, 문의 「이의 제기」,
// 운영자 회원 정보의 [활동 제한 걸기]·[해제]·기록 목록, 감독관·운영자에게는 걸기 버튼 없음
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { AppRoutes } from '../App';
import { RESTRICTIONS_NOT_READY } from '../api/restrictions';
import { fmtDateTime } from '../lib/format';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeLogin, fakeState } from './fakeSupabase';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

function Where() { const l = useLocation(); return <output data-testid="where">{l.pathname + l.search}</output>; }
const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /><Where /></MemoryRouter>);
const where = () => screen.getByTestId('where').textContent;
const MATCHUP = '/champion/Darius/counter/Quinn';
const ENDS = new Date(Date.now() + 3 * 86400000).toISOString();
const asMember = () => fakeLogin('u-me', { nickname: '나', role: 'user', level: 2, main_title: null });
const restrict = (extra = {}) => { fakeState.restriction = { id: 1, reason: '욕설 반복', ends_at: ENDS, ...extra }; };
const band = () => screen.findByRole('status', { name: '활동 제한 안내' });
const rpcCalls = (name) => fakeState.rpcCalls.filter((c) => c.name === name);

// ---------------- 띠 ----------------

test('제한 중: 모든 화면 위에 사유·풀리는 시각·[문의하기] 띠, 앱 전체에 is-restricted', async () => {
  asMember();
  restrict();
  start('/');
  const b = await band();
  expect(b).toHaveTextContent(`활동이 제한된 상태입니다. ${fmtDateTime(ENDS)}에 풀립니다. 사유: 욕설 반복`);
  expect(within(b).getByRole('link', { name: '문의하기' }).getAttribute('href')).toBe('/inquiries?category=appeal');
  expect(document.querySelector('.app').classList.contains('is-restricted')).toBe(true);
  cleanup();
  start('/board');
  expect(await band()).toHaveTextContent('사유: 욕설 반복');
});

test('제한 없음·로그인 전·068 전 DB·기간이 지난 제한: 띠가 없다', async () => {
  start('/');
  await screen.findByRole('main');
  expect(screen.queryByRole('status', { name: '활동 제한 안내' })).toBeNull();
  cleanup();
  asMember();
  start('/');
  await screen.findByRole('main');
  await new Promise((r) => setTimeout(r, 30));
  expect(screen.queryByRole('status', { name: '활동 제한 안내' })).toBeNull();
  expect(document.querySelector('.app').classList.contains('is-restricted')).toBe(false);
  cleanup();
  restrict({ ends_at: new Date(Date.now() - 60000).toISOString() });
  start('/');
  await screen.findByRole('main');
  await new Promise((r) => setTimeout(r, 30));
  expect(screen.queryByRole('status', { name: '활동 제한 안내' })).toBeNull();
  cleanup();
  restrict();
  fakeState.restrictionsMissing = true;
  start('/');
  await screen.findByRole('main');
  await new Promise((r) => setTimeout(r, 30));
  expect(screen.queryByRole('status', { name: '활동 제한 안내' })).toBeNull();
});

// ---------------- 흐린 쓰기 버튼 ----------------

test('제한 중 [글쓰기]: 화면이 안 바뀌고 같은 이유 안내 상자 — [닫기]로 닫힘, [문의하기]는 이의 제기로', async () => {
  asMember();
  restrict();
  start('/board');
  await band();
  const write = await screen.findByRole('link', { name: /글쓰기/ });
  expect(write).toHaveAttribute('data-write');
  fireEvent.click(write);
  expect(where()).toBe('/board');
  const toast = screen.getByRole('alert');
  expect(toast).toHaveTextContent(`활동이 제한된 상태입니다. ${fmtDateTime(ENDS)}에 풀립니다. 사유: 욕설 반복`);
  fireEvent.click(within(toast).getByRole('button', { name: '닫기' }));
  expect(screen.queryByRole('alert')).toBeNull();
  fireEvent.click(write);
  fireEvent.click(within(screen.getByRole('alert')).getByRole('link', { name: '문의하기' }));
  expect(where()).toBe('/inquiries?category=appeal');
});

test('제한 중 빌드 추천·저장·[+ 새 빌드]·[빌드 수정]: 서버를 부르지 않고 안내 — 이미 저장한 빌드의 저장 해제는 그대로', async () => {
  asMember();
  restrict();
  TABLES.build_bookmarks.push({ user_id: 'u-me', build_id: 102, created_at: '2026-11-20T00:00:00Z' });
  start(MATCHUP);
  await band();
  await screen.findByText(/퀸으로 다리우스 이기는 법/);
  const card = screen.getByRole('article', { name: '빌드: 탑고수' });
  fireEvent.click(within(card).getByRole('button', { name: /^추천/ }));
  expect(screen.getByRole('alert')).toHaveTextContent('사유: 욕설 반복');
  expect(rpcCalls('vote_build')).toEqual([]);
  for (const name of [/\+ 새 빌드/, '빌드 수정']) {
    const links = screen.queryAllByRole('link', { name });
    links.forEach((l) => { fireEvent.click(l); expect(where()).toBe(MATCHUP); });
  }
  const save = within(card).getByRole('button', { name: '빌드 저장' });
  expect(save).toHaveAttribute('aria-pressed', 'true');
  expect(save).not.toHaveAttribute('data-write'); // 저장 해제는 막지 않는다
  fireEvent.click(screen.getByRole('button', { name: '닫기' }));
  fireEvent.click(save);
  await waitFor(() => expect(TABLES.build_bookmarks).toEqual([])); // 해제됨
  expect(screen.queryByRole('alert')).toBeNull();
});

test('제한 없음: 같은 버튼이 그대로 동작한다 (안내 상자 없음)', async () => {
  asMember();
  start('/board');
  const write = await screen.findByRole('link', { name: /글쓰기/ });
  fireEvent.click(write);
  await waitFor(() => expect(where()).toBe('/board/new'));
  expect(screen.queryByRole('alert')).toBeNull();
});

// ---------------- 문의 「이의 제기」 ----------------

test('[문의하기] → 문의 화면에서 「이의 제기」가 골라져 있고, 운영자만 본다는 안내', async () => {
  asMember();
  restrict();
  start('/inquiries?category=appeal');
  const select = await screen.findByLabelText(/분류/);
  expect(select.value).toBe('appeal');
  expect(screen.getAllByRole('option').map((o) => o.textContent)).toContain('이의 제기');
  expect(document.body.textContent).toContain('“계정·탈퇴”·“이의 제기” 문의는 운영자만 볼 수 있습니다.');
});

test('068 전 DB: 「이의 제기」 분류는 숨긴다 (보내면 DB가 거절하므로)', async () => {
  asMember();
  fakeState.restrictionsMissing = true;
  start('/inquiries?category=appeal');
  await screen.findByLabelText(/분류/);
  await waitFor(() => expect(screen.getAllByRole('option').map((o) => o.textContent)).not.toContain('이의 제기'));
  expect(screen.getByLabelText(/분류/).value).toBe('');
});

// ---------------- 운영자 화면 ----------------

const asOp = () => fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0, main_title: null });
const member = (extra = {}) => TABLES.profiles.push({ id: 'u-bad', nickname: '말썽', role: 'user', level: 2, main_title: null, ...extra });
const section = () => screen.findByRole('region', { name: '활동 제한' });

test('운영자: [활동 제한 걸기] — 1·3·7·30일 또는 직접 입력, 사유 필수, 확정하면 기록에 「제한 중」', async () => {
  asOp();
  member();
  start('/admin/members/u-bad');
  const sec = await section();
  expect(await screen.findByText('활동 제한 기록이 없습니다.')).toBeDefined();
  fireEvent.click(screen.getByRole('button', { name: '활동 제한 걸기' }));
  expect(screen.getAllByRole('button', { pressed: false }).map((b) => b.textContent)).toEqual(['1일', '3일', '30일']);
  expect(screen.getByRole('button', { name: '7일', pressed: true })).toBeDefined();
  const confirm = () => screen.getByRole('button', { name: /제한 걸기 확정/ });
  expect(confirm()).toBeDisabled(); // 사유 없음
  fireEvent.change(screen.getByLabelText(/사유/), { target: { value: '  욕설 반복  ' } });
  expect(confirm()).toHaveTextContent('7일 제한 걸기 확정');
  fireEvent.change(screen.getByLabelText('직접 입력 (1~365일)'), { target: { value: '400' } });
  expect(screen.getByText('기간은 1일부터 365일까지 정할 수 있습니다.')).toBeDefined();
  expect(confirm()).toBeDisabled();
  fireEvent.change(screen.getByLabelText('직접 입력 (1~365일)'), { target: { value: '14' } });
  expect(confirm()).toHaveTextContent('14일 제한 걸기 확정');
  fireEvent.click(screen.getByRole('button', { name: '3일' }));
  expect(screen.getByLabelText('직접 입력 (1~365일)').value).toBe('');
  fireEvent.click(confirm());
  await waitFor(() => expect(rpcCalls('restrict_user')).toEqual([{ name: 'restrict_user', args: { p_user: 'u-bad', p_days: 3, p_reason: '욕설 반복' } }]));
  expect(await screen.findByText(/말썽님에게 3일 활동 제한을 걸었습니다/)).toBeDefined();
  await waitFor(() => expect(screen.getByRole('list', { name: '활동 제한 기록' })).toHaveTextContent('제한 중'));
  const log = screen.getByRole('list', { name: '활동 제한 기록' });
  expect(log).toHaveTextContent('3일');
  expect(log).toHaveTextContent('사유: 욕설 반복');
  expect(screen.getByRole('button', { name: '활동 제한 걸기' })).toBeDisabled(); // 제한 중엔 다시 못 건다
});

test('운영자: [해제] — 메모는 선택, 해제하면 기록에 「해제됨」과 해제 메모', async () => {
  asOp();
  member();
  TABLES.user_restrictions.push({ id: 5, user_id: 'u-bad', reason: '도배', days: 7, starts_at: '2026-11-20T00:00:00Z', ends_at: ENDS, created_by: '영자', lifted_at: null, lifted_by: null, lift_note: null });
  start('/admin/members/u-bad');
  const sec = await section();
  expect(await screen.findByText(/제한 중: .*에 풀립니다\. 사유: 도배/)).toBeDefined();
  fireEvent.click(screen.getByRole('button', { name: '해제' }));
  fireEvent.change(screen.getByLabelText(/해제 메모/), { target: { value: '이의 제기 받아들임' } });
  fireEvent.click(screen.getByRole('button', { name: '해제 확정' }));
  await waitFor(() => expect(rpcCalls('lift_restriction')).toEqual([{ name: 'lift_restriction', args: { p_id: 5, p_note: '이의 제기 받아들임' } }]));
  await waitFor(() => expect(screen.getByRole('list', { name: '활동 제한 기록' })).toHaveTextContent('해제됨'));
  expect(screen.getByRole('list', { name: '활동 제한 기록' })).toHaveTextContent('이의 제기 받아들임');
  expect(screen.getByRole('button', { name: '활동 제한 걸기' })).toBeDefined();
});

test('운영자: 서버가 거절하면 그 문장을 그대로 보여 준다', async () => {
  asOp();
  member();
  fakeState.rpcError = '이미 활동 제한 중입니다. 기간을 바꾸려면 먼저 해제한 뒤 다시 걸어 주세요.';
  start('/admin/members/u-bad');
  const sec = await section();
  fireEvent.click(await screen.findByRole('button', { name: '활동 제한 걸기' }));
  fireEvent.change(screen.getByLabelText(/사유/), { target: { value: '도배' } });
  fireEvent.click(screen.getByRole('button', { name: /제한 걸기 확정/ }));
  expect(await screen.findByRole('alert')).toHaveTextContent('이미 활동 제한 중입니다.');
});

test('운영자: 감독관·운영자에게는 [활동 제한 걸기]가 없고 이유를 보여 준다', async () => {
  asOp();
  member({ role: 'moderator' });
  start('/admin/members/u-bad');
  const sec = await section();
  expect(await screen.findByText(/감독관에게는 활동 제한을 걸 수 없습니다/)).toBeDefined();
  expect(screen.getByRole('button', { name: '활동 제한 걸기' })).toBeDisabled(); // 1.3 1-A: 비활성 버튼 + 작은 설명
});

test('운영자: 068 전 DB면 준비 중 안내만 (회원 정보는 그대로 열림)', async () => {
  asOp();
  member();
  fakeState.restrictionsMissing = true;
  start('/admin/members/u-bad');
  const sec = await section();
  expect(await screen.findByText(RESTRICTIONS_NOT_READY)).toBeDefined();
  expect(screen.queryByRole('button', { name: '활동 제한 걸기' })).toBeNull();
  expect(screen.getByRole('list', { name: '말썽 회원 정보' })).toBeDefined();
});
