import { useRef, useState } from 'react';
import { Link, useLocation, useNavigate, useParams } from 'react-router-dom';
import {
  POST_COMMENT_OPS, deleteMyPost, getEditRules, getPost, hidePost, reportPost, restorePost, staffDeletePost, votePost,
} from '../api/board';
import { canModerate, canVote, isGuest, useAuth } from '../lib/auth';
import GuestHint from '../components/GuestHint';
import { useAsync } from '../lib/useAsync';
import { canEditNow, useNow } from '../lib/editWindow';
import { ErrorBox, Loading } from '../components/Status';
import NoteForm from '../components/NoteForm';
import { BoardByline, ConfirmInline, HiddenBand, ReportForm } from '../components/BoardParts';
import CommentThread from '../components/CommentThread';
import MoreMenu from '../components/MoreMenu';
import { MediaGallery, useMediaRules } from '../components/Media';
import { ThumbIcon } from '../components/Icons';

/**
 * 글 보기 (/board/:id): 본문, 추천(밖에 둠), ⋮ 메뉴 — 내 글이면 [고치기][지우기], 남의 글이면 [신고],
 * 운영진은 [숨기기](보라)·[운영진 삭제](보라·빨강, 메모 필수). 숨긴 글의 [다시 공개]는 메뉴 밖 띠에.
 * 댓글: 바로 올라감, 댓글마다 ⋮ 메뉴 (CommentThread).
 * 숨긴 글·댓글은 운영자에게만 보인다 (RLS). 지운 글은 달린 댓글과 함께 아무에게도 안 보인다 (040).
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
        <p><Link to="/board">← 탑신병자 커뮤니티</Link></p>
      </article>
    );
  }

  const mine = userId != null && post.author_id === userId;
  return (
    <article className="board-post">
      <nav className="crumbs"><Link to="/board">← 탑신병자 커뮤니티</Link></nav>
      {done && <p className="notice" role="status">{done}</p>}
      {post.status === 'hidden' && <HiddenBand row={post} what="글" onRestore={(note) => restorePost(post.id, note)} onDone={finished} />}

      <div className="post-card">
        <header className="post-card-head">
          <h1 className="doc-title post-heading">{post.title}</h1>
          <BoardByline row={post} />
        </header>
        {post.body && <div className="post-body">{post.body}</div>}
        <MediaGallery media={post.media} />
        <PostActions post={post} mine={mine} auth={auth} onDone={finished} />
      </div>

      <CommentThread
        ops={POST_COMMENT_OPS} parentId={post.id} comments={post.comments} auth={auth} rules={post.rules} mediaRules={mediaRules}
        open={post.status === 'visible'} live={post.status === 'visible'}
        onDone={finished} onReload={retry}
      />
    </article>
  );
}

function PostActions({ post, mine, auth, onDone }) {
  const navigate = useNavigate();
  const [mode, setMode] = useState(null); // 'delete' | 'report' | 'hide' | 'staffDelete'
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
        <span className="row-push" />
        <MoreMenu
          label="글 더보기"
          items={[
            mine && visible && canEditNow('post', post, post.rules, now) && { label: '고치기', to: `/board/${post.id}/edit` },
            mine && { label: '지우기', danger: true, onSelect: () => setMode('delete') },
            signedIn && !mine && visible && !canHide && { label: '신고', onSelect: () => setMode('report') },
            canHide && visible && { label: '숨기기', op: true, onSelect: () => setMode('hide') },
            canHide && !mine && { label: '운영진 삭제', op: true, danger: true, onSelect: () => setMode('staffDelete') },
          ]}
        />
      </div>
      {vote.error && <p className="form-error" role="alert">{vote.error}</p>}
      {isGuest(auth) && !mine && visible && <GuestHint what="추천·신고를 할" />}
      {mode === 'delete' && (
        <ConfirmInline
          question={post.comment_count > 0 ? '글을 지우시겠습니까? 달린 댓글도 함께 보이지 않게 됩니다.' : '글을 지우시겠습니까?'}
          confirmLabel="지우기"
          onCancel={() => setMode(null)}
          onConfirm={async () => {
            await deleteMyPost(post.id);
            navigate('/board', { replace: true, state: { done: '글을 지웠습니다.' } });
          }}
        />
      )}
      {mode === 'staffDelete' && (
        <NoteForm
          id={`staff-delete-post-${post.id}`}
          label="삭제 사유 (필수, 작성자에게 보입니다)"
          confirmLabel="삭제 확정"
          busyLabel="삭제하는 중…"
          onCancel={() => setMode(null)}
          onSubmit={async (note) => {
            await staffDeletePost(post.id, note);
            navigate('/board', { replace: true, state: { done: '글을 삭제했습니다. 작성자에게 알림이 갔습니다.' } });
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
