import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { getChampions } from '../api/ddragon';
import { champMatch, tokenize } from '../lib/championSearch';
import BuildSearch from '../components/BuildSearch';
import { useAsync } from '../lib/useAsync';
import { ErrorBox, Loading } from '../components/Status';
import SectionHead from '../components/SectionHead';
import { CrosshairIcon } from '../components/Icons';

export default function Home() {
  const { data: champions, error, loading, retry } = useAsync(getChampions, []);
  const [query, setQuery] = useState('');

  const tokens = useMemo(() => tokenize(query), [query]);
  // 격자: 모든 단어가 맞는 챔피언 (이름·초성·영문·별명, 6-61). 단어가 둘 이상이면 후보 목록이 주인공이라 격자는 숨긴다
  const filtered = useMemo(
    () => (champions ?? []).filter((c) => tokens.length === 0 || champMatch(tokens, c) > 0),
    [champions, tokens],
  );

  return (
    <>
      <h1 className="doc-title">챔피언 선택</h1>
      <p className="lead">라인에서 만난 상대를 고르면, 그 챔피언을 이기는 상대법과 공략을 볼 수 있습니다.</p>

      <BuildSearch champions={champions ?? []} value={query} onChange={setQuery} />

      {loading && <Loading />}
      {error && <ErrorBox error={error} onRetry={retry} />}
      {champions && !(tokens.length >= 2 && filtered.length === 0) && (
        <section className="section">
          <SectionHead icon={CrosshairIcon} count={filtered.length}>상대 챔피언</SectionHead>
          {filtered.length === 0 ? (
            <p className="status">‘{query}’에 맞는 챔피언이 없습니다.</p>
          ) : (
            <ul className="champ-grid">
              {filtered.map((c) => (
                <li key={c.id}>
                  <Link to={`/champion/${c.id}`} className="champ-cell">
                    <img src={c.icon} alt="" loading="lazy" width="56" height="56" />
                    <span>{c.name}</span>
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </section>
      )}
    </>
  );
}
