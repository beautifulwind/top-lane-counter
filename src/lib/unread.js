// 안 읽은 알림 개수 (빨간 점·마이페이지 [알림 보기]) — 앱 전체가 하나를 나눠 쓴다.
// 다시 세는 때: 앱을 열 때(로그인 확인 뒤), 푸시 알림이 왔을 때, 알림을 읽음 처리한 직후. 화면을 옮길 때는 세지 않는다.
// 푸시 → sw.js가 PUSH_RECEIVED를 받아 announceNotificationsChanged(), 읽음 처리 → markAllNotificationsRead()가 같은 신호를 보낸다.
import { useEffect, useSyncExternalStore } from 'react';
import { getUnreadCount, onNotificationsChanged } from '../api/notifications';

let state = { userId: null, count: 0 };
const subs = new Set();
const publish = (next) => {
  state = next;
  subs.forEach((f) => f());
};
const subscribe = (f) => {
  subs.add(f);
  return () => subs.delete(f);
};

let inflight = null; // { userId, again }
/** 지금 사용자의 개수를 다시 센다. 세는 중에 또 부르면 그 뒤 한 번만 더 센다(여러 신호가 몰려도 요청이 겹치지 않음). 실패는 조용히 */
export function refreshUnreadCount(userId) {
  if (!userId) return Promise.resolve();
  if (inflight && inflight.userId === userId) {
    inflight.again = true;
    return inflight.done;
  }
  const job = { userId, again: false };
  job.done = (async () => {
    try {
      do {
        job.again = false;
        const n = await getUnreadCount(userId).catch(() => null);
        if (n !== null && inflight === job) publish({ userId, count: n });
      } while (job.again);
    } finally {
      if (inflight === job) inflight = null;
    }
  })();
  inflight = job;
  return job.done;
}

/** 읽기만 하는 훅: 지금 사용자의 안 읽은 알림 개수 (다른 사용자 값·로그아웃은 0) */
export function useUnreadCount(userId) {
  const snap = useSyncExternalStore(subscribe, () => state);
  return userId && snap.userId === userId ? snap.count : 0;
}

/** 상단 메뉴가 한 번 부른다: 로그인 확인 뒤 한 번 + 푸시·읽음 처리 신호마다 */
export function useUnreadRefresher(userId) {
  useEffect(() => {
    if (!userId) return undefined;
    refreshUnreadCount(userId);
    return onNotificationsChanged(() => refreshUnreadCount(userId));
  }, [userId]);
}
