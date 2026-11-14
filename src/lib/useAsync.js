import { useCallback, useEffect, useState } from 'react';

/**
 * 비동기 로더 결과를 { data, error, loading, retry }로 돌려준다.
 * - deps가 바뀐 첫 렌더부터 바로 loading이 된다 (이전 페이지 데이터를 잠깐이라도 보여주지 않음).
 * - retry()로 다시 불러올 수 있다.
 * - options.enabled가 false인 동안은 시작하지 않고 loading 그대로 둔다 (예: 로그인 확인이 끝날 때까지 기다렸다가 한 번만 불러오기).
 */
export function useAsync(loader, deps, { enabled = true } = {}) {
  const key = JSON.stringify(deps);
  const [attempt, setAttempt] = useState(0);
  const [state, setState] = useState({ key: null, attempt: -1, data: undefined, error: null });

  useEffect(() => {
    if (!enabled) return undefined;
    let alive = true;
    Promise.resolve()
      .then(loader)
      .then(
        (data) => alive && setState({ key, attempt, data, error: null }),
        (error) => alive && setState({ key, attempt, data: undefined, error: error ?? new Error('알 수 없는 오류') }),
      );
    return () => {
      alive = false;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key, attempt, enabled]);

  const retry = useCallback(() => setAttempt((n) => n + 1), []);
  const current = enabled && state.key === key && state.attempt === attempt;
  return {
    data: current ? state.data : undefined,
    error: current ? state.error : null,
    loading: !current,
    retry,
  };
}
