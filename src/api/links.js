// 장인 외부 링크 + 공개 프로필 (047, SPEC 6-34). 권한(장인·빌드 작성자·운영자)과 주소 규칙은 DB 함수가 검사한다.
import { db } from './supabase';

function friendly(error, fallback) {
  const msg = error?.message ?? '';
  const err = (text) => Object.assign(new Error(text), { code: error?.code ?? null });
  if (/permission denied/i.test(msg)) return err('권한이 없습니다. (로그인이 필요하거나 운영자만 할 수 있는 작업입니다)');
  if (/[가-힣]/.test(msg)) return err(msg);
  return err(`${fallback} (${msg})`);
}

async function rpc(name, args, fallback) {
  const { data, error } = await db().rpc(name, args);
  if (error) throw friendly(error, fallback);
  return data;
}

/**
 * 내 링크 (편집 화면): { influencer, max, profile: [{ id, url, host, sort, visible }],
 *   builds: [{ id, url, host, build_id, visible, counter_id, seq, name, target_champion, counter_champion }], domains: [{ domain, label }] }
 */
export const getMyLinks = () => rpc('my_links', {}, '내 링크를 불러오지 못했습니다.');

/** 프로필 링크를 이 목록(순서대로)으로 맞춘다. 빈 목록이면 모두 지운다. 돌려주는 값: 저장된 링크 목록 */
export const setProfileLinks = (urls) =>
  rpc('set_profile_links', { p_urls: urls.map((u) => String(u ?? '').trim()).filter(Boolean) }, '링크를 저장하지 못했습니다.');

/** 빌드 링크 1개 (빈 주소면 지움). 돌려주는 값: 링크 | null */
export const setBuildLink = (buildId, url) =>
  rpc('set_build_link', { p_build: buildId, p_url: String(url ?? '').trim() || null }, '빌드 링크를 저장하지 못했습니다.');

/** 공개 프로필 (인증된 장인만, 아니면 null): { id, nickname, influencer, links, build_count, builds } */
export async function getPublicProfile(id) {
  return rpc('public_profile', { p_user: String(id ?? '') }, '프로필을 불러오지 못했습니다.');
}

/** 상대법의 공개 빌드 링크 { 빌드 id: 링크 }. 못 읽으면 빈 값 — 링크만 빠진다 */
export async function getBuildLinks(counterRowId) {
  const { data, error } = await db().rpc('build_links', { p_counter: counterRowId });
  return error ? {} : (data ?? {});
}
