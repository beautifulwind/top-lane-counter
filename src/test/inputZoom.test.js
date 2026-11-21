import { readFileSync } from 'node:fs';
import { describe, expect, test } from 'vitest';

// iOS는 16px 미만 입력칸에 포커스하면 화면을 확대하고 되돌리지 않는다 (SPEC 6-72)
const css = readFileSync('src/index.css', 'utf8');
const html = readFileSync('index.html', 'utf8');

describe('입력칸 글자 크기 · 확대', () => {
  test('글자 입력칸 전체에 16px 이상 규칙이 있다', () => {
    expect(css).toMatch(/textarea, select \{\s*font-size: max\(var\(--fs-md\), 16px\);/);
  });

  test('tokens.css의 본문 글자(--fs-md)는 16px', () => {
    expect(readFileSync('src/styles/tokens.css', 'utf8')).toMatch(/--fs-md: 16px;/);
  });

  test('입력칸을 직접 고르는 규칙에 16px 미만 글자 크기를 쓰지 않는다', () => {
    const small = ['--fs-2xs', '--fs-xs', '--fs-sm'];
    const bad = [];
    for (const m of css.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
      const [, sel, body] = m;
      if (!/\b(input|textarea|select)\b/.test(sel)) continue;
      const fs = body.match(/(?:^|[;\s])font-size:\s*([^;]+)/);
      if (!fs) continue;
      const v = fs[1].trim();
      const px = v.match(/^(\d+(?:\.\d+)?)px$/);
      if (small.some((t) => v.includes(t)) || (px && Number(px[1]) < 16)) bad.push(sel.trim());
    }
    expect(bad).toEqual([]);
  });

  test('viewport는 확대를 막지 않는다 (접근성)', () => {
    const vp = html.match(/<meta name="viewport" content="([^"]*)"/)[1];
    expect(vp).not.toMatch(/user-scalable\s*=\s*(no|0)/);
    expect(vp).not.toMatch(/maximum-scale/);
  });
});
