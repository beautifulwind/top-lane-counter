import { useState } from 'react';
import { Link, useLocation, useSearchParams } from 'react-router-dom';
import { getFollowedBuilds, getMyFollowing } from '../api/follow';
import { getChampionMap } from '../api/ddragon';
import { isGuest, useAuth } from '../lib/auth';
import { useAsync } from '../lib/useAsync';
import { INFLUENCER_KINDS } from '../lib/nickname';
import { ErrorBox, Loading } from '../components/Status';
import InfluencerBuildCard from '../components/InfluencerBuildCard';
import FollowButton from '../components/FollowButton';
import { InfluencerName } from '../components/UserName';
import { LayersIcon } from '../components/Icons';

export const NO_FOLLOW_TEXT = '아직 팔로우한 장인이 없습니다. 상단의 돋보기(장인 찾기)로 찾아보세요.';
export const GUEST_FOLLOWING_TEXT = '비회원은 팔로우한 장인 목록을 볼 수 없습니다. 마이페이지에서 구글·카카오를 연결해 주세요.';

/**
 * 팔로우 모아보기 (/following, 050 · SPEC 6-36). 상단 돋보기(장인 찾기) 검색 칸의 [내가 팔로우한 장인의 빌드 보기],
 * 내 목록(/lists, 6-82) [팔로우한 장인] 탭의 링크로 온다.
 * 탭 두 개 (?tab=list로 주소에 남는다):
 *  - 빌드: followed_builds — 팔로우한 장인들의 공개 빌드, 최근 수정순 20개씩 [더보기]. 카드 = 장인 닉네임·챔피언·상대법 이름 → 그 빌드로
 *  - 팔로우한 장인: my_following — 20개씩, 줄마다 닉네임·장인 표시·유형·팔로워 수 + [팔로우중](누르면 취소, 다시 누르면 팔로우).
 *    063: 팔로우한 날은 보이지 않는다(DB도 주지 않음). 비회원(게스트)은 이 탭에서 안내만(DB도 거부).
 * 로그인하지 않았으면 로그인 안내만. 게스트도 빌드 탭은 쓸 수 있다.
 */
export default function Following() {
  const auth = useAuth();
  const location = useLocation();
  const [search, setSearch] = useSearchParams();
  const tab = search.get('tab') === 'list' ? 'list' : 'builds';
  const setTab = (t) => setSearch(t === 'list' ? { tab: 'list' } : {}, { replace: true });

  if (auth.status === 'loading') return <Loading />;
  return (
    <article className="me-page following-page">
      <h1 className="doc-title page-title"><LayersIcon size={26} className="title-icon" /> 팔로우한 장인의 빌드</h1>
      {auth.status !== 'signedIn' ? (
        <p className="notice" role="status">
          로그인하면 팔로우한 장인의 빌드를 모아 볼 수 있습니다.{' '}
          <Link to="/login" state={{ from: `${location.pathname}${location.search}` }}>로그인</Link>
        </p>
      ) : (
        <>
          <div className="following-tabs" role="tablist" aria-label="보기">
            <button type="button" role="tab" id="ft-builds" aria-selected={tab === 'builds'} aria-controls="ft-panel"
              className={tab === 'builds' ? 'btn btn-small on' : 'btn btn-small'} onClick={() => setTab('builds')}>빌드</button>
            <button type="button" role="tab" id="ft-list" aria-selected={tab === 'list'} aria-controls="ft-panel"
              className={tab === 'list' ? 'btn btn-small on' : 'btn btn-small'} onClick={() => setTab('list')}>팔로우한 장인</button>
          </div>
          <div id="ft-panel" role="tabpanel" aria-labelledby={tab === 'list' ? 'ft-list' : 'ft-builds'}>
            {tab === 'list'
              ? (isGuest(auth) ? <p className="notice" role="status">{GUEST_FOLLOWING_TEXT}</p> : <FollowingList userId={auth.user.id} />)
              : <FollowedBuilds userId={auth.user.id} />}
          </div>
        </>
      )}
    </article>
  );
}

/** 한 쪽씩 이어 붙이는 목록 (첫 쪽은 useAsync, [더보기]는 다음 쪽) */
function usePaged(load, deps) {
  const first = useAsync(load(1), deps);
  const [extra, setExtra] = useState({ base: null, items: [], page: 1, busy: false, error: null });
  const ext = extra.base === first.data ? extra : { base: first.data, items: [], page: 1, busy: false, error: null };
  const items = first.data ? [...first.data.page.items, ...ext.items] : [];
  const total = Number(first.data?.page.total) || 0;
  const more = async () => {
    setExtra({ ...ext, busy: true, error: null });
    try {
      const r = await load(ext.page + 1)();
      const seen = new Set(items.map((x) => x.id));
      setExtra({ base: first.data, items: [...ext.items, ...r.page.items.filter((x) => !seen.has(x.id))], page: ext.page + 1, busy: false, error: null });
    } catch (e) {
      setExtra({ ...ext, busy: false, error: e.message });
    }
  };
  return { ...first, items, total, more, moreBusy: ext.busy, moreError: ext.error };
}

function MoreButton({ list, unit }) {
  return (
    <>
      {list.items.length < list.total && (
        <div className="actions">
          <button type="button" className="btn" onClick={list.more} disabled={list.moreBusy}>
            {list.moreBusy ? '불러오는 중…' : `더보기 (${list.total - list.items.length}${unit} 남음)`}
          </button>
        </div>
      )}
      {list.moreError && <p className="form-error" role="alert">{list.moreError}</p>}
    </>
  );
}

function FollowedBuilds({ userId }) {
  const list = usePaged((page) => async () => {
    const [p, champs] = await Promise.all([getFollowedBuilds(page), getChampionMap().catch(() => ({}))]);
    return { page: p, champs };
  }, [userId]);
  if (list.loading && !list.data) return <Loading />;
  if (list.error) return <ErrorBox error={list.error} onRetry={list.retry} />;
  if (list.total === 0) return <p className="empty">{NO_FOLLOW_TEXT}</p>;
  return (
    <section aria-label="팔로우한 장인의 빌드">
      <p className="hint">팔로우한 장인이 처음 만든 공개 빌드를 최근 수정한 순서로 보여 줍니다.</p>
      <ul className="build-cards">
        {list.items.map((b) => <InfluencerBuildCard key={b.id} b={b} champs={list.data.champs} showAuthor />)}
      </ul>
      <MoreButton list={list} unit="개" />
    </section>
  );
}

/** 내가 팔로우한 장인 목록 — 내 목록(/lists) [팔로우한 장인] 탭도 쓴다 */
export function FollowingList({ userId }) {
  const list = usePaged((page) => async () => ({ page: await getMyFollowing(page) }), [userId]);
  const [now, setNow] = useState({}); // 이 화면에서 바꾼 것 { 장인 id: { following, follower_count } }
  if (list.loading && !list.data) return <Loading />;
  if (list.error) return <ErrorBox error={list.error} onRetry={list.retry} />;
  if (list.total === 0) return <p className="empty">{NO_FOLLOW_TEXT}</p>;
  return (
    <section aria-label="내가 팔로우한 장인">
      <p className="hint">팔로우한 장인 {list.total}명 · [팔로우중]을 누르면 팔로우를 취소합니다.</p>
      <ul className="link-list following-list">
        {list.items.map((p) => {
          const st = now[p.id];
          const count = st ? st.follower_count : p.follower_count;
          return (
            <li key={p.id} className="following-row">
              <span className="following-who">
                <InfluencerName profile={p} linkTo={p.id} />
                <small className="muted">
                  {INFLUENCER_KINDS[p.influencer] ?? '장인'} · 팔로워 {Number(count ?? 0).toLocaleString()}명
                </small>
              </span>
              <FollowButton
                id={p.id} nickname={p.nickname} following={st ? st.following : true}
                onChange={(r) => setNow((m) => ({ ...m, [p.id]: { following: !!r?.following, follower_count: Number(r?.follower_count) || 0 } }))}
              />
            </li>
          );
        })}
      </ul>
      <MoreButton list={list} unit="명" />
    </section>
  );
}
