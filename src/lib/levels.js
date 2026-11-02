// 레벨 계산 (DB의 level_for와 같은 규칙, SPEC 6-2). 화면의 "다음 레벨까지" 표시용 — 실제 레벨은 DB가 정한다.

/** levels = [{ level, min_xp }] (오름차순), step = 마지막 레벨 뒤 레벨마다 필요한 경험치 */
export function minXpFor(level, levels, step) {
  const top = levels[levels.length - 1];
  if (level <= top.level) return levels.find((l) => l.level === level)?.min_xp ?? 0;
  return top.min_xp + (level - top.level) * step;
}

/** { level, xp, from: 이번 레벨 시작, to: 다음 레벨 시작, toNext: 남은 양, percent } */
export function levelProgress(xp, levels, step = 1000) {
  const top = levels[levels.length - 1];
  const level = xp >= top.min_xp
    ? top.level + Math.floor((xp - top.min_xp) / Math.max(step, 1))
    : Math.max(...levels.filter((l) => l.min_xp <= xp).map((l) => l.level));
  const from = minXpFor(level, levels, step);
  const to = minXpFor(level + 1, levels, step);
  return { level, xp, from, to, toNext: to - xp, percent: Math.round(((xp - from) / (to - from)) * 100) };
}
