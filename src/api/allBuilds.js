// 전체 빌드 목록 (SPEC 6-81, /builds — 첫 화면 "지금까지 N개의 빌드" 배지를 누르면).
// 공개 빌드만, 배지 개수와 같은 조건(publicBuilds). 줄마다 가벼운 칸만 받는다 — 홈 검색 목록(6-61)과 같은 방식으로 1000줄씩 이어 받는다.
// 비로그인·닉네임 없는 사람도 읽을 수 있다 (RLS가 공개 빌드만 돌려준다, DB 변경 없음).
// 추천 수가 자주 바뀌므로 캐시하지 않는다: 화면을 열 때마다 새로 받고, 받은 개수로 배지 숫자를 맞춘다.
import { publicBuilds, setPublicBuildCount } from './buildCount';
import { compareAllBuilds } from '../lib/wikiBuild';

export const PAGE_SIZE = 1000;
const COLS_BASE = 'id, name, seq, max_skill, up_count, created_at, author_id';
const COLS = `${COLS_BASE}, author:profiles!builds_author_id_fkey(influencer, nickname, photo_path)`;
const COLS_NO_PHOTO = `${COLS_BASE}, author:profiles!builds_author_id_fkey(influencer, nickname)`; // 062(프로필 사진) 실행 전 DB

/** [{ id, name, seq, max_skill, up, created_at, author_id, author: { influencer, nickname, photo_path } | null, target, mine }] — 정렬까지 끝난 것 */
export async function getAllPublicBuilds() {
  const rows = [];
  let cols = COLS;
  for (let from = 0; ; from += PAGE_SIZE) {
    let { data, error } = await publicBuilds(cols, 'target_champion, counter_champion, status')
      .order('id', { ascending: true }).range(from, from + PAGE_SIZE - 1);
    if (error && cols === COLS && from === 0) {
      cols = COLS_NO_PHOTO;
      ({ data, error } = await publicBuilds(cols, 'target_champion, counter_champion, status')
        .order('id', { ascending: true }).range(from, from + PAGE_SIZE - 1));
    }
    if (error) throw new Error(`빌드 목록을 불러오지 못했습니다. (${error.message})`);
    rows.push(...data);
    if (data.length < PAGE_SIZE) break;
  }
  const list = rows
    .filter((b) => b.counter?.status === 'approved')
    .map((b) => {
      const a = Array.isArray(b.author) ? b.author[0] : b.author;
      return {
        id: b.id, name: b.name ?? null, seq: b.seq ?? null, max_skill: b.max_skill ?? null, up: b.up_count ?? 0,
        created_at: b.created_at, author_id: b.author_id ?? null, author: a ? { influencer: a.influencer ?? null, nickname: a.nickname ?? null, photo_path: a.photo_path ?? null } : null,
        target: b.counter.target_champion, mine: b.counter.counter_champion,
      };
    })
    .sort(compareAllBuilds); // 기본(추천순). 「최신순」 칩은 화면에서 다시 나열한다 (칩을 바꿔도 다시 받지 않음)
  setPublicBuildCount(list.length); // 배지 = 목록 개수 (차단으로 숨긴 것도 포함한 전체)
  return list;
}
