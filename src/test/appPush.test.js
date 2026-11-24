// @vitest-environment node
// SPEC 6-102 (1.3 패치 P-2): Edge Function web-push의 앱(iOS·Android) 발송.
// 진짜 Apple·Google 키 대신 테스트 안에서 만든 P-256·RSA 키를 쓰고, 외부 호출은 가짜 fetch로 받는다.
import { afterEach, beforeAll, beforeEach, describe, expect, test, vi } from 'vitest';
import {
  APNS_ORIGIN, APP_BUNDLE_ID, APP_PUSH, FCM_SCOPE, GOOGLE_TOKEN_URL,
  apnsChannel, apnsPayload, describePush, fcmChannel, fcmMessage, handlePush, pkcs8FromPem, sendAppPush,
} from '../../supabase/functions/web-push/index.ts';

const b64 = (bytes) => Buffer.from(bytes).toString('base64');
const pem = async (key) => `-----BEGIN PRIVATE KEY-----\n${b64(new Uint8Array(await crypto.subtle.exportKey('pkcs8', key))).match(/.{1,64}/g).join('\n')}\n-----END PRIVATE KEY-----\n`;
const part = (jwt, i) => JSON.parse(Buffer.from(jwt.split('.')[i], 'base64url').toString());
const verifyJwt = (jwt, key, alg) => {
  const [h, c, s] = jwt.split('.');
  return crypto.subtle.verify(alg, key, Buffer.from(s, 'base64url'), new TextEncoder().encode(`${h}.${c}`));
};
const env = (vals) => ({ get: (k) => vals[k] });
const IOS_TOKEN = 'a1b2c3d4'.repeat(8); // 64자 16진수 (APNs 모양)
const IOS_TOKEN2 = 'f0e1d2c3'.repeat(8);
const AND_TOKEN = 'fcmTokenAAA:APA91b' + 'Zz_-'.repeat(30);
const AND_TOKEN2 = 'fcmTokenBBB:APA91b' + 'Yy_-'.repeat(30);
const MSG = { title: '제안이 승인됐습니다', body: '승인 메모: 좋습니다', url: '/me/proposals/7', notificationId: 5 };
const T0 = Date.UTC(2026, 10, 24, 12, 0, 0);

let ec; let rsa; let P8; let SA; let SA_JSON;
beforeAll(async () => {
  ec = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  rsa = await crypto.subtle.generateKey({ name: 'RSASSA-PKCS1-v1_5', modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: 'SHA-256' }, true, ['sign', 'verify']);
  P8 = await pem(ec.privateKey);
  SA = { type: 'service_account', project_id: 'tsb-test', client_email: 'push@tsb-test.iam.gserviceaccount.com', private_key: await pem(rsa.privateKey), token_uri: 'https://evil.example/token' };
  SA_JSON = JSON.stringify(SA);
});
const IOS_ENV = () => env({ APNS_KEY_P8: P8, APNS_KEY_ID: 'KEYID12345', APNS_TEAM_ID: 'TEAMID1234' });
const AND_ENV = () => env({ FCM_SERVICE_ACCOUNT_JSON: SA_JSON });

// 가짜 fetch: 주소별 응답 함수. 부른 내용을 calls에 남긴다
function fakeFetch(routes) {
  const calls = [];
  const f = vi.fn(async (url, init = {}) => {
    calls.push({ url: String(url), init });
    for (const [prefix, handler] of routes) if (String(url).startsWith(prefix)) return handler(String(url), init, calls.length);
    throw new Error(`unexpected ${url}`);
  });
  f.calls = calls;
  return f;
}
const res = (status, body) => new Response(body == null ? null : JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });
const googleOk = (token = 'ya29.test-access') => () => res(200, { access_token: token, expires_in: 3599, token_type: 'Bearer' });

let logs;
beforeEach(() => {
  logs = [];
  for (const k of ['log', 'warn', 'error']) vi.spyOn(console, k).mockImplementation((...a) => { logs.push(a.map(String).join(' ')); });
});
afterEach(() => vi.restoreAllMocks());

describe('APNs (iOS)', () => {
  test('비밀 값 3개 중 하나라도 없으면 skip (경고 문장에 값 없음)', () => {
    for (const missing of ['APNS_KEY_P8', 'APNS_KEY_ID', 'APNS_TEAM_ID']) {
      const vals = { APNS_KEY_P8: P8, APNS_KEY_ID: 'KEYID12345', APNS_TEAM_ID: 'TEAMID1234' };
      delete vals[missing];
      const ch = apnsChannel(env(vals), vi.fn());
      expect(ch.skip).toMatch(/iOS는 건너뜀/);
      expect(ch.skip).not.toContain('KEYID12345');
    }
  });
  test('JWT ES256: 머리 { alg ES256, kid }, 내용 { iss 팀, iat 50분 칸 }, 테스트 공개 키로 서명 확인', async () => {
    const f = fakeFetch([[APNS_ORIGIN, () => res(200)]]);
    const ch = apnsChannel(IOS_ENV(), f, () => T0 + 7 * 60_000);
    expect(await ch.send(IOS_TOKEN, MSG)).toEqual({ ok: true });
    const jwt = f.calls[0].init.headers.authorization.replace(/^bearer /, '');
    expect(part(jwt, 0)).toEqual({ alg: 'ES256', kid: 'KEYID12345' });
    const claims = part(jwt, 1);
    expect(claims).toEqual({ iss: 'TEAMID1234', iat: Math.floor(Math.floor((T0 + 7 * 60_000) / APP_PUSH.apnsJwtMs) * APP_PUSH.apnsJwtMs / 1000) });
    expect(T0 + 7 * 60_000 - claims.iat * 1000).toBeLessThan(APP_PUSH.apnsJwtMs); // Apple: 1시간보다 묵으면 안 됨
    expect(await verifyJwt(jwt, ec.publicKey, { name: 'ECDSA', hash: 'SHA-256' })).toBe(true);
  });
  test('요청 모양: /3/device/{토큰}, apns-topic = 번들 ID, alert, 우선순위 10, aps alert·sound default, 이동 주소, 시간 제한', async () => {
    const f = fakeFetch([[APNS_ORIGIN, () => res(200)]]);
    await apnsChannel(IOS_ENV(), f, () => T0).send(IOS_TOKEN, MSG);
    const { url, init } = f.calls[0];
    expect(url).toBe(`https://api.push.apple.com/3/device/${IOS_TOKEN}`);
    expect(APP_BUNDLE_ID).toBe('com.topsinbyeongja.app');
    expect(init.method).toBe('POST');
    expect(init.headers).toMatchObject({ 'apns-topic': 'com.topsinbyeongja.app', 'apns-push-type': 'alert', 'apns-priority': '10' });
    expect(JSON.parse(init.body)).toEqual({ aps: { alert: { title: MSG.title, body: MSG.body }, sound: 'default' }, url: '/me/proposals/7', notification_id: '5' });
    expect(JSON.parse(init.body)).toEqual(apnsPayload(MSG));
    expect(init.signal).toBeInstanceOf(AbortSignal);
  });
  test('JWT는 같은 50분 칸에서는 다시 쓰고, 칸이 바뀌면 새로 만든다. ExpiredProviderToken이면 버리고 다시 만든다', async () => {
    const S0 = Math.ceil(T0 / APP_PUSH.apnsJwtMs) * APP_PUSH.apnsJwtMs; // 50분 칸이 막 시작한 시각
    let now = S0;
    const f = fakeFetch([[APNS_ORIGIN, (u, i, n) => (n === 3 ? res(403, { reason: 'ExpiredProviderToken' }) : res(200))]]);
    const sign = vi.spyOn(crypto.subtle, 'sign');
    const ch = apnsChannel(IOS_ENV(), f, () => now);
    await ch.send(IOS_TOKEN, MSG);
    now = S0 + 49 * 60_000;
    await ch.send(IOS_TOKEN, MSG);
    expect(sign).toHaveBeenCalledTimes(1);
    const auth = (i) => f.calls[i].init.headers.authorization;
    expect(auth(1)).toBe(auth(0));
    now = S0 + 51 * 60_000; // 다음 칸
    expect(await ch.send(IOS_TOKEN, MSG)).toEqual({ ok: false, remove: false, code: '403 ExpiredProviderToken' });
    expect(auth(2)).not.toBe(auth(0));
    await ch.send(IOS_TOKEN, MSG); // 거절된 JWT를 버렸으므로 같은 칸이라도 다시 만든다
    expect(sign).toHaveBeenCalledTimes(3);
  });
  test.each([
    [410, { reason: 'Unregistered' }, true],
    [410, { reason: 'ExpiredToken' }, true],
    [400, { reason: 'BadDeviceToken' }, true],
    [400, { reason: 'DeviceTokenNotForTopic' }, true],
    [400, { reason: 'BadPriority' }, false],
    [400, { reason: 'PayloadTooLarge' }, false],
    [403, { reason: 'InvalidProviderToken' }, false],
    [429, { reason: 'TooManyRequests' }, false],
    [500, { reason: 'InternalServerError' }, false],
    [503, null, false],
  ])('APNs %i %j → 지우기 %s', async (status, body, remove) => {
    const f = fakeFetch([[APNS_ORIGIN, () => res(status, body)]]);
    const r = await apnsChannel(IOS_ENV(), f, () => T0).send(IOS_TOKEN, MSG);
    expect(r.ok).toBe(false);
    expect(r.remove).toBe(remove);
    expect(r.code).toBe(body?.reason ? `${status} ${body.reason}` : String(status));
  });
  test('네트워크 오류·시간 초과는 지우지 않는다', async () => {
    const net = await apnsChannel(IOS_ENV(), vi.fn(async () => { throw new TypeError('fetch failed'); }), () => T0).send(IOS_TOKEN, MSG);
    expect(net).toEqual({ ok: false, remove: false, code: 'network' });
    const slow = await apnsChannel(IOS_ENV(), vi.fn(async () => { throw new DOMException('timeout', 'TimeoutError'); }), () => T0).send(IOS_TOKEN, MSG);
    expect(slow).toEqual({ ok: false, remove: false, code: 'timeout' });
  });
  test('.p8 형식이 틀리면 보내지 않고 apns_key 실패 (지우지 않음, 키 내용 출력 없음)', async () => {
    const f = fakeFetch([[APNS_ORIGIN, () => res(200)]]);
    const r = await apnsChannel(env({ APNS_KEY_P8: 'not-a-key!!', APNS_KEY_ID: 'K', APNS_TEAM_ID: 'T' }), f, () => T0).send(IOS_TOKEN, MSG);
    expect(r).toEqual({ ok: false, remove: false, code: 'apns_key' });
    expect(f).not.toHaveBeenCalled();
  });
  test('.p8 내용이 한 줄·글자 그대로 \\n이어도 읽는다', () => {
    const one = P8.replace(/\n/g, '\\n');
    expect(pkcs8FromPem(one)).toEqual(pkcs8FromPem(P8));
    expect(pkcs8FromPem(P8.replace(/\n/g, ''))).toEqual(pkcs8FromPem(P8));
  });
});

describe('FCM (Android)', () => {
  test('비밀 값이 없거나 JSON 형식이 틀리면 skip', () => {
    expect(fcmChannel(env({}), vi.fn()).skip).toMatch(/Android 알림을 건너뜀/);
    expect(fcmChannel(env({ FCM_SERVICE_ACCOUNT_JSON: '{not json' }), vi.fn()).skip).toMatch(/형식/);
    expect(fcmChannel(env({ FCM_SERVICE_ACCOUNT_JSON: JSON.stringify({ project_id: 'p' }) }), vi.fn()).skip).toMatch(/형식/);
  });
  test('JWT RS256 → OAuth 토큰: iss 서비스 계정, scope firebase.messaging, aud 구글 토큰 주소(JSON의 token_uri가 달라도), 1시간, 서명 확인', async () => {
    const f = fakeFetch([[GOOGLE_TOKEN_URL, googleOk()], ['https://fcm.googleapis.com/', () => res(200, { name: 'projects/tsb-test/messages/1' })]]);
    expect(await fcmChannel(AND_ENV(), f, () => T0).send(AND_TOKEN, MSG)).toEqual({ ok: true });
    const tok = f.calls[0];
    expect(tok.url).toBe('https://oauth2.googleapis.com/token');
    expect(tok.init.headers['content-type']).toBe('application/x-www-form-urlencoded');
    const form = new URLSearchParams(tok.init.body);
    expect(form.get('grant_type')).toBe('urn:ietf:params:oauth:grant-type:jwt-bearer');
    const jwt = form.get('assertion');
    expect(part(jwt, 0)).toEqual({ alg: 'RS256', typ: 'JWT' });
    expect(part(jwt, 1)).toEqual({ iss: SA.client_email, scope: FCM_SCOPE, aud: GOOGLE_TOKEN_URL, iat: T0 / 1000, exp: T0 / 1000 + 3600 });
    expect(FCM_SCOPE).toBe('https://www.googleapis.com/auth/firebase.messaging');
    expect(await verifyJwt(jwt, rsa.publicKey, { name: 'RSASSA-PKCS1-v1_5' })).toBe(true);
    expect(tok.init.signal).toBeInstanceOf(AbortSignal);
  });
  test('보내기 요청: projects/{project_id}/messages:send, Bearer, notification·data(이동 주소)·android 높은 우선순위', async () => {
    const f = fakeFetch([[GOOGLE_TOKEN_URL, googleOk()], ['https://fcm.googleapis.com/', () => res(200, {})]]);
    await fcmChannel(AND_ENV(), f, () => T0).send(AND_TOKEN, MSG);
    const { url, init } = f.calls[1];
    expect(url).toBe('https://fcm.googleapis.com/v1/projects/tsb-test/messages:send');
    expect(init.headers).toMatchObject({ authorization: 'Bearer ya29.test-access', 'content-type': 'application/json' });
    expect(JSON.parse(init.body)).toEqual({
      message: { token: AND_TOKEN, notification: { title: MSG.title, body: MSG.body }, data: { url: '/me/proposals/7', notification_id: '5' }, android: { priority: 'HIGH' } },
    });
    expect(JSON.parse(init.body)).toEqual(fcmMessage(AND_TOKEN, MSG));
    expect(init.signal).toBeInstanceOf(AbortSignal);
  });
  test('액세스 토큰: 55분 재사용, 동시에 보내도 한 번만 받음, 지나면 새로, 401이면 버림', async () => {
    let now = T0;
    let fcmStatus = 200;
    const f = fakeFetch([[GOOGLE_TOKEN_URL, googleOk()], ['https://fcm.googleapis.com/', () => res(fcmStatus, fcmStatus === 200 ? {} : { error: { status: 'UNAUTHENTICATED' } })]]);
    const ch = fcmChannel(AND_ENV(), f, () => now);
    await Promise.all([ch.send(AND_TOKEN, MSG), ch.send(AND_TOKEN2, MSG), ch.send(AND_TOKEN, MSG)]);
    const tokenCalls = () => f.calls.filter((c) => c.url === GOOGLE_TOKEN_URL).length;
    expect(tokenCalls()).toBe(1);
    now = T0 + 54 * 60_000;
    await ch.send(AND_TOKEN, MSG);
    expect(tokenCalls()).toBe(1);
    now = T0 + 56 * 60_000;
    await ch.send(AND_TOKEN, MSG);
    expect(tokenCalls()).toBe(2);
    fcmStatus = 401;
    expect(await ch.send(AND_TOKEN, MSG)).toEqual({ ok: false, remove: false, code: '401 UNAUTHENTICATED' });
    fcmStatus = 200;
    await ch.send(AND_TOKEN, MSG);
    expect(tokenCalls()).toBe(3);
  });
  const fcmErr = (status, errorCode, extra = {}) => ({ error: { code: 0, message: extra.message ?? 'x', status, details: [
    ...(errorCode ? [{ '@type': 'type.googleapis.com/google.firebase.fcm.v1.FcmError', errorCode }] : []),
    ...(extra.field ? [{ '@type': 'type.googleapis.com/google.rpc.BadRequest', fieldViolations: [{ field: extra.field, description: 'bad' }] }] : []),
  ] } });
  test.each([
    ['404 UNREGISTERED', 404, fcmErr('NOT_FOUND', 'UNREGISTERED'), true],
    ['400 토큰 칸 INVALID_ARGUMENT', 400, fcmErr('INVALID_ARGUMENT', 'INVALID_ARGUMENT', { field: 'message.token' }), true],
    ['400 registration token 문장', 400, fcmErr('INVALID_ARGUMENT', 'INVALID_ARGUMENT', { message: 'The registration token is not a valid FCM registration token' }), true],
    ['400 다른 칸 INVALID_ARGUMENT', 400, fcmErr('INVALID_ARGUMENT', 'INVALID_ARGUMENT', { field: 'message.data' }), false],
    ['403 SENDER_ID_MISMATCH', 403, fcmErr('PERMISSION_DENIED', 'SENDER_ID_MISMATCH'), false],
    ['429 QUOTA_EXCEEDED', 429, fcmErr('RESOURCE_EXHAUSTED', 'QUOTA_EXCEEDED'), false],
    ['500 INTERNAL', 500, fcmErr('INTERNAL', 'INTERNAL'), false],
    ['503 UNAVAILABLE', 503, fcmErr('UNAVAILABLE', 'UNAVAILABLE'), false],
  ])('FCM %s → 지우기 %s', async (_label, status, body, remove) => {
    const f = fakeFetch([[GOOGLE_TOKEN_URL, googleOk()], ['https://fcm.googleapis.com/', () => res(status, body)]]);
    const r = await fcmChannel(AND_ENV(), f, () => T0).send(AND_TOKEN, MSG);
    expect(r).toMatchObject({ ok: false, remove });
    expect(r.code.startsWith(String(status))).toBe(true);
  });
  test('OAuth 토큰을 못 받으면 보내지 않고 실패 (지우지 않음)', async () => {
    const f = fakeFetch([[GOOGLE_TOKEN_URL, () => res(400, { error: 'invalid_grant' })], ['https://fcm.googleapis.com/', () => res(200, {})]]);
    expect(await fcmChannel(AND_ENV(), f, () => T0).send(AND_TOKEN, MSG)).toEqual({ ok: false, remove: false, code: 'fcm_auth 400' });
    expect(f.calls.some((c) => c.url.startsWith('https://fcm.googleapis.com/'))).toBe(false);
  });
});

// ---------------- sendAppPush / handlePush ----------------
const NOTICE = { id: 5, kind: 'proposal_approved', message: '좋습니다', proposal_id: 7, build_id: null };
const tokensOf = (...list) => list.map(([platform, token], i) => ({ id: 100 + i, platform, token }));
function appDeps({ created = new Date(T0 - 10 * 60_000).toISOString(), tokens = tokensOf(['ios', IOS_TOKEN], ['android', AND_TOKEN]), ios, android, recipient } = {}) {
  const iosSend = vi.fn(async () => ({ ok: true }));
  const andSend = vi.fn(async () => ({ ok: true }));
  return {
    recipient: recipient ?? vi.fn(async () => ({ data: { user_id: 'u-1', created_at: created }, error: null })),
    tokens: vi.fn(async () => ({ data: tokens, error: null })),
    forget: vi.fn(async (ids) => ({ data: ids.length, error: null })),
    ios: ios ?? { send: iosSend },
    android: android ?? { send: andSend },
    now: () => T0,
    iosSend, andSend,
  };
}

describe('sendAppPush', () => {
  test('웹 푸시와 같은 제목·본문·이동 주소, 받는 사람의 토큰마다', async () => {
    const app = appDeps();
    const s = await sendAppPush(5, async () => NOTICE, app);
    const d = describePush(NOTICE);
    expect(app.recipient).toHaveBeenCalledWith(5);
    expect(app.tokens).toHaveBeenCalledWith('u-1');
    expect(app.iosSend).toHaveBeenCalledWith(IOS_TOKEN, { title: d.title, body: d.body, url: d.url, notificationId: 5 });
    expect(app.andSend).toHaveBeenCalledWith(AND_TOKEN, { title: d.title, body: d.body, url: d.url, notificationId: 5 });
    expect(s).toEqual({ ios: { tokens: 1, sent: 1, failed: 0, removed: 0 }, android: { tokens: 1, sent: 1, failed: 0, removed: 0 } });
    expect(app.forget).not.toHaveBeenCalled();
  });
  test('1시간 넘은 알림은 토큰도 읽지 않고 건너뜀 (push_targets와 같은 규칙)', async () => {
    const app = appDeps({ created: new Date(T0 - 61 * 60_000).toISOString() });
    expect(await sendAppPush(5, async () => NOTICE, app)).toEqual({ skipped: 'old' });
    expect(app.tokens).not.toHaveBeenCalled();
    expect(app.iosSend).not.toHaveBeenCalled();
    const ok = appDeps({ created: new Date(T0 - 59 * 60_000).toISOString() });
    expect((await sendAppPush(5, async () => NOTICE, ok)).ios.sent).toBe(1);
  });
  test('알림이 없으면·받는 사람 조회 실패면 건너뜀', async () => {
    const none = appDeps({ recipient: vi.fn(async () => ({ data: null, error: null })) });
    expect(await sendAppPush(5, async () => NOTICE, none)).toEqual({ skipped: 'no_notification' });
    const bad = appDeps({ recipient: vi.fn(async () => { throw new Error('db down'); }) });
    expect(await sendAppPush(5, async () => NOTICE, bad)).toEqual({ skipped: 'recipient_error' });
    expect(bad.tokens).not.toHaveBeenCalled();
  });
  test('토큰이 없으면 외부 호출 없음, 요약 로그도 없음', async () => {
    const app = appDeps({ tokens: [] });
    const getNotice = vi.fn(async () => NOTICE);
    expect(await sendAppPush(5, getNotice, app)).toEqual({ skipped: 'no_tokens' });
    expect(app.iosSend).not.toHaveBeenCalled();
    expect(app.andSend).not.toHaveBeenCalled();
    expect(getNotice).not.toHaveBeenCalled();
    expect(logs).toEqual([]);
  });
  test('비밀 값이 없는 플랫폼은 경고 한 줄로 건너뛰고, 다른 플랫폼은 보낸다', async () => {
    const app = appDeps({ ios: apnsChannel(env({}), vi.fn()) });
    const s = await sendAppPush(5, async () => NOTICE, app);
    expect(s.ios).toEqual({ tokens: 1, sent: 0, failed: 0, removed: 0, skipped: true });
    expect(s.android.sent).toBe(1);
    expect(logs.filter((l) => l.includes('iOS는 건너뜀'))).toHaveLength(1);
  });
  test('한쪽이 던져도 다른 쪽은 보냄, 확실한 무효 토큰만 지움', async () => {
    const tokens = tokensOf(['ios', IOS_TOKEN], ['ios', IOS_TOKEN2], ['android', AND_TOKEN], ['android', AND_TOKEN2]);
    const ios = { send: vi.fn(async (t) => (t === IOS_TOKEN ? { ok: false, remove: true, code: '410 Unregistered' } : { ok: false, remove: false, code: '503' })) };
    const android = { send: vi.fn(async (t) => { if (t === AND_TOKEN) throw new Error('boom'); return { ok: true }; }) };
    const app = appDeps({ tokens, ios, android });
    const s = await sendAppPush(5, async () => NOTICE, app);
    expect(s.ios).toEqual({ tokens: 2, sent: 0, failed: 1, removed: 1, codes: { '410 Unregistered': 1, 503: 1 } });
    expect(s.android).toEqual({ tokens: 2, sent: 1, failed: 1, removed: 0, codes: { network: 1 } });
    expect(app.forget).toHaveBeenCalledWith([100]);
  });
  test('동시에 보내는 수는 플랫폼마다 4개까지', async () => {
    let live = 0; let peak = 0;
    const slow = { send: vi.fn(async () => { live += 1; peak = Math.max(peak, live); await new Promise((r) => setTimeout(r, 5)); live -= 1; return { ok: true }; }) };
    const tokens = Array.from({ length: 10 }, (_, i) => ({ id: i, platform: 'ios', token: `${i}`.padStart(64, '0') }));
    const s = await sendAppPush(5, async () => NOTICE, appDeps({ tokens, ios: slow }));
    expect(s.ios.sent).toBe(10);
    expect(peak).toBe(APP_PUSH.concurrency);
  });
  test('로그에 토큰·비밀 값·서비스 계정 이메일이 나오지 않는다 (요약 한 줄)', async () => {
    const tokens = tokensOf(['ios', IOS_TOKEN], ['android', AND_TOKEN]);
    const f = fakeFetch([
      [APNS_ORIGIN, () => res(400, { reason: 'BadDeviceToken' })],
      [GOOGLE_TOKEN_URL, googleOk('ya29.secret-access')],
      ['https://fcm.googleapis.com/', () => res(400, fcmErr('INVALID_ARGUMENT', 'INVALID_ARGUMENT', { field: 'message.token', message: `bad token ${AND_TOKEN}` }))],
    ]);
    const app = appDeps({ tokens, ios: apnsChannel(IOS_ENV(), f, () => T0), android: fcmChannel(AND_ENV(), f, () => T0) });
    const s = await sendAppPush(5, async () => NOTICE, app);
    expect(s.ios.removed + s.android.removed).toBe(2);
    const all = logs.join('\n');
    for (const secret of [IOS_TOKEN, AND_TOKEN, 'ya29.secret-access', SA.client_email, 'KEYID12345', 'TEAMID1234', P8.split('\n')[1], SA.private_key.split('\n')[1]]) {
      expect(all).not.toContain(secret);
    }
    const summary = logs.filter((l) => l.includes('"event":"app_push"'));
    expect(summary).toHaveLength(1);
    expect(JSON.parse(summary[0])).toEqual({ event: 'app_push', kind: 'proposal_approved',
      ios: { tokens: 1, sent: 0, failed: 0, removed: 1, codes: { '400 BadDeviceToken': 1 } },
      android: { tokens: 1, sent: 0, failed: 0, removed: 1, codes: { '400 INVALID_ARGUMENT': 1 } } });
    function fcmErr(status, errorCode, extra) {
      return { error: { message: extra.message, status, details: [{ errorCode }, { fieldViolations: [{ field: extra.field }] }] } };
    }
  });
});

describe('handlePush + 앱 발송', () => {
  const ENV = env({ VAPID_PUBLIC_KEY: 'pub', PUSH_WEBHOOK_SECRET: 's' });
  const post = (body = { notification_id: 5 }, secret = 's') => new Request('https://fn.test', {
    method: 'POST', headers: { 'content-type': 'application/json', ...(secret ? { 'x-push-secret': secret } : {}) }, body: JSON.stringify(body),
  });
  const SUBS = [1, 2].map((id) => ({ id, endpoint: `https://e/${id}`, p256dh: 'k', auth: 'a' }));
  const webDeps = ({ subs = SUBS, notification = NOTICE, targetsError = null, send, forget } = {}) => ({
    targets: vi.fn(async () => (targetsError ? { data: null, error: { message: targetsError } } : { data: { notification, subscriptions: subs }, error: null })),
    forget: forget ?? vi.fn(async (ids) => ({ data: ids.length, error: null })),
    send: send ?? vi.fn(async () => {}),
  });

  test('웹 응답은 P-2 전과 똑같고, 앱 발송은 웹이 끝난 뒤', async () => {
    const order = [];
    const web = webDeps({ send: vi.fn(async () => { order.push('web'); }) });
    const app = appDeps();
    app.ios.send.mockImplementation(async () => { order.push('ios'); return { ok: true }; });
    const r = await handlePush(post(), ENV, { ...web, app });
    expect(await r.json()).toEqual({ ok: true, sent: 2, failed: 0, expired: 0 });
    expect(order).toEqual(['web', 'web', 'ios']);
    expect(app.andSend).toHaveBeenCalledTimes(1);
  });
  test('앱 쪽이 실패·예외여도 웹 응답 그대로', async () => {
    const web = webDeps();
    const app = appDeps({ recipient: vi.fn(async () => { throw new Error('app db down'); }) });
    expect(await (await handlePush(post(), ENV, { ...web, app })).json()).toEqual({ ok: true, sent: 2, failed: 0, expired: 0 });
    const app2 = appDeps();
    app2.forget = vi.fn(async () => { throw new Error('x'); });
    app2.ios.send.mockResolvedValue({ ok: false, remove: true, code: '410' });
    expect(await (await handlePush(post(), ENV, { ...webDeps(), app: app2 })).json()).toEqual({ ok: true, sent: 2, failed: 0, expired: 0 });
  });
  test('웹 쪽 실패(보내기 오류·만료 지우기 실패·예외)가 있어도 앱은 보낸다', async () => {
    const web = webDeps({ send: vi.fn(async (s) => { throw Object.assign(new Error('x'), { statusCode: s.id === 1 ? 410 : 500 }); }), forget: vi.fn(async () => ({ data: null, error: { message: 'no' } })) });
    const app = appDeps();
    expect(await (await handlePush(post(), ENV, { ...web, app })).json()).toEqual({ ok: true, sent: 0, failed: 1, expired: 1 });
    expect(app.iosSend).toHaveBeenCalledTimes(1);
    const web2 = webDeps({ forget: vi.fn(async () => { throw new Error('web forget threw'); }), send: vi.fn(async () => { throw Object.assign(new Error('x'), { statusCode: 410 }); }) });
    const app2 = appDeps();
    await expect(handlePush(post(), ENV, { ...web2, app: app2 })).rejects.toThrow('web forget threw'); // 웹 예외는 예전처럼 그대로 올라감
    expect(app2.iosSend).toHaveBeenCalledTimes(1); // 그래도 앱은 보냈다
  });
  test('웹 구독이 없어도 앱은 보낸다 (웹 응답은 예전 그대로 { ok, sent: 0 })', async () => {
    const app = appDeps();
    expect(await (await handlePush(post(), ENV, { ...webDeps({ subs: [] }), app })).json()).toEqual({ ok: true, sent: 0 });
    expect(app.iosSend).toHaveBeenCalledTimes(1);
  });
  test('웹 구독이 없어도 팔로우 새 빌드는 작성자를 읽어 장인 페이지로', async () => {
    const app = appDeps();
    const notification = { id: 5, kind: 'followed_build_created', message: '팔로우한 장인 쿠키의 새 빌드가 올라왔습니다.', build_id: 9 };
    const buildAuthor = vi.fn(async () => ({ data: 'author-1', error: null }));
    await handlePush(post(), ENV, { ...webDeps({ subs: [], notification }), buildAuthor, app });
    expect(buildAuthor).toHaveBeenCalledWith(9);
    expect(app.iosSend.mock.calls[0][1]).toMatchObject({ title: '쿠키 님이 새 빌드를 올렸습니다', url: '/u/author-1' });
  });
  test('웹 구독이 있으면 작성자는 한 번만 읽는다', async () => {
    const app = appDeps();
    const notification = { id: 5, kind: 'followed_build_created', message: '팔로우한 장인 쿠키의 새 빌드가 올라왔습니다.', build_id: 9 };
    const buildAuthor = vi.fn(async () => ({ data: 'author-1', error: null }));
    await handlePush(post(), ENV, { ...webDeps({ notification }), buildAuthor, app });
    expect(buildAuthor).toHaveBeenCalledTimes(1);
    expect(app.iosSend.mock.calls[0][1].url).toBe('/u/author-1');
  });
  test('push_targets가 알림을 주지 않거나(1시간 넘음·없음) 실패하면 앱도 안 보냄', async () => {
    const app = appDeps();
    await handlePush(post(), ENV, { ...webDeps({ notification: null, subs: [] }), app });
    const r = await handlePush(post(), ENV, { ...webDeps({ targetsError: 'db' }), app });
    expect(r.status).toBe(500);
    expect(app.recipient).not.toHaveBeenCalled();
  });
  test('비밀 헤더가 틀리거나 번호가 이상하면 앱도 안 보냄', async () => {
    const app = appDeps();
    expect((await handlePush(post(undefined, 'wrong'), ENV, { ...webDeps(), app })).status).toBe(401);
    expect((await handlePush(post({ notification_id: 'x' }), ENV, { ...webDeps(), app })).status).toBe(400);
    expect(app.recipient).not.toHaveBeenCalled();
  });
  test('뒤로 미룰 수 있으면(defer true) 앱 발송을 기다리지 않고 응답', async () => {
    let release;
    const app = appDeps();
    app.ios.send.mockImplementation(() => new Promise((r) => { release = () => r({ ok: true }); }));
    const deferred = [];
    const r = await handlePush(post(), ENV, { ...webDeps(), app, defer: (w) => { deferred.push(w); return true; } });
    expect(await r.json()).toEqual({ ok: true, sent: 2, failed: 0, expired: 0 });
    expect(deferred).toHaveLength(1);
    await vi.waitFor(() => expect(release).toBeTypeOf('function'));
    release();
    await expect(deferred[0]).resolves.toBeUndefined();
  });
  test('앱 설정(deps.app)이 없으면 앱 쪽은 아무것도 하지 않는다 (P-2 전과 같음)', async () => {
    const web = webDeps({ subs: [] });
    expect(await (await handlePush(post(), ENV, web)).json()).toEqual({ ok: true, sent: 0 });
    expect(logs.some((l) => l.includes('app_push') || l.includes('app-push'))).toBe(false);
  });
});

// ---------------- 1.3 패치 P-2b (073, SPEC 6-106): 앱 토큰만 있고 웹 구독이 없는 사람 ----------------
// 073 뒤 DB: push_wanted가 「웹 구독 또는 앱 토큰」이면 트리거가 부르고, push_targets는 그 사람에게 웹 구독 [](빈 목록)을 준다.
// Edge Function은 바꾸지 않았다 - 웹은 0건으로 조용히 끝나고 앱 발송은 이어지는지 DB가 주는 모양 그대로 확인한다.
describe('P-2b: 웹 구독 없이 앱 토큰만 있는 사람 (073)', () => {
  const ENV = env({ VAPID_PUBLIC_KEY: 'pub', PUSH_WEBHOOK_SECRET: 's' });
  const post = () => new Request('https://fn.test', {
    method: 'POST', headers: { 'content-type': 'application/json', 'x-push-secret': 's' }, body: JSON.stringify({ notification_id: 5 }),
  });
  // 073 뒤 push_targets(앱만 사람의 알림)가 실제로 돌려주는 모양 (037·038·042 칸 전부, subscriptions는 [])
  const TARGETS_APP_ONLY = {
    notification: { id: 5, kind: 'link_removed', message: '링크가 삭제됐습니다.', proposal_id: null, build_id: null,
      counter_id: null, target_champion: null, counter_champion: null, post_id: null },
    subscriptions: [],
  };
  const webOnly = (data) => ({
    targets: vi.fn(async () => ({ data, error: null })),
    forget: vi.fn(async () => ({ data: 0, error: null })),
    send: vi.fn(async () => {}),
  });

  test('웹은 보내기·만료 지우기를 하나도 부르지 않고 { ok, sent: 0 }으로 끝나며 오류 로그가 없다', async () => {
    const web = webOnly(TARGETS_APP_ONLY);
    const app = appDeps();
    const r = await handlePush(post(), ENV, { ...web, app });
    expect(r.status).toBe(200);
    expect(await r.json()).toEqual({ ok: true, sent: 0 });
    expect(web.send).not.toHaveBeenCalled();
    expect(web.forget).not.toHaveBeenCalled();
    expect(logs.some((l) => l.includes('web-push:'))).toBe(false); // 웹 쪽 오류·경고 없음
    expect(logs.some((l) => l.includes('"event":"web_push"'))).toBe(false); // 보낸 게 없으면 웹 요약도 없음 (예전과 같음)
  });
  test('앱은 iOS·Android 모두 보내고, 내용은 describePush 그대로 (링크 관리로 이동)', async () => {
    const app = appDeps();
    await handlePush(post(), ENV, { ...webOnly(TARGETS_APP_ONLY), app });
    const d = describePush(TARGETS_APP_ONLY.notification);
    expect(d.url).toBe('/me/links');
    expect(app.recipient).toHaveBeenCalledWith(5);
    expect(app.iosSend).toHaveBeenCalledWith(IOS_TOKEN, { title: d.title, body: d.body, url: d.url, notificationId: 5 });
    expect(app.andSend).toHaveBeenCalledWith(AND_TOKEN, { title: d.title, body: d.body, url: d.url, notificationId: 5 });
    const summary = logs.filter((l) => l.includes('"event":"app_push"'));
    expect(summary).toHaveLength(1);
    expect(JSON.parse(summary[0])).toEqual({ event: 'app_push', kind: 'link_removed',
      ios: { tokens: 1, sent: 1, failed: 0, removed: 0 }, android: { tokens: 1, sent: 1, failed: 0, removed: 0 } });
  });
  test('응답 뒤 발송(defer)이어도 앱만 사람에게 보낸다 (배포 환경과 같은 길)', async () => {
    const app = appDeps();
    const deferred = [];
    const r = await handlePush(post(), ENV, { ...webOnly(TARGETS_APP_ONLY), app, defer: (w) => { deferred.push(w); return true; } });
    expect(await r.json()).toEqual({ ok: true, sent: 0 });
    expect(deferred).toHaveLength(1);
    await deferred[0];
    expect(app.iosSend).toHaveBeenCalledTimes(1);
    expect(app.andSend).toHaveBeenCalledTimes(1);
  });
  test('subscriptions 칸이 null이거나 없어도 웹은 0건, 앱은 보낸다 (방어)', async () => {
    for (const data of [{ ...TARGETS_APP_ONLY, subscriptions: null }, { notification: TARGETS_APP_ONLY.notification }]) {
      const app = appDeps();
      const web = webOnly(data);
      expect(await (await handlePush(post(), ENV, { ...web, app })).json()).toEqual({ ok: true, sent: 0 });
      expect(web.send).not.toHaveBeenCalled();
      expect(app.iosSend).toHaveBeenCalledTimes(1);
    }
  });
  test('그 사이 앱 토큰도 지워졌으면(로그아웃 등) 외부 호출 없이 조용히 끝난다', async () => {
    const app = appDeps({ tokens: [] });
    expect(await (await handlePush(post(), ENV, { ...webOnly(TARGETS_APP_ONLY), app })).json()).toEqual({ ok: true, sent: 0 });
    expect(app.iosSend).not.toHaveBeenCalled();
    expect(app.andSend).not.toHaveBeenCalled();
    expect(logs).toEqual([]);
  });
  test('073 마이그레이션: push_wanted 마지막 조건이 「웹 구독 또는 앱 토큰」이고, 위 판단은 067과 같다', async () => {
    const { readFileSync } = await import('node:fs');
    const body = (file) => {
      const src = readFileSync(new URL(`../../supabase/migrations/${file}`, import.meta.url), 'utf8').replace(/\r/g, '');
      const m = /\ncreate or replace function public\.push_wanted\(p_user uuid, p_kind text\)\n([\s\S]*?)\n\$\$;/.exec(src);
      return m[1];
    };
    const before = body('067_build_edit_notify.sql');
    const after = body('073_push_wanted_device_tokens.sql');
    const OLD = '  and exists (select 1 from public.push_subscriptions where user_id = p_user);';
    const NEW = '  and (exists (select 1 from public.push_subscriptions where user_id = p_user)\n'
      + '       or exists (select 1 from public.device_push_tokens where user_id = p_user));  -- 073: 웹 구독 또는 앱 기기 토큰';
    expect(before.endsWith(OLD)).toBe(true);
    expect(after.endsWith(NEW)).toBe(true);
    expect(after.replace(NEW, OLD)).toBe(before); // 나머지(묶음·운영자 모드·설정)는 한 글자도 안 바뀜
  });
});

// ---------------- 1.3 패치 2-F (074, SPEC 6-107): 댓글 알림의 앱 푸시 ----------------
describe('댓글·답글 앱 푸시 (074)', () => {
  test('앱에도 웹과 같은 제목·본문·주소 (글 댓글 → 그 글, 문서 답글 → 상대법 댓글 칸)', async () => {
    const post = { id: 21, kind: 'post_comment', message: '내 글 「탑 라인 질문」에 새 댓글 2개가 달렸습니다.', proposal_id: null, build_id: null, post_id: 31 };
    const app = appDeps();
    await sendAppPush(21, async () => post, app);
    expect(app.iosSend).toHaveBeenCalledWith(IOS_TOKEN, { title: '새 댓글', body: post.message, url: '/board/31', notificationId: 21 });
    const reply = { id: 22, kind: 'comment_reply', message: '상대법 문서에 쓴 내 댓글에 새 답글이 달렸습니다.', proposal_id: null, build_id: null,
      post_id: null, counter_id: 4, target_champion: 'Darius', counter_champion: 'Garen' };
    const app2 = appDeps();
    await sendAppPush(22, async () => reply, app2);
    expect(app2.andSend).toHaveBeenCalledWith(AND_TOKEN, { title: '새 답글', body: reply.message, url: '/champion/Darius/counter/Garen#comments', notificationId: 22 });
    expect(apnsPayload({ title: '새 답글', body: reply.message, url: '/champion/Darius/counter/Garen#comments', notificationId: 22 }).url)
      .toBe('/champion/Darius/counter/Garen#comments');
  });
});
