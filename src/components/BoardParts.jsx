import { useState } from 'react';
import { REPORT_REASONS } from '../api/board';
import { fmtDateTime } from '../lib/format';
import UserName from './UserName';

/** 글쓴이 · 시간 · 수정됨 (탈퇴하면 "탈퇴한 유저") */
export function BoardByline({ row }) {
  return (
    <span className="post-meta">
      {row.author ? <UserName profile={row.author} /> : <span>탈퇴한 유저</span>}
      <span>{fmtDateTime(row.created_at)}</span>
      {row.edited_at && <span className="edited" title={`${fmtDateTime(row.edited_at)}에 고침`}>수정됨</span>}
    </span>
  );
}

/** 글자 수 (넘으면 빨강) */
export function CharCount({ value, max }) {
  const n = value.trim().length;
  return <small className={n > max ? 'count over' : 'count'}>{n.toLocaleString()}/{max.toLocaleString()}</small>;
}

/**
 * 그 자리에 열리는 확인 줄: "정말 지울까요? [지우기] [취소]". onConfirm이 던지면 이유를 보여 준다.
 */
export function ConfirmInline({ question, confirmLabel, onConfirm, onCancel }) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const confirm = async () => {
    setBusy(true);
    setError(null);
    try {
      await onConfirm();
    } catch (e) {
      setError(e.message);
      setBusy(false);
    }
  };
  return (
    <div className="confirm-inline" role="group" aria-label={question}>
      <span>{question}</span>
      <button type="button" className="btn btn-small btn-danger" onClick={confirm} disabled={busy}>{busy ? '처리하는 중…' : confirmLabel}</button>
      <button type="button" className="btn btn-small" onClick={onCancel} disabled={busy}>취소</button>
      {error && <p className="form-error" role="alert">{error}</p>}
    </div>
  );
}

/**
 * 신고 폼: 이유 고르기(기타는 내용 필수) → [신고하기]. 같은 사람이 같은 글·댓글은 한 번만 (DB가 막는다)
 * onSubmit(reason, detail): 실패하면 던진다
 */
export function ReportForm({ id, what, onSubmit, onCancel }) {
  const [reason, setReason] = useState(null);
  const [detail, setDetail] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const ready = reason && (reason !== 'other' || detail.trim() !== '');

  const submit = async (e) => {
    e.preventDefault();
    if (!ready || busy) return;
    setBusy(true);
    setError(null);
    try {
      await onSubmit(reason, detail.trim());
    } catch (err) {
      setError(err.message);
      setBusy(false);
    }
  };

  return (
    <form className="report-form" onSubmit={submit} onKeyDown={(e) => e.key === 'Escape' && !busy && onCancel()}>
      <fieldset>
        <legend>{what} 신고 — 이유를 골라 주세요</legend>
        {Object.entries(REPORT_REASONS).map(([key, label]) => (
          <label key={key} className="report-reason">
            <input type="radio" name={`${id}-reason`} value={key} checked={reason === key} onChange={() => setReason(key)} />
            {label}
          </label>
        ))}
      </fieldset>
      <label htmlFor={`${id}-detail`}>{reason === 'other' ? '내용 (필수)' : '내용 (선택)'}</label>
      <textarea id={`${id}-detail`} rows={2} maxLength={500} value={detail} onChange={(e) => setDetail(e.target.value)} />
      <small className="hint">신고 내용은 운영자만 봐요.</small>
      <div className="note-form-actions">
        <button type="submit" className="btn btn-small btn-danger" disabled={!ready || busy}>{busy ? '보내는 중…' : '신고하기'}</button>
        <button type="button" className="btn btn-small" onClick={onCancel} disabled={busy}>취소</button>
      </div>
      {error && <p className="form-error" role="alert">{error}</p>}
    </form>
  );
}
