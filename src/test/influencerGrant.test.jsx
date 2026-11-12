// 049 장인 직접 지정 (SPEC 6-35): 회원 정보의 [장인으로 직접 지정] → 유형·메모 → 확인 창 → 지정 → 같은 자리에 [인증 해제]
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeLogin, fakeState } from './fakeSupabase';
import { GRANT_CONFIRM_TEXT } from '../components/InfluencerAdmin';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /></MemoryRouter>);
const rpcCalls = (name) => fakeState.rpcCalls.filter((c) => c.name === name).map((c) => c.args);
const profile = (id) => TABLES.profiles.find((p) => p.id === id);
const asOperator = () => fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0, main_title: null });
const info = () => screen.findByRole('region', { name: '기본 정보' });

test('확인 창 문구', () => {
  expect(GRANT_CONFIRM_TEXT).toBe('신청·확인 절차 없이 바로 장인 표시가 붙습니다.');
});

test('운영자: 유형·메모 → 확인 창 → 지정 → 같은 자리에 [인증 해제], 닉네임 그대로', async () => {
  asOperator();
  start('/admin/members/u-old');
  const box = await info();
  expect(within(box).queryByRole('button', { name: '인증 해제' })).toBeNull();
  fireEvent.click(within(box).getByRole('button', { name: '장인으로 직접 지정' }));
  const form = within(box).getByRole('form', { name: '장인으로 직접 지정' });
  const submit = within(form).getByRole('button', { name: '지정하기' });
  expect(submit).toBeDisabled(); // 유형·메모 둘 다 있어야
  fireEvent.click(within(form).getByRole('radio', { name: '그랜드마스터 이상' }));
  expect(submit).toBeDisabled();
  fireEvent.change(within(form).getByLabelText(/지정 메모/), { target: { value: '   ' } });
  expect(submit).toBeDisabled(); // 빈칸만은 메모가 아님
  fireEvent.change(within(form).getByLabelText(/지정 메모/), { target: { value: ' op.gg 직접 확인 ' } });
  // 공식 이메일·라이엇 닉네임·채널 링크 칸은 없다
  expect(within(form).queryByLabelText(/^(공식 이메일|라이엇|채널)/)).toBeNull();
  fireEvent.click(submit);

  // 확인 창: [취소]하면 아무것도 안 함
  let dialog = screen.getByRole('alertdialog', { name: '장인으로 직접 지정' });
  expect(dialog).toHaveTextContent(GRANT_CONFIRM_TEXT);
  expect(dialog).toHaveTextContent('기존유저 · 그랜드마스터 이상');
  expect(within(dialog).getByRole('button', { name: '취소' })).toHaveFocus();
  fireEvent.click(within(dialog).getByRole('button', { name: '취소' }));
  expect(screen.queryByRole('alertdialog')).toBeNull();
  expect(rpcCalls('grant_influencer')).toEqual([]);

  fireEvent.click(submit);
  dialog = screen.getByRole('alertdialog', { name: '장인으로 직접 지정' });
  fireEvent.click(within(dialog).getByRole('button', { name: '지정' }));
  expect(await screen.findByText('"기존유저" 회원을 장인(그랜드마스터 이상)으로 지정했습니다.')).toHaveAttribute('role', 'status');
  expect(rpcCalls('grant_influencer')).toEqual([{ p_user: 'u-old', p_kind: 'grandmaster', p_note: 'op.gg 직접 확인' }]);
  expect(profile('u-old')).toMatchObject({ nickname: '기존유저', influencer: 'grandmaster' });

  const after = await info();
  expect(await within(after).findByRole('button', { name: '인증 해제' })).toBeDefined();
  expect(within(after).queryByRole('button', { name: '장인으로 직접 지정' })).toBeNull();
  expect(within(after).getByText(/장인 \(그랜드마스터 이상\)/)).toBeDefined();
  // 지정된 회원에게는 기존 influencer_approved 알림
  expect(TABLES.notifications.some((n) => n.user_id === 'u-old' && n.kind === 'influencer_approved')).toBe(true);
});

test('Esc로 확인 창 닫기, DB 거부 문구는 폼 아래에', async () => {
  asOperator();
  start('/admin/members/u-old');
  const box = await info();
  fireEvent.click(within(box).getByRole('button', { name: '장인으로 직접 지정' }));
  fireEvent.click(within(box).getByRole('radio', { name: '크리에이터' }));
  fireEvent.change(within(box).getByLabelText(/지정 메모/), { target: { value: '채널 확인' } });
  fireEvent.click(within(box).getByRole('button', { name: '지정하기' }));
  fireEvent.keyDown(screen.getByRole('alertdialog'), { key: 'Escape' });
  expect(screen.queryByRole('alertdialog')).toBeNull();
  expect(within(box).getByRole('form', { name: '장인으로 직접 지정' })).toBeDefined(); // 폼은 그대로

  fakeState.rpcError = '운영자만 할 수 있습니다.';
  fireEvent.click(within(box).getByRole('button', { name: '지정하기' }));
  fireEvent.click(within(screen.getByRole('alertdialog')).getByRole('button', { name: '지정' }));
  expect(await within(box).findByRole('alert')).toHaveTextContent('운영자만 할 수 있습니다.');
  expect(profile('u-old').influencer ?? null).toBeNull();
});

test('버튼이 없는 회원: 이미 장인([인증 해제]만)·운영자·비회원·신청 처리 전(심사 화면 안내)', async () => {
  asOperator();
  Object.assign(profile('u-old'), { influencer: 'pro', influencer_at: '2026-11-01T00:00:00Z' });
  start('/admin/members/u-old');
  let box = await info();
  expect(within(box).queryByRole('button', { name: '장인으로 직접 지정' })).toBeNull();
  expect(within(box).getByRole('button', { name: '인증 해제' })).toBeDefined();
  cleanup();

  Object.assign(profile('u-old'), { influencer: null, influencer_at: null, nickname_state: 'pending' });
  start('/admin/members/u-old');
  box = await info();
  expect(within(box).queryByRole('button', { name: '장인으로 직접 지정' })).toBeNull();
  expect(within(box).getByText(/심사 중인 회원이라 직접 지정할 수 없습니다/)).toBeDefined();
  expect(within(box).getByRole('link', { name: '장인 인증 심사 화면' })).toHaveAttribute('href', '/admin/influencers');
  cleanup();

  Object.assign(profile('u-old'), { nickname_state: null, is_guest: true });
  start('/admin/members/u-old');
  box = await info();
  expect(within(box).queryByRole('button', { name: '장인으로 직접 지정' })).toBeNull();
  expect(within(box).getByText(/비회원\(구글·카카오 연결 전\)은 장인으로 지정할 수 없습니다/)).toBeDefined();
  cleanup();

  start('/admin/members/u-op');
  box = await info();
  expect(within(box).queryByRole('button', { name: '장인으로 직접 지정' })).toBeNull();
});

test('장인 심사 화면: 끝난 목록의 직접 지정 줄은 "직접 지정" 표시, 신청서 칸 없이 [인증 해제]', async () => {
  asOperator();
  TABLES.influencer_applications.push({
    id: 1, user_id: 'u-old', kind: 'creator', nickname: '기존유저', old_nickname: null, channel_url: null, official_email: null, riot_id: null,
    opgg_url: null, status: 'approved', created_at: '2026-11-12T01:00:00Z', expires_at: '2026-11-12T01:00:00Z', extended_count: 0,
    ended_at: '2026-11-12T01:00:00Z', review_note: '채널 확인', retry_now: false, nickname_reverted: null, revoked_at: null, revoke_note: null,
    direct: true, reviewer: '영자',
  });
  Object.assign(profile('u-old'), { influencer: 'creator', influencer_at: '2026-11-12T01:00:00Z' });
  start('/admin/influencers');
  await screen.findByText('처리할 장인 신청이 없습니다.');
  fireEvent.click(screen.getByRole('button', { name: '승인' })); // 보기 [승인]
  const row = await screen.findByRole('listitem', { name: '장인 신청: 기존유저' });
  expect(row).toHaveTextContent('직접 지정');
  expect(row).toHaveTextContent('운영자가 신청·확인 절차 없이 직접 지정했습니다.');
  expect(row).toHaveTextContent('지정한 회원:');
  expect(within(row).queryByLabelText('이메일 확인')).toBeNull();
  expect(within(row).getByRole('button', { name: '인증 해제' })).toBeDefined();
});
