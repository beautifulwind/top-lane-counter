import { useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { getChampionMap } from '../../api/ddragon';
import { approveProposal, getProposalForReview, rejectProposal } from '../../api/proposals';
import { useAsync } from '../../lib/useAsync';
import { STATUS_LABEL, TYPE_LABEL, fmtDateTime } from '../../lib/format';
import { ErrorBox, Loading } from '../../components/Status';
import RequireOperator from '../../components/RequireOperator';
import DiffView from '../../components/DiffView';
import UserName from '../../components/UserName';
import NoteForm from '../../components/NoteForm';

/** 제안 하나 검토: 기존 ↔ 제안 비교, 승인 / 거절(사유 필수) */
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
  const { data, error, loading, retry } = useAsync(async () => {
    const [champs, review] = await Promise.all([getChampionMap(), getProposalForReview(Number(id))]);
    return { champs, review };
  }, [id]);
  const [open, setOpen] = useState(null); // 'approve' | 'reject' | null — 메모 입력창

  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  if (!data.review) return <p className="empty">제안을 찾지 못했어요.</p>;
  const { proposal: p, current, exists, hidden, stale, resubmitted } = data.review;
  const name = (cid) => data.champs[cid]?.name ?? cid;
  const title = `${name(p.counter_champion)}(으)로 ${name(p.target_champion)} 잡는 법`;
  const label = resubmitted ? '재검토 후 다시 낸 제안' : TYPE_LABEL[p.type];

  // 메모 입력이 확인 단계: 실패하면 NoteForm이 이유를 보여 주고 그대로 둔다
  const act = async (kind, note) => {
    if (kind === 'approve') await approveProposal(p.id, note);
    else await rejectProposal(p.id, note);
    const what = kind === 'approve' ? (resubmitted ? '승인하고 다시 공개' : '승인') : '거절';
    navigate('/admin', { state: { done: `${what}했어요: [${label}] ${title}` } });
  };
  const toggle = (kind) => setOpen(open === kind ? null : kind);

  return (
    <article>
      <nav className="crumbs"><Link to="/admin">운영자 페이지</Link> › 제안 #{p.id}</nav>
      <h1 className="doc-title">[{label}] {title}</h1>
      <p className="proposal-meta">
        {p.proposer ? <UserName profile={p.proposer} /> : <span>(탈퇴한 유저)</span>}
        <span>{fmtDateTime(p.created_at)}</span>
        <span className={`status-badge ${p.status}`}>{STATUS_LABEL[p.status]}</span>
      </p>

      {hidden && p.status === 'pending' && (
        <p className="warn" role="alert">
          {p.type === 'new_counter'
            ? '운영자가 숨긴 카운터예요. 살리려면 운영자 페이지의 [다시 공개]를 쓰고, 이 제안은 거절해 주세요.'
            : '숨긴 카운터의 제안이에요. 승인할 수 없으니 거절해 주세요.'}
        </p>
      )}
      {resubmitted && p.status === 'pending' && (
        <div className="revision-note" role="note">
          <p>숨긴 카운터의 제안자가 재검토 요청을 받고 고쳐서 다시 낸 제안이에요. <strong>승인하면 고친 내용으로 다시 공개</strong>되고(목록 맨 뒤), 거절하면 계속 숨김이에요.</p>
          <p>보낸 재검토 메모: {p.revision_note}</p>
        </div>
      )}
      {p.type === 'new_counter' && exists && p.status === 'pending' && (
        <p className="warn" role="alert">이미 같은 카운터가 공개돼 있어요. 승인할 수 없으니 거절해 주세요.</p>
      )}
      {stale && (
        <p className="warn" role="alert">
          이 제안을 쓴 뒤에 문서가 다른 승인으로 바뀌었어요. 아래 비교는 <strong>지금 문서</strong> 기준이라, 승인하면 그 사이 바뀐 내용이 덮어써질 수 있어요.
        </p>
      )}

      <section className="section">
        <h2 className="section-title">
          {resubmitted ? '바뀐 부분 (숨긴 문서 → 고친 내용)' : p.type === 'new_counter' ? '제안한 문서 내용' : '바뀐 부분 (지금 문서 → 제안)'}
        </h2>
        <DiffView before={p.type === 'doc_edit' || resubmitted ? current : null} after={p.content} />
      </section>

      {p.status === 'pending' ? (
        <section className="section">
          <div className="row-actions">
            <button
              type="button"
              className="btn"
              onClick={() => toggle('approve')}
              disabled={hidden || (p.type === 'new_counter' && exists)}
              aria-expanded={open === 'approve'}
            >
              승인
            </button>
            <button type="button" className="btn" onClick={() => toggle('reject')} aria-expanded={open === 'reject'}>
              거절
            </button>
          </div>
          {open === 'approve' && (
            <NoteForm
              id="approve-note"
              label="승인 메모 (필수, 제안자에게 보여요)"
              hint={resubmitted ? '승인하면 고친 내용으로 다시 공개돼요 (목록 맨 뒤).' : undefined}
              confirmLabel="승인 확정"
              busyLabel="승인 중…"
              onCancel={() => setOpen(null)}
              onSubmit={(note) => act('approve', note)}
            />
          )}
          {open === 'reject' && (
            <NoteForm
              id="reject-note"
              label="거절 사유 (필수, 제안자에게 보여요)"
              confirmLabel="거절 확정"
              busyLabel="거절 중…"
              onCancel={() => setOpen(null)}
              onSubmit={(note) => act('reject', note)}
            />
          )}
        </section>
      ) : (
        <>
          {p.status === 'approved' && p.approve_note && <p className="approve-note">승인 메모: {p.approve_note}</p>}
          {p.reject_reason && <p className="reject-reason">거절 사유: {p.reject_reason}</p>}
          {p.status === 'revoked' && <p className="reject-reason">승인 취소 사유: {p.revoke_reason} ({fmtDateTime(p.revoked_at)})</p>}
        </>
      )}
    </article>
  );
}
