// 탈퇴한 이용자 표기 통일 (SPEC 6-50): 처리 기록의 대상이 비어도 "탈퇴한 이용자"
import { expect, test } from 'vitest';
import { targetText, WITHDRAWN_USER } from '../components/ModeratorAdmin';

test('대상 닉네임·id가 비면 "탈퇴한 이용자"로 보인다', () => {
  expect(WITHDRAWN_USER).toBe('탈퇴한 이용자');
  expect(targetText({ target_kind: 'user', target_id: null, target_nickname: '탈퇴한 이용자' })).toBe('탈퇴한 이용자');
  expect(targetText({ target_kind: 'user', target_id: null, target_nickname: null })).toBe('탈퇴한 이용자');
  expect(targetText({ target_kind: 'user', target_id: null, target_nickname: '  ' })).toBe('탈퇴한 이용자');
  expect(targetText({ target_kind: 'user', target_id: 'u1', target_nickname: '철수' })).toBe('철수');
  expect(targetText({ target_kind: 'post', target_id: 12 })).toBe('글 #12');
  expect(targetText({ target_kind: 'post', target_id: null })).toBe('글 (탈퇴한 이용자)');
});
