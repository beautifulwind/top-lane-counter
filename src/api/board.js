// 자유게시판·문서 댓글 접근 계층 (SPEC 3장 /board, 6-5, 6-6). 화면 컴포넌트는 이 모듈만 호출한다.
// 쓰기·고치기·지우기·추천·신고·숨기기는 모두 DB 함수(015)로만 — 로그인·닉네임·도배 간격·길이·권한은 DB가 막는다.
import { db } from './supabase';
import { editRulesFrom } from '../lib/editWindow';
import { signMedia } from './media';

export const PAGE_SIZE = 20;
export const TITLE_MAX = 100;
export const BODY_MAX = 10000;
export const COMMENT_MAX = 1000;
// 신고 사유 (보이는 순서). DB 검사(021 board_report_check)와 같은 키. 예전 abuse 신고도 새 이름으로 보인다
export const REPORT_REASONS = {
  abuse: '욕설·인신공격',
  hate: '혐오·비하',
  obscene: '음란·잔혹한 사진',
  privacy: '신상 공개·개인정보',
  spam: '도배·광고',
  other: '기타',
};
export const REPORT_REASON_HINTS = {
  hate: '실존 인물·고인 비하, 성별·지역·장애 등을 이유로 한 비하 포함',
  privacy: '실명·연락처·사진·학교·직장 등 본인 동의 없는 정보',
  obscene: '노출·성적인 사진, 잔인하거나 끔찍한 사진·GIF',
};
/** 사진을 붙일 수 없는 곳(문서 댓글)의 신고에는 사진 사유를 빼고 보여 준다 */
export const PHOTO_REPORT_REASONS = ['obscene'];

const PERSON = 'nickname, role, level, main_title, is_guest';
const POST_FIELDS =
  'id, author_id, title, body, status, hidden_note, hidden_at, edited_at, edit_grace_until, deleted_at, comment_count, up_count, created_at';
const COMMENT_FIELDS = 'id, post_id, author_id, body, status, hidden_note, hidden_at, edited_at, edit_grace_until, created_at';
const DOC_COMMENT_FIELDS = 'id, counter_id, author_id, body, status, hidden_note, hidden_at, edited_at, edit_grace_until, created_at';
const COUNTER = 'counter:counters!doc_comments_counter_id_fkey(id, target_champion, counter_champion, status)';
// 숨긴 사람의 역할만 (감독관은 다른 감독관이 숨긴 것만 다시 공개할 수 있다, 030)
const POST_HIDER = 'hider:profiles!posts_hidden_by_fkey(role)';
const COMMENT_HIDER = 'hider:profiles!post_comments_hidden_by_fkey(role)';
const DOC_HIDER = 'hider:profiles!doc_comments_hidden_by_fkey(role)';
// 023: 붙은 사진 (보이는 글·댓글의 것만 RLS가 돌려준다)
const MEDIA = 'path, mime, size, position';
const POST_MEDIA = `media:board_attachments!board_attachments_post_id_fkey(${MEDIA})`;
const COMMENT_MEDIA = `media:board_attachments!board_attachments_comment_id_fkey(${MEDIA})`;
const byPosition = (list) => [...(list ?? [])].sort((a, b) => a.position - b.position);

function friendly(error, fallback) {
  const msg = error?.message ?? '';
  if (/permission denied/i.test(msg)) return new Error('권한이 없습니다. 로그인했는지 확인해 주세요.');
  if (/[가-힣]/.test(msg)) return new Error(msg);
  return new Error(`${fallback} (${msg})`);
}

async function run(query, fallback) {
  const { data, error } = await query;
  if (error) throw friendly(error, fallback);
  return data;
}

async function rpc(name, args, fallback) {
  const { data, error } = await db().rpc(name, args);
  if (error) throw friendly(error, fallback);
  return data;
}

/** 목록: { total, size, rows: [{ id, title, status, comment_count, up_count, created_at, edited_at, author }] } (최신순) */
export const getBoardPage = (q, page) =>
  rpc('board_page', { p_q: q || null, p_page: page, p_size: PAGE_SIZE }, '글 목록을 불러오지 못했습니다.');

/** 글 하나 + 댓글 (+ 내 추천 여부). 숨긴 글은 운영자에게만 보인다 → 없으면 null. 글·댓글의 media = [{ path, mime, size, url }] */
export async function getPost(id, userId = null) {
  const post = await run(
    db().from('posts').select(`${POST_FIELDS}, ${POST_HIDER}, author:profiles!posts_author_id_fkey(${PERSON}), ${POST_MEDIA}`).eq('id', id).maybeSingle(),
    '글을 불러오지 못했습니다.',
  );
  if (!post) return null;
  const [rawComments, vote] = await Promise.all([
    run(
      db().from('post_comments').select(`${COMMENT_FIELDS}, ${COMMENT_HIDER}, author:profiles!post_comments_author_id_fkey(${PERSON}), ${COMMENT_MEDIA}`)
        .eq('post_id', id).order('created_at', { ascending: true }).order('id', { ascending: true }),
      '댓글을 불러오지 못했습니다.',
    ),
    userId
      ? run(db().from('post_votes').select('post_id').eq('post_id', id).eq('user_id', userId).maybeSingle(), '추천을 불러오지 못했습니다.')
      : null,
  ]);
  const [postMedia, ...commentMedia] = await signMedia([byPosition(post.media), ...rawComments.map((c) => byPosition(c.media))]);
  const comments = rawComments.map((c, i) => ({ ...c, media: commentMedia[i] }));
  return { ...post, media: postMedia, comments, voted: Boolean(vote) };
}

/** 글쓰기 → 새 글 id. media = 올린 사진 경로 (보이는 순서) */
export const createPost = (title, body, media = []) =>
  rpc('create_post', { p_title: title, p_body: body, p_media: media }, '글을 올리지 못했습니다.');
/** media: 경로 목록이면 그 목록으로 바꾸고, null이면 사진은 그대로 */
export const editPost = (id, title, body, media = null) =>
  rpc('edit_post', { p_id: id, p_title: title, p_body: body, p_media: media }, '글을 고치지 못했습니다.');
/** 040부터 지운 글은 아무에게도 안 보인다 (달린 댓글도 함께). 1년 보관 뒤 정리 */
export const deleteMyPost = (id) => rpc('delete_my_post', { p_id: id }, '글을 지우지 못했습니다.');
/** 추천 누르기/취소 → { up, mine } */
export const votePost = (id) => rpc('vote_post', { p_id: id }, '추천하지 못했습니다.');

export const createComment = (postId, body, media = []) =>
  rpc('create_comment', { p_post: postId, p_body: body, p_media: media }, '댓글을 올리지 못했습니다.');
export const editComment = (id, body, media = null) =>
  rpc('edit_comment', { p_id: id, p_body: body, p_media: media }, '댓글을 고치지 못했습니다.');
export const deleteMyComment = (id) => rpc('delete_my_comment', { p_id: id }, '댓글을 지우지 못했습니다.');

export const reportPost = (id, reason, detail) =>
  rpc('report_post', { p_id: id, p_reason: reason, p_detail: detail || null }, '신고하지 못했습니다.');
export const reportComment = (id, reason, detail) =>
  rpc('report_comment', { p_id: id, p_reason: reason, p_detail: detail || null }, '신고하지 못했습니다.');

// ---------------- 운영자 ----------------
export const hidePost = (id, note) => rpc('hide_post', { p_id: id, p_note: note }, '숨기지 못했습니다.');
export const restorePost = (id, note) => rpc('restore_post', { p_id: id, p_note: note }, '다시 공개하지 못했습니다.');
export const hideComment = (id, note) => rpc('hide_comment', { p_id: id, p_note: note }, '숨기지 못했습니다.');
export const restoreComment = (id, note) => rpc('restore_comment', { p_id: id, p_note: note }, '다시 공개하지 못했습니다.');
// 운영진 삭제 (040): 메모 필수, 작성자에게 알림. 감독관은 일반 회원 것만 (DB가 검사)
export const staffDeletePost = (id, note) => rpc('staff_delete_post', { p_id: id, p_note: note }, '삭제하지 못했습니다.');
export const staffDeleteComment = (id, note) => rpc('staff_delete_comment', { p_id: id, p_note: note }, '삭제하지 못했습니다.');
export const dismissReports = ({ postId = null, commentId = null, docCommentId = null }, note) =>
  rpc('dismiss_reports', { p_post: postId, p_comment: commentId, p_note: note || null, p_doc_comment: docCommentId }, '기각하지 못했습니다.');

/**
 * 처리할 신고를 대상(글·댓글·문서 댓글)별로 묶는다 (오래된 신고 먼저).
 * [{ key, postId, commentId, docCommentId, post, comment, docComment, reports: [{ reason, detail, created_at, reporter }] }]
 */
export async function getOpenReports(forModerator = false) {
  // 감독관(030): 신고 표는 직접 못 읽는다. 처리할 수 있는 대상만, 신고자를 뺀 목록을 DB 함수로 받는다
  const rows = forModerator ? await rpc('open_reports_for_moderator', {}, '신고를 불러오지 못했습니다.') : await run(
    db().from('reports')
      .select(
        'id, post_id, comment_id, doc_comment_id, reason, detail, created_at, ' +
        `reporter:profiles!reports_reporter_id_fkey(${PERSON}), ` +
        `post:posts!reports_post_id_fkey(id, title, body, status, deleted_at, author_id, author:profiles!posts_author_id_fkey(${PERSON})), ` +
        `comment:post_comments!reports_comment_id_fkey(id, post_id, body, status, author_id, author:profiles!post_comments_author_id_fkey(${PERSON})), ` +
        `doc_comment:doc_comments!reports_doc_comment_id_fkey(id, counter_id, body, status, author_id, author:profiles!doc_comments_author_id_fkey(${PERSON}), ${COUNTER})`,
      )
      .eq('status', 'open').order('created_at', { ascending: true }),
    '신고를 불러오지 못했습니다.',
  );
  const groups = new Map();
  for (const r of rows) {
    const key = r.post_id ? `post-${r.post_id}` : r.comment_id ? `comment-${r.comment_id}` : `doc-${r.doc_comment_id}`;
    if (!groups.has(key)) {
      groups.set(key, {
        key, postId: r.post_id, commentId: r.comment_id, docCommentId: r.doc_comment_id,
        post: r.post, comment: r.comment, docComment: r.doc_comment, reports: [],
      });
    }
    groups.get(key).reports.push(r);
  }
  const list = [...groups.values()];
  const hides = await getHideCounts(list.map((g) => (g.post ?? g.comment ?? g.docComment)?.author_id));
  for (const g of list) {
    const author = (g.post ?? g.comment ?? g.docComment)?.author_id;
    g.hides = hides && author ? { days: hides.days, count: hides.counts[author] ?? 0 } : null;
  }
  return list;
}

/**
 * 운영자: 작성자별 최근 N일 숨김 횟수 (021 hide_counts, 다시 공개한 것은 빼고 작성자가 지운 것은 셈).
 * 실패하면 null — 신고 목록은 횟수 없이 그대로 보인다.
 */
async function getHideCounts(authorIds) {
  const ids = [...new Set(authorIds.filter(Boolean))];
  if (ids.length === 0) return null;
  const { data, error } = await db().rpc('hide_counts', { p_users: ids });
  return error || !data ? null : data;
}

/** 숨긴 글·댓글·문서 댓글 (최근에 숨긴 순) */
export async function getHiddenBoard() {
  const [posts, comments, docComments] = await Promise.all([
    run(
      db().from('posts').select(`${POST_FIELDS}, ${POST_HIDER}, author:profiles!posts_author_id_fkey(${PERSON})`)
        .eq('status', 'hidden').order('hidden_at', { ascending: false }),
      '숨긴 글을 불러오지 못했습니다.',
    ),
    run(
      db().from('post_comments').select(`${COMMENT_FIELDS}, ${COMMENT_HIDER}, author:profiles!post_comments_author_id_fkey(${PERSON})`)
        .eq('status', 'hidden').order('hidden_at', { ascending: false }),
      '숨긴 댓글을 불러오지 못했습니다.',
    ),
    run(
      db().from('doc_comments').select(`${DOC_COMMENT_FIELDS}, ${DOC_HIDER}, author:profiles!doc_comments_author_id_fkey(${PERSON}), ${COUNTER}`)
        .eq('status', 'hidden').order('hidden_at', { ascending: false }),
      '숨긴 문서 댓글을 불러오지 못했습니다.',
    ),
  ]);
  return { posts, comments, docComments };
}

// ---------------- 고치기 시간 (016) ----------------

/** 고치기 시간 규칙 { post, comment, grace } (분, xp_rules) */
export async function getEditRules() {
  const rows = await run(
    db().from('xp_rules').select('key, value').in('key', ['post_edit_minutes', 'comment_edit_minutes', 'edit_grace_minutes']),
    '설정을 불러오지 못했습니다.',
  );
  return editRulesFrom(rows);
}

/** 고치는 화면을 열 때: 마감 전이면 유예를 받는다. 돌려주는 값: 저장할 수 있는 마지막 시각. kind = 'post' | 'comment' | 'doc_comment' */
export const beginEdit = (kind, id) => rpc('begin_edit', { p_kind: kind, p_id: id }, '고칠 수 없습니다.');

// ---------------- 문서 댓글 (016) ----------------

/** 매치업 문서의 댓글 (오래된 순). 숨긴 것과 숨긴 카운터의 댓글은 운영자에게만 보인다 */
export function getDocComments(counterRowId) {
  return run(
    db().from('doc_comments').select(`${DOC_COMMENT_FIELDS}, ${DOC_HIDER}, author:profiles!doc_comments_author_id_fkey(${PERSON})`)
      .eq('counter_id', counterRowId).order('created_at', { ascending: true }).order('id', { ascending: true }),
    '댓글을 불러오지 못했습니다.',
  );
}
export const createDocComment = (counterRowId, body) =>
  rpc('create_doc_comment', { p_counter: counterRowId, p_body: body }, '댓글을 올리지 못했습니다.');
export const editDocComment = (id, body) => rpc('edit_doc_comment', { p_id: id, p_body: body }, '댓글을 고치지 못했습니다.');
export const deleteMyDocComment = (id) => rpc('delete_my_doc_comment', { p_id: id }, '댓글을 지우지 못했습니다.');
export const reportDocComment = (id, reason, detail) =>
  rpc('report_doc_comment', { p_id: id, p_reason: reason, p_detail: detail || null }, '신고하지 못했습니다.');
export const hideDocComment = (id, note) => rpc('hide_doc_comment', { p_id: id, p_note: note }, '숨기지 못했습니다.');
export const restoreDocComment = (id, note) => rpc('restore_doc_comment', { p_id: id, p_note: note }, '다시 공개하지 못했습니다.');
export const staffDeleteDocComment = (id, note) => rpc('staff_delete_doc_comment', { p_id: id, p_note: note }, '삭제하지 못했습니다.');

/** 댓글 화면(CommentThread)에 넘기는 처리 묶음 */
export const POST_COMMENT_OPS = {
  kind: 'comment', media: true, create: createComment, edit: editComment, remove: deleteMyComment,
  report: reportComment, hide: hideComment, restore: restoreComment, staffRemove: staffDeleteComment,
};
export const DOC_COMMENT_OPS = {
  kind: 'doc_comment', create: createDocComment, edit: editDocComment, remove: deleteMyDocComment,
  report: reportDocComment, hide: hideDocComment, restore: restoreDocComment, staffRemove: staffDeleteDocComment,
};
