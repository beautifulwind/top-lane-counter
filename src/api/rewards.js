// 경험치·레벨·칭호·비주류 픽 접근 계층 (SPEC 6장).
// 지급·회수·레벨 계산은 모두 DB(014: sync_rewards 트리거)가 한다. 화면은 읽기와 대표 칭호 고르기만.
import { db } from './supabase';

function friendly(error, fallback) {
  const msg = error?.message ?? '';
  if (/profiles_main_title_owned/.test(msg)) return new Error('가지고 있는 칭호만 대표 칭호로 고를 수 있어요.');
  if (/permission denied/i.test(msg)) return new Error('권한이 없어요.');
  if (/[가-힣]/.test(msg)) return new Error(msg);
  return new Error(`${fallback} (${msg})`);
}

async function run(query, fallback) {
  const { data, error } = await query;
  if (error) throw friendly(error, fallback);
  return data;
}

/**
 * 내 경험치·칭호: { xp, level, main_title (지금 값), events: 경험치 내역(최근 순), titles: 내 칭호들, levels: 레벨표, rules: { key: value } }
 * RLS: 경험치 내역은 내 것만 보인다.
 */
export async function getMyRewards(userId) {
  const [me, events, titles, levels, rules] = await Promise.all([
    run(db().from('profiles').select('xp, level, main_title').eq('id', userId).maybeSingle(), '경험치를 불러오지 못했어요.'),
    run(
      db().from('xp_events')
        .select('id, type, amount, change, reason, target_champion, counter_champion, created_at')
        .eq('user_id', userId).order('created_at', { ascending: false }).order('id', { ascending: false }),
      '경험치 내역을 불러오지 못했어요.',
    ),
    run(db().from('user_titles').select('title_key, earned_at').eq('user_id', userId), '칭호를 불러오지 못했어요.'),
    run(db().from('xp_levels').select('level, min_xp').order('level', { ascending: true }), '레벨표를 불러오지 못했어요.'),
    run(db().from('xp_rules').select('key, value'), '경험치 설정을 불러오지 못했어요.'),
  ]);
  return { ...me, events, titles, levels, rules: Object.fromEntries(rules.map((r) => [r.key, r.value])) };
}

/** 대표 칭호 고르기 (null = 없음). DB가 "내가 가진 칭호"인지 확인한다. 바뀐 프로필을 돌려준다 */
export function setMainTitle(userId, titleKey) {
  return run(
    db().from('profiles').update({ main_title: titleKey }).eq('id', userId).select('*').maybeSingle(),
    '대표 칭호를 바꾸지 못했어요.',
  );
}

// ---------------- 비주류 픽 목록 (운영자) ----------------

/** 비주류 픽 목록 (누구나 읽기) */
export function getOffmetaChampions() {
  return run(
    db().from('offmeta_champions').select('champion_id, created_at').order('created_at', { ascending: true }),
    '비주류 픽 목록을 불러오지 못했어요.',
  );
}

async function rpc(name, args, fallback) {
  const { data, error } = await db().rpc(name, args);
  if (error) throw friendly(error, fallback);
  return data;
}
/** 추가·빼기: 운영자만. 이미 승인된 기여의 비주류 여부는 바뀌지 않는다 (승인할 때 기록) */
export const addOffmeta = (championId) => rpc('add_offmeta', { p_champion: championId }, '추가하지 못했어요.');
export const removeOffmeta = (championId) => rpc('remove_offmeta', { p_champion: championId }, '빼지 못했어요.');
