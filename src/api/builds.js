// 빌드 접근 계층. 화면 컴포넌트는 이 모듈만 호출한다.
// 권한은 DB가 막는다: 등록은 RLS + 검사 트리거(승인 대기로만), 투표는 vote_build(), 승인·거절·숨기기·다시 공개는 운영자 전용 함수.
import { db } from './supabase';
import { compareBuilds, toRow } from '../lib/buildContent';

const PERSON = 'nickname, level, main_title';
const BUILD_FIELDS =
  'id, counter_id, author_id, proposal_id, runes, summoner_spells, starting_items, core_items, skill_order, early_skills, patch, ' +
  'up_count, down_count, status, created_at';
const AUTHOR = `author:profiles!builds_author_id_fkey(${PERSON})`;
const COUNTER = 'counter:counters!builds_counter_id_fkey(id, target_champion, counter_champion, status)';
const REVIEW_FIELDS = 'approve_note, reject_reason, hide_reason, hidden_at, reviewed_at';

function friendly(error, fallback) {
  const msg = error?.message ?? '';
  if (/row-level security/i.test(msg)) return new Error('빌드를 등록할 권한이 없어요. 로그인하고 닉네임을 정했는지 확인해 주세요.');
  if (/permission denied/i.test(msg)) return new Error('권한이 없어요. (로그인이 필요하거나 운영자만 할 수 있는 작업이에요)');
  if (/[가-힣]/.test(msg)) return new Error(msg);
  return new Error(`${fallback} (${msg})`);
}

async function run(query, fallback) {
  const { data, error } = await query;
  if (error) throw friendly(error, fallback);
  return data;
}

async function rpc(name, args, fallback) {
  const { data, error } = await db().rpc(name, args);
  if (error) throw friendly(error, fallback);
  return data;
}

const shape = ({ up_count, down_count, ...b }) => ({ ...b, up: up_count, down: down_count });

/**
 * 매치업의 공개된 빌드 (점수 → 투표 수 → 최신순). userId를 주면 내 표(mine: 1 | -1 | null)도 붙인다.
 */
export async function getBuilds(counterRowId, userId = null) {
  const rows = await run(
    db().from('builds').select(`${BUILD_FIELDS}, ${AUTHOR}`).eq('counter_id', counterRowId).eq('status', 'approved'),
    '빌드를 불러오지 못했어요.',
  );
  let votes = [];
  if (userId && rows.length > 0) {
    votes = await run(
      db().from('build_votes').select('build_id, value').eq('user_id', userId).in('build_id', rows.map((b) => b.id)),
      '내 투표를 불러오지 못했어요.',
    );
  }
  return rows
    .map((b) => ({ ...shape(b), mine: votes.find((v) => v.build_id === b.id)?.value ?? null }))
    .sort(compareBuilds);
}

/** 빌드 등록 → 승인 대기. patch = 지금 Data Dragon 버전 */
export async function submitBuild(userId, counterRowId, build, patch) {
  await run(
    db().from('builds').insert({ counter_id: counterRowId, author_id: userId, patch, ...toRow(build) }),
    '빌드를 보내지 못했어요.',
  );
}

/** 따봉(1)·비추(-1)·취소(null). 돌려주는 값: { up, down, mine } */
export const voteBuild = (buildId, value) =>
  rpc('vote_build', { p_build_id: buildId, p_value: value }, '투표하지 못했어요.');

/** 내 빌드 (최근 순, 모든 상태). RLS가 내 것만 돌려준다. counter: 숨긴 카운터면 null */
export async function getMyBuilds(userId) {
  const rows = await run(
    db().from('builds').select(`${BUILD_FIELDS}, ${REVIEW_FIELDS}, ${COUNTER}`)
      .eq('author_id', userId).order('created_at', { ascending: false }),
    '내 빌드를 불러오지 못했어요.',
  );
  return rows.map(shape);
}

/** 내 빌드 하나 ([이 빌드로 다시 쓰기]) */
export async function getMyBuild(userId, id) {
  const row = await run(
    db().from('builds').select(BUILD_FIELDS).eq('author_id', userId).eq('id', id).maybeSingle(),
    '빌드를 불러오지 못했어요.',
  );
  return row && shape(row);
}

// ---------------- 운영자 ----------------

const LOGS = `logs:build_status_log(id, action, reason, created_at, actor:profiles!build_status_log_actor_fkey(${PERSON}))`;

/** 같은 카운터에 공개된 다른 빌드 (똑같은 빌드인지 비교용) */
async function approvedByCounter(counterIds) {
  if (counterIds.length === 0) return [];
  return run(
    db().from('builds').select(BUILD_FIELDS).eq('status', 'approved').in('counter_id', counterIds),
    '공개된 빌드를 확인하지 못했어요.',
  );
}

const newestFirst = (logs) => [...(logs ?? [])].sort((a, b) => String(b.created_at).localeCompare(String(a.created_at)));

/** 승인 대기 빌드 (오래된 순) + 같은 카운터의 공개 빌드 (approved) */
export async function getPendingBuilds() {
  const pending = await run(
    db().from('builds').select(`${BUILD_FIELDS}, ${AUTHOR}, ${COUNTER}`).eq('status', 'pending').order('created_at', { ascending: true }),
    '빌드 승인 대기 목록을 불러오지 못했어요.',
  );
  const approved = await approvedByCounter([...new Set(pending.map((b) => b.counter_id))]);
  return { pending: pending.map(shape), approved: approved.map(shape) };
}

/** 숨긴 빌드 (최근 숨긴 순) + 기록 */
export async function getHiddenBuilds() {
  const rows = await run(
    db().from('builds').select(`${BUILD_FIELDS}, ${REVIEW_FIELDS}, ${AUTHOR}, ${COUNTER}`).eq('status', 'hidden')
      .order('hidden_at', { ascending: false }),
    '숨긴 빌드를 불러오지 못했어요.',
  );
  return rows.map(shape);
}

/** 빌드 하나 (운영자 [자세히]) + 처리 기록 + 같은 카운터의 공개 빌드 */
export async function getBuildForReview(id) {
  const row = await run(
    db().from('builds').select(`${BUILD_FIELDS}, ${REVIEW_FIELDS}, ${AUTHOR}, ${COUNTER}, ${LOGS}`).eq('id', id).maybeSingle(),
    '빌드를 불러오지 못했어요.',
  );
  if (!row) return null;
  const approved = await approvedByCounter([row.counter_id]);
  return { build: { ...shape(row), logs: newestFirst(row.logs) }, approved: approved.map(shape) };
}

export const approveBuild = (id, note) => rpc('approve_build', { p_id: id, p_note: note }, '승인하지 못했어요.');
export const rejectBuild = (id, reason) => rpc('reject_build', { p_id: id, p_reason: reason }, '거절하지 못했어요.');
export const hideBuild = (id, reason) => rpc('hide_build', { p_id: id, p_reason: reason }, '숨기지 못했어요.');
export const restoreBuild = (id, note) => rpc('restore_build', { p_id: id, p_note: note }, '다시 공개하지 못했어요.');
