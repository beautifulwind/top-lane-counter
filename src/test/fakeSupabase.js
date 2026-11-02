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
    build(102, { nickname: '탑고수', level: 7, main_title: 'solid_heavy' }, { up_count: 5, down_count: 1 }),
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
  // 014 경험치·칭호 (내 기록만 넣는다 — RLS 흉내는 테스트가 그렇게 넣는 것으로)
  xp_events: [],
  user_titles: [],
  offmeta_champions: [],
  // 015 자유게시판 (author = select가 돌려주는 관계 모양)
  posts: [],
  post_comments: [],
  post_votes: [],
  reports: [],
  doc_comments: [],
  // 017 닉네임 변경 기록 (본인 것만 넣는다)
  nickname_changes: [],
  xp_levels: [[1, 0], [2, 100], [3, 300], [4, 600], [5, 1000], [6, 1500], [7, 2100], [8, 2800], [9, 3600], [10, 4500]]
    .map(([level, min_xp]) => ({ level, min_xp })),
  xp_rules: [
    ['new_counter', 100], ['doc_edit', 50], ['build', 30], ['vote', 2], ['vote_daily_cap', 40], ['level_step', 1000],
    ['title_top_addict', 1], ['title_tool_hater', 10], ['title_solid_heavy', 25], ['title_butcher_owner', 50],
    ['title_general', 100], ['title_offmeta', 5],
    ['post_edit_minutes', 60], ['comment_edit_minutes', 10], ['edit_grace_minutes', 5], ['nickname_change_days', 30],
  ].map(([key, value]) => ({ key, value })),
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
  inserts: [], insertError: null, rpcCalls: [], rpcError: null, boardError: null,
  functionCalls: [], functionError: null, // Edge Function 호출 (017 delete-account)
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
  TABLES.xp_events = [];
  TABLES.user_titles = [];
  TABLES.offmeta_champions = [];
  TABLES.posts = [];
  TABLES.post_comments = [];
  TABLES.post_votes = [];
  TABLES.reports = [];
  TABLES.doc_comments = [];
  TABLES.nickname_changes = [];
  TABLES.builds = INITIAL_BUILDS();
  fakeState.functionCalls = [];
  fakeState.functionError = null;
  fakeState.inserts = [];
  fakeState.insertError = null;
  fakeState.rpcCalls = [];
  fakeState.rpcError = null;
  fakeState.boardError = null;
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

const withCounter = (c) => {
  if (!c) return null;
  const k = TABLES.counters.find((x) => x.id === c.counter_id);
  return { ...c, counter: k ? { id: k.id, target_champion: k.target_champion, counter_champion: k.counter_champion, status: k.status } : null };
};
const isAdminNow = () => TABLES.profiles.find((p) => p.id === fakeState.session?.user.id)?.role === 'admin';
/** RLS 흉내: 숨긴 글·댓글(숨긴 글의 댓글 포함)은 운영자에게만 */
function visibleRows(table) {
  const rows = TABLES[table] ?? [];
  if (table === 'reports') {
    // 관계 (post, comment) 는 select가 붙여 주는 모양 그대로
    return rows.map((r) => ({
      ...r,
      post: r.post_id != null ? TABLES.posts.find((p) => p.id === r.post_id) ?? null : null,
      comment: r.comment_id != null ? TABLES.post_comments.find((c) => c.id === r.comment_id) ?? null : null,
      doc_comment: r.doc_comment_id != null ? withCounter(TABLES.doc_comments.find((c) => c.id === r.doc_comment_id)) : null,
    }));
  }
  if (table === 'doc_comments') {
    const all = rows.map(withCounter);
    // RLS 흉내: 숨긴 댓글·숨긴 카운터의 댓글은 운영자에게만
    return isAdminNow() ? all : all.filter((c) => c.status === 'visible' && c.counter?.status === 'approved');
  }
  if (isAdminNow()) return rows;
  if (table === 'posts') return rows.filter((p) => p.status === 'visible');
  if (table === 'post_comments') {
    return rows.filter((c) => c.status === 'visible' && TABLES.posts.find((p) => p.id === c.post_id)?.status === 'visible');
  }
  return rows;
}

function query(table) {
  let rows = [...visibleRows(table)];
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
    limit: (n) => { rows = rows.slice(0, n); return q; },
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
      // DB 제약 흉내: 대표 칭호는 내가 가진 칭호만 (profiles_main_title_owned)
      if (patch.main_title && !TABLES.user_titles.some((t) => t.user_id === me && t.title_key === patch.main_title)) {
        return { data: null, error: { code: '23503', message: 'violates foreign key constraint "profiles_main_title_owned"' } };
      }
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

// Edge Function 흉내: delete-account는 탈퇴하면 세션을 끝낸다. 실패는 fakeState.functionError (DB 문구)
const functions = {
  invoke: async (name, { body } = {}) => {
    fakeState.functionCalls.push({ name, body });
    if (fakeState.functionError) {
      const message = fakeState.functionError;
      return { data: null, error: { message: 'Edge Function returned a non-2xx status code', context: { json: async () => ({ error: message }) } } };
    }
    return { data: { ok: true }, error: null };
  },
};

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
  if (name === 'add_offmeta') {
    TABLES.offmeta_champions.push({ champion_id: args.p_champion, created_at: new Date().toISOString() });
    return { data: null, error: null };
  }
  if (name === 'remove_offmeta') {
    TABLES.offmeta_champions = TABLES.offmeta_champions.filter((o) => o.champion_id !== args.p_champion);
    return { data: null, error: null };
  }
  const board = boardRpc(name, args);
  if (board) return board;
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

const me = () => fakeState.session?.user.id;
const person = (id) => {
  const p = TABLES.profiles.find((x) => x.id === id);
  return p ? { nickname: p.nickname, level: p.level, main_title: p.main_title } : null;
};
const fail = (message) => ({ data: null, error: { message } });
const ok = (data = null) => ({ data, error: null });

/** 테스트에서 쓰는 글 한 줄 (기본: 기존유저가 쓴 보이는 글) */
export function fakePost(id, extra = {}) {
  return {
    id, author_id: 'u-old', author: { nickname: '기존유저', level: 1, main_title: null }, title: `글 ${id}`, body: `본문 ${id}`,
    status: 'visible', hidden_note: null, hidden_at: null, edited_at: null, deleted_at: null, comment_count: 0, up_count: 0,
    created_at: `2026-11-01T0${id % 10}:00:00Z`, ...extra,
  };
}
/** 테스트에서 쓰는 문서 댓글 한 줄 (기본: 퀸 매치업, 기존유저) */
export function fakeDocComment(id, extra = {}) {
  return {
    id, counter_id: 1, author_id: 'u-old', author: { nickname: '기존유저', level: 1, main_title: null }, body: `문서 댓글 ${id}`,
    status: 'visible', hidden_note: null, hidden_at: null, edited_at: null, edit_grace_until: null,
    created_at: new Date().toISOString(), ...extra,
  };
}
export function fakeComment(id, postId, extra = {}) {
  return {
    id, post_id: postId, author_id: 'u-old', author: { nickname: '기존유저', level: 1, main_title: null }, body: `댓글 ${id}`,
    status: 'visible', hidden_note: null, hidden_at: null, edited_at: null, created_at: `2026-11-01T1${id % 10}:00:00Z`, ...extra,
  };
}

/** 게시판 DB 함수 흉내 (015). 권한·간격 같은 검사는 DB 검사(board_test.sql)에서 하고, 여기서는 화면 흐름만 */
function boardRpc(name, args) {
  const post = (id) => TABLES.posts.find((p) => p.id === id);
  const comment = (id) => TABLES.post_comments.find((c) => c.id === id);
  const recount = (pid) => {
    const p = post(pid);
    if (p) p.comment_count = TABLES.post_comments.filter((c) => c.post_id === pid && c.status === 'visible').length;
  };
  switch (name) {
    case 'board_page': {
      const q = (args.p_q ?? '').toLowerCase();
      let rows = visibleRows('posts');
      if (q) rows = rows.filter((p) => !p.deleted_at && (p.title.toLowerCase().includes(q) || p.body.toLowerCase().includes(q)));
      rows = [...rows].sort((a, b) => (a.created_at < b.created_at ? 1 : a.created_at > b.created_at ? -1 : b.id - a.id));
      const from = (args.p_page - 1) * args.p_size;
      return ok({
        total: rows.length, size: args.p_size,
        rows: rows.slice(from, from + args.p_size).map((p) => ({
          id: p.id, title: p.title, status: p.status, deleted: p.deleted_at != null, comment_count: p.comment_count,
          up_count: p.up_count, created_at: p.created_at, edited_at: p.edited_at, author: p.author,
        })),
      });
    }
    case 'create_post': {
      if (fakeState.boardError) return fail(fakeState.boardError);
      const id = 700 + TABLES.posts.length;
      TABLES.posts.push(fakePost(id, {
        author_id: me(), author: person(me()), title: args.p_title.trim(), body: args.p_body.trim(), created_at: new Date().toISOString(),
      }));
      return ok(id);
    }
    case 'begin_edit': {
      if (fakeState.boardError) return fail(fakeState.boardError);
      return ok(new Date(Date.now() + 5 * 60_000).toISOString());
    }
    case 'create_doc_comment': {
      if (fakeState.boardError) return fail(fakeState.boardError);
      const id = 900 + TABLES.doc_comments.length;
      TABLES.doc_comments.push(fakeDocComment(id, {
        counter_id: args.p_counter, author_id: me(), author: person(me()), body: args.p_body.trim(),
      }));
      return ok(id);
    }
    case 'edit_doc_comment':
      if (fakeState.boardError) return fail(fakeState.boardError);
      Object.assign(TABLES.doc_comments.find((c) => c.id === args.p_id), { body: args.p_body.trim(), edited_at: new Date().toISOString() });
      return ok();
    case 'delete_my_doc_comment':
      TABLES.doc_comments = TABLES.doc_comments.filter((c) => c.id !== args.p_id);
      return ok();
    case 'report_doc_comment':
      TABLES.reports.push({
        id: 600 + TABLES.reports.length, reporter_id: me(), post_id: null, comment_id: null, doc_comment_id: args.p_id,
        reason: args.p_reason, detail: args.p_detail, status: 'open', created_at: new Date().toISOString(), reporter: person(me()),
      });
      return ok();
    case 'hide_doc_comment':
    case 'restore_doc_comment': {
      const row = TABLES.doc_comments.find((c) => c.id === args.p_id);
      if (name === 'hide_doc_comment') {
        Object.assign(row, { status: 'hidden', hidden_note: args.p_note, hidden_at: new Date().toISOString() });
        TABLES.reports.filter((r) => r.doc_comment_id === row.id && r.status === 'open').forEach((r) => { r.status = 'resolved'; });
      } else {
        Object.assign(row, { status: 'visible', hidden_note: null, hidden_at: null });
      }
      return ok();
    }
    case 'edit_post':
      Object.assign(post(args.p_id), { title: args.p_title.trim(), body: args.p_body.trim(), edited_at: new Date().toISOString() });
      return ok();
    case 'delete_my_post': {
      const p = post(args.p_id);
      if (TABLES.post_comments.some((c) => c.post_id === p.id && c.author_id !== me())) {
        Object.assign(p, { title: '', body: '', deleted_at: new Date().toISOString(), up_count: 0 });
        return ok('soft');
      }
      TABLES.posts = TABLES.posts.filter((x) => x !== p);
      return ok('hard');
    }
    case 'vote_post': {
      const p = post(args.p_id);
      const old = TABLES.post_votes.find((v) => v.post_id === p.id && v.user_id === me());
      if (old) TABLES.post_votes = TABLES.post_votes.filter((v) => v !== old);
      else TABLES.post_votes.push({ post_id: p.id, user_id: me() });
      p.up_count = TABLES.post_votes.filter((v) => v.post_id === p.id).length;
      return ok({ up: p.up_count, mine: !old });
    }
    case 'create_comment': {
      if (fakeState.boardError) return fail(fakeState.boardError);
      const id = 800 + TABLES.post_comments.length;
      TABLES.post_comments.push(fakeComment(id, args.p_post, {
        author_id: me(), author: person(me()), body: args.p_body.trim(), created_at: new Date().toISOString(),
      }));
      recount(args.p_post);
      return ok(id);
    }
    case 'edit_comment':
      if (fakeState.boardError) return fail(fakeState.boardError);
      Object.assign(comment(args.p_id), { body: args.p_body.trim(), edited_at: new Date().toISOString() });
      return ok();
    case 'delete_my_comment': {
      const c = comment(args.p_id);
      TABLES.post_comments = TABLES.post_comments.filter((x) => x !== c);
      recount(c.post_id);
      return ok();
    }
    case 'report_post':
    case 'report_comment': {
      const key = name === 'report_post' ? 'post_id' : 'comment_id';
      if (TABLES.reports.some((r) => r.reporter_id === me() && r[key] === args.p_id)) {
        return fail(name === 'report_post' ? '이미 신고한 글이에요.' : '이미 신고한 댓글이에요.');
      }
      TABLES.reports.push({
        id: 600 + TABLES.reports.length, reporter_id: me(), post_id: null, comment_id: null, [key]: args.p_id,
        reason: args.p_reason, detail: args.p_detail, status: 'open', created_at: new Date().toISOString(), reporter: person(me()),
      });
      return ok();
    }
    case 'hide_post':
    case 'hide_comment':
    case 'restore_post':
    case 'restore_comment': {
      const row = name.endsWith('post') ? post(args.p_id) : comment(args.p_id);
      if (name.startsWith('hide')) {
        Object.assign(row, { status: 'hidden', hidden_note: args.p_note, hidden_at: new Date().toISOString() });
        const key = name.endsWith('post') ? 'post_id' : 'comment_id';
        TABLES.reports.filter((r) => r[key] === row.id && r.status === 'open').forEach((r) => { r.status = 'resolved'; });
      } else {
        Object.assign(row, { status: 'visible', hidden_note: null, hidden_at: null });
      }
      if (!name.endsWith('post')) recount(row.post_id);
      return ok();
    }
    case 'dismiss_reports': {
      const open = TABLES.reports.filter((r) => r.status === 'open'
        && ((args.p_post != null && r.post_id === args.p_post) || (args.p_comment != null && r.comment_id === args.p_comment)
          || (args.p_doc_comment != null && r.doc_comment_id === args.p_doc_comment)));
      open.forEach((r) => { r.status = 'dismissed'; });
      return ok(open.length);
    }
    default:
      return null;
  }
}

export function db() {
  return { from: query, auth, rpc, functions };
}
