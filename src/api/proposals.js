// 제안·승인 접근 계층. 화면 컴포넌트는 이 모듈만 호출한다.
// 권한은 DB가 막는다: 제안 넣기는 RLS + 검사 트리거, 승인·거절·순서·되돌리기는 운영자 전용 함수(rpc).
import { db } from './supabase';
import { cleanDoc } from '../lib/docContent';
import { proposalBuildBlock, toProposalBuild } from '../lib/buildContent';

const PERSON = 'nickname, level, main_title, is_guest';
const PROPOSAL_COLUMNS =
  'id, type, target_champion, counter_champion, counter_id, content, status, reject_reason, reviewed_at, created_at, base_revision_id, ' +
  'revoke_reason, revoked_at, approve_note, revision_note, revision_requested_at, resubmitted_at, build, approved_content, approved_build, ' +
  'version, edited_at, ' +
  `proposer:profiles!edit_proposals_proposer_id_fkey(${PERSON})`;
const DOC_COLUMNS = 'counter_id, summary, level_notes, lane_cautions, updated_at, revision_id';

/** DB 오류를 사람이 읽을 문장으로. DB 함수·트리거는 한국어 문장으로 오류를 낸다. */
function friendly(error, fallback) {
  const msg = error?.message ?? '';
  if (/row-level security/i.test(msg)) return new Error('제안할 권한이 없습니다. 로그인하고 닉네임을 정했는지 확인해 주세요.');
  if (/permission denied/i.test(msg)) return new Error('권한이 없습니다. (운영자만 할 수 있는 작업입니다)');
  if (/[가-힣]/.test(msg)) return new Error(msg);
  return new Error(`${fallback} (${msg})`);
}

async function run(query, fallback) {
  const { data, error } = await query;
  if (error) throw friendly(error, fallback);
  return data;
}

// ---------------- 제안 넣기 (로그인 + 닉네임 필요) ----------------

/**
 * 새 카운터 제안: target(지는 쪽)을 counter(이기는 쪽)가 이긴다 + 첫 문서 내용 + 빌드 1개(필수).
 * 승인되면 그 빌드가 카운터의 첫 빌드로 공개된다. patch = 지금 Data Dragon 버전
 */
export async function proposeNewCounter(userId, target, counter, content, build, patch) {
  await run(
    db().from('edit_proposals').insert({
      type: 'new_counter',
      target_champion: target,
      counter_champion: counter,
      proposer_id: userId,
      content: cleanDoc(content),
      build: toProposalBuild(build, patch),
    }),
    '제안을 보내지 못했습니다.',
  );
}

/** 문서 수정 제안. baseRevisionId = 편집을 시작할 때 보고 있던 문서 버전 */
export async function proposeDocEdit(userId, counterRow, content, baseRevisionId) {
  await run(
    db().from('edit_proposals').insert({
      type: 'doc_edit',
      target_champion: counterRow.target_champion,
      counter_champion: counterRow.counter_champion,
      counter_id: counterRow.id,
      proposer_id: userId,
      content: cleanDoc(content),
      base_revision_id: baseRevisionId ?? null,
    }),
    '제안을 보내지 못했습니다.',
  );
}

/** 내 제안 목록 (최근 순). RLS가 내 것만 돌려준다. */
export function getMyProposals(userId) {
  return run(
    db().from('edit_proposals').select(PROPOSAL_COLUMNS).eq('proposer_id', userId).order('created_at', { ascending: false }),
    '내 제안을 불러오지 못했습니다.',
  );
}

/** 내 제안 하나 (다시 제출 화면용). RLS가 내 것만 돌려준다. */
export function getMyProposal(userId, id) {
  return run(
    db().from('edit_proposals').select(PROPOSAL_COLUMNS).eq('proposer_id', userId).eq('id', id).maybeSingle(),
    '제안을 불러오지 못했습니다.',
  );
}

// ---------------- 알림 (확인하면 꺼짐) ----------------
// 알림은 DB 함수만 만든다 (재검토 요청, 제안 승인·거절, 빌드 승인·거절·숨김·다시 공개). /me에서 보이면 읽음 처리 → 상단 빨간 점이 꺼진다.

const NOTIFICATIONS_CHANGED = 'tlc:notifications-changed';
/** 읽음 처리 등으로 알림 개수가 바뀌었을 때 상단 빨간 점이 다시 세도록 */
export function onNotificationsChanged(cb) {
  window.addEventListener(NOTIFICATIONS_CHANGED, cb);
  return () => window.removeEventListener(NOTIFICATIONS_CHANGED, cb);
}

/** 안 읽은 내 알림 (최근 순). RLS가 내 것만 돌려준다. */
export function getMyUnreadNotifications(userId) {
  return run(
    db().from('notifications')
      .select('id, kind, proposal_id, build_id, post_id, counter_id, message, created_at, counter:counters!notifications_counter_id_fkey(target_champion, counter_champion, status)')
      .eq('user_id', userId).is('read_at', null).order('created_at', { ascending: false }),
    '알림을 불러오지 못했습니다.',
  );
}

/** 내 알림 읽음 처리 (본인 것만 처리된다 — DB 함수가 확인) */
export async function markNotificationsRead(ids) {
  if (ids.length === 0) return;
  await rpc('mark_notifications_read', { p_ids: ids }, '알림을 확인 처리하지 못했습니다.');
  window.dispatchEvent(new Event(NOTIFICATIONS_CHANGED));
}

/**
 * 재검토 요청 받은 내 제안을 고쳐서 다시 제출 → 승인 대기. 본인만 (DB 함수가 확인)
 * 새 카운터 제안은 글 + 빌드(필수), 문서 수정 제안은 글만 (build = null)
 */
export const resubmitProposal = (id, content, build, patch) =>
  rpc('resubmit_proposal', { p_id: id, p_content: cleanDoc(content), p_build: build ? toProposalBuild(build, patch) : null }, '다시 보내지 못했습니다.');

/**
 * 승인 대기 중인 내 제안 고치기 (순서는 그대로, 운영자에게 "제안자가 고침" 표시). 본인만 (DB 함수가 확인)
 * 새 카운터 제안은 글 + 빌드(필수, 지금 패치로), 문서 수정 제안은 글만 (build = null)
 */
export const editMyProposal = (id, content, build, patch) =>
  rpc('edit_my_proposal', { p_id: id, p_content: cleanDoc(content), p_build: build ? toProposalBuild(build, patch) : null }, '고치지 못했습니다.');

/** 운영자가 처리하려는 사이 제안자·작성자가 고쳐서 막혔나 → 새 내용을 다시 불러오게 한다 */
export const isChangedByAuthor = (err) => /방금 고쳤습니다/.test(err?.message ?? '');

/** 숨긴 카운터 재검토 흐름의 제안인가 (그 카운터를 만든 새 카운터 제안) — 요청 취소는 [다시 공개]로 */
export const isHiddenCounterFlow = (p) => p.type === 'new_counter' && p.counter_id != null;
/** 숨긴 카운터 재검토 후 다시 낸 제안인가 */
export const isResubmission = (p) => isHiddenCounterFlow(p) && p.resubmitted_at != null;
/** 운영자가 고쳐서 승인했나 */
export const approvedWithEdits = (p) => p.status === 'approved' && (p.approved_content != null || p.approved_build != null);

// ---------------- 운영자 ----------------

/**
 * 제안과 대상 카운터를 보고 승인 전에 알아야 할 것.
 * counter: 운영자가 읽은 대상 카운터(+ matchup_docs) | null
 */
function reviewFlags(proposal, counter) {
  const current = one(counter?.matchup_docs);
  // 재검토 후 다시 낸 제안: 숨긴 문서 → 고친 내용을 비교하고, 승인하면 다시 공개된다
  const resubmitted = isResubmission(proposal) && counter?.status === 'hidden';
  const hidden = counter?.status === 'hidden' && !resubmitted;
  // 이미 승인된 새 카운터 제안이면 그 카운터는 "자기 자신"이라 중복 경고 대상이 아니다
  const exists = proposal.type === 'doc_edit' || counter?.status === 'approved';
  const stale = proposal.type === 'doc_edit' && proposal.status === 'pending' && current != null
    && proposal.base_revision_id != null && current.revision_id !== proposal.base_revision_id;
  return { current, resubmitted, hidden, exists, stale };
}

/**
 * 목록에서 바로 승인하면 위험한 이유 (없으면 null) → 줄에서 [승인]을 잠그고 [자세히]로 보낸다.
 * 거절은 줄에서 바로 할 수 있다.
 */
export function quickApproveBlock(proposal, flags, game) {
  if (flags.hidden) return '숨긴 카운터에 대한 제안입니다.';
  if (proposal.type === 'new_counter' && game) {
    const b = proposalBuildBlock(proposal.build, game);
    if (b) return b;
  }
  if (proposal.type === 'new_counter' && flags.exists) return '같은 카운터가 이미 공개돼 있습니다.';
  if (proposal.type === 'doc_edit' && !flags.current) return '수정할 문서를 찾지 못했습니다.';
  if (flags.stale) return '제안 뒤에 문서가 바뀌었습니다.';
  return null;
}

/**
 * 승인 대기 목록 (오래된 순) + 줄에서 바로 승인해도 되는지 (block: 막는 이유 | null).
 * game(Data Dragon)을 주면 새 카운터 제안의 빌드도 확인한다.
 */
export async function getPendingProposals(game) {
  const [pending, counters] = await Promise.all([
    run(
      db().from('edit_proposals').select(PROPOSAL_COLUMNS).eq('status', 'pending').order('created_at', { ascending: true }),
      '승인 대기 목록을 불러오지 못했습니다.',
    ),
    // 운영자는 숨긴 카운터도 읽는다 (RLS: is_admin)
    run(
      db().from('counters').select('id, target_champion, counter_champion, status, matchup_docs(revision_id)'),
      '카운터 목록을 확인하지 못했습니다.',
    ),
  ]);
  return pending.map((p) => {
    const counter = p.type === 'doc_edit' || isResubmission(p)
      ? counters.find((c) => c.id === p.counter_id)
      : counters.find((c) => c.target_champion === p.target_champion && c.counter_champion === p.counter_champion);
    const flags = reviewFlags(p, counter ?? null);
    return { ...p, resubmitted: flags.resubmitted, block: quickApproveBlock(p, flags, game) };
  });
}

/**
 * 제안 하나 + 비교할 지금 문서.
 * { proposal, current: 지금 문서 | null, exists: (새 카운터) 이미 공개된 같은 카운터가 있나,
 *   hidden: 대상 카운터를 운영자가 숨겼나(승인 불가), stale: 제안 후 문서가 바뀌었나,
 *   resubmitted: 재검토 후 다시 낸 제안인가(current = 숨긴 문서, 승인하면 다시 공개) }
 */
export async function getProposalForReview(id) {
  const proposal = await run(
    db().from('edit_proposals').select(PROPOSAL_COLUMNS).eq('id', id).maybeSingle(),
    '제안을 불러오지 못했습니다.',
  );
  if (!proposal) return null;
  // 운영자는 숨긴 카운터도 읽을 수 있다 (RLS: is_admin)
  const counter = proposal.type === 'doc_edit'
    ? await run(
      db().from('counters').select(`id, status, matchup_docs(${DOC_COLUMNS})`).eq('id', proposal.counter_id).maybeSingle(),
      '지금 문서를 불러오지 못했습니다.',
    )
    : await run(
      db()
        .from('counters')
        .select(`id, status, matchup_docs(${DOC_COLUMNS})`)
        .eq('target_champion', proposal.target_champion)
        .eq('counter_champion', proposal.counter_champion)
        .maybeSingle(),
      '지금 카운터 목록을 확인하지 못했습니다.',
    );
  const { current, resubmitted, hidden, exists, stale } = reviewFlags(proposal, counter);
  // 재검토 후 다시 낸 제안: 비교할 원래 첫 빌드 (이 제안에서 공개됐던 빌드 중 최근 것)
  const firstBuilds = resubmitted
    ? await run(
      db().from('builds').select(FIRST_BUILD_COLUMNS).eq('proposal_id', proposal.id).order('id', { ascending: false }),
      '원래 첫 빌드를 불러오지 못했습니다.',
    )
    : [];
  return {
    proposal, current: proposal.type === 'doc_edit' || resubmitted ? current : null, exists, hidden, stale, resubmitted,
    firstBuild: firstBuilds.find((b) => b.status === 'approved') ?? firstBuilds[0] ?? null,
  };
}

const one = (v) => (Array.isArray(v) ? v[0] ?? null : v ?? null);
const FIRST_BUILD_COLUMNS =
  'id, status, runes, summoner_spells, starting_items, core_items, max_skill, patch, up_count, down_count';

async function rpc(name, args, fallback) {
  const { data, error } = await db().rpc(name, args);
  if (error) throw friendly(error, fallback);
  return data;
}

// 승인·재검토 요청·거절은 p = 화면이 본 제안 줄 { id, version }을 받는다.
// 그 사이 제안자가 고쳤으면 DB가 "제안자가 방금 고쳤습니다. 다시 확인해 주세요."로 거부한다 (isChangedByAuthor).

/**
 * 승인: 메모 필수 (제안자에게 보인다).
 * edits = { content, build, patch } — 운영자가 고친 것만 넣는다 (안 고친 칸은 빼면 제안 그대로 공개).
 * build는 등록 화면 값 모양, patch는 지금 Data Dragon 버전 (고친 빌드는 지금 패치로 기록)
 */
export const approveProposal = (p, note, { content = null, build = null, patch = null } = {}) =>
  rpc('approve_proposal', {
    p_id: p.id, p_note: note, p_content: content ? cleanDoc(content) : null, p_build: build ? toProposalBuild(build, patch) : null,
    p_version: p.version,
  }, '승인하지 못했습니다.');
/** 거절: 승인 대기·재검토 기다리는 중인 제안 */
export const rejectProposal = (p, reason) =>
  rpc('reject_proposal', { p_id: p.id, p_reason: reason, p_version: p.version }, '거절하지 못했습니다.');
/** 승인 대기 제안에 재검토 요청 (메모 필수, 제안자에게 알림) */
export const requestProposalRevision = (p, note) =>
  rpc('request_proposal_revision', { p_id: p.id, p_note: note, p_version: p.version }, '재검토를 요청하지 못했습니다.');
/** 재검토 요청 취소 → 원래 제안 그대로 승인 대기 (메모 필수, 제안자에게 알림) */
export const cancelProposalRevision = (id, note) =>
  rpc('cancel_proposal_revision', { p_id: id, p_note: note }, '요청을 취소하지 못했습니다.');

/** 재검토를 요청하고 제안자가 고쳐 내기를 기다리는 제안 (숨긴 카운터 흐름은 "숨긴 카운터"에서 처리하므로 뺀다) */
export async function getRevisionProposals() {
  const rows = await run(
    db().from('edit_proposals').select(PROPOSAL_COLUMNS).eq('status', 'revision_requested').order('revision_requested_at', { ascending: true }),
    '재검토 기다리는 제안을 불러오지 못했습니다.',
  );
  return rows.filter((p) => !isHiddenCounterFlow(p));
}
/** ids = 그 챔피언의 공개된 카운터 id 전부, 새 순서대로 */
export const reorderCounters = (target, ids) => rpc('reorder_counters', { p_target: target, p_ids: ids }, '순서를 저장하지 못했습니다.');
/** 되돌리기: 메모 필수 (수정 기록에 남는다) */
export const revertDoc = (revisionId, note) => rpc('revert_doc', { p_revision_id: revisionId, p_note: note }, '되돌리지 못했습니다.');

/** 문서 버전 목록 (최근 순) */
export function getRevisions(counterRowId) {
  return run(
    db()
      .from('doc_revisions')
      .select(
        'id, kind, content, note, created_at, proposal_id, reverted_from, ' +
          `editor:profiles!doc_revisions_edited_by_fkey(${PERSON}), approver:profiles!doc_revisions_approved_by_fkey(${PERSON})`,
      )
      .eq('counter_id', counterRowId)
      .order('created_at', { ascending: false })
      .order('id', { ascending: false }),
    '수정 기록을 불러오지 못했습니다.',
  );
}

// ---------------- 카운터 숨기기(승인 취소) / 다시 공개 ----------------

/** 숨기기: 일반 사용자에게서 카운터·문서·빌드를 가린다. 그 카운터를 만든 제안은 "승인 취소"가 된다. 사유 필수 */
export const hideCounter = (counterRowId, reason) =>
  rpc('hide_counter', { p_counter_id: counterRowId, p_reason: reason }, '숨기지 못했습니다.');
/** 다시 공개: 목록 맨 뒤로 돌아오고, 제안은 다시 "승인". 메모 필수 */
export const restoreCounter = (counterRowId, note) =>
  rpc('restore_counter', { p_counter_id: counterRowId, p_note: note }, '다시 공개하지 못했습니다.');

/**
 * 숨긴 카운터 목록 — 운영자만.
 * 각 카운터: logs(숨김·공개·재검토 기록, 최근 순), origin(그 카운터를 만든 제안 | null: 초기 데이터처럼 제안 없이 생김)
 */
export async function getHiddenCounters() {
  const counters = await run(
    db().from('counters').select('id, target_champion, counter_champion, status').eq('status', 'hidden'),
    '숨긴 카운터를 불러오지 못했습니다.',
  );
  if (counters.length === 0) return [];
  const ids = counters.map((c) => c.id);
  const [logs, origins] = await Promise.all([
    run(
      db()
        .from('counter_status_log')
        .select(`id, counter_id, action, reason, created_at, actor:profiles!counter_status_log_actor_fkey(${PERSON})`)
        .in('counter_id', ids)
        .order('created_at', { ascending: false })
        .order('id', { ascending: false }),
      '숨김 기록을 불러오지 못했습니다.',
    ),
    run(
      db().from('edit_proposals').select(PROPOSAL_COLUMNS).eq('type', 'new_counter').in('counter_id', ids)
        .order('id', { ascending: false }),
      '원래 제안을 불러오지 못했습니다.',
    ),
  ]);
  return counters.map((c) => ({
    ...c,
    logs: logs.filter((l) => l.counter_id === c.id),
    origin: origins.find((p) => p.counter_id === c.id) ?? null,
  }));
}

/** 숨긴 카운터의 매치업 문서 (운영자 미리보기). 숨긴 카운터가 아니면 null */
export async function getHiddenMatchup(targetId, counterId) {
  const row = await run(
    db()
      .from('counters')
      .select(`id, target_champion, counter_champion, status, matchup_docs(${DOC_COLUMNS})`)
      .eq('target_champion', targetId)
      .eq('counter_champion', counterId)
      .eq('status', 'hidden')
      .maybeSingle(),
    '숨긴 카운터를 불러오지 못했습니다.',
  );
  if (!row) return null;
  const { matchup_docs, ...counter } = row;
  return { counter, doc: one(matchup_docs) };
}

/** 재검토 요청: 메모 필수. 그 카운터를 만든 제안이 "재검토 요청"이 되고 제안자 /me에 메모가 보인다 */
export const requestRevision = (counterRowId, note) =>
  rpc('request_revision', { p_counter_id: counterRowId, p_note: note }, '재검토를 요청하지 못했습니다.');

/** 완전 삭제할 때 함께 지워지는 것 개수 */
export async function getDeletionCounts(counterRowId) {
  const [proposals, revisions, builds, comments] = await Promise.all([
    run(db().from('edit_proposals').select('id').eq('counter_id', counterRowId), '개수를 세지 못했습니다.'),
    run(db().from('doc_revisions').select('id').eq('counter_id', counterRowId), '개수를 세지 못했습니다.'),
    run(db().from('builds').select('id').eq('counter_id', counterRowId), '개수를 세지 못했습니다.'),
    run(db().from('doc_comments').select('id').eq('counter_id', counterRowId), '개수를 세지 못했습니다.'),
  ]);
  const votes = builds.length === 0 ? [] : await run(
    db().from('build_votes').select('build_id').in('build_id', builds.map((b) => b.id)),
    '개수를 세지 못했습니다.',
  );
  return { proposals: proposals.length, revisions: revisions.length, builds: builds.length, votes: votes.length, comments: comments.length };
}

/** 완전 삭제: 숨긴 카운터만. confirmChampion = 이기는 챔피언 ID (DB가 실제 카운터와 같은지 확인) */
export const deleteCounter = (counterRowId, confirmChampion, reason) =>
  rpc('delete_counter', { p_counter_id: counterRowId, p_confirm: confirmChampion, p_reason: reason }, '삭제하지 못했습니다.');

/** 삭제 기록 (최근 순) — 운영자만 */
export function getDeletions() {
  return run(
    db()
      .from('counter_deletions')
      .select(
        'id, target_champion, counter_champion, reason, deleted_at, proposals_count, revisions_count, builds_count, votes_count, comments_count, ' +
          `deleter:profiles!counter_deletions_deleted_by_fkey(${PERSON}), proposer:profiles!counter_deletions_proposer_id_fkey(${PERSON})`,
      )
      .order('deleted_at', { ascending: false }),
    '삭제 기록을 불러오지 못했습니다.',
  );
}
