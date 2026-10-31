import { describe, expect, test } from 'vitest';
import { matchesQuery, toChosung } from './chosung';

describe('초성 검색', () => {
  test('초성 변환', () => {
    expect(toChosung('다리우스')).toBe('ㄷㄹㅇㅅ');
  });
  test('초성으로 찾기', () => {
    expect(matchesQuery('ㄷㄹㅇㅅ', '다리우스')).toBe(true);
    expect(matchesQuery('ㄷㄹ', '다리우스')).toBe(true);
    expect(matchesQuery('ㄱㄹ', '다리우스')).toBe(false);
  });
  test('이름 일부와 공백 무시', () => {
    expect(matchesQuery('리우', '다리우스')).toBe(true);
    expect(matchesQuery('리 신', '리 신')).toBe(true);
    expect(matchesQuery('리신', '리 신')).toBe(true);
  });
  test('영문 id', () => {
    expect(matchesQuery('dar', '다리우스', 'Darius')).toBe(true);
  });
});
