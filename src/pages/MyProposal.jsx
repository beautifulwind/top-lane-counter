import { useState } from 'react';
import { Link, useLocation, useParams } from 'react-router-dom';
import { getChampionMap, getItems, getLatestVersion, getRunes, getSummonerSpells } from '../api/ddragon';
import { approvedWithEdits, getMyProposal } from '../api/proposals';
import { STATUS_LABEL, TYPE_LABEL, fmtDateTime } from '../lib/format';
import { useAuth } from '../lib/auth';
import { useAsync } from '../lib/useAsync';
import { ErrorBox, Loading } from '../components/Status';
import { RequireLogin } from '../components/RequireOperator';
import DocView from '../components/DocView';
import DiffView from '../components/DiffView';
import { matchupTitle } from '../lib/josa';

/**
 * 내 제안 자세히: /me/proposals/:id — 보낸 글·빌드 전체를 매치업 문서 모양으로.
 * 상태별: 승인 대기 [고치기] / 재검토 요청 [고쳐서 다시 제출] / 승인 [문서 보기] / 거절 [다시 쓰기] / 승인 취소 없음
 */
export default function MyProposal() {
  return (
    <RequireLogin>
      <Detail />
    </RequireLogin>
  );
}

function Detail() {
  const { id } = useParams();
  const auth = useAuth();
  const sent = useLocation().state?.sent;
  const { data, error, loading, retry } = useAsync(async () => {
    const [champs, proposal, items, runes, spells, latest] = await Promise.all([
      getChampionMap(), getMyProposal(auth.user.id, Number(id)), getItems(), getRunes(), getSummonerSpells(), getLatestVersion(),
    ]);
    return { champs, proposal, game: { items, runes, spells, latest } };
  }, [auth.user.id, id]);

  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  const p = data.proposal;
  const crumbs = <nav className="crumbs"><Link to="/me">내 활동</Link> › 제안 #{id}</nav>;
  if (!p) {
    return (
      <article>
        {crumbs}
        <h1 className="doc-title">제안 자세히</h1>
        <p className="empty">제안을 찾지 못했어요. 내가 보낸 제안만 볼 수 있어요.</p>
      </article>
    );
  }
  return <ProposalView p={p} data={data} crumbs={crumbs} sent={sent} />;
}

function ProposalView({ p, data, crumbs, sent }) {
  const name = (cid) => data.champs[cid]?.name ?? cid;
  const title = `${matchupTitle(name(p.counter_champion), name(p.target_champion))}`;
  const docPath = `/champion/${p.target_champion}/counter/${p.counter_champion}`;
  const edited = approvedWithEdits(p);
  const [shown, setShown] = useState('sent'); // 운영자가 고쳐서 승인했을 때: sent(보낸 내용) | published(공개된 내용)
  const published = shown === 'published';
  const content = published ? p.approved_content ?? p.content : p.content;
  const build = published ? p.approved_build ?? p.build : p.build;
  const isNew = p.type === 'new_counter';
  const rewriteTo = isNew
    ? `/champion/${p.target_champion}/propose?counter=${p.counter_champion}&from=${p.id}`
    : `${docPath}/edit?from=${p.id}`;

  return (
    <article>
      {crumbs}
      {sent && <p className="notice" role="status">{sent}</p>}
      <h1 className="doc-title">
        [{TYPE_LABEL[p.type]}] {title}
      </h1>
      <div className="proposal-meta">
        <span className={`status-badge ${p.status}`}>{STATUS_LABEL[p.status]}</span>
        <span>보낸 날 {fmtDateTime(p.created_at)}</span>
        {p.edited_at && p.status === 'pending' && <span>고친 때 {fmtDateTime(p.edited_at)}</span>}
        {p.resubmitted_at && <span>다시 보낸 날 {fmtDateTime(p.resubmitted_at)}</span>}
        {p.reviewed_at && <span>처리 {fmtDateTime(p.reviewed_at)}</span>}
      </div>

      {p.status === 'pending' && (
        <div className="status-box">
          <p>승인 대기 중이에요. 운영자가 처리하기 전까지는 직접 고칠 수 있어요. 고쳐도 대기 순서는 그대로예요.</p>
          <div className="actions"><Link to={`/me/proposals/${p.id}/edit`} className="btn">고치기</Link></div>
        </div>
      )}
      {p.status === 'revision_requested' && (
        <div className="revision-note">
          <p>
            <strong>재검토 요청</strong>
            {p.revision_requested_at && <small> ({fmtDateTime(p.revision_requested_at)})</small>}
          </p>
          <p>운영자 메모: {p.revision_note}</p>
          <Link to={`/me/proposals/${p.id}/edit`} className="btn btn-small">고쳐서 다시 보내기</Link>
        </div>
      )}
      {p.status === 'approved' && (
        <div className="status-box">
          {p.approve_note && <p className="approve-note">승인 메모: {p.approve_note}</p>}
          <p className="hint">승인된 제안은 고칠 수 없어요. 내용을 바꾸려면 문서에서 [문서 수정 제안]을 보내 주세요.</p>
          <div className="actions"><Link to={docPath} className="btn">문서 보기</Link></div>
        </div>
      )}
      {p.status === 'rejected' && (
        <div className="status-box">
          <p className="reject-reason">거절 사유: {p.reject_reason}</p>
          <p className="hint">보낸 내용을 채운 채로 새로 쓸 수 있어요.</p>
          <div className="actions"><Link to={rewriteTo} className="btn">다시 쓰기</Link></div>
        </div>
      )}
      {p.status === 'revoked' && (
        <p className="reject-reason">
          승인 취소 사유: {p.revoke_reason}
          {p.revoked_at && <> ({fmtDateTime(p.revoked_at)})</>}
        </p>
      )}

      {edited && (
        <div className="view-switch" role="group" aria-label="볼 내용">
          <button type="button" className="btn btn-small" aria-pressed={!published} onClick={() => setShown('sent')}>보낸 내용</button>
          <button type="button" className="btn btn-small" aria-pressed={published} onClick={() => setShown('published')}>
            공개된 내용 (운영자가 고침)
          </button>
        </div>
      )}
      {edited && p.approved_content && (
        <details className="edited-by-operator">
          <summary>운영자가 고친 부분 보기</summary>
          <DiffView before={p.content} after={p.approved_content} />
        </details>
      )}

      <DocView
        doc={content}
        builds={isNew ? (build ? [{ ...build, author: p.proposer }] : []) : null}
        game={data.game}
        emptyBuilds="이 제안에는 빌드가 없어요."
      />
    </article>
  );
}
