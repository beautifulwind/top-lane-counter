// SPEC 6-65: delete-account Edge Function의 Apple 연결 해제 (코드 교환 → 계정 삭제 → 해제)
// 진짜 Apple 키 대신 테스트 안에서 만든 P-256 키를 쓴다. 가짜 fetch로 Apple·카카오 요청을 받는다.
import { afterEach, beforeAll, beforeEach, describe, expect, test, vi } from 'vitest';
import {
  APPLE_MESSAGES, appleClientSecret, appleConfig, handleDelete, jwtClaims, pkcs8FromP8,
} from '../../supabase/functions/delete-account/index.ts';

const BUNDLE = 'com.example.test';
const SUB = '000123.abcdef.0456';
const b64 = (bytes) => Buffer.from(bytes).toString('base64');
const b64url = (obj) => Buffer.from(JSON.stringify(obj)).toString('base64url');
const fakeIdToken = (claims) => `${b64url({ alg: 'RS256' })}.${b64url(claims)}.sig`;

let keys;
let pem;
beforeAll(async () => {
  keys = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
  const body = b64(new Uint8Array(await crypto.subtle.exportKey('pkcs8', keys.privateKey)));
  pem = `-----BEGIN PRIVATE KEY-----\n${body.match(/.{1,64}/g).join('\n')}\n-----END PRIVATE KEY-----\n`;
});

const envOf = (vars) => ({ get: (k) => vars[k] });
let vars;
let calls; // 순서 기록: 'token' | 'delete' | 'kakao' | 'revoke'
let tokenReply;
let revokeReplies;
let deleteResult;
let logs;

beforeEach(() => {
  vars = { APPLE_TEAM_ID: 'TEAM123456', APPLE_KEY_ID: 'KEY1234567', APPLE_BUNDLE_ID: BUNDLE, APPLE_PRIVATE_KEY: pem, KAKAO_ADMIN_KEY: 'kakao-admin' };
  calls = [];
  tokenReply = () => new Response(JSON.stringify({
    access_token: 'a', refresh_token: 'refresh-1', id_token: fakeIdToken({ iss: 'https://appleid.apple.com', aud: BUNDLE, sub: SUB }),
  }), { status: 200 });
  revokeReplies = [() => new Response('', { status: 200 })];
  deleteResult = { data: null, error: null };
  logs = [];
  vi.spyOn(console, 'log').mockImplementation((...a) => logs.push(a.join(' ')));
  vi.spyOn(console, 'error').mockImplementation((...a) => logs.push(a.join(' ')));
});
afterEach(() => vi.restoreAllMocks());

const fetcher = vi.fn(async (url, init) => {
  const params = init.body instanceof URLSearchParams ? Object.fromEntries(init.body) : {};
  if (url === 'https://appleid.apple.com/auth/token') {
    calls.push({ step: 'token', params });
    return tokenReply(params);
  }
  if (url === 'https://appleid.apple.com/auth/revoke') {
    calls.push({ step: 'revoke', params });
    const reply = revokeReplies.shift() ?? (() => new Response('', { status: 500 }));
    return reply();
  }
  if (url === 'https://kapi.kakao.com/v1/user/unlink') {
    calls.push({ step: 'kakao', params });
    return new Response('{}', { status: 200 });
  }
  throw new Error(`unexpected ${url}`);
});

const identitiesOf = (kinds) => kinds.map((k) => (k === 'apple'
  ? { provider: 'apple', id: SUB, identity_data: { sub: SUB, email: 'x@privaterelay.appleid.com' } }
  : { provider: k, id: `${k}-id`, identity_data: { sub: `${k}-id` } }));

function run(body, { identities = ['apple'], userError = null } = {}) {
  const req = new Request('https://fn.test/delete-account', {
    method: 'POST', headers: { authorization: 'Bearer user-jwt', 'content-type': 'application/json' }, body: JSON.stringify(body),
  });
  return handleDelete(req, envOf(vars), {
    getUser: async (authorization) => {
      expect(authorization).toBe('Bearer user-jwt');
      return userError ? { data: { user: null }, error: { message: userError } } : { data: { user: { identities: identitiesOf(identities) } }, error: null };
    },
    deleteRpc: async (authorization, confirm) => {
      calls.push({ step: 'delete', confirm });
      return deleteResult;
    },
    fetcher,
  });
}
const steps = () => calls.map((c) => c.step);

describe('Apple 연결 계정 + 코드', () => {
  test('코드 교환 → 계정 삭제 → 해제 순서, 응답 apple: revoked', async () => {
    const res = await run({ confirm: '사과', appleCode: 'code-1' });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true, apple: 'revoked' });
    expect(steps()).toEqual(['token', 'delete', 'revoke']);
    const token = calls[0].params;
    expect(token).toMatchObject({ client_id: BUNDLE, code: 'code-1', grant_type: 'authorization_code' });
    expect(calls[2].params).toMatchObject({ client_id: BUNDLE, token: 'refresh-1', token_type_hint: 'refresh_token' });
  });

  test('카카오도 연결돼 있으면 카카오 끊기도 그대로', async () => {
    deleteResult = { data: '12345', error: null };
    const res = await run({ confirm: '사과', appleCode: 'code-1' }, { identities: ['apple', 'kakao'] });
    expect(await res.json()).toEqual({ ok: true, apple: 'revoked' });
    expect(steps()).toEqual(['token', 'delete', 'kakao', 'revoke']);
  });

  test('코드 교환 실패(만료·이미 씀) → 400, 계정은 지우지 않는다', async () => {
    tokenReply = () => new Response(JSON.stringify({ error: 'invalid_grant' }), { status: 400 });
    const res = await run({ confirm: '사과', appleCode: 'old' });
    expect(res.status).toBe(400);
    expect(await res.json()).toEqual({ error: APPLE_MESSAGES.failed });
    expect(steps()).toEqual(['token']);
  });

  test('invalid_client(키·팀·번들 설정 틀림) → 500 설정 안내, 지우지 않음', async () => {
    tokenReply = () => new Response(JSON.stringify({ error: 'invalid_client' }), { status: 400 });
    const res = await run({ confirm: '사과', appleCode: 'c' });
    expect(res.status).toBe(500);
    expect((await res.json()).error).toBe(APPLE_MESSAGES.notReady);
    expect(steps()).toEqual(['token']);
  });

  test('네트워크 오류 → 400, 지우지 않음', async () => {
    tokenReply = () => { throw new TypeError('network'); };
    const res = await run({ confirm: '사과', appleCode: 'c' });
    expect(res.status).toBe(400);
    expect(steps()).toEqual(['token']);
  });

  test('다른 Apple ID의 코드(sub 다름) → 403, 지우지 않음', async () => {
    tokenReply = () => new Response(JSON.stringify({ refresh_token: 'r', id_token: fakeIdToken({ iss: 'https://appleid.apple.com', aud: BUNDLE, sub: 'someone-else' }) }), { status: 200 });
    const res = await run({ confirm: '사과', appleCode: 'c' });
    expect(res.status).toBe(403);
    expect((await res.json()).error).toBe(APPLE_MESSAGES.otherAccount);
    expect(steps()).toEqual(['token']);
  });

  test.each([
    ['aud 다름', { iss: 'https://appleid.apple.com', aud: 'com.other.app', sub: SUB }],
    ['iss 다름', { iss: 'https://evil.example', aud: BUNDLE, sub: SUB }],
  ])('id_token %s → 400, 지우지 않음', async (_n, claims) => {
    tokenReply = () => new Response(JSON.stringify({ refresh_token: 'r', id_token: fakeIdToken(claims) }), { status: 200 });
    const res = await run({ confirm: '사과', appleCode: 'c' });
    expect(res.status).toBe(400);
    expect(steps()).toEqual(['token']);
  });

  test('refresh token이 없으면 400, 지우지 않음', async () => {
    tokenReply = () => new Response(JSON.stringify({ id_token: fakeIdToken({ iss: 'https://appleid.apple.com', aud: BUNDLE, sub: SUB }) }), { status: 200 });
    expect((await run({ confirm: '사과', appleCode: 'c' })).status).toBe(400);
    expect(steps()).toEqual(['token']);
  });

  test('계정 삭제가 거절되면(닉네임 다름·운영자) DB 문구 그대로, Apple 해제는 하지 않는다', async () => {
    deleteResult = { data: null, error: { message: '확인 칸에 내 닉네임을 그대로 적어 주세요.' } };
    const res = await run({ confirm: '틀림', appleCode: 'c' });
    expect(res.status).toBe(400);
    expect(await res.json()).toEqual({ error: '확인 칸에 내 닉네임을 그대로 적어 주세요.' });
    expect(steps()).toEqual(['token', 'delete']);
  });

  test('해제 한 번 실패 → 한 번 더 해서 성공', async () => {
    revokeReplies = [() => new Response('', { status: 503 }), () => new Response('', { status: 200 })];
    const res = await run({ confirm: '사과', appleCode: 'c' });
    expect(await res.json()).toEqual({ ok: true, apple: 'revoked' });
    expect(steps()).toEqual(['token', 'delete', 'revoke', 'revoke']);
  });

  test('해제가 두 번 다 실패해도 탈퇴는 끝난 것 → 200 apple: failed', async () => {
    revokeReplies = [() => new Response('', { status: 500 }), () => { throw new TypeError('network'); }];
    const res = await run({ confirm: '사과', appleCode: 'c' });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true, apple: 'failed' });
    expect(steps()).toEqual(['token', 'delete', 'revoke', 'revoke']);
  });

  test.each(['APPLE_TEAM_ID', 'APPLE_KEY_ID', 'APPLE_BUNDLE_ID', 'APPLE_PRIVATE_KEY'])('비밀 값 %s가 없으면 500 설정 안내, 지우지 않음', async (name) => {
    delete vars[name];
    const res = await run({ confirm: '사과', appleCode: 'c' });
    expect(res.status).toBe(500);
    expect((await res.json()).error).toBe(APPLE_MESSAGES.notReady);
    expect(steps()).toEqual([]);
  });

  test('키 형식이 잘못되면 500 설정 안내, 로그에 키 내용이 없다', async () => {
    vars.APPLE_PRIVATE_KEY = '-----BEGIN PRIVATE KEY-----\nTk9UQUtFWQ==\n-----END PRIVATE KEY-----';
    const res = await run({ confirm: '사과', appleCode: 'c' });
    expect(res.status).toBe(500);
    expect(steps()).toEqual([]);
    expect(logs.join('\n')).toContain('APPLE_PRIVATE_KEY 형식 오류');
    expect(logs.join('\n')).not.toContain('Tk9UQUtFWQ');
  });

  test('로그에는 결과만 — 코드·토큰·sub·이메일이 없다', async () => {
    await run({ confirm: '사과', appleCode: 'secret-code' });
    const all = logs.join('\n');
    expect(all).toContain('"apple":"revoked"');
    for (const s of ['secret-code', 'refresh-1', SUB, 'privaterelay', '사과']) expect(all).not.toContain(s);
  });
});

describe('코드 없이 / Apple 연결 없음', () => {
  test('Apple 연결 계정인데 코드 없음(웹·안드로이드) → 탈퇴하고 apple: not_revoked', async () => {
    const res = await run({ confirm: '사과' });
    expect(await res.json()).toEqual({ ok: true, apple: 'not_revoked' });
    expect(steps()).toEqual(['delete']);
  });

  test('비밀 값이 없어도 코드 없는 탈퇴는 그대로 된다', async () => {
    delete vars.APPLE_PRIVATE_KEY;
    expect(await (await run({ confirm: '사과' })).json()).toEqual({ ok: true, apple: 'not_revoked' });
  });

  test('Apple 연결이 없으면 코드가 와도 무시하고 지금처럼 (apple: none)', async () => {
    deleteResult = { data: '777', error: null };
    const res = await run({ confirm: '카카오', appleCode: 'c' }, { identities: ['kakao'] });
    expect(await res.json()).toEqual({ ok: true, apple: 'none' });
    expect(steps()).toEqual(['delete', 'kakao']);
    expect(calls[1].params).toEqual({ target_id_type: 'user_id', target_id: '777' });
  });

  test('구글 회원: Apple·카카오 요청 없음', async () => {
    const res = await run({ confirm: '구글' }, { identities: ['google'] });
    expect(await res.json()).toEqual({ ok: true, apple: 'none' });
    expect(steps()).toEqual(['delete']);
  });

  test('사용자 정보를 못 읽으면 401, 지우지 않음', async () => {
    const res = await run({ confirm: '사과' }, { userError: 'bad jwt' });
    expect(res.status).toBe(401);
    expect(steps()).toEqual([]);
  });

  test('토큰 없음 401 / GET 405 / OPTIONS / JSON 아님 400', async () => {
    const deps = { getUser: vi.fn(), deleteRpc: vi.fn(), fetcher };
    const env = envOf(vars);
    expect((await handleDelete(new Request('https://fn.test', { method: 'POST', body: '{}' }), env, deps)).status).toBe(401);
    expect((await handleDelete(new Request('https://fn.test', { method: 'GET' }), env, deps)).status).toBe(405);
    expect((await handleDelete(new Request('https://fn.test', { method: 'OPTIONS' }), env, deps)).status).toBe(200);
    const bad = new Request('https://fn.test', { method: 'POST', headers: { authorization: 'Bearer x' }, body: 'not json' });
    expect((await handleDelete(bad, env, deps)).status).toBe(400);
    expect(deps.deleteRpc).not.toHaveBeenCalled();
  });
});

describe('client secret (ES256)', () => {
  const verify = async (jwt) => {
    const [h, c, s] = jwt.split('.');
    return crypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, keys.publicKey, Buffer.from(s, 'base64url'), new TextEncoder().encode(`${h}.${c}`));
  };

  test('헤더·내용이 Apple 규칙대로이고 공개키로 서명이 맞다', async () => {
    const now = Date.UTC(2026, 10, 17, 0, 0, 0);
    const jwt = await appleClientSecret(appleConfig(envOf(vars)), now);
    const [h] = jwt.split('.');
    expect(JSON.parse(Buffer.from(h, 'base64url').toString())).toEqual({ alg: 'ES256', kid: 'KEY1234567', typ: 'JWT' });
    expect(jwtClaims(jwt)).toEqual({ iss: 'TEAM123456', iat: now / 1000, exp: now / 1000 + 300, aud: 'https://appleid.apple.com', sub: BUNDLE });
    expect(Buffer.from(jwt.split('.')[2], 'base64url')).toHaveLength(64); // r||s
    expect(await verify(jwt)).toBe(true);
  });

  test.each([
    ['줄바꿈 그대로', (p) => p],
    ['글자 그대로의 \\n', (p) => p.replace(/\n/g, '\\n')],
    ['한 줄로 붙음', (p) => p.replace(/\n/g, '')],
    ['줄바꿈이 공백으로', (p) => p.replace(/\n/g, ' ')],
    ['CRLF + 앞뒤 공백', (p) => `  ${p.replace(/\n/g, '\r\n')}  `],
    ['따옴표로 감쌈', (p) => `"${p.replace(/\n/g, '\\n')}"`],
    ['머리·꼬리 줄 없이 본문만', (p) => p.replace(/-----[^-]+-----/g, '')],
  ])('.p8 붙여 넣기 형태: %s', async (_n, shape) => {
    const cfg = { ...appleConfig(envOf(vars)), privateKey: shape(pem) };
    expect(await verify(await appleClientSecret(cfg, Date.now()))).toBe(true);
  });

  test('base64가 아닌 글자가 있으면 형식 오류', () => {
    expect(() => pkcs8FromP8('-----BEGIN PRIVATE KEY-----\n@@@\n-----END PRIVATE KEY-----')).toThrow('APPLE_PRIVATE_KEY 형식 오류');
    expect(() => pkcs8FromP8('')).toThrow('APPLE_PRIVATE_KEY 형식 오류');
  });

  test('jwtClaims: 모양이 아니면 null', () => {
    expect(jwtClaims('abc')).toBeNull();
    expect(jwtClaims(null)).toBeNull();
    expect(jwtClaims('a.!!!.c')).toBeNull();
  });
});
