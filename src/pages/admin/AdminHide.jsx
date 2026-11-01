import { useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { getChampionMap } from '../../api/ddragon';
import { getMatchup } from '../../api/content';
import { hideCounter } from '../../api/proposals';
import { useAsync } from '../../lib/useAsync';
import { ErrorBox, Loading } from '../../components/Status';
import RequireOperator from '../../components/RequireOperator';
import NotFound from '../NotFound';

/** 카운터 숨기기(승인 취소): /admin/hide/:targetId/:counterId */
export default function AdminHide() {
  return (
    <RequireOperator>
      <HideForm />
    </RequireOperator>
  );
}

function HideForm() {
  const { targetId, counterId } = useParams();
  const navigate = useNavigate();
  const { data, error, loading, retry } = useAsync(async () => {
    const [champs, matchup] = await Promise.all([getChampionMap(), getMatchup(targetId, counterId)]);
    return { champs, matchup };
  }, [targetId, counterId]);
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [actionError, setActionError] = useState(null);

  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  const target = data.champs[targetId];
  const counter = data.champs[counterId];
  if (!target || !counter || !data.matchup) return <NotFound />;
  const title = `${counter.name}(으)로 ${target.name} 잡는 법`;

  const hide = async () => {
    if (!window.confirm(`'${title}'을(를) 숨길까요? 운영자 페이지에서 다시 공개할 수 있어요.`)) return;
    setBusy(true);
    setActionError(null);
    try {
      await hideCounter(data.matchup.counter.id, reason);
      navigate('/admin', { state: { done: `숨겼어요: ${title}` } });
    } catch (e) {
      setActionError(e.message);
      setBusy(false);
    }
  };

  return (
    <article>
      <nav className="crumbs">
        <Link to="/admin">운영자 페이지</Link> › <Link to={`/champion/${targetId}/counter/${counterId}`}>{title}</Link> › 숨기기
      </nav>
      <h1 className="doc-title">카운터 숨기기 (승인 취소)</h1>
      <p className="doc-sub">{title}</p>
      <ul className="hint-list">
        <li>카운터 목록·매치업 문서·빌드가 다른 사람에게 보이지 않게 돼요. 지우지는 않아요.</li>
        <li>이 카운터를 만든 새 카운터 제안은 <strong>승인 취소</strong>가 되고, 아래 사유가 제안자의 [내 활동]에 보여요.</li>
        <li>운영자 페이지의 [숨긴 카운터]에서 언제든 다시 공개할 수 있어요. 다시 공개하면 목록 맨 뒤로 가요.</li>
      </ul>
      <section className="section review-actions">
        <label htmlFor="hide-reason">숨기는 사유 (필수, 제안자에게 보여요)</label>
        <textarea id="hide-reason" rows={3} value={reason} onChange={(e) => setReason(e.target.value)} maxLength={500} />
        <button type="button" className="btn" onClick={hide} disabled={busy || !reason.trim()}>
          {busy ? '숨기는 중…' : '숨기기'}
        </button>
        {actionError && <p className="form-error" role="alert">{actionError}</p>}
      </section>
    </article>
  );
}
