import { describe, expect, test } from 'vitest';
import { champMatch, champScore, findAt, searchAll, titleScore, tokenize } from './championSearch';

const C = (id, name) => ({ id, name, title: `${name} 칭호`, icon: `${id}.png` });
const CHAMPS = [
  C('Akali', '아칼리'), C('Chogath', '초가스'), C('Darius', '다리우스'), C('LeeSin', '리 신'), C('MasterYi', '마스터 이'),
  C('MonkeyKing', '오공'), C('Quinn', '퀸'), C('TwistedFate', '트위스티드 페이트'), C('Vi', '바이'), C('Kalista', '칼리스타'),
];
const id = (list) => list.map((c) => c.id);
const counter = (i, target, mine, order = i) => ({ id: i, target, mine, order });
const build = (i, target, mine, title, extra = {}) => ({ id: i, title, seq: 1, target, mine, influencer: false, ...extra });

describe('낱말·글자 맞추기', () => {
  test('단어 나누기: 앞뒤·여러 칸 공백 무시, 소문자, 아포스트로피 제거, 6개까지', () => {
    expect(tokenize('  빛망   감전  Cho\'Gath ')).toEqual(['빛망', '감전', 'chogath']);
    expect(tokenize('')).toEqual([]);
    expect(tokenize('a b c d e f g h')).toHaveLength(6);
  });
  test('초성·글자 섞기', () => {
    expect(findAt('아칼리', 'ㅇㅋㄹ')).toBe(0);
    expect(findAt('아칼리', 'ㅋㄹ')).toBe(1);
    expect(findAt('아칼리', '아ㅋㄹ')).toBe(0);
    expect(findAt('아칼리', 'ㅋㅋ')).toBe(-1);
    expect(findAt('빛망', 'ㅂㅁ')).toBe(0);
  });
  test('챔피언: 한글 부분 일치 · 초성 · 영문 id · 별명 · 띄어쓰기 이름', () => {
    const ids = (q) => id(CHAMPS.filter((c) => champMatch(tokenize(q), c) > 0));
    expect(ids('다리')).toEqual(['Darius']);
    expect(ids('ㄷㄹㅇㅅ')).toEqual(['Darius']);
    expect(ids('darius')).toEqual(['Darius']);
    expect(ids('cho\'gath')).toEqual(['Chogath']);
    expect(ids('손오공')).toEqual(['MonkeyKing']); // 별명
    expect(ids('wukong')).toEqual(['MonkeyKing']); // 영문 이름 (id는 MonkeyKing)
    expect(ids('트페')).toEqual(['TwistedFate']);
    expect(ids('리 신')).toEqual(['LeeSin']); // 한 챔피언 이름 안의 띄어쓰기
    expect(ids('마이')).toEqual(['MasterYi']);
  });
  test('점수: 통째로 같음 > 앞에서 일치 > 중간', () => {
    const [vi, ak] = [CHAMPS[8], CHAMPS[0]];
    expect(champScore('바이', vi)).toBe(8);
    expect(champScore('아칼', ak)).toBe(5);
    expect(champScore('칼리', ak)).toBe(2);
  });
  test('빌드 제목 단어: 첫 단어 앞 일치가 가장 높다', () => {
    expect(titleScore('빛망', '빛망 감전 아칼리')).toBeGreaterThan(titleScore('감전', '빛망 감전 아칼리'));
    expect(titleScore('ㄱㅈ', '빛망 감전 아칼리')).toBeGreaterThan(0);
    expect(titleScore('룬', '빛망 감전 아칼리')).toBe(0);
  });
});

describe('조합 찾기', () => {
  const index = {
    counters: [counter(1, 'Vi', 'Kalista'), counter(2, 'Kalista', 'Vi'), counter(3, 'Darius', 'Quinn'), counter(4, 'Darius', 'Vi'), counter(5, 'Darius', 'Akali', 0)],
    builds: [build(10, 'Vi', 'Kalista', '기본'), build(11, 'Vi', 'Kalista', '')],
  };
  test('두 단어 = 내 챔피언 + 상대 챔피언: 정방향 상대법, 빌드 개수', () => {
    const r = searchAll(tokenize('칼리스타 바이'), CHAMPS, index);
    expect(r.combos).toHaveLength(2);
    expect(r.combos[0]).toMatchObject({ target: { id: 'Vi' }, mine: { id: 'Kalista' }, builds: 2 });
    expect(r.combos[1]).toMatchObject({ reverse: true, target: { id: 'Kalista' }, mine: { id: 'Vi' } }); // 반대 방향은 뒤에
    expect(r.missing).toBeNull();
  });
  test('순서를 뒤집으면 방향이 뒤집힌 조합이 먼저', () => {
    const r = searchAll(tokenize('바이 칼리스타'), CHAMPS, index);
    expect(r.combos[0]).toMatchObject({ target: { id: 'Kalista' }, mine: { id: 'Vi' } });
    expect(r.combos[0].reverse).toBeUndefined();
    expect(r.combos[1].reverse).toBe(true);
  });
  test('정방향이 없으면 "아직 없음, 직접 쓰기" (반대 방향만 있어도)', () => {
    const r = searchAll(tokenize('다리우스 퀸'), CHAMPS, index);
    expect(r.combos.map((c) => c.reverse)).toEqual([true]);
    expect(r.missing).toMatchObject({ mine: { id: 'Darius' }, target: { id: 'Quinn' } });
    const none = searchAll(tokenize('퀸 칼리스타'), CHAMPS, index);
    expect(none.combos).toEqual([]);
    expect(none.missing).toMatchObject({ mine: { id: 'Quinn' }, target: { id: 'Kalista' } });
  });
  test('한 단어가 챔피언이 아니면 아직 없음 줄도 없다', () => {
    expect(searchAll(tokenize('퀸 zzz'), CHAMPS, index).missing).toBeNull();
  });
  test('한 단어: 이름이 통째로 맞으면 그 챔피언을 상대로 한 상대법(운영자 순서, 최대 5)', () => {
    const many = { counters: Array.from({ length: 7 }, (_, i) => counter(20 + i, 'Darius', i % 2 ? 'Quinn' : 'Akali', 7 - i)), builds: [] };
    const r = searchAll(tokenize('다리우스'), CHAMPS, many);
    expect(id(r.champions)).toEqual(['Darius']);
    expect(r.combos).toHaveLength(5);
    expect(r.combos.map((c) => c.counter.order)).toEqual([1, 2, 3, 4, 5]);
    // 걸리는 챔피언이 여럿이고 통째로 같은 것이 없으면 상대법은 안 보인다
    expect(searchAll(tokenize('ㅇ'), CHAMPS, many).combos).toEqual([]);
  });
  test('조합은 최대 8개', () => {
    const big = { counters: [], builds: [] };
    const ids = CHAMPS.map((c) => c.id);
    let n = 1;
    for (const t of ids) for (const m of ids) if (t !== m) big.counters.push(counter(n++, t, m));
    expect(searchAll(tokenize('ㅇ ㅂ'), CHAMPS, big).combos.length).toBeLessThanOrEqual(8);
  });
  test('목록을 아직 못 받았으면(index 없음) 챔피언만', () => {
    const r = searchAll(tokenize('퀸 다리우스'), CHAMPS, null);
    expect(r.combos).toEqual([]);
    expect(r.builds).toEqual([]);
    expect(r.missing).toBeNull();
  });
});

describe('빌드 제목 찾기', () => {
  const index = {
    counters: [],
    builds: [
      build(1, 'Darius', 'Akali', '빛망 감전 아칼리', { influencer: true }),
      build(2, 'Darius', 'Akali', '감전 단단'),
      build(3, 'Darius', 'Quinn', '빛망 감전 퀸'),
      build(4, 'Darius', 'Akali', ''), // 제목 없음 → 후보에 안 낌
    ],
  };
  const found = (q) => searchAll(tokenize(q), CHAMPS, index).builds.map((r) => r.build.id);
  test('단어 순서가 달라도, 제목 일부만 넣어도 같은 빌드가 뜬다', () => {
    expect(found('빛망 감전 아칼리')).toContain(1);
    expect(found('감전 아칼리 빛망')).toContain(1);
    expect(found('아칼리 빛망')).toContain(1);
    expect(found('빛 감전')).toContain(1);
    expect(found('아칼리 빛망').includes(2)).toBe(false); // 모든 단어가 맞아야 한다 (빛망이 없음)
  });
  test('초성이 섞여도 된다', () => {
    expect(found('ㅂㅁ 감전 ㅇㅋㄹ')).toContain(1);
    expect(found('ㄱㅈ 아칼')).toEqual(expect.arrayContaining([1, 2]));
  });
  test('하나라도 안 맞으면 빠진다 (AND), 제목에 맞는 단어가 없으면 빌드 후보가 아니다', () => {
    expect(found('빛망 룬')).toEqual([]);
    // 챔피언에만 맞고 제목에는 없으면 빌드 후보가 아니다 (상대법 구역의 몫)
    expect(searchAll(tokenize('퀸'), CHAMPS, { counters: [], builds: [build(5, 'Darius', 'Quinn', '단단 묵직')] }).builds).toEqual([]);
    expect(found('빛망 감전 아칼리 룬')).toEqual([]);
  });
  test('맞는 단어가 많고 제목 앞에서 일치할수록 위', () => {
    expect(found('감전')[0]).toBe(2); // 제목 첫 단어에서 일치
    const both = found('빛망 감전');
    expect(both.indexOf(3)).toBeGreaterThanOrEqual(0);
    expect(found('빛망')[0]).not.toBe(2);
  });
  test('빌드 후보는 최대 6개', () => {
    const many = { counters: [], builds: Array.from({ length: 12 }, (_, i) => build(100 + i, 'Darius', 'Akali', `빛망 ${i}`)) };
    expect(searchAll(tokenize('빛망'), CHAMPS, many).builds).toHaveLength(6);
  });
});

describe('이름 + 한 줄 요약', () => {
  const index = {
    counters: [],
    builds: [
      build(1, 'Darius', 'Akali', '빛망 감전'), // 이름만
      build(2, 'Darius', 'Akali', '', { summary: '감전 룬으로 초반 견제' }), // 요약만 (이름 없음)
      build(3, 'Darius', 'Akali', '착취 탱커', { summary: '정복자 대신 감전' }), // 둘 다
      build(4, 'Darius', 'Akali', '', { summary: '' }), // 둘 다 없음
    ],
  };
  const found = (q) => searchAll(tokenize(q), CHAMPS, index).builds.map((r) => r.build.id);
  test('이름만 / 요약만 / 둘 다 있으면 찾고, 둘 다 없으면 빠진다', () => {
    expect(found('감전').sort()).toEqual([1, 2, 3]);
    expect(found('견제')).toEqual([2]); // 이름이 없어도 요약으로
    expect(found('빛망')).toEqual([1]);
    expect(found('감전')).not.toContain(4);
  });
  test('한 단어는 이름에, 다른 단어는 요약에 있어도 된다 (순서 무관, 초성도)', () => {
    expect(found('착취 정복자')).toEqual([3]);
    expect(found('정복자 착취')).toEqual([3]);
    expect(found('ㅊㅊ ㅈㅂㅈ')).toEqual([3]);
    expect(found('착취 견제')).toEqual([]); // 3번 요약에 견제 없음 → AND 불성립
  });
  test('챔피언 단어 + 요약 단어', () => {
    expect(found('아칼리 견제')).toEqual([2]);
  });
  test('이름에서 맞은 빌드가 요약에서만 맞은 빌드보다 위', () => {
    expect(found('감전')[0]).toBe(1);
  });
});
