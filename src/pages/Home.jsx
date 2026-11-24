import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { getChampions } from '../api/ddragon';
import { getPublicBuildCount } from '../api/buildCount';
import { champMatch, tokenize } from '../lib/championSearch';
import BuildCountBadge from '../components/BuildCountBadge';
import BuildSearch from '../components/BuildSearch';
import HomeInfluencers from '../components/HomeInfluencers';
import { CHAMP_VISIBLE_ROWS, gridColumnCount } from '../lib/homeLayout';
import { useAsync } from '../lib/useAsync';
import { ErrorBox, Loading } from '../components/Status';
import SectionHead from '../components/SectionHead';
import { CrosshairIcon } from '../components/Icons';

export default function Home() {
  const { data: champions, error, loading, retry } = useAsync(getChampions, []);
  const [query, setQuery] = useState('');
  // 등록된 빌드 수 (6-78): 챔피언 격자를 기다리지 않고 따로 받는다. 실패·0개면 조용히 숨긴다
  const [buildCount, setBuildCount] = useState(0);
  useEffect(() => {
    let live = true;
    getPublicBuildCount().then((n) => { if (live) setBuildCount(n); }, () => {});
    return () => { live = false; };
  }, []);

  const tokens = useMemo(() => tokenize(query), [query]);
  // 격자: 모든 단어가 맞는 챔피언 (이름·초성·영문·별명, 6-61). 단어가 둘 이상이면 후보 목록이 주인공이라 격자는 숨긴다
  const filtered = useMemo(
    () => (champions ?? []).filter((c) => tokens.length === 0 || champMatch(tokens, c) > 0),
    [champions, tokens],
  );

  // 격자 4줄 제한 (1-B2): 한 줄 칸 수는 화면 폭에 따라 달라서(CSS auto-fill) 그려진 격자에서 읽고, 폭이 바뀌면 다시 읽는다. 못 읽으면 5칸으로 본다.
  const [expanded, setExpanded] = useState(false);
  const [cols, setCols] = useState(0);
  const gridRef = useRef(null);
  const showGrid = !!champions && filtered.length > 0;
  useLayoutEffect(() => {
    const el = gridRef.current;
    if (!el) return undefined;
    const read = () => setCols(gridColumnCount(el));
    read();
    if (typeof ResizeObserver === 'function') {
      const ro = new ResizeObserver(read);
      ro.observe(el);
      return () => ro.disconnect();
    }
    window.addEventListener('resize', read);
    return () => window.removeEventListener('resize', read);
  }, [showGrid]);
  const searching = tokens.length > 0; // 검색 중에는 4줄 제한 없이 결과를 모두
  const limit = (cols || 5) * CHAMP_VISIBLE_ROWS;
  const canFold = !searching && filtered.length > limit;
  const folded = canFold && !expanded;
  const shown = folded ? filtered.slice(0, limit) : filtered; // 접힌 줄은 그리지 않아 키보드 초점·스크린리더에서도 빠진다

  return (
    <>
      <div className="home-title-row">
        <h1 className="doc-title">챔피언 선택</h1>
        {buildCount > 0 && <BuildCountBadge count={buildCount} />}
      </div>
      <p className="lead">라인에서 만난 상대를 고르면, 그 챔피언을 이기는 상대법과 공략을 볼 수 있습니다.</p>

      <HomeInfluencers />

      {(champions || !error) && (
        <section className="section">
          <SectionHead icon={CrosshairIcon} count={champions && !(tokens.length >= 2 && filtered.length === 0) ? filtered.length : undefined}>상대 챔피언</SectionHead>
          <BuildSearch champions={champions ?? []} value={query} onChange={setQuery} />
          {champions && !(tokens.length >= 2 && filtered.length === 0) && (filtered.length === 0 ? (
            <p className="status">‘{query}’에 맞는 챔피언이 없습니다.</p>
          ) : (
            <>
              <ul className="champ-grid" id="champ-grid" ref={gridRef}>
                {shown.map((c) => (
                  <li key={c.id}>
                    <Link to={`/champion/${c.id}`} className="champ-cell">
                      <img src={c.icon} alt="" loading="lazy" width="56" height="56" />
                      <span>{c.name}</span>
                    </Link>
                  </li>
                ))}
              </ul>
              {canFold && (
                <div className="champ-more">
                  <button type="button" className="btn btn-small" aria-expanded={expanded} aria-controls="champ-grid" onClick={() => setExpanded((v) => !v)}>
                    {expanded ? '접기' : '모두 보기'}
                  </button>
                </div>
              )}
            </>
          ))}
        </section>
      )}
      {loading && <Loading />}
      {error && <ErrorBox error={error} onRetry={retry} />}
    </>
  );
}
