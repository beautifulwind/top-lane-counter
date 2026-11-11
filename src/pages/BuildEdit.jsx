import { useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { getChampionMap } from '../api/ddragon';
import { getMatchup } from '../api/content';
import { BUILD_CONFLICT, editBuild, getBuildCautionUps, getBuildGame, getBuilds } from '../api/builds';
import { isGuest, useAuth } from '../lib/auth';
import { useAsync } from '../lib/useAsync';
import { patchMinor } from '../lib/buildContent';
import { buildLabel, wikiBuildToForm } from '../lib/wikiBuild';
import { matchupTitle } from '../lib/josa';
import { ErrorBox, Loading } from '../components/Status';
import { RequireLogin } from '../components/RequireOperator';
import WikiBuildForm from '../components/WikiBuildForm';
import NotFound from './NotFound';

/**
 * 빌드 수정 (위키 방식): /champion/:targetId/counter/:counterId/build/:buildId/edit
 * 누구나 고칠 수 있다. 단, 남의 빌드는 구글·카카오 회원만 (DB edit_build가 막고, 화면도 미리 알려 준다).
 * 추천이 많은 빌드는 "신중히 수정해 주세요" 안내. 다른 분이 먼저 고쳤으면(TL412) [최신 내용 불러오기].
 */
export default function BuildEdit() {
  return (
    <RequireLogin>
      <BuildEditForm />
    </RequireLogin>
  );
}

function BuildEditForm() {
  const { targetId, counterId, buildId } = useParams();
  const id = Number(buildId);
  const auth = useAuth();
  const navigate = useNavigate();
  const [reloaded, setReloaded] = useState(false);
  const { data, error, loading, retry } = useAsync(async () => {
    const [champs, matchup, game, cautionUps] = await Promise.all([
      getChampionMap(), getMatchup(targetId, counterId), getBuildGame(), getBuildCautionUps(),
    ]);
    const builds = matchup ? await getBuilds(matchup.counter.id) : [];
    const index = builds.findIndex((b) => b.id === id);
    return { champs, matchup, game, cautionUps, build: builds[index] ?? null, index };
  }, [targetId, counterId, id]);

  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  const target = data.champs[targetId];
  const counter = data.champs[counterId];
  if (!target || !counter || !data.matchup) return <NotFound />;
  const path = `/champion/${target.id}/counter/${counter.id}`;
  const { build } = data;
  const label = build ? buildLabel(build, data.index) : '빌드';
  const crumbs = (
    <nav className="crumbs">
      <Link to="/">홈</Link> › <Link to={`/champion/${target.id}`}>{target.name}</Link> ›{' '}
      <Link to={path}>{counter.name}</Link> › 빌드 수정
    </nav>
  );

  if (!build) {
    return (
      <article>
        {crumbs}
        <h1 className="doc-title">빌드 수정</h1>
        <p className="empty">공개된 빌드만 수정할 수 있습니다. 숨겨졌거나 없는 빌드입니다.</p>
        <div className="actions"><Link to={path} className="btn">상대법으로 돌아가기</Link></div>
      </article>
    );
  }

  const own = build.author_id === auth.user.id;
  const guestBlocked = isGuest(auth) && !own;
  const backTo = `${path}?build=${build.id}`;

  return (
    <article>
      {crumbs}
      <h1 className="doc-title">{matchupTitle(counter.name, target.name)} — {label} 수정</h1>
      {guestBlocked ? (
        <>
          <p className="notice" role="status">
            다른 분의 빌드는 구글·카카오로 로그인한 회원만 수정할 수 있습니다. 비회원은 새 빌드를 등록하거나 내 빌드를 수정할 수 있습니다.
          </p>
          <div className="actions">
            <Link to={`${path}/build/new?from=${build.id}`} className="btn btn-primary">+ 새 빌드</Link>
            <Link to="/me" className="btn">구글·카카오 연결하기</Link>
            <Link to={backTo} className="btn">돌아가기</Link>
          </div>
        </>
      ) : (
        <>
          {reloaded && <p className="notice" role="status">최신 내용을 불러왔습니다. 다시 고쳐 주세요.</p>}
          {build.up >= data.cautionUps && (
            <p className="notice caution" role="note">많은 분이 추천한 빌드입니다. 신중히 수정해 주세요.</p>
          )}
          <p className="lead">
            고치면 바로 모두에게 보입니다. 누가 고쳤는지는 [수정 기록]에 남습니다.
            룬·아이템을 바꾸면 패치 {patchMinor(data.game.latest)} 기준으로 바뀝니다.
          </p>
          <WikiBuildForm
            key={`${build.id}-${build.version}`}
            game={data.game}
            initial={wikiBuildToForm(build)}
            unchangedFrom={wikiBuildToForm(build)}
            author={build.author}
            submitLabel="수정 저장"
            busyLabel="저장하는 중…"
            cancelTo={backTo}
            onSubmit={async (v) => {
              await editBuild(build, v, data.game.latest);
              navigate(backTo, { state: { done: '빌드를 수정했습니다.' } });
            }}
            errorExtra={(err) => err.code === BUILD_CONFLICT && (
              <div className="row-actions">
                <button type="button" className="btn btn-small" onClick={() => { setReloaded(true); retry(); }}>
                  최신 내용 불러오기
                </button>
                <small className="hint">불러오면 지금 고친 내용은 지워집니다.</small>
              </div>
            )}
          />
        </>
      )}
    </article>
  );
}
