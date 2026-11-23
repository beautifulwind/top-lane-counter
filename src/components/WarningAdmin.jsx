import { useState } from 'react';
import { WARNING_MEMO_MAX, getMemberWarnings, warnUser } from '../api/warnings';
import { fmtDateTime } from '../lib/format';
import { useAsync } from '../lib/useAsync';
import { CharCount } from './BoardParts';
import { ErrorBox, Loading } from './Status';
import { WITHDRAWN_USER } from './ModeratorAdmin';

/** 운영자 화면 상태: 확인함 / 알림만 읽음 / 아직 */
export const WARNING_STATE_LABEL = { acked: '확인함', read: '알림만 읽음', unread: '아직' };

/**
 * 운영자: 회원 정보(/admin/members/:id)의 "경고" 칸 (069, SPEC 6-86).
 * [경고 보내기] → 내용(본인에게 그대로 보임, 500자) → [경고 보내기 확정]. 활동 제한과는 따로다(함께 하려면 위 칸에서 제한도 건다).
 * 아래에 기록 목록(언제·누가·내용·상태 확인함/알림만 읽음/아직·함께 건 활동 제한). 막는 규칙(자기 자신·운영자)은 DB가 정한다.
 */
export default function WarningAdmin({ member, onDone }) {
  const [refresh, setRefresh] = useState(0);
  const { data, error, loading, retry } = useAsync(() => getMemberWarnings(member.id), [member.id, refresh]);
  const [open, setOpen] = useState(false);
  const blockedBy = member.role === 'admin' ? '운영자에게는 경고를 보낼 수 없습니다.' : null;
  return (
    <section className="section" aria-label="경고">
      <h2 className="section-title">경고</h2>
      {loading && !data && <Loading />}
      {error && (error.code === 'NOT_READY' ? <p className="hint">{error.message}</p> : <ErrorBox error={error} onRetry={retry} />)}
      {data && (
        <>
          {blockedBy && <p className="hint">{blockedBy}</p>}
          {!open && !blockedBy && (
            <div className="row-actions">
              <button type="button" className="btn btn-small btn-op" onClick={() => setOpen(true)}>경고 보내기</button>
            </div>
          )}
          {open && (
            <WarnForm
              member={member}
              onCancel={() => setOpen(false)}
              onSubmit={async (memo) => {
                const r = await warnUser(member.id, memo);
                setOpen(false);
                setRefresh((n) => n + 1);
                onDone(`${member.nickname ?? '회원'}님에게 경고를 보냈습니다.${r?.restriction_id ? ' (지금 걸려 있는 활동 제한과 함께 기록)' : ''}`);
              }}
            />
          )}
          <WarningLog rows={data} />
        </>
      )}
    </section>
  );
}

function WarnForm({ member, onSubmit, onCancel }) {
  const [memo, setMemo] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const len = memo.trim().length;
  const ready = len >= 1 && len <= WARNING_MEMO_MAX;
  const submit = async (e) => {
    e.preventDefault();
    if (!ready || busy) return;
    setBusy(true);
    setError(null);
    try {
      await onSubmit(memo.trim());
    } catch (err) {
      setError(err.message);
      setBusy(false);
    }
  };
  return (
    <form className="note-form warn-form" onSubmit={submit} onKeyDown={(e) => e.key === 'Escape' && !busy && onCancel()}>
      <label htmlFor="warn-memo">경고 내용 (필수, {member.nickname ?? '회원'}님에게 그대로 보입니다)</label>
      {/* eslint-disable-next-line jsx-a11y/no-autofocus -- [경고 보내기]를 눌러 연 칸이라 바로 쓰게 한다 */}
      <textarea id="warn-memo" rows={3} value={memo} onChange={(e) => setMemo(e.target.value)} autoFocus />
      <CharCount value={memo.trim()} max={WARNING_MEMO_MAX} />
      <small className="hint">
        받는 사람에게 알림(「운영자 경고를 받았습니다」, 내용은 알림에 넣지 않음)이 가고, 화면 위 안내 상자에 내용과 [확인했습니다]가 보입니다.
        경고만으로는 활동이 막히지 않습니다.
      </small>
      <div className="note-form-actions">
        <button type="submit" className="btn btn-small btn-op" disabled={!ready || busy}>{busy ? '보내는 중…' : '경고 보내기 확정'}</button>
        <button type="button" className="btn btn-small" onClick={onCancel} disabled={busy}>취소</button>
      </div>
      {error && <p className="form-error" role="alert">{error}</p>}
    </form>
  );
}

function WarningLog({ rows }) {
  if (rows.length === 0) return <p className="empty">받은 경고가 없습니다.</p>;
  return (
    <ul className="log-list warning-log" aria-label="경고 기록">
      {rows.map((w) => (
        <li key={w.id}>
          <strong className={`warning-state warning-state-${w.state}`}>{WARNING_STATE_LABEL[w.state] ?? w.state}</strong>
          {' · '}{fmtDateTime(w.created_at)}
          {w.state === 'acked' && <small className="hint"> (확인: {fmtDateTime(w.acked_at)})</small>}
          {w.state === 'read' && <small className="hint"> (알림 읽음: {fmtDateTime(w.notice_read_at)})</small>}
          <small className="hint">
            보낸 사람: {w.created_by || WITHDRAWN_USER}{w.restriction_id ? ` · 활동 제한과 함께 (제한 #${w.restriction_id})` : ''}
          </small>
          <p className="warning-log-memo">{w.memo}</p>
        </li>
      ))}
    </ul>
  );
}
