import { useState } from 'react';
import { Link, useLocation, useSearchParams } from 'react-router-dom';
import { PAGE_SIZE, getBoardPage } from '../api/board';
import { useAuth } from '../lib/auth';
import { useAsync } from '../lib/useAsync';
import { fmtDateTime } from '../lib/format';
import { ErrorBox, Loading } from '../components/Status';
import UserName from '../components/UserName';
import { ChevronIcon, ImageIcon, MessageIcon, PencilIcon, SearchIcon, ThumbIcon } from '../components/Icons';

/**
 * 자유게시판 목록 (/board): 최신순 20개씩, 제목·본문 검색. 검색어·쪽은 주소(?q=&page=)에 남는다.
 * 읽기는 누구나, 글쓰기는 로그인 + 닉네임 (승인 없이 바로 올라감, SPEC 6-5)
 */
export default function Board() {
  const auth = useAuth();
  const [params, setParams] = useSearchParams();
  const q = params.get('q') ?? '';
  const page = Math.max(1, Number.parseInt(params.get('page') ?? '1', 10) || 1);
  const done = useLocation().state?.done;
  const { data, error, loading, retry } = useAsync(() => getBoardPage(q, page), [q, page]);
  const [draft, setDraft] = useState(q);
  const [lastQ, setLastQ] = useState(q);
  if (lastQ !== q) {
    // 뒤로 가기 등으로 주소의 검색어가 바뀌면 입력칸도 맞춘다
    setLastQ(q);
    setDraft(q);
  }

  const go = (nextQ, nextPage) => {
    const next = {};
    if (nextQ) next.q = nextQ;
    if (nextPage > 1) next.page = String(nextPage);
    setParams(next);
  };
  const search = (e) => {
    e.preventDefault();
    go(draft.trim(), 1);
  };
  const pages = data ? Math.max(1, Math.ceil(data.total / PAGE_SIZE)) : 1;

  return (
    <article className="board">
      <div className="board-head">
        <h1 className="doc-title page-title"><MessageIcon size={26} className="title-icon" /> 자유게시판</h1>
        {auth.status === 'signedIn' ? (
          <Link to="/board/new" className="btn btn-primary"><PencilIcon size={16} /> 글쓰기</Link>
        ) : (
          <Link to="/login" state={{ from: '/board/new' }} className="btn">로그인하고 글쓰기</Link>
        )}
      </div>
      {done && <p className="notice" role="status">{done}</p>}

      <form className="search board-search" role="search" onSubmit={search}>
        <span className="search-field">
          <SearchIcon size={18} className="search-icon" />
          <input
            type="search" value={draft} onChange={(e) => setDraft(e.target.value)}
            placeholder="제목·본문 검색" aria-label="제목·본문 검색" maxLength={50} enterKeyHint="search"
          />
        </span>
        <button type="submit" className="btn">검색</button>
      </form>
      {q && (
        <p className="hint">
          ‘{q}’ 검색 결과 {data ? `${data.total}개` : ''} · <button type="button" className="link-btn" onClick={() => go('', 1)}>검색 지우기</button>
        </p>
      )}

      {loading && <Loading />}
      {error && <ErrorBox error={error} onRetry={retry} />}
      {data && data.rows.length === 0 && (
        <p className="empty">{q ? '검색에 맞는 글이 없습니다.' : '아직 글이 없습니다. 첫 글을 써 보세요!'}</p>
      )}
      {data && data.rows.length > 0 && (
        <ul className="post-list" aria-label="글 목록">
          {data.rows.map((p) => (
            <li key={p.id} className={p.status === 'hidden' ? 'post-row hidden-row' : 'post-row'}>
              <Link to={`/board/${p.id}`} className="post-link">
                <span className="post-title-line">
                  {p.status === 'hidden' && <span className="op-badge">숨김</span>}
                  <span className="post-title">{p.title}</span>
                  {p.media_count > 0 && <span className="post-media" role="img" aria-label="사진 있음" title="사진 있음"><ImageIcon size={16} /></span>}
                </span>
                <span className="post-meta">
                  {p.author ? <UserName profile={p.author} /> : <span>(탈퇴한 유저)</span>}
                  <span>{fmtDateTime(p.created_at)}</span>
                </span>
                <span className="post-stats">
                  {p.comment_count > 0 && <span className="post-count" aria-label={`댓글 ${p.comment_count}개`}><MessageIcon size={14} /> {p.comment_count}</span>}
                  {p.up_count > 0 && <span className="post-up" aria-label={`추천 ${p.up_count}`}><ThumbIcon size={14} /> {p.up_count}</span>}
                </span>
                <span className="chev" aria-hidden="true"><ChevronIcon size={18} /></span>
              </Link>
            </li>
          ))}
        </ul>
      )}
      {data && pages > 1 && <Pager page={page} pages={pages} onGo={(n) => go(q, n)} />}
    </article>
  );
}

/** 쪽 번호: [이전] 1 … 4 5 [6] 7 8 … 20 [다음] */
function Pager({ page, pages, onGo }) {
  const nums = [];
  for (let n = Math.max(1, page - 2); n <= Math.min(pages, page + 2); n += 1) nums.push(n);
  if (nums[0] > 1) nums.unshift(1, ...(nums[0] > 2 ? ['…a'] : []));
  if (nums[nums.length - 1] < pages) nums.push(...(nums[nums.length - 1] < pages - 1 ? ['…b'] : []), pages);
  return (
    <nav className="pager" aria-label="쪽 이동">
      <button type="button" className="btn btn-small" disabled={page <= 1} onClick={() => onGo(page - 1)}>이전</button>
      {nums.map((n) => (typeof n === 'string' ? (
        <span key={n} className="pager-gap" aria-hidden="true">…</span>
      ) : (
        <button
          key={n} type="button" className={n === page ? 'btn btn-small current' : 'btn btn-small'}
          aria-current={n === page ? 'page' : undefined} aria-label={`${n}쪽`} onClick={() => onGo(n)}
        >
          {n}
        </button>
      )))}
      <button type="button" className="btn btn-small" disabled={page >= pages} onClick={() => onGo(page + 1)}>다음</button>
    </nav>
  );
}
