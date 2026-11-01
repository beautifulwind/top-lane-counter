import { useState } from 'react';
import { Link, useLocation } from 'react-router-dom';
import { getChampionMap } from '../../api/ddragon';
import { getHiddenCounters, getPendingProposals, restoreCounter } from '../../api/proposals';
import { useAsync } from '../../lib/useAsync';
import { TYPE_LABEL, fmtDateTime } from '../../lib/format';
import { ErrorBox, Loading } from '../../components/Status';
import RequireOperator from '../../components/RequireOperator';
import UserName from '../../components/UserName';

/** 운영자 페이지: 승인 대기 목록 (오래된 순) */
export default function AdminHome() {
  return (
    <RequireOperator>
      <PendingList />
    </RequireOperator>
  );
}

function PendingList() {
  const done = useLocation().state?.done;
  const { data, error, loading, retry } = useAsync(async () => {
    const [champs, pending, hidden] = await Promise.all([getChampionMap(), getPendingProposals(), getHiddenCounters()]);
    return { champs, pending, hidden };
  }, []);
  const name = (id) => data.champs[id]?.name ?? id;

  return (
    <article>
      <h1 className="doc-title">운영자 페이지</h1>
      {done && <p className="notice" role="status">{done}</p>}
      <p className="hint">카운터 순서 변경은 각 챔피언 문서의 [순서 변경], 문서 되돌리기는 매치업 문서의 [수정 기록]에서 해요.</p>

      <section className="section">
        <h2 className="section-title">승인 대기 {data ? `(${data.pending.length})` : ''}</h2>
        {loading && <Loading />}
        {error && <ErrorBox error={error} onRetry={retry} />}
        {data && data.pending.length === 0 && <p className="empty">대기 중인 제안이 없어요.</p>}
        {data && data.pending.length > 0 && (
          <ul className="proposal-list">
            {data.pending.map((p) => (
              <li key={p.id} className="proposal-row">
                <Link to={`/admin/proposals/${p.id}`} className="proposal-main">
                  <span className="proposal-type">{TYPE_LABEL[p.type]}</span>{' '}
                  {name(p.counter_champion)}(으)로 {name(p.target_champion)} 잡는 법
                </Link>
                <div className="proposal-meta">
                  {p.proposer ? <UserName profile={p.proposer} /> : <span>(탈퇴한 유저)</span>}
                  <span>{fmtDateTime(p.created_at)}</span>
                </div>
              </li>
            ))}
          </ul>
        )}
      </section>

      {data && (
        <section className="section">
          <h2 className="section-title">숨긴 카운터 ({data.hidden.length})</h2>
          {data.hidden.length === 0 ? (
            <p className="empty">숨긴 카운터가 없어요.</p>
          ) : (
            <ul className="proposal-list">
              {data.hidden.map((c) => (
                <HiddenRow key={c.id} counter={c} name={name} onRestored={retry} />
              ))}
            </ul>
          )}
        </section>
      )}
    </article>
  );
}

const ACTION_LABEL = { hide: '숨김', restore: '다시 공개' };

function HiddenRow({ counter: c, name, onRestored }) {
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const title = `${name(c.counter_champion)}(으)로 ${name(c.target_champion)} 잡는 법`;
  const lastHide = c.logs.find((l) => l.action === 'hide');

  const restore = async () => {
    if (!window.confirm(`'${title}'을(를) 다시 공개할까요? 카운터 목록 맨 뒤로 들어가요.`)) return;
    setBusy(true);
    setError(null);
    try {
      await restoreCounter(c.id, note.trim());
      onRestored();
    } catch (e) {
      setError(e.message);
      setBusy(false);
    }
  };

  return (
    <li className="proposal-row" aria-label={title}>
      <div className="proposal-main">{title}</div>
      {lastHide && (
        <div className="proposal-meta">
          <span>숨긴 날 {fmtDateTime(lastHide.created_at)}</span>
          <span>사유: {lastHide.reason}</span>
        </div>
      )}
      <div className="restore-form">
        <label htmlFor={`restore-note-${c.id}`}>다시 공개 메모 (선택)</label>
        <input id={`restore-note-${c.id}`} value={note} onChange={(e) => setNote(e.target.value)} maxLength={500} />
        <button type="button" className="btn btn-small" onClick={restore} disabled={busy}>
          {busy ? '공개하는 중…' : '다시 공개'}
        </button>
      </div>
      {error && <p className="form-error" role="alert">{error}</p>}
      <details>
        <summary>숨김·공개 기록 {c.logs.length}개</summary>
        <ul className="log-list">
          {c.logs.map((l) => (
            <li key={l.id}>
              {fmtDateTime(l.created_at)} · {ACTION_LABEL[l.action]} · {l.actor ? <UserName profile={l.actor} /> : '—'}
              {l.reason && <> · {l.reason}</>}
            </li>
          ))}
        </ul>
      </details>
    </li>
  );
}
