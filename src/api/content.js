// 위키 콘텐츠 접근 계층. 화면 컴포넌트는 이 모듈만 호출한다.
// 2단계: Supabase에서 읽는다. 공개 여부(승인된 것만)는 RLS가 보장하고, 여기서도 한 번 더 거른다.
import { db } from './supabase';
import { compareBuilds } from '../lib/buildContent';

async function run(query) {
  const { data, error } = await query;
  if (error) throw new Error(`위키 데이터를 불러오지 못했습니다. (${error.message})`);
  return data;
}

// 1:1 관계(matchup_docs)는 객체로 오지만, 혹시 배열로 와도 처리
const one = (v) => (Array.isArray(v) ? v[0] ?? null : v ?? null);
const day = (ts) => (ts ? String(ts).slice(0, 10) : null);

// 맨 앞 빌드 (038, 장인 우선): 공개된 빌드 중 지금 인증된 장인이 처음 만든 빌드가 있으면 그중 추천 수 1등(compareBuilds 그대로),
// 없으면 기존대로 추천 → 점수 → 최신. 해제·탈퇴한 작성자는 author.influencer가 비어 장인 빌드로 치지 않는다
export function topBuild(builds) {
  const open = (builds ?? []).filter((b) => b.status === 'approved').map((b) => ({ ...b, up: b.up_count, down: b.down_count }));
  const inf = open.filter((b) => one(b.author)?.influencer);
  return (inf.length > 0 ? inf : open).sort(compareBuilds)[0] ?? null;
}

/** 이 챔피언을 이기는 카운터 목록 (운영자가 정한 순서) */
export async function getCountersFor(targetId) {
  const rows = await run(
    db()
      .from('counters')
      .select('id, target_champion, counter_champion, sort_order, matchup_docs(summary), builds(summary, status, up_count, down_count, created_at, author:profiles!builds_author_id_fkey(influencer))')
      .eq('target_champion', targetId)
      .eq('status', 'approved')
      .order('sort_order', { ascending: true })
      .order('id', { ascending: true }),
  );
  // 한 줄 요약 = 맨 앞 빌드(추천 → 점수 → 최신)의 요약 (038). 빌드에 요약이 없으면 예전 문서 요약
  return rows.map(({ matchup_docs, builds, ...c }) => {
    const top = topBuild(builds);
    // topInfluencer: 요약으로 올라온 빌드가 장인 빌드일 때만 (챔피언 화면의 "장인 빌드" 칩)
    return { ...c, summary: top?.summary || one(matchup_docs)?.summary || '', topInfluencer: !!top?.summary && !!one(top.author)?.influencer };
  });
}

/** 매치업 문서 (없으면 null) */
export async function getMatchup(targetId, counterId) {
  const row = await run(
    db()
      .from('counters')
      .select('id, target_champion, counter_champion, sort_order, matchup_docs(counter_id, summary, level_notes, lane_cautions, updated_at, revision_id)')
      .eq('target_champion', targetId)
      .eq('counter_champion', counterId)
      .eq('status', 'approved')
      .maybeSingle(),
  );
  if (!row) return null;
  const { matchup_docs, ...counter } = row;
  const doc = one(matchup_docs);
  return { counter, doc: doc && { ...doc, updated_at: day(doc.updated_at) } };
}

// 빌드는 src/api/builds.js
