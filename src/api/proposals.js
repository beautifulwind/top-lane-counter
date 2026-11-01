// 제안·승인 접근 계층. 화면 컴포넌트는 이 모듈만 호출한다.
// 권한은 DB가 막는다: 제안 넣기는 RLS + 검사 트리거, 승인·거절·순서·되돌리기는 운영자 전용 함수(rpc).
import { db } from './supabase';
import { cleanDoc } from '../lib/docContent';

const PERSON = 'nickname, level, main_title';
const PROPOSAL_COLUMNS =
  'id, type, target_champion, counter_champion, counter_id, content, status, reject_reason, reviewed_at, created_at, base_revision_id, ' +
  'revoke_reason, revoked_at, ' +
  `proposer:profiles!edit_proposals_proposer_id_fkey(${PERSON})`;
const DOC_COLUMNS = 'counter_id, summary, level_notes, lane_cautions, updated_at, revision_id';

/** DB 오류를 사람이 읽을 문장으로. DB 함수·트리거는 한국어 문장으로 오류를 낸다. */
function friendly(error, fallback) {
  const msg = error?.message ?? '';
  if (/row-level security/i.test(msg)) return new Error('제안할 권한이 없어요. 로그인하고 닉네임을 정했는지 확인해 주세요.');
  if (/permission denied/i.test(msg)) return new Error('권한이 없어요. (운영자만 할 수 있는 작업이에요)');
  if (/[가-힣]/.test(msg)) return new Error(msg);
  return new Error(`${fallback} (${msg})`);
}

async function run(query, fallback) {
  const { data, error } = await query;
  if (error) throw friendly(error, fallback);
  return data;
}

// ---------------- 제안 넣기 (로그인 + 닉네임 필요) ----------------

/** 새 카운터 제안: target(지는 쪽)을 counter(이기는 쪽)가 이긴다 + 첫 문서 내용 */
export async function proposeNewCounter(userId, target, counter, content) {
  await run(
    db().from('edit_proposals').insert({
      type: 'new_counter',
      target_champion: target,
      counter_champion: counter,
      proposer_id: userId,
      content: cleanDoc(content),
    }),
    '제안을 보내지 못했어요.',
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
    '제안을 보내지 못했어요.',
  );
}

/** 내 제안 목록 (최근 순). RLS가 내 것만 돌려준다. */
export function getMyProposals(userId) {
  return run(
    db().from('edit_proposals').select(PROPOSAL_COLUMNS).eq('proposer_id', userId).order('created_at', { ascending: false }),
    '내 제안을 불러오지 못했어요.',
  );
}

// ---------------- 운영자 ----------------

/** 승인 대기 목록 (오래된 순) */
export function getPendingProposals() {
  return run(
    db().from('edit_proposals').select(PROPOSAL_COLUMNS).eq('status', 'pending').order('created_at', { ascending: true }),
    '승인 대기 목록을 불러오지 못했어요.',
  );
}

/**
 * 제안 하나 + 비교할 지금 문서.
 * { proposal, current: 지금 문서 | null, exists: (새 카운터) 이미 공개된 같은 카운터가 있나,
 *   hidden: 대상 카운터를 운영자가 숨겼나, stale: 제안 후 문서가 바뀌었나 }
 */
export async function getProposalForReview(id) {
  const proposal = await run(
    db().from('edit_proposals').select(PROPOSAL_COLUMNS).eq('id', id).maybeSingle(),
    '제안을 불러오지 못했어요.',
  );
  if (!proposal) return null;
  // 운영자는 숨긴 카운터도 읽을 수 있다 (RLS: is_admin)
  const counter = proposal.type === 'doc_edit'
    ? await run(
      db().from('counters').select(`id, status, matchup_docs(${DOC_COLUMNS})`).eq('id', proposal.counter_id).maybeSingle(),
      '지금 문서를 불러오지 못했어요.',
    )
    : await run(
      db()
        .from('counters')
        .select(`id, status, matchup_docs(${DOC_COLUMNS})`)
        .eq('target_champion', proposal.target_champion)
        .eq('counter_champion', proposal.counter_champion)
        .maybeSingle(),
      '지금 카운터 목록을 확인하지 못했어요.',
    );
  const current = one(counter?.matchup_docs);
  const hidden = counter?.status === 'hidden';
  // 이미 승인된 새 카운터 제안이면 그 카운터는 "자기 자신"이라 중복 경고 대상이 아니다
  const exists = proposal.type === 'doc_edit' || counter?.status === 'approved';
  const stale = proposal.type === 'doc_edit' && proposal.status === 'pending' && current != null
    && proposal.base_revision_id != null && current.revision_id !== proposal.base_revision_id;
  return { proposal, current: proposal.type === 'doc_edit' ? current : null, exists, hidden, stale };
}

const one = (v) => (Array.isArray(v) ? v[0] ?? null : v ?? null);

async function rpc(name, args, fallback) {
  const { data, error } = await db().rpc(name, args);
  if (error) throw friendly(error, fallback);
  return data;
}

export const approveProposal = (id) => rpc('approve_proposal', { p_id: id }, '승인하지 못했어요.');
export const rejectProposal = (id, reason) => rpc('reject_proposal', { p_id: id, p_reason: reason }, '거절하지 못했어요.');
/** ids = 그 챔피언의 공개된 카운터 id 전부, 새 순서대로 */
export const reorderCounters = (target, ids) => rpc('reorder_counters', { p_target: target, p_ids: ids }, '순서를 저장하지 못했어요.');
export const revertDoc = (revisionId) => rpc('revert_doc', { p_revision_id: revisionId }, '되돌리지 못했어요.');

/** 문서 버전 목록 (최근 순) */
export function getRevisions(counterRowId) {
  return run(
    db()
      .from('doc_revisions')
      .select(
        'id, kind, content, created_at, proposal_id, reverted_from, ' +
          `editor:profiles!doc_revisions_edited_by_fkey(${PERSON}), approver:profiles!doc_revisions_approved_by_fkey(${PERSON})`,
      )
      .eq('counter_id', counterRowId)
      .order('created_at', { ascending: false })
      .order('id', { ascending: false }),
    '수정 기록을 불러오지 못했어요.',
  );
}

// ---------------- 카운터 숨기기(승인 취소) / 다시 공개 ----------------

/** 숨기기: 일반 사용자에게서 카운터·문서·빌드를 가린다. 그 카운터를 만든 제안은 "승인 취소"가 된다. 사유 필수 */
export const hideCounter = (counterRowId, reason) =>
  rpc('hide_counter', { p_counter_id: counterRowId, p_reason: reason }, '숨기지 못했어요.');
/** 다시 공개: 목록 맨 뒤로 돌아오고, 제안은 다시 "승인". 메모는 선택 */
export const restoreCounter = (counterRowId, note) =>
  rpc('restore_counter', { p_counter_id: counterRowId, p_note: note || null }, '다시 공개하지 못했어요.');

/** 숨긴 카운터 목록 + 각 카운터의 숨김·공개 기록(최근 순) — 운영자만 */
export async function getHiddenCounters() {
  const counters = await run(
    db().from('counters').select('id, target_champion, counter_champion, status').eq('status', 'hidden'),
    '숨긴 카운터를 불러오지 못했어요.',
  );
  if (counters.length === 0) return [];
  const logs = await run(
    db()
      .from('counter_status_log')
      .select(`id, counter_id, action, reason, created_at, actor:profiles!counter_status_log_actor_fkey(${PERSON})`)
      .order('created_at', { ascending: false }),
    '숨김 기록을 불러오지 못했어요.',
  );
  return counters.map((c) => ({ ...c, logs: logs.filter((l) => l.counter_id === c.id) }));
}
