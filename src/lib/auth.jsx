import { createContext, useCallback, useContext, useEffect, useState } from 'react';
import { finishLoginFromUrl, getProfile, getSession, onAuthChange, touchLastSeen } from '../api/auth';
import { isGuest } from './guest';
import { isStaffPerson } from './nickname';

/**
 * 로그인 상태를 앱 전체에 공유한다.
 * status: 'loading'(확인 중) | 'signedOut' | 'signedIn'
 * profile: 로그인했을 때 내 프로필 (불러오는 중이면 undefined)
 */
const AuthContext = createContext(null);
const SIGNED_OUT = { status: 'signedOut', session: null, user: null, profile: null, isOperatorAccount: false, isOperator: false, isModerator: false, isStaff: false, setProfile: () => {}, loginError: null, clearLoginError: () => {}, notice: null, clearNotice: () => {}, cameBack: false, clearCameBack: () => {} };

/** 운영자 모드가 켜진 운영자인가 (034: profiles.operator_mode, 없으면 켜짐) */
const operatorOn = (profile) => profile?.role === 'admin' && profile?.operator_mode !== false;

export function AuthProvider({ children }) {
  const [session, setSession] = useState(undefined); // undefined = 아직 확인 중
  const [loginError, setLoginError] = useState(null); // 구글/카카오에서 돌아왔는데 로그인·연결이 안 됐을 때
  const [notice, setNotice] = useState(null); // 기존 계정에 합쳐짐 / 연결함 안내
  // 구글·카카오에서 막 돌아왔나 (처음 가입한 사람은 닉네임 정하기를 한 번 보여 준다 — 건너뛸 수 있음)
  const [cameBack, setCameBack] = useState(() => /[?&]code=/.test(window.location.search));
  const [loaded, setLoaded] = useState({ userId: null, profile: undefined, error: null });

  useEffect(() => {
    let alive = true;
    let off = () => {};
    try {
      off = onAuthChange((s) => alive && setSession(s));
      finishLoginFromUrl()
        .then((n) => alive && n && setNotice(n), (e) => alive && setLoginError(e))
        .then(getSession)
        .then((s) => alive && setSession(s), () => alive && setSession(null));
    } catch (e) {
      // Supabase 설정이 잘못됐으면 로그아웃 상태로 보고, 로그인하고 돌아온 길이었다면 이유를 보여준다
      setSession(null);
      if (/[?&](code|error_description)=/.test(window.location.search)) setLoginError(e);
    }
    return () => { alive = false; off(); };
  }, []);

  const userId = session?.user?.id ?? null;
  useEffect(() => {
    if (!userId) return undefined;
    let alive = true;
    getProfile(userId).then(
      (profile) => alive && setLoaded({ userId, profile, error: null }),
      (error) => alive && setLoaded({ userId, profile: null, error }),
    );
    return () => { alive = false; };
  }, [userId]);

  // 마지막 접속 (오래 안 쓴 비회원 정리 기준, 하루 한 번)
  useEffect(() => {
    if (userId) touchLastSeen(userId);
  }, [userId]);

  const setProfile = useCallback((profile) => setLoaded({ userId, profile, error: null }), [userId]);
  const clearLoginError = useCallback(() => setLoginError(null), []);
  const clearNotice = useCallback(() => setNotice(null), []);
  const clearCameBack = useCallback(() => setCameBack(false), []);

  let value;
  if (session === undefined) value = { ...SIGNED_OUT, status: 'loading' };
  else if (!session) value = { ...SIGNED_OUT, loginError, clearLoginError };
  else {
    const profile = loaded.userId === userId ? loaded.profile : undefined;
    value = {
      status: 'signedIn',
      session,
      user: session.user,
      profile,
      profileError: loaded.userId === userId ? loaded.error : null,
      // 운영자 계정 = role 'admin'인 유일한 계정. 운영자 모드(034)를 꺼도 그대로 — 모드 스위치·Lv.0·탈퇴 불가에만 쓴다
      isOperatorAccount: profile?.role === 'admin',
      // 운영자 (모든 권한) = 운영자 계정 + 운영자 모드 켜짐. 끄면 화면 전체가 일반 회원과 같은 길로 간다.
      // (034 전 DB처럼 operator_mode가 없으면 켜짐으로 본다.) 실제 권한 검사는 DB(is_admin·RLS)가 같은 기준으로 한다.
      isOperator: operatorOn(profile),
      // 감독관 (030): 운영자가 지정. 화면은 허용된 것만 보여 주고, 실제 권한 검사는 DB가 한다.
      isModerator: profile?.role === 'moderator',
      isStaff: operatorOn(profile) || profile?.role === 'moderator',
      setProfile,
      loginError, // 로그인한 채로 계정 연결에 실패했을 때
      clearLoginError,
      notice,
      clearNotice,
      cameBack,
      clearCameBack,
    };
  }
  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

/** Provider 밖(일부 테스트)에서는 로그아웃 상태로 동작 */
export function useAuth() {
  return useContext(AuthContext) ?? SIGNED_OUT;
}

/** 로그인했고 프로필도 불러왔는데 닉네임이 아직 없는가 */
/** 이 글·댓글에 [숨기기]를 보여 줄까: 운영자는 전부, 감독관은 본인·운영진의 것 빼고 (실제 검사는 DB) */
export const canModerate = (auth, authorId, author) =>
  auth.isOperator || (auth.isModerator && authorId !== auth.user?.id && !isStaffPerson(author));

/** [다시 공개]를 보여 줄까: 운영자는 전부, 감독관은 다른 감독관이 숨긴 것만 (실제 검사는 DB) */
export const canRestore = (auth, row) => auth.isOperator || (auth.isModerator && row.hider?.role === 'moderator');

export const needsNickname = (auth) => auth.status === 'signedIn' && auth.profile !== undefined && !auth.profile?.nickname;

/** 쓰기(제안·빌드·투표·글·댓글·신고)를 할 수 있나 = 로그인 + 닉네임. 실제 검사는 DB가 한다 */
export const canWrite = (auth) => auth.status === 'signedIn' && !!auth.profile?.nickname;

/** 빌드 추천·비추천, 자유게시판 추천, 신고를 할 수 있나 = 쓰기 + 비회원 아님 (020, 실제 검사는 DB 트리거) */
export const canVote = (auth) => canWrite(auth) && !isGuest(auth);

export { isGuest };

/**
 * 닉네임을 정해야 열리는 화면 (쓰기 화면과 /me). 닉네임이 없어도 읽기는 어디서나 된다 (SPEC 3장).
 * 이 주소로 오면 닉네임 정하기로 보내고, 정하면 돌아온다.
 */
export const NICKNAME_ROUTES = [
  /^\/champion\/[^/]+\/propose$/,
  /^\/matchup\/new$/,
  /^\/champion\/[^/]+\/counter\/[^/]+\/(edit|build\/new|build\/\d+\/edit)$/,
  /^\/board\/(new|\d+\/edit)$/,
  /^\/me(\/|$)/,
];
export const needsNicknameFor = (pathname) => NICKNAME_ROUTES.some((r) => r.test(pathname));
