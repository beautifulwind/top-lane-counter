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
    build(105, { nickname: '영자(운)', level: 0, main_title: null }), // 운영자가 쓴 빌드 (점수 0)
  ],
  profiles: [
    { id: 'u-old', nickname: '기존유저', role: 'user', xp: 0, level: 1, main_title: null },
  ],
};

// 테스트가 바꾸는 상태. setupTests.js가 테스트마다 초기화한다.
export const fakeState = { error: null, session: null, initError: null, oauthCalls: [], listeners: new Set() };
const INITIAL_PROFILES = TABLES.profiles.map((p) => ({ ...p }));

export function resetFake() {
  fakeState.error = null;
  fakeState.session = null;
  fakeState.initError = null;
  fakeState.oauthCalls = [];
  fakeState.listeners.clear();
  TABLES.profiles = INITIAL_PROFILES.map((p) => ({ ...p }));
}

/** 테스트에서 "구글 로그인을 마치고 돌아온" 상태 만들기. DB 트리거처럼 프로필도 만든다. */
export function fakeLogin(id, profile = {}) {
  if (!TABLES.profiles.some((p) => p.id === id)) {
    TABLES.profiles.push({ id, nickname: null, role: 'user', xp: 0, level: 1, main_title: null, ...profile });
  }
  fakeState.session = { user: { id }, access_token: 'fake' };
  fakeState.listeners.forEach((cb) => cb('SIGNED_IN', fakeState.session));
}

function query(table) {
  let rows = [...(TABLES[table] ?? [])];
  let single = false;
  let patch = null;
  const q = {
    select: () => q,
    update: (values) => { patch = values; return q; },
    eq: (col, v) => { rows = rows.filter((r) => r[col] === v); return q; },
    order: (col, { ascending = true } = {}) => {
      rows.sort((a, b) => (a[col] < b[col] ? -1 : a[col] > b[col] ? 1 : 0) * (ascending ? 1 : -1));
      return q;
    },
    maybeSingle: () => { single = true; return q; },
    then: (ok, fail) => Promise.resolve(run()).then(ok, fail),
  };
  function run() {
    if (fakeState.error) return { data: null, error: { message: fakeState.error } };
    if (patch) {
      // RLS 흉내: 내 행만 수정 / DB 제약 흉내: 닉네임 중복(대소문자 무시) 금지
      const me = fakeState.session?.user.id;
      rows = rows.filter((r) => r.id === me);
      const nick = patch.nickname?.toLowerCase();
      if (nick && TABLES[table].some((r) => r.id !== me && r.nickname?.toLowerCase() === nick)) {
        return { data: null, error: { code: '23505', message: 'duplicate key value violates unique constraint' } };
      }
      rows.forEach((r) => Object.assign(r, patch));
      rows = rows.map((r) => ({ ...r }));
    }
    return { data: single ? rows[0] ?? null : rows, error: null };
  }
  return q;
}

const auth = {
  // 진짜 supabase-js처럼: code 교환 실패는 던지지 않고 { error }로만 돌려준다
  initialize: async () => ({ error: fakeState.initError }),
  getSession: async () => ({ data: { session: fakeState.session }, error: null }),
  onAuthStateChange: (cb) => {
    fakeState.listeners.add(cb);
    return { data: { subscription: { unsubscribe: () => fakeState.listeners.delete(cb) } } };
  },
  signInWithOAuth: async (args) => { fakeState.oauthCalls.push(args); return { data: {}, error: null }; },
  signOut: async () => {
    fakeState.session = null;
    fakeState.listeners.forEach((cb) => cb('SIGNED_OUT', null));
    return { error: null };
  },
};

export function db() {
  return { from: query, auth };
}
