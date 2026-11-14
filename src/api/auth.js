// 로그인·프로필 접근 계층. 화면 컴포넌트는 이 모듈만 호출한다.
import { INFLUENCER_MARK_MESSAGE, hasReservedMark, mimicsInfluencer } from '../lib/nickname';
import { db } from './supabase';
import { dropBrowserPush, forgetDevicePush } from './push';
import { ALREADY_MEMBER_TEXT } from '../lib/guest';

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
  if (!PROVIDERS[provider]) throw new Error(`지원하지 않는 로그인 방식입니다. (${provider})`);
  rememberPending('signIn', provider);
  const { error } = await db().auth.signInWithOAuth({
    provider,
    options: { redirectTo: window.location.origin + returnTo, queryParams: PROVIDER_PROMPT[provider] },
  });
  if (error) {
    forgetPending();
    throw new Error(`로그인을 시작하지 못했습니다. (${error.message})`);
  }
}

/**
 * 로그인한 계정에 다른 로그인 방식을 붙인다 (Supabase 수동 연결 = linkIdentity).
 * 구글/카카오에 다녀와서 계정 설정(/me/settings)으로 돌아온다 — 비회원 연결(guest)은 마이페이지(/me)로.
 * Supabase에서 "Allow manual linking"이 켜져 있어야 한다.
 */
/** 계정 설정 화면 (로그인 연결·닉네임·탈퇴) */
export const SETTINGS_PATH = '/me/settings';

export async function linkProvider(provider, { guest = false } = {}) {
  if (!PROVIDERS[provider]) throw new Error(`지원하지 않는 로그인 방식입니다. (${provider})`);
  rememberPending(guest ? 'upgrade' : 'link', provider);
  const { error } = await db().auth.linkIdentity({
    provider,
    options: { redirectTo: window.location.origin + (guest ? '/me' : SETTINGS_PATH), queryParams: PROVIDER_PROMPT[provider] },
  });
  if (error) {
    forgetPending();
    if (/manual linking/i.test(error.message)) {
      throw new Error('계정 연결 기능이 아직 꺼져 있습니다. (Supabase에서 Allow manual linking을 켜야 합니다)');
    }
    throw new Error(`${PROVIDERS[provider]} 연결을 시작하지 못했습니다. (${error.message})`);
  }
}

/**
 * 비회원으로 시작 (Supabase 익명 로그인). captchaToken: Turnstile 토큰 (Supabase Auth에서 캡차를 켰을 때 필요).
 * Supabase에서 "Allow anonymous sign-ins"가 켜져 있어야 한다.
 */
export async function signInAsGuest(captchaToken) {
  const { error } = await db().auth.signInAnonymously(captchaToken ? { options: { captchaToken } } : undefined);
  if (!error) return;
  if (/anonymous sign-ins are disabled/i.test(error.message)) {
    throw new Error('비회원 시작이 아직 꺼져 있습니다. (Supabase에서 Allow anonymous sign-ins를 켜야 합니다)');
  }
  if (/captcha/i.test(error.message)) throw new Error('자동 가입 방지 확인을 다시 해 주세요.');
  if (/rate limit|too many/i.test(error.message)) throw new Error('잠시 뒤에 다시 시도해 주세요. (짧은 시간에 너무 많이 시작했습니다)');
  throw new Error(`비회원으로 시작하지 못했습니다. (${error.message})`);
}

/**
 * 비회원이 [새 계정으로 시작하기]·[기존 계정으로 로그인]: 이 기기에서만 비회원 세션을 지우고 구글·카카오로 로그인.
 * 비회원 계정은 다시 들어올 수 없다 (기록은 남고, 오래 안 쓴 비회원 정리 규칙을 따른다).
 */
export async function startFresh(provider, returnTo = '/') {
  await forgetDevicePush(); // 비회원 때 켠 알림이 다음 계정으로 가지 않게 (037)
  await db().auth.signOut({ scope: 'local' });
  await signIn(provider, returnTo);
}

/** 마지막 접속 기록 (비회원 정리 기준). 하루 한 번만 부른다 — 실패해도 조용히 */
export async function touchLastSeen(userId) {
  const key = `seen:${userId}`;
  const today = new Date().toISOString().slice(0, 10);
  try {
    if (localStorage.getItem(key) === today) return;
    localStorage.setItem(key, today);
  } catch { /* 저장소를 못 쓰면 매번 부른다 (DB가 1시간 안에는 다시 쓰지 않음) */ }
  await db().rpc('touch_last_seen').then(() => {}, () => {});
}

/** 내 계정에 붙어 있는 로그인 방식들 [{ provider, email, createdAt }] */
export async function getIdentities() {
  const { data, error } = await db().auth.getUserIdentities();
  if (error) throw new Error(`연결된 로그인 방식을 불러오지 못했습니다. (${error.message})`);
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
  if (kind === 'upgrade') return { type: 'upgraded', provider };
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
  if (notice.type === 'upgraded') return `${name} 로그인을 연결해서 정식 계정이 됐습니다. 글·제안·경험치·닉네임은 그대로입니다.`;
  if (notice.type === 'linked') return `${name} 로그인을 이 계정에 연결했습니다. 이제 ${name}로 로그인해도 같은 계정입니다.`;
  const others = notice.others.map((p) => PROVIDERS[p]).join('·');
  return `같은 이메일로 이미 가입된 계정(${others})이 있어서, ${name} 로그인을 그 계정에 연결했습니다. 앞으로 어느 쪽으로 로그인해도 같은 계정입니다.`;
}

function clearCallbackParams() {
  const url = new URL(window.location.href);
  CALLBACK_PARAMS.forEach((p) => url.searchParams.delete(p));
  if (CALLBACK_PARAMS.some((p) => new URLSearchParams(url.hash.slice(1)).has(p))) url.hash = '';
  window.history.replaceState(window.history.state, '', url.toString());
}

function loginError(error, providerError, providerCode, pending) {
  const raw = error?.message ?? providerError ?? '';
  const upgrading = pending?.kind === 'upgrade';
  const linking = pending?.kind === 'link' || upgrading;
  const name = PROVIDERS[pending?.provider] ?? '';
  let message;
  const taken = providerCode === 'identity_already_exists' || /already linked|identity_already_exists/i.test(raw)
    || ((providerCode === 'email_exists' || /email.*(already|exists)|already.*registered/i.test(raw)) && upgrading);
  if (taken && upgrading) {
    // 비회원이 연결하려던 구글·카카오가 이미 다른 회원 계정 → 기존 계정으로 로그인할지 묻는다 (합치지 않음)
    return Object.assign(new Error(ALREADY_MEMBER_TEXT), {
      detail: raw || null, title: '연결하지 못했습니다.', retryTo: '/me', existing: pending.provider,
    });
  }
  if (taken) {
    message = `이 ${name || '로그인'} 계정은 이미 다른 회원 계정에 연결돼 있습니다. 그 계정으로 로그인하거나, 다른 ${name || '로그인'} 계정으로 연결해 주세요.`;
  } else if (/manual linking/i.test(raw)) {
    message = '계정 연결 기능이 아직 꺼져 있습니다. (Supabase에서 Allow manual linking을 켜야 합니다)';
  } else if (providerError && !error?.message?.match(/verifier|flow state|ByteString|fetch/i)) {
    message = linking ? `${name} 연결이 취소됐거나 거절됐습니다. 다시 시도해 주세요.` : '로그인이 취소됐거나 거절됐습니다. 다시 시도해 주세요.';
  } else if (/ByteString|ISO-8859-1|Failed to fetch|NetworkError|Load failed/i.test(raw)) {
    message = 'Supabase 서버에 로그인 요청을 보내지 못했습니다. 인터넷 연결과 Supabase 키 설정(.env / Cloudflare 환경변수)을 확인해 주세요.';
  } else if (/verifier/i.test(raw) || !error) {
    // code는 왔는데 이 브라우저에 로그인 시작 기록(code verifier)이 없음
    message = '로그인을 시작한 곳과 돌아온 곳이 다릅니다. 같은 주소, 같은 브라우저 창에서 다시 로그인해 주세요.';
  } else if (/flow state|expired|already|invalid grant/i.test(raw)) {
    message = '로그인 코드가 만료됐거나 이미 사용됐습니다. 다시 로그인해 주세요.';
  } else {
    message = '로그인을 마치지 못했습니다. 다시 시도해 주세요.';
  }
  return Object.assign(new Error(message), {
    detail: raw || null,
    title: linking ? '계정을 연결하지 못했습니다.' : '로그인하지 못했습니다.',
    retryTo: upgrading ? '/me' : linking ? SETTINGS_PATH : '/login',
  });
}

export async function signOut() {
  await forgetDevicePush(); // 이 기기의 알림 주소를 먼저 지운다 (로그인이 남아 있을 때만 지울 수 있음, 037)
  const { error } = await db().auth.signOut();
  if (error) throw new Error(`로그아웃하지 못했습니다. (${error.message})`);
}

export async function getSession() {
  const { data, error } = await db().auth.getSession();
  if (error) throw new Error(`로그인 정보를 불러오지 못했습니다. (${error.message})`);
  return data.session;
}

/** 로그인 상태가 바뀔 때마다 cb(session). 해제 함수를 돌려준다. */
export function onAuthChange(cb) {
  // 주의: 이 콜백 안에서 Supabase를 await 하면 안 된다 (supabase-js 내부 잠금과 엉킴)
  const { data } = db().auth.onAuthStateChange((_event, session) => cb(session));
  return () => data.subscription.unsubscribe();
}

const RESERVED_NICKNAME_MESSAGE = '닉네임에는 (운)·(감)을 쓸 수 없습니다.';

const PROFILE_COLUMNS_OLD = 'id, nickname, role, xp, level, main_title, is_guest';
// operator_mode = 운영자 모드 (034). 034 실행 전 DB에는 이 칸이 없으므로 그때는 옛 칸만 읽는다 (모드 = 켜짐으로 본다)
const PROFILE_COLUMNS_MODE = `${PROFILE_COLUMNS_OLD}, operator_mode`;
// 046: 장인(influencer)·인증 대기/닉네임 변경 예정(nickname_state, nickname_reset_at). 046 전 DB면 위 칸으로 한 번 더
const PROFILE_COLUMNS = `${PROFILE_COLUMNS_MODE}, influencer, nickname_state, nickname_reset_at`;
const missingColumn = (error) => error?.code === '42703' || /does not exist/.test(error?.message ?? '');

/** 프로필 칸을 골라 읽는 요청(run(칸 목록))을 보낸다. 새 칸이 아직 없으면 옛 칸으로 다시 */
async function withProfileColumns(run) {
  let res = await run(PROFILE_COLUMNS);
  if (missingColumn(res.error)) res = await run(PROFILE_COLUMNS_MODE);
  return missingColumn(res.error) ? run(PROFILE_COLUMNS_OLD) : res;
}

/** 내 프로필 (첫 로그인 시 DB 트리거가 만든다. nickname이 null이면 닉네임 설정 전) */
export async function getProfile(userId) {
  const { data, error } = await withProfileColumns((cols) => db().from('profiles').select(cols).eq('id', userId).maybeSingle());
  if (error) throw new Error(`프로필을 불러오지 못했습니다. (${error.message})`);
  return data;
}

/**
 * 운영자 모드 켜기/끄기 (034). 운영자 본인만 — 운영자가 아니면 DB가 거부한다.
 * 돌려주는 값: 바뀐 내 프로필 (화면 전체가 이 값으로 운영자/일반 회원 화면을 고른다)
 */
export async function setOperatorMode(userId, on) {
  const { error } = await db().rpc('set_operator_mode', { p_on: on });
  if (error) {
    if (/[가-힣]/.test(error.message ?? '')) throw new Error(error.message);
    throw new Error(`운영자 모드를 바꾸지 못했습니다. (${error.message})`);
  }
  return getProfile(userId);
}

/** 닉네임 앞뒤 공백 제거 + 규칙 검사. 문제가 있으면 안내 문구, 없으면 null */
export function nicknameProblem(raw) {
  const nickname = raw.trim();
  if (!nickname) return '닉네임을 입력해 주세요.';
  if ([...nickname].length > NICKNAME_MAX) return `닉네임은 ${NICKNAME_MAX}자 이하로 정해 주세요.`;
  if (hasReservedMark(nickname)) return RESERVED_NICKNAME_MESSAGE;
  if (mimicsInfluencer(nickname)) return INFLUENCER_MARK_MESSAGE;
  return null;
}

export const HELD_NICKNAME_MESSAGE = '최근 탈퇴한 장인의 닉네임이라 30일 동안 사용할 수 없습니다.';

export async function saveNickname(userId, raw) {
  const problem = nicknameProblem(raw);
  if (problem) throw new Error(problem);
  const { data, error } = await withProfileColumns((cols) => db()
    .from('profiles')
    .update({ nickname: raw.trim() })
    .eq('id', userId)
    .select(cols)
    .maybeSingle());
  if (error) {
    // 055: 예약된 닉네임도 같은 23505라서 DB 문구("최근 탈퇴한 장인의 닉네임…")로 구분한다
    if (error.code === '23505' && /최근 탈퇴한 장인/.test(error.message ?? '')) throw new Error(HELD_NICKNAME_MESSAGE);
    if (error.code === '23505') throw new Error('이미 사용 중인 닉네임입니다. 비슷한 닉네임도 쓸 수 없습니다.');
    if (error.code === '42501' && /장인/.test(error.message ?? '')) throw new Error(error.message); // 046: 장인·인증 대기는 직접 못 바꿈
    if (error.code === 'P0001') throw new Error(error.message); // 30일에 한 번 (DB 문구에 다음 날짜가 들어 있다)
    if (error.code === '23514' && /\(운\)/.test(error.message ?? '')) throw new Error(RESERVED_NICKNAME_MESSAGE);
    if (error.code === '23514' && /장인/.test(error.message ?? '')) throw new Error(INFLUENCER_MARK_MESSAGE);
    if (error.code === '23514') throw new Error(`닉네임은 앞뒤 공백 없이 1~${NICKNAME_MAX}자로 정해 주세요.`);
    throw new Error(`닉네임을 저장하지 못했습니다. (${error.message})`);
  }
  if (!data) throw new Error('프로필을 찾지 못했습니다. 로그아웃 후 다시 로그인해 주세요.');
  return data;
}

// ---------------- 닉네임 변경 · 회원 탈퇴 (017, SPEC 6-8) ----------------

/** 닉네임 변경 규칙: 마지막으로 바꾼 때와 다음에 바꿀 수 있는 때 (처음 정한 것은 변경이 아님). 기록은 본인만 읽는다 */
export async function getNicknameRule(userId) {
  const [changes, rule] = await Promise.all([
    db().from('nickname_changes').select('*').eq('user_id', userId).order('changed_at', { ascending: false }).limit(20),
    db().from('xp_rules').select('value').eq('key', 'nickname_change_days').maybeSingle(),
  ]);
  if (changes.error || rule.error) throw new Error('닉네임 변경 정보를 불러오지 못했습니다.');
  const days = rule.data?.value ?? 30;
  // 046: 본인이 바꾼 것(user)·신청(apply)만 30일 제한에 센다. 마지막 변경이 운영자·되돌림·임시 닉네임(admin·revert·reset)이면 바로 바꿀 수 있다 (DB keep_nickname과 같음)
  const counted = (c) => !c.kind || c.kind === 'user' || c.kind === 'apply';
  const rows = changes.data ?? [];
  const free = rows.length > 0 && !counted(rows[0]);
  const last = rows.find(counted)?.changed_at ?? null;
  const next = last && !free ? new Date(Date.parse(last) + days * 86400000).toISOString() : null;
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
    throw new Error(message ?? `탈퇴하지 못했습니다. (${error.message})`);
  }
  await dropBrowserPush(); // 알림 주소는 계정과 함께 DB에서 지워졌다 — 이 브라우저 구독만 끊는다 (037)
  await db().auth.signOut({ scope: 'local' }).catch(() => {});
}
