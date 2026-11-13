// ☰ 메뉴 도우미 (상단 바는 로고와 ☰만 — 마이페이지·탑신병자 커뮤니티·관리·로그인·로그아웃은 메뉴 패널 안)
import { fireEvent, screen, waitFor, within } from '@testing-library/react';
import { expect } from 'vitest';

export const menuButton = () => screen.findByRole('button', { name: /^메뉴 열기/ });

/** ☰를 눌러 패널을 열고, 패널 안을 찾는 within을 돌려준다 */
export async function openMenu() {
  fireEvent.click(await menuButton());
  const panel = await screen.findByRole('dialog', { name: '메뉴' });
  // 로그인 확인·프로필 읽기가 끝나야 항목이 생긴다
  await waitFor(() => expect(panel.querySelector('.menu-item')).not.toBeNull());
  return within(panel);
}

/** 메뉴를 열고 항목(링크·버튼)을 누른다 */
export async function clickMenu(name, role = 'link') {
  const menu = await openMenu();
  fireEvent.click(await menu.findByRole(role, { name }));
}

/** 메뉴 맨 위에 보이는 "Lv.7 칭호 닉네임" 글자 (보고 나서 Esc로 닫는다) */
export async function menuUserText() {
  const menu = await openMenu();
  let text = '';
  await waitFor(() => {
    text = document.querySelector('.menu-user')?.textContent ?? '';
    expect(text).not.toBe('');
  });
  fireEvent.keyDown(await menu.findByRole('button', { name: '메뉴 닫기' }), { key: 'Escape' });
  return text;
}
