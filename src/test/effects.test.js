// useEffect 오용을 막는 정적 검사 (ESLint가 없어서 테스트로 대신한다)
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { expect, test } from 'vitest';

function sourceFiles(dir) {
  return readdirSync(dir).flatMap((name) => {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) return sourceFiles(p);
    return /\.(jsx?|tsx?)$/.test(name) && !/\.test\./.test(name) ? [p] : [];
  });
}

const EFFECT = /use(?:Layout|Insertion)?Effect\(\s*/g;

test('useEffect에 async 함수나 값을 return하는 화살표 함수를 넣지 않는다', () => {
  const problems = [];
  for (const file of sourceFiles('src')) {
    const src = readFileSync(file, 'utf8');
    for (const m of src.matchAll(EFFECT)) {
      const rest = src.slice(m.index + m[0].length);
      const line = src.slice(0, m.index).split('\n').length;
      if (/^async\b/.test(rest)) problems.push(`${file}:${line} async 함수를 바로 넣음`);
      else if (/^(?:\([^)]*\)|\w+)\s*=>\s*[^{\s]/.test(rest)) problems.push(`${file}:${line} 중괄호 없는 화살표 함수 (값을 return함)`);
    }
  }
  expect(problems).toEqual([]);
});
