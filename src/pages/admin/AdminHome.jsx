import { useState } from 'react';
import { Link, useLocation } from 'react-router-dom';
import { getChampionMap } from '../../api/ddragon';
import { getDeletions, getHiddenCounters, getPendingProposals, isResubmission, requestRevision, restoreCounter } from '../../api/proposals';
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
    const [champs, pending, hidden, deletions] = await Promise.all([
      getChampionMap(), getPendingProposals(), getHiddenCounters(), getDeletions(),
    ]);
    return { champs, pending, hidden, deletions };
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
                  <span className="proposal-type">{isResubmission(p) ? '재검토 후 다시 낸 제안' : TYPE_LABEL[p.type]}</span>{' '}
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
                <HiddenRow key={c.id} counter={c} name={name} onChanged={retry} />
              ))}
            </ul>
          )}
        </section>
      )}

      {data && (
        <section className="section">
          <h2 className="section-title">삭제 기록 ({data.deletions.length})</h2>
          {data.deletions.length === 0 ? (
            <p className="empty">삭제한 카운터가 없어요.</p>
          ) : (
            <ul className="proposal-list">
              {data.deletions.map((d) => (
                <li key={d.id} className="proposal-row">
                  <div className="proposal-main">{name(d.counter_champion)}(으)로 {name(d.target_champion)} 잡는 법</div>
                  <div className="proposal-meta">
                    <span>{fmtDateTime(d.deleted_at)}</span>
                    <span>삭제: {d.deleter ? <UserName profile={d.deleter} /> : '—'}</span>
                    <span>원래 제안자: {d.proposer ? <UserName profile={d.proposer} /> : '없음(초기 데이터)'}</span>
                  </div>
                  <p className="reject-reason">사유: {d.reason}</p>
                  <small className="hint">
                    지운 것: 제안 {d.proposals_count} · 수정 기록 {d.revisions_count} · 빌드 {d.builds_count} · 따봉 {d.votes_count}
                  </small>
                </li>
              ))}
            </ul>
          )}
        </section>
      )}
    </article>
  );
}

const ACTION_LABEL = {
  hide: '숨김', restore: '다시 공개', revision_request: '재검토 요청', resubmit: '다시 제출', reject: '다시 낸 제안 거절',
};

/** 숨긴 카운터의 원래 제안 상태 → 운영자에게 보여 줄 문구 */
function originState(origin) {
  if (!origin) return { text: '제안 없이 생긴 카운터 (재검토 요청 불가)', canRequest: false, waiting: false };
  if (origin.status === 'revision_requested') return { text: '재검토 요청 중 (제안자 수정 대기)', canRequest: false, waiting: false };
  if (origin.status === 'pending') return { text: '다시 제출됨 (승인 대기 목록에 있음)', canRequest: false, waiting: true };
  if (origin.status === 'rejected') return { text: '다시 낸 제안을 거절함 (재검토 다시 요청 가능)', canRequest: true, waiting: false };
  return { text: null, canRequest: origin.status === 'revoked', waiting: false };
}

function HiddenRow({ counter: c, name, onChanged }) {
  const [note, setNote] = useState('');
  const [revisionNote, setRevisionNote] = useState('');
  const [asking, setAsking] = useState(false);
  const [busy, setBusy] = useState(null);
  const [error, setError] = useState(null);
  const title = `${name(c.counter_champion)}(으)로 ${name(c.target_champion)} 잡는 법`;
  const lastHide = c.logs.find((l) => l.action === 'hide');
  const state = originState(c.origin);
  const path = `${c.target_champion}/${c.counter_champion}`;

  const act = async (kind, question, call) => {
    if (!window.confirm(question)) return;
    setBusy(kind);
    setError(null);
    try {
      await call();
      onChanged();
    } catch (e) {
      setError(e.message);
      setBusy(null);
    }
  };
  const restore = () =>
    act('restore', `'${title}'을(를) 다시 공개할까요? 카운터 목록 맨 뒤로 들어가요.`
      + (c.origin?.status === 'revision_requested' ? ' 보낸 재검토 요청은 취소돼요.' : ''),
    () => restoreCounter(c.id, note.trim()));
  const ask = () =>
    act('revision', `'${title}'의 제안자에게 재검토를 요청할까요?`, () => requestRevision(c.id, revisionNote.trim()));

  return (
    <li className="proposal-row" aria-label={title}>
      <div className="proposal-main">{title}</div>
      {lastHide && (
        <div className="proposal-meta">
          <span>숨긴 날 {fmtDateTime(lastHide.created_at)}</span>
          <span>사유: {lastHide.reason}</span>
        </div>
      )}
      {c.origin?.proposer && (
        <div className="proposal-meta">
          <span>제안자: <UserName profile={c.origin.proposer} /></span>
        </div>
      )}
      {state.text && (
        <p className="hidden-state">
          {state.waiting ? <Link to={`/admin/proposals/${c.origin.id}`}>{state.text}</Link> : state.text}
        </p>
      )}

      <div className="hidden-actions">
        <Link to={`/admin/preview/${path}`} className="btn btn-small">미리보기</Link>
        <button
          type="button"
          className="btn btn-small"
          onClick={() => setAsking((v) => !v)}
          disabled={!state.canRequest || busy !== null}
          aria-expanded={asking}
        >
          재검토 요청
        </button>
        {state.waiting ? (
          <button type="button" className="btn btn-small" disabled title="다시 낸 제안부터 승인하거나 거절해 주세요">완전 삭제</button>
        ) : (
          <Link to={`/admin/delete/${path}`} className="btn btn-small btn-danger">완전 삭제</Link>
        )}
      </div>

      {asking && state.canRequest && (
        <div className="restore-form">
          <label htmlFor={`revision-note-${c.id}`}>재검토 요청 메모 (필수, 제안자에게 보여요)</label>
          <textarea id={`revision-note-${c.id}`} rows={3} value={revisionNote} onChange={(e) => setRevisionNote(e.target.value)} maxLength={500} />
          <button type="button" className="btn btn-small" onClick={ask} disabled={busy !== null || !revisionNote.trim()}>
            {busy === 'revision' ? '보내는 중…' : '재검토 요청 보내기'}
          </button>
        </div>
      )}

      <div className="restore-form">
        <label htmlFor={`restore-note-${c.id}`}>다시 공개 메모 (선택)</label>
        <input id={`restore-note-${c.id}`} value={note} onChange={(e) => setNote(e.target.value)} maxLength={500} />
        <button type="button" className="btn btn-small" onClick={restore} disabled={busy !== null || state.waiting}>
          {busy === 'restore' ? '공개하는 중…' : '다시 공개'}
        </button>
      </div>
      {state.waiting && <p className="hint">다시 낸 제안이 승인 대기 중이라 다시 공개·삭제는 잠겨 있어요. 그 제안부터 처리해 주세요.</p>}
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
