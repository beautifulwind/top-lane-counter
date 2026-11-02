import { useState } from 'react';
import { Link, useNavigate, useParams, useSearchParams } from 'react-router-dom';
import { getChampionMap, getItems, getLatestVersion, getRunes, getSummonerSpells } from '../api/ddragon';
import { getMatchup } from '../api/content';
import { getMyBuild, submitBuild } from '../api/builds';
import { useAuth } from '../lib/auth';
import { useAsync } from '../lib/useAsync';
import { buildProblem, buildToForm, emptyBuild, patchMinor } from '../lib/buildContent';
import { ErrorBox, Loading } from '../components/Status';
import { RequireLogin } from '../components/RequireOperator';
import BuildFields from '../components/BuildFields';
import NotFound from './NotFound';
import { matchupTitle } from '../lib/josa';

/**
 * 빌드 등록: /champion/:targetId/counter/:counterId/build/new[?from=내 빌드 id]
 * from: [이 빌드로 다시 쓰기] — 내 빌드 내용을 채워서 새 빌드로 보낸다 (원래 빌드는 그대로).
 */
export default function ProposeBuild() {
  return (
    <RequireLogin>
      <ProposeBuildForm />
    </RequireLogin>
  );
}

function ProposeBuildForm() {
  const { targetId, counterId } = useParams();
  const [search] = useSearchParams();
  const fromId = Number(search.get('from')) || null;
  const auth = useAuth();
  const { data, error, loading, retry } = useAsync(async () => {
    const [champs, matchup, items, runes, spells, latest, from] = await Promise.all([
      getChampionMap(), getMatchup(targetId, counterId), getItems(), getRunes(), getSummonerSpells(), getLatestVersion(),
      fromId ? getMyBuild(auth.user.id, fromId) : null,
    ]);
    return { champs, matchup, items, runes, spells, latest, from };
  }, [targetId, counterId, fromId, auth.user.id]);

  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  const target = data.champs[targetId];
  const counter = data.champs[counterId];
  if (!target || !counter || !data.matchup) return <NotFound />;
  return <BuildEditor key={fromId ?? 'new'} data={data} target={target} counter={counter} fromId={fromId} />;
}

function BuildEditor({ data, target, counter, fromId }) {
  const auth = useAuth();
  const navigate = useNavigate();
  const [build, setBuild] = useState(() => (data.from ? buildToForm(data.from) : emptyBuild()));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const game = { items: data.items, runes: data.runes, spells: data.spells, latest: data.latest };
  const problem = buildProblem(build, game);
  const title = `${matchupTitle(counter.name, target.name)}`;

  const submit = async (e) => {
    e.preventDefault();
    if (problem || busy) return;
    setBusy(true);
    setError(null);
    try {
      await submitBuild(auth.user.id, data.matchup.counter.id, build, data.latest);
      navigate('/me', { state: { sent: `${title} — 빌드를 보냈어요.` } });
    } catch (err) {
      setError(err.message);
      setBusy(false);
    }
  };

  return (
    <article>
      <nav className="crumbs">
        <Link to="/">홈</Link> › <Link to={`/champion/${target.id}`}>{target.name}</Link> ›{' '}
        <Link to={`/champion/${target.id}/counter/${counter.id}`}>{counter.name}</Link> › 빌드 등록
      </nav>
      <h1 className="doc-title">{title} — 빌드 등록</h1>
      {fromId && data.from && <p className="notice" role="status">내 빌드 내용을 채워 뒀어요. 고쳐서 새 빌드로 보내요. (원래 빌드는 그대로 남아요)</p>}
      {fromId && !data.from && <p className="notice" role="status">불러올 내 빌드를 찾지 못했어요. 빈 칸에서 시작해요.</p>}
      <p className="lead">
        운영자가 승인하면 매치업 문서에 공개돼요. 패치 {patchMinor(data.latest)} 기준으로 등록돼요.
      </p>

      <form className="build-form" onSubmit={submit}>
        <BuildFields game={game} value={build} onChange={setBuild} author={auth.profile} />

        {error && <p className="form-error" role="alert">{error}</p>}
        <div className="actions">
          <button type="submit" className="btn" disabled={!!problem || busy}>
            {busy ? '보내는 중…' : '빌드 보내기'}
          </button>
          <Link to={`/champion/${target.id}/counter/${counter.id}`} className="btn">취소</Link>
        </div>
      </form>
    </article>
  );
}
