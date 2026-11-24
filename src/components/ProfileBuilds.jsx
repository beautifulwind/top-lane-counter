import { useSearchParams } from 'react-router-dom';
import { getInfluencerBuilds } from '../api/follow';
import { useAsync } from '../lib/useAsync';
import InfluencerBuildCard from './InfluencerBuildCard';
import Pagination, { BUILD_PAGE_SIZE, usePaging } from './Pagination';
import SectionHead from './SectionHead';
import { ErrorBox, Loading } from './Status';
import { LayersIcon } from './Icons';

/** 정렬 칩 (1.3 패치 1-C, 6-98): 최신순(기본 — 서버의 최근 수정순 그대로) / 인기순(추천 많은 순, 같으면 최근 수정순). 선택은 ?sort=popular */
export const PROFILE_SORTS = [{ key: 'recent', label: '최신순' }, { key: 'popular', label: '인기순' }];

/**
 * 인기순은 서버가 정렬해 주지 않아(influencer_builds는 최근 수정순 20개씩만) 전부 받아 화면에서 정렬한다.
 * 그래서 빌드가 이 개수를 넘는 장인에게는 인기순 칩을 두지 않는다 (일부만 정렬하면 틀린 순위가 되므로). DB 정렬이 생기면 이 한도는 없어진다.
 */
export const POPULAR_MAX = 200;

/**
 * 장인 페이지의 빌드 목록. first = 1쪽(최신순) 응답. 쪽은 ?page=(기존 Pagination), 정렬은 ?sort=popular(최신순은 주소에 없음, 잘못된 값은 최신순).
 * 칩을 바꾸면 1쪽으로. 최신순은 쪽마다 서버에 묻고, 인기순은 한 번 전부 받아 나눈다. 숨김·승인 대기 빌드는 서버 조회 조건 그대로 오지 않는다.
 */
export default function ProfileBuilds({ id, champs, first, actions }) {
  const [params, setParams] = useSearchParams();
  const total = Number(first.total) || 0;
  const popularOk = total <= POPULAR_MAX;
  const sort = params.get('sort') === 'popular' && popularOk ? 'popular' : 'recent';
  const pg = usePaging(total);

  const direct = sort === 'recent' && pg.page === 1; // 처음 보이는 쪽은 이미 받아 둔 것 — 다시 묻지도, 깜박이지도 않는다
  const { data: fetched, error, loading: waiting, retry } = useAsync(async () => {
    if (sort === 'recent') {
      const r = await getInfluencerBuilds(id, pg.page);
      if (!r) throw new Error('장인 인증이 해제돼 빌드를 불러올 수 없습니다.');
      return r.items;
    }
    const pages = Math.ceil(total / BUILD_PAGE_SIZE);
    const rest = await Promise.all(Array.from({ length: Math.max(0, pages - 1) }, (_, i) => getInfluencerBuilds(id, i + 2)));
    const seen = new Set();
    const all = [...first.items, ...rest.flatMap((r) => r?.items ?? [])].filter((b) => !seen.has(b.id) && seen.add(b.id));
    return all.sort((a, b) => (b.up_count ?? 0) - (a.up_count ?? 0)); // 안정 정렬: 같으면 받은 순서(최근 수정순)
  }, [id, sort, sort === 'recent' ? pg.page : 0], { enabled: !direct });

  const pickSort = (key) => {
    const next = new URLSearchParams(params);
    next.delete('page'); // 칩을 바꾸면 1쪽으로
    if (key === 'popular') next.set('sort', 'popular');
    else next.delete('sort');
    setParams(next, { replace: true });
  };
  const data = direct ? first.items : fetched;
  const loading = direct ? false : waiting;
  const shown = data ? (sort === 'popular' ? data.slice(pg.start, pg.end) : data) : [];

  return (
    <section className="me-section" aria-labelledby="pp-builds">
      <SectionHead icon={LayersIcon} id="pp-builds" count={total}>처음 만든 빌드</SectionHead>
      {total > 0 && popularOk && (
        <div className="sort-chips" role="group" aria-label="정렬">
          {PROFILE_SORTS.map((o) => (
            <button
              key={o.key} type="button" className={sort === o.key ? 'btn btn-small on' : 'btn btn-small'}
              aria-pressed={sort === o.key} onClick={() => pickSort(o.key)}
            >{o.label}</button>
          ))}
        </div>
      )}
      {total === 0 && <p className="empty">공개된 빌드가 없습니다.</p>}
      {total > 0 && loading && <Loading />}
      {!direct && error && <ErrorBox error={error} onRetry={retry} />}
      {total > 0 && !loading && (direct || !error) && (
        <ul className="build-cards" ref={pg.listRef} aria-label="빌드 목록">
          {shown.map((b) => <InfluencerBuildCard key={b.id} b={b} champs={champs} linkActions={actions} />)}
        </ul>
      )}
      <Pagination {...pg} />
    </section>
  );
}
