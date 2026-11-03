import { useMemo, useState } from 'react';
import { Link, useNavigate, useParams, useSearchParams } from 'react-router-dom';
import { getChampions } from '../api/ddragon';
import { getBuildGame } from '../api/builds';
import { getCountersFor } from '../api/content';
import { getMyProposal, proposeNewCounter } from '../api/proposals';
import { useAuth } from '../lib/auth';
import { matchesQuery } from '../lib/chosung';
import { buildMissing, buildToForm, emptyBuild } from '../lib/buildContent';
import { useAsync } from '../lib/useAsync';
import { ErrorBox, Loading } from '../components/Status';
import DocForm from '../components/DocForm';
import BuildFields from '../components/BuildFields';
import { RequireLogin } from '../components/RequireOperator';
import NotFound from './NotFound';
import { matchupTitle } from '../lib/josa';

/**
 * 카운터 등록(새 카운터 제안): /champion/:id/propose (?counter=Quinn 으로 미리 고를 수 있음). 글 + 빌드 1개(필수)
 * ?from=내 제안 id: 거절된 내 제안 [다시 쓰기] — 그 글·빌드를 채워서 새 제안으로 보낸다 (원래 제안은 그대로)
 */
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
  const fromId = Number(params.get('from')) || null;
  const { data, error, loading, retry } = useAsync(async () => {
    const [list, counters, game, mine] = await Promise.all([
      getChampions(), getCountersFor(id), getBuildGame(),
      fromId ? getMyProposal(auth.user.id, fromId) : null,
    ]);
    const from = mine?.type === 'new_counter' && mine.target_champion === id ? mine : null;
    return { list, existing: new Set(counters.map((c) => c.counter_champion)), game, from };
  }, [id, fromId, auth.user.id]);
  const [picked, setPicked] = useState(params.get('counter'));
  const [query, setQuery] = useState('');
  // 고르기 전에는 null: [다시 쓰기]면 보낸 빌드, 아니면 빈 빌드에서 시작
  const [picks, setBuild] = useState(null);
  const from = data?.from ?? null;
  const startBuild = useMemo(() => (from?.build ? buildToForm(from.build) : emptyBuild()), [from]);
  const build = picks ?? startBuild;

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
    navigate('/me', { state: { sent: `${matchupTitle(counter.name, target.name)} — 새 카운터 제안을 보냈어요.` } });
  };

  return (
    <article>
      <nav className="crumbs">
        <Link to="/">홈</Link> › <Link to={`/champion/${id}`}>{target.name}</Link> › 카운터 등록
      </nav>
      <h1 className="doc-title">{target.name} 카운터 선택</h1>

      <section className="section">
        <h2 className="section-title"><span className="num">1.</span> 카운터 고르기</h2>
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
                aria-label="카운터 챔피언 검색"
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
          <h2 className="section-title"><span className="num">2.</span> 상대법</h2>
          {from && counter.id === from.counter_champion && (
            <p className="notice" role="status">거절된 내 제안의 글과 빌드를 채워 뒀어요. 거절 사유를 보고 고쳐서 보내 주세요.</p>
          )}
          <DocForm
            key={from && counter.id === from.counter_champion ? `from-${from.id}` : 'new'}
            initial={from && counter.id === from.counter_champion ? from.content : undefined}
            onSubmit={submit}
            blocked={buildMissing(build, data.game)}
            cancelTo={`/champion/${target.id}`}
          >
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

