import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { josa } from '../lib/josa';
import { BOARD_NAME } from '../lib/siteNames';

const css = readFileSync('src/index.css', 'utf8');
const rule = (sel) => css.split('\n').find((l) => l.startsWith(`${sel} {`)) ?? '';

describe('줄바꿈 표시와 이름', () => {
  it.each(['.prose', '.level dd', '.post-body', '.comment-body'])('%s: 줄바꿈 그대로 + 긴 줄 넘침 방지', (sel) => {
    expect(rule(sel)).toMatch(/white-space: pre-wrap/);
    expect(rule(sel)).toMatch(/overflow-wrap: anywhere/);
  });
  it('탑신병자 커뮤니티 뒤 조사', () => {
    expect(josa(BOARD_NAME, '과/와')).toBe('탑신병자 커뮤니티와');
    expect(josa(BOARD_NAME, '은/는')).toBe('탑신병자 커뮤니티는');
  });
});
