// 닉네임 표시와 예약어 (2026-11-07)
// - 운영진 표시 "(운)"은 role을 보고 화면이 닉네임 앞에 붙인다 (닉네임 글자에는 들어 있지 않다).
//   운영자(admin)와 감독관(moderator) 모두 같은 "(운)"이다. 권한 구분은 DB가 role로 한다 (030).
// - 그래서 아무도 닉네임에 "(운)"·"(감)"을 쓸 수 없다. 화면(여기)과 DB(029 nickname_reserved)가 같은 기준으로 막는다.

/** 운영진(운영자·감독관)인가 */
export const isStaffPerson = (person) => person?.role === 'admin' || person?.role === 'moderator';

/** 이름 앞에 붙는 역할 표시 */
export const roleMark = (person) => (isStaffPerson(person) ? '(운)' : '');

/** 화면에 보이는 닉네임: 운영진은 "(운)영자". 사람이 없으면(탈퇴 등) fallback */
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

// ---------------- 장인 (046, SPEC 6-32) ----------------
// 화면 글자는 "장인", 코드·DB 이름은 influencer. 닉네임 글자로 "장인" 표시를 흉내 내지 못하게 DB(nickname_mimics_influencer)와 같은 기준으로 먼저 막는다.

/** 장인 유형 (profiles.influencer · 신청서 kind) */
export const INFLUENCER_KINDS = { creator: '크리에이터', pro: '프로게이머', grandmaster: '그랜드마스터 이상' };

/** 장인 태그 말풍선 */
export const INFLUENCER_TIP = '인증된 장인(크리에이터·그랜드마스터 이상·프로게이머)';

/** 닉네임 칸에 "[장인]"류를 쓰면 보이는 안내 (DB 문구와 같음) */
export const INFLUENCER_MARK_MESSAGE = '닉네임에는 [장인]·(장인)을 쓸 수 없고, "장인 "으로 시작할 수 없습니다.';

// 공백은 남기고(시작 검사용) 보이지 않는 글자만 지운다
const HIDDEN = /[\u00AD\u034F\u115F\u1160\u17B4\u17B5\u180E\u200B-\u200F\u202A-\u202E\u2060-\u206F\u3164\uFEFF\uFFA0\u0300-\u036F]/g;
const SPACES = /[\s\u00A0\u2000-\u200A\u2028\u2029\u202F\u205F\u3000]+/g;
const MIMIC_START = /^장인[ _|\u00B7.:/~-]/;

/** "장인" 표시 흉내인가: [장인]·(장인)(괄호 모양·띄어쓰기·보이지 않는 글자 변형 포함), "장인 "으로 시작. "장인정신"처럼 붙여 쓴 것은 된다 */
export function mimicsInfluencer(raw) {
  let s = String(raw ?? '').normalize('NFKC').replace(HIDDEN, '').replace(SPACES, ' ').trim();
  if (MIMIC_START.test(s)) return true;
  s = [...s.replace(/ /g, '')].map((c) => (OPEN.includes(c) ? '(' : CLOSE.includes(c) ? ')' : c)).join('');
  return /\(장인\)/.test(s);
}
