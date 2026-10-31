// 한글 초성 검색. 예: "ㄷㄹㅇㅅ" → 다리우스, "다리" → 다리우스
const CHO = ['ㄱ', 'ㄲ', 'ㄴ', 'ㄷ', 'ㄸ', 'ㄹ', 'ㅁ', 'ㅂ', 'ㅃ', 'ㅅ', 'ㅆ', 'ㅇ', 'ㅈ', 'ㅉ', 'ㅊ', 'ㅋ', 'ㅌ', 'ㅍ', 'ㅎ'];
const HANGUL_START = 0xac00;
const HANGUL_END = 0xd7a3;

export function toChosung(text) {
  let out = '';
  for (const ch of text) {
    const code = ch.charCodeAt(0);
    if (code >= HANGUL_START && code <= HANGUL_END) {
      out += CHO[Math.floor((code - HANGUL_START) / 588)];
    } else {
      out += ch;
    }
  }
  return out;
}

const normalize = (s) => s.replace(/\s+/g, '').toLowerCase();
const isChosungOnly = (s) => /^[ㄱ-ㅎ]+$/.test(s);

/**
 * 검색어가 이름과 맞는지 확인한다.
 * - 초성만 입력하면 초성끼리 비교
 * - 그 외에는 이름 일부 포함 여부 (공백 무시)
 * - 영문 id(예: "darius")도 허용
 */
export function matchesQuery(query, name, id = '') {
  const q = normalize(query);
  if (!q) return true;
  const n = normalize(name);
  if (isChosungOnly(q)) return toChosung(n).includes(q);
  return n.includes(q) || normalize(id).includes(q);
}
