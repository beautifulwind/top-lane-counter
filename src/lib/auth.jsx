import { createContext, useCallback, useContext, useEffect, useState } from 'react';
import { finishLoginFromUrl, getProfile, getSession, onAuthChange } from '../api/auth';

/**
 * 로그인 상태를 앱 전체에 공유한다.
 * status: 'loading'(확인 중) | 'signedOut' | 'signedIn'
 * profile: 로그인했을 때 내 프로필 (불러오는 중이면 undefined)
 */
const AuthContext = createContext(null);
const SIGNED_OUT = { status: 'signedOut', session: null, user: null, profile: null, isAdmin: false, setProfile: () => {}, loginError: null, clearLoginError: () => {} };

export function AuthProvider({ children }) {
  const [session, setSession] = useState(undefined); // undefined = 아직 확인 중
  const [loginError, setLoginError] = useState(null); // 구글에서 돌아왔는데 로그인이 안 됐을 때
  const [loaded, setLoaded] = useState({ userId: null, profile: undefined, error: null });

  useEffect(() => {
    let alive = true;
    let off = () => {};
    try {
      off = onAuthChange((s) => alive && setSession(s));
      finishLoginFromUrl()
        .catch((e) => alive && setLoginError(e))
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

  const setProfile = useCallback((profile) => setLoaded({ userId, profile, error: null }), [userId]);
  const clearLoginError = useCallback(() => setLoginError(null), []);

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
      isAdmin: profile?.role === 'admin',
      setProfile,
      loginError: null,
      clearLoginError,
    };
  }
  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

/** Provider 밖(일부 테스트)에서는 로그아웃 상태로 동작 */
export function useAuth() {
  return useContext(AuthContext) ?? SIGNED_OUT;
}

/** 로그인했고 프로필도 불러왔는데 닉네임이 아직 없는가 */
export const needsNickname = (auth) => auth.status === 'signedIn' && auth.profile !== undefined && !auth.profile?.nickname;
