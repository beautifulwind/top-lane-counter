import { useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { BODY_MAX, TITLE_MAX, createPost, editPost, getPost } from '../api/board';
import { useAuth } from '../lib/auth';
import { useAsync } from '../lib/useAsync';
import { ErrorBox, Loading } from '../components/Status';
import { RequireLogin } from '../components/RequireOperator';
import { CharCount } from '../components/BoardParts';

/** 글쓰기 (/board/new) · 고치기 (/board/:id/edit). 로그인 + 닉네임 필요 (닉네임은 Layout이 먼저 보낸다) */
export default function BoardWrite() {
  return (
    <RequireLogin>
      <WriteOrEdit />
    </RequireLogin>
  );
}

function WriteOrEdit() {
  const { id } = useParams();
  const auth = useAuth();
  const { data, error, loading, retry } = useAsync(() => (id ? getPost(Number(id)) : null), [id]);
  if (!id) return <PostForm />;
  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  if (!data || data.author_id !== auth.user.id || data.deleted_at || data.status !== 'visible') {
    return (
      <article>
        <h1 className="doc-title">글 고치기</h1>
        <p className="empty">고칠 수 있는 내 글이 아니에요.</p>
        <p><Link to="/board">← 자유게시판</Link></p>
      </article>
    );
  }
  return <PostForm post={data} />;
}

function PostForm({ post = null }) {
  const navigate = useNavigate();
  const [title, setTitle] = useState(post?.title ?? '');
  const [body, setBody] = useState(post?.body ?? '');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const t = title.trim().length;
  const b = body.trim().length;
  const ready = t > 0 && t <= TITLE_MAX && b > 0 && b <= BODY_MAX;

  const submit = async (e) => {
    e.preventDefault();
    if (!ready || busy) return; // 보내는 동안은 잠가서 두 번 눌러도 한 번만
    setBusy(true);
    setError(null);
    try {
      if (post) {
        await editPost(post.id, title, body);
        navigate(`/board/${post.id}`, { replace: true, state: { done: '글을 고쳤어요.' } });
      } else {
        const newId = await createPost(title, body);
        navigate(`/board/${newId}`, { replace: true, state: { done: '글을 올렸어요.' } });
      }
    } catch (err) {
      setError(err.message);
      setBusy(false);
    }
  };

  return (
    <article>
      <nav className="crumbs"><Link to={post ? `/board/${post.id}` : '/board'}>← {post ? '글로 돌아가기' : '자유게시판'}</Link></nav>
      <h1 className="doc-title">{post ? '글 고치기' : '글쓰기'}</h1>
      <p className="lead">승인 없이 바로 올라가요. 욕설·도배·개인정보는 운영자가 숨길 수 있어요.</p>
      <form className="doc-form post-form" onSubmit={submit}>
        <label htmlFor="post-title">제목</label>
        <input id="post-title" value={title} onChange={(e) => setTitle(e.target.value)} autoComplete="off" />
        <CharCount value={title} max={TITLE_MAX} />
        <label htmlFor="post-body">본문</label>
        <textarea id="post-body" rows={12} value={body} onChange={(e) => setBody(e.target.value)} />
        <CharCount value={body} max={BODY_MAX} />
        {error && <p className="form-error" role="alert">{error}</p>}
        <div className="actions">
          <button type="submit" className="btn btn-primary" disabled={!ready || busy}>
            {busy ? '보내는 중…' : post ? '고친 내용 저장' : '올리기'}
          </button>
          <Link to={post ? `/board/${post.id}` : '/board'} className="btn">취소</Link>
        </div>
      </form>
    </article>
  );
}
