import { useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { getChampionMap } from '../../api/ddragon';
import { getMatchup } from '../../api/content';
import { getRevisions, revertDoc } from '../../api/proposals';
import { useAsync } from '../../lib/useAsync';
import { fmtDateTime } from '../../lib/format';
import { ErrorBox, Loading } from '../../components/Status';
import RequireOperator from '../../components/RequireOperator';
import DiffView from '../../components/DiffView';
import UserName from '../../components/UserName';
import NoteForm from '../../components/NoteForm';
import NotFound from '../NotFound';
import { matchupTitle } from '../../lib/josa';

/** 매치업 문서 수정 기록 + 예전 버전으로 되돌리기 */
export default function AdminHistory() {
  return (
    <RequireOperator>
      <History />
    </RequireOperator>
  );
}

const who = (p) => (p ? <UserName profile={p} /> : '—');

function History() {
  const { targetId, counterId } = useParams();
  const { data, error, loading, retry } = useAsync(async () => {
    const [champs, matchup] = await Promise.all([getChampionMap(), getMatchup(targetId, counterId)]);
    const revisions = matchup ? await getRevisions(matchup.counter.id) : [];
    return { champs, matchup, revisions };
  }, [targetId, counterId]);
  const [open, setOpen] = useState(null); // 비교를 펼친 버전 id
  const [reverting, setReverting] = useState(null); // 되돌리기 메모 입력창을 연 버전 id
  const [message, setMessage] = useState(null);

  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  const target = data.champs[targetId];
  const counter = data.champs[counterId];
  if (!target || !counter || !data.matchup) return <NotFound />;
  const doc = data.matchup.doc;
  const total = data.revisions.length;
  const number = Object.fromEntries(data.revisions.map((r, i) => [r.id, total - i])); // 오래된 것이 1번

  // 운영자가 고쳐서 승인한 제안: 같은 제안의 앞 줄 = 제안 원본(공개 안 됨), admin_edit 줄 = 운영자 수정
  const editedProposals = new Set(data.revisions.filter((r) => r.kind === 'admin_edit').map((r) => r.proposal_id));
  const original = (r) => r.kind !== 'admin_edit' && r.proposal_id != null && editedProposals.has(r.proposal_id);
  const kindText = (r) => {
    if (r.kind === 'admin_edit') return '운영자 수정 (제안을 고쳐서 승인)';
    if (r.kind === 'revert') return `되돌림 (${number[r.reverted_from] ?? '?'}번 버전으로)`;
    const base = r.kind === 'create' ? '처음 작성' : '수정 제안';
    return original(r) ? `${base} 원본 (공개 안 됨)` : r.kind === 'create' ? base : '수정 제안 승인';
  };

  // 메모 입력이 확인 단계: 실패하면 NoteForm이 이유를 보여 준다
  const revert = async (r, note) => {
    await revertDoc(r.id, note);
    setMessage(`${number[r.id]}번 버전으로 되돌렸어요.`);
    setOpen(null);
    setReverting(null);
    retry();
  };

  return (
    <article>
      <nav className="crumbs">
        <Link to="/admin">운영자 페이지</Link> ›{' '}
        <Link to={`/champion/${targetId}/counter/${counterId}`}>{matchupTitle(counter.name, target.name)}</Link> › 수정 기록
      </nav>
      <h1 className="doc-title">수정 기록</h1>
      {message && <p className="notice" role="status">{message}</p>}
      {total === 0 && <p className="empty">기록이 없어요.</p>}

      <ol className="revision-list">
        {data.revisions.map((r) => {
          const isCurrent = r.id === doc?.revision_id;
          return (
            <li key={r.id} className={isCurrent ? 'revision current' : 'revision'} aria-label={`${number[r.id]}번 버전`}>
              <div className="revision-head">
                <strong>{number[r.id]}번 버전</strong> · {kindText(r)}
                {isCurrent && <span className="status-badge approved">지금 문서</span>}
              </div>
              <div className="proposal-meta">
                <span>{fmtDateTime(r.created_at)}</span>
                <span>작성 {who(r.editor)}</span>
                <span>승인 {who(r.approver)}</span>
              </div>
              {r.note && <p className="approve-note">{r.kind === 'admin_edit' ? '승인 메모' : '되돌리기 메모'}: {r.note}</p>}
              {!isCurrent && (
                <div className="actions">
                  <button type="button" className="btn btn-small btn-op" onClick={() => setOpen(open === r.id ? null : r.id)}>
                    {open === r.id ? '비교 닫기' : '지금 문서와 비교'}
                  </button>
                  <button
                    type="button"
                    className="btn btn-small btn-op"
                    onClick={() => setReverting(reverting === r.id ? null : r.id)}
                    aria-expanded={reverting === r.id}
                  >
                    이 버전으로 되돌리기
                  </button>
                </div>
              )}
              {!isCurrent && reverting === r.id && (
                <NoteForm
                  id={`revert-note-${r.id}`}
                  label="되돌리기 메모 (필수, 수정 기록에 남아요)"
                  hint="지금 문서는 기록에 남아요."
                  confirmLabel="되돌리기 확정"
                  busyLabel="되돌리는 중…"
                  onCancel={() => setReverting(null)}
                  onSubmit={(note) => revert(r, note)}
                />
              )}
              {open === r.id && (
                <>
                  <p className="hint">이 버전으로 되돌리면 이렇게 바뀌어요 (지금 문서 → {number[r.id]}번 버전)</p>
                  <DiffView before={doc} after={r.content} />
                </>
              )}
            </li>
          );
        })}
      </ol>
    </article>
  );
}
