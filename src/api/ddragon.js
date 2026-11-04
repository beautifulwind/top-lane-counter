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

const TIMEOUT_MS = 15000;

async function getJson(url) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), TIMEOUT_MS);
  try {
    const res = await fetch(url, { signal: ctrl.signal });
    if (!res.ok) throw new Error(`게임 데이터 요청 실패 (${res.status})`);
    return await res.json();
  } catch (err) {
    if (err.name === 'AbortError') throw new Error('게임 데이터 서버 응답이 너무 늦습니다.');
    if (err instanceof TypeError) throw new Error('게임 데이터 서버에 연결할 수 없습니다. 인터넷 연결을 확인해 주세요.');
    throw err;
  } finally {
    clearTimeout(timer);
  }
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

/**
 * 아이템 (id → { id, name, icon, gold, shop }).
 * shop: 소환사의 협곡 상점에서 살 수 있는 아이템 (빌드 등록 화면의 고르기 목록). 예전 빌드 표시용으로 나머지도 다 담는다.
 */
export function getItems() {
  return once('items', async () => {
    const v = await getLatestVersion();
    const { data } = await getJson(`${BASE}/cdn/${v}/data/${LANG}/item.json`);
    const map = {};
    const shopNames = new Set();
    // 같은 이름이 여러 id로 있으면(모드별 사본) 작은 id 하나만 상점 목록에 넣는다
    for (const [id, it] of Object.entries(data).sort((a, b) => Number(a[0]) - Number(b[0]))) {
      const shop = isShopItem(id, it) && !shopNames.has(it.name);
      if (shop) shopNames.add(it.name);
      map[id] = { id, name: it.name, icon: `${BASE}/cdn/${v}/img/item/${it.image.full}`, gold: it.gold?.total ?? 0, shop };
    }
    return map;
  });
}

function isShopItem(id, it) {
  return Number(id) < 10000 && it.maps?.['11'] === true && it.gold?.purchasable === true
    && it.inStore !== false && !it.hideFromAll && !it.requiredChampion && !it.requiredAlly;
}

/** 소환사 주문 (id → { id, name, icon, classic }). classic: 소환사의 협곡에서 쓸 수 있는 주문 */
export function getSummonerSpells() {
  return once('spells', async () => {
    const v = await getLatestVersion();
    const { data } = await getJson(`${BASE}/cdn/${v}/data/${LANG}/summoner.json`);
    const map = {};
    for (const s of Object.values(data)) {
      map[s.id] = {
        id: s.id, name: s.name, icon: `${BASE}/cdn/${v}/img/spell/${s.image.full}`, classic: (s.modes ?? []).includes('CLASSIC'),
      };
    }
    return map;
  });
}

// 능력치 파편은 runesReforged.json에 없어서 여기에 정의한다. 줄마다 고를 수 있는 값은 SHARD_ROWS (DB 검사와 같음).
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
export const SHARD_ROWS = [[5008, 5005, 5007], [5008, 5010, 5001], [5011, 5013, 5001]];

/**
 * 룬 경로와 개별 룬을 id로 찾을 수 있게 정리.
 * paths[id] = { id, name, icon, keystones: [룬 id], rows: [[1줄], [2줄], [3줄]] }
 * runes[id] = { id, name, icon, path: 경로 id, row: 0(핵심 룬)~3 }
 */
export function getRunes() {
  return once('runes', async () => {
    const v = await getLatestVersion();
    const paths = await getJson(`${BASE}/cdn/${v}/data/${LANG}/runesReforged.json`);
    const pathMap = {};
    const runeMap = {};
    for (const p of paths) {
      const slots = p.slots.map((slot) => slot.runes.map((r) => r.id));
      pathMap[p.id] = { id: p.id, name: p.name, icon: `${BASE}/cdn/img/${p.icon}`, keystones: slots[0] ?? [], rows: slots.slice(1) };
      p.slots.forEach((slot, row) => {
        for (const r of slot.runes) {
          runeMap[r.id] = { id: r.id, name: r.name, icon: `${BASE}/cdn/img/${r.icon}`, path: p.id, row };
        }
      });
    }
    return { paths: pathMap, runes: runeMap, shards: STAT_SHARDS };
  });
}
