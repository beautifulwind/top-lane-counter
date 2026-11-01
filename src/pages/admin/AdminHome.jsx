import { useState } from 'react';
import { Link, useLocation } from 'react-router-dom';
import { getChampionMap } from '../../api/ddragon';
import {
  approveProposal, getDeletions, getHiddenCounters, getPendingProposals, rejectProposal, requestRevision, restoreCounter,
} from '../../api/proposals';
import { useAsync } from '../../lib/useAsync';
import { TYPE_LABEL, fmtDateTime } from '../../lib/format';
import { ErrorBox, Loading } from '../../components/Status';
import RequireOperator from '../../components/RequireOperator';
import UserName from '../../components/UserName';
import NoteForm from '../../components/NoteForm';

/** 운영자 페이지: 승인 대기·숨긴 카운터를 목록에서 바로 처리 (메모 입력이 확인 단계), 삭제 기록 */
export default function AdminHome() {
  return (
    <RequireOperator>
      <PendingList />
    </RequireOperator>
  );
}

function PendingList() {
  const location = useLocation();
  const [done, setDone] = useState(location.state?.done ?? null);
  const { data, error, loading, retry } = useAsync(async () => {
    const [champs, pending, hidden, deletions] = await Promise.all([
      getChampionMap(), getPendingProposals(), getHiddenCounters(), getDeletions(),
    ]);
    return { champs, pending, hidden, deletions };
  }, []);
  const name = (id) => data.champs[id]?.name ?? id;
  /** 줄에서 처리를 마치면: 안내를 띄우고 목록을 다시 불러온다 */
  const finished = (message) => {
    setDone(message);
    retry();
  };

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
              <PendingRow key={p.id} proposal={p} name={name} onDone={finished} />
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
                <HiddenRow key={c.id} counter={c} name={name} onDone={finished} />
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

/** 승인 대기 한 줄: [승인] [거절]은 그 자리에 메모 입력창, 내용은 [자세히] */
function PendingRow({ proposal: p, name, onDone }) {
  const [open, setOpen] = useState(null); // 'approve' | 'reject' | null
  const title = `${name(p.counter_champion)}(으)로 ${name(p.target_champion)} 잡는 법`;
  const label = p.resubmitted ? '재검토 후 다시 낸 제안' : TYPE_LABEL[p.type];
  const toggle = (kind) => setOpen(open === kind ? null : kind);

  return (
    <li className="proposal-row" aria-label={`[${label}] ${title}`}>
      <div className="proposal-main">
        <span className="proposal-type">{label}</span> {title}
      </div>
      <div className="proposal-meta">
        {p.proposer ? <UserName profile={p.proposer} /> : <span>(탈퇴한 유저)</span>}
        <span>{fmtDateTime(p.created_at)}</span>
      </div>
      {p.block && <p className="block-reason">{p.block} 내용을 [자세히]에서 확인해 주세요.</p>}
      <div className="row-actions">
        <button type="button" className="btn btn-small" onClick={() => toggle('approve')} disabled={!!p.block} aria-expanded={open === 'approve'}>
          승인
        </button>
        <button type="button" className="btn btn-small" onClick={() => toggle('reject')} aria-expanded={open === 'reject'}>
          거절
        </button>
        <Link to={`/admin/proposals/${p.id}`} className="btn btn-small">자세히</Link>
      </div>
      {open === 'approve' && (
        <NoteForm
          id={`approve-note-${p.id}`}
          label="승인 메모 (필수, 제안자에게 보여요)"
          hint={p.resubmitted ? '승인하면 고친 내용으로 다시 공개돼요 (목록 맨 뒤).' : undefined}
          confirmLabel="승인 확정"
          busyLabel="승인 중…"
          onCancel={() => setOpen(null)}
          onSubmit={async (note) => {
            await approveProposal(p.id, note);
            onDone(`${p.resubmitted ? '승인하고 다시 공개' : '승인'}했어요: [${label}] ${title}`);
          }}
        />
      )}
      {open === 'reject' && (
        <NoteForm
          id={`reject-note-${p.id}`}
          label="거절 사유 (필수, 제안자에게 보여요)"
          confirmLabel="거절 확정"
          busyLabel="거절 중…"
          onCancel={() => setOpen(null)}
          onSubmit={async (reason) => {
            await rejectProposal(p.id, reason);
            onDone(`거절했어요: [${label}] ${title}`);
          }}
        />
      )}
    </li>
  );
}

/** 숨긴 카운터 한 줄: [재검토 요청] [다시 공개]는 그 자리에 메모 입력창 */
function HiddenRow({ counter: c, name, onDone }) {
  const [open, setOpen] = useState(null); // 'revision' | 'restore' | null
  const title = `${name(c.counter_champion)}(으)로 ${name(c.target_champion)} 잡는 법`;
  const lastHide = c.logs.find((l) => l.action === 'hide');
  const state = originState(c.origin);
  const path = `${c.target_champion}/${c.counter_champion}`;
  const toggle = (kind) => setOpen(open === kind ? null : kind);

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

      <div className="row-actions">
        <button
          type="button"
          className="btn btn-small"
          onClick={() => toggle('revision')}
          disabled={!state.canRequest}
          aria-expanded={open === 'revision'}
        >
          재검토 요청
        </button>
        <button type="button" className="btn btn-small" onClick={() => toggle('restore')} disabled={state.waiting} aria-expanded={open === 'restore'}>
          다시 공개
        </button>
        <Link to={`/admin/preview/${path}`} className="btn btn-small">미리보기</Link>
        {state.waiting ? (
          <button type="button" className="btn btn-small" disabled title="다시 낸 제안부터 승인하거나 거절해 주세요">완전 삭제</button>
        ) : (
          <Link to={`/admin/delete/${path}`} className="btn btn-small btn-danger">완전 삭제</Link>
        )}
      </div>
      {state.waiting && <p className="hint">다시 낸 제안이 승인 대기 중이라 다시 공개·삭제는 잠겨 있어요. 그 제안부터 처리해 주세요.</p>}

      {open === 'revision' && (
        <NoteForm
          id={`revision-note-${c.id}`}
          label="재검토 요청 메모 (필수, 제안자에게 보여요)"
          confirmLabel="재검토 요청 확정"
          busyLabel="보내는 중…"
          onCancel={() => setOpen(null)}
          onSubmit={async (note) => {
            await requestRevision(c.id, note);
            onDone(`재검토를 요청했어요: ${title}`);
          }}
        />
      )}
      {open === 'restore' && (
        <NoteForm
          id={`restore-note-${c.id}`}
          label="다시 공개 메모 (필수)"
          hint={`카운터 목록 맨 뒤로 들어가요.${c.origin?.status === 'revision_requested' ? ' 보낸 재검토 요청은 취소돼요.' : ''}`}
          confirmLabel="다시 공개 확정"
          busyLabel="공개하는 중…"
          onCancel={() => setOpen(null)}
          onSubmit={async (note) => {
            await restoreCounter(c.id, note);
            onDone(`다시 공개했어요: ${title}`);
          }}
        />
      )}

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
