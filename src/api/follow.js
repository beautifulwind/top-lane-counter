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

/**
 * 팔로워 목록 (063: 장인 본인·운영자만, 비회원 거부. 최근 순은 서버 안에서만, 20개씩).
 * 장인 본인이 볼 때는 장인과 차단 관계(어느 쪽이든)인 팔로워가 목록·total에서 빠진다. 운영자가 남의 목록을 보면 전부. 팔로우한 날은 주지 않는다.
 * { follower_count(= total), total, page, size, items: [{ id, nickname, influencer, nickname_state }] }
 */
export const getFollowers = (id, page = 1) =>
  rpc('influencer_followers', { p_user: id, p_page: page }, '팔로워 목록을 불러오지 못했습니다.');

/** 장인 찾기 (비로그인도): 인증된 장인 닉네임 부분 일치 1~20자, 20개씩. { total, page, size, items: [{ id, nickname, influencer, follower_count, build_count }] } */
export const searchInfluencers = (query, page = 1) =>
  rpc('search_influencers', { p_query: String(query ?? '').trim(), p_page: page }, '장인을 찾지 못했습니다.');

/**
 * 전체 장인 목록 (070 influencer_directory, 비로그인도, 1.3 패치 1-B1): 검색어(비면 전체, 20자까지)·정렬 'followers'|'recent'·쪽·크기.
 * { total, page, size, sort, items: [{ id, nickname, influencer, photo_path, follower_count, build_count, last_activity_at }] }
 */
export const getInfluencerDirectory = ({ query = '', sort = 'followers', page = 1, size = 10 } = {}) =>
  rpc('influencer_directory', { p_query: String(query ?? '').trim(), p_sort: sort, p_page: page, p_size: size }, '장인 목록을 불러오지 못했습니다.');

/** 팔로우 모아보기 (로그인한 사람만): 내가 팔로우한 장인들의 공개 빌드, 최근 수정순 20개씩. { total, page, size, items: [빌드 카드] } */
export const getFollowedBuilds = (page = 1) => rpc('followed_builds', { p_page: page }, '팔로우한 장인의 빌드를 불러오지 못했습니다.');

/** 내가 팔로우한 장인 (로그인한 정식 회원만 — 063: 비회원 거부, 최근 팔로우 순 20개씩, 날짜는 주지 않음). { total, page, size, items: [{ id, nickname, influencer, follower_count }] } */
export const getMyFollowing = (page = 1) => rpc('my_following', { p_page: page }, '팔로우한 장인 목록을 불러오지 못했습니다.');
