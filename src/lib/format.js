const pad = (n) => String(n).padStart(2, '0');

/** "2026-11-01 14:05" (브라우저 시간대) */
export function fmtDateTime(ts) {
  if (!ts) return '';
  const d = new Date(ts);
  if (Number.isNaN(d.getTime())) return String(ts);
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

export const STATUS_LABEL = { pending: '대기 중', approved: '승인', rejected: '거절', revoked: '승인 취소', revision_requested: '재검토 요청' };
export const TYPE_LABEL = { new_counter: '새 카운터', doc_edit: '문서 수정' };
