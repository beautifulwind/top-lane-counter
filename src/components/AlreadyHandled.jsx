import { isAlreadyHandled } from '../api/proposals';

export const ALREADY_HANDLED = '이미 다른 분이 처리했습니다.';

/**
 * 다른 운영진이 먼저 처리해서 DB가 막았을 때(오류 코드 TL409): 오류 화면 대신 안내하고 목록을 새로고침한다.
 * guard(fn): 처리 함수를 감싼다 — 그 오류면 onHandled()를 부르고 오류는 던지지 않는다 (줄이 사라지므로 폼의 빨간 오류도 필요 없음).
 */
export function useAlreadyHandled(onHandled) {
  return (fn) => async (...args) => {
    try {
      return await fn(...args);
    } catch (err) {
      if (isAlreadyHandled(err)) {
        onHandled(`${ALREADY_HANDLED} 목록을 새로고침했습니다.`);
        return undefined;
      }
      throw err;
    }
  };
}
