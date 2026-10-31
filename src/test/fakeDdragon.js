// 테스트용 가짜 Data Dragon 응답
const champ = (id, name) => ({ id, name, title: `${name} 칭호`, tags: [], image: { full: `${id}.png` } });
const DATA = {
  'versions.json': ['99.1.1'],
  'champion.json': { data: { Darius: champ('Darius', '다리우스'), Quinn: champ('Quinn', '퀸'), Vayne: champ('Vayne', '베인'), Kennen: champ('Kennen', '케넨'), Teemo: champ('Teemo', '티모'), Garen: champ('Garen', '가렌') } },
  'item.json': { data: {} },
  'summoner.json': { data: {} },
  'runesReforged.json': [],
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
