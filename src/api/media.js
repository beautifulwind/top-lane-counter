// 자유게시판 사진·GIF (SPEC 6-13, 023). 비공개 버킷 board-media — 보이는 글·댓글의 사진만 서명된 주소(하루짜리)로 본다.
// 올리기는 Storage 규칙이, 붙이기·바꾸기·빼기는 글·댓글 DB 함수가 검사한다 (회원만·내 폴더·개수·크기·하루 개수·전체 용량).
import { db } from './supabase';

export const MEDIA_BUCKET = 'board-media';
const SIGN_SECONDS = 24 * 60 * 60;

/** 숫자 (xp_rules media_*) — 화면 기본값은 DB 처음 값과 같다 */
export const DEFAULT_MEDIA_RULES = { postMax: 4, postGifMax: 1, commentMax: 1, photoMaxKb: 600, gifMaxKb: 3072 };
const RULE_KEYS = {
  media_post_max: 'postMax', media_post_gif_max: 'postGifMax', media_comment_max: 'commentMax',
  media_photo_max_kb: 'photoMaxKb', media_gif_max_kb: 'gifMaxKb',
};

export async function getMediaRules() {
  const { data, error } = await db().from('xp_rules').select('key, value').in('key', Object.keys(RULE_KEYS));
  if (error || !data) return DEFAULT_MEDIA_RULES; // 숫자를 못 읽어도 DB가 다시 검사하므로 기본값으로
  const rules = { ...DEFAULT_MEDIA_RULES };
  for (const r of data) rules[RULE_KEYS[r.key]] = r.value;
  return rules;
}

/** 지금 올릴 수 없는 이유 (올릴 수 있으면 null): 비회원, 하루 개수, 전체 용량 */
export async function mediaUploadProblem() {
  const { data, error } = await db().rpc('media_upload_problem');
  if (error) return null; // 못 물어보면 올릴 때 Storage 규칙이 막는다
  return data ?? null;
}

const newName = () =>
  (globalThis.crypto?.randomUUID?.() ?? `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 12)}`);

/** 줄인 사진 하나 올리기 → 경로 (사용자id/임의이름.확장자) */
export async function uploadMedia(userId, { blob, mime, ext }) {
  const path = `${userId}/${newName()}.${ext}`;
  const { error } = await db().storage.from(MEDIA_BUCKET).upload(path, blob, { contentType: mime, upsert: false, cacheControl: '86400' });
  if (error) {
    if (/row-level security|unauthorized|403/i.test(error.message ?? '')) {
      throw new Error((await mediaUploadProblem()) ?? '사진을 올릴 수 없습니다. 로그인 상태를 확인해 주세요.');
    }
    throw new Error(`사진을 올리지 못했습니다. (${error.message})`);
  }
  return path;
}

/**
 * 사진 목록들에 보기 주소(url)를 붙인다 (한 번에 서명). lists = [[{ path, mime, ... }], ...] → 같은 모양 + url
 * 서명에 실패한 사진은 url 없이 둔다 (화면은 "사진을 불러오지 못했습니다")
 */
export async function signMedia(lists) {
  const paths = [...new Set(lists.flat().map((m) => m.path))];
  if (paths.length === 0) return lists;
  const { data, error } = await db().storage.from(MEDIA_BUCKET).createSignedUrls(paths, SIGN_SECONDS);
  const urls = new Map((error ? [] : data ?? []).filter((d) => !d.error && d.signedUrl).map((d) => [d.path, d.signedUrl]));
  return lists.map((list) => list.map((m) => ({ ...m, url: urls.get(m.path) ?? null })));
}

/** 운영자: 사진 저장 공간 (023 media_usage) */
export async function getMediaUsage() {
  const { data, error } = await db().rpc('media_usage');
  if (error) throw new Error(/[가-힣]/.test(error.message) ? error.message : `사진 저장 공간을 불러오지 못했습니다. (${error.message})`);
  return data;
}

/**
 * 보낼 때: 새로 고른 사진을 올리고, 전체 경로 목록을 고른 순서대로 돌려준다.
 * 올린 사진은 그 항목에 경로를 적어 둔다 → 글 저장이 실패해 다시 눌러도 같은 사진을 또 올리지 않는다
 */
export async function finishMedia(items, userId) {
  const paths = [];
  for (const it of items) {
    if (!it.path) it.path = await uploadMedia(userId, it.prepared);
    paths.push(it.path);
  }
  return paths;
}
