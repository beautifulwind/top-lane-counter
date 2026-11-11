// ⋮ 더보기 메뉴 도우미 (040: 글·댓글 메뉴)
import { fireEvent, screen, within } from '@testing-library/react';

/** scope(screen 또는 within(...)) 안의 ⋮ 버튼을 눌러 연 메뉴의 within */
export function openMore(scope = screen, label = /더보기/) {
  const btn = scope.getAllByRole('button', { name: label })[0];
  if (btn.getAttribute('aria-expanded') !== 'true') fireEvent.click(btn);
  return within(document.getElementById(btn.getAttribute('aria-controls')));
}

/** ⋮ 메뉴를 열고 항목을 누른다 */
export function pickMore(scope, item, label) {
  const menu = openMore(scope, label);
  fireEvent.click(menu.getByRole('menuitem', { name: item }));
}

/** ⋮ 메뉴 항목 이름들 (열어서 보고 Esc로 닫는다). ⋮가 없으면 [] */
export function moreNames(scope = screen, label = /더보기/) {
  const btns = scope.queryAllByRole('button', { name: label });
  if (btns.length === 0) return [];
  const menu = openMore(scope, label);
  const names = menu.queryAllByRole('menuitem').map((el) => el.textContent);
  fireEvent.keyDown(menu.getAllByRole('menuitem')[0] ?? btns[0], { key: 'Escape' });
  return names;
}
