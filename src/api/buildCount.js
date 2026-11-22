// 첫 화면에 보여 주는 "등록된 빌드 수" (SPEC 6-78).
// 공개된(승인된) 빌드만, 누가 보든 같은 숫자 — 내가 차단한 사람의 빌드도 센다.
// 비로그인(게스트)도 읽을 수 있다: builds는 anon에게 select가 열려 있고 RLS가 공개 빌드만 돌려준다 (DB 변경 없음).
// 줄을 받지 않고 개수만 센다(count + head). 10분 동안은 같은 결과를 재사용해 홈에 올 때마다 묻지 않는다.
// 6-81: 전체 빌드 목록(/builds)과 같은 조건(publicBuilds)으로 센다 — 공개 빌드 + 상대법도 공개 중.
//       (운영자·본인은 RLS상 숨긴 상대법 밑 빌드도 읽을 수 있어 6-78에서는 숫자가 조금 컸다) 목록을 받으면 그 개수로 맞춘다.
import { db } from './supabase';

export const BUILD_COUNT_TTL_MS = 10 * 60 * 1000;

/** 상대법(counters)을 붙이되, 상대법이 공개 중인 빌드만 남기는 연결 (inner) */
const counterJoin = (cols) => `counter:counters!builds_counter_id_fkey!inner(${cols})`;
export const COUNT_SELECT = `id, ${counterJoin('status')}`;

/**
 * 누구나 보는 "공개 빌드" 조회의 공통 조건 (배지 개수·전체 빌드 목록이 같이 쓴다 → 숫자가 어긋나지 않게).
 * cols: builds 칸, counterCols: 붙일 상대법 칸 (status 포함)
 */
export const publicBuilds = (cols, counterCols = 'status', opts = undefined) =>
  db().from('builds').select(`${cols}, ${counterJoin(counterCols)}`, opts).eq('status', 'approved').eq('counter.status', 'approved');

let cached = null; // { at, promise }

async function load() {
  const { count, error } = await publicBuilds('id', 'status', { count: 'exact', head: true });
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

/** 전체 빌드 목록을 받은 직후 그 개수로 배지 숫자를 맞춘다 (같은 조건이라 다시 묻지 않는다) */
export function setPublicBuildCount(n) {
  cached = { at: Date.now(), promise: Promise.resolve(n) };
}

/** 빌드를 등록·수정·숨김한 직후에 부른다 → 다음에 홈에서 새로 센다 */
export function invalidateBuildCount() {
  cached = null;
}
