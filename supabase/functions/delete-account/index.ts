// 회원 탈퇴 (SPEC 6-8, 6-65): /me의 [탈퇴]가 로그인한 사람의 토큰으로 부른다. 받는 값 { confirm, appleCode? }
//   0) Apple이 연결된 계정이고 iOS 앱이 appleCode(Apple 재확인으로 받은 authorization code)를 보냈으면
//      Apple 키로 client secret(ES256 JWT)을 만들어 코드를 refresh token으로 바꾼다 (/auth/token).
//      받은 id_token의 sub가 이 계정의 Apple sub와 같아야 한다. 여기서 실패하면 아무것도 지우지 않고 멈춘다.
//   1) 그 사람 권한으로 DB 함수 delete_my_account(확인 문구) → 계정 삭제 (운영자 불가, 닉네임 확인은 DB가 한다)
//   2) 카카오가 연결돼 있었으면 카카오 "연결 끊기" API → 카카오의 "연결된 서비스" 목록에서도 빠진다.
//      이 단계가 실패해도 탈퇴는 이미 끝났으므로 로그만 남긴다 (카카오가 보내는 연결 끊기 알림은 'not_found'로 끝남)
//   3) 0)에서 받은 refresh token을 Apple /auth/revoke로 해제 (실패하면 한 번 더). 실패해도 탈퇴는 끝났으므로
//      응답 apple: 'failed' → 화면이 iPhone 설정에서 직접 중단하는 방법을 안내한다.
//   응답 { ok: true, apple: 'revoked' | 'failed' | 'not_revoked'(Apple 연결은 있는데 코드 없음 — 웹·안드로이드) | 'none' }
//   코드·토큰·sub·이메일은 로그에 남기지 않는다. Apple 토큰은 저장하지 않는다.
//
// 배포: Supabase 대시보드 → Edge Functions → delete-account → Code에 이 파일 내용 그대로. "Verify JWT"는 켠다 (기본값)
// 비밀 값 (대시보드 → Edge Functions → Secrets). 코드·.env·저장소에 넣지 않는다.
//   KAKAO_ADMIN_KEY (kakao-unlink와 같은 값)
//   APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_BUNDLE_ID(= Apple client_id, 앱 번들 ID),
//   APPLE_PRIVATE_KEY (.p8 내용 전체. 줄바꿈이 살아 있든, 한 줄로 붙었든, 글자 그대로 \n이든 모두 읽는다)
// SUPABASE_URL, SUPABASE_ANON_KEY는 Supabase가 자동으로 넣어 준다.
import { createClient } from 'npm:@supabase/supabase-js@2.49.1';

type Env = { get(key: string): string | undefined };
type RpcResult = { data: unknown; error: { message: string } | null };
type Identity = { provider?: string; id?: string; identity_data?: { sub?: unknown } | null };
type UserResult = { data: { user: { identities?: Identity[] | null } | null } | null; error: { message: string } | null };
export type Deps = {
  deleteRpc: (authorization: string, confirm: string) => Promise<RpcResult>;
  getUser: (authorization: string) => Promise<UserResult>;
  fetcher: typeof fetch;
  now?: () => number;
};

const APPLE = 'https://appleid.apple.com';

const CORS = {
  'access-control-allow-origin': '*', // 로그인 토큰이 있어야만 동작하므로 출처는 따지지 않는다
  'access-control-allow-headers': 'authorization, x-client-info, apikey, content-type',
  'access-control-allow-methods': 'POST, OPTIONS',
};
const json = (body: unknown, status: number) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, 'content-type': 'application/json; charset=utf-8' } });

export const APPLE_MESSAGES = {
  notReady: 'Apple 연결 해제 설정이 아직 준비되지 않아 탈퇴하지 않았습니다. 잠시 뒤 다시 시도하거나 [문의하기]로 알려 주세요.',
  failed: 'Apple 확인을 마치지 못해 탈퇴하지 않았습니다. 다시 시도해 주세요.',
  otherAccount: '지금 로그인한 계정에 연결된 Apple ID로 확인해 주세요. 탈퇴하지 않았습니다.',
};

// ---------------- Apple client secret (ES256 JWT) ----------------

const b64url = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const b64urlText = (text: string) => b64url(new TextEncoder().encode(text));

/** .p8 내용 → PKCS#8 바이트. 머리·꼬리 줄, 따옴표, 공백·줄바꿈, 글자 그대로의 \n·\r을 모두 지우고 base64만 읽는다 */
export function pkcs8FromP8(text: string): Uint8Array {
  const body = text
    .replace(/-----(BEGIN|END)[^-]*-----/g, '')
    .replace(/\\[nr]/g, '')
    .replace(/["'\s]/g, '');
  if (!body || !/^[A-Za-z0-9+/]+={0,2}$/.test(body)) throw new Error('APPLE_PRIVATE_KEY 형식 오류');
  return Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
}

export type AppleConfig = { teamId: string; keyId: string; clientId: string; privateKey: string };

/** 비밀 값 4개 (하나라도 없으면 null) */
export function appleConfig(env: Env): AppleConfig | null {
  const teamId = env.get('APPLE_TEAM_ID')?.trim();
  const keyId = env.get('APPLE_KEY_ID')?.trim();
  const clientId = env.get('APPLE_BUNDLE_ID')?.trim();
  const privateKey = env.get('APPLE_PRIVATE_KEY');
  if (!teamId || !keyId || !clientId || !privateKey?.trim()) return null;
  return { teamId, keyId, clientId, privateKey };
}

/** Apple /auth/token·/auth/revoke에 쓰는 client secret. 5분짜리 (한 번 쓰고 버린다) */
export async function appleClientSecret(cfg: AppleConfig, nowMs: number): Promise<string> {
  let key: CryptoKey;
  try {
    key = await crypto.subtle.importKey('pkcs8', pkcs8FromP8(cfg.privateKey), { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
  } catch {
    throw new Error('APPLE_PRIVATE_KEY 형식 오류'); // 키 내용은 절대 출력하지 않는다
  }
  const iat = Math.floor(nowMs / 1000);
  const head = b64urlText(JSON.stringify({ alg: 'ES256', kid: cfg.keyId, typ: 'JWT' }));
  const claims = b64urlText(JSON.stringify({ iss: cfg.teamId, iat, exp: iat + 300, aud: APPLE, sub: cfg.clientId }));
  const input = `${head}.${claims}`;
  // WebCrypto ECDSA 서명은 r||s 64바이트 (JWS ES256이 쓰는 모양 그대로)
  const sig = new Uint8Array(await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, new TextEncoder().encode(input)));
  return `${input}.${b64url(sig)}`;
}

/** JWT 가운데(내용)만 읽는다. id_token은 우리가 키로 인증한 요청에 Apple이 TLS로 직접 준 것이라 서명은 따로 보지 않는다 */
export function jwtClaims(token: unknown): Record<string, unknown> | null {
  if (typeof token !== 'string') return null;
  const part = token.split('.')[1];
  if (!part) return null;
  try {
    const b64 = part.replace(/-/g, '+').replace(/_/g, '/');
    const bytes = Uint8Array.from(atob(b64 + '='.repeat((4 - (b64.length % 4)) % 4)), (c) => c.charCodeAt(0));
    const v = JSON.parse(new TextDecoder().decode(bytes));
    return v && typeof v === 'object' ? v : null;
  } catch {
    return null;
  }
}

const form = (fields: Record<string, string>) => ({
  method: 'POST',
  headers: { 'content-type': 'application/x-www-form-urlencoded' },
  body: new URLSearchParams(fields),
});

/** 이 계정의 Apple sub들 (identity_data.sub, 없으면 id) */
function appleSubs(identities: Identity[] | null | undefined): string[] {
  return (identities ?? [])
    .filter((i) => i?.provider === 'apple')
    .flatMap((i) => [i.identity_data?.sub, i.id])
    .filter((s): s is string => typeof s === 'string' && s.length > 0);
}

type Exchange = { ok: true; refreshToken: string } | { ok: false; response: Response };

/** 0) 코드 → refresh token. 실패하면 멈출 응답을 돌려준다 (아무것도 지우지 않은 상태) */
async function exchangeAppleCode(code: string, subs: string[], cfg: AppleConfig | null, deps: Deps): Promise<Exchange> {
  const stop = (message: string, status: number, reason: string) => {
    console.error(JSON.stringify({ event: 'apple_exchange_failed', reason }));
    return { ok: false as const, response: json({ error: message }, status) };
  };
  if (!cfg) return stop(APPLE_MESSAGES.notReady, 500, 'missing_secrets');
  let secret: string;
  try {
    secret = await appleClientSecret(cfg, (deps.now ?? Date.now)());
  } catch (e) {
    return stop(APPLE_MESSAGES.notReady, 500, String((e as Error)?.message ?? e));
  }
  let body: Record<string, unknown> = {};
  let status = 0;
  try {
    const res = await deps.fetcher(`${APPLE}/auth/token`, form({ client_id: cfg.clientId, client_secret: secret, code, grant_type: 'authorization_code' }));
    status = res.status;
    body = await res.json().catch(() => ({}));
    if (!res.ok) {
      const err = String(body?.error ?? '');
      // invalid_client = 팀 ID·키 ID·번들 ID·키가 맞지 않음 (운영 설정 문제)
      return err === 'invalid_client' ? stop(APPLE_MESSAGES.notReady, 500, 'invalid_client') : stop(APPLE_MESSAGES.failed, 400, `token ${status} ${err}`);
    }
  } catch {
    return stop(APPLE_MESSAGES.failed, 400, 'token_network');
  }
  const refreshToken = typeof body.refresh_token === 'string' ? body.refresh_token : '';
  const claims = jwtClaims(body.id_token);
  if (!refreshToken || !claims) return stop(APPLE_MESSAGES.failed, 400, 'token_shape');
  const aud = claims.aud;
  const audOk = aud === cfg.clientId || (Array.isArray(aud) && aud.includes(cfg.clientId));
  if (claims.iss !== APPLE || !audOk) return stop(APPLE_MESSAGES.failed, 400, 'id_token_aud_iss');
  if (typeof claims.sub !== 'string' || !subs.includes(claims.sub)) return stop(APPLE_MESSAGES.otherAccount, 403, 'sub_mismatch');
  return { ok: true, refreshToken };
}

/** 3) refresh token 해제. 실패하면 한 번 더 */
async function revokeApple(refreshToken: string, cfg: AppleConfig, deps: Deps): Promise<'revoked' | 'failed'> {
  for (let attempt = 1; attempt <= 2; attempt++) {
    try {
      const secret = await appleClientSecret(cfg, (deps.now ?? Date.now)());
      const res = await deps.fetcher(`${APPLE}/auth/revoke`, form({
        client_id: cfg.clientId, client_secret: secret, token: refreshToken, token_type_hint: 'refresh_token',
      }));
      if (res.ok) return 'revoked';
      console.error(JSON.stringify({ event: 'apple_revoke_failed', attempt, status: res.status }));
    } catch {
      console.error(JSON.stringify({ event: 'apple_revoke_failed', attempt, status: 'network' }));
    }
  }
  return 'failed';
}

export async function handleDelete(req: Request, env: Env, deps: Deps): Promise<Response> {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json({ error: '허용되지 않는 요청이에요.' }, 405);
  const authorization = req.headers.get('authorization') ?? '';
  if (!authorization.startsWith('Bearer ')) return json({ error: '로그인해 주세요.' }, 401);

  let confirm = '';
  let appleCode = '';
  try {
    const body = await req.json();
    confirm = String(body?.confirm ?? '');
    appleCode = typeof body?.appleCode === 'string' ? body.appleCode.trim() : '';
  } catch {
    return json({ error: '요청 형식이 잘못됐어요.' }, 400);
  }

  const { data: userData, error: userError } = await deps.getUser(authorization);
  if (userError || !userData?.user) return json({ error: '로그인해 주세요.' }, 401);
  const subs = appleSubs(userData.user.identities);
  const hasApple = subs.length > 0;

  // 0) Apple: 지우기 전에 코드부터 바꿔 둔다 (실패하면 아무것도 지우지 않음)
  const cfg = appleConfig(env);
  let refreshToken: string | null = null;
  if (hasApple && appleCode) {
    const ex = await exchangeAppleCode(appleCode, subs, cfg, deps);
    if (!ex.ok) return ex.response;
    refreshToken = ex.refreshToken;
  }

  // 1) 계정 삭제
  const { data: kakaoId, error } = await deps.deleteRpc(authorization, confirm);
  if (error) return json({ error: error.message }, 400); // DB가 정한 문구 그대로 (운영자 불가, 닉네임 다름 등). 받은 Apple 토큰은 버린다

  // 2) 카카오
  let kakao = 'none';
  if (typeof kakaoId === 'string' && kakaoId) {
    const adminKey = env.get('KAKAO_ADMIN_KEY');
    if (!adminKey) {
      kakao = 'skipped';
      console.error('delete-account: KAKAO_ADMIN_KEY 비밀 값이 없어 카카오 연결 끊기를 못 했어요');
    } else {
      try {
        const res = await deps.fetcher('https://kapi.kakao.com/v1/user/unlink', {
          method: 'POST',
          headers: { authorization: `KakaoAK ${adminKey}`, 'content-type': 'application/x-www-form-urlencoded;charset=utf-8' },
          body: new URLSearchParams({ target_id_type: 'user_id', target_id: kakaoId }),
        });
        kakao = res.ok ? 'unlinked' : `failed ${res.status}`;
      } catch (e) {
        kakao = 'failed';
        console.error('delete-account: 카카오 연결 끊기 요청 실패', String(e));
      }
    }
  }

  // 3) Apple 해제
  let apple: 'revoked' | 'failed' | 'not_revoked' | 'none' = 'none';
  if (refreshToken && cfg) apple = await revokeApple(refreshToken, cfg, deps);
  else if (hasApple) apple = 'not_revoked';

  console.log(JSON.stringify({ event: 'account_deleted', kakao, apple })); // 누가 탈퇴했는지는 남기지 않는다
  return json({ ok: true, apple }, 200);
}

if (typeof Deno !== 'undefined') {
  const url = Deno.env.get('SUPABASE_URL')!;
  const anon = Deno.env.get('SUPABASE_ANON_KEY')!;
  const asUser = (authorization: string) =>
    createClient(url, anon, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
  Deno.serve((req) =>
    handleDelete(req, Deno.env, {
      deleteRpc: (authorization, confirm) => asUser(authorization).rpc('delete_my_account', { p_confirm: confirm }),
      getUser: (authorization) => asUser(authorization).auth.getUser(authorization.slice('Bearer '.length)),
      fetcher: fetch,
    }));
}
