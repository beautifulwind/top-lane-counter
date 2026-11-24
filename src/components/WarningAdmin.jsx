import { useState } from 'react';
import { WARNING_MEMO_MAX, warnUser } from '../api/warnings';
import { fmtDateTime } from '../lib/format';
import LimitedList from './LimitedList';
import { PREVIEW_COUNT } from '../lib/adminView';
import { CharCount } from './BoardParts';
import { ErrorBox, Loading } from './Status';
import { WITHDRAWN_USER } from './ModeratorAdmin';

/** 운영자 화면 상태: 확인함 / 알림만 읽음 / 아직 */
export const WARNING_STATE_LABEL = { acked: '확인함', read: '알림만 읽음', unread: '아직' };

/**
 * 운영자: 회원 정보(/admin/members/:id)의 "경고" (069, SPEC 6-86, 1.3 패치 1-A 배치).
 * 기록은 페이지가 한 번 불러와(state) 칩·이 칸이 같이 쓴다. [경고 보내기]는 페이지의 나란한 버튼 줄에 있고,
 * 열린 칸(WarningPanel)은 그 아래, 기록 목록(WarningAdmin)은 이 칸에 있다. 활동 제한과는 따로다(함께 하려면 활동 제한도 건다).
 * 목록은 날짜·보낸 사람·확인 여부·첫 줄만, [펼치기]로 전문. 막는 규칙(자기 자신·운영자)은 DB가 정한다.
 */
export const warnBlockedBy = (member) => (member.role === 'admin' ? '운영자에게는 경고를 보낼 수 없습니다.' : null);

/** 안 확인한 경고가 있나 (칩 빨간 표시) */
export const unackedWarnings = (rows) => (rows ?? []).filter((w) => w.state !== 'acked').length;

export default function WarningAdmin({ state }) {
  const { data, error, loading, retry } = state;
  return (
    <section className="section" aria-label="경고">
      <h2 className="section-title">경고</h2>
      {loading && !data && <Loading />}
      {error && (error.code === 'NOT_READY' ? <p className="hint">{error.message}</p> : <ErrorBox error={error} onRetry={retry} />)}
      {data && <WarningLog rows={data} />}
    </section>
  );
}

/** 열린 칸: open이면 경고 내용 칸 */
export function WarningPanel({ member, open, setOpen, onChanged, onDone }) {
  if (!open) return null;
  return (
    <WarnForm
      member={member}
      onCancel={() => setOpen(false)}
      onSubmit={async (memo) => {
        const r = await warnUser(member.id, memo);
        setOpen(false);
        onChanged();
        onDone(`${member.nickname ?? '회원'}님에게 경고를 보냈습니다.${r?.restriction_id ? ' (지금 걸려 있는 활동 제한과 함께 기록)' : ''}`);
      }}
    />
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
  if (rows.length === 0) return <p className="none-line">받은 경고가 없습니다.</p>;
  return (
    <LimitedList
      items={rows} limit={PREVIEW_COUNT.logs} className="log-list warning-log" label="경고 기록"
      renderItem={(w) => <WarningItem key={w.id} w={w} />}
    />
  );
}

/** 한 줄: 날짜 · 보낸 사람 · 확인 여부 + 내용 첫 줄. [펼치기]로 전문과 확인 시각 */
function WarningItem({ w }) {
  const [open, setOpen] = useState(false);
  const firstLine = String(w.memo ?? '').split('\n')[0];
  return (
    <li>
      <span className="warning-head">
        <strong className={`warning-state warning-state-${w.state}`}>{WARNING_STATE_LABEL[w.state] ?? w.state}</strong>
        {' · '}{fmtDateTime(w.created_at)}{' · '}{w.created_by || WITHDRAWN_USER}
      </span>
      <p className={open ? 'warning-log-memo' : 'warning-log-memo warning-first'}>{open ? w.memo : firstLine}</p>
      <button type="button" className="btn btn-small" aria-expanded={open} onClick={() => setOpen((v) => !v)}>{open ? '접기' : '펼치기'}</button>
      {open && (
        <small className="hint">
          {w.state === 'acked' && `확인: ${fmtDateTime(w.acked_at)}`}
          {w.state === 'read' && `알림 읽음: ${fmtDateTime(w.notice_read_at)}`}
          {w.restriction_id ? ` 활동 제한과 함께 (제한 #${w.restriction_id})` : ''}
        </small>
      )}
    </li>
  );
}
