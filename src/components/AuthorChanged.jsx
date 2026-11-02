import { useState } from 'react';
import { isChangedByAuthor } from '../api/proposals';
import { fmtDateTime } from '../lib/format';

/**
 * 운영자가 처리하는 사이 제안자(작성자)가 내용을 고쳐서 DB가 막았을 때 (승인·재검토 요청·거절).
 * guard(fn): 처리 함수를 감싼다 — 그 오류면 안내를 띄우고, 오류는 그대로 던져 메모 폼에도 이유가 보이게 한다.
 * notice: [새 내용 불러오기] 안내 (누르면 reload — 승인 화면에서 고치던 내용은 사라진다)
 */
export function useAuthorChanged(reload, who = '제안자') {
  const [changed, setChanged] = useState(false);
  const guard = (fn) => async (...args) => {
    try {
      return await fn(...args);
    } catch (err) {
      if (isChangedByAuthor(err)) setChanged(true);
      throw err;
    }
  };
  const notice = changed && (
    <div className="warn author-changed" role="alert">
      <p>{who}가 방금 내용을 고쳤어요. 지금 보이는 건 고치기 전 내용이라 처리하지 않았어요. 새 내용을 불러와 다시 확인해 주세요.</p>
      <p className="hint">불러오면 승인 화면에서 고치던 내용과 쓰던 메모는 사라져요.</p>
      <button type="button" className="btn btn-small btn-op" onClick={() => { setChanged(false); reload(); }}>
        새 내용 불러오기
      </button>
    </div>
  );
  return { guard, notice };
}

/** "제안자가 고침 · 시각" 표시 (승인 대기 중에 고쳤을 때만, 대기 순서는 처음 보낸 때 그대로) */
export function EditedBadge({ row, who = '제안자' }) {
  if (!row.edited_at || row.status !== 'pending') return null;
  return <span className="edited-badge">{who}가 고침 · {fmtDateTime(row.edited_at)}</span>;
}
