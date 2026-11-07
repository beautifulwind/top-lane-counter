import { useRef, useState } from 'react';
import { Link, useLocation, useNavigate, useParams } from 'react-router-dom';
import {
  POST_COMMENT_OPS, deleteMyPost, getEditRules, getPost, hidePost, reportPost, restorePost, votePost,
} from '../api/board';
import { canModerate, canVote, isGuest, useAuth } from '../lib/auth';
import GuestHint from '../components/GuestHint';
import { useAsync } from '../lib/useAsync';
import { canEditNow, useNow } from '../lib/editWindow';
import { ErrorBox, Loading } from '../components/Status';
import NoteForm from '../components/NoteForm';
import { BoardByline, ConfirmInline, HiddenBand, ReportForm } from '../components/BoardParts';
import CommentThread from '../components/CommentThread';
import { MediaGallery, useMediaRules } from '../components/Media';
import { ThumbIcon } from '../components/Icons';

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
  const mediaRules = useMediaRules();
  const [done, setDone] = useState(location.state?.done ?? null);
  const { data, error, loading, retry } = useAsync(
    async () => {
      if (auth.status === 'loading') return new Promise(() => {});
      const [post, rules] = await Promise.all([getPost(postId, userId), getEditRules()]);
      return post && { ...post, rules };
    },
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
        <h1 className="doc-title">글을 찾지 못했습니다</h1>
        <p className="empty">지워졌거나 운영진이 숨긴 글입니다.</p>
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
        <div className="post-card">
          <h1 className="doc-title post-heading deleted">(삭제된 글)</h1>
          <p className="empty">작성자가 삭제한 글입니다. 댓글은 그대로 남아 있습니다.</p>
        </div>
      ) : (
        <div className="post-card">
          <header className="post-card-head">
            <h1 className="doc-title post-heading">{post.title}</h1>
            <BoardByline row={post} />
          </header>
          {post.body && <div className="post-body">{post.body}</div>}
          <MediaGallery media={post.media} />
          <PostActions post={post} mine={mine} auth={auth} onDone={finished} />
        </div>
      )}

      <CommentThread
        ops={POST_COMMENT_OPS} parentId={post.id} comments={post.comments} auth={auth} rules={post.rules} mediaRules={mediaRules}
        open={!deleted && post.status === 'visible'} live={post.status === 'visible'}
        closedHint={deleted ? '삭제된 글에는 댓글을 달 수 없습니다.' : null}
        onDone={finished} onReload={retry}
      />
    </article>
  );
}

function PostActions({ post, mine, auth, onDone }) {
  const navigate = useNavigate();
  const [mode, setMode] = useState(null); // 'delete' | 'report' | 'hide'
  const [vote, setVote] = useState({ up: post.up_count, mine: post.voted, busy: false, error: null });
  const signedIn = canVote(auth); // 추천·신고는 닉네임이 있고 비회원이 아니어야
  const visible = post.status === 'visible';
  const canHide = canModerate(auth, post.author_id, post.author);
  const now = useNow();

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
            type="button" className={vote.mine ? 'vote vote-btn on' : 'vote vote-btn'}
            aria-pressed={vote.mine} onClick={toggleVote} disabled={vote.busy}
          >
            <ThumbIcon /> 추천 {vote.up}
          </button>
        ) : (
          <span className="vote-count" aria-label={`추천 ${vote.up}`}><ThumbIcon /> {vote.up}</span>
        )}
        {mine && visible && canEditNow('post', post, post.rules, now) && (
          <Link to={`/board/${post.id}/edit`} className="btn btn-small">고치기</Link>
        )}
        {mine && <button type="button" className="btn btn-small" onClick={() => setMode('delete')}>지우기</button>}
        {signedIn && !mine && visible && !canHide && (
          <button type="button" className="btn btn-small" onClick={() => setMode('report')}>신고</button>
        )}
        {canHide && visible && (
          <button type="button" className="btn btn-small btn-op" onClick={() => setMode('hide')}>숨기기</button>
        )}
      </div>
      {vote.error && <p className="form-error" role="alert">{vote.error}</p>}
      {isGuest(auth) && !mine && visible && <GuestHint what="추천·신고를 할" />}
      {mode === 'delete' && (
        <ConfirmInline
          question={post.comment_count > 0 ? '글을 지우시겠습니까? 다른 사람 댓글은 남습니다.' : '글을 지우시겠습니까?'}
          confirmLabel="지우기"
          onCancel={() => setMode(null)}
          onConfirm={async () => {
            const how = await deleteMyPost(post.id);
            if (how === 'soft') {
              onDone('글을 지웠습니다. 다른 사람 댓글이 있어서 "삭제된 글"로 남습니다.');
              setMode(null);
            } else {
              navigate('/board', { replace: true, state: { done: '글을 지웠습니다.' } });
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
            onDone('신고했습니다. 운영진이 확인하겠습니다.');
          }}
        />
      )}
      {mode === 'hide' && (
        <NoteForm
          id={`hide-post-${post.id}`}
          label="숨기는 사유 (필수, 작성자에게 보입니다)"
          confirmLabel="숨기기 확정"
          busyLabel="숨기는 중…"
          onCancel={() => setMode(null)}
          onSubmit={async (note) => {
            await hidePost(post.id, note);
            setMode(null);
            onDone('글을 숨겼습니다. 작성자에게 알림이 갔습니다.');
          }}
        />
      )}
    </div>
  );
}
