// 빌드 난이도 별점 (1.3 패치 3-A·3-B, SPEC 6-104). 값 = 0.5 단위 0.5~5.0, 선택 사항(비어 있으면 null = 아무것도 표시하지 않음).
// 의미: 「이 빌드를 플레이하기 어려운 정도」. DB(071)가 값을 한 번 더 검사한다.

export const DIFFICULTY_MIN = 0.5;
export const DIFFICULTY_MAX = 5;
export const DIFFICULTY_HELP = '이 빌드를 플레이하기 어려운 정도입니다. 선택 사항입니다.';
export const DIFFICULTY_SAVE_FAILED = '빌드는 등록됐지만 난이도 저장에 실패했습니다. 빌드 수정에서 다시 입력해 주세요.';
export const DIFFICULTY_EDIT_SAVE_FAILED = '빌드는 수정됐지만 난이도 저장에 실패했습니다. 빌드 수정에서 다시 입력해 주세요.';
/** 한 번에 build_difficulties로 물을 수 있는 id 수 (DB 상한) */
export const DIFFICULTY_BATCH = 200;

/** 화면·DB가 받는 값으로 다듬기: 0.5 단위 0.5~5.0이면 그 수, 아니면 null (비어 있음) */
export function cleanDifficulty(v) {
  if (v == null || v === '') return null;
  const n = Number(v);
  if (!Number.isFinite(n) || n < DIFFICULTY_MIN || n > DIFFICULTY_MAX || Math.round(n * 2) !== n * 2) return null;
  return n;
}

/** 별 n번째(1~5)를 눌렀을 때 다음 값: 처음 누르면 n점 → 같은 별을 다시 누르면 반 칸 줄어 n-0.5점 → 한 번 더 누르면 비움 */
export function nextDifficulty(current, star) {
  if (current === star) return star - 0.5;
  if (current === star - 0.5) return null;
  return star;
}

/** 3.5 → "3.5", 4 → "4.0" */
export const difficultyText = (v) => Number(v).toFixed(1);

/** 읽는 문구: 「난이도 3.5점」 / 비어 있으면 「난이도 선택 안 함」 */
export const difficultyLabel = (v) => (cleanDifficulty(v) == null ? '난이도 선택 안 함' : `난이도 ${difficultyText(v)}점`);

/** 별 한 칸의 채움: 0(빈 별) | 0.5(반 칸) | 1(가득). star = 1~5 */
export const starFill = (value, star) => (value == null ? 0 : value >= star ? 1 : value >= star - 0.5 ? 0.5 : 0);

/** 같은 값인가 (null·undefined는 같게 본다) */
export const sameDifficulty = (a, b) => (cleanDifficulty(a) ?? null) === (cleanDifficulty(b) ?? null);
