import { Link, useNavigate, useParams } from 'react-router-dom';
import { useState } from 'react';
import { getChampionMap, getItems, getLatestVersion, getRunes, getSummonerSpells } from '../api/ddragon';
import { getMyProposal, isHiddenCounterFlow, resubmitProposal } from '../api/proposals';
import { useAuth } from '../lib/auth';
import { useAsync } from '../lib/useAsync';
import { fmtDateTime } from '../lib/format';
import { ErrorBox, Loading } from '../components/Status';
import DocForm from '../components/DocForm';
import BuildFields from '../components/BuildFields';
import { buildMissing, buildToForm, emptyBuild, sameBuild } from '../lib/buildContent';
import { RequireLogin } from '../components/RequireOperator';

/**
 * 재검토 요청 받은 내 제안을 고쳐서 다시 제출: /me/resubmit/:id
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
    const [champs, proposal, items, runes, spells, latest] = await Promise.all([
      getChampionMap(), getMyProposal(auth.user.id, Number(id)), getItems(), getRunes(), getSummonerSpells(), getLatestVersion(),
    ]);
    return { champs, proposal, game: { items, runes, spells, latest } };
  }, [auth.user.id, id]);

  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  const p = data.proposal;
  const crumbs = <nav className="crumbs"><Link to="/me">내 활동</Link> › 다시 제출</nav>;
  if (!p || p.status !== 'revision_requested') {
    return (
      <article>
        {crumbs}
        <h1 className="doc-title">다시 제출</h1>
        <p className="empty">재검토 요청을 받은 제안이 아니에요. 이미 다시 제출했거나, 운영자가 요청을 취소했을 수 있어요.</p>
      </article>
    );
  }
  return <ResubmitEditor p={p} data={data} crumbs={crumbs} />;
}

function ResubmitEditor({ p, data, crumbs }) {
  const auth = useAuth();
  const navigate = useNavigate();
  const isNew = p.type === 'new_counter';
  const hiddenFlow = isHiddenCounterFlow(p);
  const [build, setBuild] = useState(() => (p.build ? buildToForm(p.build) : emptyBuild()));
  const name = (cid) => data.champs[cid]?.name ?? cid;
  const title = `${name(p.counter_champion)}(으)로 ${name(p.target_champion)} 잡는 법`;

  const submit = async (content) => {
    await resubmitProposal(p.id, content, isNew ? build : null, data.game.latest);
    navigate('/me', { state: { sent: `${title} — 고친 내용을 다시 제출했어요.` } });
  };

  return (
    <article>
      {crumbs}
      <h1 className="doc-title">{title} — 고쳐서 다시 제출</h1>
      <div className="revision-note" role="note">
        <strong>운영자 메모</strong>
        {p.revision_requested_at && <small> ({fmtDateTime(p.revision_requested_at)})</small>}
        <p>{p.revision_note}</p>
      </div>
      {hiddenFlow ? (
        <p className="lead">
          숨기기 전의 문서와 첫 빌드가 채워져 있어요. 메모를 보고 글이나 빌드를 고친 뒤 다시 제출해 주세요.
          빌드를 바꾸면 승인될 때 원래 첫 빌드 대신 고친 빌드가 공개돼요.
        </p>
      ) : (
        <p className="lead">
          보낸 {isNew ? '글과 빌드가' : '글이'} 채워져 있어요. 메모를 보고 고친 뒤 다시 제출하면 다시 승인 대기로 들어가요.
        </p>
      )}
      {isNew && !p.build && <p className="notice" role="status">이 제안에는 빌드가 없어요. 이제 새 카운터에는 빌드가 꼭 있어야 하니 빌드도 채워 주세요.</p>}
      <DocForm
        initial={p.content}
        onSubmit={submit}
        submitLabel="다시 제출"
        requireChange
        changedElsewhere={isNew && !sameBuild(p.build, build)}
        unchangedMessage={`고친 내용이 없어요. 운영자 메모를 보고 ${isNew ? '글이나 빌드를' : '글을'} 고쳐 주세요.`}
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
