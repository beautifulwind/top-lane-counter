// 말투 검사 (SPEC 3장 "화면 공통 규칙", 2026-11-04): 화면 문구는 "~합니다"체, 부탁만 "~해 주세요".
// 화면 코드(테스트 빼고)와 index.html에 "~해요"체 말끝(…어요·…에요·…돼요·…할까요·…할게요 등)이 다시 들어오면 실패한다.
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { expect, test } from 'vitest';

// "~요"로 끝나도 괜찮은 낱말: 부탁("주세요"·"하세요"·"보세요"·"두세요")과 "~요"로 끝나는 명사
const ALLOWED = new Set(['주세요', '하세요', '보세요', '두세요', '필요', '중요']);

function files(dir) {
  return readdirSync(dir).flatMap((name) => {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) return name === 'test' ? [] : files(p);
    return /\.(js|jsx)$/.test(name) && !/\.test\.(js|jsx)$/.test(name) ? [p] : [];
  });
}

test('화면 코드에 "~해요"체 말끝이 없다', () => {
  const found = [];
  for (const p of [...files('src'), 'index.html']) {
    for (const [i, line] of readFileSync(p, 'utf8').split('\n').entries()) {
      for (const [w] of line.matchAll(/[가-힣]+요/g)) {
        if (!ALLOWED.has(w)) found.push(`${p}:${i + 1} ${w}`);
      }
    }
  }
  expect(found).toEqual([]);
});
