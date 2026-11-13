import { useRef, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { BODY_MAX, TITLE_MAX, beginEdit, createNotice, createPost, editPost, getPost } from '../api/board';
import { fmtTime } from '../lib/editWindow';
import { isGuest, useAuth } from '../lib/auth';
import { finishMedia } from '../api/media';
import { useAsync } from '../lib/useAsync';
import { ErrorBox, Loading } from '../components/Status';
import { RequireLogin } from '../components/RequireOperator';
import { CharCount } from '../components/BoardParts';
import GuestHint from '../components/GuestHint';
import { MediaGallery, MediaPicker, mediaToItems, sameMedia, useMediaRules } from '../components/Media';
import { PencilIcon } from '../components/Icons';

/**
 * 글쓰기 (/board/new) · 고치기 (/board/:id/edit). 로그인 + 닉네임 필요 (닉네임은 Layout이 먼저 보낸다)
 * 고치기는 쓴 뒤 정해진 시간 안에만 (SPEC 6-7). 화면을 열 때 DB에 알려(begin_edit) 마감 전이면 유예를 받는다.
 * 051: 운영자(운영자 모드 켜짐)는 새 글에서 [공지로 올리기] → [알림 보내기](기본 켬). 고치기에는 없다(고쳐도 알림은 다시 가지 않는다).
 */
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
  const { data, error, loading, retry } = useAsync(async () => {
    if (!id) return null;
    const post = await getPost(Number(id));
    if (!post || post.author_id !== auth.user.id || post.deleted_at || post.status !== 'visible') return { post: null };
    try {
      return { post, deadline: await beginEdit('post', post.id) };
    } catch (e) {
      return { post: null, closed: e.message };
    }
  }, [id]);
  if (!id) return <PostForm />;
  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  if (!data.post) {
    return (
      <article>
        <h1 className="doc-title">글 고치기</h1>
        <p className="empty">{data.closed ?? '고칠 수 있는 내 글이 아닙니다.'}</p>
        <p><Link to={data.closed ? `/board/${id}` : '/board'}>← {data.closed ? '글로 돌아가기' : '탑신병자 커뮤니티'}</Link></p>
      </article>
    );
  }
  return <PostForm post={data.post} deadline={data.deadline} />;
}

function PostForm({ post = null, deadline = null }) {
  const navigate = useNavigate();
  const auth = useAuth();
  const guest = isGuest(auth);
  const rules = useMediaRules();
  const formRef = useRef(null);
  const [media, setMedia] = useState(() => mediaToItems(post?.media));
  const [title, setTitle] = useState(post?.title ?? '');
  const [body, setBody] = useState(post?.body ?? '');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const canNotice = !post && auth.isOperator;
  const [asNotice, setAsNotice] = useState(false);
  const [notify, setNotify] = useState(true);
  const notice = canNotice && asNotice;
  const t = title.trim().length;
  const b = body.trim().length;
  // 사진만 올리는 글도 된다 (제목은 꼭)
  const ready = t > 0 && t <= TITLE_MAX && b <= BODY_MAX && (b > 0 || media.length > 0);

  const submit = async (e) => {
    e.preventDefault();
    if (!ready || busy) return; // 보내는 동안은 잠가서 두 번 눌러도 한 번만
    setBusy(true);
    setError(null);
    try {
      const paths = await finishMedia(media, auth.user.id);
      if (post) {
        await editPost(post.id, title, body, sameMedia(media, post.media) ? null : paths);
        navigate(`/board/${post.id}`, { replace: true, state: { done: '글을 고쳤습니다.' } });
      } else {
        const newId = notice ? await createNotice(title, body, paths, notify) : await createPost(title, body, paths);
        const done = !notice ? '글을 올렸습니다.'
          : notify ? '공지를 올렸습니다. 가입자에게 알림을 차례로 보냅니다.' : '공지를 올렸습니다. 알림은 보내지 않았습니다.';
        navigate(`/board/${newId}`, { replace: true, state: { done } });
      }
    } catch (err) {
      setError(err.message);
      setBusy(false);
    }
  };

  return (
    <article>
      <nav className="crumbs"><Link to={post ? `/board/${post.id}` : '/board'}>← {post ? '글로 돌아가기' : '탑신병자 커뮤니티'}</Link></nav>
      <h1 className="doc-title page-title"><PencilIcon size={24} className="title-icon" /> {post ? '글 고치기' : '글쓰기'}</h1>
      <p className="lead">
        승인 없이 바로 올라갑니다. 욕설·혐오·비하·신상 공개·도배는 운영진이 숨길 수 있습니다. 자세한 건 <Link to="/terms">이용약관</Link>을 봐 주세요.
      </p>
      {deadline && <p className="notice edit-deadline">{fmtTime(deadline)}까지 저장할 수 있습니다. 그 뒤에는 지우기만 할 수 있습니다.</p>}
      <form className="doc-form post-form form-card media-drop-zone" onSubmit={submit} ref={formRef}>
        <label htmlFor="post-title">제목</label>
        <input id="post-title" value={title} onChange={(e) => setTitle(e.target.value)} autoComplete="off" />
        <CharCount value={title} max={TITLE_MAX} />
        <label htmlFor="post-body">본문</label>
        <textarea id="post-body" rows={12} value={body} onChange={(e) => setBody(e.target.value)} />
        <CharCount value={body} max={BODY_MAX} />
        <span className="field-label" id="post-media-label">사진·GIF</span>
        {guest ? (
          <>
            {post?.media?.length > 0 && <MediaGallery media={post.media} />}
            <GuestHint what="사진을 붙일" />
          </>
        ) : (
          <MediaPicker
            id="post-media" items={media} onChange={setMedia} max={rules.postMax} gifMax={rules.postGifMax} rules={rules} disabled={busy} dropRef={formRef}
          />
        )}
        {canNotice && (
          <fieldset className="notice-options" disabled={busy}>
            <legend>공지 (운영자만)</legend>
            <label className="check-row">
              <input type="checkbox" checked={asNotice} onChange={(e) => setAsNotice(e.target.checked)} />
              <span>
                공지로 올리기
                <small className="hint">목록 맨 위에 고정됩니다.</small>
              </span>
            </label>
            {asNotice && (
              <label className="check-row">
                <input type="checkbox" checked={notify} onChange={(e) => setNotify(e.target.checked)} />
                <span>
                  알림 보내기
                  <small className="hint">
                    {notify
                      ? '가입자 모두(게스트 포함)의 알림함에 쌓이고, 휴대폰 알림을 켠 사람에게는 휴대폰 알림도 갑니다. 고쳐도 알림은 다시 가지 않습니다.'
                      : '알림 없이 공지만 올라갑니다.'}
                  </small>
                </span>
              </label>
            )}
          </fieldset>
        )}
        {error && <p className="form-error" role="alert">{error}</p>}
        <div className="actions">
          <button type="submit" className="btn btn-primary" disabled={!ready || busy}>
            {busy ? (post ? '저장하는 중…' : '올리는 중…') : post ? '고친 내용 저장' : notice ? '공지 올리기' : '글 올리기'}
          </button>
          <Link to={post ? `/board/${post.id}` : '/board'} className="btn">취소</Link>
        </div>
      </form>
    </article>
  );
}
