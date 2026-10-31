// 위키 콘텐츠 접근 계층. 화면 컴포넌트는 이 모듈만 호출한다.
// 1단계: 가짜 데이터 / 2단계: 같은 함수 시그니처로 Supabase 조회로 교체.
import { builds, counters, matchupDocs } from '../data/mockContent';
import { getLatestVersion } from './ddragon';

const delay = (v) => new Promise((r) => setTimeout(() => r(v), 50));

/** 이 챔피언을 이기는 카운터 목록 (관리자가 정한 순서) */
export async function getCountersFor(targetId) {
  const list = counters
    .filter((c) => c.target_champion === targetId)
    .sort((a, b) => a.sort_order - b.sort_order)
    .map((c) => ({ ...c, summary: matchupDocs[c.id]?.summary ?? '' }));
  return delay(list);
}

/** 매치업 문서 (없으면 null) */
export async function getMatchup(targetId, counterId) {
  const counter = counters.find(
    (c) => c.target_champion === targetId && c.counter_champion === counterId,
  );
  if (!counter) return delay(null);
  const doc = matchupDocs[counter.id] ?? null;
  return delay({ counter, doc });
}

/** 매치업의 공개된 빌드 목록 (따봉 점수 높은 순) */
export async function getBuilds(counterRowId) {
  const latest = await getLatestVersion();
  const list = builds
    .filter((b) => b.counter_id === counterRowId)
    .map((b) => ({ ...b, patch: b.patch === 'LATEST' ? latest : b.patch }))
    .sort((a, b) => b.up - b.down - (a.up - a.down));
  return delay(list);
}
