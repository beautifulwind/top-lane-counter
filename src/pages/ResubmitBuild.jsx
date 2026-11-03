import { useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { getChampionMap } from '../api/ddragon';
import { editMyBuild, getBuildGame, getMyBuild, resubmitBuild } from '../api/builds';
import { useAuth } from '../lib/auth';
import { useAsync } from '../lib/useAsync';
import { fmtDateTime } from '../lib/format';
import { buildProblem, buildToForm, patchMinor, sameBuild } from '../lib/buildContent';
import { ErrorBox, Loading } from '../components/Status';
import { RequireLogin } from '../components/RequireOperator';
import BuildFields from '../components/BuildFields';
import { matchupTitle } from '../lib/josa';

/**
 * 내 빌드 고치기: /me/builds/:id/edit (옛 주소 /me/builds/:id/resubmit는 여기로 보낸다). 고친 빌드는 지금 패치로.
 * - 승인 대기: 그대로 고친다 (edit_my_build, 대기 순서 그대로)
 * - 재검토 요청: 고쳐서 다시 제출 (resubmit_build → 다시 승인 대기)
 */
export default function ResubmitBuild() {
  return (
    <RequireLogin>
      <ResubmitBuildForm />
    </RequireLogin>
  );
}

function ResubmitBuildForm() {
  const { id } = useParams();
  const auth = useAuth();
  const { data, error, loading, retry } = useAsync(async () => {
    const [champs, build, game] = await Promise.all([
      getChampionMap(), getMyBuild(auth.user.id, Number(id)), getBuildGame(),
    ]);
    return { champs, build, game };
  }, [auth.user.id, id]);

  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  const b = data.build;
  const crumbs = (
    <nav className="crumbs">
      <Link to="/me">마이페이지</Link> › {b ? <Link to={`/me/builds/${b.id}`}>빌드 #{b.id}</Link> : '빌드'} › 고치기
    </nav>
  );
  if (!b || !['pending', 'revision_requested'].includes(b.status) || b.counter?.status !== 'approved') {
    return (
      <article>
        {crumbs}
        <h1 className="doc-title">빌드 고치기</h1>
        <p className="empty">
          지금은 고칠 수 없는 빌드예요. 승인 대기 중이거나 재검토 요청을 받은 빌드만 고칠 수 있어요.
          {b?.status === 'approved' && ' 공개된 빌드는 [이 빌드로 다시 쓰기]로 새 빌드를 보내 주세요.'}
        </p>
        {b && <div className="actions"><Link to={`/me/builds/${b.id}`} className="btn">빌드 자세히</Link></div>}
      </article>
    );
  }
  return <Editor b={b} data={data} crumbs={crumbs} />;
}

function Editor({ b, data, crumbs }) {
  const auth = useAuth();
  const navigate = useNavigate();
  const [build, setBuild] = useState(() => buildToForm(b));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const name = (cid) => data.champs[cid]?.name ?? cid;
  const c = b.counter;
  const title = c ? `${matchupTitle(name(c.counter_champion), name(c.target_champion))}` : '(알 수 없는 매치업)';
  const problem = buildProblem(build, data.game);
  const resubmit = b.status === 'revision_requested';

  const submit = async (e) => {
    e.preventDefault();
    if (problem || busy) return;
    if (sameBuild(b, build)) return setError(resubmit ? '고친 내용이 없어요. 운영자 메모를 보고 빌드를 고쳐 주세요.' : '고친 내용이 없어요.');
    setBusy(true);
    setError(null);
    try {
      if (resubmit) {
        await resubmitBuild(b.id, build, data.game.latest);
        navigate('/me', { state: { sent: `${title} — 고친 빌드를 다시 보냈어요.` } });
      } else {
        await editMyBuild(b.id, build, data.game.latest);
        navigate(`/me/builds/${b.id}`, { state: { sent: '고친 빌드를 저장했어요. 승인 대기 순서는 그대로예요.' } });
      }
    } catch (err) {
      setError(err.message);
      setBusy(false);
    }
  };

  return (
    <article>
      {crumbs}
      <h1 className="doc-title">{title} — {resubmit ? '빌드 고쳐서 다시 보내기' : '빌드 고치기'}</h1>
      {resubmit && (
        <div className="revision-note" role="note">
          <strong>운영자 메모</strong>
          {b.revision_requested_at && <small> ({fmtDateTime(b.revision_requested_at)})</small>}
          <p>{b.revision_note}</p>
        </div>
      )}
      <p className="lead">
        {resubmit
          ? '보낸 빌드가 채워져 있어요. 메모를 보고 고친 뒤 다시 보내면 다시 승인 대기로 들어가요.'
          : '승인 대기 중인 빌드예요. 고쳐서 저장하면 운영자는 고친 빌드를 보게 되고, 대기 순서는 그대로예요.'}
        {' '}패치 {patchMinor(data.game.latest)} 기준으로 다시 기록돼요.
      </p>
      <form className="build-form" onSubmit={submit}>
        <BuildFields game={data.game} value={build} onChange={setBuild} author={auth.profile} />
        {error && <p className="form-error" role="alert">{error}</p>}
        <div className="actions">
          <button type="submit" className="btn" disabled={!!problem || busy}>{busy ? (resubmit ? '보내는 중…' : '저장하는 중…') : resubmit ? '다시 보내기' : '고친 내용 저장'}</button>
          <Link to={`/me/builds/${b.id}`} className="btn">취소</Link>
        </div>
      </form>
    </article>
  );
}
