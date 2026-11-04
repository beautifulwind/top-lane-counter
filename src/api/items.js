// 자주 쓰는 아이템 (028, SPEC 5장 빌드 입력): 아이템 고르기 목록 맨 위에 먼저 보이는 아이템.
// 읽기는 누구나, 추가·빼기는 운영자 전용 DB 함수로만 (넣을 수 있는 종류·시작템 골드 상한은 DB가 확인).
import { db } from './supabase';

/** 칸: core = 핵심 템트리, starting = 시작 아이템 */
export const FREQUENT_SLOTS = { core: '핵심 템트리', starting: '시작 아이템' };

/** { core: [id…], starting: [id…] } (넣은 순서) */
export async function getFrequentItems() {
  const { data, error } = await db().from('frequent_items').select('slot, item_id, created_at').order('created_at', { ascending: true });
  if (error) throw new Error(`자주 쓰는 아이템을 불러오지 못했습니다. (${error.message})`);
  const out = { core: [], starting: [] };
  for (const r of data ?? []) out[r.slot]?.push(r.item_id);
  return out;
}

async function rpc(name, args, fallback) {
  const { error } = await db().rpc(name, args);
  if (error) {
    const msg = error.message ?? '';
    if (/permission denied/i.test(msg)) throw new Error('운영자만 할 수 있는 작업입니다.');
    throw new Error(/[가-힣]/.test(msg) ? msg : `${fallback} (${msg})`);
  }
}

export const addFrequentItem = (slot, itemId) =>
  rpc('add_frequent_item', { p_slot: slot, p_item: itemId }, '자주 쓰는 아이템에 넣지 못했습니다.');
export const removeFrequentItem = (slot, itemId) =>
  rpc('remove_frequent_item', { p_slot: slot, p_item: itemId }, '자주 쓰는 아이템에서 빼지 못했습니다.');
