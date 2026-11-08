import { describe, expect, it } from 'vitest';
import { installKind } from '../lib/install';

describe('installKind (☰ 메뉴 [앱 설치] 보임 여부)', () => {
  it('이미 설치(standalone)면 숨긴다 — 다른 조건과 상관없이', () => {
    expect(installKind({ standalone: true, hasPrompt: true, ios: true })).toBe('installed');
  });
  it('설치 창을 쓸 수 있으면 설치 창', () => {
    expect(installKind({ standalone: false, hasPrompt: true, ios: false })).toBe('prompt');
  });
  it('아이폰은 안내', () => {
    expect(installKind({ standalone: false, hasPrompt: false, ios: true })).toBe('ios');
  });
  it('설치할 수 없는 환경은 숨긴다', () => {
    expect(installKind({ standalone: false, hasPrompt: false, ios: false })).toBe('none');
  });
});
