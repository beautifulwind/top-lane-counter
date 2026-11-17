// 홈 검색창이 쓰는 조합·빌드 목록 (SPEC 6-61). 키 입력마다 요청하지 않고 한 번 받아 메모리에 10분 둔다.
// 공개 여부는 RLS가 보장한다(승인된 상대법·공개 빌드만). 여기서도 한 번 더 거른다.
import { db } from './supabase';

/** 한 번에 받는 줄 수 (Supabase 기본 상한 1000에 맞춘다. 넘으면 range로 쪼개 이어 받는다) */
export const PAGE_SIZE = 1000;
export const INDEX_TTL_MS = 10 * 60 * 1000;

let cached = null; // { at, promise }

async function allRows(make) {
  const out = [];
  for (let from = 0; ; from += PAGE_SIZE) {
    const { data, error } = await make().range(from, from + PAGE_SIZE - 1);
    if (error) throw new Error(`검색 목록을 불러오지 못했습니다. (${error.message})`);
    out.push(...data);
    if (data.length < PAGE_SIZE) return out;
  }
}

async function load() {
  const [counters, builds] = await Promise.all([
    allRows(() => db().from('counters').select('id, target_champion, counter_champion, sort_order').eq('status', 'approved').order('id', { ascending: true })),
    allRows(() => db().from('builds')
      .select('id, counter_id, name, seq, summary, author:profiles!builds_author_id_fkey(influencer), counter:counters!builds_counter_id_fkey(target_champion, counter_champion, status)')
      .eq('status', 'approved').order('id', { ascending: true })),
  ]);
  return {
    counters: counters.map((c) => ({ id: c.id, target: c.target_champion, mine: c.counter_champion, order: c.sort_order ?? 0 })),
    builds: builds
      .filter((b) => b.counter?.status === 'approved')
      .map((b) => {
        const a = Array.isArray(b.author) ? b.author[0] : b.author;
        return { id: b.id, title: b.name ?? '', summary: b.summary ?? '', seq: b.seq ?? null, target: b.counter.target_champion, mine: b.counter.counter_champion, influencer: !!a?.influencer };
      }),
  };
}

/** 조합·빌드 목록 ({ counters, builds }). 10분 안에는 같은 약속을 돌려준다. 실패하면 캐시하지 않는다 */
export function getSearchIndex() {
  if (cached && Date.now() - cached.at < INDEX_TTL_MS) return cached.promise;
  const entry = { at: Date.now(), promise: null };
  entry.promise = load().catch((e) => {
    if (cached === entry) cached = null;
    throw e;
  });
  cached = entry;
  return entry.promise;
}

/** 상대법·빌드를 등록·수정·숨김·삭제한 직후에 부른다 → 다음 검색 때 새로 받는다 */
export function invalidateSearchIndex() {
  cached = null;
}
