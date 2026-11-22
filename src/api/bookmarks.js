// 빌드 저장(북마크) 접근 계층 (066, SPEC 6-82). 나만 보는 기능 — 다른 사람에게 숫자·목록을 보여 주는 곳은 없다.
// 066을 실행하기 전 DB(표·함수가 없음)에서도 화면이 죽지 않게: 저장 여부는 "저장 안 함"으로, 저장·목록만 "준비 중" 안내.
import { db } from './supabase';

export const BOOKMARK_LIMIT = 500;
export const BOOKMARKS_NOT_READY = '빌드 저장 기능을 준비하고 있습니다. 잠시 뒤 다시 시도해 주세요.';

/** 저장 표·함수가 아직 없다는 오류인가 (Postgres 42P01·42883, PostgREST PGRST202·PGRST205·PGRST200) */
export function isMissingBookmarks(error) {
  if (!error) return false;
  if (['42P01', '42883', 'PGRST202', 'PGRST205', 'PGRST200'].includes(error.code)) return true;
  return /build_bookmarks|save_build|my_saved_builds/.test(error.message ?? '') && /does not exist|schema cache|could not find/i.test(error.message ?? '');
}

function friendly(error, fallback) {
  if (isMissingBookmarks(error)) return new Error(BOOKMARKS_NOT_READY);
  const msg = error?.message ?? '';
  if (/[가-힣]/.test(msg)) return new Error(msg); // DB가 주는 한국어 사유 (로그인·닉네임·공개 빌드만·500개까지)
  if (/failed to fetch|networkerror|load failed|network request failed|fetch failed/i.test(msg)) {
    return new Error('인터넷 연결이 불안정합니다. 잠시 뒤 다시 눌러 주세요.');
  }
  if (error?.code === '42501' || /permission denied/i.test(msg)) return new Error('로그인한 뒤 저장할 수 있습니다.');
  return new Error(`${fallback} (${msg})`);
}

async function call(name, args, fallback) {
  const { data, error } = await db().rpc(name, args);
  if (error) throw friendly(error, fallback);
  return data;
}

/** 저장 → { saved: true, count } */
export const saveBuild = (buildId) => call('save_build', { p_build: buildId }, '저장하지 못했습니다.');
/** 저장 해제 → { saved: false, count } */
export const unsaveBuild = (buildId) => call('unsave_build', { p_build: buildId }, '저장을 해제하지 못했습니다.');

/**
 * 내가 저장한 빌드 (최근 저장순, 공개된 것만). { total, hidden, limit, items: [{ id, name, seq, max_skill, up, created_at, author_id, author, target, mine, saved_at }] }
 * author = { influencer } — BuildTitle·장인 빌드 뱃지가 읽는 모양(전체 빌드 목록 /builds와 같은 줄)
 */
export async function getMySavedBuilds() {
  const data = await call('my_saved_builds', {}, '저장한 빌드를 불러오지 못했습니다.');
  return {
    total: Number(data?.total ?? 0),
    hidden: Number(data?.hidden ?? 0),
    limit: Number(data?.limit ?? BOOKMARK_LIMIT),
    items: (data?.items ?? []).map((b) => ({ ...b, up: Number(b.up ?? 0), author: { influencer: b.influencer ?? null } })),
  };
}

/**
 * 이 상대법에서 내가 저장한 빌드 id들 (Set). 상대법 화면이 빌드와 함께 부른다.
 * 실패하거나 066 전이면 빈 Set — 저장 표시만 빠지고 빌드 화면은 그대로 열린다.
 */
export async function getSavedInCounter(userId, counterRowId) {
  if (!userId) return new Set();
  try {
    const { data, error } = await db().from('build_bookmarks').select('build_id, builds!inner(counter_id)')
      .eq('user_id', userId).eq('builds.counter_id', counterRowId);
    if (error) return new Set();
    return new Set((data ?? []).map((r) => r.build_id));
  } catch {
    return new Set();
  }
}
