import { useEffect, useRef, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { getFollowStatus, getInfluencerDirectory } from '../api/follow';
import FollowButton from '../components/FollowButton';
import { NoneLine } from '../components/LimitedList';
import Pagination, { clampPage } from '../components/Pagination';
import ProfilePhoto from '../components/ProfilePhoto';
import { ErrorBox, Loading } from '../components/Status';
import { SEARCH_WAIT_MS } from '../components/InfluencerSearch';
import { isBlocked, useAuth } from '../lib/auth';
import { INFLUENCER_PAGE_SIZE, INFLUENCER_QUERY_MAX, INFLUENCER_SORTS } from '../lib/influencerList';
import { useAsync } from '../lib/useAsync';

const DEFAULT_SORT = INFLUENCER_SORTS[0].key;

/**
 * 전체 장인 목록 (1.3 패치 1-B1, SPEC 6-93): 로그인 없이 볼 수 있다. 제목 + 인원수 칩 → 닉네임 검색 → 정렬 칩(팔로워 많은 순·최신순) → 장인 줄 → 쪽 번호.
 * 정렬·검색어·쪽은 주소(?sort= ?q= ?page=)에 남아 새로고침해도 같다(기본값은 주소에 안 남김). 한 쪽 INFLUENCER_PAGE_SIZE명(influencer_directory가 쪽을 나눈다).
 * 줄: 사진(없으면 첫 글자 원) · 닉네임 · 「인증」 · 「빌드 N · 팔로워 N」 — 누르면 /u/:id. 팔로우 버튼은 줄 링크 밖에 따로 있어 눌러도 이동하지 않는다(본인 줄은 없음).
 * 팔로우 상태는 목록을 받은 뒤 getFollowStatus로 한 번에 받는다. 뒤로 가기는 상단 바 ← 가 한다.
 */
export default function Influencers() {
  const auth = useAuth();
  const [params, setParams] = useSearchParams();
  const query = (params.get('q') ?? '').trim().slice(0, INFLUENCER_QUERY_MAX);
  const sort = INFLUENCER_SORTS.some((s) => s.key === params.get('sort')) ? params.get('sort') : DEFAULT_SORT;
  const wantPage = Math.max(1, Number.parseInt(params.get('page') ?? '', 10) || 1);
  const [input, setInput] = useState(query);
  const listRef = useRef(null);
  const moved = useRef(false);

  /** 주소를 바꾼다 (기본값은 지움). 주소 기록은 쌓지 않는다 */
  const update = (patch) => {
    const next = new URLSearchParams(params);
    Object.entries(patch).forEach(([k, v]) => {
      if (v == null || v === '' || (k === 'sort' && v === DEFAULT_SORT) || (k === 'page' && Number(v) <= 1)) next.delete(k);
      else next.set(k, String(v));
    });
    setParams(next, { replace: true });
  };

  // 입력을 멈추고 잠깐 뒤 검색어를 주소에 올린다 (글자마다 요청하지 않게). 공백뿐이면 빈 검색
  useEffect(() => {
    const term = input.trim();
    if (term === query) return undefined;
    const t = setTimeout(() => update({ q: term, page: null }), SEARCH_WAIT_MS);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [input]);
  // 뒤로 가기 등으로 주소의 검색어가 바뀌면 입력칸도 맞춘다
  useEffect(() => { setInput((cur) => (cur.trim() === query ? cur : query)); }, [query]);

  const { data, error, loading, retry } = useAsync(() => getInfluencerDirectory({ query, sort, page: wantPage, size: INFLUENCER_PAGE_SIZE }), [query, sort, wantPage]);
  const last = useRef(null); // 다음 쪽을 받는 동안 이전 목록을 그대로 보여 준다 (깜빡임 방지)
  if (data) last.current = data;
  const shown = data ?? (loading ? last.current : null);

  const total = Number(shown?.total) || 0;
  const pages = Math.max(1, Math.ceil(total / INFLUENCER_PAGE_SIZE));
  const page = clampPage(wantPage, pages);
  // 주소의 쪽이 끝 쪽을 넘으면(장인이 줄었거나 손으로 고친 주소) 끝 쪽으로
  useEffect(() => { if (data && wantPage > pages) update({ page: pages }); }, [data, wantPage, pages]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => {
    if (!moved.current || !data) return;
    moved.current = false;
    listRef.current?.scrollIntoView?.({ block: 'start' });
    listRef.current?.querySelector('li a')?.focus({ preventScroll: true });
  }, [data]);

  const items = (shown?.items ?? []).filter((p) => !isBlocked(auth, p.id)); // 061: 내가 차단한 장인은 뺀다 (장인 찾기와 같음)
  const ids = items.map((p) => p.id).join(',');
  const [follows, setFollows] = useState({});
  useEffect(() => {
    let alive = true;
    if (!data || auth.status !== 'signedIn' || !ids) { setFollows({}); return undefined; }
    getFollowStatus(ids.split(',')).then((m) => alive && setFollows(m));
    return () => { alive = false; };
  }, [data, ids, auth.status]);
  const [counts, setCounts] = useState({}); // 팔로우·취소 직후 줄의 팔로워 수 (서버가 돌려준 값)
  useEffect(() => { setCounts({}); }, [data]);

  const onFollow = (id) => (r) => {
    setFollows((m) => ({ ...m, [id]: r.following }));
    if (r.follower_count != null) setCounts((c) => ({ ...c, [id]: r.follower_count }));
  };

  return (
    <article className="influencers-page">
      <div className="section-head">
        <h1 className="doc-title page-title">장인</h1>
        {shown && <span className="count-badge">{total.toLocaleString()}명</span>}
      </div>

      <div className="inf-list-search" role="search" aria-label="장인 닉네임 검색">
        <label className="sr-only" htmlFor="inf-list-q">장인 닉네임</label>
        <input
          id="inf-list-q" type="search" className="inf-search-input" value={input} maxLength={INFLUENCER_QUERY_MAX}
          placeholder="장인 닉네임 검색" autoComplete="off" enterKeyHint="search"
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Enter') e.preventDefault(); }}
        />
      </div>

      <div className="following-tabs inf-sort" role="group" aria-label="정렬">
        {INFLUENCER_SORTS.map((s) => (
          <button
            key={s.key} type="button" className={sort === s.key ? 'btn btn-small on' : 'btn btn-small'}
            aria-pressed={sort === s.key} onClick={() => update({ sort: s.key, page: null })}
          >
            {s.label}
          </button>
        ))}
      </div>

      {!shown && loading && <Loading />}
      {error && <ErrorBox error={error} onRetry={retry} />}
      {shown && !error && (items.length === 0 ? (
        <NoneLine>{query ? `「${query}」에 맞는 장인이 없습니다.` : '아직 인증된 장인이 없습니다.'}</NoneLine>
      ) : (
        <ul className="inf-rows" aria-label="장인 목록" aria-busy={loading} ref={listRef}>
          {items.map((p) => (
            <li key={p.id} className="inf-row">
              <Link to={`/u/${p.id}`} className="inf-row-main">
                <span className="inf-row-avatar" aria-hidden="true">
                  <ProfilePhoto
                    path={p.photo_path} alt="" className="inf-row-photo"
                    fallback={<span className="inf-row-initial">{Array.from(p.nickname ?? '?')[0]}</span>}
                  />
                </span>
                <span className="inf-row-text">
                  <span className="inf-row-name">
                    <span className="user-nick">{p.nickname}</span>
                    <span className="inf-tag">인증</span>
                  </span>
                  <small className="muted">
                    빌드 {Number(p.build_count ?? 0).toLocaleString()} · 팔로워 {Number(counts[p.id] ?? p.follower_count ?? 0).toLocaleString()}
                  </small>
                </span>
              </Link>
              {auth.user?.id !== p.id && (
                <div className="inf-row-follow">
                  <FollowButton id={p.id} nickname={p.nickname} following={!!follows[p.id]} onChange={onFollow(p.id)} />
                </div>
              )}
            </li>
          ))}
        </ul>
      ))}

      <Pagination page={page} pages={pages} go={(n) => { moved.current = true; update({ page: n }); }} />
    </article>
  );
}
