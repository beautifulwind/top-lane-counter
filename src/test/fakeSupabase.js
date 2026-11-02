// 테스트용 가짜 Supabase. src/api/supabase.js의 db()를 대신한다 (setupTests.js에서 연결).
// 행 모양은 supabase/schema.sql + content.js의 select(관계 포함)가 돌려주는 모양을 따른다.
const runes = (keystone) => ({ primaryPath: 8000, keystone, primary: [9111, 9104, 8014], secondaryPath: 8100, secondary: [8143, 8106], shards: [5005, 5008, 5011] });
const QUINN = { id: 1, target_champion: 'Darius', counter_champion: 'Quinn', status: 'approved' };
const build = (id, author, extra = {}) => ({
  id, counter_id: 1, author, author_id: author ? `u-${id}` : null, proposal_id: null, status: 'approved', runes: runes(8005),
  summoner_spells: ['SummonerFlash', 'SummonerTeleport'], starting_items: ['1055', '2003'],
  core_items: ['6672', '3006', '3031'], skill_order: ['Q', 'E', 'W'], early_skills: ['Q', 'E', 'W'], patch: '99.1.1',
  up_count: 0, down_count: 0, created_at: `2026-11-0${id - 100}T00:00:00Z`, counter: QUINN, logs: [],
  approve_note: null, reject_reason: null, hide_reason: null, hidden_at: null, reviewed_at: null, version: 1, edited_at: null, ...extra,
});
/** 테스트에서 쓰는 빌드 한 줄 (기본: 퀸 매치업에 공개된 빌드) */
export const fakeBuild = (id, author, extra) => build(id, author, extra);

const INITIAL_BUILDS = () => [
    build(101, null, { patch: '14.1.1', up_count: 1 }),
    build(102, { nickname: '탑신병자', level: 7, main_title: 'senior_researcher' }, { up_count: 5, down_count: 1 }),
    build(103, { nickname: '칭호없음', level: 3, main_title: null }, { up_count: 2 }),
    build(104, { nickname: '대기중', level: 1, main_title: null }, { status: 'pending', up_count: 99 }),
    build(105, { nickname: '영자(운)', level: 0, main_title: null }), // 운영자가 쓴 빌드 (점수 0)
];

export const TABLES = {
  builds: INITIAL_BUILDS(),
  counters: [
    {
      id: 1, target_champion: 'Darius', counter_champion: 'Quinn', sort_order: 1, status: 'approved',
      matchup_docs: {
        counter_id: 1, summary: '사거리로 일방적인 견제',
        level_notes: { 1: '1렙 내용', 2: '2렙', 3: '3렙', 4: '4렙 추가', 6: '6렙', 9: '9렙', 11: '11렙' },
        lane_cautions: 'E 사거리 주의', updated_at: '2026-11-01T09:00:00+00:00', revision_id: 7,
      },
    },
    { id: 2, target_champion: 'Darius', counter_champion: 'Vayne', sort_order: 0, status: 'pending', matchup_docs: null },
  ],
  profiles: [
    { id: 'u-old', nickname: '기존유저', role: 'user', xp: 0, level: 1, main_title: null },
  ],
  // 관계(proposer, editor, approver)는 select가 돌려주는 모양 그대로 넣어 둔다
  edit_proposals: [],
  doc_revisions: [],
  counter_status_log: [],
  counter_deletions: [],
  build_votes: [],
  notifications: [],
};

/** 테스트에서 쓰는 제안 한 줄 (기본: 기존유저가 보낸 대기 중 문서 수정) */
/** 새 카운터 제안에 담기는 빌드 (DB clean_build 모양) */
export const FAKE_PROPOSAL_BUILD = {
  runes: { primaryPath: 8000, keystone: 8010, primary: [9111, 9104, 8299], secondaryPath: 8400, secondary: [8446, 8444], shards: [5005, 5008, 5011] },
  summoner_spells: ['SummonerFlash', 'SummonerTeleport'], starting_items: ['1055', '2003'], core_items: ['3053', '3047', '6631'],
  skill_order: ['Q', 'E', 'W'], early_skills: ['Q', 'E', 'W'], patch: '99.1.1',
};

export function fakeProposal(extra = {}) {
  return {
    build: extra.type === 'new_counter' ? FAKE_PROPOSAL_BUILD : null,
    id: 501, type: 'doc_edit', target_champion: 'Darius', counter_champion: 'Quinn', counter_id: 1,
    content: { summary: '고친 요약', level_notes: { 1: '1렙 내용', 2: '2렙', 3: '3렙', 6: '6렙', 9: '9렙', 11: '11렙' }, lane_cautions: 'E 사거리 주의\n궁 조심' },
    status: 'pending', reject_reason: null, reviewed_at: null, created_at: '2026-11-01T10:00:00Z', base_revision_id: 7,
    revoke_reason: null, revoked_at: null, approve_note: null, revision_note: null, revision_requested_at: null, resubmitted_at: null,
    version: 1, edited_at: null, proposer_id: 'u-old', proposer: { nickname: '기존유저', level: 1, main_title: null }, ...extra,
  };
}

// 테스트가 바꾸는 상태. setupTests.js가 테스트마다 초기화한다.
export const fakeState = {
  error: null, session: null, initError: null, oauthCalls: [], linkCalls: [], linkError: null, listeners: new Set(),
  inserts: [], insertError: null, rpcCalls: [], rpcError: null,
};
const INITIAL_PROFILES = TABLES.profiles.map((p) => ({ ...p }));

export function resetFake() {
  fakeState.error = null;
  fakeState.session = null;
  fakeState.initError = null;
  fakeState.oauthCalls = [];
  fakeState.linkCalls = [];
  fakeState.linkError = null;
  fakeState.listeners.clear();
  TABLES.profiles = INITIAL_PROFILES.map((p) => ({ ...p }));
  TABLES.edit_proposals = [];
  TABLES.doc_revisions = [];
  TABLES.counter_status_log = [];
  TABLES.counter_deletions = [];
  TABLES.build_votes = [];
  TABLES.notifications = [];
  TABLES.builds = INITIAL_BUILDS();
  fakeState.inserts = [];
  fakeState.insertError = null;
  fakeState.rpcCalls = [];
  fakeState.rpcError = null;
}

/**
 * 테스트에서 "구글/카카오 로그인을 마치고 돌아온" 상태 만들기. DB 트리거처럼 프로필도 만든다.
 * user: 세션의 user에 덧붙일 값 (예: 이메일 없는 카카오 유저 { email: '', app_metadata: { provider: 'kakao' } })
 */
export function fakeLogin(id, profile = {}, user = {}) {
  if (!TABLES.profiles.some((p) => p.id === id)) {
    TABLES.profiles.push({ id, nickname: null, role: 'user', xp: 0, level: 1, main_title: null, ...profile });
  }
  fakeState.session = { user: { id, ...user }, access_token: 'fake' };
  fakeState.listeners.forEach((cb) => cb('SIGNED_IN', fakeState.session));
}

function query(table) {
  let rows = [...(TABLES[table] ?? [])];
  let single = false;
  let patch = null;
  let inserted = null;
  const q = {
    select: () => q,
    insert: (values) => { inserted = values; return q; },
    update: (values) => { patch = values; return q; },
    eq: (col, v) => { rows = rows.filter((r) => r[col] === v); return q; },
    is: (col, v) => { rows = rows.filter((r) => (r[col] ?? null) === v); return q; },
    in: (col, vs) => { rows = rows.filter((r) => vs.includes(r[col])); return q; },
    order: (col, { ascending = true } = {}) => {
      rows.sort((a, b) => (a[col] < b[col] ? -1 : a[col] > b[col] ? 1 : 0) * (ascending ? 1 : -1));
      return q;
    },
    maybeSingle: () => { single = true; return q; },
    then: (ok, fail) => Promise.resolve(run()).then(ok, fail),
  };
  function run() {
    if (fakeState.error) return { data: null, error: { message: fakeState.error } };
    if (inserted) {
      // DB 트리거·RLS가 낸 오류 흉내 (예: '이미 등록된 카운터예요.')
      if (fakeState.insertError) return { data: null, error: { message: fakeState.insertError } };
      fakeState.inserts.push({ table, values: inserted });
      if (table === 'builds') {
        const me = TABLES.profiles.find((p) => p.id === inserted.author_id);
        TABLES.builds.push(build(900 + TABLES.builds.length, me && { nickname: me.nickname, level: me.level, main_title: me.main_title }, {
          ...inserted, status: 'pending', created_at: new Date().toISOString(),
          counter: TABLES.counters.find((c) => c.id === inserted.counter_id) ?? null,
        }));
        return { data: null, error: null };
      }
      const proposer = TABLES.profiles.find((p) => p.id === inserted.proposer_id);
      TABLES[table].push({
        id: 900 + TABLES[table].length, status: 'pending', reject_reason: null, reviewed_at: null,
        created_at: new Date().toISOString(), base_revision_id: null, counter_id: null, ...inserted,
        proposer: proposer && { nickname: proposer.nickname, level: proposer.level, main_title: proposer.main_title },
      });
      return { data: null, error: null };
    }
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
  linkIdentity: async (args) => {
    fakeState.linkCalls.push(args);
    return fakeState.linkError ? { data: null, error: { message: fakeState.linkError } } : { data: {}, error: null };
  },
  // 진짜처럼 user.identities를 돌려준다 (fakeLogin의 user 인자로 넣는다)
  getUserIdentities: async () => ({ data: { identities: fakeState.session?.user.identities ?? [] }, error: null }),
  signOut: async () => {
    fakeState.session = null;
    fakeState.listeners.forEach((cb) => cb('SIGNED_OUT', null));
    return { error: null };
  },
};

// 운영자 전용 DB 함수 호출 기록. 오류는 fakeState.rpcError로 흉내 낸다 (예: '운영자만 할 수 있어요.')
async function rpc(name, args) {
  fakeState.rpcCalls.push({ name, args });
  if (fakeState.rpcError) return { data: null, error: { message: fakeState.rpcError, code: '42501' } };
  if (name === 'mark_notifications_read') {
    // DB 함수처럼 내 것만 읽음 처리
    const me = fakeState.session?.user.id;
    const mine = TABLES.notifications.filter((n) => args.p_ids.includes(n.id) && n.user_id === me && !n.read_at);
    mine.forEach((n) => { n.read_at = new Date().toISOString(); });
    return { data: mine.length, error: null };
  }
  if (name === 'vote_build') {
    // DB 함수처럼: 한 사람 한 표, null = 취소, 따봉 수 다시 세기
    const me = fakeState.session?.user.id;
    const b = TABLES.builds.find((x) => x.id === args.p_build_id);
    const old = TABLES.build_votes.find((v) => v.build_id === b.id && v.user_id === me);
    if (old) b[old.value === 1 ? 'up_count' : 'down_count'] -= 1;
    TABLES.build_votes = TABLES.build_votes.filter((v) => v !== old);
    if (args.p_value != null) {
      TABLES.build_votes.push({ build_id: b.id, user_id: me, value: args.p_value });
      b[args.p_value === 1 ? 'up_count' : 'down_count'] += 1;
    }
    return { data: { up: b.up_count, down: b.down_count, mine: args.p_value }, error: null };
  }
  return { data: null, error: null };
}

export function db() {
  return { from: query, auth, rpc };
}
