// 로그인·프로필 접근 계층. 화면 컴포넌트는 이 모듈만 호출한다.
import { db } from './supabase';

export const NICKNAME_MAX = 20;

/** 로그인할 수 있는 방식 (Supabase Auth의 provider 이름 → 화면에 보일 이름) */
export const PROVIDERS = { google: '구글', kakao: '카카오' };

/**
 * 소셜 로그인 시작 → 구글/카카오 → Supabase → 지금 접속한 주소(origin)의 returnTo 경로로 돌아온다.
 * 카카오: Supabase가 account_email·profile_nickname·profile_image를 항상 요청한다 (scopes로 뺄 수 없음).
 *   이메일은 카카오 동의항목에서 "선택 동의"로 두고, Supabase에서 "Allow users without an email"을 켠다.
 *   앱은 이메일을 쓰지 않는다.
 */
export async function signIn(provider, returnTo = '/') {
  if (!PROVIDERS[provider]) throw new Error(`지원하지 않는 로그인 방식이에요. (${provider})`);
  const { error } = await db().auth.signInWithOAuth({
    provider,
    options: { redirectTo: window.location.origin + returnTo },
  });
  if (error) throw new Error(`로그인을 시작하지 못했어요. (${error.message})`);
}

// 로그인 후 돌아온 주소에 붙는 값들 (처리 후 주소창에서 지운다)
const CALLBACK_PARAMS = ['code', 'sb_flow_id', 'error', 'error_code', 'error_description'];

/**
 * 구글/카카오 → Supabase를 거쳐 ?code=...로 돌아왔을 때, 그 code가 세션으로 바뀌었는지 확인한다.
 * (supabase-js는 이 단계가 실패해도 콘솔에 아무것도 남기지 않으므로 여기서 직접 잡아 화면에 보여준다)
 * 로그인 콜백이 아니면 아무 일도 하지 않는다. 실패하면 안내 문구가 담긴 Error를 던진다.
 */
export async function finishLoginFromUrl() {
  const query = new URLSearchParams(window.location.search);
  const hash = new URLSearchParams(window.location.hash.slice(1));
  const providerError = query.get('error_description') ?? hash.get('error_description');
  if (!query.has('code') && !providerError) return;

  const auth = db().auth;
  const { error } = await auth.initialize(); // supabase-js가 code → 세션 교환을 마칠 때까지 기다림
  const { data } = await auth.getSession();
  clearCallbackParams();
  if (data.session && !error) return;
  throw loginError(error, providerError);
}

function clearCallbackParams() {
  const url = new URL(window.location.href);
  CALLBACK_PARAMS.forEach((p) => url.searchParams.delete(p));
  if (CALLBACK_PARAMS.some((p) => new URLSearchParams(url.hash.slice(1)).has(p))) url.hash = '';
  window.history.replaceState(window.history.state, '', url.toString());
}

function loginError(error, providerError) {
  const raw = error?.message ?? providerError ?? '';
  let message;
  if (providerError && !error?.message?.match(/verifier|flow state|ByteString|fetch/i)) {
    message = '로그인이 취소됐거나 거절됐어요. 다시 시도해 주세요.';
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
  return Object.assign(new Error(message), { detail: raw || null });
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
    if (error.code === '23514') throw new Error(`닉네임은 앞뒤 공백 없이 1~${NICKNAME_MAX}자로 정해 주세요.`);
    throw new Error(`닉네임을 저장하지 못했어요. (${error.message})`);
  }
  if (!data) throw new Error('프로필을 찾지 못했어요. 로그아웃 후 다시 로그인해 주세요.');
  return data;
}
