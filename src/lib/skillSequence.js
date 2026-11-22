// 스킬 찍는 순서 상세 입력 (065, SPEC 6-80): 1렙부터 차례로 Q·W·E·R을 적은 글자 줄 ("QEWQQRE…"), 1~18칸, 없으면 null.
// DB public.skill_sequence_mode·skill_sequence_problem과 같은 규칙·같은 예외 표·같은 문구. DB가 한 번 더 막는다.

export const SEQ_KEYS = ['Q', 'W', 'E', 'R'];
export const SEQ_MAX = 18;
const SEQ_PATTERN = /^[QWER]{1,18}$/;
const R_LEVELS = [6, 11, 16];
const NTH = ['', '두 번째 ', '세 번째 '];
export const SEQ_FORMAT_PROBLEM = '스킬 순서는 Q·W·E·R만 1~18칸까지 적을 수 있습니다.';
export const SEQ_HIDDEN_PROBLEM = '이 챔피언은 스킬을 직접 찍지 않아 상세 순서를 적을 수 없습니다.';

/**
 * 챔피언(Data Dragon id)별 예외. DB skill_sequence_mode와 똑같이 둔다 — 새 예외는 두 곳에 한 줄씩.
 *   hidden: Q·W·E를 직접 찍지 않아 상세 순서를 받지 않는다 (입력 칸을 숨긴다)
 *   loose:  찍는 규칙이 기본과 달라 형식(Q·W·E·R, 1~18칸)만 본다 — 표가 지금 게임과 조금 달라도 정상 빌드를 막지 않게
 * 표에 없는 챔피언은 기본 규칙(strict).
 */
export const SEQ_EXCEPTIONS = {
  Aphelios: 'hidden', // Q·W·E를 직접 찍지 않음
  Udyr: 'loose', // 궁이 따로 없고 네 스킬을 1렙부터
  Jayce: 'loose', // 변신(R)을 1렙부터
  Elise: 'loose',
  Nidalee: 'loose',
  Karma: 'loose', // 만트라(R)를 1렙부터
};

/** 'strict' | 'loose' | 'hidden' */
export const seqMode = (champion) => SEQ_EXCEPTIONS[champion] ?? 'strict';

/** 저장된 값 → 입력 값 (형식이 틀리면 빈 글자) */
export const toSeq = (v) => (typeof v === 'string' && SEQ_PATTERN.test(v) ? v : '');

/** 입력 값 → DB에 보내는 값 (비면 null — 명시적으로 지운다) */
export const seqPayload = (v) => (v ? v : null);

/**
 * 지금까지 적은 순서(prev) 다음 레벨에 key를 찍을 수 없는 이유 (되면 null). 기본 규칙(strict) 기준.
 * Q·W·E 각 5번, R 3번(첫 R 6렙·두 번째 11렙·세 번째 16렙부터), Q·W·E는 그 레벨/2 올림 번까지.
 */
export function stepProblem(prev, key) {
  const level = prev.length + 1;
  if (level > SEQ_MAX) return `${SEQ_MAX}렙까지만 적을 수 있습니다.`;
  const n = [...prev].filter((c) => c === key).length + 1;
  if (key === 'R') {
    if (n > 3) return 'R은 3번까지 찍을 수 있습니다.';
    const need = R_LEVELS[n - 1];
    return level < need ? `${NTH[n - 1]}R은 ${need}렙부터 찍을 수 있습니다.` : null;
  }
  if (n > 5) return `${key}는 5번까지 찍을 수 있습니다.`;
  const cap = Math.ceil(level / 2);
  return n > cap ? `${level}렙에는 ${key}를 ${cap}번까지 찍을 수 있습니다.` : null;
}

/** 다음 칸에 key를 누를 수 없는 이유 (되면 null). 챔피언 예외 반영 */
export function nextKeyProblem(prev, key, champion) {
  if (prev.length >= SEQ_MAX) return `${SEQ_MAX}렙까지 다 적었습니다.`;
  return seqMode(champion) === 'strict' ? stepProblem(prev, key) : null;
}

/** 순서 전체의 문제 (없으면 null). DB skill_sequence_problem과 같은 문구 */
export function seqProblem(seq, champion) {
  if (!seq) return null;
  if (!SEQ_PATTERN.test(seq)) return SEQ_FORMAT_PROBLEM;
  const mode = seqMode(champion);
  if (mode === 'hidden') return SEQ_HIDDEN_PROBLEM;
  if (mode === 'loose') return null;
  for (let i = 0; i < seq.length; i += 1) {
    const p = stepProblem(seq.slice(0, i), seq[i]);
    if (p) return `스킬 순서 ${i + 1}렙: ${p}`;
  }
  return null;
}

/** Q·W·E 중 순서에서 처음으로 5번 찍은 스킬 (없으면 null) */
export function firstMaxed(seq) {
  const n = { Q: 0, W: 0, E: 0 };
  for (const c of seq ?? '') {
    if (c in n) {
      n[c] += 1;
      if (n[c] === 5) return c;
    }
  }
  return null;
}

/** 선마와 순서가 어긋나면 안내 문구 (막지 않는다). 아직 5번 찍은 스킬이 없으면 null */
export function maxSkillMismatch(seq, maxSkill) {
  const first = firstMaxed(seq);
  if (!first || !maxSkill || first === maxSkill) return null;
  return `선마와 순서가 다릅니다. 선마는 ${maxSkill}인데, 적은 순서에서는 ${first}를 먼저 5번 찍었습니다.`;
}

/** 스크린리더 문장: "1렙 Q, 2렙 E, …" */
export const seqSpoken = (seq) => [...(seq ?? '')].map((c, i) => `${i + 1}렙 ${c}`).join(', ');

/** "N렙까지 작성하셨습니다 (N/18)" */
export const seqProgress = (seq) => (seq
  ? `${seq.length}렙까지 작성하셨습니다 (${seq.length}/${SEQ_MAX})`
  : `아직 적지 않았습니다 (0/${SEQ_MAX})`);
