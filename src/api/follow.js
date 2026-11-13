// 장인 팔로우 (050, SPEC 6-36). 권한(로그인·게스트 허용·장인만·자기 자신 안 됨·호출 횟수)은 DB 함수가 검사한다.
import { db } from './supabase';

/** DB 오류를 쉬운 말로. DB가 한국어로 이유를 주면 그대로 (예: "팔로우를 너무 자주 눌렀습니다. 1분 뒤에 다시 해 주세요.") */
function friendly(error, fallback) {
  const msg = error?.message ?? '';
  const err = (text) => Object.assign(new Error(text), { code: error?.code ?? null });
  if (/permission denied/i.test(msg)) return err('로그인한 뒤에 할 수 있습니다.');
  if (/[가-힣]/.test(msg)) return err(msg);
  if (/fetch|network/i.test(msg)) return err(`${fallback} 인터넷 연결을 확인한 뒤 다시 해 주세요.`);
  return err(`${fallback} 잠시 뒤 다시 해 주세요.`);
}

async function rpc(name, args, fallback) {
  const { data, error } = await db().rpc(name, args);
  if (error) throw friendly(error, fallback);
  return data;
}

/** 팔로우 (로그인한 사람, 게스트 포함). 돌려주는 값: { following: true, follower_count } */
export const followInfluencer = (id) => rpc('follow_influencer', { p_user: id }, '팔로우하지 못했습니다.');

/** 팔로우 취소. 돌려주는 값: { following: false, follower_count } */
export const unfollowInfluencer = (id) => rpc('unfollow_influencer', { p_user: id }, '팔로우를 취소하지 못했습니다.');

/**
 * [+] 버튼 상태를 한 번에: 장인 id 목록 → { id: 팔로우 중인가 }. 로그인 전이거나 목록이 비면 부르지 않는다.
 * 못 불러오면 빈 값 — 버튼은 "팔로우 안 함"으로 보이고, 누르면 DB가 그대로 처리한다(이미 팔로우 중이어도 오류 아님).
 */
export async function getFollowStatus(ids) {
  const list = [...new Set((ids ?? []).filter(Boolean))].slice(0, 100);
  if (list.length === 0) return {};
  try {
    const { data, error } = await db().rpc('follow_status', { p_users: list });
    return error ? {} : (data ?? {});
  } catch {
    return {};
  }
}

/**
 * 장인의 공개 빌드 (비로그인도, 최근 수정순, 20개씩). 장인이 아니면 null.
 * { influencer: { id, nickname, influencer }, follower_count, total, page, size, items: [빌드 카드] }
 */
export const getInfluencerBuilds = (id, page = 1) =>
  rpc('influencer_builds', { p_user: String(id ?? ''), p_page: page }, '빌드를 불러오지 못했습니다.');

/** 팔로워 목록 (로그인한 사람만, 최근 순, 20개씩): { follower_count, total, page, size, items: [{ id, nickname, influencer, nickname_state, followed_at }] } */
export const getFollowers = (id, page = 1) =>
  rpc('influencer_followers', { p_user: id, p_page: page }, '팔로워 목록을 불러오지 못했습니다.');

/** 장인 찾기 (비로그인도): 인증된 장인 닉네임 부분 일치 1~20자, 20개씩. { total, page, size, items: [{ id, nickname, influencer, follower_count, build_count }] } */
export const searchInfluencers = (query, page = 1) =>
  rpc('search_influencers', { p_query: String(query ?? '').trim(), p_page: page }, '장인을 찾지 못했습니다.');

/** 팔로우 모아보기 (로그인한 사람만): 내가 팔로우한 장인들의 공개 빌드, 최근 수정순 20개씩. { total, page, size, items: [빌드 카드] } */
export const getFollowedBuilds = (page = 1) => rpc('followed_builds', { p_page: page }, '팔로우한 장인의 빌드를 불러오지 못했습니다.');

/** 내가 팔로우한 장인 (로그인한 사람만, 최근 팔로우 순 20개씩). { total, page, size, items: [{ id, nickname, influencer, followed_at, follower_count }] } */
export const getMyFollowing = (page = 1) => rpc('my_following', { p_page: page }, '팔로우한 장인 목록을 불러오지 못했습니다.');
