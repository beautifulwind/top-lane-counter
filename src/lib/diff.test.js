import { expect, test } from 'vitest';
import { docDiff, lineDiff } from './diff';
import { cleanDoc, docProblem, sameDoc } from './docContent';

const req = { 1: 'a', 2: 'b', 3: 'c', 6: 'd', 9: 'e', 11: 'f' };

test('줄 비교: 같은 줄은 그대로, 바뀐 줄은 지움+더함', () => {
  expect(lineDiff('가\n나\n다', '가\n라\n다')).toEqual([
    { type: 'same', text: '가' }, { type: 'del', text: '나' }, { type: 'add', text: '라' }, { type: 'same', text: '다' },
  ]);
  expect(lineDiff('', '새 줄')).toEqual([{ type: 'add', text: '새 줄' }]);
  expect(lineDiff('옛 줄', '')).toEqual([{ type: 'del', text: '옛 줄' }]);
});

test('문서 비교: 요약 → 레벨(합친 목록, 숫자순) → 주의사항, 바뀐 칸 표시', () => {
  const before = { summary: '요약', level_notes: { ...req, 4: '4렙' }, lane_cautions: '주의' };
  const after = { summary: '요약', level_notes: { ...req, 9: 'E', 13: '13렙' }, lane_cautions: '주의' };
  const d = docDiff(before, after);
  expect(d.map((f) => f.label)).toEqual(['한 줄 요약', '1레벨', '2레벨', '3레벨', '4레벨', '6레벨', '9레벨', '11레벨', '13레벨', '라인전 주의사항']);
  expect(d.filter((f) => f.changed).map((f) => f.key)).toEqual(['lv4', 'lv9', 'lv13']);
  expect(d.find((f) => f.key === 'lv4')).toMatchObject({ before: '4렙', after: '' });
});

test('새 문서(before 없음)는 모든 칸이 바뀐 칸', () => {
  expect(docDiff(null, { summary: 's', level_notes: req, lane_cautions: '' }).filter((f) => f.changed)).toHaveLength(7);
});

test('문서 규칙: DB와 같은 기준으로 정리·검사', () => {
  expect(cleanDoc({ summary: ' s ', level_notes: { ...req, '07': ' 칠 ', 5: '  ' }, lane_cautions: ' x ' }))
    .toEqual({ summary: 's', level_notes: { ...req, 7: '칠' }, lane_cautions: 'x' });
  expect(docProblem({ summary: '', level_notes: req })).toBe('한 줄 요약을 적어 주세요.');
  expect(docProblem({ summary: 's', level_notes: { ...req, 9: ' ' } })).toBe('9레벨 딜교법은 꼭 적어야 해요.');
  expect(docProblem({ summary: 's'.repeat(101), level_notes: req })).toMatch(/100자 이하/);
  expect(docProblem({ summary: 's', level_notes: { ...req, 19: 'x' } })).toMatch(/1~18/);
  expect(docProblem({ summary: 's', level_notes: req })).toBeNull();
  expect(sameDoc({ summary: 's ', level_notes: { ...req, 5: '' } }, { summary: 's', level_notes: req, lane_cautions: '' })).toBe(true);
});
