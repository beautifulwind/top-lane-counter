// 1단계 가짜 데이터. 2단계에서 Supabase 테이블(counters, matchup_docs, builds)로 교체된다.
// 모양은 SPEC 7장의 테이블 구조를 따른다.

export const counters = [
  { id: 1, target_champion: 'Darius', counter_champion: 'Quinn', sort_order: 1 },
  { id: 2, target_champion: 'Darius', counter_champion: 'Vayne', sort_order: 2 },
  { id: 3, target_champion: 'Darius', counter_champion: 'Kennen', sort_order: 3 },
  { id: 4, target_champion: 'Darius', counter_champion: 'Teemo', sort_order: 4 },
  { id: 5, target_champion: 'Garen', counter_champion: 'Vayne', sort_order: 1 },
  { id: 6, target_champion: 'Garen', counter_champion: 'Kayle', sort_order: 2 },
  { id: 7, target_champion: 'Fiora', counter_champion: 'Malphite', sort_order: 1 },
];

const sampleLevels = (who, target) => ({
  1: `${who} 쪽이 사거리가 길다. ${target}에게 붙지 말고 미니언 뒤에서 평타로만 견제한다.`,
  2: `상대가 2레벨을 먼저 찍으면 바로 뒤로 빠진다. 웨이브를 먼저 밀어 2레벨 선점을 노린다.`,
  3: `핵심 스킬 3개가 모두 생기는 구간. 상대 주요 스킬이 빠진 걸 보고 짧게 딜교한다.`,
  6: `궁극기 유무가 가장 중요하다. 상대 궁 각이 보이면 체력을 반 이상 유지한다.`,
  9: `주력 스킬 마스터. 짧은 교환을 여러 번 하는 쪽이 유리하다.`,
  11: `궁극기 2레벨. 사이드 운영으로 상대를 라인에 묶어둔다.`,
});

export const matchupDocs = {
  1: {
    counter_id: 1,
    summary: '사거리로 일방적인 견제, 다리우스 W·E만 피하면 라인전 압승',
    level_notes: {
      ...sampleLevels('퀸', '다리우스'),
      4: '첫 귀환 전 체력을 깎아 두면 다리우스가 CS를 포기하게 된다.',
    },
    lane_cautions:
      '다리우스 E(포획) 사거리 안에서 오래 머무르지 않는다.\n출혈 5중첩 + 궁극기 각이 나오면 바로 빠진다.\n상대 정글이 탑에 오면 다리우스 혼자서도 킬각이 나오므로 와드 필수.',
    updated_at: '2026-10-20',
  },
};

export const builds = [
  {
    id: 101,
    counter_id: 1,
    author: '예시유저1',
    runes: {
      primaryPath: 8000,
      keystone: 8005,
      primary: [9111, 9104, 8014],
      secondaryPath: 8100,
      secondary: [8143, 8106],
      shards: [5005, 5008, 5011],
    },
    summoner_spells: ['SummonerFlash', 'SummonerTeleport'],
    starting_items: ['1055', '2003'],
    core_items: ['6672', '3006', '3031', '3036'],
    skill_order: ['Q', 'E', 'W'],
    patch: 'LATEST', // 가짜 데이터용: 화면에서 최신 패치로 치환
    up: 42,
    down: 3,
  },
  {
    id: 102,
    counter_id: 1,
    author: '예시유저2',
    runes: {
      primaryPath: 8000,
      keystone: 8021,
      primary: [9111, 9104, 8299],
      secondaryPath: 8400,
      secondary: [8444, 8451],
      shards: [5005, 5008, 5011],
    },
    summoner_spells: ['SummonerFlash', 'SummonerDot'],
    starting_items: ['1055', '2003'],
    core_items: ['3153', '3006', '3124', '3031'],
    skill_order: ['Q', 'W', 'E'],
    patch: '14.1.1',
    up: 15,
    down: 4,
  },
];
