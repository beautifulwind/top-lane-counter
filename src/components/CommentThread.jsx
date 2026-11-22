import { useRef, useState } from 'react';
import { Link, useLocation, useNavigate } from 'react-router-dom';
import { COMMENT_MAX, beginEdit } from '../api/board';
import { canEditNow, fmtTime, useNow } from '../lib/editWindow';
import { BoardByline, CharCount, ConfirmInline, HiddenBand, ReportForm } from './BoardParts';
import NoteForm from './NoteForm';
import MoreMenu from './MoreMenu';
import { canModerate, canVote, canWrite, isBlocked, isGuest } from '../lib/auth';
import { BLOCKED_COMMENT, blockMenuItem } from '../lib/blocks';
import { DEFAULT_MEDIA_RULES, finishMedia } from '../api/media';
import { MediaGallery, MediaPicker, mediaToItems, sameMedia } from './Media';
import GuestHint from './GuestHint';
import SectionHead from './SectionHead';
import { MessageIcon } from './Icons';

/** 부모 댓글이 지워졌거나(숨겨져) 안 보일 때 그 자리에 남기는 문구 (058) */
export const DELETED_COMMENT = '삭제된 댓글입니다.';

/**
 * 댓글을 답글과 함께 묶는다 (058): [{ comment | null(부모가 안 보임), parentId, replies: [] }] — 번호(=쓴 순서) 순.
 * 답글의 부모가 목록에 없으면(지움·숨김) 부모 자리는 null → 화면이 "삭제된 댓글입니다."
 */
export function threadComments(comments) {
  const byId = new Map(comments.map((c) => [c.id, c]));
  const replies = new Map();
  const tops = [];
  for (const c of comments) {
    if (c.parent_id == null) {
      tops.push(c);
    } else {
      if (!replies.has(c.parent_id)) replies.set(c.parent_id, []);
      replies.get(c.parent_id).push(c);
    }
  }
  const threads = tops.map((c) => ({ comment: c, parentId: c.id, replies: replies.get(c.id) ?? [] }));
  for (const [parentId, list] of replies) {
    if (!byId.has(parentId)) threads.push({ comment: null, parentId, replies: list });
  }
  return threads.sort((a, b) => a.parentId - b.parentId);
}

/**
 * 댓글 칸 (탑신병자 커뮤니티 글, 매치업 문서 공통 — SPEC 6-5, 6-6, 고치기 시간 6-7, 답글 6-53, 문서 댓글 답글 6-60).
 * ops: POST_COMMENT_OPS | DOC_COMMENT_OPS
 *   (kind, create(parentId, body, media?, replyTo?), edit, remove, report, hide, restore, staffRemove,
 *    replies = 답글(2단계) 사용, noGuest = 비회원은 댓글·답글 못 닮, noGuestReply = 비회원은 답글만 못 닮, media = 사진)
 * 댓글마다 ⋮ 메뉴 (040): 내 댓글 [고치기][지우기], 남의 댓글 [신고], 운영진 [숨기기]·[운영진 삭제](메모 필수).
 * 숨긴 댓글의 [다시 공개]는 메뉴 밖 띠에. 지운 댓글은 아무에게도 안 보인다 — 답글이 남은 부모 자리는 "삭제된 댓글입니다."
 * 답글: 최상위 댓글에만 [답글] (답글에는 없음 — DB도 3단계를 막는다).
 * parentId: 글 id / 카운터 id
 * open: 새 댓글을 달 수 있나 (글·문서가 보이는 상태), closedHint: 못 달 때 안내 (없으면 안내 없이 폼만 숨김)
 * live: 글·문서가 보이는 상태인가 (아니면 고치기·신고·답글 숨김 — 숨긴 것은 운영진만 봄)
 * rules: 고치기 시간 { post, comment, grace }
 * num: 칸 제목 번호 (없으면 번호 없이 — 매치업 문서 댓글은 6-83부터 번호 없음), 개수는 제목 옆 "N개" 알약. heading=false면 제목 없이
 * idPrefix: 한 화면에 댓글 칸이 둘일 때 입력칸·줄 id가 겹치지 않게 ('comment' = 예전 id 그대로)
 * mediaRules: 사진 숫자 (ops.media일 때만 — 탑신병자 커뮤니티 댓글)
 */
export default function CommentThread({
  ops, parentId, comments, auth, open, closedHint, live, rules, mediaRules = DEFAULT_MEDIA_RULES, num, onDone, onReload,
  heading = true, idPrefix = 'comment', sectionId = 'comments', label = '댓글',
}) {
  const { pathname } = useLocation();
  const now = useNow();
  // 061: 내가 차단한 사람의 댓글·답글은 빼고 그린다 (답글이 남은 부모 자리는 "차단한 사용자의 댓글입니다.")
  const blockedIds = new Set(comments.filter((c) => isBlocked(auth, c.author_id)).map((c) => c.id));
  const shownComments = blockedIds.size > 0 ? comments.filter((c) => !blockedIds.has(c.id)) : comments;
  const visibleCount = shownComments.filter((c) => c.status === 'visible').length;
  const threads = (ops.replies ? threadComments(shownComments) : shownComments.map((c) => ({ comment: c, parentId: c.id, replies: [] })))
    .map((t) => (t.comment ? t : { ...t, blocked: blockedIds.has(t.parentId) }));
  const guestBlocked = Boolean(ops.noGuest) && isGuest(auth);
  const writable = canWrite(auth) && !guestBlocked;
  // 059 문서 댓글: 비회원은 최상위 댓글만 — [답글]은 없고 목록 아래 안내 한 줄
  const guestNoReply = Boolean(ops.replies) && Boolean(ops.noGuestReply) && isGuest(auth);
  const shared = { ops, live, rules, mediaRules, now, auth, onDone, onReload, idPrefix };
  return (
    <section className="section comments" id={sectionId} aria-labelledby={heading ? `${sectionId}-title` : undefined} aria-label={heading ? undefined : label}>
      {heading && <SectionHead icon={MessageIcon} num={num} count={visibleCount} id={`${sectionId}-title`}>{label}</SectionHead>}
      {shownComments.length === 0 && <p className="hint">아직 댓글이 없습니다.</p>}
      {shownComments.length > 0 && (
        <ul className="comment-list" aria-label={label}>
          {threads.map((t) => (
            <Thread
              key={t.comment ? t.comment.id : `gone-${t.parentId}`} thread={t} target={parentId} {...shared}
              canReply={Boolean(ops.replies) && open && writable && !guestNoReply && live}
            />
          ))}
        </ul>
      )}
      {guestNoReply && open && live && shownComments.length > 0 && <GuestHint what="답글을 달" />}
      {!open && closedHint && <p className="hint">{closedHint}</p>}
      {open && (writable ? (
        <CommentForm ops={ops} parentId={parentId} auth={auth} mediaRules={mediaRules} onDone={onReload} idPrefix={idPrefix} />
      ) : guestBlocked ? (
        <GuestHint what="댓글을 달" />
      ) : auth.status === 'signedIn' ? (
        <p className="hint">
          <Link to="/welcome" state={{ from: pathname }}>닉네임을 정하면</Link> 댓글을 달 수 있습니다.
        </p>
      ) : (
        <p className="hint">
          <Link to="/login" state={{ from: pathname }}>로그인</Link>하면 댓글을 달 수 있습니다.
        </p>
      ))}
    </section>
  );
}

/** 댓글 하나 + 그 답글들 + [답글] 폼. 부모가 안 보이면(comment = null) "삭제된 댓글입니다." 자리만 (내가 차단한 사람의 댓글이면 "차단한 사용자의 댓글입니다.") */
function Thread({ thread, canReply, target, ...shared }) {
  const { ops, idPrefix } = shared;
  const [replying, setReplying] = useState(false);
  const c = thread.comment;
  const replyOpen = canReply && c && c.status === 'visible';
  const replyList = thread.replies.length > 0 && (
    <ul className="reply-list" aria-label="답글">
      {thread.replies.map((r) => <Comment key={r.id} comment={r} reply {...shared} />)}
    </ul>
  );
  if (!c) {
    return (
      <li className="comment gone-row" id={`${idPrefix}-gone-${thread.parentId}`}>
        <p className="hint deleted-comment">{thread.blocked ? BLOCKED_COMMENT : DELETED_COMMENT}</p>
        {replyList}
      </li>
    );
  }
  return (
    <Comment
      comment={c} {...shared}
      onReply={replyOpen ? () => setReplying((v) => !v) : null} replying={replying}
    >
      {replyList}
      {replying && replyOpen && (
        <CommentForm
          ops={ops} parentId={target} replyTo={c} auth={shared.auth} mediaRules={shared.mediaRules} idPrefix={idPrefix}
          onCancel={() => setReplying(false)}
          onDone={() => {
            setReplying(false);
            shared.onReload();
          }}
        />
      )}
    </Comment>
  );
}

function Comment({
  comment: c, ops, live, rules, mediaRules, now, auth, onDone, onReload, idPrefix, reply = false, onReply = null, replying = false, children = null,
}) {
  const [mode, setMode] = useState(null); // 'edit' | 'delete' | 'report' | 'hide' | 'staffDelete'
  const navigate = useNavigate();
  const location = useLocation();
  const [body, setBody] = useState(c.body);
  const [media, setMedia] = useState(() => mediaToItems(c.media));
  const editRef = useRef(null);
  const [deadline, setDeadline] = useState(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const mine = auth.user?.id != null && c.author_id === auth.user.id;
  const canHide = canModerate(auth, c.author_id, c.author);
  const visible = c.status === 'visible' && live;
  const signedIn = canVote(auth); // 신고는 닉네임이 있고 비회원이 아니어야
  const editable = mine && visible && canEditNow(ops.kind, c, rules, now);
  const what = reply ? '답글' : '댓글';

  // [고치기]: DB에 "지금 연다"를 알려 유예를 받고 저장 마감을 받아 온다
  const startEdit = async () => {
    setBusy(true);
    setError(null);
    try {
      const until = await beginEdit(ops.kind, c.id);
      setDeadline(until);
      setBody(c.body);
      setMedia(mediaToItems(c.media));
      setMode('edit');
    } catch (err) {
      setError(err.message);
    }
    setBusy(false);
  };

  const cancelEdit = () => {
    setMode(null);
    setBody(c.body);
    setMedia(mediaToItems(c.media));
    setError(null);
  };

  const save = async (e) => {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      if (ops.media) {
        const paths = await finishMedia(media, auth.user.id);
        await ops.edit(c.id, body, sameMedia(media, c.media) ? null : paths);
      } else {
        await ops.edit(c.id, body);
      }
      setMode(null);
      onReload();
    } catch (err) {
      setError(err.message); // 쓴 내용은 입력칸에 그대로
    }
    setBusy(false);
  };

  const rowClass = ['comment', reply && 'reply', c.status === 'hidden' && 'hidden-row'].filter(Boolean).join(' ');
  return (
    <li className={rowClass} id={`${idPrefix}-${c.id}`}>
      {c.status === 'hidden' && (
        <HiddenBand row={c} what={what} onRestore={(note) => ops.restore(c.id, note)} onDone={onDone} />
      )}
      <div className="comment-head">
        <BoardByline row={c} />
        {mode === null && (
          <MoreMenu
            label={`${what} 더보기`}
            items={[
              editable && { label: '고치기', onSelect: startEdit, disabled: busy },
              mine && { label: '지우기', danger: true, onSelect: () => setMode('delete') },
              signedIn && !mine && visible && !canHide && { label: '신고', onSelect: () => setMode('report') },
              isGuest(auth) && !mine && visible && {
                label: '신고', disabled: true, hint: '비회원은 신고할 수 없습니다. 마이페이지에서 구글·카카오를 연결해 주세요.',
              },
              canHide && c.status === 'visible' && { label: '숨기기', op: true, onSelect: () => setMode('hide') },
              canHide && !mine && ops.staffRemove && { label: '운영진 삭제', op: true, danger: true, onSelect: () => setMode('staffDelete') },
              // 061: 남의 댓글·답글 [이 사용자 차단] — 로그인 전이면 로그인으로
              blockMenuItem(auth, c.author_id, c.author, {
                onLogin: () => navigate('/login', { state: { from: `${location.pathname}${location.search}` } }),
                onDone,
              }),
            ]}
          />
        )}
      </div>
      {mode === 'edit' ? (
        <form className="comment-form media-drop-zone" ref={editRef} onSubmit={save} onKeyDown={(e) => e.key === 'Escape' && !busy && cancelEdit()}>
          <label htmlFor={`edit-${idPrefix}-${c.id}`} className="sr-only">{what} 고치기</label>
          {/* eslint-disable-next-line jsx-a11y/no-autofocus -- [고치기]를 눌러 연 칸이라 바로 쓰게 한다 */}
          <textarea id={`edit-${idPrefix}-${c.id}`} rows={3} value={body} onChange={(e) => setBody(e.target.value)} autoFocus />
          {ops.media && !isGuest(auth) && (
            <MediaPicker
              id={`edit-${idPrefix}-media-${c.id}`} items={media} onChange={setMedia} max={mediaRules.commentMax} rules={mediaRules} disabled={busy}
              dropRef={editRef}
            />
          )}
          {deadline && <small className="hint edit-deadline">{fmtTime(deadline)}까지 저장할 수 있습니다.</small>}
          <div className="comment-form-foot">
            <CharCount value={body} max={COMMENT_MAX} />
            <button type="submit" className="btn btn-small" disabled={busy || (!body.trim() && media.length === 0) || body.trim().length > COMMENT_MAX}>
              {busy ? '저장하는 중…' : '고친 내용 저장'}
            </button>
            <button type="button" className="btn btn-small" disabled={busy} onClick={cancelEdit}>취소</button>
          </div>
          {error && <p className="form-error" role="alert">{error}</p>}
        </form>
      ) : (
        <>
          {c.body && <div className="comment-body">{c.body}</div>}
          <MediaGallery media={c.media} label={`${what} 사진`} />
        </>
      )}
      {onReply && mode === null && (
        <div className="comment-actions">
          <button type="button" className="link-btn reply-btn" aria-expanded={replying} onClick={onReply}>
            {replying ? '답글 닫기' : '답글'}
          </button>
        </div>
      )}
      {mode === null && error && <p className="form-error" role="alert">{error}</p>}
      {mode === 'delete' && (
        <ConfirmInline
          question={`${what}을 지우시겠습니까?`} confirmLabel="지우기" onCancel={() => setMode(null)}
          onConfirm={async () => {
            await ops.remove(c.id);
            onReload();
          }}
        />
      )}
      {mode === 'report' && (
        <ReportForm
          id={`report-${ops.kind}-${c.id}`} what={what} photos={Boolean(ops.media)} onCancel={() => setMode(null)}
          onSubmit={async (reason, detail) => {
            await ops.report(c.id, reason, detail);
            setMode(null);
            onDone('신고했습니다. 운영진이 확인하겠습니다.');
          }}
        />
      )}
      {mode === 'staffDelete' && (
        <NoteForm
          id={`staff-delete-${ops.kind}-${c.id}`}
          label="삭제 사유 (필수, 작성자에게 보입니다)"
          confirmLabel="삭제 확정"
          busyLabel="삭제하는 중…"
          onCancel={() => setMode(null)}
          onSubmit={async (note) => {
            await ops.staffRemove(c.id, note);
            setMode(null);
            onDone(`${what}을 삭제했습니다. 작성자에게 알림이 갔습니다.`);
          }}
        />
      )}
      {mode === 'hide' && (
        <NoteForm
          id={`hide-${ops.kind}-${c.id}`}
          label="숨기는 사유 (필수, 작성자에게 보입니다)"
          confirmLabel="숨기기 확정"
          busyLabel="숨기는 중…"
          onCancel={() => setMode(null)}
          onSubmit={async (note) => {
            await ops.hide(c.id, note);
            setMode(null);
            onDone(`${what}을 숨겼습니다. 작성자에게 알림이 갔습니다.`);
          }}
        />
      )}
      {children}
    </li>
  );
}

/**
 * 댓글 달기: 보내는 동안 버튼을 잠가 두 번 눌러도 한 번만.
 * replyTo: 답글이면 그 부모 댓글 (058) — 칸 이름 "답글 쓰기", [취소]·Esc로 닫힘
 */
function CommentForm({ ops, parentId, replyTo = null, auth, mediaRules, onDone, onCancel = null, idPrefix }) {
  const [body, setBody] = useState('');
  const [media, setMedia] = useState([]);
  const formRef = useRef(null);
  const withMedia = ops.media && !isGuest(auth);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const n = body.trim().length;
  const what = replyTo ? '답글' : '댓글';
  const fieldId = replyTo ? `reply-${idPrefix}-${replyTo.id}` : `new-${idPrefix}`;
  const replyId = replyTo?.id ?? null;

  const submit = async (e) => {
    e.preventDefault();
    if (busy || (n === 0 && media.length === 0) || n > COMMENT_MAX) return;
    setBusy(true);
    setError(null);
    try {
      if (withMedia) await ops.create(parentId, body, await finishMedia(media, auth.user.id), replyId);
      else await ops.create(parentId, body, replyId);
      setBody('');
      setMedia([]);
      onDone();
    } catch (err) {
      setError(err.message);
    }
    setBusy(false);
  };

  return (
    <form
      className={replyTo ? 'comment-form reply-form media-drop-zone' : 'comment-form media-drop-zone'} onSubmit={submit} ref={formRef}
      onKeyDown={onCancel ? (e) => e.key === 'Escape' && !busy && onCancel() : undefined}
    >
      <label htmlFor={fieldId} className="sr-only">{what} 쓰기</label>
      <textarea
        id={fieldId} rows={replyTo ? 2 : 3} placeholder={replyTo ? '답글을 남겨 주세요' : '댓글을 남겨 주세요'} value={body}
        onChange={(e) => setBody(e.target.value)}
        // eslint-disable-next-line jsx-a11y/no-autofocus -- [답글]을 눌러 연 칸이라 바로 쓰게 한다
        autoFocus={Boolean(replyTo)}
      />
      {withMedia && (
        <MediaPicker
          id={`${fieldId}-media`} items={media} onChange={setMedia} max={mediaRules.commentMax} rules={mediaRules} disabled={busy} dropRef={formRef}
        />
      )}
      <div className="comment-form-foot">
        <CharCount value={body} max={COMMENT_MAX} />
        <button type="submit" className="btn btn-small btn-primary" disabled={busy || (n === 0 && media.length === 0) || n > COMMENT_MAX}>
          {busy ? '올리는 중…' : `${what} 올리기`}
        </button>
        {onCancel && <button type="button" className="btn btn-small" disabled={busy} onClick={onCancel}>취소</button>}
      </div>
      {error && <p className="form-error" role="alert">{error}</p>}
    </form>
  );
}
