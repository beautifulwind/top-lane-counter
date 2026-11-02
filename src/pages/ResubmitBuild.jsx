import { useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { getChampionMap, getItems, getLatestVersion, getRunes, getSummonerSpells } from '../api/ddragon';
import { getMyBuild, resubmitBuild } from '../api/builds';
import { useAuth } from '../lib/auth';
import { useAsync } from '../lib/useAsync';
import { fmtDateTime } from '../lib/format';
import { buildProblem, buildToForm, patchMinor, sameBuild } from '../lib/buildContent';
import { ErrorBox, Loading } from '../components/Status';
import { RequireLogin } from '../components/RequireOperator';
import BuildFields from '../components/BuildFields';

/** 재검토 요청 받은 내 빌드를 고쳐서 다시 제출: /me/builds/:id/resubmit → 다시 승인 대기 (지금 패치로) */
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
    const [champs, build, items, runes, spells, latest] = await Promise.all([
      getChampionMap(), getMyBuild(auth.user.id, Number(id)), getItems(), getRunes(), getSummonerSpells(), getLatestVersion(),
    ]);
    return { champs, build, game: { items, runes, spells, latest } };
  }, [auth.user.id, id]);

  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  const b = data.build;
  const crumbs = <nav className="crumbs"><Link to="/me">내 활동</Link> › 빌드 다시 제출</nav>;
  if (!b || b.status !== 'revision_requested') {
    return (
      <article>
        {crumbs}
        <h1 className="doc-title">빌드 다시 제출</h1>
        <p className="empty">재검토 요청을 받은 빌드가 아니에요. 이미 다시 제출했거나, 운영자가 요청을 취소했을 수 있어요.</p>
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
  const title = c ? `${name(c.counter_champion)}(으)로 ${name(c.target_champion)} 잡는 법` : '(알 수 없는 매치업)';
  const problem = buildProblem(build, data.game);

  const submit = async (e) => {
    e.preventDefault();
    if (problem || busy) return;
    if (sameBuild(b, build)) return setError('고친 내용이 없어요. 운영자 메모를 보고 빌드를 고쳐 주세요.');
    setBusy(true);
    setError(null);
    try {
      await resubmitBuild(b.id, build, data.game.latest);
      navigate('/me', { state: { sent: `${title} — 고친 빌드를 다시 제출했어요.` } });
    } catch (err) {
      setError(err.message);
      setBusy(false);
    }
  };

  return (
    <article>
      {crumbs}
      <h1 className="doc-title">{title} — 빌드 고쳐서 다시 제출</h1>
      <div className="revision-note" role="note">
        <strong>운영자 메모</strong>
        {b.revision_requested_at && <small> ({fmtDateTime(b.revision_requested_at)})</small>}
        <p>{b.revision_note}</p>
      </div>
      <p className="lead">
        보낸 빌드가 채워져 있어요. 메모를 보고 고친 뒤 다시 제출하면 다시 승인 대기로 들어가요.
        패치 {patchMinor(data.game.latest)} 기준으로 다시 기록돼요.
      </p>
      <form className="build-form" onSubmit={submit}>
        <BuildFields game={data.game} value={build} onChange={setBuild} author={auth.profile} />
        {error && <p className="form-error" role="alert">{error}</p>}
        <div className="actions">
          <button type="submit" className="btn" disabled={!!problem || busy}>{busy ? '보내는 중…' : '다시 제출'}</button>
          <Link to="/me" className="btn">취소</Link>
        </div>
      </form>
    </article>
  );
}
