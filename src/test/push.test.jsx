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
