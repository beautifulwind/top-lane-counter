import { useEffect, useRef, useState } from 'react';
import { getBuildDifficulties } from '../api/builds';

/**
 * 빌드 id 목록의 난이도 별점을 받아 { id: 별점 }으로 돌려준다 (장인 프로필·/following·/lists — 목록 함수가 별점을 안 주는 화면, 6-104).
 * - 화면에 보이는 id만 한 번에 물어본다(200개씩 나눔). 쪽을 넘기거나 [더보기]로 id가 늘면 새 id만 물어보고, 이미 받은 id는 다시 묻지 않는다.
 * - 별점이 없는 빌드도 "받았음"으로 센다. 호출이 실패하면 그 id는 별점 없이 보여 주고(화면은 정상), 나중에 다시 보이면 한 번 더 묻는다.
 */
export function useBuildDifficulties(ids) {
  const [values, setValues] = useState({});
  const asked = useRef(new Set());
  const alive = useRef(true);
  const key = ids.join(',');

  useEffect(() => {
    alive.current = true;
    return () => { alive.current = false; };
  }, []);

  useEffect(() => {
    const missing = ids.filter((id) => !asked.current.has(id));
    if (missing.length === 0) return;
    missing.forEach((id) => asked.current.add(id));
    getBuildDifficulties(missing).then(({ values: got, failed }) => {
      failed.forEach((id) => asked.current.delete(id));
      if (alive.current && Object.keys(got).length > 0) setValues((prev) => ({ ...prev, ...got }));
    });
  }, [key]); // eslint-disable-line react-hooks/exhaustive-deps

  return values;
}
