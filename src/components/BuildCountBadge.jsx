import { useEffect, useState } from 'react';

export const COUNT_UP_MS = 1200;

// 같은 방문(페이지를 새로 열기 전)에서 한 번 올라갔으면 다시 이 화면에 와도 바로 최종 숫자 (SPEC 6-78)
let played = false;
export function resetCountUp() { played = false; }

const reducedMotion = () => {
  try { return !!window.matchMedia?.('(prefers-reduced-motion: reduce)').matches; } catch { return false; }
};
const easeOut = (t) => 1 - (1 - t) ** 3;
const fmt = (n) => n.toLocaleString('ko-KR');

/** 처음 보이는 숫자: 올라가는 효과를 쓸 거면 0, 아니면 최종 값 */
function useCountUp(target) {
  const [shown, setShown] = useState(() => (played || reducedMotion() ? target : 0));
  useEffect(() => {
    if (played || reducedMotion()) { setShown(target); return undefined; }
    let frame = 0;
    const start = performance.now();
    const tick = (now) => {
      const t = Math.min(1, (now - start) / COUNT_UP_MS);
      setShown(Math.round(target * easeOut(t)));
      if (t < 1) frame = requestAnimationFrame(tick);
      else played = true; // 끝까지 올라간 뒤에만 "이미 봤다" (개발 모드의 effect 두 번 실행·중간에 떠난 경우에도 다시 올라간다)
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [target]);
  return shown;
}

/**
 * 제목 옆 "지금까지 N개의 빌드" 알약 배지 (SPEC 6-78).
 * 눈에 보이는 부분은 aria-hidden(올라가는 중간 숫자를 읽지 않게), 스크린리더에는 최종 숫자가 든 문장 하나만 준다(aria-live 아님).
 */
export default function BuildCountBadge({ count }) {
  const shown = useCountUp(count);
  return (
    <p className="build-count">
      <span className="sr-only">{`지금까지 ${fmt(count)}개의 빌드가 등록되었습니다.`}</span>
      <span className="build-count-visual" aria-hidden="true">
        <span className="build-count-dot" />
        <span className="build-count-text">지금까지 <strong className="build-count-num">{fmt(shown)}</strong>개의 빌드</span>
      </span>
    </p>
  );
}
