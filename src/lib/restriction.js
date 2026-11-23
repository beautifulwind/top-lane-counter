// 내 활동 제한 상태 (068, SPEC 6-85) — 앱 전체가 하나를 나눠 쓴다 (unread.js와 같은 방식).
// 다시 읽는 때: 로그인 확인 뒤, 앱·탭이 다시 보일 때(30초 안이면 건너뜀), 풀리는 시각이 지났을 때, 쓰기 버튼이 막혔을 때.
// 실제로 막는 것은 DB다 — 여기 상태는 띠와 흐린 버튼을 그리는 데만 쓴다(조금 늦어도 서버가 같은 문장으로 막는다).
import { useEffect, useSyncExternalStore } from 'react';
import { getMyRestriction } from '../api/restrictions';

let state = { userId: null, ready: true, restriction: null };
const subs = new Set();
const publish = (next) => {
  state = next;
  subs.forEach((f) => f());
};
const subscribe = (f) => {
  subs.add(f);
  return () => subs.delete(f);
};

export const RESTRICTION_RECHECK_MS = 30000;
let last = { userId: null, at: 0 };

/** 지금 사용자의 제한을 다시 읽는다 (실패는 조용히 — 이전 값 유지) */
export async function refreshRestriction(userId) {
  if (!userId) return;
  last = { userId, at: Date.now() };
  try {
    const { ready, restriction } = await getMyRestriction();
    if (last.userId === userId) publish({ userId, ready, restriction });
  } catch {
    /* 못 읽으면 그대로 둔다 */
  }
}

/** 지금 사용자의 제한 { ready, restriction } (로그아웃·다른 사용자 값이면 제한 없음) */
export function useRestriction(userId) {
  const snap = useSyncExternalStore(subscribe, () => state);
  if (!userId || snap.userId !== userId) return { ready: true, restriction: null };
  // 풀리는 시각이 지났으면 다시 읽기 전이라도 제한 없음으로 본다
  if (snap.restriction && Date.parse(snap.restriction.ends_at) <= Date.now()) return { ready: snap.ready, restriction: null };
  return snap;
}

/** 지금 제한 중인지 (이벤트 처리기에서 읽기용) */
export const currentRestriction = () =>
  state.restriction && Date.parse(state.restriction.ends_at) > Date.now() ? state.restriction : null;

/** 띠가 한 번 부른다: 로그인 확인 뒤 + 다시 보일 때 + 풀리는 시각에 */
export function useRestrictionRefresher(userId) {
  const { restriction } = useRestriction(userId);
  useEffect(() => {
    if (!userId) {
      last = { userId: null, at: 0 };
      if (state.userId !== null) publish({ userId: null, ready: true, restriction: null });
      return undefined;
    }
    refreshRestriction(userId);
    const onVisible = () => {
      if (document.visibilityState === 'visible' && (last.userId !== userId || Date.now() - last.at >= RESTRICTION_RECHECK_MS)) {
        refreshRestriction(userId);
      }
    };
    document.addEventListener('visibilitychange', onVisible);
    window.addEventListener('pageshow', onVisible);
    return () => {
      document.removeEventListener('visibilitychange', onVisible);
      window.removeEventListener('pageshow', onVisible);
    };
  }, [userId]);
  // 풀리는 시각이 되면 다시 읽어 띠를 내린다 (setTimeout 최대값을 넘으면 그만큼만 기다렸다 다시)
  const endsAt = restriction?.ends_at;
  useEffect(() => {
    if (!userId || !endsAt) return undefined;
    const wait = Math.min(Math.max(Date.parse(endsAt) - Date.now() + 1000, 1000), 2 ** 31 - 1);
    const t = setTimeout(() => refreshRestriction(userId), wait);
    return () => clearTimeout(t);
  }, [userId, endsAt]);
}

// ---- 쓰기 버튼 막기: data-write가 붙은 버튼·링크·폼 ----
// 제한 중이면 흐리게(CSS .is-restricted [data-write]) 보이고, 누르면 동작 대신 같은 이유를 보여 준다.
const blockedSubs = new Set();
/** 막힌 순간 알림을 받는다 (띠 컴포넌트가 안내 상자를 띄움) */
export function onWriteBlocked(f) {
  blockedSubs.add(f);
  return () => blockedSubs.delete(f);
}

function block(e, restriction) {
  e.preventDefault();
  e.stopPropagation();
  blockedSubs.forEach((f) => f(restriction));
}

/** 문서에 한 번 건다 (capture 단계 — 각 버튼의 onClick보다 먼저) */
export function installWriteGuard(doc = document) {
  const onClick = (e) => {
    const r = currentRestriction();
    if (!r) return;
    const el = e.target instanceof Element ? e.target.closest('[data-write]') : null;
    if (el && el.tagName !== 'FORM') block(e, r);
  };
  const onSubmit = (e) => {
    const r = currentRestriction();
    if (!r) return;
    const form = e.target;
    if (form instanceof Element && (form.matches('[data-write]') || form.querySelector('[type="submit"][data-write]'))) block(e, r);
  };
  doc.addEventListener('click', onClick, true);
  doc.addEventListener('submit', onSubmit, true);
  return () => {
    doc.removeEventListener('click', onClick, true);
    doc.removeEventListener('submit', onSubmit, true);
  };
}

/** 검사용: 상태 초기화 */
export function resetRestrictionForTest() {
  last = { userId: null, at: 0 };
  state = { userId: null, ready: true, restriction: null };
}
