import { useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { getChampionMap } from '../../api/ddragon';
import { deleteCounter, getDeletionCounts, getHiddenMatchup } from '../../api/proposals';
import { useAsync } from '../../lib/useAsync';
import { ErrorBox, Loading } from '../../components/Status';
import RequireOperator from '../../components/RequireOperator';
import NotFound from '../NotFound';

/** 숨긴 카운터 완전 삭제: /admin/delete/:targetId/:counterId — 챔피언 이름을 직접 입력해야 버튼이 눌린다 */
export default function AdminDelete() {
  return (
    <RequireOperator>
      <DeleteForm />
    </RequireOperator>
  );
}

function DeleteForm() {
  const { targetId, counterId } = useParams();
  const navigate = useNavigate();
  const { data, error, loading, retry } = useAsync(async () => {
    const [champs, matchup] = await Promise.all([getChampionMap(), getHiddenMatchup(targetId, counterId)]);
    const counts = matchup ? await getDeletionCounts(matchup.counter.id) : null;
    return { champs, matchup, counts };
  }, [targetId, counterId]);
  const [reason, setReason] = useState('');
  const [typed, setTyped] = useState('');
  const [busy, setBusy] = useState(false);
  const [actionError, setActionError] = useState(null);

  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  const target = data.champs[targetId];
  const counter = data.champs[counterId];
  if (!target || !counter) return <NotFound />;
  const title = `${counter.name}(으)로 ${target.name} 잡는 법`;
  const crumbs = <nav className="crumbs"><Link to="/admin">운영자 페이지</Link> › 완전 삭제</nav>;

  if (!data.matchup) {
    return (
      <article>
        {crumbs}
        <h1 className="doc-title">카운터 완전 삭제</h1>
        <p className="empty">숨긴 카운터만 삭제할 수 있어요. {title}은(는) 숨긴 카운터가 아니에요.</p>
      </article>
    );
  }
  const { counts } = data;
  const nameOk = typed.trim() === counter.name;

  const remove = async () => {
    if (!window.confirm(`'${title}'을(를) 완전히 삭제할까요? 되돌릴 수 없어요.`)) return;
    setBusy(true);
    setActionError(null);
    try {
      await deleteCounter(data.matchup.counter.id, counterId, reason);
      navigate('/admin', { state: { done: `삭제했어요: ${title}` } });
    } catch (e) {
      setActionError(e.message);
      setBusy(false);
    }
  };

  return (
    <article>
      {crumbs}
      <h1 className="doc-title">카운터 완전 삭제</h1>
      <p className="doc-sub">{title}</p>
      <p className="warn" role="note">삭제하면 되돌릴 수 없어요. 다시 살릴 가능성이 있으면 숨긴 채로 두세요.</p>
      <h2 className="section-title">함께 지워지는 것</h2>
      <ul className="hint-list" aria-label="함께 지워지는 것">
        <li>카운터와 매치업 문서</li>
        <li>문서 수정 기록 {counts.revisions}개</li>
        <li>빌드 {counts.builds}개와 따봉 {counts.votes}개</li>
        <li>이 카운터에 대한 제안 {counts.proposals}개 (제안자의 [내 활동]에서도 사라져요)</li>
        <li>숨김·공개·재검토 기록</li>
      </ul>
      <p className="hint">누가, 언제, 왜 삭제했는지와 원래 제안자는 운영자 페이지의 [삭제 기록]에 남아요.</p>

      <section className="section review-actions">
        <label htmlFor="delete-reason">삭제 사유 (필수)</label>
        <textarea id="delete-reason" rows={3} value={reason} onChange={(e) => setReason(e.target.value)} maxLength={500} />
        <label htmlFor="delete-confirm">
          확인을 위해 챔피언 이름 <strong>{counter.name}</strong>을(를) 그대로 입력해 주세요
        </label>
        <input id="delete-confirm" value={typed} onChange={(e) => setTyped(e.target.value)} autoComplete="off" />
        <button type="button" className="btn btn-danger" onClick={remove} disabled={busy || !reason.trim() || !nameOk}>
          {busy ? '삭제하는 중…' : '완전 삭제'}
        </button>
        {actionError && <p className="form-error" role="alert">{actionError}</p>}
      </section>
    </article>
  );
}
