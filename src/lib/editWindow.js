// 글·댓글 고치기 시간 (SPEC 6-7). 마지막 판단은 DB(require_edit_window)가 하고, 화면은 [고치기]를 숨기는 데만 쓴다.
import { useEffect, useState } from 'react';

export const DEFAULT_EDIT_RULES = { post: 60, comment: 10, grace: 5 };

/** xp_rules 줄들 → { post, comment, grace } (분) */
export function editRulesFrom(rows) {
  const v = Object.fromEntries(rows.map((r) => [r.key, r.value]));
  return {
    post: v.post_edit_minutes ?? DEFAULT_EDIT_RULES.post,
    comment: v.comment_edit_minutes ?? DEFAULT_EDIT_RULES.comment,
    grace: v.edit_grace_minutes ?? DEFAULT_EDIT_RULES.grace,
  };
}

/** 저장할 수 있는 마지막 시각 (ms): 쓴 때 + 제한 시간, 유예를 받았으면 그때까지 */
export function editDeadline(kind, row, rules = DEFAULT_EDIT_RULES) {
  const minutes = kind === 'post' ? rules.post : rules.comment;
  const base = new Date(row.created_at).getTime() + minutes * 60_000;
  const grace = row.edit_grace_until ? new Date(row.edit_grace_until).getTime() : -Infinity;
  return Math.max(base, grace);
}

export const canEditNow = (kind, row, rules, now = Date.now()) => now <= editDeadline(kind, row, rules);

/** 지금 시각 (30초마다 다시 그려 [고치기]가 제때 사라지게) */
export function useNow(intervalMs = 30_000) {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), intervalMs);
    return () => clearInterval(id);
  }, [intervalMs]);
  return now;
}

const pad = (n) => String(n).padStart(2, '0');
/** "14:05" */
export function fmtTime(ts) {
  const d = new Date(ts);
  return `${pad(d.getHours())}:${pad(d.getMinutes())}`;
}
