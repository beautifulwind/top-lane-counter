import { Link, useParams } from 'react-router-dom';
import { getChampionMap } from '../api/ddragon';
import { getCountersFor } from '../api/content';
import { useAsync } from '../lib/useAsync';
import { ErrorBox, Loading, PendingButton } from '../components/Status';
import NotFound from './NotFound';

export default function Champion() {
  const { id } = useParams();
  const { data, error, loading, retry } = useAsync(
    async () => {
      const [champs, counters] = await Promise.all([getChampionMap(), getCountersFor(id)]);
      return { champs, counters };
    },
    [id],
  );

  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  const target = data.champs[id];
  if (!target) return <NotFound />;

  return (
    <article>
      <nav className="crumbs">
        <Link to="/">홈</Link> › {target.name}
      </nav>
      <header className="doc-head">
        <img src={target.icon} alt="" width="64" height="64" className="doc-head-icon" />
        <div>
          <h1 className="doc-title">{target.name}</h1>
          <p className="doc-sub">{target.title}</p>
        </div>
      </header>

      <section className="section">
        <h2 className="section-title">
          <span className="num">1.</span> {target.name}을(를) 이기는 챔피언
        </h2>
        <p className="hint">위에 있을수록 더 확실하게 이기는 카운터예요. 순서는 관리자가 정합니다.</p>

        {data.counters.length === 0 ? (
          <p className="empty">아직 등록된 카운터가 없어요. 첫 카운터를 제안해 주세요!</p>
        ) : (
          <ol className="counter-list">
            {data.counters.map((c, i) => {
              const champ = data.champs[c.counter_champion];
              if (!champ) return null;
              return (
                <li key={c.id}>
                  <Link to={`/champion/${id}/counter/${champ.id}`} className="counter-row">
                    <span className="rank">{i + 1}</span>
                    <img src={champ.icon} alt="" width="44" height="44" />
                    <span className="counter-text">
                      <strong>{champ.name}</strong>
                      <span>{c.summary || '공략 문서가 아직 비어 있어요.'}</span>
                    </span>
                    <span className="chev" aria-hidden="true">›</span>
                  </Link>
                </li>
              );
            })}
          </ol>
        )}

        <div className="actions">
          <PendingButton>+ 새 카운터 제안</PendingButton>
        </div>
      </section>
    </article>
  );
}
