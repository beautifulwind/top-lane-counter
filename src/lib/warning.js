// 아직 확인하지 않은 내 경고 (069, SPEC 6-86) — 앱 전체가 하나를 나눠 쓴다 (restriction.js와 같은 방식).
// 다시 읽는 때: 로그인 확인 뒤, 앱·탭이 다시 보일 때(30초 안이면 건너뜀), 알림이 바뀌었을 때(푸시·읽음 처리), [확인했습니다] 뒤.
import { useEffect, useSyncExternalStore } from 'react';
import { ackWarning, getMyWarnings } from '../api/warnings';
import { announceNotificationsChanged, onNotificationsChanged } from '../api/notifications';

let state = { userId: null, warnings: [] };
const subs = new Set();
const publish = (next) => {
  state = next;
  subs.forEach((f) => f());
};
const subscribe = (f) => {
  subs.add(f);
  return () => subs.delete(f);
};

export const WARNING_RECHECK_MS = 30000;
let last = { userId: null, at: 0 };

/** 지금 사용자의 안 본 경고를 다시 읽는다 (실패는 조용히 — 이전 값 유지) */
export async function refreshWarnings(userId) {
  if (!userId) return;
  last = { userId, at: Date.now() };
  try {
    const warnings = await getMyWarnings();
    if (last.userId === userId) publish({ userId, warnings });
  } catch {
    /* 못 읽으면 그대로 둔다 */
  }
}

/** 지금 사용자의 안 본 경고 목록 (로그아웃·다른 사용자 값이면 빈 목록) */
export function useWarnings(userId) {
  const snap = useSyncExternalStore(subscribe, () => state);
  return userId && snap.userId === userId ? snap.warnings : [];
}

/** [확인했습니다]: 저장되면 목록에서 뺀다 (다음 경고가 있으면 그것이 보인다). 실패하면 던진다 */
export async function acknowledge(userId, id) {
  await ackWarning(id);
  if (state.userId === userId) publish({ userId, warnings: state.warnings.filter((w) => w.id !== id) });
  announceNotificationsChanged(); // 그 경고 알림도 읽음이 됐다 → 빨간 점 다시 세기
}

/** 안내 상자가 한 번 부른다: 로그인 확인 뒤 + 다시 보일 때 + 알림이 바뀔 때 */
export function useWarningRefresher(userId) {
  useEffect(() => {
    if (!userId) {
      last = { userId: null, at: 0 };
      if (state.userId !== null) publish({ userId: null, warnings: [] });
      return undefined;
    }
    refreshWarnings(userId);
    const off = onNotificationsChanged(() => refreshWarnings(userId)); // 새 경고 알림이 푸시로 왔을 때
    const onVisible = () => {
      if (document.visibilityState === 'visible' && (last.userId !== userId || Date.now() - last.at >= WARNING_RECHECK_MS)) {
        refreshWarnings(userId);
      }
    };
    document.addEventListener('visibilitychange', onVisible);
    window.addEventListener('pageshow', onVisible);
    return () => {
      off();
      document.removeEventListener('visibilitychange', onVisible);
      window.removeEventListener('pageshow', onVisible);
    };
  }, [userId]);
}

/** 검사용: 상태 초기화 */
export function resetWarningsForTest() {
  last = { userId: null, at: 0 };
  state = { userId: null, warnings: [] };
}
