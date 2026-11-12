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

// ---- 3b: 신고·삭제·허용 사이트 (047, 048) ----

/** 링크 신고 (정식 회원, 내 링크 빼고). reason: spam | obscene | malicious | not_own | other(내용 필수) */
export const reportLink = (linkId, reason, detail) =>
  rpc('report_link', { p_link: linkId, p_reason: reason, p_detail: String(detail ?? '').trim() || null }, '신고하지 못했습니다.');

/** 링크 삭제 (운영자는 전부, 감독관은 일반 장인의 링크만 — 048). 사유 필수, 올린 장인에게 알림이 간다 */
export const removeLink = (linkId, note) => rpc('remove_link', { p_link: linkId, p_note: note }, '링크를 삭제하지 못했습니다.');

/** 처리 전 링크 신고 (운영자만): { total, page, size, links: [{ id, url, host, build_id, visible, owner, build, reports }] } */
export const getLinkReports = (page = 1, size = 20) =>
  rpc('admin_link_reports', { p_page: page, p_size: size }, '링크 신고를 불러오지 못했습니다.');

/** 처리 전 링크 신고 수 (운영자만). 못 불러오면 0 — 처리 대기 숫자에서만 빠진다 */
export async function getLinkReportCount() {
  try {
    const { data, error } = await db().rpc('admin_link_reports', { p_page: 1, p_size: 1 });
    return error ? 0 : Number(data?.total) || 0;
  } catch {
    return 0;
  }
}

/** 링크 신고 기각 (운영자만, 메모 선택 — 링크는 그대로). 돌려주는 값: 기각한 신고 수 */
export const dismissLinkReports = (linkId, note) =>
  rpc('dismiss_link_reports', { p_link: linkId, p_note: String(note ?? '').trim() || null }, '신고를 기각하지 못했습니다.');

/** 허용 사이트 목록 (누구나 읽음): [{ domain, label }] */
export async function getLinkDomains() {
  const { data, error } = await db().from('link_domains').select('domain, label').order('domain');
  if (error) throw friendly(error, '허용 사이트를 불러오지 못했습니다.');
  return data ?? [];
}

/** 허용 사이트 더하기 (운영자만). 돌려주는 값: 정리된 도메인 */
export const addLinkDomain = (domain, label) =>
  rpc('admin_add_link_domain', { p_domain: domain, p_label: label }, '사이트를 더하지 못했습니다.');

/** 허용 사이트 빼기 (운영자만, 사유 필수). 그 사이트 링크는 지우지 않고 숨긴다. 돌려주는 값: 숨겨진 링크 수 */
export const removeLinkDomain = (domain, note) =>
  rpc('admin_remove_link_domain', { p_domain: domain, p_note: note }, '사이트를 빼지 못했습니다.');
