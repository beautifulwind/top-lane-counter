// 빌드 입력(BuildFields)을 채우는 테스트 도우미. 빌드 등록·새 카운터 제안·다시 제출 테스트가 같이 쓴다.
import { fireEvent, screen, within } from '@testing-library/react';
import { expect } from 'vitest';

/** 아이템 고르기는 처음 N개만 보이므로, 버튼이 없으면 같은 칸의 [더보기]를 먼저 눌러 펼친다 */
export const pick = (group, name) => {
  let g = screen.getByRole('group', { name: group });
  if (!within(g).queryByRole('button', { name })) {
    const more = within(g.closest('fieldset')).queryByRole('button', { name: /^더보기/ });
    if (more) {
      fireEvent.click(more);
      g = screen.getByRole('group', { name: group });
    }
  }
  fireEvent.click(within(g).getByRole('button', { name }));
};

/** 선마만 빼고 다 채운다 (선마는 테스트가 고른다). withSkill: 선마(Q)까지. 시작 아이템은 도란의 검 + 물약 = 500골드 */
export function fillBuild({ withSkill = false } = {}) {
  pick('주 경로', '주 경로 정밀');
  pick('핵심 룬', '정복자');
  pick('주 경로 1줄', '승전보');
  pick('주 경로 2줄', '전설: 민첩함');
  pick('주 경로 3줄', '최후의 저항');
  pick('보조 경로', '보조 경로 결의');
  pick('보조 룬 (서로 다른 줄에서 2개)', '철거');
  pick('보조 룬 (서로 다른 줄에서 2개)', '사전 준비');
  pick('능력치 파편 공격', '공격 공격 속도');
  pick('능력치 파편 유연', '유연 적응형 능력치');
  pick('능력치 파편 방어', '방어 체력');
  pick('소환사 주문', '점멸');
  pick('소환사 주문', '순간이동');
  pick('시작 아이템 고르기', '도란의 검');
  pick('시작 아이템 고르기', '체력 물약');
  pick('핵심 템트리 고르기', '스테락의 도전');
  pick('핵심 템트리 고르기', '강철판 장화');
  pick('핵심 템트리 고르기', '선혈포식자');
  if (withSkill) pick(SKILL_GROUP, '선마 Q');
  expect(screen.getByRole('group', { name: SKILL_GROUP })).toBeDefined();
}

export const SKILL_GROUP = '선마 (첫 번째로 마스터할 스킬)';

/** 빌드 한 벌 (038): 한 줄 요약 + 필수 레벨(1·2·3·6) 딜교법 + 빌드(선마 Q까지)를 채운다. name: 빌드 이름 (선택) */
export function fillWikiBuild({ name = '', summary = '착취로 짧게 딜교' } = {}) {
  if (name) fireEvent.change(screen.getByLabelText('빌드 이름 (선택)'), { target: { value: name } });
  fireEvent.change(screen.getByLabelText('한 줄 요약 (필수)'), { target: { value: summary } });
  for (const lv of [1, 2, 3, 6]) fireEvent.change(screen.getByLabelText(`${lv}레벨 (필수)`), { target: { value: `${lv}렙 공략` } });
  fillBuild({ withSkill: true });
}

/** fillWikiBuild로 채운 빌드가 DB에 가는 모양 (p_build) */
export const WIKI_PAYLOAD = (extra = {}) => ({
  runes: { primaryPath: 8000, keystone: 8010, primary: [9111, 9104, 8299], secondaryPath: 8400, secondary: [8446, 8444], shards: [5005, 5008, 5011] },
  summoner_spells: ['SummonerFlash', 'SummonerTeleport'],
  starting_items: ['1055', '2003'],
  core_items: ['3053', '3047', '6631'],
  max_skill: 'Q',
  patch: '99.1.1',
  name: null,
  summary: '착취로 짧게 딜교',
  level_notes: { 1: '1렙 공략', 2: '2렙 공략', 3: '3렙 공략', 6: '6렙 공략' },
  lane_cautions: '',
  ...extra,
});
