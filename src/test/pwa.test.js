import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

// 설치 정보(manifest)·index.html·오프라인 화면의 색이 tokens.css의 --bg와 같은지, 아이콘 파일이 있는지 확인한다.
const read = (p) => readFileSync(join(process.cwd(), p), 'utf8');
const bg = /--bg:\s*(#[0-9a-fA-F]{6})/.exec(read('src/styles/tokens.css'))[1].toLowerCase();
const manifest = JSON.parse(read('public/manifest.json'));

describe('PWA 설치 정보', () => {
  it('테마색·배경색이 tokens.css의 --bg와 같다', () => {
    expect(manifest.theme_color.toLowerCase()).toBe(bg);
    expect(manifest.background_color.toLowerCase()).toBe(bg);
    expect(read('index.html')).toContain(`name="theme-color" content="${bg}"`);
  });
  it('이름과 standalone 화면', () => {
    expect(manifest.short_name).toBe('탑신병자');
    expect(manifest.display).toBe('standalone');
  });
  it('마스커블 아이콘을 포함하고 파일이 모두 있다', () => {
    expect(manifest.icons.some((i) => i.purpose === 'maskable')).toBe(true);
    for (const i of manifest.icons) expect(existsSync(join(process.cwd(), 'public', i.src))).toBe(true);
  });
});
