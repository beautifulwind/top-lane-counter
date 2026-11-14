import { describe, expect, test } from 'vitest';
import { displayNickname, hasReservedMark } from './nickname';

describe('닉네임 예약어 (운)·(감)', () => {
  test.each([
    '(운)', '(감)', '영자(운)', '(운)영자', '탑(감)신',
    '（운）', '（감）', '[운]', '[감]', '【운】', '「감」', '<운>', '〔운〕',
    '( 운 )', '(\u3000감\u3000)', '( 운)', '(감 )', '(\u200B운\u200B)', '(\u3164운)', '(운\u00AD)',
    '(운]', '［운］', '﹙감﹚',
  ])('막는다: %s', (nick) => {
    expect(hasReservedMark(nick)).toBe(true);
  });

  test.each(['영자', '운영자', '감독', '운', '감', '(운영)', '(감독)', '탑(고수)', '운)', '(감', '탑 운 감'])('통과: %s', (nick) => {
    expect(hasReservedMark(nick)).toBe(false);
  });
});

test('displayNickname: 운영자·감독관은 닉네임 앞에 똑같이 (운), 사람이 없으면 fallback', () => {
  expect(displayNickname({ nickname: '영자', role: 'admin' })).toBe('(운)영자');
  expect(displayNickname({ nickname: '감독', role: 'moderator' })).toBe('(운)감독');
  expect(displayNickname({ nickname: '탑고수', role: 'user' })).toBe('탑고수');
  expect(displayNickname({ nickname: '탑고수' })).toBe('탑고수');
  expect(displayNickname(null)).toBe('탈퇴한 이용자');
  expect(displayNickname({ nickname: '' })).toBe('탈퇴한 이용자');
  expect(displayNickname(null, '닉네임을 정하지 않은 사용자')).toBe('닉네임을 정하지 않은 사용자');
});
