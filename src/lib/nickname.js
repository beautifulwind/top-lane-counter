// 닉네임 표시와 예약어 (2026-11-07)
// - 운영자 표시 "(운)"은 role을 보고 화면이 닉네임 앞에 붙인다 (닉네임 글자에는 들어 있지 않다).
// - 그래서 아무도 닉네임에 "(운)"·"(감)"을 쓸 수 없다. 화면(여기)과 DB(029 nickname_reserved)가 같은 기준으로 막는다.

/** 이름 앞에 붙는 역할 표시 (지금은 운영자만) */
export const roleMark = (person) => (person?.role === 'admin' ? '(운)' : '');

/** 화면에 보이는 닉네임: 운영자는 "(운)영자". 사람이 없으면(탈퇴 등) fallback */
export const displayNickname = (person, fallback = '탈퇴한 유저') =>
  person?.nickname ? `${roleMark(person)}${person.nickname}` : fallback;

const OPEN = '[{<〔【〈《「『〖﹙⁽₍❨❪❬❮❰❲❴⟦⟨⟪⟬⦅〘〚﹛﹝＜';
const CLOSE = ']}>〕】〉》」』〗﹚⁾₎❩❫❭❯❱❳❵⟧⟩⟫⟭⦆〙〛﹜﹞＞';
// 보이지 않는 글자: 공백류 · 제로폭 · 방향 표시 · 소프트 하이픈 · 한글 채움 · 결합 기호
const INVISIBLE = /[\s\u00AD\u034F\u115F\u1160\u17B4\u17B5\u180E\u200B-\u200F\u2028-\u202F\u2060-\u206F\u3164\uFEFF\uFFA0\u0300-\u036F]/g;
const RESERVED = /\([운감]\)/;

/** 예약된 역할 표시가 들어 있는가: 전각 괄호·대괄호 같은 모양과 띄어쓰기를 바꾼 변형도 같게 본다 */
export function hasReservedMark(raw) {
  let s = String(raw ?? '').normalize('NFKC');
  s = s.replace(INVISIBLE, '');
  s = [...s].map((c) => (OPEN.includes(c) ? '(' : CLOSE.includes(c) ? ')' : c)).join('');
  return RESERVED.test(s);
}
