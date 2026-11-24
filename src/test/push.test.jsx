// 웹 푸시 (037): 켤 수 있는 환경 판정 · [계정 설정] 휴대폰 알림 · 로그아웃·탈퇴 정리 · 알림 누르면 이동 ·
// Edge Function web-push (보낼 내용이 화면 알림 목록과 같은지, 비밀 값·만료 처리)
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeLogin, fakeState } from './fakeSupabase';
import { clickMenu } from './menu';
import { PUSH_HELP, keyBytes, pushSupport } from '../lib/push';
import { describeNotification } from '../lib/notifications';
import { handleWorkerMessage } from '../lib/sw';
import { describePush, handlePush } from '../../supabase/functions/web-push/index.ts';

const UA = navigator.userAgent;
beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
  vi.unstubAllEnvs();
  delete navigator.serviceWorker;
  delete window.PushManager;
  delete window.Notification;
  Object.defineProperty(navigator, 'userAgent', { value: UA, configurable: true });
});

function Where() { const l = useLocation(); return <output data-testid="where">{l.pathname}</output>; }
const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /><Where /></MemoryRouter>);
const where = () => screen.getByTestId('where').textContent;
const section = () => screen.findByRole('region', { name: '휴대폰 알림' });

/** 알림을 지원하는 브라우저 흉내 (배포된 사이트 = PROD). grant = 허용 창에서 누를 답 */
function fakeBrowserPush({ permission = 'default', grant = 'granted' } = {}) {
  let sub = null;
  let n = 0;
  const pushManager = {
    getSubscription: async () => sub,
    subscribe: vi.fn(async (opts) => {
      n += 1;
      const endpoint = `https://push.example/device-${n}`;
      const me = { endpoint, options: opts, toJSON: () => ({ endpoint, keys: { p256dh: 'pk', auth: 'ak' } }) };
      me.unsubscribe = vi.fn(async () => { if (sub === me) sub = null; return true; });
      sub = me;
      return me;
    }),
  };
  Object.defineProperty(navigator, 'serviceWorker', { value: { getRegistration: async () => ({ pushManager }) }, configurable: true });
  window.PushManager = function PushManager() {};
  window.Notification = { permission, requestPermission: vi.fn(async () => { window.Notification.permission = grant; return grant; }) };
  vi.stubEnv('PROD', true);
  return { current: () => sub, pushManager };
}

// ---------------- 켤 수 있는 환경 ----------------

describe('pushSupport', () => {
  const base = { ios: false, standalone: false, hasPush: true, permission: 'default', prod: true };
  test.each([
    [{}, 'ok'],
    [{ ios: true }, 'ios-browser'], // 아이폰 Safari 탭: 홈 화면 앱이 아님
    [{ ios: true, standalone: true }, 'ok'], // iOS 16.4+ 홈 화면 앱
    [{ ios: true, standalone: true, hasPush: false }, 'ios-old'], // 홈 화면 앱인데 푸시가 없음 = 16.4 미만
    [{ hasPush: false }, 'unsupported'],
    [{ permission: 'denied' }, 'denied'],
    [{ prod: false }, 'dev'],
    [{ native: true }, 'app'], // 안드로이드 앱: 서비스 워커가 없어 웹 푸시 불가 (SPEC 6-55)
    [{ native: true, ios: true, standalone: false }, 'app'], // iOS 앱: 홈 화면 안내 대신 앱 안내
  ])('%j → %s', (over, kind) => {
    expect(pushSupport({ ...base, ...over })).toBe(kind);
    expect(PUSH_HELP[kind] ?? 'ok').toBeTruthy();
  });
  test('VAPID 공개 키(base64url)를 바이트로', () => {
    expect([...keyBytes('AQID_-8')]).toEqual([1, 2, 3, 255, 239]);
  });
});

// ---------------- [계정 설정] 휴대폰 알림 ----------------

test('알림을 지원하지 않는 브라우저: 안내만, 받을 알림 종류는 보인다 (일반 회원은 "내 상대법·빌드 다시 공개"만)', async () => {
  fakeLogin('u-1', { nickname: '탑고수' });
  start('/me/settings');
  const box = await section();
  expect(box.textContent).toContain(PUSH_HELP.unsupported);
  expect(screen.queryByRole('button', { name: /이 기기에서 알림/ })).toBeNull();
  expect(await screen.findByRole('checkbox', { name: /내 상대법·빌드 다시 공개/ })).toBeChecked();
  expect(screen.queryByRole('checkbox', { name: /운영진 알림/ })).toBeNull();
});

test('아이폰 Safari(홈 화면 앱이 아님): 홈 화면에 추가하라는 안내', async () => {
  Object.defineProperty(navigator, 'userAgent', { value: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)', configurable: true });
  fakeBrowserPush();
  fakeLogin('u-1', { nickname: '탑고수' });
  start('/me/settings');
  expect((await section()).textContent).toContain('[홈 화면에 추가]');
  expect(screen.queryByRole('button', { name: /이 기기에서 알림/ })).toBeNull();
});

test('켜기: 허용 → 새 구독 → 내 계정에 저장 / 끄기: 지우고 구독 끊기', async () => {
  const browser = fakeBrowserPush();
  fakeLogin('u-1', { nickname: '탑고수' });
  start('/me/settings');
  await section();
  fireEvent.click(await screen.findByRole('button', { name: '이 기기에서 알림 켜기' }));
  expect(await screen.findByRole('button', { name: '이 기기에서 알림 끄기' })).toBeDefined();
  expect(window.Notification.requestPermission).toHaveBeenCalled();
  expect(browser.pushManager.subscribe).toHaveBeenCalledWith(expect.objectContaining({ userVisibleOnly: true }));
  expect(fakeState.functionCalls).toContainEqual({ name: 'web-push', body: undefined, method: 'GET' }); // 공개 키는 Edge Function에서
  expect(TABLES.push_subscriptions).toEqual([expect.objectContaining({ user_id: 'u-1', endpoint: 'https://push.example/device-1', p256dh: 'pk', auth: 'ak' })]);

  const sub = browser.current();
  fireEvent.click(screen.getByRole('button', { name: '이 기기에서 알림 끄기' }));
  expect(await screen.findByRole('button', { name: '이 기기에서 알림 켜기' })).toBeDefined();
  expect(TABLES.push_subscriptions).toEqual([]);
  expect(sub.unsubscribe).toHaveBeenCalled();
});

test('허용 창에서 차단하면 안내하고 저장하지 않는다', async () => {
  fakeBrowserPush({ grant: 'denied' });
  fakeLogin('u-1', { nickname: '탑고수' });
  start('/me/settings');
  fireEvent.click(await screen.findByRole('button', { name: '이 기기에서 알림 켜기' }));
  expect((await screen.findByRole('alert')).textContent).toContain('알림이 차단됐습니다');
  expect(TABLES.push_subscriptions).toEqual([]);
});

test('이 기기의 예전 구독(다른 계정이 쓰던 것)은 끊고 새 주소로 저장한다 — 남의 줄은 건드리지 않는다', async () => {
  const browser = fakeBrowserPush({ permission: 'granted' });
  await browser.pushManager.subscribe({});
  const old = browser.current();
  TABLES.push_subscriptions.push({ id: 1, user_id: 'u-other', endpoint: old.endpoint, p256dh: 'x', auth: 'y' });
  fakeLogin('u-1', { nickname: '탑고수' });
  start('/me/settings');
  // 브라우저 구독은 있지만 내 계정 줄이 아니므로 "꺼짐"
  fireEvent.click(await screen.findByRole('button', { name: '이 기기에서 알림 켜기' }));
  await screen.findByRole('button', { name: '이 기기에서 알림 끄기' });
  expect(old.unsubscribe).toHaveBeenCalled();
  expect(TABLES.push_subscriptions.map((r) => [r.user_id, r.endpoint])).toEqual([
    ['u-other', 'https://push.example/device-1'], // RLS: 남의 줄은 못 지움 (다음에 보낼 때 410으로 지워짐)
    ['u-1', 'https://push.example/device-2'],
  ]);
});

test('로그아웃하면 이 기기 알림 주소를 지우고 구독을 끊는다', async () => {
  const browser = fakeBrowserPush({ permission: 'granted' });
  await browser.pushManager.subscribe({});
  const sub = browser.current();
  TABLES.push_subscriptions.push({ id: 1, user_id: 'u-1', endpoint: sub.endpoint, p256dh: 'pk', auth: 'ak' });
  fakeLogin('u-1', { nickname: '탑고수' });
  start('/');
  await clickMenu('로그아웃', 'button');
  await waitFor(() => expect(TABLES.push_subscriptions).toEqual([]));
  expect(sub.unsubscribe).toHaveBeenCalled();
});

test('운영자·감독관: 운영진 알림 칸이 보이고, 바꾸면 내 설정으로 저장된다', async () => {
  fakeLogin('u-mod', { nickname: '감독', role: 'moderator' });
  start('/me/settings');
  const staff = await screen.findByRole('checkbox', { name: '운영진 알림: 새 문의·새 오류 신고·새 신고' });
  expect(staff).toBeChecked();
  fireEvent.click(staff);
  await waitFor(() => expect(TABLES.push_settings).toEqual([expect.objectContaining({ user_id: 'u-mod', staff_new: false, my_results: true })]));
  expect(screen.getByRole('checkbox', { name: /운영진 알림/ })).not.toBeChecked();
  fireEvent.click(screen.getByRole('checkbox', { name: /내 상대법·빌드 다시 공개/ }));
  await waitFor(() => expect(TABLES.push_settings[0]).toEqual(expect.objectContaining({ staff_new: false, my_results: false })));
});

test('운영자 모드를 끈 운영자: 운영진 알림이 오지 않는다는 안내 (운영자 문구는 새 상대법·새 빌드·새 글까지)', async () => {
  fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0, operator_mode: false });
  start('/me/settings');
  expect(await screen.findByRole('checkbox', { name: /운영진 알림: 새 상대법·새 빌드·새 글·새 문의·새 오류 신고·새 신고/ })).toBeDefined();
  expect(await screen.findByText('운영자 모드를 끈 동안에는 오지 않습니다.')).toBeDefined();
});

test('빌드 수정 알림(067): 누구나 보이고 기본 켜짐, 끄면 build_edits=false로 저장 (운영자는 문구가 "모든 빌드")', async () => {
  fakeLogin('u-1', { nickname: '탑고수' });
  start('/me/settings');
  const box = await screen.findByRole('checkbox', { name: /빌드 수정: 내가 만들거나 고친 빌드를 다른 사람이 고쳤을 때/ });
  expect(box).toBeChecked();
  expect(screen.getByText('같은 사람이 10분 안에 또 고치면 한 알림으로 묶습니다. 끄면 알림 목록에도 쌓이지 않습니다.')).toBeDefined();
  fireEvent.click(box);
  await waitFor(() => expect(TABLES.push_settings).toEqual([expect.objectContaining({ user_id: 'u-1', build_edits: false, my_results: true })]));
  expect(box).not.toBeChecked();
  cleanup();
  fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0 });
  start('/me/settings');
  expect(await screen.findByRole('checkbox', { name: /빌드 수정: 누가 빌드를 고치거나 되돌렸을 때 \(운영자는 모든 빌드\)/ })).toBeChecked();
});

test('067 실행 전 DB: 설정 저장은 build_edits 칸 없이 다시 시도해 성공한다', async () => {
  fakeState.buildEditsMissing = true;
  fakeLogin('u-1', { nickname: '탑고수' });
  start('/me/settings');
  fireEvent.click(await screen.findByRole('checkbox', { name: /팔로우한 장인의 새 빌드/ }));
  await waitFor(() => expect(TABLES.push_settings).toEqual([expect.objectContaining({ user_id: 'u-1', follow_builds: false })]));
  expect('build_edits' in TABLES.push_settings[0]).toBe(false);
  expect(screen.queryByRole('alert')).toBeNull();
});

test('저장된 설정을 읽어 보여 준다', async () => {
  TABLES.push_settings.push({ user_id: 'u-1', staff_new: true, my_results: false });
  fakeLogin('u-1', { nickname: '탑고수' });
  start('/me/settings');
  expect(await screen.findByRole('checkbox', { name: /내 상대법·빌드 다시 공개/ })).not.toBeChecked();
});

// ---------------- 알림을 누르면 이동 ----------------

test('서비스 워커가 OPEN_PATH를 보내면 그 주소로 이동한다 (사이트 밖 주소는 무시)', async () => {
  start('/');
  await screen.findByRole('button', { name: /^메뉴 열기/ });
  act(() => handleWorkerMessage({ type: 'OPEN_PATH', path: '//evil.test/x' }));
  expect(where()).toBe('/');
  act(() => handleWorkerMessage({ type: 'OPEN_PATH', path: '/privacy' }));
  await waitFor(() => expect(where()).toBe('/privacy'));
});

test('푸시가 오면(PUSH_RECEIVED) 빨간 점을 다시 센다', () => {
  const seen = vi.fn();
  window.addEventListener('tlc:notifications-changed', seen);
  handleWorkerMessage({ type: 'PUSH_RECEIVED' });
  window.removeEventListener('tlc:notifications-changed', seen);
  expect(seen).toHaveBeenCalledTimes(1);
});

// ---------------- Edge Function web-push ----------------

const PUSH_KINDS = ['proposal_approved', 'proposal_rejected', 'build_approved', 'build_rejected', 'revision_request',
  'counter_restored', 'build_restored', 'proposal_submitted', 'build_submitted', 'inquiry_received'];

describe('describePush: 잠금 화면 내용이 알림 목록과 같은 곳으로 간다', () => {
  test.each(PUSH_KINDS.flatMap((kind) => [
    [kind, { proposal_id: 7, build_id: null }],
    [kind, { proposal_id: null, build_id: 9 }],
  ]))('%s %j', (kind, refs) => {
    const n = { id: 1, kind, message: '메모 내용', ...refs };
    const push = describePush(n);
    const row = describeNotification({ ...n, proposal: null, build: null });
    expect(push.url).toBe(row.to ?? '/notifications');
    if (!kind.endsWith('_submitted') && kind !== 'inquiry_received') {
      expect(push.title).toBe(row.title);
      expect(push.body).toBe(row.detail);
    } else {
      expect(push.body).toBe('메모 내용');
    }
    expect(push.tag).toBe('n-1');
  });
  test.each(['matchup_created', 'build_created'])('%s (038): 그 상대법으로, 빌드를 고른 채로 — 알림 목록과 같은 곳', (kind) => {
    const n = { id: 3, kind, message: '새 상대법이 등록됐습니다.', proposal_id: null, build_id: 12, counter_id: 4, target_champion: 'Darius', counter_champion: 'Quinn' };
    const push = describePush(n);
    expect(push).toMatchObject({ title: '운영진 알림', body: '새 상대법이 등록됐습니다.', url: '/champion/Darius/counter/Quinn?build=12' });
    const counter = { target_champion: 'Darius', counter_champion: 'Quinn' };
    expect(describeNotification({ ...n, counter, build: { counter } }).to).toBe(push.url);
    // 상대법 정보가 없으면(옛 DB) 알림 목록으로
    expect(describePush({ id: 3, kind, message: null, proposal_id: null, build_id: 12 }).url).toBe('/notifications');
  });
  test('build_edited (067): Edge Function은 그대로 — 휴대폰 알림은 「탑신병자」 + DB 문장, 누르면 알림 목록 (그 줄에서 다시 이동)', () => {
    const n = { id: 5, kind: 'build_edited', message: '고침이님이 회원님의 빌드를 수정했습니다.', proposal_id: null, build_id: 12, counter_id: 4 };
    expect(describePush(n)).toEqual({ title: '탑신병자', body: '고침이님이 회원님의 빌드를 수정했습니다.', url: '/notifications', tag: 'n-5' });
  });
  test('post_created (042): 새 글로 — 알림 목록과 같은 곳, 글 번호가 없으면 알림 목록', () => {
    const n = { id: 4, kind: 'post_created', message: '새 글이 올라왔습니다. 「탑 라인 질문」', proposal_id: null, build_id: null, post_id: 31 };
    const push = describePush(n);
    expect(push).toMatchObject({ title: '운영진 알림', body: '새 글이 올라왔습니다. 「탑 라인 질문」', url: '/board/31', tag: 'n-4' });
    expect(describeNotification({ ...n, counter: null }).to).toBe(push.url);
    expect(describeNotification({ ...n, counter: null }).title).toBe(n.message);
    expect(describePush({ ...n, post_id: null }).url).toBe('/notifications');
  });
  test('error_reported (043): 신고 화면 "오류 신고" 탭으로 — 알림 목록과 같은 곳', () => {
    const n = { id: 5, kind: 'error_reported', message: '새 오류 신고가 들어왔습니다. (내용이 틀림)', proposal_id: null, build_id: 12 };
    const push = describePush(n);
    expect(push).toMatchObject({ title: '운영진 알림', body: n.message, url: '/admin/reports?tab=wiki', tag: 'n-5' });
    expect(describeNotification({ ...n, counter: null, build: null }).to).toBe(push.url);
  });
  test('report_received (045): 신고 화면 "글·댓글 신고" 탭(기본 탭)으로 — 알림 목록과 같은 곳, 옛 화면이 모르는 종류는 이동 없음', () => {
    const n = { id: 6, kind: 'report_received', message: '새 신고가 들어왔습니다. (글)', proposal_id: null, build_id: null, post_id: 31 };
    const push = describePush(n);
    expect(push).toMatchObject({ title: '운영진 알림', body: n.message, url: '/admin/reports', tag: 'n-6' });
    expect(describeNotification({ ...n, counter: null, post: null }).to).toBe(push.url);
    // 문서 댓글 신고는 둘째 줄에 [문서 댓글] 매치업
    const doc = { ...n, message: '새 신고가 들어왔습니다. (문서 댓글)', post_id: null, counter_id: 1, counter: { target_champion: 'Darius', counter_champion: 'Quinn', status: 'approved' } };
    expect(describeNotification(doc, (id) => ({ Darius: '다리우스', Quinn: '퀸' })[id])).toMatchObject({
      title: doc.message, subject: '[문서 댓글] 퀸으로 다리우스 이기는 법', to: '/admin/reports',
    });
    // 이 파일 이전 배포는 모르는 종류를 종 모양 + 문장으로만 보여 주고 이동하지 않는다 (fallback)
    expect(describeNotification({ kind: 'some_future_kind', message: '새 알림' })).toMatchObject({ icon: 'bell', title: '새 알림', to: null });
  });
  test('긴 메모는 잘라서 보낸다, 메모가 없으면 안내 문구', () => {
    expect([...describePush({ id: 1, kind: 'proposal_rejected', message: '가'.repeat(300) }).body].length).toBe(120);
    expect(describePush({ id: 1, kind: 'proposal_approved', message: null }).body).toBe('눌러서 확인해 주세요.');
  });
});

describe('handlePush', () => {
  const env = (vals) => ({ get: (k) => vals[k] });
  const ENV = env({ VAPID_PUBLIC_KEY: 'pub', PUSH_WEBHOOK_SECRET: 's' });
  const post = (body, secret = 's') => new Request('https://fn.test', {
    method: 'POST', headers: { 'content-type': 'application/json', ...(secret ? { 'x-push-secret': secret } : {}) }, body: JSON.stringify(body),
  });
  const deps = (subs, fail = {}) => ({
    targets: vi.fn(async () => ({ data: { notification: { id: 5, kind: 'proposal_approved', message: '좋습니다', proposal_id: 7, build_id: null }, subscriptions: subs }, error: null })),
    forget: vi.fn(async (ids) => ({ data: ids.length, error: null })),
    send: vi.fn(async (s) => { if (fail[s.id]) throw Object.assign(new Error('x'), { statusCode: fail[s.id] }); }),
  });

  test('GET: 공개 키만 돌려준다 (설정 전이면 503)', async () => {
    expect(await (await handlePush(new Request('https://fn.test'), ENV, deps([]))).json()).toEqual({ publicKey: 'pub' });
    expect((await handlePush(new Request('https://fn.test'), env({}), deps([]))).status).toBe(503);
  });
  test('POST: 비밀 값이 없거나 틀리면 거절, 보내지 않는다', async () => {
    const d = deps([{ id: 1, endpoint: 'https://e/1', p256dh: 'k', auth: 'a' }]);
    expect((await handlePush(post({ notification_id: 5 }, null), ENV, d)).status).toBe(401);
    expect((await handlePush(post({ notification_id: 5 }, 'wrong'), ENV, d)).status).toBe(401);
    expect((await handlePush(post({ notification_id: 'x' }), ENV, d)).status).toBe(400);
    expect(d.targets).not.toHaveBeenCalled();
  });
  test('POST: 기기마다 보내고, 404·410은 지운다 (다른 실패는 남겨 둔다)', async () => {
    const subs = [1, 2, 3, 4].map((id) => ({ id, endpoint: `https://e/${id}`, p256dh: 'k', auth: 'a' }));
    const d = deps(subs, { 2: 410, 3: 404, 4: 500 });
    const res = await (await handlePush(post({ notification_id: 5 }), ENV, d)).json();
    expect(res).toEqual({ ok: true, sent: 1, failed: 1, expired: 2 });
    expect(d.targets).toHaveBeenCalledWith(5);
    expect(d.forget).toHaveBeenCalledWith([2, 3]);
    expect(JSON.parse(d.send.mock.calls[0][1])).toEqual({ title: '제안이 승인됐습니다', body: '승인 메모: 좋습니다', url: '/me/proposals/7', tag: 'n-5' });
  });
  test('POST: 보낼 기기가 없으면 아무것도 안 함', async () => {
    const d = deps([]);
    expect(await (await handlePush(post({ notification_id: 5 }), ENV, d)).json()).toEqual({ ok: true, sent: 0 });
    expect(d.send).not.toHaveBeenCalled();
  });
});

// ---------------- 1.3 패치 2-F (074, SPEC 6-107): 댓글·답글 휴대폰 알림 ----------------
describe('댓글 알림 설정 (push_settings.comments)', () => {
  const COMMENTS = /댓글: 내 글·내가 제안한 상대법에 댓글이, 내 댓글에 답글이 달렸을 때/;
  test('누구나 보이고 기본 켜짐, 끄면 comments=false로 저장 (다른 설정은 그대로)', async () => {
    fakeLogin('u-1', { nickname: '탑고수' });
    start('/me/settings');
    const box = await screen.findByRole('checkbox', { name: COMMENTS });
    expect(box).toBeChecked();
    expect(screen.getByText('확인하지 않은 댓글 알림이 있는 동안에는 다시 울리지 않습니다. 꺼 두어도 알림 목록에는 쌓입니다.')).toBeDefined();
    fireEvent.click(box);
    await waitFor(() => expect(TABLES.push_settings).toEqual([expect.objectContaining({
      user_id: 'u-1', comments: false, staff_new: true, my_results: true, follow_builds: true, notice: true, new_followers: false, build_edits: true,
    })]));
    expect(box).not.toBeChecked();
    fireEvent.click(box);
    await waitFor(() => expect(TABLES.push_settings[0].comments).toBe(true));
  });
  test('다른 칸을 바꿔도 댓글 설정은 그대로 저장된다 (끈 상태 유지)', async () => {
    TABLES.push_settings.push({ user_id: 'u-1', staff_new: true, my_results: true, comments: false });
    fakeLogin('u-1', { nickname: '탑고수' });
    start('/me/settings');
    expect(await screen.findByRole('checkbox', { name: COMMENTS })).not.toBeChecked();
    fireEvent.click(screen.getByRole('checkbox', { name: /공지: 운영자가 새 공지를 올렸을 때/ }));
    await waitFor(() => expect(TABLES.push_settings[0]).toEqual(expect.objectContaining({ notice: false, comments: false })));
  });
  test('설정 줄이 없거나 옛 줄(comments 칸 없음)이면 켜짐으로 보인다', async () => {
    TABLES.push_settings.push({ user_id: 'u-1', staff_new: true, my_results: false });
    fakeLogin('u-1', { nickname: '탑고수' });
    start('/me/settings');
    expect(await screen.findByRole('checkbox', { name: COMMENTS })).toBeChecked();
  });
  test('074 실행 전 DB: comments 칸 없이 다시 저장해 성공한다 (오류 안내 없음)', async () => {
    fakeState.commentsPushMissing = true;
    fakeLogin('u-1', { nickname: '탑고수' });
    start('/me/settings');
    fireEvent.click(await screen.findByRole('checkbox', { name: /팔로우한 장인의 새 빌드/ }));
    await waitFor(() => expect(TABLES.push_settings).toEqual([expect.objectContaining({ user_id: 'u-1', follow_builds: false, build_edits: true })]));
    expect('comments' in TABLES.push_settings[0]).toBe(false);
    expect(screen.queryByRole('alert')).toBeNull();
  });
  test('067·074 둘 다 실행 전 DB: 두 칸 모두 빼고 저장된다', async () => {
    fakeState.commentsPushMissing = true;
    fakeState.buildEditsMissing = true;
    fakeLogin('u-1', { nickname: '탑고수' });
    start('/me/settings');
    fireEvent.click(await screen.findByRole('checkbox', { name: /팔로우한 장인의 새 빌드/ }));
    await waitFor(() => expect(TABLES.push_settings).toEqual([expect.objectContaining({ user_id: 'u-1', follow_builds: false })]));
    expect('comments' in TABLES.push_settings[0] || 'build_edits' in TABLES.push_settings[0]).toBe(false);
    expect(screen.queryByRole('alert')).toBeNull();
  });
  test('문구는 합니다체, 안내 문장은 380px 화면에서도 줄바꿈되는 짧은 문장 두 개', async () => {
    fakeLogin('u-1', { nickname: '탑고수' });
    start('/me/settings');
    const box = await screen.findByRole('checkbox', { name: COMMENTS });
    const row = box.closest('label');
    expect(row.className).toBe('check-row'); // 다른 칸과 같은 줄 모양(체크 상자 + 줄바꿈되는 글)
    const hint = row.querySelector('small.hint');
    expect(hint.textContent.split('. ').every((s) => /니다\.?$/.test(s))).toBe(true); // 문장마다 「…니다.」
    expect(row.textContent).not.toMatch(/[a-zA-Z]{12,}/); // 끊기지 않는 긴 낱말 없음
  });
});

describe('describePush: 댓글·답글 (074) — 알림 목록과 같은 문장·같은 곳', () => {
  const NAME = (id) => ({ Darius: '다리우스', Garen: '가렌' })[id] ?? id;
  const counter = { target_champion: 'Darius', counter_champion: 'Garen', status: 'approved' };
  const CASES = [
    ['post_comment 처음', { kind: 'post_comment', message: '내 글 「탑 라인 질문」에 새 댓글이 달렸습니다.', post_id: 31 }, '새 댓글', '/board/31'],
    ['post_comment 합쳐짐', { kind: 'post_comment', message: '내 글 「탑 라인 질문」에 새 댓글 3개가 달렸습니다.', post_id: 31 }, '새 댓글', '/board/31'],
    ['doc_comment', { kind: 'doc_comment', message: '내가 제안한 상대법 문서에 새 댓글 2개가 달렸습니다.', counter_id: 4 }, '새 댓글', '/champion/Darius/counter/Garen#comments'],
    ['comment_reply 글', { kind: 'comment_reply', message: '「탑 라인 질문」에 쓴 내 댓글에 새 답글이 달렸습니다.', post_id: 31, counter_id: null }, '새 답글', '/board/31'],
    ['comment_reply 문서', { kind: 'comment_reply', message: '상대법 문서에 쓴 내 댓글에 새 답글 4개가 달렸습니다.', post_id: null, counter_id: 4 }, '새 답글', '/champion/Darius/counter/Garen#comments'],
  ];
  test.each(CASES)('%s', (_label, refs, title, url) => {
    const n = { id: 9, proposal_id: null, build_id: null, post_id: null, ...refs,
      ...(refs.counter_id ? { target_champion: 'Darius', counter_champion: 'Garen' } : {}) };
    const push = describePush(n);
    expect(push).toEqual({ title, body: refs.message, url, tag: 'n-9' });
    // 알림 목록: 제목 = 같은 DB 문장(「새 댓글 N개」 포함), 누르면 같은 곳
    const row = describeNotification({ ...n, counter: refs.counter_id ? counter : null }, NAME);
    expect(row.title).toBe(push.body);
    expect(row.to).toBe(push.url);
  });
  test('갈 곳을 모르면 알림 목록 (글 번호 없음 · 상대법 정보 없음), 문장이 없으면 안내 문구', () => {
    expect(describePush({ id: 1, kind: 'post_comment', message: '내 글에 새 댓글이 달렸습니다.', proposal_id: null, build_id: null, post_id: null }).url).toBe('/notifications');
    expect(describePush({ id: 1, kind: 'doc_comment', message: 'x', proposal_id: null, build_id: null, counter_id: 4 }).url).toBe('/notifications');
    expect(describePush({ id: 1, kind: 'comment_reply', message: null, proposal_id: null, build_id: null, post_id: 31 }))
      .toMatchObject({ title: '새 답글', body: '눌러서 확인해 주세요.', url: '/board/31' });
  });
  test('긴 글 제목이 든 문장은 120자로 자른다, " 메모: " 뒤는 보내지 않는다 (알림 목록 제목과 같은 규칙)', () => {
    const long = `내 글 「${'가'.repeat(200)}」에 새 댓글이 달렸습니다.`;
    expect([...describePush({ id: 1, kind: 'post_comment', message: long, proposal_id: null, build_id: null, post_id: 1 }).body].length).toBe(120);
    expect(describePush({ id: 1, kind: 'post_comment', message: '내 글에 새 댓글이 달렸습니다. 메모: 숨김', proposal_id: null, build_id: null, post_id: 1 }).body)
      .toBe('내 글에 새 댓글이 달렸습니다.');
  });
  test('댓글 숨김·삭제·다시 공개 알림은 여전히 푸시 대상이 아니다 (DB 묶음 없음) — 혹시 오면 예전처럼 「탑신병자」', () => {
    expect(describePush({ id: 1, kind: 'comment_hidden', message: '내 댓글이 숨겨졌습니다.', proposal_id: null, build_id: null }))
      .toMatchObject({ title: '탑신병자', url: '/notifications' });
  });
});
