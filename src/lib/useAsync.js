import { useCallback, useEffect, useState } from 'react';

/**
 * 비동기 로더 결과를 { data, error, loading, retry }로 돌려준다.
 * - deps가 바뀐 첫 렌더부터 바로 loading이 된다 (이전 페이지 데이터를 잠깐이라도 보여주지 않음).
 * - retry()로 다시 불러올 수 있다.
 */
export function useAsync(loader, deps) {
  const key = JSON.stringify(deps);
  const [attempt, setAttempt] = useState(0);
  const [state, setState] = useState({ key: null, attempt: -1, data: undefined, error: null });

  useEffect(() => {
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
  }, [key, attempt]);

  const retry = useCallback(() => setAttempt((n) => n + 1), []);
  const current = state.key === key && state.attempt === attempt;
  return {
    data: current ? state.data : undefined,
    error: current ? state.error : null,
    loading: !current,
    retry,
  };
}
