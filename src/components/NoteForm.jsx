import { useState } from 'react';

/**
 * 확인 창 대신 쓰는 "메모 입력 = 확인 단계" 폼.
 * 버튼을 누르면 그 자리에 열리고, 메모(앞뒤 공백 제외)를 써야 확정 버튼이 눌린다.
 * onSubmit(note): 실패하면 Error를 던진다 → 폼 아래에 이유를 보여 주고 그대로 둔다.
 * onCancel: [취소] 또는 Esc
 */
export default function NoteForm({ id, label, confirmLabel, busyLabel = '처리하는 중…', hint, onSubmit, onCancel }) {
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const ready = note.trim() !== '';

  const submit = async (e) => {
    e.preventDefault();
    if (!ready || busy) return;
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
    <form
      className="note-form"
      onSubmit={submit}
      onKeyDown={(e) => e.key === 'Escape' && !busy && onCancel()}
    >
      <label htmlFor={id}>{label}</label>
      {/* eslint-disable-next-line jsx-a11y/no-autofocus -- 버튼을 눌러 연 입력창이라 바로 쓰게 한다 */}
      <textarea id={id} rows={2} value={note} onChange={(e) => setNote(e.target.value)} maxLength={500} autoFocus />
      {hint && <small className="hint">{hint}</small>}
      <div className="note-form-actions">
        <button type="submit" className="btn btn-small" disabled={!ready || busy}>
          {busy ? busyLabel : confirmLabel}
        </button>
        <button type="button" className="btn btn-small" onClick={onCancel} disabled={busy}>
          취소
        </button>
      </div>
      {error && <p className="form-error" role="alert">{error}</p>}
    </form>
  );
}
