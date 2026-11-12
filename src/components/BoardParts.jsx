import { useState } from 'react';
import { PHOTO_REPORT_REASONS, REPORT_REASONS, REPORT_REASON_HINTS } from '../api/board';
import { canRestore, useAuth } from '../lib/auth';
import { fmtDateTime } from '../lib/format';
import UserName from './UserName';
import NoteForm from './NoteForm';

/** 글쓴이 · 시간 · 수정됨 (탈퇴하면 "(탈퇴한 유저)") */
export function BoardByline({ row }) {
  return (
    <span className="post-meta">
      {row.author ? <UserName profile={row.author} linkTo={row.author_id} /> : <span>(탈퇴한 유저)</span>}
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
 * 그 자리에 열리는 확인 줄: "정말 지우시겠습니까? [지우기] [취소]". onConfirm이 던지면 이유를 보여 준다.
 * 열리면 [취소]에 초점이 가서(실수로 Enter를 눌러도 안 지워짐) Esc로 닫을 수 있다.
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
    <div className="confirm-inline" role="group" aria-label={question} onKeyDown={(e) => e.key === 'Escape' && !busy && onCancel()}>
      <span>{question}</span>
      <button type="button" className="btn btn-small btn-danger" onClick={confirm} disabled={busy}>{busy ? '처리하는 중…' : confirmLabel}</button>
      {/* eslint-disable-next-line jsx-a11y/no-autofocus -- 버튼을 눌러 연 확인 줄이라 바로 [취소]에 둔다 (Esc로 닫기) */}
      <button type="button" className="btn btn-small" onClick={onCancel} disabled={busy} autoFocus>취소</button>
      {error && <p className="form-error" role="alert">{error}</p>}
    </div>
  );
}

/**
 * 신고 폼: 이유 고르기(기타는 내용 필수) → [신고하기]. 같은 사람이 같은 글·댓글은 한 번만 (DB가 막는다)
 * onSubmit(reason, detail): 실패하면 던진다
 * photos=false: 사진을 붙일 수 없는 곳(문서 댓글)이라 사진 신고 사유를 뺀다
 * 상대법·빌드 오류 신고(043)도 같은 폼: reasons(키 → 이름)·hints·max(내용 글자 수)·legend·label·note를 바꿔 쓴다
 */
export function ReportForm({
  id, what, photos = true, onSubmit, onCancel,
  reasons = null, hints = REPORT_REASON_HINTS, max = 500, legend = null, label = '내용', note = '신고 내용은 운영진만 봅니다.',
}) {
  const choices = reasons ?? Object.fromEntries(Object.entries(REPORT_REASONS).filter(([key]) => photos || !PHOTO_REPORT_REASONS.includes(key)));
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
        <legend>{legend ?? `${what} 신고 — 이유를 골라 주세요`}</legend>
        {Object.entries(choices).map(([key, name]) => (
          <label key={key} className="report-reason">
            <input type="radio" name={`${id}-reason`} value={key} checked={reason === key} onChange={() => setReason(key)} />
            {name}
            {hints?.[key] && <small className="hint"> ({hints[key]})</small>}
          </label>
        ))}
      </fieldset>
      <label htmlFor={`${id}-detail`}>{reason === 'other' ? `${label} (필수)` : `${label} (선택)`}</label>
      <textarea id={`${id}-detail`} rows={2} maxLength={max} value={detail} onChange={(e) => setDetail(e.target.value)} />
      <small className="hint">{note}</small>
      <div className="note-form-actions">
        <button type="submit" className="btn btn-small btn-danger" disabled={!ready || busy}>{busy ? '보내는 중…' : '신고 보내기'}</button>
        <button type="button" className="btn btn-small" onClick={onCancel} disabled={busy}>취소</button>
      </div>
      {error && <p className="form-error" role="alert">{error}</p>}
    </form>
  );
}

/** 운영진에게만: 숨김 띠 + [다시 공개] (감독관은 다른 감독관이 숨긴 것만) */
export function HiddenBand({ row, what, onRestore, onDone }) {
  const auth = useAuth();
  const [open, setOpen] = useState(false);
  const restorable = canRestore(auth, row);
  return (
    <div className="op-band">
      <p>
        <strong>숨김</strong> · {fmtDateTime(row.hidden_at)} · 메모: {row.hidden_note}
        <br />
        <small>운영진에게만 보입니다.</small>
      </p>
      {restorable && !open && (
        <button type="button" className="btn btn-small btn-op" onClick={() => setOpen(true)}>다시 공개</button>
      )}
      {open && (
        <NoteForm
          id={`restore-${what}-${row.id}`}
          label="다시 공개 메모 (필수, 작성자에게 보입니다)"
          confirmLabel="다시 공개 확정"
          busyLabel="공개하는 중…"
          onCancel={() => setOpen(false)}
          onSubmit={async (note) => {
            await onRestore(note);
            onDone(`${what}을 다시 공개했습니다.`);
          }}
        />
      )}
    </div>
  );
}
