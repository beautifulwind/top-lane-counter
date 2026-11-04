// 섹션 제목(SectionHead) + 옆 "N개" 알약 확인 (3단계 디자인: 개수는 제목 밖 알약)
import { screen } from '@testing-library/react';
import { expect, vi } from 'vitest';

/** 이름이 name인 제목을 찾고, 옆 알약이 "n개"가 될 때까지 기다린다. 제목을 돌려준다 */
export async function sectionCount(name, n) {
  const heading = await screen.findByRole('heading', { name });
  await vi.waitFor(() => {
    const h = screen.getByRole('heading', { name });
    expect(h.closest('.section-head').querySelector('.count-badge')?.textContent).toBe(`${n}개`);
  });
  return heading;
}
