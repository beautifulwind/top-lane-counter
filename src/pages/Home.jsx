import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { getChampions } from '../api/ddragon';
import { matchesQuery } from '../lib/chosung';
import { useAsync } from '../lib/useAsync';
import { ErrorBox, Loading } from '../components/Status';

export default function Home() {
  const { data: champions, error, loading, retry } = useAsync(getChampions, []);
  const [query, setQuery] = useState('');

  const filtered = useMemo(
    () => (champions ?? []).filter((c) => matchesQuery(query, c.name, c.id)),
    [champions, query],
  );

  return (
    <>
      <h1 className="doc-title">상대 탑 라이너 찾기</h1>
      <p className="lead">라인에서 만난 상대를 고르면, 그 챔피언을 이기는 카운터와 공략을 볼 수 있어요.</p>

      <div className="search">
        <input
          type="search"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="챔피언 검색 (예: 다리우스, ㄷㄹㅇㅅ)"
          aria-label="챔피언 검색"
          autoComplete="off"
        />
      </div>

      {loading && <Loading />}
      {error && <ErrorBox error={error} onRetry={retry} />}
      {champions && (
        <>
          {filtered.length === 0 ? (
            <p className="status">‘{query}’에 맞는 챔피언이 없어요.</p>
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
        </>
      )}
    </>
  );
}
