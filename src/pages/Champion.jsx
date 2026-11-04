import { useState } from 'react';
import { Link, useLocation, useParams } from 'react-router-dom';
import { getChampionMap } from '../api/ddragon';
import { getCountersFor } from '../api/content';
import { useAsync } from '../lib/useAsync';
import { ErrorBox, Loading } from '../components/Status';
import { useAuth } from '../lib/auth';
import { hideCounter } from '../api/proposals';
import NoteForm from '../components/NoteForm';
import NotFound from './NotFound';
import { matchupTitle } from '../lib/josa';

export default function Champion() {
  const { id } = useParams();
  const { isOperator } = useAuth();
  const [hiding, setHiding] = useState(null); // 숨기기 사유 입력창을 연 카운터 id
  const location = useLocation();
  const [done, setDone] = useState(location.state?.done ?? null); // 숨긴 뒤 안내 (매치업 문서에서 숨기고 온 경우 포함)
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

      {done && <p className="notice" role="status">{done}</p>}
      <section className="section">
        <h2 className="section-title">
          <span className="num">1.</span> {target.name} 카운터
        </h2>

        {data.counters.length === 0 ? (
          <p className="empty">아직 등록된 카운터가 없습니다.</p>
        ) : (
          <ol className="counter-list">
            {data.counters.filter((c) => data.champs[c.counter_champion]).map((c, i) => {
              const champ = data.champs[c.counter_champion];
              const title = `${matchupTitle(champ.name, target.name)}`;
              return (
                <li key={c.id}>
                  <div className="counter-item">
                    <Link to={`/champion/${id}/counter/${champ.id}`} className="counter-row">
                      <span className={i < 3 ? 'rank top' : 'rank'} aria-label={`${i + 1}위`}>{i + 1}</span>
                      <img src={champ.icon} alt="" width="44" height="44" />
                      <span className="counter-text">
                        <strong>{champ.name}</strong>
                        <span>{c.summary || '공략 문서가 아직 비어 있습니다.'}</span>
                      </span>
                      <span className="chev" aria-hidden="true">›</span>
                    </Link>
                    {isOperator && (
                      <button
                        type="button"
                        className="btn btn-small btn-op row-action"
                        onClick={() => setHiding(hiding === c.id ? null : c.id)}
                        aria-expanded={hiding === c.id}
                        aria-label={`${champ.name} 숨기기`}
                      >
                        숨기기
                      </button>
                    )}
                  </div>
                  {hiding === c.id && (
                    <NoteForm
                      id={`hide-reason-${c.id}`}
                      label={`${champ.name} 숨기는 사유 (필수, 제안자에게 보입니다)`}
                      hint="숨기면 다른 사람에게 이 카운터·문서·빌드가 안 보입니다. 운영자 페이지에서 다시 공개할 수 있습니다."
                      confirmLabel="숨기기 확정"
                      busyLabel="숨기는 중…"
                      onCancel={() => setHiding(null)}
                      onSubmit={async (reason) => {
                        await hideCounter(c.id, reason);
                        setHiding(null);
                        setDone(`숨겼습니다: ${title}`);
                        retry();
                      }}
                    />
                  )}
                </li>
              );
            })}
          </ol>
        )}

        <div className="actions">
          <Link to={`/champion/${id}/propose`} className="btn">+ 카운터 등록</Link>
          {isOperator && <Link to={`/admin/order/${id}`} className="btn btn-op">순서 변경</Link>}
        </div>
      </section>
    </article>
  );
}
