// 빌드 입력(BuildFields)을 채우는 테스트 도우미. 빌드 등록·새 카운터 제안·다시 제출 테스트가 같이 쓴다.
import { fireEvent, screen, within } from '@testing-library/react';
import { expect } from 'vitest';

export const pick = (group, name) => fireEvent.click(within(screen.getByRole('group', { name: group })).getByRole('button', { name }));

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
