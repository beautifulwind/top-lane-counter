// 6-86: 운영자 경고 (069) — 모든 화면 위 안내 상자(「운영자 경고를 받았습니다」 + 내용 + [확인했습니다]), 여러 개면 하나씩,
// 확인 실패는 문장 그대로, 제한 중에도 누를 수 있음, 069 전 DB·로그인 전·남의 경고 없음, 알림 한 줄(내용 없음·이동 없음),
// 운영자 회원 정보의 [경고 보내기]·기록 목록(확인함 / 알림만 읽음 / 아직·함께 건 활동 제한), 운영자에게는 버튼 없음, 처리 기록 이름 「경고」
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import { WARNINGS_NOT_READY } from '../api/warnings';
import { describeNotification } from '../lib/notifications';
import { ACTION_LABEL } from '../components/ModeratorAdmin';
import { fmtDateTime } from '../lib/format';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeLogin, fakeState } from './fakeSupabase';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /></MemoryRouter>);
const asMember = () => fakeLogin('u-me', { nickname: '나', role: 'user', level: 2, main_title: null });
const warn = (id, memo, extra = {}) => TABLES.user_warnings.push({
  id, user_id: 'u-me', memo, created_at: `2026-11-2${id}T03:00:00Z`, created_by: '영자', restriction_id: null, notice_read_at: null, acked_at: null, ...extra,
});
const box = () => screen.findByRole('alert', { name: '운영자 경고' });
const rpcCalls = (name) => fakeState.rpcCalls.filter((c) => c.name === name);

// ---------------- 안내 상자 ----------------

test('안 본 경고: 모든 화면 위에 「운영자 경고를 받았습니다」 + 받은 시각 + 내용, [확인했습니다]를 누르면 닫힌다', async () => {
  asMember();
  warn(1, '욕설을 반복했습니다.\n다음에는 활동 제한입니다.');
  start('/');
  const b = await box();
  expect(b).toHaveTextContent('운영자 경고를 받았습니다');
  expect(b).toHaveTextContent(fmtDateTime('2026-11-21T03:00:00Z'));
  expect(b.querySelector('.warning-band-memo').textContent).toBe('욕설을 반복했습니다.\n다음에는 활동 제한입니다.');
  expect(b).not.toHaveTextContent('(1/'); // 하나면 번호 없음
  fireEvent.click(within(b).getByRole('button', { name: '확인했습니다' }));
  await waitFor(() => expect(screen.queryByRole('alert', { name: '운영자 경고' })).toBeNull());
  expect(rpcCalls('ack_warning')).toEqual([{ name: 'ack_warning', args: { p_id: 1 } }]);
  expect(TABLES.user_warnings[0].acked_at).not.toBeNull();
  cleanup();
  start('/board'); // 다시 열어도 나오지 않는다
  await screen.findByRole('main');
  await new Promise((r) => setTimeout(r, 30));
  expect(screen.queryByRole('alert', { name: '운영자 경고' })).toBeNull();
});

test('여러 개면 오래된 것부터 하나씩 (1/2 → 다음 것)', async () => {
  asMember();
  warn(2, '두 번째');
  warn(1, '첫 번째');
  start('/board');
  const b = await box();
  expect(b).toHaveTextContent('(1/2)');
  expect(b).toHaveTextContent('첫 번째');
  fireEvent.click(within(b).getByRole('button', { name: '확인했습니다' }));
  await waitFor(() => expect(screen.getByRole('alert', { name: '운영자 경고' })).toHaveTextContent('두 번째'));
  expect(screen.getByRole('alert', { name: '운영자 경고' })).not.toHaveTextContent('(1/');
  expect(rpcCalls('ack_warning').map((c) => c.args.p_id)).toEqual([1]);
});

test('확인 저장이 실패하면 상자는 그대로, 문장을 보여 준다', async () => {
  asMember();
  warn(1, '도배');
  fakeState.rpcError = '경고를 찾지 못했습니다.';
  start('/');
  const b = await box();
  fireEvent.click(within(b).getByRole('button', { name: '확인했습니다' }));
  await waitFor(() => expect(within(b).getByText('경고를 찾지 못했습니다.')).toBeDefined());
  expect(within(b).getByRole('button', { name: '확인했습니다' })).not.toBeDisabled();
});

test('활동 제한 중에도 [확인했습니다]는 흐리지 않고 눌린다 (쓰기 버튼이 아님)', async () => {
  asMember();
  warn(1, '욕설로 3일 제한합니다.');
  fakeState.restriction = { id: 1, reason: '욕설', ends_at: new Date(Date.now() + 3 * 86400000).toISOString() };
  start('/');
  const b = await box();
  await screen.findByRole('status', { name: '활동 제한 안내' });
  const btn = within(b).getByRole('button', { name: '확인했습니다' });
  expect(btn.closest('[data-write]')).toBeNull();
  fireEvent.click(btn);
  await waitFor(() => expect(screen.queryByRole('alert', { name: '운영자 경고' })).toBeNull());
  expect(rpcCalls('ack_warning')).toHaveLength(1);
});

test('로그인 전·069 전 DB·남의 경고·이미 확인한 경고: 안내 상자가 없다', async () => {
  warn(1, '남의 것', { user_id: 'u-other' });
  warn(2, '이미 확인함', { acked_at: '2026-11-22T00:00:00Z' });
  start('/');
  await screen.findByRole('main');
  await new Promise((r) => setTimeout(r, 30));
  expect(screen.queryByRole('alert', { name: '운영자 경고' })).toBeNull();
  cleanup();
  asMember();
  start('/');
  await screen.findByRole('main');
  await new Promise((r) => setTimeout(r, 30));
  expect(screen.queryByRole('alert', { name: '운영자 경고' })).toBeNull();
  cleanup();
  warn(3, '새 경고');
  fakeState.warningsMissing = true;
  start('/');
  await screen.findByRole('main');
  await new Promise((r) => setTimeout(r, 30));
  expect(screen.queryByRole('alert', { name: '운영자 경고' })).toBeNull();
});

// ---------------- 알림 한 줄 ----------------

test('알림 warning_received: 경고 아이콘·제목, 내용 없음, 누를 곳 없음', () => {
  const d = describeNotification({ kind: 'warning_received', message: '운영자 경고를 받았습니다. 화면 위 안내에서 내용을 확인해 주세요.' });
  expect(d).toEqual({ icon: 'alert', title: '운영자 경고를 받았습니다', subject: null, detail: '내용은 화면 위 안내 상자에서 확인해 주세요.', to: null });
});

test('알림 화면: 경고 알림 한 줄이 링크 없이 보인다', async () => {
  asMember();
  TABLES.notifications.push({
    id: 1, user_id: 'u-me', kind: 'warning_received', message: '운영자 경고를 받았습니다. 화면 위 안내에서 내용을 확인해 주세요.',
    created_at: new Date().toISOString(), read_at: null, proposal_id: null, build_id: null, post_id: null, counter_id: null,
  });
  start('/notifications');
  const line = (await screen.findAllByText('운영자 경고를 받았습니다')).find((el) => el.closest('main') && !el.closest('[aria-label="운영자 경고"]'));
  expect(line).toBeDefined();
  expect(line.closest('a')).toBeNull();
  expect(screen.getByText('내용은 화면 위 안내 상자에서 확인해 주세요.')).toBeDefined();
});

test('처리 기록 이름: warn_user = 경고', () => {
  expect(ACTION_LABEL.warn_user).toBe('경고');
});

// ---------------- 운영자 화면 ----------------

const asOp = () => fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0, main_title: null });
const member = (extra = {}) => TABLES.profiles.push({ id: 'u-bad', nickname: '말썽', role: 'user', level: 2, main_title: null, ...extra });
const section = () => screen.findByRole('region', { name: '경고' });

test('운영자: [경고 보내기] — 내용 필수(앞뒤 공백 지움), 확정하면 기록에 「아직」', async () => {
  asOp();
  member();
  start('/admin/members/u-bad');
  const sec = await section();
  expect(await within(sec).findByText('받은 경고가 없습니다.')).toBeDefined();
  fireEvent.click(within(sec).getByRole('button', { name: '경고 보내기' }));
  const confirm = () => within(sec).getByRole('button', { name: '경고 보내기 확정' });
  expect(confirm()).toBeDisabled();
  fireEvent.change(within(sec).getByLabelText(/경고 내용/), { target: { value: '   ' } });
  expect(confirm()).toBeDisabled();
  fireEvent.change(within(sec).getByLabelText(/경고 내용/), { target: { value: '  욕설 반복  ' } });
  fireEvent.click(confirm());
  await waitFor(() => expect(rpcCalls('warn_user')).toEqual([{ name: 'warn_user', args: { p_user: 'u-bad', p_memo: '욕설 반복' } }]));
  expect(await screen.findByText('말썽님에게 경고를 보냈습니다.')).toBeDefined();
  await waitFor(() => expect(within(sec).getByRole('list', { name: '경고 기록' })).toHaveTextContent('아직'));
  expect(within(sec).getByRole('list', { name: '경고 기록' })).toHaveTextContent('욕설 반복');
  expect(within(sec).getByRole('button', { name: '경고 보내기' })).toBeDefined(); // 또 보낼 수 있다
});

test('운영자: 기록 상태 확인함 / 알림만 읽음 / 아직, 함께 건 활동 제한 번호, 탈퇴한 보낸 사람', async () => {
  asOp();
  member();
  TABLES.user_warnings.push(
    { id: 1, user_id: 'u-bad', memo: '첫 경고', created_at: '2026-11-20T00:00:00Z', created_by: '영자', restriction_id: null, notice_read_at: '2026-11-20T01:00:00Z', acked_at: '2026-11-20T02:00:00Z' },
    { id: 2, user_id: 'u-bad', memo: '둘째 경고', created_at: '2026-11-21T00:00:00Z', created_by: null, restriction_id: 7, notice_read_at: '2026-11-21T01:00:00Z', acked_at: null },
    { id: 3, user_id: 'u-bad', memo: '셋째 경고', created_at: '2026-11-22T00:00:00Z', created_by: '영자', restriction_id: null, notice_read_at: null, acked_at: null },
  );
  start('/admin/members/u-bad');
  const sec = await section();
  const log = await within(sec).findByRole('list', { name: '경고 기록' });
  const items = within(log).getAllByRole('listitem');
  expect(items.map((li) => li.querySelector('strong').textContent)).toEqual(['아직', '알림만 읽음', '확인함']); // 최근 것부터
  expect(items[2]).toHaveTextContent(`확인: ${fmtDateTime('2026-11-20T02:00:00Z')}`);
  expect(items[1]).toHaveTextContent(`알림 읽음: ${fmtDateTime('2026-11-21T01:00:00Z')}`);
  expect(items[1]).toHaveTextContent('활동 제한과 함께 (제한 #7)');
  expect(items[1]).toHaveTextContent('보낸 사람: 탈퇴한');
});

test('운영자: 활동 제한 중인 회원에게 보내면 「함께 기록」 안내', async () => {
  asOp();
  member();
  TABLES.user_restrictions.push({ id: 4, user_id: 'u-bad', reason: '도배', days: 3, starts_at: '2026-11-22T00:00:00Z', ends_at: new Date(Date.now() + 86400000).toISOString(), created_by: '영자', lifted_at: null, lifted_by: null, lift_note: null });
  start('/admin/members/u-bad');
  const sec = await section();
  fireEvent.click(await within(sec).findByRole('button', { name: '경고 보내기' }));
  fireEvent.change(within(sec).getByLabelText(/경고 내용/), { target: { value: '도배로 3일 제한합니다.' } });
  fireEvent.click(within(sec).getByRole('button', { name: '경고 보내기 확정' }));
  expect(await screen.findByText(/지금 걸려 있는 활동 제한과 함께 기록/)).toBeDefined();
  await waitFor(() => expect(within(sec).getByRole('list', { name: '경고 기록' })).toHaveTextContent('제한 #4'));
});

test('운영자: 서버가 거절하면 그 문장을 그대로, 운영자에게는 버튼이 없다', async () => {
  asOp();
  member();
  fakeState.rpcError = '경고 내용은 500자까지 적을 수 있습니다.';
  start('/admin/members/u-bad');
  const sec = await section();
  fireEvent.click(await within(sec).findByRole('button', { name: '경고 보내기' }));
  fireEvent.change(within(sec).getByLabelText(/경고 내용/), { target: { value: '도배' } });
  fireEvent.click(within(sec).getByRole('button', { name: '경고 보내기 확정' }));
  expect(await within(sec).findByRole('alert')).toHaveTextContent('경고 내용은 500자까지 적을 수 있습니다.');
  cleanup();
  fakeState.rpcError = null;
  TABLES.profiles.find((p) => p.id === 'u-bad').role = 'admin';
  start('/admin/members/u-bad');
  const sec2 = await section();
  expect(await within(sec2).findByText('운영자에게는 경고를 보낼 수 없습니다.')).toBeDefined();
  expect(within(sec2).queryByRole('button', { name: '경고 보내기' })).toBeNull();
});

test('운영자: 069 전 DB면 준비 중 안내만 (회원 정보·활동 제한 칸은 그대로)', async () => {
  asOp();
  member();
  fakeState.warningsMissing = true;
  start('/admin/members/u-bad');
  const sec = await section();
  expect(await within(sec).findByText(WARNINGS_NOT_READY)).toBeDefined();
  expect(within(sec).queryByRole('button', { name: '경고 보내기' })).toBeNull();
  expect(screen.getByRole('list', { name: '말썽 회원 정보' })).toBeDefined();
  expect(await within(await screen.findByRole('region', { name: '활동 제한' })).findByRole('button', { name: '활동 제한 걸기' })).toBeDefined();
});
