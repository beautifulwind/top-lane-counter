// 로그인·프로필 접근 계층. 화면 컴포넌트는 이 모듈만 호출한다.
import { db } from './supabase';

export const NICKNAME_MAX = 20;

/** 로그인할 수 있는 방식 (Supabase Auth의 provider 이름 → 화면에 보일 이름) */
export const PROVIDERS = { google: '구글', kakao: '카카오' };

/**
 * 브라우저에 이미 로그인된 구글·카카오 계정으로 자동으로 들어가지 않게, 매번 계정을 고르게 한다.
 * (로그아웃은 이 사이트의 세션만 끝낸다 — 구글·카카오 로그인은 브라우저에 남아 있으므로 여기서 다시 묻는다)
 *   구글: prompt=select_account → 계정 선택 화면,  카카오: prompt=login → 카카오 로그인 화면
 * Supabase가 이 값을 그대로 구글·카카오 로그인 주소에 붙여 준다.
 */
export const PROVIDER_PROMPT = { google: { prompt: 'select_account' }, kakao: { prompt: 'login' } };

/**
 * 소셜 로그인 시작 → 구글/카카오 → Supabase → 지금 접속한 주소(origin)의 returnTo 경로로 돌아온다.
 * 카카오: Supabase가 account_email·profile_nickname·profile_image를 항상 요청한다 (scopes로 뺄 수 없음).
 *   이메일은 카카오 동의항목에서 "필수 동의"다 (카카오 비즈 앱 필요). 같은 이메일의 구글·카카오 계정을
 *   Supabase가 한 계정으로 자동 연결하는 데 쓰이고, 화면에는 /me의 "로그인 연결"에만 보인다.
 */
export async function signIn(provider, returnTo = '/') {
  if (!PROVIDERS[provider]) throw new Error(`지원하지 않는 로그인 방식이에요. (${provider})`);
  rememberPending('signIn', provider);
  const { error } = await db().auth.signInWithOAuth({
    provider,
    options: { redirectTo: window.location.origin + returnTo, queryParams: PROVIDER_PROMPT[provider] },
  });
  if (error) {
    forgetPending();
    throw new Error(`로그인을 시작하지 못했어요. (${error.message})`);
  }
}

/**
 * 로그인한 계정에 다른 로그인 방식을 붙인다 (Supabase 수동 연결 = linkIdentity).
 * 구글/카카오에 다녀와서 /me로 돌아온다. Supabase에서 "Allow manual linking"이 켜져 있어야 한다.
 */
export async function linkProvider(provider) {
  if (!PROVIDERS[provider]) throw new Error(`지원하지 않는 로그인 방식이에요. (${provider})`);
  rememberPending('link', provider);
  const { error } = await db().auth.linkIdentity({
    provider,
    options: { redirectTo: window.location.origin + '/me', queryParams: PROVIDER_PROMPT[provider] },
  });
  if (error) {
    forgetPending();
    if (/manual linking/i.test(error.message)) {
      throw new Error('계정 연결 기능이 아직 꺼져 있어요. (Supabase에서 Allow manual linking을 켜야 해요)');
    }
    throw new Error(`${PROVIDERS[provider]} 연결을 시작하지 못했어요. (${error.message})`);
  }
}

/** 내 계정에 붙어 있는 로그인 방식들 [{ provider, email, createdAt }] */
export async function getIdentities() {
  const { data, error } = await db().auth.getUserIdentities();
  if (error) throw new Error(`연결된 로그인 방식을 불러오지 못했어요. (${error.message})`);
  return (data?.identities ?? []).map((i) => ({
    provider: i.provider,
    email: i.identity_data?.email ?? null,
    createdAt: i.created_at ?? null,
  }));
}

// 구글/카카오로 떠나기 직전에 "무엇을 하러 갔는지" 기억해 둔다 (돌아왔을 때 안내 문구에 쓴다).
// 같은 탭에서만 필요하므로 sessionStorage. 못 쓰는 환경이면 안내만 빠진다.
const PENDING_KEY = 'auth:pending';
function rememberPending(kind, provider) {
  try { sessionStorage.setItem(PENDING_KEY, JSON.stringify({ kind, provider })); } catch { /* 안내만 빠짐 */ }
}
function forgetPending() {
  try { sessionStorage.removeItem(PENDING_KEY); } catch { /* 무시 */ }
}
function takePending() {
  try {
    const v = JSON.parse(sessionStorage.getItem(PENDING_KEY) ?? 'null');
    sessionStorage.removeItem(PENDING_KEY);
    return v && PROVIDERS[v.provider] ? v : null;
  } catch {
    return null;
  }
}

// 로그인 후 돌아온 주소에 붙는 값들 (처리 후 주소창에서 지운다)
const CALLBACK_PARAMS = ['code', 'sb_flow_id', 'error', 'error_code', 'error_description'];

/**
 * 구글/카카오 → Supabase를 거쳐 ?code=...로 돌아왔을 때, 그 code가 세션으로 바뀌었는지 확인한다.
 * (supabase-js는 이 단계가 실패해도 콘솔에 아무것도 남기지 않으므로 여기서 직접 잡아 화면에 보여준다)
 * 로그인 콜백이 아니면 아무 일도 하지 않는다. 실패하면 안내 문구가 담긴 Error를 던진다.
 * 성공하면 화면에 띄울 안내(notice)를 돌려줄 수 있다:
 *   { type: 'merged', provider, others } 같은 이메일의 기존 계정에 자동으로 합쳐짐 (Supabase 자동 연결)
 *   { type: 'linked', provider }         /me에서 연결하기를 눌러 붙임
 */
export async function finishLoginFromUrl() {
  const query = new URLSearchParams(window.location.search);
  const hash = new URLSearchParams(window.location.hash.slice(1));
  const providerError = query.get('error_description') ?? hash.get('error_description');
  const providerCode = query.get('error_code') ?? hash.get('error_code');
  if (!query.has('code') && !providerError) return null;

  const pending = takePending();
  const auth = db().auth;
  const { error } = await auth.initialize(); // supabase-js가 code → 세션 교환을 마칠 때까지 기다림
  const { data } = await auth.getSession();
  clearCallbackParams();
  // 연결(linkIdentity)이 실패해도 원래 세션은 남아 있으므로, 구글/카카오가 보낸 오류가 있으면 실패로 본다
  if (data.session && !error && !providerError) return loginNotice(pending, data.session.user);
  throw loginError(error, providerError, providerCode, pending);
}

// 처음 만들어진 계정이면 계정과 로그인 방식이 같은 순간에 생긴다. 이보다 늦게 붙었으면 "기존 계정에 합쳐짐".
const MERGE_GAP_MS = 60 * 1000;

function loginNotice(pending, user) {
  if (!pending) return null;
  const { kind, provider } = pending;
  if (kind === 'link') return { type: 'linked', provider };
  const identities = user?.identities ?? [];
  const mine = identities.find((i) => i.provider === provider);
  const others = [...new Set(identities.map((i) => i.provider).filter((p) => p !== provider && PROVIDERS[p]))];
  if (!mine?.created_at || !user?.created_at || others.length === 0) return null;
  const joinedLater = Date.parse(mine.created_at) - Date.parse(user.created_at) > MERGE_GAP_MS;
  const justNow = Date.now() - Date.parse(mine.created_at) < 10 * 60 * 1000;
  return joinedLater && justNow ? { type: 'merged', provider, others } : null;
}

/** 안내(notice)를 사람이 읽을 문장으로 */
export function noticeText(notice) {
  const name = PROVIDERS[notice.provider];
  if (notice.type === 'linked') return `${name} 로그인을 이 계정에 연결했어요. 이제 ${name}로 로그인해도 같은 계정이에요.`;
  const others = notice.others.map((p) => PROVIDERS[p]).join('·');
  return `같은 이메일로 이미 가입된 계정(${others})이 있어서, ${name} 로그인을 그 계정에 연결했어요. 앞으로 어느 쪽으로 로그인해도 같은 계정이에요.`;
}

function clearCallbackParams() {
  const url = new URL(window.location.href);
  CALLBACK_PARAMS.forEach((p) => url.searchParams.delete(p));
  if (CALLBACK_PARAMS.some((p) => new URLSearchParams(url.hash.slice(1)).has(p))) url.hash = '';
  window.history.replaceState(window.history.state, '', url.toString());
}

function loginError(error, providerError, providerCode, pending) {
  const raw = error?.message ?? providerError ?? '';
  const linking = pending?.kind === 'link';
  const name = PROVIDERS[pending?.provider] ?? '';
  let message;
  if (providerCode === 'identity_already_exists' || /already linked|identity_already_exists/i.test(raw)) {
    message = `이 ${name || '로그인'} 계정은 이미 다른 회원 계정에 연결돼 있어요. 그 계정으로 로그인하거나, 다른 ${name || '로그인'} 계정으로 연결해 주세요.`;
  } else if (/manual linking/i.test(raw)) {
    message = '계정 연결 기능이 아직 꺼져 있어요. (Supabase에서 Allow manual linking을 켜야 해요)';
  } else if (providerError && !error?.message?.match(/verifier|flow state|ByteString|fetch/i)) {
    message = linking ? `${name} 연결이 취소됐거나 거절됐어요. 다시 시도해 주세요.` : '로그인이 취소됐거나 거절됐어요. 다시 시도해 주세요.';
  } else if (/ByteString|ISO-8859-1|Failed to fetch|NetworkError|Load failed/i.test(raw)) {
    message = 'Supabase 서버에 로그인 요청을 보내지 못했어요. 인터넷 연결과 Supabase 키 설정(.env / Cloudflare 환경변수)을 확인해 주세요.';
  } else if (/verifier/i.test(raw) || !error) {
    // code는 왔는데 이 브라우저에 로그인 시작 기록(code verifier)이 없음
    message = '로그인을 시작한 곳과 돌아온 곳이 달라요. 같은 주소, 같은 브라우저 창에서 다시 로그인해 주세요.';
  } else if (/flow state|expired|already|invalid grant/i.test(raw)) {
    message = '로그인 코드가 만료됐거나 이미 사용됐어요. 다시 로그인해 주세요.';
  } else {
    message = '로그인을 마치지 못했어요. 다시 시도해 주세요.';
  }
  return Object.assign(new Error(message), {
    detail: raw || null,
    title: linking ? '계정을 연결하지 못했어요.' : '로그인하지 못했어요.',
    retryTo: linking ? '/me' : '/login',
  });
}

export async function signOut() {
  const { error } = await db().auth.signOut();
  if (error) throw new Error(`로그아웃하지 못했어요. (${error.message})`);
}

export async function getSession() {
  const { data, error } = await db().auth.getSession();
  if (error) throw new Error(`로그인 정보를 불러오지 못했어요. (${error.message})`);
  return data.session;
}

/** 로그인 상태가 바뀔 때마다 cb(session). 해제 함수를 돌려준다. */
export function onAuthChange(cb) {
  // 주의: 이 콜백 안에서 Supabase를 await 하면 안 된다 (supabase-js 내부 잠금과 엉킴)
  const { data } = db().auth.onAuthStateChange((_event, session) => cb(session));
  return () => data.subscription.unsubscribe();
}

const PROFILE_COLUMNS = 'id, nickname, role, xp, level, main_title';

/** 내 프로필 (첫 로그인 시 DB 트리거가 만든다. nickname이 null이면 닉네임 설정 전) */
export async function getProfile(userId) {
  const { data, error } = await db().from('profiles').select(PROFILE_COLUMNS).eq('id', userId).maybeSingle();
  if (error) throw new Error(`프로필을 불러오지 못했어요. (${error.message})`);
  return data;
}

/** 닉네임 앞뒤 공백 제거 + 규칙 검사. 문제가 있으면 안내 문구, 없으면 null */
export function nicknameProblem(raw) {
  const nickname = raw.trim();
  if (!nickname) return '닉네임을 입력해 주세요.';
  if ([...nickname].length > NICKNAME_MAX) return `닉네임은 ${NICKNAME_MAX}자 이하로 정해 주세요.`;
  return null;
}

export async function saveNickname(userId, raw) {
  const problem = nicknameProblem(raw);
  if (problem) throw new Error(problem);
  const { data, error } = await db()
    .from('profiles')
    .update({ nickname: raw.trim() })
    .eq('id', userId)
    .select(PROFILE_COLUMNS)
    .maybeSingle();
  if (error) {
    if (error.code === '23505') throw new Error('이미 사용 중인 닉네임이에요. 다른 닉네임을 정해 주세요.');
    if (error.code === 'P0001') throw new Error(error.message); // 30일에 한 번 (DB 문구에 다음 날짜가 들어 있다)
    if (error.code === '23514') throw new Error(`닉네임은 앞뒤 공백 없이 1~${NICKNAME_MAX}자로 정해 주세요.`);
    throw new Error(`닉네임을 저장하지 못했어요. (${error.message})`);
  }
  if (!data) throw new Error('프로필을 찾지 못했어요. 로그아웃 후 다시 로그인해 주세요.');
  return data;
}

// ---------------- 닉네임 변경 · 회원 탈퇴 (017, SPEC 6-8) ----------------

/** 닉네임 변경 규칙: 마지막으로 바꾼 때와 다음에 바꿀 수 있는 때 (처음 정한 것은 변경이 아님). 기록은 본인만 읽는다 */
export async function getNicknameRule(userId) {
  const [changes, rule] = await Promise.all([
    db().from('nickname_changes').select('changed_at').eq('user_id', userId).order('changed_at', { ascending: false }).limit(1),
    db().from('xp_rules').select('value').eq('key', 'nickname_change_days').maybeSingle(),
  ]);
  if (changes.error || rule.error) throw new Error('닉네임 변경 정보를 불러오지 못했어요.');
  const days = rule.data?.value ?? 30;
  const last = changes.data?.[0]?.changed_at ?? null;
  const next = last ? new Date(Date.parse(last) + days * 86400000).toISOString() : null;
  return { days, last, next };
}

/**
 * 회원 탈퇴: Edge Function delete-account (DB delete_my_account + 카카오 연결 끊기). confirm = 내 닉네임 그대로.
 * 성공하면 이 브라우저의 로그인도 지운다 (서버 세션은 계정과 함께 이미 없어짐).
 */
export async function deleteMyAccount(confirm) {
  const { error } = await db().functions.invoke('delete-account', { body: { confirm } });
  if (error) {
    let message = null;
    try {
      message = (await error.context?.json?.())?.error ?? null;
    } catch { /* 문구 없음 */ }
    throw new Error(message ?? `탈퇴하지 못했어요. (${error.message})`);
  }
  await db().auth.signOut({ scope: 'local' }).catch(() => {});
}
