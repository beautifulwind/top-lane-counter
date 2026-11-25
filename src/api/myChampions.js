// 내 챔피언 (080, SPEC 6-116). 나만 보는 기능 — 다른 사람의 등록 챔피언을 읽는 길은 없다(DB가 언제나 부른 사람 본인 것만).
// 080을 실행하기 전 DB(함수가 없음)에서도 화면이 죽지 않게: 함수가 없다는 오류는 missing 표시를 붙여 던지고, 탭은 「준비 중」 안내만 보인다.
import { db } from './supabase';

export const MY_CHAMPION_LIMIT = 10;
export const MY_CHAMPION_LIMIT_TEXT = '최대 10개까지 선택할 수 있습니다. 하나를 해제한 뒤 선택해 주세요.';
export const MY_CHAMPIONS_NOT_READY = '내 챔피언 기능을 준비하고 있습니다. 잠시 뒤 다시 시도해 주세요.';
/** 11개째 등록을 DB가 거절할 때의 오류 번호 (080 set_my_champion) */
export const LIMIT_CODE = 'TL413';

/** 080 표·함수가 아직 없다는 오류인가 (Postgres 42P01·42883, PostgREST PGRST202·PGRST205) */
export function isMissingMyChampions(error) {
  if (!error) return false;
  if (['42P01', '42883', 'PGRST202', 'PGRST205'].includes(error.code)) return true;
  return /set_my_champion|my_champions|my_champion_builds|user_champions/.test(error.message ?? '')
    && /does not exist|schema cache|could not find/i.test(error.message ?? '');
}

function friendly(error, fallback) {
  const err = (text, extra = {}) => Object.assign(new Error(text), { code: error?.code ?? null, ...extra });
  if (isMissingMyChampions(error)) return err(MY_CHAMPIONS_NOT_READY, { missing: true });
  if (error?.code === LIMIT_CODE) return err(MY_CHAMPION_LIMIT_TEXT, { limit: true });
  const msg = error?.message ?? '';
  if (/[가-힣]/.test(msg)) return err(msg); // DB가 주는 한국어 사유 (로그인·없는 챔피언·활동 제한)
  if (/failed to fetch|networkerror|load failed|network request failed|fetch failed/i.test(msg)) {
    return err('인터넷 연결이 불안정합니다. 잠시 뒤 다시 눌러 주세요.');
  }
  if (error?.code === '42501' || /permission denied/i.test(msg)) return err('로그인한 뒤 쓸 수 있습니다.');
  return err(`${fallback} (${msg})`);
}

async function call(name, args, fallback) {
  const { data, error } = await db().rpc(name, args);
  if (error) throw friendly(error, fallback);
  return data;
}

/** 내 등록 챔피언 (최근 등록순) → { limit, items: [챔피언 id] } */
export async function getMyChampions() {
  const data = await call('my_champions', {}, '내 챔피언을 불러오지 못했습니다.');
  return { limit: Number(data?.limit ?? MY_CHAMPION_LIMIT), items: Array.isArray(data?.items) ? data.items : [] };
}

/** 등록(selected = true)·해제(false) → { champion, selected, count, limit }. 11개째는 err.limit = true */
export const setMyChampion = (champion, selected) =>
  call('set_my_champion', { p_champion: champion, p_selected: !!selected }, selected ? '선택하지 못했습니다.' : '해제하지 못했습니다.');

/**
 * 내 챔피언들의 공개 빌드 (champion을 주면 그 챔피언 하나만). 20개씩, /builds 추천순(장인 → 추천 → 최신)은 DB가 정한다.
 * → { total, blocked, page, size, items: [{ id, name, seq, max_skill, up, created_at, author_id, author: { influencer, nickname, photo_path } | null, target, mine }] }
 * 별점(difficulty)은 없다 — 화면이 기존처럼 build_difficulties로 붙인다.
 */
export async function getMyChampionBuilds({ champion = null, page = 1 } = {}) {
  const data = await call('my_champion_builds', { p_champion: champion, p_page: page }, '내 챔피언의 빌드를 불러오지 못했습니다.');
  return {
    total: Number(data?.total ?? 0),
    blocked: Number(data?.blocked ?? 0),
    page: Number(data?.page ?? page),
    size: Number(data?.size ?? 20),
    items: (data?.items ?? []).map((b) => ({ ...b, up: Number(b.up ?? 0), author: b.author ?? null })),
  };
}
