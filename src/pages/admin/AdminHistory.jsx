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
import NotFound from '../NotFound';

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
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState(null);
  const [actionError, setActionError] = useState(null);

  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  const target = data.champs[targetId];
  const counter = data.champs[counterId];
  if (!target || !counter || !data.matchup) return <NotFound />;
  const doc = data.matchup.doc;
  const total = data.revisions.length;
  const number = Object.fromEntries(data.revisions.map((r, i) => [r.id, total - i])); // 오래된 것이 1번

  const kindText = (r) =>
    r.kind === 'create' ? '처음 작성' : r.kind === 'revert' ? `되돌림 (${number[r.reverted_from] ?? '?'}번 버전으로)` : '수정 제안 승인';

  const revert = async (r) => {
    if (!window.confirm(`${number[r.id]}번 버전으로 되돌릴까요? 지금 문서는 기록에 남아요.`)) return;
    setBusy(true);
    setActionError(null);
    try {
      await revertDoc(r.id);
      setMessage(`${number[r.id]}번 버전으로 되돌렸어요.`);
      setOpen(null);
      retry();
    } catch (e) {
      setActionError(e.message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <article>
      <nav className="crumbs">
        <Link to="/admin">운영자 페이지</Link> ›{' '}
        <Link to={`/champion/${targetId}/counter/${counterId}`}>{counter.name}(으)로 {target.name} 잡는 법</Link> › 수정 기록
      </nav>
      <h1 className="doc-title">수정 기록</h1>
      {message && <p className="notice" role="status">{message}</p>}
      {actionError && <p className="form-error" role="alert">{actionError}</p>}
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
              {!isCurrent && (
                <div className="actions">
                  <button type="button" className="btn btn-small" onClick={() => setOpen(open === r.id ? null : r.id)}>
                    {open === r.id ? '비교 닫기' : '지금 문서와 비교'}
                  </button>
                  <button type="button" className="btn btn-small" onClick={() => revert(r)} disabled={busy}>
                    이 버전으로 되돌리기
                  </button>
                </div>
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
