import { useRef, useState } from 'react';
import { Link, useLocation, useNavigate, useParams } from 'react-router-dom';
import {
  COMMENT_MAX, createComment, deleteMyComment, deleteMyPost, editComment, getPost, hideComment, hidePost,
  reportComment, reportPost, restoreComment, restorePost, votePost,
} from '../api/board';
import { useAuth } from '../lib/auth';
import { useAsync } from '../lib/useAsync';
import { fmtDateTime } from '../lib/format';
import { ErrorBox, Loading } from '../components/Status';
import NoteForm from '../components/NoteForm';
import { BoardByline, CharCount, ConfirmInline, ReportForm } from '../components/BoardParts';

/**
 * 글 보기 (/board/:id): 본문, 추천, 내 글이면 [고치기][지우기], 남의 글이면 [신고], 운영자는 [숨기기]/[다시 공개].
 * 댓글: 바로 올라감, 내 댓글은 고치기·지우기, 남의 댓글은 신고, 운영자는 숨기기.
 * 숨긴 글·댓글은 운영자에게만 보인다 (RLS). 삭제된 글은 "작성자가 삭제한 글"로 댓글과 함께 남는다.
 */
export default function BoardPost() {
  const { id } = useParams();
  const postId = Number(id);
  const auth = useAuth();
  const userId = auth.user?.id ?? null;
  const location = useLocation();
  const [done, setDone] = useState(location.state?.done ?? null);
  const { data, error, loading, retry } = useAsync(
    () => (auth.status === 'loading' ? new Promise(() => {}) : getPost(postId, userId)),
    [postId, userId, auth.status],
  );
  const finished = (message) => {
    setDone(message);
    retry();
  };
  // 댓글을 달거나 처리한 뒤 다시 불러오는 동안에는 보던 내용을 그대로 둔다 (화면이 "불러오는 중"으로 튀지 않게)
  const last = useRef(null);
  if (data) last.current = data;
  const post = data !== undefined ? data : (loading && last.current?.id === postId ? last.current : undefined);

  if (post === undefined && loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  if (!post) {
    return (
      <article>
        <h1 className="doc-title">글을 찾지 못했어요</h1>
        <p className="empty">지워졌거나 운영자가 숨긴 글이에요.</p>
        <p><Link to="/board">← 자유게시판</Link></p>
      </article>
    );
  }

  const mine = userId != null && post.author_id === userId;
  const deleted = post.deleted_at != null;
  return (
    <article className="board-post">
      <nav className="crumbs"><Link to="/board">← 자유게시판</Link></nav>
      {done && <p className="notice" role="status">{done}</p>}
      {post.status === 'hidden' && <HiddenBand row={post} what="글" onRestore={(note) => restorePost(post.id, note)} onDone={finished} />}

      {deleted ? (
        <>
          <h1 className="doc-title post-heading deleted">(삭제된 글)</h1>
          <p className="empty">작성자가 삭제한 글이에요. 댓글은 그대로 남아 있어요.</p>
        </>
      ) : (
        <>
          <h1 className="doc-title post-heading">{post.title}</h1>
          <BoardByline row={post} />
          <div className="post-body">{post.body}</div>
          <PostActions post={post} mine={mine} auth={auth} onDone={finished} />
        </>
      )}

      <Comments post={post} auth={auth} onDone={finished} onReload={retry} />
    </article>
  );
}

/** 운영자에게만: 숨김 띠 + [다시 공개] */
function HiddenBand({ row, what, onRestore, onDone }) {
  const [open, setOpen] = useState(false);
  return (
    <div className="op-band">
      <p>
        <strong>숨김</strong> · {fmtDateTime(row.hidden_at)} · 메모: {row.hidden_note}
        <br />
        <small>운영자에게만 보여요.</small>
      </p>
      {!open && (
        <button type="button" className="btn btn-small btn-op" onClick={() => setOpen(true)}>다시 공개</button>
      )}
      {open && (
        <NoteForm
          id={`restore-${what}-${row.id}`}
          label="다시 공개 메모 (필수, 작성자에게 보여요)"
          confirmLabel="다시 공개 확정"
          busyLabel="공개하는 중…"
          onCancel={() => setOpen(false)}
          onSubmit={async (note) => {
            await onRestore(note);
            onDone(`${what}을 다시 공개했어요.`);
          }}
        />
      )}
    </div>
  );
}

function PostActions({ post, mine, auth, onDone }) {
  const navigate = useNavigate();
  const [mode, setMode] = useState(null); // 'delete' | 'report' | 'hide'
  const [vote, setVote] = useState({ up: post.up_count, mine: post.voted, busy: false, error: null });
  const signedIn = auth.status === 'signedIn';
  const visible = post.status === 'visible';

  const toggleVote = async () => {
    setVote((v) => ({ ...v, busy: true, error: null }));
    try {
      const r = await votePost(post.id);
      setVote({ up: r.up, mine: r.mine, busy: false, error: null });
    } catch (e) {
      setVote((v) => ({ ...v, busy: false, error: e.message }));
    }
  };

  return (
    <div className="post-actions">
      <div className="row-actions">
        {signedIn && !mine && visible ? (
          <button
            type="button" className={vote.mine ? 'btn btn-small vote-btn on' : 'btn btn-small vote-btn'}
            aria-pressed={vote.mine} onClick={toggleVote} disabled={vote.busy}
          >
            👍 추천 {vote.up}
          </button>
        ) : (
          <span className="vote-count" aria-label={`추천 ${vote.up}`}>👍 {vote.up}</span>
        )}
        {mine && visible && <Link to={`/board/${post.id}/edit`} className="btn btn-small">고치기</Link>}
        {mine && <button type="button" className="btn btn-small" onClick={() => setMode('delete')}>지우기</button>}
        {signedIn && !mine && visible && !auth.isOperator && (
          <button type="button" className="btn btn-small" onClick={() => setMode('report')}>신고</button>
        )}
        {auth.isOperator && visible && (
          <button type="button" className="btn btn-small btn-op" onClick={() => setMode('hide')}>숨기기</button>
        )}
      </div>
      {vote.error && <p className="form-error" role="alert">{vote.error}</p>}
      {mode === 'delete' && (
        <ConfirmInline
          question={post.comment_count > 0 ? '글을 지울까요? 다른 사람 댓글은 남아요.' : '글을 지울까요?'}
          confirmLabel="지우기"
          onCancel={() => setMode(null)}
          onConfirm={async () => {
            const how = await deleteMyPost(post.id);
            if (how === 'soft') {
              onDone('글을 지웠어요. 다른 사람 댓글이 있어서 "삭제된 글"로 남아요.');
              setMode(null);
            } else {
              navigate('/board', { replace: true, state: { done: '글을 지웠어요.' } });
            }
          }}
        />
      )}
      {mode === 'report' && (
        <ReportForm
          id={`report-post-${post.id}`} what="글" onCancel={() => setMode(null)}
          onSubmit={async (reason, detail) => {
            await reportPost(post.id, reason, detail);
            setMode(null);
            onDone('신고했어요. 운영자가 확인할게요.');
          }}
        />
      )}
      {mode === 'hide' && (
        <NoteForm
          id={`hide-post-${post.id}`}
          label="숨기는 이유 (필수, 작성자에게 보여요)"
          confirmLabel="숨기기 확정"
          busyLabel="숨기는 중…"
          onCancel={() => setMode(null)}
          onSubmit={async (note) => {
            await hidePost(post.id, note);
            setMode(null);
            onDone('글을 숨겼어요. 작성자에게 알림이 갔어요.');
          }}
        />
      )}
    </div>
  );
}

function Comments({ post, auth, onDone, onReload }) {
  const { pathname } = useLocation();
  const deleted = post.deleted_at != null;
  return (
    <section className="section comments" aria-labelledby="comments-title">
      <h2 className="section-title" id="comments-title">댓글 {post.comments.filter((c) => c.status === 'visible').length}</h2>
      {post.comments.length === 0 && <p className="hint">아직 댓글이 없어요.</p>}
      {post.comments.length > 0 && (
        <ul className="comment-list" aria-label="댓글">
          {post.comments.map((c) => (
            <Comment key={c.id} comment={c} post={post} auth={auth} onDone={onDone} onReload={onReload} />
          ))}
        </ul>
      )}
      {deleted && <p className="hint">삭제된 글에는 댓글을 달 수 없어요.</p>}
      {!deleted && post.status === 'visible' && (auth.status === 'signedIn' ? (
        <CommentForm postId={post.id} onDone={onReload} />
      ) : (
        <p className="hint">
          <Link to="/login" state={{ from: pathname }}>로그인</Link>하면 댓글을 달 수 있어요.
        </p>
      ))}
    </section>
  );
}

function Comment({ comment: c, post, auth, onDone, onReload }) {
  const [mode, setMode] = useState(null); // 'edit' | 'delete' | 'report' | 'hide'
  const [body, setBody] = useState(c.body);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const mine = auth.user?.id != null && c.author_id === auth.user.id;
  const visible = c.status === 'visible' && post.status === 'visible';
  const signedIn = auth.status === 'signedIn';

  const save = async (e) => {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await editComment(c.id, body);
      setMode(null);
      onReload();
    } catch (err) {
      setError(err.message);
    }
    setBusy(false);
  };

  return (
    <li className={c.status === 'hidden' ? 'comment hidden-row' : 'comment'} id={`comment-${c.id}`}>
      {c.status === 'hidden' && (
        <HiddenBand row={c} what="댓글" onRestore={(note) => restoreComment(c.id, note)} onDone={onDone} />
      )}
      <BoardByline row={c} />
      {mode === 'edit' ? (
        <form className="comment-form" onSubmit={save}>
          <label htmlFor={`edit-comment-${c.id}`} className="sr-only">댓글 고치기</label>
          <textarea id={`edit-comment-${c.id}`} rows={3} value={body} onChange={(e) => setBody(e.target.value)} />
          <div className="comment-form-foot">
            <CharCount value={body} max={COMMENT_MAX} />
            <button type="submit" className="btn btn-small" disabled={busy || !body.trim() || body.trim().length > COMMENT_MAX}>
              {busy ? '저장하는 중…' : '저장'}
            </button>
            <button type="button" className="btn btn-small" disabled={busy} onClick={() => { setMode(null); setBody(c.body); }}>취소</button>
          </div>
          {error && <p className="form-error" role="alert">{error}</p>}
        </form>
      ) : (
        <div className="comment-body">{c.body}</div>
      )}
      {mode === null && (
        <div className="comment-actions">
          {mine && visible && <button type="button" className="link-btn" onClick={() => setMode('edit')}>고치기</button>}
          {mine && <button type="button" className="link-btn" onClick={() => setMode('delete')}>지우기</button>}
          {signedIn && !mine && visible && !auth.isOperator && (
            <button type="button" className="link-btn" onClick={() => setMode('report')}>신고</button>
          )}
          {auth.isOperator && c.status === 'visible' && (
            <button type="button" className="link-btn op-link" onClick={() => setMode('hide')}>숨기기</button>
          )}
        </div>
      )}
      {mode === 'delete' && (
        <ConfirmInline
          question="댓글을 지울까요?" confirmLabel="지우기" onCancel={() => setMode(null)}
          onConfirm={async () => {
            await deleteMyComment(c.id);
            onReload();
          }}
        />
      )}
      {mode === 'report' && (
        <ReportForm
          id={`report-comment-${c.id}`} what="댓글" onCancel={() => setMode(null)}
          onSubmit={async (reason, detail) => {
            await reportComment(c.id, reason, detail);
            setMode(null);
            onDone('신고했어요. 운영자가 확인할게요.');
          }}
        />
      )}
      {mode === 'hide' && (
        <NoteForm
          id={`hide-comment-${c.id}`}
          label="숨기는 이유 (필수, 작성자에게 보여요)"
          confirmLabel="숨기기 확정"
          busyLabel="숨기는 중…"
          onCancel={() => setMode(null)}
          onSubmit={async (note) => {
            await hideComment(c.id, note);
            setMode(null);
            onDone('댓글을 숨겼어요. 작성자에게 알림이 갔어요.');
          }}
        />
      )}
    </li>
  );
}

/** 댓글 달기: 보내는 동안 버튼을 잠가 두 번 눌러도 한 번만 */
function CommentForm({ postId, onDone }) {
  const [body, setBody] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const n = body.trim().length;

  const submit = async (e) => {
    e.preventDefault();
    if (busy || n === 0 || n > COMMENT_MAX) return;
    setBusy(true);
    setError(null);
    try {
      await createComment(postId, body);
      setBody('');
      onDone();
    } catch (err) {
      setError(err.message);
    }
    setBusy(false);
  };

  return (
    <form className="comment-form" onSubmit={submit}>
      <label htmlFor="new-comment" className="sr-only">댓글 쓰기</label>
      <textarea id="new-comment" rows={3} placeholder="댓글을 남겨 주세요" value={body} onChange={(e) => setBody(e.target.value)} />
      <div className="comment-form-foot">
        <CharCount value={body} max={COMMENT_MAX} />
        <button type="submit" className="btn btn-small btn-primary" disabled={busy || n === 0 || n > COMMENT_MAX}>
          {busy ? '올리는 중…' : '댓글 달기'}
        </button>
      </div>
      {error && <p className="form-error" role="alert">{error}</p>}
    </form>
  );
}
