import { Link, useLocation, useSearchParams } from 'react-router-dom';
import { getMySavedBuilds } from '../api/bookmarks';
import { getChampionMap } from '../api/ddragon';
import { canWrite, isBlocked, isGuest, useAuth } from '../lib/auth';
import { useAsync } from '../lib/useAsync';
import { useBuildDifficulties } from '../lib/useBuildDifficulties';
import { ErrorBox, Loading } from '../components/Status';
import BuildRow from '../components/BuildRow';
import Pagination, { usePaging } from '../components/Pagination';
import { BookmarkIcon } from '../components/Icons';
import MyChampions from '../components/MyChampions';
import { FollowingList, GUEST_FOLLOWING_TEXT } from './Following';

export const NO_SAVED_TEXT = '아직 저장한 빌드가 없습니다. 빌드 카드의 추천 버튼 옆 [저장]을 누르면 여기에 모입니다.';

/**
 * 내 목록 (/lists, SPEC 6-82). ☰ 메뉴 [내 목록 보기]로 온다. 위쪽 탭 세 개 (?tab=following · ?tab=champions로 주소에 남는다):
 *  - 저장한 빌드 (기본): my_saved_builds — 최근 저장순, 줄 모양은 전체 빌드 목록(/builds)과 같은 BuildRow(왼쪽 강조선 카드).
 *    20개씩 쪽 번호(이전 · 1 2 3 … · 다음, 쪽은 ?page=, 6-87), 차단한 사람의 빌드는 숨기고 개수 안내, 지금 볼 수 없는(숨김) 빌드 수 안내.
 *  - 팔로우한 장인: 팔로우 모아보기(/following)의 목록 그대로 (063 규칙: 내 것만, 팔로우한 날 없음, 비회원은 안내만).
 *  - 내 챔피언 (6-116, 080): 내가 하는 챔피언 최대 10개를 골라 그 챔피언들의 공개 빌드를 모아 본다 (components/MyChampions, /following과 같은 탭). 비회원도 쓸 수 있다.
 * 로그인하지 않았으면 로그인 안내만. 닉네임 전이면 목록은 보이고 저장하려면 닉네임이 필요하다고 알려 준다 (/following과 같은 규칙).
 */
export default function MyLists() {
  const auth = useAuth();
  const location = useLocation();
  const [search, setSearch] = useSearchParams();
  const tab = ['following', 'champions'].includes(search.get('tab')) ? search.get('tab') : 'saved';
  const setTab = (t) => setSearch(t === 'saved' ? {} : { tab: t }, { replace: true });
  const tabId = { saved: 'ml-saved', following: 'ml-following', champions: 'ml-champions' }[tab];

  if (auth.status === 'loading') return <Loading />;
  return (
    <article className="me-page following-page my-lists">
      <h1 className="doc-title page-title"><BookmarkIcon size={26} className="title-icon" /> 내 목록</h1>
      {auth.status !== 'signedIn' ? (
        <p className="notice" role="status">
          로그인하면 저장한 빌드와 팔로우한 장인을 모아 볼 수 있습니다.{' '}
          <Link to="/login" state={{ from: `${location.pathname}${location.search}` }}>로그인</Link>
        </p>
      ) : (
        <>
          <div className="following-tabs" role="tablist" aria-label="내 목록">
            <button type="button" role="tab" id="ml-saved" aria-selected={tab === 'saved'} aria-controls="ml-panel"
              className={tab === 'saved' ? 'btn btn-small on' : 'btn btn-small'} onClick={() => setTab('saved')}>저장한 빌드</button>
            <button type="button" role="tab" id="ml-following" aria-selected={tab === 'following'} aria-controls="ml-panel"
              className={tab === 'following' ? 'btn btn-small on' : 'btn btn-small'} onClick={() => setTab('following')}>팔로우한 장인</button>
            <button type="button" role="tab" id="ml-champions" aria-selected={tab === 'champions'} aria-controls="ml-panel"
              className={tab === 'champions' ? 'btn btn-small on' : 'btn btn-small'} onClick={() => setTab('champions')}>내 챔피언</button>
          </div>
          <div id="ml-panel" role="tabpanel" aria-labelledby={tabId}>
            {tab === 'champions' ? (
              <MyChampions userId={auth.user.id} />
            ) : tab === 'following' ? (
              <>
                {isGuest(auth) ? <p className="notice" role="status">{GUEST_FOLLOWING_TEXT}</p> : <FollowingList userId={auth.user.id} />}
                <p className="hint"><Link to="/following">팔로우한 장인의 빌드 모아 보기</Link></p>
              </>
            ) : (
              <SavedBuilds userId={auth.user.id} />
            )}
          </div>
        </>
      )}
    </article>
  );
}

function SavedBuilds({ userId }) {
  const auth = useAuth();
  const { data, error, loading, retry } = useAsync(async () => {
    const [saved, champs] = await Promise.all([getMySavedBuilds(), getChampionMap().catch(() => ({}))]);
    return { saved, champs };
  }, [userId]);
  const visible = (data?.saved.items ?? []).filter((b) => !isBlocked(auth, b.author_id));
  const pg = usePaging(visible.length);
  const shownNow = visible.slice(pg.start, pg.end);
  const ratings = useBuildDifficulties(shownNow.map((b) => b.id)); // 6-104: 보이는 쪽의 id만 (저장 한도 500개 중 20개씩)

  if (loading && !data) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;

  const { items, total, hidden, limit } = data.saved;
  const blocked = items.length - visible.length;
  const shown = shownNow;

  return (
    <section aria-label="저장한 빌드">
      {!canWrite(auth) && <p className="hint">닉네임을 정하면 빌드를 저장할 수 있습니다.</p>}
      {total > 0 && (
        <p className="hint">{`저장한 빌드 ${total}개 (최대 ${limit}개) · 최근에 저장한 순서입니다. 나만 볼 수 있습니다.`}</p>
      )}
      {hidden > 0 && <p className="hint" role="note">{`지금은 볼 수 없는 빌드 ${hidden}개는 뺐습니다. (숨겨진 빌드나 상대법 — 다시 공개되면 돌아옵니다)`}</p>}
      {blocked > 0 && <p className="hint" role="note">{`차단한 사용자의 빌드 ${blocked}개는 숨겼습니다.`}</p>}
      {visible.length === 0 ? (
        <p className="empty">{total === 0 ? NO_SAVED_TEXT : '보여 줄 빌드가 없습니다.'}</p>
      ) : (
        <ul className="build-cards all-builds saved-builds" ref={pg.listRef}>
          {shown.map((b) => <BuildRow key={b.id} b={{ ...b, difficulty: ratings[b.id] ?? null }} champs={data.champs} />)}
        </ul>
      )}
      <Pagination {...pg} />
    </section>
  );
}
