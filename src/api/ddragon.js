// Riot Data Dragon 접근 모듈. 게임 데이터는 DB에 복사하지 않고 여기서 읽는다.
const BASE = 'https://ddragon.leagueoflegends.com';
const LANG = 'ko_KR';

const cache = new Map();
function once(key, loader) {
  if (!cache.has(key)) {
    const p = loader().catch((err) => {
      cache.delete(key);
      throw err;
    });
    cache.set(key, p);
  }
  return cache.get(key);
}

async function getJson(url) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Data Dragon 요청 실패 (${res.status})`);
  return res.json();
}

export function getLatestVersion() {
  return once('version', async () => (await getJson(`${BASE}/api/versions.json`))[0]);
}

/** 전체 챔피언 목록 (이름순) */
export function getChampions() {
  return once('champions', async () => {
    const v = await getLatestVersion();
    const { data } = await getJson(`${BASE}/cdn/${v}/data/${LANG}/champion.json`);
    return Object.values(data)
      .map((c) => ({
        id: c.id,
        name: c.name,
        title: c.title,
        tags: c.tags,
        icon: `${BASE}/cdn/${v}/img/champion/${c.image.full}`,
      }))
      .sort((a, b) => a.name.localeCompare(b.name, 'ko'));
  });
}

export async function getChampionMap() {
  const list = await getChampions();
  return Object.fromEntries(list.map((c) => [c.id, c]));
}

export function getItems() {
  return once('items', async () => {
    const v = await getLatestVersion();
    const { data } = await getJson(`${BASE}/cdn/${v}/data/${LANG}/item.json`);
    const map = {};
    for (const [id, it] of Object.entries(data)) {
      map[id] = { id, name: it.name, icon: `${BASE}/cdn/${v}/img/item/${it.image.full}` };
    }
    return map;
  });
}

export function getSummonerSpells() {
  return once('spells', async () => {
    const v = await getLatestVersion();
    const { data } = await getJson(`${BASE}/cdn/${v}/data/${LANG}/summoner.json`);
    const map = {};
    for (const s of Object.values(data)) {
      map[s.id] = { id: s.id, name: s.name, icon: `${BASE}/cdn/${v}/img/spell/${s.image.full}` };
    }
    return map;
  });
}

// 능력치 파편은 runesReforged.json에 없어서 여기에 정의한다.
const SHARD_IMG = `${BASE}/cdn/img/perk-images/StatMods`;
export const STAT_SHARDS = {
  5008: { id: 5008, name: '적응형 능력치', icon: `${SHARD_IMG}/StatModsAdaptiveForceIcon.png` },
  5005: { id: 5005, name: '공격 속도', icon: `${SHARD_IMG}/StatModsAttackSpeedIcon.png` },
  5007: { id: 5007, name: '스킬 가속', icon: `${SHARD_IMG}/StatModsCDRScalingIcon.png` },
  5010: { id: 5010, name: '이동 속도', icon: `${SHARD_IMG}/StatModsMovementSpeedIcon.png` },
  5011: { id: 5011, name: '체력', icon: `${SHARD_IMG}/StatModsHealthPlusIcon.png` },
  5001: { id: 5001, name: '성장 체력', icon: `${SHARD_IMG}/StatModsHealthScalingIcon.png` },
  5013: { id: 5013, name: '강인함 및 둔화 저항', icon: `${SHARD_IMG}/StatModsTenacityIcon.png` },
};

/** 룬 경로와 개별 룬을 id로 찾을 수 있게 정리 */
export function getRunes() {
  return once('runes', async () => {
    const v = await getLatestVersion();
    const paths = await getJson(`${BASE}/cdn/${v}/data/${LANG}/runesReforged.json`);
    const pathMap = {};
    const runeMap = {};
    for (const p of paths) {
      pathMap[p.id] = { id: p.id, name: p.name, icon: `${BASE}/cdn/img/${p.icon}` };
      for (const slot of p.slots) {
        for (const r of slot.runes) {
          runeMap[r.id] = { id: r.id, name: r.name, icon: `${BASE}/cdn/img/${r.icon}` };
        }
      }
    }
    return { paths: pathMap, runes: runeMap, shards: STAT_SHARDS };
  });
}
