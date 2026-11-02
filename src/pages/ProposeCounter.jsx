import { useMemo, useState } from 'react';
import { Link, useNavigate, useParams, useSearchParams } from 'react-router-dom';
import { getChampions, getItems, getLatestVersion, getRunes, getSummonerSpells } from '../api/ddragon';
import { getCountersFor } from '../api/content';
import { proposeNewCounter } from '../api/proposals';
import { useAuth } from '../lib/auth';
import { matchesQuery } from '../lib/chosung';
import { buildMissing, emptyBuild } from '../lib/buildContent';
import { useAsync } from '../lib/useAsync';
import { ErrorBox, Loading } from '../components/Status';
import DocForm from '../components/DocForm';
import BuildFields from '../components/BuildFields';
import { RequireLogin } from '../components/RequireOperator';
import NotFound from './NotFound';

/** 새 카운터 제안: /champion/:id/propose (?counter=Quinn 으로 미리 고를 수 있음). 글 + 빌드 1개(필수) */
export default function ProposeCounter() {
  return (
    <RequireLogin>
      <ProposeCounterForm />
    </RequireLogin>
  );
}

function ProposeCounterForm() {
  const { id } = useParams();
  const [params] = useSearchParams();
  const auth = useAuth();
  const navigate = useNavigate();
  const { data, error, loading, retry } = useAsync(async () => {
    const [list, counters, items, runes, spells, latest] = await Promise.all([
      getChampions(), getCountersFor(id), getItems(), getRunes(), getSummonerSpells(), getLatestVersion(),
    ]);
    return { list, existing: new Set(counters.map((c) => c.counter_champion)), game: { items, runes, spells, latest } };
  }, [id]);
  const [picked, setPicked] = useState(params.get('counter'));
  const [query, setQuery] = useState('');
  const [build, setBuild] = useState(emptyBuild);

  const choices = useMemo(
    () => (data?.list ?? []).filter((c) => c.id !== id && matchesQuery(query, c.name, c.id)),
    [data, id, query],
  );

  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  const byId = Object.fromEntries(data.list.map((c) => [c.id, c]));
  const target = byId[id];
  if (!target) return <NotFound />;
  const counter = picked && picked !== id && !data.existing.has(picked) ? byId[picked] : null;

  const submit = async (content) => {
    await proposeNewCounter(auth.user.id, id, counter.id, content, build, data.game.latest);
    navigate('/me', { state: { sent: `${counter.name}(으)로 ${target.name} 잡는 법 — 새 카운터 제안을 보냈어요.` } });
  };

  return (
    <article>
      <nav className="crumbs">
        <Link to="/">홈</Link> › <Link to={`/champion/${id}`}>{target.name}</Link> › 새 카운터 제안
      </nav>
      <h1 className="doc-title">{target.name}을(를) 이기는 챔피언 제안</h1>

      <section className="section">
        <h2 className="section-title"><span className="num">1.</span> 이기는 챔피언 고르기</h2>
        {counter ? (
          <p className="picked">
            <img src={counter.icon} alt="" width="44" height="44" /> <strong>{counter.name}</strong>
            <button type="button" className="btn btn-small" onClick={() => setPicked(null)}>다시 고르기</button>
          </p>
        ) : (
          <>
            <div className="search">
              <input
                type="search"
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder="챔피언 검색 (예: 퀸, ㅋ)"
                aria-label="이기는 챔피언 검색"
                autoComplete="off"
              />
            </div>
            <ul className="champ-grid">
              {choices.map((c) => {
                const taken = data.existing.has(c.id);
                return (
                  <li key={c.id}>
                    <button
                      type="button"
                      className="champ-cell"
                      onClick={() => setPicked(c.id)}
                      disabled={taken}
                      title={taken ? '이미 등록된 카운터예요' : undefined}
                    >
                      <img src={c.icon} alt="" loading="lazy" width="56" height="56" />
                      <span>{c.name}{taken ? ' (등록됨)' : ''}</span>
                    </button>
                  </li>
                );
              })}
            </ul>
          </>
        )}
      </section>

      {counter && (
        <section className="section">
          <h2 className="section-title"><span className="num">2.</span> {counter.name}(으)로 {target.name} 잡는 법</h2>
          <DocForm onSubmit={submit} blocked={buildMissing(build, data.game)}>
            <fieldset className="pick-group build-in-doc">
              <legend>빌드 (필수)</legend>
              <p className="hint">
                새 카운터에는 빌드가 꼭 하나 있어야 해요. 승인되면 이 빌드가 카운터의 첫 빌드로 함께 공개돼요.
              </p>
              <div className="build-form">
                <BuildFields game={data.game} value={build} onChange={setBuild} author={auth.profile} />
              </div>
            </fieldset>
          </DocForm>
        </section>
      )}
    </article>
  );
}

