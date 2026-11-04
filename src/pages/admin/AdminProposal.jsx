import { useState } from 'react';
import { Link, useNavigate, useParams, useSearchParams } from 'react-router-dom';
import { getChampionMap } from '../../api/ddragon';
import { getBuildGame } from '../../api/builds';
import {
  approveProposal, approvedWithEdits, cancelProposalRevision, getProposalForReview, isHiddenCounterFlow, rejectProposal,
  requestProposalRevision,
} from '../../api/proposals';
import { useAsync } from '../../lib/useAsync';
import { STATUS_LABEL, TYPE_LABEL, fmtDateTime } from '../../lib/format';
import { ErrorBox, Loading } from '../../components/Status';
import RequireOperator from '../../components/RequireOperator';
import DiffView from '../../components/DiffView';
import UserName from '../../components/UserName';
import NoteForm from '../../components/NoteForm';
import BuildCard from '../../components/BuildCard';
import ApproveEditor from '../../components/ApproveEditor';
import { EditedBadge, useAuthorChanged } from '../../components/AuthorChanged';
import { proposalBuildBlock, sameBuild } from '../../lib/buildContent';
import { matchupTitle } from '../../lib/josa';

/** 제안 하나 검토: 기존 ↔ 제안 비교, [승인](고쳐서 승인 가능) / [재검토 요청] / [거절] — 모두 메모 필수. ?approve=1이면 [승인]을 연 채로 */
export default function AdminProposal() {
  return (
    <RequireOperator>
      <Review />
    </RequireOperator>
  );
}

function Review() {
  const { id } = useParams();
  const navigate = useNavigate();
  const [search] = useSearchParams();
  const { data, error, loading, retry } = useAsync(async () => {
    const [champs, review, game] = await Promise.all([
      getChampionMap(), getProposalForReview(Number(id)), getBuildGame(),
    ]);
    return { champs, review, game };
  }, [id]);
  // 'approve'(고쳐서 승인 편집기) | 'revision' | 'reject' | 'cancel' | null — 목록 줄의 [내용 고치기]로 오면 [승인]이 열려 있다
  const [open, setOpen] = useState(search.get('approve') ? 'approve' : null);
  const { guard, notice } = useAuthorChanged(retry);

  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  if (!data.review) return <p className="empty">제안을 찾지 못했습니다.</p>;
  const { proposal: p, current, exists, hidden, stale, resubmitted, firstBuild } = data.review;
  const isNew = p.type === 'new_counter';
  const noBuild = isNew && !p.build;
  const buildWarn = isNew && p.build ? proposalBuildBlock(p.build, data.game) : null;
  const buildChanged = resubmitted && !sameBuild(firstBuild, p.build);
  const card = (b, extra = {}) => <BuildCard build={{ ...b, author: p.proposer, ...extra }} {...data.game} />;
  const name = (cid) => data.champs[cid]?.name ?? cid;
  const title = `${matchupTitle(name(p.counter_champion), name(p.target_champion))}`;
  const label = resubmitted ? '재검토 후 다시 낸 제안' : TYPE_LABEL[p.type];

  const hiddenFlow = isHiddenCounterFlow(p);
  const cannotApprove = hidden || (p.type === 'new_counter' && exists) || noBuild;
  const done = (what) => navigate('/admin', { state: { done: `${what}: [${label}] ${title}` } });
  // 메모 입력이 확인 단계: 실패하면 NoteForm이 이유를 보여 주고 그대로 둔다
  const approve = guard(async ({ note, content, build }) => {
    await approveProposal(p, note, { content, build, patch: data.game.latest });
    const how = content || build ? '고쳐서 ' : '';
    done(resubmitted ? `${how}승인하고 다시 공개했습니다` : `${how}승인했습니다`);
  });
  const toggle = (kind) => setOpen(open === kind ? null : kind);

  return (
    <article>
      <nav className="crumbs"><Link to="/admin">운영자 페이지</Link> › 제안 #{p.id}</nav>
      <h1 className="doc-title">[{label}] {title}</h1>
      <p className="proposal-meta">
        {p.proposer ? <UserName profile={p.proposer} /> : <span>(탈퇴한 유저)</span>}
        <span>{fmtDateTime(p.created_at)}</span>
        <span className={`status-badge ${p.status}`}>{STATUS_LABEL[p.status]}</span>
        <EditedBadge row={p} />
      </p>

      {hidden && p.status === 'pending' && (
        <p className="warn" role="alert">
          {p.type === 'new_counter'
            ? '운영자가 숨긴 카운터입니다. 살리려면 운영자 페이지의 [다시 공개]를 쓰고, 이 제안은 거절해 주세요.'
            : '숨긴 카운터의 제안입니다. 승인할 수 없으니 거절해 주세요.'}
        </p>
      )}
      {resubmitted && p.status === 'pending' && (
        <div className="revision-note" role="note">
          <p>숨긴 카운터의 제안자가 재검토 요청을 받고 고쳐서 다시 낸 제안입니다. <strong>승인하면 고친 내용으로 다시 공개</strong>되고(목록 맨 뒤), 거절하면 계속 숨김입니다.</p>
          <p>보낸 재검토 메모: {p.revision_note}</p>
        </div>
      )}
      {p.type === 'new_counter' && exists && p.status === 'pending' && (
        <p className="warn" role="alert">이미 같은 카운터가 공개돼 있습니다. 승인할 수 없으니 거절해 주세요.</p>
      )}
      {noBuild && p.status === 'pending' && (
        <p className="warn" role="alert">빌드가 없는 새 카운터 제안입니다. 새 카운터에는 빌드가 꼭 있어야 해서 승인할 수 없습니다. 거절해 주세요.</p>
      )}
      {buildWarn && p.status === 'pending' && <p className="warn" role="alert">{buildWarn} 아래 빌드를 확인하고 승인해 주세요.</p>}
      {stale && (
        <p className="warn" role="alert">
          이 제안을 쓴 뒤에 문서가 다른 승인으로 바뀌었습니다. 아래 비교는 <strong>지금 문서</strong> 기준이라, 승인하면 그 사이 바뀐 내용이 덮어써질 수 있습니다.
        </p>
      )}

      <section className="section">
        <h2 className="section-title">
          {resubmitted ? '바뀐 부분 (숨긴 문서 → 고친 내용)' : p.type === 'new_counter' ? '제안한 문서 내용' : '바뀐 부분 (지금 문서 → 제안)'}
        </h2>
        <DiffView before={p.type === 'doc_edit' || resubmitted ? current : null} after={p.content} />
      </section>

      {isNew && p.build && (
        <section className="section">
          {!resubmitted && (
            <>
              <h2 className="section-title">함께 공개될 첫 빌드</h2>
              <p className="hint">승인하면 카운터와 함께 이 빌드가 공개되고, 거절하면 같이 거절됩니다.</p>
              {card(p.build)}
            </>
          )}
          {resubmitted && !buildChanged && (
            <>
              <h2 className="section-title">첫 빌드 (그대로)</h2>
              <p className="hint">빌드는 고치지 않았습니다. 승인하면 원래 첫 빌드가 그대로 공개됩니다.</p>
              {card(p.build)}
            </>
          )}
          {resubmitted && buildChanged && (
            <>
              <h2 className="section-title">바뀐 빌드 (원래 첫 빌드 → 고친 빌드)</h2>
              <p className="hint">승인하면 원래 첫 빌드는 숨기고("재검토로 교체"), 고친 빌드를 공개합니다. 원래 빌드의 추천 수는 숨긴 빌드에 남습니다.</p>
              <div className="build-compare">
                <div>
                  <h3>원래 첫 빌드</h3>
                  {firstBuild ? card(firstBuild, { up: firstBuild.up_count, down: firstBuild.down_count }) : <p className="empty">원래 첫 빌드가 없습니다.</p>}
                </div>
                <div>
                  <h3>고친 빌드</h3>
                  {card(p.build)}
                </div>
              </div>
            </>
          )}
        </section>
      )}

      {approvedWithEdits(p) && <EditedByOperator p={p} card={card} />}

      {p.status === 'pending' && (
        <section className="section">
          {notice}
          <div className="row-actions">
            <button type="button" className="btn btn-op" onClick={() => toggle('approve')} disabled={cannotApprove} aria-expanded={open === 'approve'}>
              승인
            </button>
            <button type="button" className="btn btn-op" onClick={() => toggle('revision')} aria-expanded={open === 'revision'}>
              재검토 요청
            </button>
            <button type="button" className="btn btn-op" onClick={() => toggle('reject')} aria-expanded={open === 'reject'}>
              거절
            </button>
          </div>
          {open === 'approve' && !cannotApprove && (
            <ApproveEditor
              doc={p.content}
              build={isNew ? p.build : null}
              game={data.game}
              author={p.proposer}
              noteLabel="승인 메모 (필수, 제안자에게 보입니다)"
              hint={resubmitted ? '승인하면 고친 내용으로 다시 공개됩니다 (목록 맨 뒤).' : undefined}
              onCancel={() => setOpen(null)}
              onSubmit={approve}
            />
          )}
          {open === 'revision' && (
            <NoteForm
              id="revision-note"
              label="재검토 요청 메모 (필수, 제안자에게 보입니다)"
              hint="제안자가 [마이페이지]에서 고쳐서 다시 내면 승인 대기로 돌아옵니다."
              confirmLabel="재검토 요청 확정"
              busyLabel="보내는 중…"
              onCancel={() => setOpen(null)}
              onSubmit={guard(async (note) => {
                await requestProposalRevision(p, note);
                done('재검토를 요청했습니다');
              })}
            />
          )}
          {open === 'reject' && (
            <NoteForm
              id="reject-note"
              label="거절 사유 (필수, 제안자에게 보입니다)"
              confirmLabel="거절 확정"
              busyLabel="거절 중…"
              onCancel={() => setOpen(null)}
              onSubmit={guard(async (note) => {
                await rejectProposal(p, note);
                done('거절했습니다');
              })}
            />
          )}
        </section>
      )}

      {p.status === 'revision_requested' && (
        <section className="section">
          <div className="revision-note" role="note">
            <p><strong>재검토 요청 중</strong> — 제안자가 고쳐서 다시 내기를 기다리고 있습니다.{p.revision_requested_at && <small> ({fmtDateTime(p.revision_requested_at)})</small>}</p>
            <p>보낸 메모: {p.revision_note}</p>
          </div>
          {hiddenFlow ? (
            <p className="hint">숨긴 카운터의 재검토 요청입니다. 취소하려면 운영자 페이지 "숨긴 카운터"의 [다시 공개]를 써 주세요.</p>
          ) : (
            <>
              <div className="row-actions">
                <button type="button" className="btn btn-op" onClick={() => toggle('cancel')} aria-expanded={open === 'cancel'}>요청 취소</button>
                <button type="button" className="btn btn-op" onClick={() => toggle('reject')} aria-expanded={open === 'reject'}>거절</button>
              </div>
              {open === 'cancel' && (
                <NoteForm
                  id="cancel-note"
                  label="요청 취소 메모 (필수, 제안자에게 보입니다)"
                  hint="원래 제안 그대로 승인 대기로 돌아갑니다."
                  confirmLabel="요청 취소 확정"
                  busyLabel="취소하는 중…"
                  onCancel={() => setOpen(null)}
                  onSubmit={async (note) => {
                    await cancelProposalRevision(p.id, note);
                    done('재검토 요청을 취소했습니다');
                  }}
                />
              )}
              {open === 'reject' && (
                <NoteForm
                  id="reject-note"
                  label="거절 사유 (필수, 제안자에게 보입니다)"
                  confirmLabel="거절 확정"
                  busyLabel="거절 중…"
                  onCancel={() => setOpen(null)}
                  onSubmit={async (note) => {
                    await rejectProposal(p, note);
                    done('거절했습니다');
                  }}
                />
              )}
            </>
          )}
        </section>
      )}

      {!['pending', 'revision_requested'].includes(p.status) && (
        <>
          {p.status === 'approved' && p.approve_note && <p className="approve-note">승인 메모: {p.approve_note}</p>}
          {p.reject_reason && <p className="reject-reason">거절 사유: {p.reject_reason}</p>}
          {p.status === 'revoked' && <p className="reject-reason">승인 취소 사유: {p.revoke_reason} ({fmtDateTime(p.revoked_at)})</p>}
        </>
      )}
    </article>
  );
}

/** 운영자가 고쳐서 승인한 제안: 원래 제안 → 고친 내용 (제안자 /me와 같은 비교) */
export function EditedByOperator({ p, card }) {
  return (
    <section className="section edited-by-operator">
      <h2 className="section-title">운영자가 고쳐서 승인했습니다 (원래 제안 → 고친 내용)</h2>
      {p.approved_content && <DiffView before={p.content} after={p.approved_content} />}
      {p.approved_build && (
        <div className="build-compare">
          <div>
            <h3>원래 제안한 빌드</h3>
            {card(p.build)}
          </div>
          <div>
            <h3>고친 빌드</h3>
            {card(p.approved_build)}
          </div>
        </div>
      )}
    </section>
  );
}
