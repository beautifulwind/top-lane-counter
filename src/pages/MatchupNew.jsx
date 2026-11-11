import { useMemo, useState } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { getChampions } from '../api/ddragon';
import { createMatchup, getBuildGame } from '../api/builds';
import { getCountersFor } from '../api/content';
import { getMyProposal } from '../api/proposals';
import { useAuth } from '../lib/auth';
import { matchesQuery } from '../lib/chosung';
import { emptyWikiBuild, wikiBuildToForm } from '../lib/wikiBuild';
import { matchupTitle } from '../lib/josa';
import { useAsync } from '../lib/useAsync';
import { ErrorBox, Loading } from '../components/Status';
import { RequireLogin } from '../components/RequireOperator';
import WikiBuildForm from '../components/WikiBuildForm';
import SectionHead from '../components/SectionHead';
import { CrosshairIcon, SearchIcon, SwordsIcon } from '../components/Icons';

/**
 * 새 상대법 등록: /matchup/new[?target=상대 챔피언&mine=플레이할 챔피언]
 * 상대 챔피언과 플레이할 챔피언을 둘 다 고르고, 첫 빌드(공략 한 벌)를 쓴다. 등록하면 바로 공개된다 (승인 없음, 038).
 * 비회원도 등록할 수 있다.
 * ?from=내 제안 id: 승인 제도 때 거절된 새 카운터 제안의 [다시 쓰기] — 그 글·빌드를 채워 둔다 (원래 제안은 그대로)
 */
export default function MatchupNew() {
  return (
    <RequireLogin>
      <MatchupNewForm />
    </RequireLogin>
  );
}

function MatchupNewForm() {
  const [params, setParams] = useSearchParams();
  const auth = useAuth();
  const navigate = useNavigate();
  const targetId = params.get('target');
  const mineId = params.get('mine');
  const fromId = Number(params.get('from')) || null;
  const { data, error, loading, retry } = useAsync(async () => {
    const [list, game, mineProposal] = await Promise.all([
      getChampions(), getBuildGame(), fromId ? getMyProposal(auth.user.id, fromId) : null,
    ]);
    const from = mineProposal?.type === 'new_counter' ? mineProposal : null;
    return { list, game, from, byId: Object.fromEntries(list.map((c) => [c.id, c])) };
  }, [fromId, auth.user.id]);
  // 상대 챔피언을 고르면 이미 있는 상대법을 불러와 플레이할 챔피언 목록에 "(등록됨)"으로 표시
  const existing = useAsync(
    async () => (targetId ? new Set((await getCountersFor(targetId)).map((c) => c.counter_champion)) : new Set()),
    [targetId],
  );

  const pick = (key, value) => {
    const next = new URLSearchParams(params);
    if (value) next.set(key, value);
    else next.delete(key);
    setParams(next, { replace: true });
  };

  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  const target = data.byId[targetId] ?? null;
  const taken = existing.data ?? new Set();
  const mine = target && mineId !== targetId ? data.byId[mineId] ?? null : null;
  const mineTaken = !!mine && taken.has(mine.id);
  const from = data.from && target?.id === data.from.target_champion && mine?.id === data.from.counter_champion ? data.from : null;

  return (
    <article>
      <nav className="crumbs">
        <Link to="/">홈</Link> › {target ? <><Link to={`/champion/${target.id}`}>{target.name}</Link> › </> : null}새 상대법
      </nav>
      <h1 className="doc-title">새 상대법 등록</h1>
      <p className="lead">
        어떤 챔피언을 상대로 무엇을 하면 이기는지, 빌드와 함께 적어 주세요. 등록하면 바로 공개됩니다.
      </p>

      <section className="section">
        <SectionHead icon={CrosshairIcon} num={1}>상대 챔피언</SectionHead>
        <ChampPicker
          list={data.list}
          picked={target}
          label="상대 챔피언"
          onPick={(id) => {
            const next = new URLSearchParams(params);
            next.set('target', id);
            if (next.get('mine') === id) next.delete('mine');
            setParams(next, { replace: true });
          }}
          onReset={() => pick('target', null)}
        />
      </section>

      {target && (
        <section className="section">
          <SectionHead icon={SwordsIcon} num={2}>플레이할 챔피언</SectionHead>
          {existing.loading && !existing.data ? <Loading /> : existing.error ? (
            <ErrorBox error={existing.error} onRetry={existing.retry} />
          ) : (
            <ChampPicker
              list={data.list.filter((c) => c.id !== target.id)}
              picked={mine}
              label="플레이할 챔피언"
              taken={taken}
              onPick={(id) => pick('mine', id)}
              onReset={() => pick('mine', null)}
            />
          )}
          {mineTaken && (
            <div className="notice" role="status">
              <p>이미 있는 상대법입니다. 그 상대법에 새 빌드를 더해 주세요.</p>
              <div className="row-actions">
                <Link to={`/champion/${target.id}/counter/${mine.id}`} className="btn btn-small">상대법 보기</Link>
                <Link to={`/champion/${target.id}/counter/${mine.id}/build/new`} className="btn btn-small">+ 새 빌드</Link>
              </div>
            </div>
          )}
        </section>
      )}

      {target && mine && !mineTaken && (
        <section className="section">
          <SectionHead num={3}>{matchupTitle(mine.name, target.name)} — 첫 빌드</SectionHead>
          {from && <p className="notice" role="status">거절된 내 제안의 글과 빌드를 채워 뒀습니다. 고쳐서 등록해 주세요.</p>}
          <WikiBuildForm
            key={`${target.id}-${mine.id}-${from?.id ?? ''}`}
            game={data.game}
            initial={from ? { ...wikiBuildToForm({ ...(from.build ?? {}), ...from.content }), name: '' } : emptyWikiBuild()}
            author={auth.profile}
            submitLabel="상대법 등록"
            cancelTo={`/champion/${target.id}`}
            onSubmit={async (v) => {
              const made = await createMatchup(target.id, mine.id, v, data.game.latest);
              navigate(`/champion/${target.id}/counter/${mine.id}?build=${made.build_id}`, {
                state: { done: '새 상대법을 등록했습니다.' },
              });
            }}
          />
        </section>
      )}
    </article>
  );
}

/** 챔피언 고르기: 고르기 전에는 검색 + 격자, 고른 뒤에는 고른 카드 + [다시 고르기]. taken = 고를 수 없는(이미 있는) 챔피언 */
function ChampPicker({ list, picked, label, taken = null, onPick, onReset }) {
  const [query, setQuery] = useState('');
  const choices = useMemo(() => list.filter((c) => matchesQuery(query, c.name, c.id)), [list, query]);
  if (picked) {
    return (
      <div className="picked-card">
        <img src={picked.icon} alt="" width="48" height="48" />
        <span className="picked-text"><small>고른 {label}</small><strong>{picked.name}</strong></span>
        <button type="button" className="btn btn-small" onClick={onReset} aria-label={`${label} 다시 고르기`}>다시 고르기</button>
      </div>
    );
  }
  return (
    <>
      <div className="search">
        <SearchIcon size={18} className="search-icon" />
        <input
          type="search"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="챔피언 검색 (예: 퀸, ㅋ)"
          aria-label={`${label} 검색`}
          autoComplete="off"
        />
      </div>
      <ul className="champ-grid" aria-label={`${label} 고르기`}>
        {choices.map((c) => {
          const has = taken?.has(c.id);
          return (
            <li key={c.id}>
              <button
                type="button"
                className="champ-cell"
                onClick={() => onPick(c.id)}
                title={has ? '이미 있는 상대법입니다' : undefined}
              >
                <img src={c.icon} alt="" loading="lazy" width="56" height="56" />
                <span>{c.name}{has ? ' (등록됨)' : ''}</span>
              </button>
            </li>
          );
        })}
      </ul>
    </>
  );
}
