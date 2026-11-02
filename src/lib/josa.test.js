import { josa, josaOf, matchupTitle, matchupShort } from './josa';

test('받침 있음 / 없음 / ㄹ 받침', () => {
  expect(josa('다리우스', '을/를')).toBe('다리우스를');
  expect(josa('가렌', '을/를')).toBe('가렌을');
  expect(josa('티모', '은/는')).toBe('티모는');
  expect(josa('퀸', '은/는')).toBe('퀸은');
  expect(josa('퀸', '으로/로')).toBe('퀸으로');
  expect(josa('티모', '으로/로')).toBe('티모로');
  expect(josa('케일', '으로/로')).toBe('케일로'); // ㄹ 받침
  expect(josa('말파이트', '이/가')).toBe('말파이트가');
  expect(josa('누누와 윌럼프', '과/와')).toBe('누누와 윌럼프와');
});

test('한글이 아니면 자리표시 그대로', () => {
  expect(josaOf('K\'Sante', '을/를')).toBe('을(를)');
  expect(josaOf('X', '으로/로')).toBe('(으)로');
  expect(josaOf('', '은/는')).toBe('은(는)');
});

test('매치업 이름', () => {
  expect(matchupTitle('퀸', '다리우스')).toBe('퀸으로 다리우스 잡는 법');
  expect(matchupTitle('말파이트', '트린다미어')).toBe('말파이트로 트린다미어 잡는 법');
  expect(matchupShort('가렌', '다리우스')).toBe('가렌으로 다리우스');
});

test('모르는 조사는 바로 알린다', () => {
  expect(() => josa('퀸', '의/에')).toThrow();
});
