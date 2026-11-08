// 문의하기 (032, SPEC 6-19): 보내기(비회원·닉네임 전 포함), 내 문의·답변·지우기, 운영진 목록과 답변(감독관은 계정·탈퇴 제외, 분류 옮기기는 운영자만), 답변 알림
// DB가 하는 검사(하루 3건·글자 수·RLS)는 supabase/tests/inquiry_test.sql — 여기서는 화면 흐름과 안내만
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeGuestLogin, fakeLogin, fakeState } from './fakeSupabase';
import { openMenu } from './menu';
import { describeNotification } from '../lib/notifications';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /></MemoryRouter>);
const asMember = () => fakeLogin('u-me', { nickname: '나', role: 'user', level: 2, main_title: null });
const asMod = () => fakeLogin('u-mod', { nickname: '감독', role: 'moderator', level: 3, main_title: null });
const asOp = () => fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0, main_title: null });
const rpcs = (name) => fakeState.rpcCalls.filter((c) => c.name === name).map((c) => c.args);
const row = (id, extra = {}) => ({
  id, user_id: 'u-other', category: 'bug', body: `문의 내용 ${id}`, created_at: '2026-11-08T01:00:00Z', answer: null, answered_at: null,
  user: { nickname: '보낸이', role: 'user', level: 2, main_title: null }, ...extra,
});
const text = 'x'.repeat(12);

test('로그인 전에는 로그인 화면으로 간다', async () => {
  start('/inquiries');
  expect(await screen.findByRole('heading', { name: /로그인/ })).toBeDefined();
});

test('보내기: 분류와 내용(5자 이상)이 있어야 버튼이 켜지고, 보내면 안내 + 내 문의에 보인다', async () => {
  asMember();
  start('/inquiries');
  const send = await screen.findByRole('button', { name: '문의 보내기' });
  expect(screen.getByText(/하루에 3건까지/)).toBeDefined();
  expect(screen.getByText(/개인정보는 적지 말아 주세요/)).toBeDefined();
  expect(screen.getAllByRole('option').map((o) => o.textContent)).toEqual(['분류를 골라 주세요', '오류 신고', '건의', '계정·탈퇴', '기타']);
  expect(send.disabled).toBe(true);
  fireEvent.change(screen.getByLabelText('내용'), { target: { value: '짧음' } });
  fireEvent.change(screen.getByLabelText('분류'), { target: { value: 'bug' } });
  expect(send.disabled).toBe(true); // 5자 미만
  fireEvent.change(screen.getByLabelText('내용'), { target: { value: '  화면이 멈춥니다 확인해 주세요  ' } });
  expect(send.disabled).toBe(false);
  fireEvent.click(send);
  expect(await screen.findByText('문의를 보냈습니다. 답변이 달리면 알림으로 알려 드립니다.')).toBeDefined();
  expect(rpcs('create_inquiry')).toEqual([{ p_category: 'bug', p_body: '  화면이 멈춥니다 확인해 주세요  ' }]);
  const list = await screen.findByRole('list', { name: '내 문의 목록' });
  expect(within(list).getByText('화면이 멈춥니다 확인해 주세요')).toBeDefined();
  expect(within(list).getByText('답변 대기')).toBeDefined();
  expect(screen.getByLabelText('내용').value).toBe(''); // 보낸 뒤 칸을 비운다
});

test('1000자를 넘기면 보낼 수 없다', async () => {
  asMember();
  start('/inquiries');
  fireEvent.change(await screen.findByLabelText('분류'), { target: { value: 'idea' } });
  fireEvent.change(screen.getByLabelText('내용'), { target: { value: 'a'.repeat(1001) } });
  expect(screen.getByRole('button', { name: '문의 보내기' }).disabled).toBe(true);
  fireEvent.change(screen.getByLabelText('내용'), { target: { value: 'a'.repeat(1000) } });
  expect(screen.getByRole('button', { name: '문의 보내기' }).disabled).toBe(false);
});

test('DB가 하루 3건을 막으면 이유를 보여 주고 쓴 내용은 그대로 둔다', async () => {
  asMember();
  fakeState.rpcError = '문의는 하루에 3건까지 보낼 수 있습니다. 내일 다시 보내 주세요.';
  fakeState.rpcErrorCode = 'P0001';
  start('/inquiries');
  fireEvent.change(await screen.findByLabelText('분류'), { target: { value: 'other' } });
  fireEvent.change(screen.getByLabelText('내용'), { target: { value: text } });
  fireEvent.click(screen.getByRole('button', { name: '문의 보내기' }));
  expect((await screen.findByRole('alert')).textContent).toBe('문의는 하루에 3건까지 보낼 수 있습니다. 내일 다시 보내 주세요.');
  expect(screen.getByLabelText('내용').value).toBe(text);
});

test('비회원도 닉네임을 정하기 전에도 문의를 보낼 수 있다 (닉네임 정하기로 쫓겨나지 않는다)', async () => {
  fakeGuestLogin('u-guest', { nickname: null });
  start('/inquiries');
  fireEvent.change(await screen.findByLabelText('분류'), { target: { value: 'account' } });
  fireEvent.change(screen.getByLabelText('내용'), { target: { value: text } });
  fireEvent.click(screen.getByRole('button', { name: '문의 보내기' }));
  expect(await screen.findByText(/문의를 보냈습니다/)).toBeDefined();
  expect(rpcs('create_inquiry')).toEqual([{ p_category: 'account', p_body: text }]);
  expect(screen.queryByRole('heading', { name: /닉네임/ })).toBeNull();
});

test('내 문의만 보이고 답변은 "(운) 답변"으로 보인다, 지우면 사라진다', async () => {
  asMember();
  TABLES.inquiries.push(
    row(1, { user_id: 'u-me', body: '내 문의입니다', answer: '확인했습니다', answered_at: '2026-11-08T05:00:00Z' }),
    row(2), // 남의 문의
  );
  start('/inquiries');
  const list = await screen.findByRole('list', { name: '내 문의 목록' });
  expect(within(list).getAllByRole('listitem')).toHaveLength(1);
  expect(within(list).getByText('내 문의입니다')).toBeDefined();
  expect(within(list).getByText('(운) 답변')).toBeDefined();
  expect(within(list).getByText('확인했습니다')).toBeDefined();
  expect(within(list).getByText('답변 완료')).toBeDefined();
  expect(screen.queryByText('문의 내용 2')).toBeNull();
  fireEvent.click(within(list).getByRole('button', { name: '지우기' }));
  expect(screen.getByText('문의를 지우시겠습니까? 답변도 함께 사라집니다.')).toBeDefined();
  fireEvent.click(screen.getAllByRole('button', { name: '지우기' }).at(-1));
  expect(await screen.findByText('보낸 문의가 없습니다.')).toBeDefined();
  expect(rpcs('delete_my_inquiry')).toEqual([{ p_id: 1 }]);
});

test('☰ 메뉴의 [문의하기]로 들어온다 / 마이페이지에도 [문의 내역]', async () => {
  asMember();
  start('/me');
  const menu = await openMenu();
  expect(menu.getByRole('link', { name: '문의하기' }).getAttribute('href')).toBe('/inquiries');
  expect((await screen.findByRole('link', { name: /문의 내역/ })).getAttribute('href')).toBe('/inquiries');
});

test('일반 회원은 운영진 문의 화면에 못 들어간다', async () => {
  asMember();
  TABLES.inquiries.push(row(1));
  start('/admin/inquiries');
  expect(await screen.findByText('운영자만 볼 수 있습니다.')).toBeDefined();
  expect(screen.queryByText('문의 내용 1')).toBeNull();
});

test('감독관: 계정·탈퇴는 목록에 없고(DB RLS), 답변하면 대기에서 사라지며, 분류 옮기기 버튼은 없다', async () => {
  asMod();
  TABLES.inquiries.push(row(1), row(2, { category: 'account', body: '탈퇴 문의' }), row(3, { user_id: 'u-mod', body: '내가 보낸 문의' }));
  start('/admin/inquiries');
  const waiting = await screen.findByRole('list', { name: '답변 대기 문의' });
  expect(within(waiting).getAllByRole('listitem')).toHaveLength(1); // 계정·탈퇴와 내가 보낸 것은 뺌
  expect(screen.queryByText('탈퇴 문의')).toBeNull();
  expect(screen.getByText(/계정·탈퇴.*운영자만 볼 수 있어/)).toBeDefined();
  expect(within(waiting).queryByRole('button', { name: '분류 옮기기' })).toBeNull();
  fireEvent.click(within(waiting).getByRole('button', { name: '답변 쓰기' }));
  const send = screen.getByRole('button', { name: '답변 보내기' });
  expect(send.disabled).toBe(true);
  fireEvent.change(screen.getByLabelText('답변 (보낸 사람에게 보입니다)'), { target: { value: '  곧 고치겠습니다  ' } });
  fireEvent.click(send);
  expect(await screen.findByText('답변을 보냈습니다. 보낸 사람에게 알림이 갑니다.')).toBeDefined();
  expect(rpcs('answer_inquiry')).toEqual([{ p_id: 1, p_answer: '곧 고치겠습니다' }]);
  expect(await screen.findByText('답변을 기다리는 문의가 없습니다.')).toBeDefined();
  expect(within(screen.getByRole('list', { name: '답변 완료 문의' })).getByText('곧 고치겠습니다')).toBeDefined();
});

test('먼저 답한 분이 있으면 "이미 다른 분이 처리했습니다" 안내 후 목록을 새로고침한다', async () => {
  asMod();
  TABLES.inquiries.push(row(1));
  start('/admin/inquiries');
  fireEvent.click(await screen.findByRole('button', { name: '답변 쓰기' }));
  fireEvent.change(screen.getByLabelText('답변 (보낸 사람에게 보입니다)'), { target: { value: '답변입니다' } });
  TABLES.inquiries[0].answer = '다른 분의 답변'; // 그 사이 다른 운영진이 답함
  TABLES.inquiries[0].answered_at = '2026-11-08T06:00:00Z';
  fireEvent.click(screen.getByRole('button', { name: '답변 보내기' }));
  expect(await screen.findByText('이미 다른 분이 처리했습니다. 목록을 새로고침했습니다.')).toBeDefined();
  expect(screen.queryByRole('alert')).toBeNull();
  expect(within(await screen.findByRole('list', { name: '답변 완료 문의' })).getByText('다른 분의 답변')).toBeDefined();
});

test('운영자: 계정·탈퇴도 보이고, 분류를 옮길 수 있다 (옮기면 감독관에게는 안 보임)', async () => {
  asOp();
  TABLES.inquiries.push(row(1, { category: 'other', body: '계정 문제인데 기타로 보냄' }), row(2, { category: 'account', body: '탈퇴 문의' }));
  start('/admin/inquiries');
  const waiting = await screen.findByRole('list', { name: '답변 대기 문의' });
  expect(within(waiting).getAllByRole('listitem')).toHaveLength(2);
  expect(screen.queryByText(/운영자만 볼 수 있어 이 목록에/)).toBeNull();
  const first = within(waiting).getByText('계정 문제인데 기타로 보냄').closest('li');
  fireEvent.click(within(first).getByRole('button', { name: '분류 옮기기' }));
  const move = within(first).getByRole('button', { name: '옮기기 확정' });
  expect(move.disabled).toBe(true);
  expect(within(first).getAllByRole('option').map((o) => o.textContent)).toEqual(['분류를 골라 주세요', '오류 신고', '건의', '계정·탈퇴']); // 지금 분류는 뺌
  fireEvent.change(within(first).getByLabelText('옮길 분류'), { target: { value: 'account' } });
  fireEvent.click(move);
  expect(await screen.findByText('분류를 "계정·탈퇴"(으)로 옮겼습니다.')).toBeDefined();
  expect(rpcs('set_inquiry_category')).toEqual([{ p_id: 1, p_category: 'account' }]);
  cleanup();
  asMod();
  start('/admin/inquiries');
  expect(await screen.findByText('답변을 기다리는 문의가 없습니다.')).toBeDefined();
});

test('/admin에 "문의" 구역(답변 대기 수 + [문의 보기])이 있다 — 운영자와 감독관 모두', async () => {
  asMod();
  TABLES.inquiries.push(row(1), row(2, { category: 'account' }));
  start('/admin');
  expect(await screen.findByRole('heading', { name: '문의' })).toBeDefined();
  expect(await screen.findByText('답변을 기다리는 문의가 1건 있습니다.')).toBeDefined();
  expect(screen.getByRole('link', { name: '문의 보기' }).getAttribute('href')).toBe('/admin/inquiries');
});

test('답변 알림: 짧은 제목 + 분류, 누르면 /inquiries', () => {
  const n = describeNotification({ id: 1, kind: 'inquiry_answered', message: '"오류 신고" 문의에 답변이 도착했습니다.' });
  expect(n).toMatchObject({ icon: 'comment', title: '문의에 답변이 도착했습니다', detail: '분류: 오류 신고', to: '/inquiries' });
});
