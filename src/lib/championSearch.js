// 홈 검색창의 찾기 규칙 (SPEC 6-61). 화면과 분리한 순수 함수 — 요청은 하지 않는다.
// 입력을 띄어쓰기로 나눈 단어(token)마다 챔피언(한글·초성·영문 id·별명) 또는 빌드 제목의 단어에 맞아야 하고(AND), 순서는 상관없다.
import { CHAMP_ALIASES } from './champAliases';
import { toChosung } from './chosung';

export const MAX_TOKENS = 6;
export const LIMITS = { champions: 6, combos: 8, builds: 6, counters: 5 };

/** 비교용: 소문자, 공백·아포스트로피·점·& 없앰 ("Cho'Gath" = "chogath", "리 신" = "리신") */
export const norm = (s) => String(s ?? '').toLowerCase().replace(/[\s'’.&·-]/g, '');

/** 입력 → 단어들 (앞뒤 공백 무시, 최대 MAX_TOKENS개) */
export const tokenize = (q) => String(q ?? '').trim().split(/\s+/).map(norm).filter(Boolean).slice(0, MAX_TOKENS);

const isJamo = (ch) => /[ㄱ-ㅎ]/.test(ch);

/** 글자 하나가 맞는지: 같은 글자이거나, 검색어 글자가 초성(ㅋ)이고 이름 글자의 초성이 같을 때 */
const sameChar = (p, t) => p === t || (isJamo(p) && toChosung(t) === p);

/** text 안에서 pattern이 처음 맞는 자리 (없으면 -1). 초성·글자 섞어 쓰기("아ㅋㄹ")도 된다 */
export function findAt(text, pattern) {
  const t = [...norm(text)];
  const p = [...pattern];
  if (p.length === 0) return 0;
  for (let i = 0; i + p.length <= t.length; i += 1) {
    let ok = true;
    for (let j = 0; j < p.length; j += 1) {
      if (!sameChar(p[j], t[i + j])) { ok = false; break; }
    }
    if (ok) return i;
  }
  return -1;
}

/** 단어 하나가 글자(이름·별명·제목 단어)에 맞는 정도: 0 안 맞음 / 2 중간에 포함 / 5 앞에서 일치 / 8 통째로 같음 */
export function textScore(token, text) {
  const at = findAt(text, token);
  if (at < 0) return 0;
  if (at > 0) return 2;
  return [...norm(text)].length === [...token].length ? 8 : 5;
}

/** 단어 하나가 챔피언(이름·영문 id·별명)에 맞는 정도 */
export function champScore(token, champ) {
  let best = 0;
  for (const f of [champ.name, champ.id, ...(CHAMP_ALIASES[champ.id] ?? [])]) best = Math.max(best, textScore(token, f));
  return best;
}

/** 모든 단어가 이 챔피언에 맞으면 점수 합, 아니면 0 */
export function champMatch(tokens, champ) {
  let sum = 0;
  for (const t of tokens) {
    const s = champScore(t, champ);
    if (s === 0) return 0;
    sum += s;
  }
  return sum;
}

/** 단어 하나가 빌드 제목의 단어에 맞는 정도 (제목 첫 단어에서 앞이 일치할수록 높다) */
export function titleScore(token, title) {
  let best = 0;
  String(title ?? '').trim().split(/\s+/).filter(Boolean).forEach((w, i) => {
    const at = findAt(w, token);
    if (at < 0) return;
    const s = at > 0 ? 2 : [...norm(w)].length === [...token].length ? (i === 0 ? 9 : 7) : (i === 0 ? 6 : 4);
    best = Math.max(best, s);
  });
  return best;
}

/** 단어 하나가 한 줄 요약의 단어에 맞는 정도: 이름보다 낮게 (통째 4 · 앞 3 · 중간 2) */
export function summaryScore(token, summary) {
  let best = 0;
  String(summary ?? '').trim().split(/\s+/).filter(Boolean).forEach((w) => {
    const at = findAt(w, token);
    if (at < 0) return;
    best = Math.max(best, at > 0 ? 2 : [...norm(w)].length === [...token].length ? 4 : 3);
  });
  return best;
}

const byScore = (a, b) => b.score - a.score;

/**
 * 후보 만들기.
 * champs: 챔피언 목록, index: { counters: [{id,target,mine,order}], builds: [{id,title,target,mine,influencer}] } | null (아직 못 받음)
 * 돌려주는 값: { champions, combos, missing, builds }
 *  - champions: 모든 단어가 맞는 챔피언 (최대 6)
 *  - combos: 단어가 하나면 "그 챔피언을 상대로 한" 상대법(최대 5), 둘이면 "내 챔피언 + 상대 챔피언" 상대법 (정방향 먼저, 반대 방향은 reverse: true로 뒤, 합쳐 최대 8)
 *  - missing: 단어가 둘이고 정방향 상대법이 없을 때 { target, mine } (아직 없음, 직접 쓰기)
 *  - builds: 이름·한 줄 요약이 맞는 공개 빌드 (최대 6, 모든 단어가 챔피언 또는 이름·요약에 맞고, 이름·요약에 맞는 단어가 1개 이상).
 *    단어마다 이름에 있든 요약에 있든 상관없다(이름에 한 단어, 요약에 다른 단어여도 AND 성립). 이름이 비어 있어도 요약으로 찾는다
 */
export function searchAll(tokens, champs, index) {
  const out = { champions: [], combos: [], missing: null, builds: [] };
  if (tokens.length === 0) return out;
  const byId = Object.fromEntries(champs.map((c) => [c.id, c]));
  const order = new Map(champs.map((c, i) => [c.id, i]));
  const rank = (a, b) => b.score - a.score || order.get(a.c.id) - order.get(b.c.id);

  out.champions = champs
    .map((c) => ({ c, score: champMatch(tokens, c) }))
    .filter((x) => x.score > 0).sort(rank).slice(0, LIMITS.champions).map((x) => x.c);

  if (index) {
    const counterBuilds = new Map();
    for (const b of index.builds) counterBuilds.set(`${b.target}>${b.mine}`, (counterBuilds.get(`${b.target}>${b.mine}`) ?? 0) + 1);
    const pair = new Map(index.counters.map((c) => [`${c.target}>${c.mine}`, c]));
    const row = (c, extra = {}) => ({ counter: c, target: byId[c.target], mine: byId[c.mine], builds: counterBuilds.get(`${c.target}>${c.mine}`) ?? 0, ...extra });

    if (tokens.length === 1) {
      const cands = champs.map((c) => ({ c, score: champScore(tokens[0], c) })).filter((x) => x.score > 0).sort(rank);
      // 후보가 하나뿐이거나 이름·별명이 통째로 맞을 때만 그 챔피언의 상대법을 보여 준다 ("ㅇ"처럼 여럿이 걸리면 어지럽다)
      if (cands.length > 0 && (cands.length === 1 || cands[0].score >= 8)) {
        out.combos = index.counters
          .filter((c) => c.target === cands[0].c.id && byId[c.mine])
          .sort((a, b) => a.order - b.order || a.id - b.id).slice(0, LIMITS.counters).map((c) => row(c));
      }
    } else if (tokens.length === 2) {
      const mineCands = champs.map((c) => ({ c, score: champScore(tokens[0], c) })).filter((x) => x.score > 0).sort(rank);
      const targetCands = champs.map((c) => ({ c, score: champScore(tokens[1], c) })).filter((x) => x.score > 0).sort(rank);
      const forward = [];
      const reverse = [];
      for (const a of mineCands) {
        for (const b of targetCands) {
          if (a.c.id === b.c.id) continue;
          const f = pair.get(`${b.c.id}>${a.c.id}`);
          if (f) forward.push({ ...row(f), score: a.score + b.score });
          const r = pair.get(`${a.c.id}>${b.c.id}`);
          if (r) reverse.push({ ...row(r, { reverse: true }), score: a.score + b.score });
        }
      }
      out.combos = [...forward.sort(byScore), ...reverse.sort(byScore)].slice(0, LIMITS.combos);
      if (forward.length === 0) {
        const a = mineCands[0];
        const b = targetCands.find((x) => x.c.id !== a?.c.id);
        if (a && b) out.missing = { mine: a.c, target: b.c };
      }
    }

    out.builds = index.builds
      .filter((b) => (b.title || b.summary) && byId[b.target] && byId[b.mine])
      .map((b) => {
        const t = byId[b.target];
        const m = byId[b.mine];
        let score = 0;
        let inTitle = 0;
        for (const tok of tokens) {
          const ts = Math.max(titleScore(tok, b.title), summaryScore(tok, b.summary));
          const cs = Math.max(champScore(tok, t), champScore(tok, m));
          if (ts === 0 && cs === 0) return null;
          if (ts > 0) inTitle += 1;
          score += Math.max(ts, cs) + (ts > 0 ? 3 : 0);
        }
        return inTitle > 0 ? { build: b, target: t, mine: m, score } : null;
      })
      .filter(Boolean)
      .sort((a, b) => b.score - a.score || b.build.id - a.build.id)
      .slice(0, LIMITS.builds);
  }
  return out;
}
