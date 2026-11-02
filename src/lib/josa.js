// 받침을 보고 조사를 고른다. "을(를)" 같은 자리표시 대신 쓴다.
//   josa('다리우스', '을/를') → '다리우스를',  josa('퀸', '으로/로') → '퀸으로',  josa('케일', '으로/로') → '케일로'
// 한글이 아닌 글자로 끝나면(영문·숫자 등) 받침을 알 수 없으므로 "을(를)" 모양으로 둔다.

const PAIRS = {
  '을/를': ['을', '를'],
  '은/는': ['은', '는'],
  '이/가': ['이', '가'],
  '과/와': ['과', '와'],
  '으로/로': ['으로', '로'],
};

/** 마지막 글자의 받침: null = 한글 아님, 0 = 받침 없음, 8 = ㄹ, 그 밖 = 받침 있음 */
function finalConsonant(word) {
  const s = String(word ?? '').trim();
  const code = s.charCodeAt(s.length - 1) - 0xac00;
  if (Number.isNaN(code) || code < 0 || code > 11171) return null;
  return code % 28;
}

/** 조사만 (예: josaOf('퀸', '으로/로') → '으로') */
export function josaOf(word, pair) {
  const [withBatchim, without] = PAIRS[pair] ?? [];
  if (!withBatchim) throw new Error(`모르는 조사예요: ${pair}`);
  const jong = finalConsonant(word);
  if (jong === null) return `${withBatchim === '으로' ? '(으)로' : `${withBatchim}(${without})`}`;
  if (pair === '으로/로') return jong === 0 || jong === 8 ? '로' : '으로'; // ㄹ 받침은 "로" (케일로)
  return jong === 0 ? without : withBatchim;
}

/** 낱말 + 조사 (예: josa('다리우스', '을/를') → '다리우스를') */
export const josa = (word, pair) => `${word}${josaOf(word, pair)}`;

/** 매치업 이름: "퀸으로 다리우스 잡는 법" (counterName = 이기는 쪽, targetName = 지는 쪽) */
export const matchupTitle = (counterName, targetName) => `${josa(counterName, '으로/로')} ${targetName} 잡는 법`;

/** 경험치 내역처럼 짧게: "퀸으로 다리우스" */
export const matchupShort = (counterName, targetName) => `${josa(counterName, '으로/로')} ${targetName}`;
