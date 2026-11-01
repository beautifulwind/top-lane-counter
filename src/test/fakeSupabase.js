// 테스트용 가짜 Supabase. src/api/supabase.js의 db()를 대신한다 (setupTests.js에서 연결).
// 행 모양은 supabase/schema.sql + content.js의 select(관계 포함)가 돌려주는 모양을 따른다.
const runes = (keystone) => ({ primaryPath: 8000, keystone, primary: [9111, 9104, 8014], secondaryPath: 8100, secondary: [8143, 8106], shards: [5005, 5008, 5011] });
const build = (id, author, extra = {}) => ({
  id, counter_id: 1, author, status: 'approved', runes: runes(8005),
  summoner_spells: ['SummonerFlash', 'SummonerTeleport'], starting_items: ['1055', '2003'],
  core_items: ['6672', '3006'], skill_order: ['Q', 'E', 'W'], patch: '99.1.1',
  up_count: 0, down_count: 0, created_at: `2026-11-0${id - 100}T00:00:00Z`, ...extra,
});

export const TABLES = {
  counters: [
    {
      id: 1, target_champion: 'Darius', counter_champion: 'Quinn', sort_order: 1, status: 'approved',
      matchup_docs: {
        counter_id: 1, summary: '사거리로 일방적인 견제',
        level_notes: { 1: '1렙 내용', 2: '2렙', 3: '3렙', 4: '4렙 추가', 6: '6렙', 9: '9렙', 11: '11렙' },
        lane_cautions: 'E 사거리 주의', updated_at: '2026-11-01T09:00:00+00:00',
      },
    },
    { id: 2, target_champion: 'Darius', counter_champion: 'Vayne', sort_order: 0, status: 'pending', matchup_docs: null },
  ],
  builds: [
    build(101, null, { patch: '14.1.1', up_count: 1 }),
    build(102, { nickname: '탑신병자', level: 7, main_title: 'senior_researcher' }, { up_count: 5, down_count: 1 }),
    build(103, { nickname: '칭호없음', level: 3, main_title: null }, { up_count: 2 }),
    build(104, { nickname: '대기중', level: 1, main_title: null }, { status: 'pending', up_count: 99 }),
  ],
};

export const fakeState = { error: null };

function query(table) {
  let rows = [...(TABLES[table] ?? [])];
  let single = false;
  const q = {
    select: () => q,
    eq: (col, v) => { rows = rows.filter((r) => r[col] === v); return q; },
    order: (col, { ascending = true } = {}) => {
      rows.sort((a, b) => (a[col] < b[col] ? -1 : a[col] > b[col] ? 1 : 0) * (ascending ? 1 : -1));
      return q;
    },
    maybeSingle: () => { single = true; return q; },
    then: (ok, fail) => Promise.resolve(
      fakeState.error
        ? { data: null, error: { message: fakeState.error } }
        : { data: single ? rows[0] ?? null : rows, error: null },
    ).then(ok, fail),
  };
  return q;
}

export function db() {
  return { from: query };
}
