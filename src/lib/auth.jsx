import { createContext, useCallback, useContext, useEffect, useMemo, useState } from 'react';
import { finishLoginFromUrl, getProfile, getSession, onAuthChange, touchLastSeen } from '../api/auth';
import { blockUser, getMyBlocks, unblockUser } from '../api/blocks';
import { isGuest } from './guest';
import { onNativeAuth } from './nativeAuth';
import { syncAppPush } from './nativePush';
import { isStaffPerson } from './nickname';

/**
 * 로그인 상태를 앱 전체에 공유한다.
 * status: 'loading'(확인 중) | 'signedOut' | 'signedIn'
 * profile: 로그인했을 때 내 프로필 (불러오는 중이면 undefined)
 */
const AuthContext = createContext(null);
const NO_BLOCKS = new Set();
const notSignedIn = () => Promise.reject(new Error('로그인한 뒤 차단할 수 있습니다.'));
// 061 차단 (SPEC 6-67): blocked = 내가 차단한 사람 id 모음, blocks = 설정 화면 목록, block·unblock = 차단·해제 (바로 화면에 반영)
const SIGNED_OUT_BLOCKS = { blocked: NO_BLOCKS, blocks: [], blocksReady: false, blocksAvailable: false, block: notSignedIn, unblock: notSignedIn };
const SIGNED_OUT = { ...SIGNED_OUT_BLOCKS, status: 'signedOut', session: null, user: null, profile: null, isOperatorAccount: false, isOperator: false, isModerator: false, isStaff: false, setProfile: () => {}, loginError: null, clearLoginError: () => {}, notice: null, clearNotice: () => {}, cameBack: false, clearCameBack: () => {}, goTo: null, clearGoTo: () => {} };

/** 운영자 모드가 켜진 운영자인가 (034: profiles.operator_mode, 없으면 켜짐) */
const operatorOn = (profile) => profile?.role === 'admin' && profile?.operator_mode !== false;

export function AuthProvider({ children }) {
  const [session, setSession] = useState(undefined); // undefined = 아직 확인 중
  const [loginError, setLoginError] = useState(null); // 구글/카카오에서 돌아왔는데 로그인·연결이 안 됐을 때
  const [notice, setNotice] = useState(null); // 기존 계정에 합쳐짐 / 연결함 안내
  // 구글·카카오에서 막 돌아왔나 (처음 가입한 사람은 닉네임 정하기를 한 번 보여 준다 — 건너뛸 수 있음)
  const [cameBack, setCameBack] = useState(() => /[?&]code=/.test(window.location.search));
  const [loaded, setLoaded] = useState({ userId: null, profile: undefined, error: null });
  // 앱(6-57): 로그인을 마친 뒤 갈 경로 (웹은 구글·카카오가 그 경로로 돌려보내지만, 앱은 같은 화면에 머물러 있으므로 Layout이 옮긴다)
  const [goTo, setGoTo] = useState(null);

  // 앱(6-57): 시스템 브라우저에서 돌아온 로그인 결과 (웹에서는 아무것도 오지 않는다)
  useEffect(() => {
    const off = onNativeAuth((r) => {
      if (r.type === 'success') {
        setLoginError(null);
        setNotice(r.notice ?? null);
        setCameBack(true); // 처음 가입한 사람에게 닉네임 정하기를 한 번 (웹과 같음)
        if (r.returnTo) setGoTo(r.returnTo);
      } else {
        setLoginError(r.error); // 실패·취소: 위 띠에 안내 + [다시 로그인]
      }
    });
    return off;
  }, []);

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

  // 061 내 차단 목록: 로그인하면 한 번 읽는다. 차단 표가 없거나(061 전) 못 읽으면 아무것도 숨기지 않는다
  const [blockState, setBlockState] = useState({ userId: null, rows: [], ready: false, available: false });
  useEffect(() => {
    if (!userId) return undefined;
    let alive = true;
    getMyBlocks(userId).then(
      (r) => alive && setBlockState({ userId, rows: r.rows, ready: true, available: r.available }),
      () => alive && setBlockState({ userId, rows: [], ready: true, available: false }),
    );
    return () => { alive = false; };
  }, [userId]);
  const block = useCallback(async (targetId, person = null) => {
    await blockUser(userId, targetId);
    setBlockState((b) => {
      // 목록을 아직 못 읽었어도 방금 차단한 사람은 바로 숨긴다
      const base = b.userId === userId ? b : { userId, rows: [], ready: false };
      if (base.rows.some((r) => r.blocked_id === targetId)) return { ...base, available: true };
      return { ...base, available: true, rows: [{ blocked_id: targetId, created_at: new Date().toISOString(), blocked: person }, ...base.rows] };
    });
  }, [userId]);
  const unblock = useCallback(async (targetId) => {
    await unblockUser(userId, targetId);
    setBlockState((b) => (b.userId === userId ? { ...b, rows: b.rows.filter((r) => r.blocked_id !== targetId) } : b));
  }, [userId]);
  const blockRows = blockState.userId === userId ? blockState.rows : null;
  const blocked = useMemo(() => (blockRows && blockRows.length > 0 ? new Set(blockRows.map((r) => r.blocked_id)) : NO_BLOCKS), [blockRows]);

  // 마지막 접속 (오래 안 쓴 비회원 정리 기준, 하루 한 번)
  useEffect(() => {
    if (userId) touchLastSeen(userId);
  }, [userId]);

  // 앱(P-3): 로그인 확인 뒤 이 기기 알림 토큰 등록·갱신 (처음이면 권한을 한 번 묻는다). 웹에서는 아무것도 안 함, 실패는 조용히
  useEffect(() => {
    syncAppPush(userId).catch(() => {});
  }, [userId]);

  const setProfile = useCallback((profile) => setLoaded({ userId, profile, error: null }), [userId]);
  const clearLoginError = useCallback(() => setLoginError(null), []);
  const clearNotice = useCallback(() => setNotice(null), []);
  const clearCameBack = useCallback(() => setCameBack(false), []);
  const clearGoTo = useCallback(() => setGoTo(null), []);

  let value;
  if (session === undefined) value = { ...SIGNED_OUT, status: 'loading' };
  else if (!session) value = { ...SIGNED_OUT, loginError, clearLoginError, goTo, clearGoTo };
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
      goTo,
      clearGoTo,
      blocked,
      blocks: blockRows ?? [],
      blocksReady: blockState.userId === userId && blockState.ready,
      blocksAvailable: blockState.userId === userId && blockState.available,
      block,
      unblock,
    };
  }
  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

/** Provider 밖(일부 테스트)에서는 로그아웃 상태로 동작 */
export function useAuth() {
  return useContext(AuthContext) ?? SIGNED_OUT;
}

/** 내가 차단한 사람인가 (061). Provider 밖에서 만든 auth(일부 테스트)에는 차단 목록이 없다 → false */
export const isBlocked = (auth, userId) => userId != null && Boolean(auth?.blocked?.has?.(userId));

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
