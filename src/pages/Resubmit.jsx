import { Link, useNavigate, useParams } from 'react-router-dom';
import { useState } from 'react';
import { getChampionMap } from '../api/ddragon';
import { getBuildGame } from '../api/builds';
import { editMyProposal, getMyProposal, isHiddenCounterFlow, resubmitProposal } from '../api/proposals';
import { useAuth } from '../lib/auth';
import { useAsync } from '../lib/useAsync';
import { fmtDateTime } from '../lib/format';
import { ErrorBox, Loading } from '../components/Status';
import DocForm from '../components/DocForm';
import BuildFields from '../components/BuildFields';
import { buildMissing, buildToForm, emptyBuild, sameBuild } from '../lib/buildContent';
import { RequireLogin } from '../components/RequireOperator';
import { matchupTitle } from '../lib/josa';

/**
 * 내 제안 고치기: /me/proposals/:id/edit (옛 주소 /me/resubmit/:id는 여기로 보낸다)
 * - 승인 대기: 그대로 고친다 (edit_my_proposal, 대기 순서 그대로)
 * - 재검토 요청: 고쳐서 다시 제출 (resubmit_proposal → 다시 승인 대기)
 * 새 카운터 제안은 글 + 빌드, 문서 수정 제안은 글만. 숨긴 카운터 재검토는 숨긴 시점 문서·첫 빌드에서 시작한다.
 */
export default function Resubmit() {
  return (
    <RequireLogin>
      <ResubmitForm />
    </RequireLogin>
  );
}

function ResubmitForm() {
  const { id } = useParams();
  const auth = useAuth();
  const { data, error, loading, retry } = useAsync(async () => {
    const [champs, proposal, game] = await Promise.all([
      getChampionMap(), getMyProposal(auth.user.id, Number(id)), getBuildGame(),
    ]);
    return { champs, proposal, game };
  }, [auth.user.id, id]);

  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  const p = data.proposal;
  const crumbs = (
    <nav className="crumbs">
      <Link to="/me">마이페이지</Link> › {p ? <Link to={`/me/proposals/${p.id}`}>제안 #{p.id}</Link> : '제안'} › 고치기
    </nav>
  );
  if (!p || !['pending', 'revision_requested'].includes(p.status)) {
    return (
      <article>
        {crumbs}
        <h1 className="doc-title">제안 고치기</h1>
        <p className="empty">
          지금은 고칠 수 없는 제안입니다. 승인 대기 중이거나 재검토 요청을 받은 제안만 고칠 수 있습니다.
          {p?.status === 'approved' && ' 승인된 내용을 바꾸려면 문서에서 [문서 수정 제안]을 보내 주세요.'}
        </p>
        {p && <div className="actions"><Link to={`/me/proposals/${p.id}`} className="btn">제안 자세히</Link></div>}
      </article>
    );
  }
  return <ResubmitEditor p={p} data={data} crumbs={crumbs} />;
}

function ResubmitEditor({ p, data, crumbs }) {
  const auth = useAuth();
  const navigate = useNavigate();
  const isNew = p.type === 'new_counter';
  const resubmit = p.status === 'revision_requested';
  const hiddenFlow = isHiddenCounterFlow(p);
  const [build, setBuild] = useState(() => (p.build ? buildToForm(p.build) : emptyBuild()));
  const name = (cid) => data.champs[cid]?.name ?? cid;
  const title = `${matchupTitle(name(p.counter_champion), name(p.target_champion))}`;

  const submit = async (content) => {
    if (resubmit) {
      await resubmitProposal(p.id, content, isNew ? build : null, data.game.latest);
      navigate('/me', { state: { sent: `${title} — 고친 내용을 다시 보냈습니다.` } });
    } else {
      await editMyProposal(p.id, content, isNew ? build : null, data.game.latest);
      navigate(`/me/proposals/${p.id}`, { state: { sent: '고친 내용을 저장했습니다. 승인 대기 순서는 그대로입니다.' } });
    }
  };

  return (
    <article>
      {crumbs}
      <h1 className="doc-title">{title} — {resubmit ? '고쳐서 다시 보내기' : '고치기'}</h1>
      {resubmit && (
        <div className="revision-note" role="note">
          <strong>운영자 메모</strong>
          {p.revision_requested_at && <small> ({fmtDateTime(p.revision_requested_at)})</small>}
          <p>{p.revision_note}</p>
        </div>
      )}
      {!resubmit ? (
        <p className="lead">
          승인 대기 중인 제안입니다. 보낸 {isNew ? '글과 빌드가' : '글이'} 채워져 있습니다. 고쳐서 저장하면 운영자는 고친 내용을 보게 되고,
          대기 순서는 그대로입니다.{isNew && ' 빌드를 고치면 지금 패치로 기록됩니다.'}
        </p>
      ) : hiddenFlow ? (
        <p className="lead">
          숨기기 전의 문서와 첫 빌드가 채워져 있습니다. 메모를 보고 글이나 빌드를 고친 뒤 다시 보내 주세요.
          빌드를 바꾸면 승인될 때 원래 첫 빌드 대신 고친 빌드가 공개됩니다.
        </p>
      ) : (
        <p className="lead">
          보낸 {isNew ? '글과 빌드가' : '글이'} 채워져 있습니다. 메모를 보고 고친 뒤 다시 보내면 다시 승인 대기로 들어갑니다.
        </p>
      )}
      {isNew && !p.build && <p className="notice" role="status">이 제안에는 빌드가 없습니다. 이제 새 카운터에는 빌드가 꼭 있어야 하니 빌드도 채워 주세요.</p>}
      <DocForm
        initial={p.content}
        onSubmit={submit}
        submitLabel={resubmit ? '다시 보내기' : '고친 내용 저장'}
        busyLabel={resubmit ? '보내는 중…' : '저장하는 중…'}
        cancelTo={`/me/proposals/${p.id}`}
        requireChange
        changedElsewhere={isNew && !sameBuild(p.build, build)}
        unchangedMessage={resubmit ? `고친 내용이 없습니다. 운영자 메모를 보고 ${isNew ? '글이나 빌드를' : '글을'} 고쳐 주세요.` : '고친 내용이 없습니다.'}
        blocked={isNew ? buildMissing(build, data.game) : null}
      >
        {isNew && (
          <fieldset className="pick-group build-in-doc">
            <legend>빌드 (필수)</legend>
            <div className="build-form">
              <BuildFields game={data.game} value={build} onChange={setBuild} author={auth.profile} />
            </div>
          </fieldset>
        )}
      </DocForm>
    </article>
  );
}
