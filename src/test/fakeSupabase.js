// 테스트용 가짜 Supabase. src/api/supabase.js의 db()를 대신한다 (setupTests.js에서 연결).
// 행 모양은 supabase/schema.sql + content.js의 select(관계 포함)가 돌려주는 모양을 따른다.
import { hasReservedMark, mimicsInfluencer } from '../lib/nickname';
import { hostOf, linkProblem } from '../lib/links';
const runes = (keystone) => ({ primaryPath: 8000, keystone, primary: [9111, 9104, 8014], secondaryPath: 8100, secondary: [8143, 8106], shards: [5005, 5008, 5011] });
const QUINN = { id: 1, target_champion: 'Darius', counter_champion: 'Quinn', status: 'approved' };
const QUINN_DOC = {
  summary: '사거리로 일방적인 견제',
  level_notes: { 1: '1렙 내용', 2: '2렙', 3: '3렙', 4: '4렙 추가', 6: '6렙', 9: '9렙', 11: '11렙' },
  lane_cautions: 'E 사거리 주의',
};
const build = (id, author, extra = {}) => ({
  id, counter_id: 1, author, author_id: author ? `u-${id}` : null, proposal_id: null, status: 'approved', runes: runes(8005),
  summoner_spells: ['SummonerFlash', 'SummonerTeleport'], starting_items: ['1055', '2003'],
  core_items: ['6672', '3006', '3031'], max_skill: 'Q', patch: '99.1.1',
  up_count: 0, down_count: 0, created_at: `2026-11-0${id - 100}T00:00:00Z`, counter: QUINN, logs: [],
  approve_note: null, reject_reason: null, hide_reason: null, hidden_at: null, reviewed_at: null, version: 1, edited_at: null,
  // 038: 빌드 = 공략 한 벌. 038 이전으로 예전 문서 내용이 공개 빌드마다 채워진 모양 (이름 없음 → "빌드 N")
  name: null, seq: id - 100, summary: QUINN_DOC.summary, level_notes: { ...QUINN_DOC.level_notes }, lane_cautions: QUINN_DOC.lane_cautions,
  updated_at: `2026-11-0${id - 100}T00:00:00Z`, ...extra,
});
/** 테스트에서 쓰는 빌드 한 줄 (기본: 퀸 매치업에 공개된 빌드) */
export const fakeBuild = (id, author, extra) => build(id, author, extra);

const INITIAL_BUILDS = () => [
    build(101, null, { patch: '14.1.1', up_count: 1 }),
    build(102, { nickname: '탑고수', level: 7, main_title: 'solid_heavy' }, { up_count: 5, down_count: 1 }),
    build(103, { nickname: '칭호없음', level: 3, main_title: null }, { up_count: 2 }),
    build(104, { nickname: '대기중', level: 1, main_title: null }, { status: 'pending', up_count: 99 }),
    build(105, { nickname: '영자', role: 'admin', level: 0, main_title: null }), // 운영자가 쓴 빌드 (점수 0)
];

export const TABLES = {
  builds: INITIAL_BUILDS(),
  counters: [
    {
      id: 1, target_champion: 'Darius', counter_champion: 'Quinn', sort_order: 1, status: 'approved',
      matchup_docs: {
        counter_id: 1, summary: QUINN_DOC.summary, level_notes: { ...QUINN_DOC.level_notes },
        lane_cautions: QUINN_DOC.lane_cautions, updated_at: '2026-11-01T09:00:00+00:00', revision_id: 7,
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
  influencer_applications: [], // 046 장인 신청 (influencerRpc가 쓴다)
  ext_links: [], // 047 장인 외부 링크 (linkRpc가 쓴다)
  link_domains: LINK_DOMAINS(), // 047 허용 사이트 9개
  link_reports: [], // 047 링크 신고 { id, link_id, reporter_id, reason, detail, status, created_at }
  influencer_follows: [], // 050 팔로우 { follower_id, influencer_id, created_at } (followRpc가 쓴다)
  // 014 경험치·칭호 (내 기록만 넣는다 — RLS 흉내는 테스트가 그렇게 넣는 것으로)
  xp_events: [],
  user_titles: [],
  offmeta_champions: [],
  // 015 자유게시판 (author = select가 돌려주는 관계 모양)
  posts: [],
  post_comments: [],
  post_votes: [],
  reports: [],
  // 043 오류 신고 (화면은 함수로만 읽고 쓴다)
  wiki_reports: [],
  doc_comments: [],
  // 032 문의하기 (user = select가 붙여 주는 보낸 사람 관계)
  inquiries: [],
  // 017 닉네임 변경 기록 (본인 것만 넣는다)
  nickname_changes: [],
  // 037 웹 푸시: 기기 알림 주소·종류별 설정 (RLS 흉내: 본인 것만 보이고 지워진다)
  push_subscriptions: [],
  push_settings: [],
  // 018 아이템 가격표 (DB 기준 패치만 화면에 쓴다)
  item_prices: [{ id: '1055', gold: 450, patch: '99.1.1' }, { id: '2003', gold: 50, patch: '99.1.1' }],
  xp_levels: [[1, 0], [2, 100], [3, 300], [4, 600], [5, 1000], [6, 1500], [7, 2100], [8, 2800], [9, 3600], [10, 4500]]
    .map(([level, min_xp]) => ({ level, min_xp })),
  xp_rules: [
    ['new_counter', 100], ['doc_edit', 50], ['build', 30], ['vote', 2], ['vote_daily_cap', 40], ['level_step', 1000],
    ['title_top_addict', 1], ['title_tool_hater', 10], ['title_solid_heavy', 25], ['title_butcher_owner', 50],
    ['title_general', 100], ['title_offmeta', 5],
    ['post_edit_minutes', 60], ['comment_edit_minutes', 10], ['edit_grace_minutes', 5], ['nickname_change_days', 30],
    ['starting_gold_max', 500],
    ['media_post_max', 4], ['media_post_gif_max', 1], ['media_comment_max', 1], ['media_photo_max_kb', 600], ['media_gif_max_kb', 3072],
  ].map(([key, value]) => ({ key, value })),
};

/** 테스트에서 쓰는 제안 한 줄 (기본: 기존유저가 보낸 대기 중 문서 수정) */
/** 새 카운터 제안에 담기는 빌드 (DB clean_build 모양) */
export const FAKE_PROPOSAL_BUILD = {
  runes: { primaryPath: 8000, keystone: 8010, primary: [9111, 9104, 8299], secondaryPath: 8400, secondary: [8446, 8444], shards: [5005, 5008, 5011] },
  summoner_spells: ['SummonerFlash', 'SummonerTeleport'], starting_items: ['1055', '2003'], core_items: ['3053', '3047', '6631'],
  max_skill: 'Q', patch: '99.1.1',
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

/** 운영자 사진 저장 공간 (023 media_usage) 기본: 아무것도 없음 */
export const EMPTY_USAGE = () => ({
  bytes: 0, files: 0, gif_bytes: 0, gifs: 0, hidden_bytes: 0, recent_bytes: 0, recent_files: 0, trash: 0, orphans: 0, top: [],
  total_mb: 1024, warn_mb: 800, block_mb: 900,
});
// 테스트가 바꾸는 상태. setupTests.js가 테스트마다 초기화한다.
export const fakeState = {
  error: null, session: null, initError: null, oauthCalls: [], linkCalls: [], linkError: null, listeners: new Set(),
  inserts: [], insertError: null, pendingCounts: null, pendingCountsAsked: 0, rpcCalls: [], memberCalls: [], memberStats: { total: 0, members: 0, guests: 0, google: 0, kakao: 0, both: 0, new_7d: 0, new_7d_members: 0 }, members: [], memberInfo: {}, memberDetail: {}, deletedWritings: {}, buildRevisions: {}, rpcError: null, rpcErrorCode: null, reviewCalls: [], reviewers: {}, boardError: null,
  functionCalls: [], functionError: null, // Edge Function 호출 (017 delete-account)
  anonCalls: [], anonError: null, anonDelay: null, hideCounts: {}, signOutCalls: [], touched: 0, // 비회원 (020)
  uploads: [], uploadError: null, mediaProblem: null, mediaUsage: EMPTY_USAGE(), // 사진 (023, mediaUsage = media_usage 결과)
};
const INITIAL_PROFILES = TABLES.profiles.map((p) => ({ ...p }));
const INITIAL_COUNTERS = TABLES.counters.map((c) => structuredClone(c));

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
  TABLES.influencer_applications = [];
  TABLES.ext_links = [];
  TABLES.link_domains = LINK_DOMAINS();
  TABLES.link_reports = [];
  TABLES.influencer_follows = [];
  fakeState.followStatusCalls = [];
  fakeState.influencerNextAt = null;
  TABLES.xp_events = [];
  TABLES.user_titles = [];
  TABLES.offmeta_champions = [];
  TABLES.posts = [];
  TABLES.post_comments = [];
  TABLES.post_votes = [];
  TABLES.reports = [];
  TABLES.wiki_reports = [];
  TABLES.moderation_log = [];
  TABLES.doc_comments = [];
  TABLES.nickname_changes = [];
  TABLES.inquiries = [];
  TABLES.push_subscriptions = [];
  TABLES.push_settings = [];
  TABLES.item_prices = [{ id: '1055', gold: 450, patch: '99.1.1' }, { id: '2003', gold: 50, patch: '99.1.1' }];
  TABLES.builds = INITIAL_BUILDS();
  TABLES.counters = INITIAL_COUNTERS.map((c) => structuredClone(c)); // 038: 새 상대법 등록이 counters에 줄을 더한다
  fakeState.functionCalls = [];
  fakeState.functionError = null;
  fakeState.inserts = [];
  fakeState.insertError = null;
  fakeState.rpcCalls = [];
  fakeState.contributors = {};
  fakeState.editorCounts = {};
  fakeState.memberCalls = [];
  fakeState.memberStats = { total: 0, members: 0, guests: 0, google: 0, kakao: 0, both: 0, new_7d: 0, new_7d_members: 0 };
  fakeState.members = [];
  fakeState.memberInfo = {};
  fakeState.newMembers = [];
  fakeState.memberDetail = {};
  fakeState.buildRevisions = {};
  fakeState.revertRemoved = 0;
  fakeState.deletedWritings = {};
  fakeState.rpcError = null;
  fakeState.pendingCounts = null;
  fakeState.pendingCountsAsked = 0;
  fakeState.rpcErrorCode = null;
  fakeState.reviewCalls = [];
  fakeState.reviewers = {};
  fakeState.boardError = null;
  fakeState.anonCalls = [];
  fakeState.anonError = null;
  fakeState.anonDelay = null;
  fakeState.hideCounts = {};
  fakeState.signOutCalls = [];
  fakeState.touched = 0;
  fakeState.uploads = [];
  fakeState.uploadError = null;
  fakeState.mediaProblem = null;
  fakeState.mediaUsage = EMPTY_USAGE();
}

/** 비회원(익명 로그인)으로 들어온 상태. DB 트리거처럼 is_guest 프로필을 만든다 */
export function fakeGuestLogin(id, profile = {}) {
  fakeLogin(id, { is_guest: true, ...profile }, { is_anonymous: true });
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
const meNow = () => TABLES.profiles.find((p) => p.id === fakeState.session?.user.id);
const roleNow = () => meNow()?.role;
// 034: DB의 is_admin·is_staff처럼 운영자 모드를 끈 운영자는 운영진이 아니다 (operator_mode가 없으면 켜짐)
const isAdminNow = () => roleNow() === 'admin' && meNow()?.operator_mode !== false;
const isStaffNow = () => isAdminNow() || roleNow() === 'moderator';
const STAFF_NOTICE_KINDS = ['proposal_submitted', 'build_submitted', 'inquiry_received', 'matchup_created', 'build_created', 'error_reported', 'report_received'];
const operatorModeOffNow = () => roleNow() === 'admin' && meNow()?.operator_mode === false;
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
  if (table === 'notifications') {
    // select가 붙여 주는 관계 (counter, proposal, build.counter, post) — 테스트가 직접 넣은 값이 있으면 그대로
    const counterOf = (id) => {
      const k = TABLES.counters.find((x) => x.id === id);
      return k ? { target_champion: k.target_champion, counter_champion: k.counter_champion, status: k.status } : null;
    };
    // RLS 흉내 (034): 운영자 모드를 끈 동안 운영진 알림은 안 보인다
    return rows.filter((n) => !(operatorModeOffNow() && STAFF_NOTICE_KINDS.includes(n.kind))).map((n) => {
      const p = n.proposal_id != null ? TABLES.edit_proposals?.find((x) => x.id === n.proposal_id) : null;
      const b = n.build_id != null ? TABLES.builds.find((x) => x.id === n.build_id) : null;
      const post = n.post_id != null ? TABLES.posts.find((x) => x.id === n.post_id && (x.status === 'visible' || isStaffNow())) : null;
      return {
        read_at: null,
        ...n,
        counter: n.counter !== undefined ? n.counter : counterOf(n.counter_id),
        proposal: n.proposal !== undefined ? n.proposal : p ? { type: p.type, target_champion: p.target_champion, counter_champion: p.counter_champion } : null,
        // 050: 공개 빌드(또는 내 빌드)만 작성자를 읽을 수 있다 — 숨겨진 남의 빌드는 RLS처럼 null
        build: n.build !== undefined ? n.build : b && (b.status === 'approved' || b.author_id === fakeState.session?.user.id) ? { author_id: b.author_id, counter: counterOf(b.counter_id) } : null,
        post: n.post !== undefined ? n.post : post ? { title: post.title } : null,
      };
    });
  }
  if (table === 'doc_comments') {
    const all = rows.map(withCounter);
    // RLS 흉내: 숨긴 댓글·숨긴 카운터의 댓글은 운영자에게만
    return isStaffNow() ? all : all.filter((c) => c.status === 'visible' && c.counter?.status === 'approved');
  }
  if (table === 'moderation_log') return isAdminNow() ? rows : [];
  // 038: 챔피언 목록이 counters → builds(요약·추천)를 같이 읽는다 (RLS: 공개 빌드는 누구나)
  if (table === 'counters') return rows.map((c) => ({ ...c, builds: TABLES.builds.filter((b) => b.counter_id === c.id) }));
  if (table === 'push_subscriptions' || table === 'push_settings') return rows.filter((r) => r.user_id === fakeState.session?.user.id);
  if (table === 'inquiries') {
    // 032 RLS 흉내: 본인 것 / 운영자는 전부 / 감독관은 계정·탈퇴(account) 빼고. user = 보낸 사람 관계
    const mine = fakeState.session?.user.id;
    return rows
      .filter((r) => r.user_id === mine || isAdminNow() || (roleNow() === 'moderator' && r.category !== 'account'))
      .map((r) => ({ answer: null, answered_at: null, user: r.user ?? person(r.user_id), ...r }));
  }
  if (isStaffNow()) return rows;
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
  let upserted = null;
  let removing = false;
  const q = {
    select: () => q,
    insert: (values) => { inserted = values; return q; },
    upsert: (values, { onConflict } = {}) => { upserted = { values, key: onConflict }; return q; },
    delete: () => { removing = true; return q; },
    update: (values) => { patch = values; return q; },
    eq: (col, v) => { rows = rows.filter((r) => r[col] === v); return q; },
    is: (col, v) => { rows = rows.filter((r) => (r[col] ?? null) === v); return q; },
    in: (col, vs) => { rows = rows.filter((r) => vs.includes(r[col])); return q; },
    lt: (col, v) => { rows = rows.filter((r) => r[col] < v); return q; },
    ilike: (col, pattern) => {
      const word = pattern.replace(/^%|%$/g, '').replace(/\\([\\%_])/g, '$1').toLowerCase();
      rows = rows.filter((r) => (r[col] ?? '').toLowerCase().includes(word));
      return q;
    },
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
    const me = fakeState.session?.user.id;
    if (removing) {
      // RLS 흉내: 보이는(본인) 줄만 지워진다
      TABLES[table] = TABLES[table].filter((r) => !rows.includes(r));
      return { data: null, error: null };
    }
    if (upserted) {
      const { values, key } = upserted;
      if (values.user_id !== me) return { data: null, error: { code: '42501', message: 'new row violates row-level security policy' } };
      const old = TABLES[table].find((r) => r[key] === values[key]);
      if (old) Object.assign(old, values);
      else TABLES[table].push({ ...values });
      return { data: null, error: null };
    }
    if (inserted && table === 'push_subscriptions') {
      if (inserted.user_id !== me) return { data: null, error: { code: '42501', message: 'new row violates row-level security policy' } };
      if (TABLES.push_subscriptions.some((r) => r.endpoint === inserted.endpoint)) {
        return { data: null, error: { code: '23505', message: 'duplicate key value violates unique constraint' } };
      }
      fakeState.inserts.push({ table, values: inserted });
      TABLES.push_subscriptions.push({ id: TABLES.push_subscriptions.length + 1, ...inserted });
      return { data: null, error: null };
    }
    if (inserted) {
      // DB 트리거·RLS가 낸 오류 흉내 (예: '이미 등록된 카운터입니다.')
      if (fakeState.insertError) return { data: null, error: { message: fakeState.insertError } };
      fakeState.inserts.push({ table, values: inserted });
      if (table === 'builds') {
        const me = TABLES.profiles.find((p) => p.id === inserted.author_id);
        TABLES.builds.push(build(900 + TABLES.builds.length, me && { nickname: me.nickname, role: me.role, level: me.level, main_title: me.main_title }, {
          ...inserted, status: 'pending', created_at: new Date().toISOString(),
          counter: TABLES.counters.find((c) => c.id === inserted.counter_id) ?? null,
        }));
        return { data: null, error: null };
      }
      const proposer = TABLES.profiles.find((p) => p.id === inserted.proposer_id);
      TABLES[table].push({
        id: 900 + TABLES[table].length, status: 'pending', reject_reason: null, reviewed_at: null,
        created_at: new Date().toISOString(), base_revision_id: null, counter_id: null, ...inserted,
        proposer: proposer && { nickname: proposer.nickname, role: proposer.role, level: proposer.level, main_title: proposer.main_title },
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
      if (patch.nickname && hasReservedMark(patch.nickname)) { // 029 트리거 흉내
        return { data: null, error: { code: '23514', message: '닉네임에는 (운)·(감)을 쓸 수 없습니다.' } };
      }
      if (patch.nickname && mimicsInfluencer(patch.nickname)) { // 046 트리거 흉내
        return { data: null, error: { code: '23514', message: '닉네임에는 [장인]·(장인)을 쓸 수 없고, "장인 "으로 시작할 수 없습니다.' } };
      }
      const cur = TABLES[table].find((r) => r.id === me);
      if (patch.nickname && cur?.nickname && patch.nickname !== cur.nickname) { // 046 keep_nickname 흉내
        if (cur.influencer) return { data: null, error: { code: '42501', message: '인증된 장인은 닉네임을 직접 바꿀 수 없습니다. 바꾸려면 [문의하기]로 운영자에게 알려 주세요.' } };
        if (cur.nickname_state === 'pending') return { data: null, error: { code: '42501', message: '장인 인증 신청을 심사하는 동안에는 닉네임을 바꿀 수 없습니다. 신청을 취소하면 바꿀 수 있습니다.' } };
        if (cur.nickname_state === 'yielding') Object.assign(patch, { nickname_state: null, nickname_reset_at: null });
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
  invoke: async (name, { body, method } = {}) => {
    fakeState.functionCalls.push({ name, body, ...(method ? { method } : {}) });
    if (name === 'web-push' && method === 'GET') return { data: { publicKey: 'BFAKE-test-public-key_only' }, error: null };
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
  // 비회원 시작 (020). 진짜처럼 is_anonymous 유저 + 트리거가 is_guest 프로필
  signInAnonymously: async (args) => {
    fakeState.anonCalls.push(args);
    if (fakeState.anonDelay) await fakeState.anonDelay; // 느린 네트워크 흉내
    if (fakeState.anonError) return { data: null, error: { message: fakeState.anonError } };
    fakeGuestLogin('guest-1');
    return { data: { session: fakeState.session }, error: null };
  },
  signOut: async (args) => {
    fakeState.signOutCalls.push(args);
    fakeState.session = null;
    fakeState.listeners.forEach((cb) => cb('SIGNED_OUT', null));
    return { error: null };
  },
};

// 운영자 전용 DB 함수 호출 기록. 오류는 fakeState.rpcError로 흉내 낸다 (예: '운영자만 할 수 있습니다.')
async function rpc(name, args) {
  if (name === 'hide_counts') {
    // 운영자 신고 목록이 알아서 부르는 것이라 rpcCalls에는 넣지 않는다. fakeState.hideCounts = { 작성자id: 횟수 }
    if (!isStaffNow()) return { data: null, error: { message: '운영진만 할 수 있습니다.', code: '42501' } };
    return { data: { days: 90, counts: Object.fromEntries(args.p_users.map((u) => [u, fakeState.hideCounts[u] ?? 0])) }, error: null };
  }
  if (name === 'open_reports_for_moderator') {
    // 030: 신고자는 빼고, 감독관이 처리할 수 있는 것만 (테스트는 reports 표 그대로 넣는다)
    if (!isStaffNow()) return { data: null, error: { message: '운영진만 할 수 있습니다.', code: '42501' } };
    fakeState.moderatorReportsAsked = true;
    return { data: visibleRows('reports').filter((r) => r.status === 'open').map((r) => ({ ...r, reporter_id: null, reporter: null })), error: null };
  }
  if (['start_proposal_review', 'end_proposal_review', 'proposal_reviewers'].includes(name)) {
    // 031 "검토 중" 표시: 화면이 알아서 부르는 것이라 rpcCalls에는 넣지 않고 reviewCalls에 남긴다.
    // fakeState.reviewers = { 제안id: [{ nickname, role, started_at }] } (나 말고 검토 중인 사람)
    if (!isStaffNow()) return { data: null, error: { message: '운영진만 할 수 있습니다.', code: '42501' } };
    fakeState.reviewCalls.push({ name, args });
    if (name === 'start_proposal_review') return { data: fakeState.reviewers[args.p_id] ?? [], error: null };
    if (name === 'proposal_reviewers') {
      return { data: Object.fromEntries(args.p_ids.filter((id) => fakeState.reviewers[id]?.length).map((id) => [String(id), fakeState.reviewers[id]])), error: null };
    }
    return { data: null, error: null };
  }
  if (name === 'admin_pending_counts') {
    // 033: 메뉴가 열릴 때 알아서 부르는 것이라 rpcCalls에는 넣지 않는다. fakeState.pendingCounts = { proposals, builds, inquiries } (없으면 0)
    if (!isStaffNow()) return { data: null, error: { message: '운영진만 할 수 있습니다.', code: '42501' } };
    fakeState.pendingCountsAsked += 1;
    if (fakeState.pendingCounts === 'error') return { data: null, error: { message: 'function admin_pending_counts() does not exist', code: '42883' } };
    return { data: { proposals: 0, builds: 0, inquiries: 0, wiki_reports: 0, influencers: 0, ...fakeState.pendingCounts }, error: null };
  }
  if (['admin_member_stats', 'admin_search_members', 'admin_member_info', 'admin_member_list', 'admin_member_detail', 'admin_deleted_writings', 'admin_new_members'].includes(name)) {
    // 036: 운영자 전용 (감독관·일반 회원·운영자 모드 끈 운영자는 거부). 화면이 알아서 부르는 것이라 rpcCalls에는 넣지 않는다.
    // fakeState.memberStats = 숫자들, fakeState.members = 프로필 줄들 (검색은 부분 일치, 최대 10명), fakeState.memberInfo = { id: 정보 }
    if (!isAdminNow()) return { data: null, error: { message: '운영자만 할 수 있습니다.', code: '42501' } };
    fakeState.memberCalls.push({ name, args });
    if (name === 'admin_member_stats') return { data: fakeState.memberStats, error: null };
    if (name === 'admin_search_members') {
      const q = args.p_query.trim().toLowerCase();
      return { data: fakeState.members.filter((m) => m.nickname.toLowerCase().includes(q)).slice(0, 10), error: null };
    }
    if (name === 'admin_member_list') {
      // 042: 최근 가입 순 (fakeState.members 순서가 아니라 created_at), 닉네임 부분 일치, 역할 거르기, 쪽 나누기
      const q = (args.p_query ?? '').trim().toLowerCase();
      const source = fakeState.members.length ? fakeState.members
        : TABLES.profiles.filter((m) => m.nickname).map((m) => ({ ...m, is_guest: !!m.is_guest, created_at: m.created_at ?? '2026-01-01T00:00:00Z' }));
      const all = source.filter((m) => m.nickname.toLowerCase().includes(q) && (!args.p_role || m.role === args.p_role))
        .sort((a, b) => String(b.created_at).localeCompare(String(a.created_at)));
      const size = Math.min(args.p_size ?? 20, 50);
      const page = args.p_page ?? 1;
      return { data: { total: all.length, page, size, members: all.slice((page - 1) * size, page * size) }, error: null };
    }
    if (name === 'admin_new_members') {
      // 046: fakeState.newMembers = 신규 가입자 줄들 (DB처럼 최근 가입 순으로 돌려준다)
      const all = [...(fakeState.newMembers ?? [])].sort((a, b) => String(b.created_at).localeCompare(String(a.created_at)));
      const size = Math.min(args.p_size ?? 20, 50);
      const page = args.p_page ?? 1;
      return { data: { total: all.length, hours: args.p_hours ?? 24, page, size, members: all.slice((page - 1) * size, page * size) }, error: null };
    }
    if (name === 'admin_member_detail') {
      // 테스트가 넣은 값이 없으면 프로필 표에서 간단히 만든다 (감독관 지정 뒤 다시 읽으면 바뀐 등급이 보인다)
      const p = TABLES.profiles.find((x) => x.id === args.p_user);
      if (!fakeState.memberDetail[args.p_user] && p) {
        return { data: { info: { providers: ['google'], titles: [], posts: 0, comments: 0, matchups: 0, builds: 0, xp: 0, created_at: '2026-11-01T00:00:00Z', is_guest: false, ...p }, posts: [], comments: [], edited_builds: [], moderation: [] }, error: null };
      }
      const d = fakeState.memberDetail[args.p_user];
      if (!d) return { data: null, error: { message: '회원을 찾지 못했습니다.', code: 'P0002' } };
      return { data: d, error: null };
    }
    if (name === 'admin_deleted_writings') {
      return { data: fakeState.deletedWritings[args.p_user] ?? { keep_days: 365, posts: [], comments: [], doc_comments: [] }, error: null };
    }
    return { data: fakeState.memberInfo[args.p_user], error: null };
  }
  if (name === 'media_upload_problem') return { data: fakeState.mediaProblem, error: null }; // 화면이 알아서 묻는 것
  if (name === 'media_usage') {
    if (!isAdminNow()) return { data: null, error: { message: '운영자만 할 수 있습니다.', code: '42501' } };
    return { data: fakeState.mediaUsage, error: null };
  }
  if (name === 'touch_last_seen') {
    fakeState.touched += 1; // 화면이 알아서 부르는 것이라 rpcCalls에는 넣지 않는다
    return { data: null, error: null };
  }
  if (name === 'admin_build_revisions') {
    // 043 운영자 빌드 수정 기록: fakeState.buildRevisions = { 빌드id: { build, revisions } } (화면이 알아서 부르는 것이라 rpcCalls에 넣지 않는다)
    if (!isAdminNow()) return { data: null, error: { message: '운영자만 할 수 있습니다.', code: '42501' } };
    const d = fakeState.buildRevisions[args.p_build];
    if (!d) return { data: null, error: { message: '빌드를 찾지 못했습니다.', code: 'P0002' } };
    const lim = args.p_limit ?? 20;
    const rest = [...d.revisions].sort((a, b) => b.id - a.id).filter((r) => args.p_before == null || r.id < args.p_before);
    return { data: structuredClone({ build: d.build, revisions: rest.slice(0, lim), has_more: rest.length > lim, keep_days: 365 }), error: null };
  }
  // 043: 목록은 화면이 알아서 부르는 것이라 rpcCalls에 넣지 않는다 (보내기·처리만 남긴다)
  if (['report_wiki', 'staff_wiki_reports', 'handle_wiki_report'].includes(name)) return wikiReportRpc(name, args);
  if (INFLUENCER_RPCS.includes(name)) return influencerRpc(name, args);
  if (LINK_RPCS.includes(name)) return linkRpc(name, args);
  if (FOLLOW_RPCS.includes(name)) return followRpc(name, args);
  fakeState.rpcCalls.push({ name, args });
  if (fakeState.rpcError) return { data: null, error: { message: fakeState.rpcError, code: fakeState.rpcErrorCode ?? '42501' } };
  if (name === 'mark_all_notifications_read') {
    // DB 함수처럼 내 것 중 p_upto 번호까지 한 번에, 처리한 시각을 돌려준다 (운영자 모드를 끈 동안 운영진 알림은 그대로, 034)
    const me = fakeState.session?.user.id;
    const t = new Date().toISOString();
    TABLES.notifications
      .filter((n) => n.user_id === me && !n.read_at && n.id <= args.p_upto && !(operatorModeOffNow() && STAFF_NOTICE_KINDS.includes(n.kind)))
      .forEach((n) => { n.read_at = t; });
    return { data: t, error: null };
  }
  if (name === 'mark_notifications_read') {
    // DB 함수처럼 내 것만 읽음 처리
    const me = fakeState.session?.user.id;
    const mine = TABLES.notifications.filter((n) => args.p_ids.includes(n.id) && n.user_id === me && !n.read_at);
    mine.forEach((n) => { n.read_at = new Date().toISOString(); });
    return { data: mine.length, error: null };
  }
  if (name === 'revert_build') {
    // 043 되돌리기: 운영자만, 본 버전이 다르면 TL412, 지금과 같으면 거부. 되돌린 기록을 맨 앞에 더하고 버전 +1
    if (!isAdminNow()) return { data: null, error: { message: '운영자만 할 수 있습니다.', code: '42501' } };
    const d = fakeState.buildRevisions[args.p_build];
    if (args.p_version !== d.build.version) return { data: null, error: { message: '다른 분이 먼저 수정했습니다. 최신 내용을 확인해 주세요.', code: 'TL412' } };
    const rv = d.revisions.find((r) => r.id === args.p_revision);
    if (JSON.stringify(rv.after) === JSON.stringify(d.build.current)) return { data: null, error: { message: '지금 내용과 같습니다.', code: '23514' } };
    const me = meNow();
    const version = d.build.version + 1;
    d.revisions.push({
      id: Math.max(...d.revisions.map((r) => r.id)) + 1, kind: 'revert', version, revert_of: rv.id, created_at: new Date().toISOString(),
      editor: { id: me.id, nickname: me.nickname, role: me.role, is_guest: false, level: me.level, main_title: me.main_title }, before: d.build.current, after: rv.after,
    });
    Object.assign(d.build, { version, current: rv.after });
    return { data: { version, removed_contributors: fakeState.revertRemoved ?? 0 }, error: null };
  }
  if (name === 'set_operator_mode') {
    // 034: 운영자 본인만 (모드를 꺼도 role은 그대로라 다시 켤 수 있다)
    const me = meNow();
    if (me?.role !== 'admin') return { data: null, error: { message: '운영자 계정만 운영자 모드를 바꿀 수 있습니다.', code: '42501' } };
    me.operator_mode = args.p_on;
    return { data: args.p_on, error: null };
  }
  if (name === 'set_moderator') {
    if (!isAdminNow()) return { data: null, error: { message: '운영자만 할 수 있습니다.', code: '42501' } };
    const u = TABLES.profiles.find((x) => x.id === args.p_user);
    u.role = args.p_on ? 'moderator' : 'user';
    TABLES.moderation_log.unshift({
      id: TABLES.moderation_log.length + 1, actor_nickname: '영자', actor_role: 'admin', action: args.p_on ? 'grant_moderator' : 'revoke_moderator',
      target_kind: 'user', target_id: u.id, target_nickname: u.nickname, note: args.p_note, created_at: new Date().toISOString(),
    });
    return { data: null, error: null };
  }
  if (name === 'set_item_prices') {
    if (!args.p_kinds) return { data: null, error: { message: '아이템 종류가 없습니다.', code: '23514' } };
    TABLES.item_prices = Object.entries(args.p_prices).map(([id, gold]) => ({ id, gold, kind: args.p_kinds[id], patch: args.p_patch }));
    return { data: TABLES.item_prices.length, error: null };
  }
  if (name === 'add_offmeta') {
    TABLES.offmeta_champions.push({ champion_id: args.p_champion, created_at: new Date().toISOString() });
    return { data: null, error: null };
  }
  if (name === 'remove_offmeta') {
    TABLES.offmeta_champions = TABLES.offmeta_champions.filter((o) => o.champion_id !== args.p_champion);
    return { data: null, error: null };
  }
  if (name === 'create_inquiry') {
    // DB 검사(하루 3건·글자 수)는 inquiry_test.sql에서 — 여기서는 화면 흐름만. 오류는 fakeState.rpcError
    const id = 1000 + TABLES.inquiries.length;
    TABLES.inquiries.push({ id, user_id: fakeState.session.user.id, category: args.p_category, body: args.p_body.trim(), created_at: new Date().toISOString() });
    return { data: id, error: null };
  }
  if (name === 'delete_my_inquiry') {
    TABLES.inquiries = TABLES.inquiries.filter((r) => !(r.id === args.p_id && r.user_id === fakeState.session?.user.id));
    return { data: null, error: null };
  }
  if (name === 'answer_inquiry' || name === 'set_inquiry_category') {
    const row = TABLES.inquiries.find((r) => r.id === args.p_id);
    if (!isStaffNow()) return { data: null, error: { message: '운영자만 할 수 있습니다.', code: '42501' } };
    if (name === 'set_inquiry_category' && !isAdminNow()) return { data: null, error: { message: '운영자만 할 수 있습니다.', code: '42501' } };
    if (name === 'answer_inquiry') {
      if (row.answer) return { data: null, error: { message: '이미 다른 분이 처리했습니다.', code: 'TL409' } };
      if (row.category === 'account' && !isAdminNow()) return { data: null, error: { message: '"계정·탈퇴" 문의는 운영자만 답변할 수 있습니다.', code: '42501' } };
      Object.assign(row, { answer: args.p_answer, answered_at: new Date().toISOString() });
    } else {
      row.category = args.p_category;
    }
    return { data: null, error: null };
  }
  const board = boardRpc(name, args);
  if (board) return board;
  const wiki = wikiRpc(name, args);
  if (wiki) return wiki;
  if (name === 'vote_build') {
    // DB 함수처럼: 한 사람 한 표, null = 취소, 추천 수 다시 세기
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

// ---------------- 038 상대법 = 빌드 묶음 (위키) ----------------
// DB 함수처럼: 바로 공개, 남의 빌드 수정은 정식 회원만, 버전이 다르면 TL412. fakeState.contributors = { 빌드id: [기여자] }
const BUILD_KEYS = ['runes', 'summoner_spells', 'starting_items', 'core_items', 'max_skill', 'patch', 'name', 'summary', 'level_notes', 'lane_cautions'];
const pickBuild = (p) => Object.fromEntries(BUILD_KEYS.map((k) => [k, p[k] ?? null]));
function newWikiBuild(counterId, payload) {
  const mine = meNow();
  const seq = Math.max(0, ...TABLES.builds.filter((b) => b.counter_id === counterId).map((b) => b.seq ?? 0)) + 1;
  const id = 900 + TABLES.builds.length;
  const k = TABLES.counters.find((c) => c.id === counterId);
  TABLES.builds.push(build(101, mine && { nickname: mine.nickname, role: mine.role, level: mine.level, main_title: mine.main_title, is_guest: !!mine.is_guest }, {
    ...pickBuild(payload), id, counter_id: counterId, author_id: mine?.id ?? null, seq, status: 'approved',
    created_at: new Date().toISOString(), updated_at: new Date().toISOString(),
    counter: k ? { id: k.id, target_champion: k.target_champion, counter_champion: k.counter_champion, status: k.status } : null,
  }));
  return id;
}
function wikiRpc(name, args) {
  if (name === 'create_matchup') {
    if (args.p_target === args.p_mine) return fail('같은 챔피언끼리는 상대법을 만들 수 없습니다.');
    const old = TABLES.counters.find((c) => c.target_champion === args.p_target && c.counter_champion === args.p_mine);
    if (old?.status === 'approved') return { data: null, error: { message: '이미 있는 상대법입니다. 그 상대법에 새 빌드를 더해 주세요.', code: '23505' } };
    const id = 500 + TABLES.counters.length;
    const b = args.p_build;
    TABLES.counters.push({
      id, target_champion: args.p_target, counter_champion: args.p_mine, sort_order: 99, status: 'approved',
      matchup_docs: { counter_id: id, summary: b.summary, level_notes: b.level_notes, lane_cautions: b.lane_cautions, updated_at: new Date().toISOString(), revision_id: null },
    });
    return ok({ counter_id: id, build_id: newWikiBuild(id, b) });
  }
  if (name === 'create_build') {
    if (!TABLES.counters.some((c) => c.id === args.p_counter && c.status === 'approved')) return fail('빌드를 등록할 상대법을 찾지 못했습니다.');
    return ok(newWikiBuild(args.p_counter, args.p_build));
  }
  if (name === 'edit_build') {
    const b = TABLES.builds.find((x) => x.id === args.p_id);
    if (!b || b.status !== 'approved') return fail('공개된 빌드만 수정할 수 있습니다.');
    if (meNow()?.is_guest && b.author_id !== me()) {
      return { data: null, error: { code: '42501', message: '다른 분의 빌드는 구글·카카오로 로그인한 회원만 수정할 수 있습니다. 비회원은 새 빌드를 등록하거나 내 빌드를 수정할 수 있습니다.' } };
    }
    if (args.p_version !== b.version) return { data: null, error: { code: 'TL412', message: '다른 분이 먼저 수정했습니다. 최신 내용을 확인해 주세요.' } };
    Object.assign(b, pickBuild(args.p_build), { version: b.version + 1, updated_at: new Date().toISOString() });
    return ok(b.version);
  }
  if (name === 'build_editor_counts') { // 046: fakeState.editorCounts = { 빌드id: N } (없으면 0)
    return ok(fakeState.editorCounts ?? {});
  }
  if (name === 'build_contributors') {
    const b = TABLES.builds.find((x) => x.id === args.p_build);
    const listed = fakeState.contributors?.[args.p_build];
    if (listed) return ok(listed);
    return ok(b?.author ? [{ user_id: b.author_id, level: 1, main_title: null, is_guest: false, role: 'user', ...b.author, is_origin: true }] : []);
  }
  return null;
}

const me = () => fakeState.session?.user.id;
const person = (id) => {
  const p = TABLES.profiles.find((x) => x.id === id);
  return p ? { nickname: p.nickname, role: p.role, level: p.level, main_title: p.main_title } : null;
};
const fail = (message) => ({ data: null, error: { message } });
const ok = (data = null) => ({ data, error: null });

/** 테스트에서 쓰는 글 한 줄 (기본: 기존유저가 쓴 보이는 글) */
export function fakePost(id, extra = {}) {
  return {
    id, author_id: 'u-old', author: { nickname: '기존유저', level: 1, main_title: null }, title: `글 ${id}`, body: `본문 ${id}`,
    status: 'visible', hidden_note: null, hidden_at: null, edited_at: null, deleted_at: null, comment_count: 0, up_count: 0,
    created_at: `2026-11-01T0${id % 10}:00:00Z`, media: [], ...extra,
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
    status: 'visible', hidden_note: null, hidden_at: null, edited_at: null, created_at: `2026-11-01T1${id % 10}:00:00Z`, media: [],
    ...extra,
  };
}

/** 붙인 사진 경로 → 붙은 사진 줄 (올린 파일의 형식·크기를 쓴다) */
/**
 * 043 오류 신고: DB 함수와 같은 규칙만 흉내 낸다 — 정식 회원만, 같은 대상 처리 전 중복 막기, 운영진만 목록·처리,
 * 감독관은 자기 신고 처리 불가, 처리하면 신고자에게 error_report_handled 알림. 신고자는 운영자에게만 보인다.
 * 테스트가 TABLES.wiki_reports에 줄을 직접 넣을 때는 counter_id·build_id·reason·status·reporter_id·created_at만 있으면 된다.
 */
function wikiReportRpc(name, args) {
  const now = new Date().toISOString();
  if (name !== 'staff_wiki_reports') fakeState.rpcCalls.push({ name, args });
  if (name !== 'staff_wiki_reports' && fakeState.rpcError) return { data: null, error: { message: fakeState.rpcError, code: fakeState.rpcErrorCode ?? '42501' } };
  if (name === 'report_wiki') {
    const p = meNow();
    if (!p) return fail('로그인이 필요합니다.');
    if (p.is_guest) return fail('오류 신고는 구글·카카오로 로그인한 회원만 할 수 있습니다.');
    const dup = TABLES.wiki_reports.some((r) => r.status === 'open' && r.reporter_id === p.id
      && r.counter_id === args.p_counter && (r.build_id ?? null) === (args.p_build ?? null));
    if (dup) return fail('이미 신고한 내용입니다. 운영진이 확인할 때까지 기다려 주세요.');
    const id = 900 + TABLES.wiki_reports.length;
    TABLES.wiki_reports.push({
      id, counter_id: args.p_counter, build_id: args.p_build ?? null, reporter_id: p.id, reason: args.p_reason, memo: args.p_memo ?? null,
      status: 'open', created_at: now, handled_by: null, handled_at: null, handled_note: null,
    });
    return ok(id);
  }
  if (!isStaffNow()) return fail('운영진만 할 수 있습니다.');
  const op = isAdminNow();
  const sameTarget = (a, b) => a.counter_id === b.counter_id && (a.build_id ?? null) === (b.build_id ?? null);
  if (name === 'staff_wiki_reports') {
    const open = args.p_status === 'open';
    const rows = TABLES.wiki_reports.filter((r) => (r.status === 'open') === open)
      .sort((a, b) => (open ? String(a.created_at).localeCompare(String(b.created_at)) : String(b.handled_at).localeCompare(String(a.handled_at))));
    const size = Math.min(args.p_size ?? 20, 50);
    const page = args.p_page ?? 1;
    const reports = rows.slice((page - 1) * size, page * size).map((r) => {
      const k = TABLES.counters.find((c) => c.id === r.counter_id) ?? {};
      const b = r.build_id ? TABLES.builds.find((x) => x.id === r.build_id) ?? {} : {};
      const prof = (id) => TABLES.profiles.find((x) => x.id === id);
      const h = prof(r.handled_by);
      const rp = prof(r.reporter_id);
      return {
        ...r, target_champion: k.target_champion, counter_champion: k.counter_champion, counter_status: k.status,
        build_seq: b.seq ?? null, build_name: b.name ?? null, build_status: b.status ?? null,
        handler: r.status === 'open' ? null : h ? { id: h.id, nickname: h.nickname, role: h.role, withdrawn: false } : { withdrawn: true },
        reporter: !op ? null : rp ? { id: rp.id, nickname: rp.nickname, role: rp.role, is_guest: !!rp.is_guest, withdrawn: false } : { withdrawn: true },
        mine: r.reporter_id === me(),
        same_open: TABLES.wiki_reports.filter((o) => o.status === 'open' && sameTarget(o, r)).length,
      };
    });
    return ok({ total: rows.length, page, size, reports });
  }
  // handle_wiki_report
  const r = TABLES.wiki_reports.find((x) => x.id === args.p_id);
  if (!r || r.status !== 'open') return fail('이미 처리된 신고입니다.');
  if (!op && r.reporter_id === me()) return fail('내가 낸 신고는 다른 운영진이 처리해야 합니다.');
  if (!args.p_note?.trim()) return fail('처리 메모를 적어 주세요.');
  const targets = args.p_same_target ? TABLES.wiki_reports.filter((x) => x.status === 'open' && sameTarget(x, r)) : [r];
  targets.forEach((x) => {
    Object.assign(x, { status: args.p_status, handled_by: me(), handled_at: now, handled_note: args.p_note });
    if (x.reporter_id) {
      TABLES.notifications.push({
        id: 5000 + TABLES.notifications.length, user_id: x.reporter_id, kind: 'error_report_handled', created_at: now, read_at: null,
        message: args.p_status === 'resolved' ? '보내 주신 오류 신고를 처리했습니다. 고맙습니다.' : '보내 주신 오류 신고를 검토했지만 고칠 내용이 없어 기각했습니다.',
        counter_id: x.counter_id, build_id: x.build_id, proposal_id: null, post_id: null,
      });
    }
  });
  return ok(targets.length);
}

function mediaRows(paths = []) {
  return (paths ?? []).map((path, position) => {
    const up = fakeState.uploads.find((u) => u.path === path);
    return { path, mime: up?.mime ?? 'image/webp', size: up?.size ?? 1000, position };
  });
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
          up_count: p.up_count, created_at: p.created_at, edited_at: p.edited_at, author: p.author, media_count: p.media?.length ?? 0,
        })),
      });
    }
    case 'create_post': {
      if (fakeState.boardError) return fail(fakeState.boardError);
      const id = 700 + TABLES.posts.length;
      TABLES.posts.push(fakePost(id, {
        author_id: me(), author: person(me()), title: args.p_title.trim(), body: args.p_body.trim(), created_at: new Date().toISOString(),
        media: mediaRows(args.p_media),
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
    case 'staff_delete_doc_comment':
      if (!isStaffNow()) return fail('운영진만 할 수 있습니다.');
    // eslint-disable-next-line no-fallthrough -- 지우는 방법은 같다
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
      if (args.p_media != null) post(args.p_id).media = mediaRows(args.p_media);
      return ok();
    case 'delete_my_post':
    case 'staff_delete_post': {
      // 040: 지운 글은 달린 댓글과 함께 아무에게도 안 보인다 (DB엔 1년 보관 — 여기선 목록에서 뺀다)
      if (name === 'staff_delete_post' && !isStaffNow()) return fail('운영진만 할 수 있습니다.');
      const p = post(args.p_id);
      TABLES.posts = TABLES.posts.filter((x) => x !== p);
      TABLES.post_comments = TABLES.post_comments.filter((c) => c.post_id !== p.id);
      return ok(name === 'delete_my_post' ? 'hard' : null);
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
        media: mediaRows(args.p_media),
      }));
      recount(args.p_post);
      return ok(id);
    }
    case 'edit_comment':
      if (fakeState.boardError) return fail(fakeState.boardError);
      Object.assign(comment(args.p_id), { body: args.p_body.trim(), edited_at: new Date().toISOString() });
      if (args.p_media != null) comment(args.p_id).media = mediaRows(args.p_media);
      return ok();
    case 'staff_delete_comment':
      if (!isStaffNow()) return fail('운영진만 할 수 있습니다.');
    // eslint-disable-next-line no-fallthrough -- 지우는 방법은 같다
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
        return fail(name === 'report_post' ? '이미 신고한 글입니다.' : '이미 신고한 댓글입니다.');
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

// Storage 흉내 (023 board-media): 올린 파일은 fakeState.uploads, 실패는 fakeState.uploadError. 서명 주소는 가짜 주소
const storage = {
  from: (bucket) => ({
    upload: async (path, blob, opts) => {
      if (fakeState.uploadError) return { data: null, error: { message: fakeState.uploadError } };
      fakeState.uploads.push({ bucket, path, mime: opts?.contentType, size: blob?.size ?? 0 });
      return { data: { path }, error: null };
    },
    createSignedUrls: async (paths) => ({
      data: paths.map((path) => ({ path, signedUrl: `https://fake.storage/${bucket}/${path}?token=t`, error: null })),
      error: null,
    }),
  }),
};

export function db() {
  return { from: query, auth, rpc, functions, storage };
}

// ---------------- 046 장인 인증 ----------------
// DB 함수처럼 흐름만 흉내 낸다 (규칙 자체는 supabase/tests/influencer_test.sql). 목록·내 상태는 화면이 알아서 부르므로 rpcCalls에 넣지 않는다.
// fakeState.influencerNextAt = 다시 신청할 수 있는 때 (없으면 null), 오류는 fakeState.rpcError
const INFLUENCER_RPCS = ['my_influencer_status', 'apply_influencer', 'cancel_influencer_application', 'admin_influencer_applications',
  'approve_influencer', 'reject_influencer', 'extend_influencer_application', 'revoke_influencer', 'admin_set_nickname',
  'grant_influencer']; // 049
const KIND_LABEL = { creator: '크리에이터', pro: '프로게이머', grandmaster: '그랜드마스터 이상' };
function influencerRpc(name, args) {
  const listing = name === 'my_influencer_status' || name === 'admin_influencer_applications';
  if (!listing) fakeState.rpcCalls.push({ name, args });
  if (fakeState.rpcError) return { data: null, error: { message: fakeState.rpcError, code: fakeState.rpcErrorCode ?? '42501' } };
  const meRow = meNow();
  const apps = TABLES.influencer_applications;
  const prof = (id) => TABLES.profiles.find((p) => p.id === id);
  const notify = (userId, kind, message) => TABLES.notifications.push({
    id: 7000 + TABLES.notifications.length, user_id: userId, kind, message, created_at: new Date().toISOString(), read_at: null,
  });
  if (name === 'my_influencer_status') {
    if (!meRow) return { data: null, error: { message: '로그인해 주세요.', code: '42501' } };
    const last = [...apps].reverse().find((a) => a.user_id === meRow.id) ?? null;
    return ok({
      influencer: meRow.influencer ?? null, influencer_at: meRow.influencer_at ?? null, nickname_state: meRow.nickname_state ?? null,
      nickname_reset_at: meRow.nickname_reset_at ?? null, is_guest: !!meRow.is_guest, next_apply_at: fakeState.influencerNextAt,
      application: last && structuredClone(last),
    });
  }
  if (name === 'apply_influencer') {
    const id = apps.length + 1;
    const now = Date.now();
    apps.push({
      id, user_id: meRow.id, kind: args.p_kind, nickname: args.p_nickname, old_nickname: meRow.nickname, channel_url: args.p_channel_url,
      official_email: args.p_email, riot_id: args.p_riot_id, opgg_url: args.p_opgg_url, status: 'pending',
      created_at: new Date(now).toISOString(), expires_at: new Date(now + 14 * 86400000).toISOString(), extended_count: 0,
      ended_at: null, review_note: null, retry_now: false, nickname_reverted: null, revoked_at: null, revoke_note: null,
    });
    Object.assign(meRow, { nickname: args.p_nickname, nickname_state: 'pending' });
    notify(meRow.id, 'influencer_received', args.p_kind === 'grandmaster'
      ? '신청이 접수됐습니다. 14일 안에 운영자 계정 {운영자 닉네임}으로 친구 요청을 보내 주세요. 요청이 도착하면 이 닉네임의 주인이 맞는지 확인합니다. 수락은 하지 않습니다.'
      : '신청이 접수됐습니다. 적어 주신 공식 이메일로 확인 메일을 보냅니다. 14일 안에 "본인입니다"라고 회신해 주세요.');
    return ok(id);
  }
  const a = apps.find((x) => x.id === args.p_id);
  const end = (status, extra = {}) => Object.assign(a, { status, ended_at: new Date().toISOString(), official_email: null, riot_id: null, ...extra });
  if (name === 'cancel_influencer_application') {
    end('cancelled');
    Object.assign(prof(a.user_id), { nickname_state: null });
    return ok(null);
  }
  if (!isAdminNow()) return { data: null, error: { message: '운영자만 할 수 있습니다.', code: '42501' } };
  if (name === 'admin_influencer_applications') {
    const want = (x) => (x.status === 'pending') === (args.p_status === 'pending');
    const rows = apps.filter(want).map((x) => {
      const u = prof(x.user_id);
      const o = u && TABLES.profiles.find((p) => p.id !== u.id && p.nickname && p.nickname.toLowerCase() === u.nickname?.toLowerCase());
      return {
        ...structuredClone(x), kind_label: KIND_LABEL[x.kind], reviewer: x.reviewer ?? null, recent_rejections: 0,
        user: u ? { id: u.id, nickname: u.nickname, role: u.role, level: u.level, main_title: u.main_title ?? null, is_guest: !!u.is_guest,
          influencer: u.influencer ?? null, nickname_state: u.nickname_state ?? null } : null,
        overlap: x.status === 'pending' && o ? { id: o.id, nickname: o.nickname, role: o.role } : null,
      };
    });
    const size = args.p_size ?? 20;
    const page = args.p_page ?? 1;
    return ok({ total: rows.length, page, size, items: rows.slice((page - 1) * size, page * size) });
  }
  if (name === 'approve_influencer') {
    end('approved', { review_note: args.p_note, reviewer: meRow.nickname });
    Object.assign(prof(a.user_id), { influencer: a.kind, influencer_at: new Date().toISOString(), nickname_state: null });
    return ok(null);
  }
  if (name === 'reject_influencer') {
    const u = prof(a.user_id);
    const back = args.p_revert_nickname ? a.old_nickname : null;
    end('rejected', { review_note: args.p_note, retry_now: !!args.p_retry_now, nickname_reverted: back, reviewer: meRow.nickname });
    Object.assign(u, { nickname_state: null }, back ? { nickname: back } : {});
    return ok(null);
  }
  if (name === 'extend_influencer_application') {
    a.expires_at = new Date(Date.parse(a.expires_at) + 7 * 86400000).toISOString();
    a.extended_count += 1;
    return ok(a.expires_at);
  }
  if (name === 'grant_influencer') {
    // 049: 지정 줄(direct)을 승인 상태로 만들고 장인 표시. 거부 규칙은 DB 검사(direct_grant_test)와 같은 문구로 몇 가지만
    const u = prof(args.p_user);
    if (!u) return { data: null, error: { message: '회원을 찾지 못했습니다.', code: 'P0002' } };
    if (u.is_guest) return { data: null, error: { message: '장인은 구글·카카오로 로그인한 정식 회원만 지정할 수 있습니다. 비회원은 지정할 수 없습니다.', code: '23514' } };
    if (u.influencer) return { data: null, error: { message: '이미 인증된 장인입니다.', code: '23514' } };
    if (u.nickname_state === 'pending') {
      return { data: null, error: { message: '장인 인증 신청을 심사 중인 회원입니다. 운영자 페이지 [장인 인증] 심사 화면에서 그 신청을 승인해 주세요.', code: '23514' } };
    }
    const now = new Date().toISOString();
    const id = apps.length + 1;
    apps.push({
      id, user_id: u.id, kind: args.p_kind, nickname: u.nickname, old_nickname: null, channel_url: null, official_email: null, riot_id: null,
      opgg_url: null, status: 'approved', created_at: now, expires_at: now, extended_count: 0, ended_at: now, review_note: args.p_note,
      retry_now: false, nickname_reverted: null, revoked_at: null, revoke_note: null, direct: true, reviewer: meRow.nickname,
    });
    Object.assign(u, { influencer: args.p_kind, influencer_at: now });
    notify(u.id, 'influencer_approved', '장인 인증이 완료됐습니다. 이제 닉네임 앞에 "장인" 표시가 붙습니다.');
    return ok(id);
  }
  if (name === 'revoke_influencer') {
    Object.assign(prof(args.p_user), { influencer: null, influencer_at: null });
    apps.filter((x) => x.user_id === args.p_user && x.status === 'approved')
      .forEach((x) => Object.assign(x, { status: 'revoked', revoked_at: new Date().toISOString(), revoke_note: args.p_note }));
    return ok(null);
  }
  if (name === 'admin_set_nickname') {
    Object.assign(prof(args.p_user), { nickname: args.p_nickname });
    return ok(null);
  }
  return null;
}

// ---------------- 047 장인 외부 링크 + 공개 프로필 ----------------
// 흐름만 흉내 낸다 (규칙 자체는 supabase/tests/influencer_links_test.sql). 읽기(내 링크·공개 프로필·빌드 링크)는 rpcCalls에 넣지 않는다.
function LINK_DOMAINS() {
  return [
    ['afreecatv.com', '아프리카TV (숲 예전 주소)'], ['chzzk.naver.com', '치지직'], ['instagram.com', '인스타그램'], ['sooplive.co.kr', '숲'],
    ['twitch.tv', '트위치'], ['twitter.com', 'X (트위터 예전 주소)'], ['x.com', 'X'], ['youtu.be', '유튜브 (짧은 주소)'], ['youtube.com', '유튜브'],
  ].map(([domain, label]) => ({ domain, label }));
}
const LINK_RPCS = ['my_links', 'set_profile_links', 'set_build_link', 'public_profile', 'build_links',
  'report_link', 'remove_link', 'admin_link_reports', 'dismiss_link_reports', 'admin_add_link_domain', 'admin_remove_link_domain']; // 뒤 6개: 3b
function linkRpc(name, args) {
  const reading = ['my_links', 'public_profile', 'build_links', 'admin_link_reports'].includes(name);
  if (!reading) fakeState.rpcCalls.push({ name, args });
  if (fakeState.rpcError && !reading) return { data: null, error: { message: fakeState.rpcError, code: fakeState.rpcErrorCode ?? '42501' } };
  const links = TABLES.ext_links;
  const domains = TABLES.link_domains;
  const allowed = (host) => domains.some((d) => host === d.domain || host.endsWith(`.${d.domain}`));
  const prof = (id) => TABLES.profiles.find((p) => p.id === id);
  const buildOf = (id) => TABLES.builds.find((b) => b.id === id);
  const visible = (l) => !!prof(l.owner_id)?.influencer && allowed(l.host)
    && (l.build_id == null || (buildOf(l.build_id)?.status === 'approved' && buildOf(l.build_id)?.author_id === l.owner_id));
  const shape = (l) => ({ id: l.id, url: l.url, host: l.host, build_id: l.build_id, sort: l.sort });
  const parse = (u) => {
    const problem = linkProblem(u, domains);
    if (problem) throw problem;
    const host = hostOf(u);
    return { url: `https://${host}${u.trim().slice(8 + host.length)}`, host };
  };
  const nextId = () => 900 + links.length + Math.floor(Math.random() * 1e6);
  const meRow = meNow();
  try {
    if (name === 'public_profile') {
      const p = prof(args.p_user);
      if (!p || !p.influencer || !p.nickname) return ok(null);
      const builds = TABLES.builds.filter((b) => b.author_id === p.id && b.status === 'approved')
        .sort((a, b) => String(b.created_at).localeCompare(String(a.created_at)));
      return ok(structuredClone({
        id: p.id, nickname: p.nickname, influencer: p.influencer,
        links: links.filter((l) => l.owner_id === p.id && l.build_id == null && visible(l)).sort((a, b) => a.sort - b.sort).map(shape),
        build_count: builds.length,
        builds: builds.slice(0, 10).map((b) => {
          const l = links.find((x) => x.build_id === b.id && visible(x));
          return { id: b.id, counter_id: b.counter_id, seq: b.seq, name: b.name, patch: b.patch, target_champion: b.counter.target_champion,
            counter_champion: b.counter.counter_champion, created_at: b.created_at, link: l ? shape(l) : null };
        }),
      }));
    }
    if (name === 'build_links') {
      return ok(Object.fromEntries(links.filter((l) => l.build_id != null && buildOf(l.build_id)?.counter_id === args.p_counter && visible(l))
        .map((l) => [String(l.build_id), shape(l)])));
    }
    if (!meRow) return { data: null, error: { message: '로그인이 필요해요.', code: '42501' } };
    if (name === 'my_links') {
      return ok(structuredClone({
        influencer: meRow.influencer ?? null, max: 5,
        profile: links.filter((l) => l.owner_id === meRow.id && l.build_id == null).sort((a, b) => a.sort - b.sort).map((l) => ({ ...shape(l), visible: visible(l) })),
        builds: links.filter((l) => l.owner_id === meRow.id && l.build_id != null).map((l) => {
          const b = buildOf(l.build_id);
          return { ...shape(l), visible: visible(l), counter_id: b.counter_id, seq: b.seq, name: b.name,
            target_champion: b.counter.target_champion, counter_champion: b.counter.counter_champion };
        }),
        domains,
      }));
    }
    // ---- 3b: 신고(정식 회원) / 삭제(운영자 전부, 감독관은 일반 장인 링크만 — 048) / 운영자 전용 ----
    const denied = (message) => ({ data: null, error: { message, code: '42501' } });
    const linkOf = (id) => TABLES.ext_links.find((l) => l.id === id);
    if (name === 'report_link') {
      if (meRow.is_guest) return denied('비회원은 신고할 수 없습니다. 구글/카카오를 연결하면 할 수 있습니다.');
      const l = linkOf(args.p_link);
      if (!l || !visible(l)) throw '신고할 수 없는 링크입니다.';
      if (l.owner_id === meRow.id) throw '내 링크는 신고할 수 없습니다.';
      if (args.p_reason === 'other' && !args.p_detail) throw '기타 이유를 적어 주세요.';
      if (TABLES.link_reports.some((r) => r.link_id === l.id && r.reporter_id === meRow.id)) throw '이미 신고한 링크입니다.';
      TABLES.link_reports.push({ id: 7000 + TABLES.link_reports.length, link_id: l.id, reporter_id: meRow.id, reason: args.p_reason,
        detail: args.p_detail, status: 'open', created_at: new Date().toISOString() });
      return ok(null);
    }
    if (name === 'remove_link') {
      if (!isStaffNow()) return denied(operatorModeOffNow() ? '운영자 모드를 켜야 할 수 있습니다.' : '운영자만 할 수 있습니다.');
      const l = linkOf(args.p_link);
      if (!l) throw '링크를 찾지 못했습니다. 이미 지워졌을 수 있습니다.';
      if (!isAdminNow() && (prof(l.owner_id)?.role !== 'user' || l.owner_id === meRow.id)) return denied('운영진이 올린 링크는 운영자만 삭제할 수 있습니다.');
      if (!String(args.p_note ?? '').trim()) throw '삭제 사유를 적어 주세요. (500자 이하)';
      TABLES.ext_links = TABLES.ext_links.filter((x) => x.id !== l.id);
      TABLES.link_reports = TABLES.link_reports.filter((r) => r.link_id !== l.id);
      TABLES.notifications.push({ id: 8000 + TABLES.notifications.length, user_id: l.owner_id, kind: 'link_removed', read_at: null,
        message: `${l.build_id == null ? '프로필에' : '빌드에'} 올린 링크가 운영 원칙에 따라 삭제됐습니다. 사유: ${args.p_note}`, created_at: new Date().toISOString() });
      return ok(null);
    }
    if (['admin_link_reports', 'dismiss_link_reports', 'admin_add_link_domain', 'admin_remove_link_domain'].includes(name) && !isAdminNow()) {
      return denied('운영자만 할 수 있습니다.');
    }
    if (name === 'admin_link_reports') {
      const open = TABLES.link_reports.filter((r) => r.status === 'open');
      const ids = [...new Set(open.map((r) => r.link_id))];
      const person = (id) => { const p = prof(id); return p ? { id: p.id, nickname: p.nickname, influencer: p.influencer ?? null, nickname_state: null, role: p.role } : null; };
      return ok(structuredClone({
        total: ids.length, page: 1, size: args.p_size ?? 20,
        links: ids.slice(0, args.p_size ?? 20).map((id) => {
          const l = linkOf(id);
          const b = l.build_id != null ? buildOf(l.build_id) : null;
          return { ...shape(l), visible: visible(l), owner: person(l.owner_id),
            build: b ? { id: b.id, counter_id: b.counter_id, seq: b.seq, name: b.name, status: b.status, target_champion: b.counter.target_champion, counter_champion: b.counter.counter_champion } : null,
            reports: open.filter((r) => r.link_id === id).map((r) => ({ ...r, reporter: person(r.reporter_id) })) };
        }),
      }));
    }
    if (name === 'dismiss_link_reports') {
      const open = TABLES.link_reports.filter((r) => r.link_id === args.p_link && r.status === 'open');
      if (open.length === 0) throw '처리할 신고가 없습니다.';
      open.forEach((r) => { r.status = 'dismissed'; });
      return ok(open.length);
    }
    if (name === 'admin_add_link_domain') {
      const dom = String(args.p_domain).toLowerCase().trim().replace(/^https?:\/\//, '').replace(/\/+$/, '').replace(/^www\./, '');
      if (!String(args.p_label ?? '').trim()) throw '사이트 이름을 적어 주세요. (40자 이하)';
      if (!/^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,24}$/.test(dom)) throw '도메인 모양이 올바르지 않습니다. (예: youtube.com)';
      if (domains.some((d) => d.domain === dom)) throw '이미 허용된 사이트입니다.';
      TABLES.link_domains = [...domains, { domain: dom, label: args.p_label.trim() }].sort((a, b) => a.domain.localeCompare(b.domain));
      return ok(dom);
    }
    if (name === 'admin_remove_link_domain') {
      if (!String(args.p_note ?? '').trim()) throw '빼는 사유를 적어 주세요. (500자 이하)';
      if (!domains.some((d) => d.domain === args.p_domain)) throw '허용 목록에 없는 사이트입니다.';
      const before = links.filter(visible).length;
      TABLES.link_domains = domains.filter((d) => d.domain !== args.p_domain);
      const stillAllowed = (host) => TABLES.link_domains.some((d) => host === d.domain || host.endsWith(`.${d.domain}`));
      return ok(before - links.filter((l) => visible(l) && stillAllowed(l.host)).length);
    }
    if (!meRow.influencer) return { data: null, error: { message: '인증된 장인만 링크를 올릴 수 있습니다.', code: '42501' } };
    if (name === 'set_profile_links') {
      const parsed = args.p_urls.filter((u) => u.trim()).map(parse);
      if (parsed.length > 5) throw '프로필 링크는 5개까지 올릴 수 있습니다.';
      if (new Set(parsed.map((x) => x.url)).size < parsed.length) throw '같은 주소를 두 번 올릴 수 없습니다.';
      const kept = links.filter((l) => !(l.owner_id === meRow.id && l.build_id == null && !parsed.some((x) => x.url === l.url)));
      parsed.forEach((x, i) => {
        const old = kept.find((l) => l.owner_id === meRow.id && l.build_id == null && l.url === x.url);
        if (old) old.sort = i;
        else kept.push({ id: nextId(), owner_id: meRow.id, build_id: null, url: x.url, host: x.host, sort: i });
      });
      TABLES.ext_links = kept;
      return ok(kept.filter((l) => l.owner_id === meRow.id && l.build_id == null).sort((a, b) => a.sort - b.sort).map(shape));
    }
    if (name === 'set_build_link') {
      const b = buildOf(args.p_build);
      if (!b) throw '빌드를 찾지 못했습니다.';
      if (b.author_id !== meRow.id) return { data: null, error: { message: '내가 처음 만든 빌드에만 링크를 달 수 있습니다.', code: '42501' } };
      TABLES.ext_links = links.filter((l) => l.build_id !== b.id);
      if (!args.p_url) return ok(null);
      const x = parse(args.p_url);
      const row = { id: nextId(), owner_id: meRow.id, build_id: b.id, url: x.url, host: x.host, sort: 0 };
      TABLES.ext_links.push(row);
      return ok(shape(row));
    }
  } catch (message) {
    return { data: null, error: { message: String(message), code: '23514' } };
  }
  return null;
}

// ---- 050 장인 팔로우 (SPEC 6-36): DB 함수와 같은 규칙만 흉내 낸다 ----
const FOLLOW_RPCS = ['follow_influencer', 'unfollow_influencer', 'follow_status', 'influencer_builds', 'influencer_followers', 'influencer_follower_count'];
function followRpc(name, args) {
  const writing = ['follow_influencer', 'unfollow_influencer'].includes(name);
  if (writing) fakeState.rpcCalls.push({ name, args });
  if (name === 'follow_status') fakeState.followStatusCalls.push(args.p_users);
  if (fakeState.rpcError && writing) return { data: null, error: { message: fakeState.rpcError, code: fakeState.rpcErrorCode ?? '42501' } };
  const prof = (id) => TABLES.profiles.find((p) => p.id === id);
  const isInf = (id) => !!prof(id)?.influencer;
  const count = (id) => TABLES.influencer_follows.filter((f) => f.influencer_id === id).length;
  const meRow = meNow();
  if (name === 'influencer_builds' || name === 'influencer_follower_count') {
    const p = prof(args.p_user);
    if (!p || !p.influencer || !p.nickname) return ok(null);
    if (name === 'influencer_follower_count') return ok(count(p.id));
    const all = TABLES.builds.filter((b) => b.author_id === p.id && b.status === 'approved')
      .sort((a, b) => String(b.updated_at ?? b.created_at).localeCompare(String(a.updated_at ?? a.created_at)) || b.id - a.id);
    const page = Math.max(1, args.p_page ?? 1);
    return ok(structuredClone({
      influencer: { id: p.id, nickname: p.nickname, influencer: p.influencer }, follower_count: count(p.id), total: all.length, page, size: 20,
      items: all.slice((page - 1) * 20, page * 20).map((b) => ({
        id: b.id, counter_id: b.counter_id, seq: b.seq, name: b.name, patch: b.patch, summary: b.summary,
        target_champion: b.counter.target_champion, counter_champion: b.counter.counter_champion, up_count: b.up_count, down_count: b.down_count,
        created_at: b.created_at, updated_at: b.updated_at ?? b.created_at, editor_count: 0,
        author: { id: p.id, nickname: p.nickname, influencer: p.influencer },
        link: (() => { const l = TABLES.ext_links.find((x) => x.build_id === b.id); return l ? { id: l.id, url: l.url, host: l.host, build_id: l.build_id, sort: l.sort } : null; })(),
      })),
    }));
  }
  if (!meRow) return { data: null, error: { message: 'permission denied for function ' + name, code: '42501' } };
  if (name === 'follow_status') {
    return ok(Object.fromEntries([...new Set(args.p_users ?? [])].map((u) => [u, isInf(u) && TABLES.influencer_follows.some((f) => f.follower_id === meRow.id && f.influencer_id === u)])));
  }
  if (name === 'influencer_followers') {
    if (!isInf(args.p_user)) return { data: null, error: { message: '인증된 장인을 찾지 못했습니다.', code: 'P0002' } };
    const all = TABLES.influencer_follows.filter((f) => f.influencer_id === args.p_user)
      .sort((a, b) => String(b.created_at).localeCompare(String(a.created_at)));
    const page = Math.max(1, args.p_page ?? 1);
    return ok(structuredClone({
      follower_count: all.length, total: all.length, page, size: 20,
      items: all.slice((page - 1) * 20, page * 20).map((f) => {
        const u = prof(f.follower_id);
        return { id: f.follower_id, nickname: u?.nickname ?? null, influencer: u?.influencer ?? null, nickname_state: u?.nickname_state ?? null, followed_at: f.created_at };
      }),
    }));
  }
  if (name === 'follow_influencer') {
    if (!isInf(args.p_user)) return { data: null, error: { message: '인증된 장인만 팔로우할 수 있습니다.', code: 'P0002' } };
    if (args.p_user === meRow.id) return { data: null, error: { message: '나 자신은 팔로우할 수 없습니다.', code: '23514' } };
    if (!TABLES.influencer_follows.some((f) => f.follower_id === meRow.id && f.influencer_id === args.p_user)) {
      TABLES.influencer_follows.push({ follower_id: meRow.id, influencer_id: args.p_user, created_at: new Date().toISOString() });
    }
    return ok({ following: true, follower_count: count(args.p_user) });
  }
  if (name === 'unfollow_influencer') {
    TABLES.influencer_follows = TABLES.influencer_follows.filter((f) => !(f.follower_id === meRow.id && f.influencer_id === args.p_user));
    return ok({ following: false, follower_count: count(args.p_user) });
  }
  return null;
}
