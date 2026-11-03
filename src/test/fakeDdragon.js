// 테스트용 가짜 Data Dragon 응답
const champ = (id, name) => ({ id, name, title: `${name} 칭호`, tags: [], image: { full: `${id}.png` } });
function item(name, total, extra = {}) {
  return { name, image: { full: `${name}.png` }, gold: { total, purchasable: true }, maps: { 11: true, 12: true }, ...extra };
}
function spell(id, name, modes = ['CLASSIC', 'ARAM']) {
  return { id, name, modes, image: { full: `${id}.png` } };
}
export const RUNE_NAMES = {
  8005: '집중 공격', 8010: '정복자', 9111: '승전보', 8009: '침착', 9104: '전설: 민첩함', 9105: '전설: 강인함', 8014: '최후의 일격', 8299: '최후의 저항',
  8112: '감전', 8143: '급습', 8126: '비열한 한 방', 8136: '좀비 와드', 8120: '유령 포로', 8135: '보물 사냥꾼', 8106: '궁극의 사냥꾼',
  8437: '착취의 손아귀', 8446: '철거', 8463: '생명의 샘', 8444: '사전 준비', 8473: '뼈 방패', 8242: '불굴의 의지', 8451: '과잉성장',
};
function path(id, name, keystones, rows) {
  const rune = (rid) => ({ id: rid, name: RUNE_NAMES[rid], icon: `perk/${rid}.png` });
  return { id, name, icon: `path/${id}.png`, slots: [{ runes: keystones.map(rune) }, ...rows.map((r) => ({ runes: r.map(rune) }))] };
}
const DATA = {
  'versions.json': ['99.1.1'],
  'champion.json': { data: { Darius: champ('Darius', '다리우스'), Quinn: champ('Quinn', '퀸'), Vayne: champ('Vayne', '베인'), Kennen: champ('Kennen', '케넨'), Teemo: champ('Teemo', '티모'), Garen: champ('Garen', '가렌') } },
  'item.json': { data: {
    1055: item('도란의 검', 450), 2003: item('체력 물약', 50), 1054: item('도란의 방패', 450), 1001: item('장화', 300), 3044: item('탐식의 망치', 1100), 6631: item('선혈포식자', 3300), 3047: item('강철판 장화', 1100),
    3053: item('스테락의 도전', 3000), 6672: item('크라켄 학살자', 3100), 3006: item('광전사의 군화', 1100),
    3071: item('칠흑의 양날 도끼', 3000), 3031: item('무한의 대검', 3400),
    3400: item('너만 살 수 있는 아이템', 0, { requiredAlly: 'Ornn' }), // 상점 목록에서 빠져야 함
    223031: item('무한의 대검', 3400), // 다른 모드용 사본 (id 10000 이상) → 빠져야 함
    8001: item('칼바람 전용', 1000, { maps: { 11: false, 12: true } }),
  } },
  'summoner.json': { data: {
    SummonerFlash: spell('SummonerFlash', '점멸'), SummonerTeleport: spell('SummonerTeleport', '순간이동'),
    SummonerDot: spell('SummonerDot', '점화'), SummonerSnowball: spell('SummonerSnowball', '표식', ['ARAM']),
  } },
  'runesReforged.json': [
    path(8000, '정밀', [8005, 8010], [[9111, 8009], [9104, 9105], [8014, 8299]]),
    path(8100, '지배', [8112], [[8143, 8126], [8136, 8120], [8135, 8106]]),
    path(8400, '결의', [8437], [[8446, 8463], [8444, 8473], [8242, 8451]]),
  ],
};

export function fakeFetch({ fail = false, hang = false } = {}) {
  return async (url) => {
    if (hang) return new Promise(() => {});
    if (fail) throw new TypeError('Failed to fetch');
    const key = Object.keys(DATA).find((k) => String(url).endsWith(k));
    if (!key) return { ok: false, status: 404, json: async () => ({}) };
    return { ok: true, status: 200, json: async () => DATA[key] };
  };
}
