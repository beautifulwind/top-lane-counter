import { useCallback, useEffect, useRef, useState } from 'react';
import { AlertIcon } from './Icons';

export const NOTICE_MS = 8000;

/** 추천 안내 한 줄: [notice, show, clear]. 8초 뒤 저절로 사라지고, 새 안내가 오면 시간을 다시 잼 */
export function useVoteNotice(ms = NOTICE_MS) {
  const [notice, setNotice] = useState(null);
  const timer = useRef(null);
  useEffect(() => {
    return () => clearTimeout(timer.current);
  }, []);
  const clear = useCallback(() => {
    clearTimeout(timer.current);
    setNotice(null);
  }, []);
  const show = useCallback((next) => {
    clearTimeout(timer.current);
    setNotice(next);
    timer.current = setTimeout(() => setNotice(null), ms);
  }, [ms]);
  return [notice, show, clear];
}

/**
 * 추천 버튼 밑 안내 (SPEC 6-79). 마우스를 올려야 뜨는 말풍선과 달리 폰에서도 보인다.
 * kind="error": 서버가 거절했다(role=alert, 빨강) / kind="info": 눌렀을 때 이유·다음 행동 안내(role=status).
 */
export default function VoteNotice({ notice }) {
  if (!notice) return null;
  const error = notice.kind === 'error';
  return (
    <p className={error ? 'vote-notice vote-notice-error' : 'vote-notice vote-notice-info'} role={error ? 'alert' : 'status'}>
      <AlertIcon size={18} />
      <span>{notice.text}</span>
    </p>
  );
}
