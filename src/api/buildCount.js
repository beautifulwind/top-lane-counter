// 첫 화면에 보여 주는 "등록된 빌드 수" (SPEC 6-78).
// 공개된(승인된) 빌드만, 누가 보든 같은 숫자 — 내가 차단한 사람의 빌드도 센다.
// 비로그인(게스트)도 읽을 수 있다: builds는 anon에게 select가 열려 있고 RLS가 공개 빌드만 돌려준다 (DB 변경 없음).
// 줄을 받지 않고 개수만 센다(count + head). 10분 동안은 같은 결과를 재사용해 홈에 올 때마다 묻지 않는다.
import { db } from './supabase';

export const BUILD_COUNT_TTL_MS = 10 * 60 * 1000;

let cached = null; // { at, promise }

async function load() {
  const { count, error } = await db().from('builds').select('id', { count: 'exact', head: true }).eq('status', 'approved');
  if (error) throw new Error(`빌드 수를 불러오지 못했습니다. (${error.message})`);
  return count ?? 0;
}

/** 공개된 빌드 수. 실패하면 캐시하지 않고 오류를 던진다(화면은 조용히 숨긴다) */
export function getPublicBuildCount() {
  if (cached && Date.now() - cached.at < BUILD_COUNT_TTL_MS) return cached.promise;
  const entry = { at: Date.now(), promise: null };
  entry.promise = load().catch((e) => {
    if (cached === entry) cached = null;
    throw e;
  });
  cached = entry;
  return entry.promise;
}

/** 빌드를 등록·수정·숨김한 직후에 부른다 → 다음에 홈에서 새로 센다 */
export function invalidateBuildCount() {
  cached = null;
}
