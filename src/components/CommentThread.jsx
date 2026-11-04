import { useRef, useState } from 'react';
import { Link, useLocation } from 'react-router-dom';
import { COMMENT_MAX, beginEdit } from '../api/board';
import { canEditNow, fmtTime, useNow } from '../lib/editWindow';
import { BoardByline, CharCount, ConfirmInline, HiddenBand, ReportForm } from './BoardParts';
import NoteForm from './NoteForm';
import { canVote, canWrite, isGuest } from '../lib/auth';
import { DEFAULT_MEDIA_RULES, finishMedia } from '../api/media';
import { MediaGallery, MediaPicker, mediaToItems, sameMedia } from './Media';
import GuestHint from './GuestHint';
import SectionHead from './SectionHead';
import { MessageIcon } from './Icons';

/**
 * 댓글 칸 (자유게시판 글, 매치업 문서 공통 — SPEC 6-5, 6-6, 고치기 시간 6-7).
 * ops: POST_COMMENT_OPS | DOC_COMMENT_OPS (kind, create(parentId, body), edit, remove, report, hide, restore)
 * parentId: 글 id 또는 카운터 id
 * open: 새 댓글을 달 수 있나 (글·문서가 보이는 상태), closedHint: 못 달 때 안내 (없으면 안내 없이 폼만 숨김)
 * live: 글·문서가 보이는 상태인가 (아니면 고치기·신고 숨김 — 숨긴 글·카운터는 운영자만 봄)
 * rules: 고치기 시간 { post, comment, grace }
 * num: 칸 제목 번호 (매치업 문서 4), 개수는 제목 옆 "N개" 알약
 * mediaRules: 사진 숫자 (ops.media일 때만 — 자유게시판 댓글. 문서 댓글은 사진 없음)
 */
export default function CommentThread({
  ops, parentId, comments, auth, open, closedHint, live, rules, mediaRules = DEFAULT_MEDIA_RULES, num, onDone, onReload,
}) {
  const { pathname } = useLocation();
  const now = useNow();
  const visibleCount = comments.filter((c) => c.status === 'visible').length;
  return (
    <section className="section comments" id="comments" aria-labelledby="comments-title">
      <SectionHead icon={MessageIcon} num={num} count={visibleCount} id="comments-title">댓글</SectionHead>
      {comments.length === 0 && <p className="hint">아직 댓글이 없습니다.</p>}
      {comments.length > 0 && (
        <ul className="comment-list" aria-label="댓글">
          {comments.map((c) => (
            <Comment
              key={c.id} comment={c} ops={ops} live={live} rules={rules} mediaRules={mediaRules} now={now} auth={auth}
              onDone={onDone} onReload={onReload}
            />
          ))}
        </ul>
      )}
      {!open && closedHint && <p className="hint">{closedHint}</p>}
      {open && (canWrite(auth) ? (
        <CommentForm ops={ops} parentId={parentId} auth={auth} mediaRules={mediaRules} onDone={onReload} />
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

function Comment({ comment: c, ops, live, rules, mediaRules, now, auth, onDone, onReload }) {
  const [mode, setMode] = useState(null); // 'edit' | 'delete' | 'report' | 'hide'
  const [body, setBody] = useState(c.body);
  const [media, setMedia] = useState(() => mediaToItems(c.media));
  const editRef = useRef(null);
  const [deadline, setDeadline] = useState(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const mine = auth.user?.id != null && c.author_id === auth.user.id;
  const visible = c.status === 'visible' && live;
  const signedIn = canVote(auth); // 신고는 닉네임이 있고 비회원이 아니어야
  const editable = mine && visible && canEditNow(ops.kind, c, rules, now);

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

  return (
    <li className={c.status === 'hidden' ? 'comment hidden-row' : 'comment'} id={`comment-${c.id}`}>
      {c.status === 'hidden' && (
        <HiddenBand row={c} what="댓글" onRestore={(note) => ops.restore(c.id, note)} onDone={onDone} />
      )}
      <BoardByline row={c} />
      {mode === 'edit' ? (
        <form className="comment-form media-drop-zone" ref={editRef} onSubmit={save} onKeyDown={(e) => e.key === 'Escape' && !busy && cancelEdit()}>
          <label htmlFor={`edit-comment-${c.id}`} className="sr-only">댓글 고치기</label>
          {/* eslint-disable-next-line jsx-a11y/no-autofocus -- [고치기]를 눌러 연 칸이라 바로 쓰게 한다 */}
          <textarea id={`edit-comment-${c.id}`} rows={3} value={body} onChange={(e) => setBody(e.target.value)} autoFocus />
          {ops.media && !isGuest(auth) && (
            <MediaPicker
              id={`edit-comment-media-${c.id}`} items={media} onChange={setMedia} max={mediaRules.commentMax} rules={mediaRules} disabled={busy}
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
          <MediaGallery media={c.media} label="댓글 사진" />
        </>
      )}
      {mode === null && (
        <div className="comment-actions">
          {editable && <button type="button" className="link-btn" onClick={startEdit} disabled={busy}>고치기</button>}
          {mine && <button type="button" className="link-btn" onClick={() => setMode('delete')}>지우기</button>}
          {signedIn && !mine && visible && !auth.isOperator && (
            <button type="button" className="link-btn" onClick={() => setMode('report')}>신고</button>
          )}
          {auth.isOperator && c.status === 'visible' && (
            <button type="button" className="link-btn op-link" onClick={() => setMode('hide')}>숨기기</button>
          )}
        </div>
      )}
      {mode === null && error && <p className="form-error" role="alert">{error}</p>}
      {mode === 'delete' && (
        <ConfirmInline
          question="댓글을 지우시겠습니까?" confirmLabel="지우기" onCancel={() => setMode(null)}
          onConfirm={async () => {
            await ops.remove(c.id);
            onReload();
          }}
        />
      )}
      {mode === 'report' && (
        <ReportForm
          id={`report-${ops.kind}-${c.id}`} what="댓글" photos={Boolean(ops.media)} onCancel={() => setMode(null)}
          onSubmit={async (reason, detail) => {
            await ops.report(c.id, reason, detail);
            setMode(null);
            onDone('신고했습니다. 운영자가 확인하겠습니다.');
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
            onDone('댓글을 숨겼습니다. 작성자에게 알림이 갔습니다.');
          }}
        />
      )}
    </li>
  );
}

/** 댓글 달기: 보내는 동안 버튼을 잠가 두 번 눌러도 한 번만 */
function CommentForm({ ops, parentId, auth, mediaRules, onDone }) {
  const [body, setBody] = useState('');
  const [media, setMedia] = useState([]);
  const formRef = useRef(null);
  const withMedia = ops.media && !isGuest(auth);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const n = body.trim().length;

  const submit = async (e) => {
    e.preventDefault();
    if (busy || (n === 0 && media.length === 0) || n > COMMENT_MAX) return;
    setBusy(true);
    setError(null);
    try {
      if (withMedia) await ops.create(parentId, body, await finishMedia(media, auth.user.id));
      else await ops.create(parentId, body);
      setBody('');
      setMedia([]);
      onDone();
    } catch (err) {
      setError(err.message);
    }
    setBusy(false);
  };

  return (
    <form className="comment-form media-drop-zone" onSubmit={submit} ref={formRef}>
      <label htmlFor="new-comment" className="sr-only">댓글 쓰기</label>
      <textarea id="new-comment" rows={3} placeholder="댓글을 남겨 주세요" value={body} onChange={(e) => setBody(e.target.value)} />
      {withMedia && (
        <MediaPicker
          id="new-comment-media" items={media} onChange={setMedia} max={mediaRules.commentMax} rules={mediaRules} disabled={busy} dropRef={formRef}
        />
      )}
      {ops.media && isGuest(auth) && <GuestHint what="사진을 붙일" />}
      <div className="comment-form-foot">
        <CharCount value={body} max={COMMENT_MAX} />
        <button type="submit" className="btn btn-small btn-primary" disabled={busy || (n === 0 && media.length === 0) || n > COMMENT_MAX}>
          {busy ? '올리는 중…' : '댓글 올리기'}
        </button>
      </div>
      {error && <p className="form-error" role="alert">{error}</p>}
    </form>
  );
}
