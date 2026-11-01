// 위키 콘텐츠 접근 계층. 화면 컴포넌트는 이 모듈만 호출한다.
// 2단계: Supabase에서 읽는다. 공개 여부(승인된 것만)는 RLS가 보장하고, 여기서도 한 번 더 거른다.
import { db } from './supabase';

async function run(query) {
  const { data, error } = await query;
  if (error) throw new Error(`위키 데이터를 불러오지 못했어요. (${error.message})`);
  return data;
}

// 1:1 관계(matchup_docs)는 객체로 오지만, 혹시 배열로 와도 처리
const one = (v) => (Array.isArray(v) ? v[0] ?? null : v ?? null);
const day = (ts) => (ts ? String(ts).slice(0, 10) : null);

/** 이 챔피언을 이기는 카운터 목록 (관리자가 정한 순서) */
export async function getCountersFor(targetId) {
  const rows = await run(
    db()
      .from('counters')
      .select('id, target_champion, counter_champion, sort_order, matchup_docs(summary)')
      .eq('target_champion', targetId)
      .eq('status', 'approved')
      .order('sort_order', { ascending: true })
      .order('id', { ascending: true }),
  );
  return rows.map(({ matchup_docs, ...c }) => ({ ...c, summary: one(matchup_docs)?.summary ?? '' }));
}

/** 매치업 문서 (없으면 null) */
export async function getMatchup(targetId, counterId) {
  const row = await run(
    db()
      .from('counters')
      .select('id, target_champion, counter_champion, sort_order, matchup_docs(counter_id, summary, level_notes, lane_cautions, updated_at)')
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

/** 매치업의 공개된 빌드 목록 (따봉 점수 높은 순, 같으면 먼저 등록된 순) */
export async function getBuilds(counterRowId) {
  const rows = await run(
    db()
      .from('builds')
      .select(
        'id, counter_id, runes, summoner_spells, starting_items, core_items, skill_order, patch, up_count, down_count, created_at, ' +
          'author:profiles!builds_author_id_fkey(nickname, level, main_title)',
      )
      .eq('counter_id', counterRowId)
      .eq('status', 'approved')
      .order('created_at', { ascending: true }),
  );
  return rows
    .map(({ up_count, down_count, ...b }) => ({ ...b, up: up_count, down: down_count }))
    .sort((a, b) => b.up - b.down - (a.up - a.down));
}
