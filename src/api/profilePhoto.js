// 장인 프로필 사진 (062, SPEC 6-71). 비공개 버킷 profile-photos — 장인의 "지금 사진"만 서명된 주소(1시간)로 본다.
// 경로 = 사용자id/임의이름.webp(또는 .jpg). 올릴 때마다 새 이름이라 바꾸면 주소가 바뀌어 옛 사진이 캐시로 보이지 않는다.
// 올리기는 Storage 규칙이, 정하기·지우기·신고·운영자 삭제는 DB 함수가 검사한다 (장인 본인만·내 폴더·하루 횟수 / 운영자만).
// 바꾸거나 지우면 옛 파일은 화면이 바로 지우고(본인 폴더·지금 사진이 아닌 것만 가능), 놓친 파일은 매일 media-cleanup이 지운다.
// 064: 장인 인증을 신청한 회원도 같은 버킷에 "신청 사진"을 올린다(심사 중에는 본인·운영자만 봄, 승인되면 장인 사진).
import { db } from './supabase';
import { prepareSquare } from '../lib/imageCompress';

export const PHOTO_BUCKET = 'profile-photos';
const SIGN_SECONDS = 60 * 60;

/** 신고 이유 (DB report_profile_photo와 같은 키) */
export const PHOTO_REPORT_REASONS = {
  obscene: '음란·잔혹한 사진',
  hate: '혐오·욕설',
  impersonation: '다른 사람 사진·사칭',
  spam: '광고·홍보',
  other: '기타',
};

function friendly(error, fallback) {
  const msg = error?.message ?? '';
  if (/[가-힣]/.test(msg)) return new Error(msg);
  if (/permission denied/i.test(msg)) return new Error('권한이 없습니다. (로그인이 필요하거나 운영자만 할 수 있는 작업입니다)');
  if (/could not find the function|PGRST202|42883/i.test(`${msg} ${error?.code ?? ''}`)) return new Error('프로필 사진 기능을 준비하고 있습니다. 잠시 뒤 다시 시도해 주세요.');
  return new Error(`${fallback} (${msg})`);
}

async function rpc(name, args, fallback) {
  const { data, error } = await db().rpc(name, args);
  if (error) throw friendly(error, fallback);
  return data;
}

const newName = () =>
  (globalThis.crypto?.randomUUID?.() ?? `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 12)}`);

/** 지금 올릴 수 없는 이유 (올릴 수 있으면 null) */
export async function photoUploadProblem() {
  const { data, error } = await db().rpc('profile_photo_upload_problem');
  if (error) return null; // 못 물어보면 올릴 때 Storage 규칙이 막는다
  return data ?? null;
}

/** 줄인 사진 하나 올리기 → 경로 */
async function upload(userId, { blob, mime, ext }) {
  const path = `${userId}/${newName()}.${ext}`;
  const { error } = await db().storage.from(PHOTO_BUCKET).upload(path, blob, { contentType: mime, upsert: false, cacheControl: '3600' });
  if (error) {
    if (/row-level security|unauthorized|403/i.test(error.message ?? '')) {
      throw new Error((await photoUploadProblem()) ?? '사진을 올릴 수 없습니다. 로그인 상태를 확인해 주세요.');
    }
    throw new Error(`사진을 올리지 못했습니다. (${error.message})`);
  }
  return path;
}

/** 내 폴더의 파일 지우기 (지금 사진이 아닌 것만 지워진다). 실패해도 매일 정리가 지우므로 오류를 내지 않는다 */
async function removeFile(path) {
  if (!path) return;
  try {
    await db().storage.from(PHOTO_BUCKET).remove([path]);
  } catch {
    /* 매일 정리(media-cleanup)가 지운다 */
  }
}

/**
 * 사진 바꾸기 (처음 올리기 포함): 고른 파일 → 가운데 정사각형 512px → 올리기 → 내 사진으로 정하기 → 옛 파일 지우기.
 * 돌려주는 값: 새 경로. 정하기가 실패하면 방금 올린 파일도 지운다
 */
export async function changeProfilePhoto(userId, file, oldPath = null) {
  const prepared = await prepareSquare(file);
  const path = await upload(userId, prepared);
  try {
    await rpc('set_profile_photo', { p_path: path }, '프로필 사진을 바꾸지 못했습니다.');
  } catch (e) {
    await removeFile(path);
    throw e;
  }
  if (oldPath && oldPath !== path) await removeFile(oldPath);
  return path;
}

/** 내 사진 지우기 (사진 없이 예전처럼 보인다) */
export async function deleteMyProfilePhoto(oldPath) {
  await rpc('clear_profile_photo', {}, '프로필 사진을 지우지 못했습니다.');
  await removeFile(oldPath);
}

// ---- 장인 인증 신청 사진 (064, SPEC 6-76) — 같은 버킷·같은 경로 모양. 심사 중에는 본인·운영자만 보고, 승인되면 장인 사진이 된다 ----

/**
 * 줄여 둔 사진(prepareSquare 결과) 올리기 → 내 심사 중 신청에 붙이기 → 옛 신청 사진 지우기. 돌려주는 값: 새 경로.
 * 붙이기가 실패하면 방금 올린 파일도 지운다. 신청서는 신청이 접수된 뒤 이걸 부른다(그 전에는 올릴 권한이 없다)
 */
export async function uploadApplicationPhoto(userId, prepared, oldPath = null) {
  const path = await upload(userId, prepared);
  try {
    await rpc('set_application_photo', { p_path: path }, '신청 사진을 정하지 못했습니다.');
  } catch (e) {
    await removeFile(path);
    throw e;
  }
  if (oldPath && oldPath !== path) await removeFile(oldPath);
  return path;
}

/** 심사 중 신청 사진 바꾸기 (처음 올리기 포함): 고른 파일 → 가운데 정사각형 512px → 올리기 → 신청에 붙이기 */
export async function changeApplicationPhoto(userId, file, oldPath = null) {
  return uploadApplicationPhoto(userId, await prepareSquare(file), oldPath);
}

/** 심사 중 신청 사진 지우기 (사진 없이 심사) */
export async function deleteApplicationPhoto(oldPath) {
  await rpc('clear_application_photo', {}, '신청 사진을 지우지 못했습니다.');
  await removeFile(oldPath);
}

/** 보기 주소 (서명된 주소, 1시간). 못 받으면 null — 화면은 사진 없이 보여 준다 */
export async function profilePhotoUrl(path) {
  if (!path) return null;
  try {
    const { data, error } = await db().storage.from(PHOTO_BUCKET).createSignedUrl(path, SIGN_SECONDS);
    return error ? null : (data?.signedUrl ?? null);
  } catch {
    return null;
  }
}

/** 장인 프로필 사진 신고 (정식 회원, 남의 사진). reason: PHOTO_REPORT_REASONS 키 */
export const reportProfilePhoto = (userId, reason, detail) =>
  rpc('report_profile_photo', { p_user: userId, p_reason: reason, p_detail: String(detail ?? '').trim() || null }, '신고하지 못했습니다.');

// ---- 운영자 (운영자 모드가 켜진 운영자만 — 감독관 불가) ----

/** 처리 전 신고 (사진별 묶음): { total, page, size, photos: [{ photo_path, current, owner, reports }] } */
export const getProfilePhotoReports = (page = 1, size = 20) =>
  rpc('admin_profile_photo_reports', { p_page: page, p_size: size }, '프로필 사진 신고를 불러오지 못했습니다.');

/** 처리 전 신고 수. 못 불러오면 0 (062 전 DB 포함) — 처리 대기 숫자에서만 빠진다 */
export async function getProfilePhotoReportCount() {
  try {
    const { data, error } = await db().rpc('admin_profile_photo_reports', { p_page: 1, p_size: 1 });
    return error ? 0 : Number(data?.total) || 0;
  } catch {
    return 0;
  }
}

/** 신고 기각 (사진은 그대로). 돌려주는 값: 닫은 신고 수 */
export const dismissProfilePhotoReports = (userId, note) =>
  rpc('dismiss_profile_photo_reports', { p_user: userId, p_note: String(note ?? '').trim() || null }, '신고를 기각하지 못했습니다.');

/** 그 회원의 지금 프로필 사진 경로 (profiles는 누구나 읽음). 062 전 DB거나 못 읽으면 null */
export async function getMemberPhotoPath(userId) {
  try {
    const { data, error } = await db().from('profiles').select('photo_path').eq('id', userId).maybeSingle();
    return error ? null : (data?.photo_path ?? null);
  } catch {
    return null;
  }
}

/** 운영자 삭제 (사유 필수 — 장인에게 알림이 간다) */
export const removeProfilePhoto = (userId, note) =>
  rpc('remove_profile_photo', { p_user: userId, p_note: note }, '프로필 사진을 삭제하지 못했습니다.');
