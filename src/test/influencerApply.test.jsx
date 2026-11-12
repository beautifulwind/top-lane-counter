// 장인 2b 화면 (046, SPEC 6-33): 신청 화면 /me/influencer · 운영자 심사 화면 /admin/influencers · 알림·푸시 · 처리 대기 건수
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeLogin, fakeState } from './fakeSupabase';
import { openMenu } from './menu';
import { describeNotification } from '../lib/notifications';
import { OPERATOR_RIOT_ID, confirmMail, fillOperatorId } from '../lib/influencer';
import { describePush } from '../../supabase/functions/web-push/index.ts';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /></MemoryRouter>);
const rpcCalls = (name) => fakeState.rpcCalls.filter((c) => c.name === name).map((c) => c.args);
const profile = (id) => TABLES.profiles.find((p) => p.id === id);
const asOperator = (extra = {}) => fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0, main_title: null, ...extra });
const type = (label, value) => fireEvent.change(screen.getByLabelText(label), { target: { value } });

/** 신청서 하나를 바로 넣어 둔다 (기존유저 u-old, 희망 닉네임 = 지금 닉네임) */
function seedApp(kind = 'creator', extra = {}) {
  const u = profile('u-old');
  Object.assign(u, { nickname_state: 'pending' });
  TABLES.influencer_applications.push({
    id: 1, user_id: 'u-old', kind, nickname: u.nickname, old_nickname: '옛닉', status: 'pending',
    channel_url: kind === 'grandmaster' ? null : 'https://youtube.com/@toptop',
    official_email: kind === 'grandmaster' ? null : 'biz@toptop.kr',
    riot_id: kind === 'grandmaster' ? '탑고수#KR1' : null, opgg_url: kind === 'grandmaster' ? 'https://op.gg/summoners/kr/x' : null,
    created_at: '2026-11-10T00:00:00Z', expires_at: '2026-11-24T00:00:00Z', extended_count: 0, ended_at: null,
    review_note: null, retry_now: false, nickname_reverted: null, revoked_at: null, revoke_note: null, ...extra,
  });
}

// ---------------- 신청 화면 ----------------

test('마이페이지 [장인 인증] → 신청 화면, 그랜드마스터: 친구 요청 안내(이유·3단계·운영자 계정 복사·안심) → 신청 → 확인 중 + 인증 대기', async () => {
  fakeLogin('u-old');
  const writeText = vi.fn().mockResolvedValue();
  Object.defineProperty(navigator, 'clipboard', { value: { writeText }, configurable: true });
  start('/me');
  fireEvent.click(await screen.findByRole('link', { name: '장인 인증' }));
  expect(await screen.findByRole('heading', { level: 1, name: '장인 인증' })).toBeDefined();
  expect(await screen.findByRole('button', { name: '신청 보내기' })).toBeDisabled();
  expect(screen.queryByLabelText('라이엇 닉네임#태그')).toBeNull(); // 유형을 고르기 전에는 칸이 없다

  fireEvent.click(screen.getByRole('radio', { name: /그랜드마스터 이상/ }));
  const guide = screen.getByLabelText('친구 요청 안내');
  for (const h of ['친구 요청을 보내는 이유', '이렇게 해 주세요', '안심하셔도 됩니다']) expect(within(guide).getByRole('heading', { name: h })).toBeDefined();
  expect(within(guide).getByText(OPERATOR_RIOT_ID)).toBeDefined();
  expect(guide.textContent).toContain(`친구 요청을 보낼 운영자 인증 계정: ${OPERATOR_RIOT_ID}`);
  expect(guide.textContent).not.toContain('(으)로');
  expect(guide.textContent).toMatch(/수락하지 않습니다/);
  fireEvent.click(within(guide).getByRole('button', { name: '운영자 라이엇 닉네임 복사' }));
  expect(writeText).toHaveBeenCalledWith(OPERATOR_RIOT_ID);
  expect(await within(guide).findByText('복사했습니다.')).toBeDefined();
  expect(screen.queryByLabelText('공식 이메일')).toBeNull();
  expect(screen.getByText(/이미 다른 분이 신청한 닉네임·채널·라이엇 닉네임이면/).textContent).toMatch(/문의하기/);

  type('희망 닉네임', '탑장인');
  type('라이엇 닉네임#태그', '탑장인');
  type('op.gg 링크', 'https://op.gg/summoners/kr/x');
  fireEvent.click(screen.getByRole('button', { name: '신청 보내기' }));
  expect(await screen.findByRole('alert')).toHaveTextContent('라이엇 닉네임#태그를 적어 주세요. (예: 닉네임#KR1)');
  expect(rpcCalls('apply_influencer')).toEqual([]);

  type('라이엇 닉네임#태그', '탑장인 # KR1');
  fireEvent.click(screen.getByRole('button', { name: '신청 보내기' }));
  expect(await screen.findByText(`신청을 보냈습니다. 14일 안에 운영자 인증 계정에 친구 요청을 보내 주세요. 친구 요청을 보낼 운영자 인증 계정: ${OPERATOR_RIOT_ID}`)).toHaveAttribute('role', 'status');
  expect(rpcCalls('apply_influencer')).toEqual([{
    p_kind: 'grandmaster', p_nickname: '탑장인', p_channel_url: null, p_email: null, p_riot_id: '탑장인 # KR1', p_opgg_url: 'https://op.gg/summoners/kr/x',
  }]);
  const card = await screen.findByRole('region', { name: '내 신청' });
  expect(within(card).getByText('확인 중', { selector: 'li' })).toHaveAttribute('aria-current', 'step');
  expect(within(card).getByLabelText('친구 요청 안내')).toBeDefined();
  expect(screen.queryByRole('button', { name: '신청 보내기' })).toBeNull(); // 심사 중에는 새 신청 없음
  expect(profile('u-old')).toMatchObject({ nickname: '탑장인', nickname_state: 'pending' });
});

test('크리에이터: 이메일 회신 안내, 이메일·링크 검사 → 보내면 유형에 맞는 칸만 간다', async () => {
  fakeLogin('u-old');
  start('/me/influencer');
  fireEvent.click(await screen.findByRole('radio', { name: /크리에이터/ }));
  const guide = screen.getByLabelText('이메일 회신 안내');
  for (const h of ['이메일로 확인하는 이유', '이렇게 해 주세요', '안심하셔도 됩니다']) expect(within(guide).getByRole('heading', { name: h })).toBeDefined();
  expect(guide.textContent).toMatch(/탑신병자 가입자 본인 확인 이메일입니다/);
  expect(guide.textContent).not.toMatch(/캡처를|캡처 파일/);
  type('채널·방송 링크', 'youtube.com/@x');
  fireEvent.click(screen.getByRole('button', { name: '신청 보내기' }));
  expect(await screen.findByRole('alert')).toHaveTextContent('채널·방송 링크를 https://로 시작하는 주소로 적어 주세요.');
  type('채널·방송 링크', 'https://youtube.com/@x');
  type('공식 이메일', 'nope');
  fireEvent.click(screen.getByRole('button', { name: '신청 보내기' }));
  expect(await screen.findByRole('alert')).toHaveTextContent(/공식 이메일을 적어 주세요/);
  type('공식 이메일', 'biz@x.kr');
  type('희망 닉네임', '[장인]티');
  fireEvent.click(screen.getByRole('button', { name: '신청 보내기' }));
  expect(await screen.findByRole('alert')).toHaveTextContent(/\[장인\]/); // 사칭 금지
  type('희망 닉네임', '기존유저');
  fireEvent.click(screen.getByRole('button', { name: '신청 보내기' }));
  expect(await screen.findByRole('status')).toHaveTextContent('적어 주신 공식 이메일로 확인 메일이 갑니다.');
  expect(rpcCalls('apply_influencer')[0]).toEqual({
    p_kind: 'creator', p_nickname: '기존유저', p_channel_url: 'https://youtube.com/@x', p_email: 'biz@x.kr', p_riot_id: null, p_opgg_url: null,
  });
});

test('DB가 거부하면(이미 신청된 닉네임 등) 그 이유를 그대로 보여 준다', async () => {
  fakeLogin('u-old');
  start('/me/influencer');
  fireEvent.click(await screen.findByRole('radio', { name: /프로게이머/ }));
  type('채널·방송 링크', 'https://team.example/kr');
  type('공식 이메일', 'pr@team.example');
  fakeState.rpcError = '이미 장인 인증을 신청 중인 닉네임입니다. 본인의 닉네임이라면 [문의하기]로 알려 주세요.';
  fakeState.rpcErrorCode = '23505';
  fireEvent.click(screen.getByRole('button', { name: '신청 보내기' }));
  expect(await screen.findByRole('alert')).toHaveTextContent('이미 장인 인증을 신청 중인 닉네임입니다.');
});

test('심사 중: [신청 취소] → 확인 → 취소되고 다시 신청할 수 있다', async () => {
  fakeLogin('u-old');
  seedApp('creator');
  start('/me/influencer');
  const card = await screen.findByRole('region', { name: '내 신청' });
  expect(card.textContent).toMatch(/공식 이메일 biz@toptop\.kr/); // 본인에게는 심사 중 내용이 보인다
  fireEvent.click(within(card).getByRole('button', { name: '신청 취소' }));
  fireEvent.click(within(card).getByRole('button', { name: '신청 취소' })); // 확인 줄의 [신청 취소]
  expect(await screen.findByRole('status')).toHaveTextContent('신청을 취소했습니다.');
  expect(rpcCalls('cancel_influencer_application')).toEqual([{ p_id: 1 }]);
  expect(await screen.findByRole('button', { name: '신청 보내기' })).toBeDefined();
  expect(screen.getByRole('region', { name: '내 신청' }).textContent).toMatch(/취소/);
});

test('반려: 사유와 다시 신청할 수 있는 날짜, 그 전에는 신청서가 없다', async () => {
  fakeLogin('u-old');
  seedApp('grandmaster', { status: 'rejected', ended_at: '2026-11-11T00:00:00Z', review_note: '친구 요청이 오지 않았습니다', riot_id: null, nickname_reverted: '옛닉' });
  profile('u-old').nickname_state = null;
  fakeState.influencerNextAt = new Date(Date.now() + 6 * 86400000).toISOString();
  start('/me/influencer');
  const card = await screen.findByRole('region', { name: '내 신청' });
  expect(card.textContent).toMatch(/반려됐습니다\. 사유: 친구 요청이 오지 않았습니다/);
  expect(card.textContent).toMatch(/부터 다시 신청할 수 있습니다/);
  expect(card.textContent).toMatch(/닉네임을 "옛닉"으로 되돌렸습니다/);
  expect(screen.queryByRole('button', { name: '신청 보내기' })).toBeNull();
});

test('만료: 안내 + 바로 다시 신청', async () => {
  fakeLogin('u-old');
  seedApp('creator', { status: 'expired', ended_at: '2026-11-11T00:00:00Z', official_email: null });
  profile('u-old').nickname_state = null;
  start('/me/influencer');
  expect((await screen.findByRole('region', { name: '내 신청' })).textContent).toMatch(/만료됐습니다\. 다시 신청할 수 있습니다/);
  expect(screen.getByRole('button', { name: '신청 보내기' })).toBeDefined();
});

test('비회원·운영자는 신청할 수 없고, 장인은 인증 정보만, 닉네임 변경 예정이면 먼저 새 닉네임', async () => {
  fakeLogin('u-g', { nickname: '손님', is_guest: true });
  start('/me/influencer');
  expect(await screen.findByText(/구글·카카오로 로그인한 회원만 신청할 수 있습니다/)).toBeDefined();
  expect(screen.queryByRole('radio')).toBeNull();
  cleanup();

  asOperator();
  start('/me/influencer');
  expect(await screen.findByText('운영자 계정은 장인 인증을 신청할 수 없습니다.')).toBeDefined();
  expect(screen.queryByRole('radio')).toBeNull();
  cleanup();

  fakeLogin('u-old');
  Object.assign(profile('u-old'), { influencer: 'pro', influencer_at: '2026-11-01T00:00:00Z' });
  start('/me/influencer');
  const ok = await screen.findByRole('region', { name: '인증된 장인입니다' });
  expect(ok.textContent).toMatch(/유형 프로게이머/);
  expect(ok.querySelector('.inf-tag')).not.toBeNull();
  expect(screen.queryByRole('radio')).toBeNull();
  cleanup();

  Object.assign(profile('u-old'), { influencer: null, nickname_state: 'yielding' });
  start('/me/influencer');
  expect(await screen.findByText(/먼저/)).toHaveTextContent('계정 설정에서 새 닉네임을 정한 뒤 신청해 주세요.');
  expect(screen.queryByRole('radio')).toBeNull();
});

// ---------------- 운영자 심사 화면 ----------------

test('운영자: (a) 신청 — 채널·공식 이메일·확인 메일 문구 복사, 승인은 메모 필수 → 승인되면 장인', async () => {
  seedApp('creator');
  asOperator();
  const writeText = vi.fn().mockResolvedValue();
  Object.defineProperty(navigator, 'clipboard', { value: { writeText }, configurable: true });
  start('/admin/influencers');
  const row = await screen.findByRole('listitem', { name: '장인 신청: 기존유저' });
  expect(within(row).getByRole('link', { name: 'https://youtube.com/@toptop' })).toHaveAttribute('target', '_blank');
  expect(within(row).getByText('biz@toptop.kr')).toBeDefined();
  expect(within(row).getByRole('link', { name: /기존유저/ })).toHaveAttribute('href', '/admin/members/u-old');
  const mail = confirmMail('기존유저');
  expect(mail.body).toMatch(/"기존유저" 닉네임으로 장인 인증을 신청하신 본인이 맞으시면/);
  fireEvent.click(within(row).getByRole('button', { name: '확인 메일 제목 복사' }));
  expect(writeText).toHaveBeenLastCalledWith('탑신병자 가입자 본인 확인 이메일입니다');
  fireEvent.click(within(row).getByRole('button', { name: '확인 메일 본문 복사' }));
  expect(writeText).toHaveBeenLastCalledWith(mail.body);

  fireEvent.click(within(row).getByRole('button', { name: '승인' }));
  const confirm = within(row).getByRole('button', { name: '승인 확정' });
  expect(confirm).toBeDisabled();
  fireEvent.change(within(row).getByLabelText(/승인 메모/), { target: { value: '이메일 회신 확인' } });
  fireEvent.click(confirm);
  expect(await screen.findByRole('status')).toHaveTextContent('"기존유저" 님을 장인으로 승인했습니다.');
  expect(rpcCalls('approve_influencer')).toEqual([{ p_id: 1, p_note: '이메일 회신 확인' }]);
  expect(profile('u-old')).toMatchObject({ influencer: 'creator', nickname_state: null });
  expect(await screen.findByText('처리할 장인 신청이 없습니다.')).toBeDefined();

  fireEvent.click(screen.getByRole('button', { name: '승인' })); // 보기 [승인]
  const done = await screen.findByRole('listitem', { name: '장인 신청: 기존유저' });
  expect(done.textContent).toMatch(/이메일 회신 확인/);
  expect(done.textContent).not.toMatch(/biz@toptop\.kr/); // 끝난 신청은 공식 이메일이 지워졌다
  // 승인된 신청에서 인증 해제 (사유 필수)
  fireEvent.click(within(done).getByRole('button', { name: '인증 해제' }));
  fireEvent.change(within(done).getByLabelText(/해제 사유/), { target: { value: '본인 요청' } });
  fireEvent.click(within(done).getByRole('button', { name: '인증 해제 확정' }));
  expect(await screen.findByRole('status')).toHaveTextContent('"기존유저" 회원의 장인 인증을 해제했습니다.');
  expect(rpcCalls('revoke_influencer')).toEqual([{ p_user: 'u-old', p_note: '본인 요청' }]);
  expect(profile('u-old').influencer).toBeNull();
});

test('운영자: (b) 신청 — 라이엇 닉네임 복사·op.gg 링크, 운영자 계정은 수락하지 않는다는 안내, 반려 옵션 둘', async () => {
  seedApp('grandmaster');
  TABLES.profiles.push({ id: 'u-same', nickname: '기존유저', role: 'user', level: 1 }); // 같은 닉네임 회원
  asOperator();
  start('/admin/influencers');
  const row = await screen.findByRole('listitem', { name: '장인 신청: 기존유저' });
  expect(within(row).getByText('탑고수#KR1')).toBeDefined();
  expect(within(row).getByRole('button', { name: '라이엇 닉네임 복사' })).toBeDefined();
  expect(within(row).getByRole('link', { name: 'https://op.gg/summoners/kr/x' })).toHaveAttribute('rel', 'noopener noreferrer nofollow');
  expect(row.textContent).toContain(`받은 친구 요청에서 위 이름을 찾습니다. 수락하지 않습니다. (운영자 인증 계정: ${OPERATOR_RIOT_ID})`);
  expect(row.textContent).toMatch(/수락하지 않습니다/);
  expect(row.textContent).toMatch(/승인하면 이 회원에게 미리 알림이 가고, 3일 뒤 임시 닉네임으로 바뀝니다/);

  fireEvent.click(within(row).getByRole('button', { name: '반려' }));
  fireEvent.click(within(row).getByRole('checkbox', { name: /닉네임도 되돌리기/ }));
  fireEvent.click(within(row).getByRole('checkbox', { name: /바로 다시 신청 허용/ }));
  fireEvent.change(within(row).getByLabelText(/반려 사유/), { target: { value: '친구 요청이 오지 않았습니다' } });
  fireEvent.click(within(row).getByRole('button', { name: '반려 확정' }));
  expect(await screen.findByRole('status')).toHaveTextContent('"기존유저" 신청을 반려했습니다.');
  expect(rpcCalls('reject_influencer')).toEqual([{ p_id: 1, p_note: '친구 요청이 오지 않았습니다', p_revert_nickname: true, p_retry_now: true }]);
  fireEvent.click(screen.getByRole('button', { name: '반려' })); // 보기 [반려]
  const done = await screen.findByRole('listitem', { name: '장인 신청: 기존유저' });
  expect(done.textContent).toMatch(/바로 다시 신청 허용/);
  expect(done.textContent).toMatch(/닉네임을 "옛닉"으로 되돌림/);
});

test('운영자: [만료일 7일 늘리기] → 새 만료일 안내, 운영진이 쓰는 닉네임과 겹치면 [승인]이 막힌다', async () => {
  seedApp('creator');
  TABLES.profiles.push({ id: 'u-mod', nickname: '기존유저', role: 'moderator', level: 1 });
  asOperator();
  start('/admin/influencers');
  const row = await screen.findByRole('listitem', { name: '장인 신청: 기존유저' });
  expect(within(row).getByRole('button', { name: '승인' })).toBeDisabled();
  expect(row.textContent).toMatch(/운영진이 쓰는 닉네임이라 승인할 수 없습니다/);
  fireEvent.click(within(row).getByRole('button', { name: '만료일 7일 늘리기' }));
  expect(await screen.findByRole('status')).toHaveTextContent(/"기존유저" 신청의 만료일을 2026-12-01 .*까지 늘렸습니다\./);
  expect(rpcCalls('extend_influencer_application')).toEqual([{ p_id: 1 }]);
  expect((await screen.findByRole('listitem', { name: '장인 신청: 기존유저' })).textContent).toMatch(/1번 늘림/);
});

test('운영자 모드를 끄면 심사 화면을 쓸 수 없고, 감독관·일반 회원은 볼 수 없다', async () => {
  asOperator({ operator_mode: false });
  start('/admin/influencers');
  expect(await screen.findByText(/운영자 모드가 꺼져 있어 장인 인증을 심사할 수 없습니다/)).toBeDefined();
  cleanup();
  fakeLogin('u-mod', { nickname: '감독', role: 'moderator', level: 3 });
  start('/admin/influencers');
  expect(await screen.findByText('운영자만 볼 수 있습니다.')).toBeDefined();
});

test('처리 대기 건수: ☰ [관리] 숫자·풍선에 장인 신청, 운영자 페이지 [처리할 장인 신청 N건]', async () => {
  asOperator();
  fakeState.pendingCounts = { inquiries: 1, influencers: 2 };
  start('/admin');
  const menu = await openMenu();
  const link = await menu.findByRole('link', { name: '관리, 처리 대기 3건' });
  expect(link.querySelector('.menu-count').getAttribute('title')).toBe('문의 1 · 장인 신청 2');
  fireEvent.keyDown(await menu.findByRole('button', { name: '메뉴 닫기' }), { key: 'Escape' });
  const go = await screen.findByRole('link', { name: '처리할 장인 신청 2건' });
  expect(go).toHaveAttribute('href', '/admin/influencers');
});

// ---------------- 알림·푸시 ----------------

const MESSAGES = {
  influencer_applied: '장인 인증 신청이 들어왔습니다. (탑장인 · 그랜드마스터 이상)',
  influencer_received: '신청이 접수됐습니다. 14일 안에 운영자 계정 {운영자 닉네임}으로 친구 요청을 보내 주세요. 요청이 도착하면 이 닉네임의 주인이 맞는지 확인합니다. 수락은 하지 않습니다.',
  influencer_expiring: '신청이 3일 뒤 만료됩니다. 아직 친구 요청을 보내지 않았다면 {운영자 닉네임}으로 보내 주세요.',
  influencer_approved: '장인 인증이 완료됐습니다. 이제 닉네임 앞에 "장인" 표시가 붙습니다.',
  influencer_rejected: '장인 인증이 반려됐습니다. 사유: 친구 요청이 오지 않았습니다 · 7일 뒤 다시 신청할 수 있습니다.',
  influencer_expired: '14일 안에 확인이 끝나지 않아 신청이 만료됐습니다. 다시 신청할 수 있습니다.',
  influencer_revoked: '장인 인증이 해제됐습니다. 사유: 본인 요청',
  nickname_reset_soon: '운영 원칙에 따라 3일 뒤 닉네임이 임시 닉네임으로 바뀝니다. 그 전에 새 닉네임을 정해 주세요.',
  nickname_reset: '운영 원칙에 따라 닉네임이 임시 닉네임으로 바뀌었습니다. 새 닉네임을 정해 주세요.',
  link_removed: '프로필에 올린 링크가 운영 원칙에 따라 삭제됐습니다.',
};
const WHERE = {
  influencer_applied: '/admin/influencers', nickname_reset_soon: '/me/settings', nickname_reset: '/me/settings',
  link_removed: '/me/links', // 3b: 링크 관리로
};

test.each(Object.keys(MESSAGES))('알림 %s: 아이콘·문장·누르면 갈 곳, 푸시도 같은 곳', (kind) => {
  const n = { id: 9, kind, message: MESSAGES[kind], proposal_id: null, build_id: null };
  const row = describeNotification(n);
  const to = WHERE[kind] ?? '/me/influencer';
  expect(row.to).toBe(to);
  expect(row.icon).not.toBe(undefined);
  expect(`${row.title}${row.detail ? ` ${row.detail}` : ''}`).toBe(fillOperatorId(MESSAGES[kind]));
  expect(row.title).not.toMatch(/\{운영자 닉네임\}/);
  const push = describePush(n);
  expect(push.url).toBe(to);
  expect(push.body).not.toMatch(/\{운영자 닉네임\}|OPERATOR/); // 잠금 화면에는 운영자 닉네임 대신 "운영자 계정"
  expect(push.title).toBe(kind === 'influencer_applied' ? '운영진 알림' : kind.startsWith('nickname') ? '닉네임 안내' : kind === 'link_removed' ? '장인 링크' : '장인 인증');
});

test('운영자 닉네임 자리표시: 화면은 값 뒤에 조사 없이, 푸시는 "운영자 계정으로", 반려 사유는 둘째 줄', () => {
  expect(fillOperatorId(MESSAGES.influencer_received, '탑신병자#1188'))
    .toMatch(/^신청이 접수됐습니다\. 14일 안에 운영자 인증 계정에 친구 요청을 보내 주세요\(친구 요청을 보낼 계정: 탑신병자#1188\)\. 요청이 도착하면/);
  expect(fillOperatorId(MESSAGES.influencer_expiring, '탑신병자#1188'))
    .toBe('신청이 3일 뒤 만료됩니다. 아직 친구 요청을 보내지 않았다면 운영자 인증 계정에 보내 주세요(친구 요청을 보낼 계정: 탑신병자#1188).');
  expect(fillOperatorId('{운영자 닉네임}으로 가기', '탑신병자#1188')).toBe('운영자 인증 계정(탑신병자#1188)으로 가기');
  for (const m of Object.values(MESSAGES)) expect(fillOperatorId(m)).not.toContain('(으)로');
  expect(describePush({ id: 1, kind: 'influencer_received', message: MESSAGES.influencer_received }).body)
    .toMatch(/^신청이 접수됐습니다\. 14일 안에 운영자 계정으로 친구 요청을 보내 주세요\./);
  expect(describePush({ id: 1, kind: 'influencer_expiring', message: MESSAGES.influencer_expiring }).body).toMatch(/운영자 계정으로 보내 주세요/);
  expect(describeNotification({ kind: 'influencer_rejected', message: MESSAGES.influencer_rejected })).toMatchObject({
    icon: 'ban', title: '장인 인증이 반려됐습니다.', detail: '사유: 친구 요청이 오지 않았습니다 · 7일 뒤 다시 신청할 수 있습니다.',
  });
});

test('알림 화면: 접수 알림을 누르면 신청 화면, 운영자 닉네임이 채워져 보인다', async () => {
  fakeLogin('u-old');
  TABLES.notifications.push({ id: 1, user_id: 'u-old', kind: 'influencer_received', message: MESSAGES.influencer_received, created_at: new Date().toISOString(), read_at: null });
  start('/notifications');
  const link = await screen.findByRole('link', { name: new RegExp(`친구 요청을 보낼 계정: ${OPERATOR_RIOT_ID}`) });
  expect(link).toHaveAttribute('href', '/me/influencer');
});

test('휴대폰 알림 설정 문구: 운영자는 "새 장인 신청", 모두 "장인 인증 결과"', async () => {
  asOperator();
  start('/me/settings');
  await waitFor(() => expect(document.body.textContent).toMatch(/새 장인 신청/));
  expect(document.body.textContent).toMatch(/장인 인증 결과/);
  expect(document.body.textContent).not.toMatch(/인플루언서/);
});
