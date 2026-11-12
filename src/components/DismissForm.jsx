import { useState } from 'react';

/** 신고 기각: 메모는 선택 (작성자·신고자에게 가지 않고 기록만) */
export function DismissForm({ id, onSubmit, onCancel }) {
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const submit = async (e) => {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await onSubmit(note.trim());
    } catch (err) {
      setError(err.message);
      setBusy(false);
    }
  };
  return (
    <form className="note-form" onSubmit={submit} onKeyDown={(e) => e.key === 'Escape' && !busy && onCancel()}>
      <label htmlFor={id}>기각 메모 (선택, 기록용 — 아무에게도 알림이 가지 않습니다)</label>
      <textarea id={id} rows={2} maxLength={500} value={note} onChange={(e) => setNote(e.target.value)} />
      <div className="note-form-actions">
        <button type="submit" className="btn btn-small btn-op" disabled={busy}>{busy ? '처리하는 중…' : '기각 확정'}</button>
        <button type="button" className="btn btn-small" onClick={onCancel} disabled={busy}>취소</button>
      </div>
      {error && <p className="form-error" role="alert">{error}</p>}
    </form>
  );
}
