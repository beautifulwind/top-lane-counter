import { Link, useNavigate, useParams, useSearchParams } from 'react-router-dom';
import { getChampionMap } from '../api/ddragon';
import { getMatchup } from '../api/content';
import { createBuild, getBuildGame, getBuilds, getMyBuild } from '../api/builds';
import { useAuth } from '../lib/auth';
import { useAsync } from '../lib/useAsync';
import { patchMinor } from '../lib/buildContent';
import { buildLabel, emptyWikiBuild } from '../lib/wikiBuild';
import { matchupTitle } from '../lib/josa';
import { ErrorBox, Loading } from '../components/Status';
import { RequireLogin } from '../components/RequireOperator';
import WikiBuildForm from '../components/WikiBuildForm';
import NotFound from './NotFound';

/**
 * 새 빌드: /champion/:targetId/counter/:counterId/build/new[?from=빌드 id]
 * 빈 칸에서 시작한다. from(보던 빌드·내 빌드)이 있으면 [지금 빌드 내용 가져오기]로 그 내용을 채울 수 있다.
 * 등록하면 바로 공개되고, 그 빌드를 고른 상대법 화면으로 간다. 비회원도 등록할 수 있다.
 */
export default function BuildNew() {
  return (
    <RequireLogin>
      <BuildNewForm />
    </RequireLogin>
  );
}

function BuildNewForm() {
  const { targetId, counterId } = useParams();
  const [search] = useSearchParams();
  const fromId = Number(search.get('from')) || null;
  const auth = useAuth();
  const navigate = useNavigate();
  const { data, error, loading, retry } = useAsync(async () => {
    const [champs, matchup, game] = await Promise.all([getChampionMap(), getMatchup(targetId, counterId), getBuildGame()]);
    const builds = matchup ? await getBuilds(matchup.counter.id) : [];
    let from = null;
    if (fromId) {
      const i = builds.findIndex((b) => b.id === fromId);
      if (i >= 0) from = { build: builds[i], label: `"${buildLabel(builds[i], i)}"` };
      else {
        const mine = await getMyBuild(auth.user.id, fromId);
        if (mine && mine.counter_id === matchup?.counter.id) from = { build: mine, label: '내 빌드' };
      }
    }
    return { champs, matchup, game, builds, from };
  }, [targetId, counterId, fromId, auth.user.id]);

  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  const target = data.champs[targetId];
  const counter = data.champs[counterId];
  if (!target || !counter || !data.matchup) return <NotFound />;
  const path = `/champion/${target.id}/counter/${counter.id}`;
  const title = matchupTitle(counter.name, target.name);

  return (
    <article>
      <nav className="crumbs">
        <Link to="/">홈</Link> › <Link to={`/champion/${target.id}`}>{target.name}</Link> ›{' '}
        <Link to={path}>{counter.name}</Link> › 새 빌드
      </nav>
      <h1 className="doc-title">{title} — 새 빌드</h1>
      <p className="lead">
        이 상대법에 다른 공략 한 벌을 더합니다. 등록하면 바로 공개됩니다. 패치 {patchMinor(data.game.latest)} 기준으로 등록됩니다.
      </p>
      <WikiBuildForm
        game={data.game}
        initial={emptyWikiBuild()}
        author={auth.profile}
        copyFrom={data.from}
        submitLabel="빌드 등록"
        cancelTo={data.from?.build.status === 'approved' ? `${path}?build=${data.from.build.id}` : path}
        onSubmit={async (v) => {
          const id = await createBuild(data.matchup.counter.id, v, data.game.latest);
          navigate(`${path}?build=${id}`, { state: { done: '새 빌드를 등록했습니다.' } });
        }}
      />
    </article>
  );
}
