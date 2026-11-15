// iOS 앱에서만 쓰는 Apple 로그인 (SPEC 6-58). 웹·안드로이드는 이 파일의 signInWithAppleSheet를 부르지 않는다.
// iOS의 Apple 로그인 시트(@capawesome/capacitor-apple-sign-in) → id token → Supabase signInWithIdToken / linkIdentity(token).
// 플러그인은 부를 때만 동적으로 불러온다 (웹 번들에 들어가지 않게, 따로 나뉜 조각으로만 존재).

/** Apple에서 받는 정보: 이메일만 (이름은 쓰지 않으므로 요청하지 않는다 — 닉네임은 사용자가 직접 정한다) */
export const APPLE_SCOPES = ['EMAIL'];

/** 이메일 숨기기(Apple 릴레이) 주소인가 */
export function isRelayEmail(email) {
  return typeof email === 'string' && /@privaterelay\.appleid\.com$/i.test(email.trim());
}

/** 화면에 보일 이메일 (릴레이 주소는 "이메일 숨김") */
export function displayEmail(email) {
  if (!email) return null;
  return isRelayEmail(email) ? '이메일 숨김 (Apple)' : email;
}

const hex = (bytes) => [...new Uint8Array(bytes)].map((b) => b.toString(16).padStart(2, '0')).join('');

/**
 * nonce 한 쌍: raw(원문) → Supabase, hashed(SHA-256 hex) → Apple.
 * Apple id token의 nonce 값은 hashed이고, Supabase는 raw를 해시해 맞춰 본다 (재전송 공격 방지).
 */
export async function makeNonce(cryptoImpl = globalThis.crypto) {
  const raw = hex(cryptoImpl.getRandomValues(new Uint8Array(32)));
  const hashed = hex(await cryptoImpl.subtle.digest('SHA-256', new TextEncoder().encode(raw)));
  return { raw, hashed };
}

/** 사용자가 Apple 시트를 닫았는가 (플러그인 코드 SIGN_IN_CANCELED, iOS ASAuthorizationError.canceled = 1001) */
export function isAppleCancel(error) {
  const code = String(error?.code ?? '');
  return code === 'SIGN_IN_CANCELED' || code === '1001';
}

const loadPlugin = async () => (await import('@capawesome/capacitor-apple-sign-in')).AppleSignIn;

/**
 * iOS Apple 로그인 시트를 띄워 id token을 받는다. 돌려주는 값: { idToken, nonce(원문) }.
 * 취소하면 cancelled: true가 붙은 Error, 그 밖의 실패는 그대로 Error.
 */
export async function signInWithAppleSheet({ load = loadPlugin, cryptoImpl } = {}) {
  const { raw, hashed } = await makeNonce(cryptoImpl);
  const plugin = await load();
  let result;
  try {
    result = await plugin.signIn({ scopes: APPLE_SCOPES, nonce: hashed });
  } catch (e) {
    if (isAppleCancel(e)) throw Object.assign(new Error('Apple 로그인 창을 닫았습니다.'), { cancelled: true });
    throw new Error(e?.message ?? String(e));
  }
  if (!result?.idToken) throw new Error('Apple에서 로그인 정보를 받지 못했습니다.');
  return { idToken: result.idToken, nonce: raw };
}

/** 이 계정의 로그인 방식이 Apple뿐인가 (다른 기기에서 쓰려면 구글·카카오 연결 안내) */
export function isAppleOnly(providers) {
  const list = (providers ?? []).filter((p) => p && p !== 'anonymous');
  return list.includes('apple') && list.every((p) => p === 'apple');
}

/** 세션 user의 로그인 방식들 (identities가 있으면 그것, 없으면 app_metadata.providers) */
export function userProviders(user) {
  const fromIdentities = user?.identities?.map((i) => i.provider);
  return fromIdentities?.length ? fromIdentities : (user?.app_metadata?.providers ?? []);
}

/** 다른 기기 안내 문구 (Apple 가입자에게만) */
export const APPLE_ONLY_TEXT = 'Apple 로그인은 iOS 앱에서만 됩니다. 다른 기기(웹·안드로이드)에서도 쓰려면 구글·카카오를 연결해 주세요.';
