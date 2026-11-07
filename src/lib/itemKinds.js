// 아이템 종류 (028, SPEC 5장 빌드 입력): Data Dragon item.json으로 나눈다. DB 가격표(item_prices.kind)도 이 값을 받는다.
// legendary 전설(완성템) · epic 서사(완성템의 중간 재료, 예: 덤불 조끼) · boots 신발(장화·강화 신발 포함)
// basic 기본템(재료 없음: 롱소드·도란템·여신의 눈물) · consumable 소모품 · trinket 장신구 · support 서포터 퀘스트템
export const ITEM_KINDS = ['legendary', 'epic', 'boots', 'basic', 'consumable', 'trinket', 'support'];

/** 핵심 템트리에 넣을 수 있는 종류 (전설은 1개 이상 — buildProblem·DB check_core_items) */
export const CORE_KINDS = ['legendary', 'epic', 'boots']; // 고르기 목록 순서도 이 순서 (전설 → 서사 → 신발)

/**
 * 아이템 하나의 종류. data = item.json의 data 전체, shopIds = 소환사의 협곡 상점 아이템 id 모음.
 * 서사는 "협곡 상점 아이템으로 이어지는 것"만 — 덤불 조끼의 다음 단계에는 협곡에 없는 아이템(323075)도 섞여 있다.
 * 신발은 Boots 표시가 있거나 신발로 만드는 것 (건메탈 군화는 Boots 표시가 없다).
 */
export function itemKind(it, data, shopIds) {
  const tags = it.tags ?? [];
  if (tags.includes('Consumable') || it.consumed) return 'consumable';
  if (tags.includes('Trinket')) return 'trinket';
  if (tags.includes('GoldPer')) return 'support';
  const from = it.from ?? [];
  if (tags.includes('Boots') || from.some((f) => (data[f]?.tags ?? []).includes('Boots'))) return 'boots';
  if (from.length === 0) return 'basic';
  if ((it.into ?? []).some((x) => shopIds.has(String(x)))) return 'epic';
  return 'legendary';
}

/** 핵심 템트리에 넣을 수 있는 아이템인가 (지금 상점에 있고 전설·서사·신발) */
export const isCoreItem = (it) => !!it && it.shop && CORE_KINDS.includes(it.kind);

