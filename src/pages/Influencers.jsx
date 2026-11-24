import { useEffect, useRef, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { getFollowStatus, getInfluencerDirectory } from '../api/follow';
import FollowButton from '../components/FollowButton';
import { SEARCH_WAIT_MS } from '../components/InfluencerSearch';
import { ClockIcon } from '../components/Icons';
import { NoneLine } from '../components/LimitedList';
import Pagination, { clampPage } from '../components/Pagination';
import ProfilePhoto from '../components/ProfilePhoto';
import SearchField from '../components/SearchField';
import { ErrorBox, Loading } from '../components/Status';
import { isBlocked, useAuth } from '../lib/auth';
import { INFLUENCER_FETCH_MAX, INFLUENCER_PAGE_SIZE, INFLUENCER_QUERY_MAX, INFLUENCER_SORT_DEFAULT, INFLUENCER_SORT_RECENT } from '../lib/influencerList';
import { photoFirst } from '../lib/influencerOrder';
import { useAsync } from '../lib/useAsync';

/**
 * 전체 장인 목록 (1.3 패치 1-B1·1-B2 보완·정정, SPEC 6-93·6-95·6-96): 로그인 없이 볼 수 있다. 제목 + 인원수 칩 → 닉네임 검색(알약형) → 「최신순」 칩 → 장인 줄 → 쪽 번호.
 * 기본 정렬은 팔로워 많은 순(같으면 최신순, influencer_directory 'followers' — 화면에 따로 표시하지 않음). 「최신순」 칩은 켜고 끄는 토글: 켜면 'recent'(최근 활동순).
 * 칩 상태는 주소 ?sort=recent에 남고(끄면 지움), 다른 값·잘못된 값은 followers로 본다. 칩을 바꾸면 1쪽으로, 검색어는 유지.
 * 사진 없는 장인은 맨 뒤(lib/influencerOrder.js — 나중에 DB 정렬로 바꾸기 쉽게 한 곳). 두 정렬 모두 그렇다. 그러려면 전체를 봐야 해서 정렬이 바뀔 때마다 INFLUENCER_FETCH_MAX(50)명을 새로 받아
 * 웹에서 INFLUENCER_PAGE_SIZE(10)명씩 나눈다(검색어가 있어도 같음). 전체가 50명을 넘으면 사진 순서를 못 맞추므로 서버 쪽 나누기(쪽마다 요청)로 되돌린다.
 * 검색어·쪽은 주소(?q= ?page=)에 남아 새로고침해도 같다.
 * 줄: 사진(없으면 첫 글자 원) · 닉네임 · 「인증」 · 「빌드 N · 팔로워 N」 — 누르면 /u/:id. 팔로우 버튼은 줄 링크 밖에 따로 있어 눌러도 이동하지 않는다(본인 줄은 없음).
 * 팔로우 상태는 화면에 보이는 장인만 대상으로 getFollowStatus 한 번. 뒤로 가기는 상단 바 ← 가 한다.
 */
export default function Influencers() {
  const auth = useAuth();
  const [params, setParams] = useSearchParams();
  const query = (params.get('q') ?? '').trim().slice(0, INFLUENCER_QUERY_MAX);
  const sort = params.get('sort') === INFLUENCER_SORT_RECENT ? INFLUENCER_SORT_RECENT : INFLUENCER_SORT_DEFAULT; // 다른 값은 followers
  const wantPage = Math.max(1, Number.parseInt(params.get('page') ?? '', 10) || 1);
  const [input, setInput] = useState(query);
  const listRef = useRef(null);
  const moved = useRef(false);

  /** 주소를 바꾼다 (기본값은 지움, sort는 recent일 때만 남기고 잘못된 값은 지움). 주소 기록은 쌓지 않는다 */
  const update = (patch) => {
    const next = new URLSearchParams(params);
    next.delete('sort');
    if ((patch.sort !== undefined ? patch.sort : sort) === INFLUENCER_SORT_RECENT) next.set('sort', INFLUENCER_SORT_RECENT);
    Object.entries(patch).forEach(([k, v]) => {
      if (k === 'sort') return;
      if (v == null || v === '' || (k === 'page' && Number(v) <= 1)) next.delete(k);
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
  const clearSearch = () => update({ q: null, page: null }); // [지우기]: 입력은 SearchField가 비우고, 주소의 q·page도 바로 초기화

  // 한 번에 받아 오기 (검색어가 바뀔 때만). 50명 이하면 이걸로 끝, 넘으면 서버 쪽 나누기로
  const all = useAsync(() => getInfluencerDirectory({ query, sort, page: 1, size: INFLUENCER_FETCH_MAX }), [query, sort]);
  const serverMode = !!all.data && Number(all.data.total) > INFLUENCER_FETCH_MAX;
  const paged = useAsync(
    () => getInfluencerDirectory({ query, sort, page: wantPage, size: INFLUENCER_PAGE_SIZE }),
    [query, sort, wantPage], { enabled: serverMode },
  );
  const data = serverMode ? paged.data : all.data;
  const error = all.error ?? (serverMode ? paged.error : null);
  const loading = all.loading || (serverMode && paged.loading);
  const retry = () => { all.retry(); if (serverMode) paged.retry(); };
  const last = useRef(null); // 다음 쪽을 받는 동안 이전 목록을 그대로 보여 준다 (깜빡임 방지)
  if (data) last.current = { serverMode, data };
  const shown = data ? { serverMode, data } : (loading ? last.current : null);

  // 차단한 장인(061)은 뺀다 (장인 찾기와 같음). 웹에서 나눌 때는 뺀 뒤에 사진 순서·쪽을 정해서 쪽이 비지 않게 한다
  const visible = (shown?.data.items ?? []).filter((p) => !isBlocked(auth, p.id));
  const total = !shown ? 0 : shown.serverMode ? Number(shown.data.total) || 0 : visible.length;
  const pages = Math.max(1, Math.ceil(total / INFLUENCER_PAGE_SIZE));
  const page = clampPage(wantPage, pages);
  const items = !shown ? [] : shown.serverMode ? visible
    : photoFirst(visible).slice((page - 1) * INFLUENCER_PAGE_SIZE, page * INFLUENCER_PAGE_SIZE);
  // 주소의 쪽이 끝 쪽을 넘으면(장인이 줄었거나 손으로 고친 주소) 끝 쪽으로
  useEffect(() => { if (data && wantPage > pages) update({ page: pages }); }, [data, wantPage, pages]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => {
    if (!moved.current || !data) return;
    moved.current = false;
    listRef.current?.scrollIntoView?.({ block: 'start' });
    listRef.current?.querySelector('li a')?.focus({ preventScroll: true });
  }, [data, page]);

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
        <SearchField
          id="inf-list-q" value={input} onChange={setInput} onClear={clearSearch} maxLength={INFLUENCER_QUERY_MAX}
          placeholder="장인 닉네임 검색" label="장인 닉네임"
          onKeyDown={(e) => { if (e.key === 'Enter') e.preventDefault(); }}
        />
      </div>

      {/* 정렬 칩: 꺼짐 = 팔로워 많은 순(기본, 표시 없음), 켜짐 = 최신순(주황) */}
      <p className="inf-sort">
        <button
          type="button" className={sort === INFLUENCER_SORT_RECENT ? 'sort-chip on' : 'sort-chip'}
          aria-pressed={sort === INFLUENCER_SORT_RECENT}
          onClick={() => update({ sort: sort === INFLUENCER_SORT_RECENT ? null : INFLUENCER_SORT_RECENT, page: null })}
        >
          <ClockIcon size={15} aria-hidden="true" />최신순
        </button>
      </p>

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
