// 운영자 전용 버튼·링크는 운영자 색(btn-op / top-btn op / op-link, 색은 src/styles/tokens.css의 --op)
// 일반 사용자 화면에는 운영자 색이 하나도 없어야 한다.
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
// 승인 제도 화면은 지금 꺼 두었다(lib/features.js). 이 파일의 승인 검사는 켠 채로 한다 — 끈 상태는 approvalOff.test.jsx
vi.mock('../lib/features', async (importOriginal) => ({ ...(await importOriginal()), APPROVAL_ENABLED: true }));
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { readFileSync } from 'node:fs';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeLogin, fakeProposal } from './fakeSupabase';
import { openMenu } from './menu';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /></MemoryRouter>);
const asOperator = () => fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0, main_title: null });
const OP = '.btn-op, .top-btn.op, .op-link, .more-item.op'; // 038: ⋮ 메뉴 안 운영진 항목도 보라
const opMarks = () => document.querySelectorAll(OP);
const isOp = (el) => el.matches(OP);

test('일반 사용자: 매치업·챔피언 화면에 운영자 색이 없다', async () => {
  fakeLogin('u-old', { nickname: '기존유저' });
  start('/champion/Darius/counter/Quinn');
  await screen.findByRole('link', { name: '빌드 수정' });
  expect(opMarks()).toHaveLength(0);
  cleanup();
  start('/champion/Darius');
  await screen.findByRole('link', { name: '+ 상대법 등록' });
  expect(opMarks()).toHaveLength(0);
});

test('운영자: 상대법 ⋮ 메뉴의 [상대법 숨기기] [예전 문서 수정 기록] [빌드 숨기기]·메뉴 [관리]는 운영자 색, [빌드 수정] [수정 기록] [+ 새 빌드]는 보통 색', async () => {
  asOperator();
  start('/champion/Darius/counter/Quinn');
  fireEvent.click(await screen.findByRole('button', { name: '상대법 더보기' }));
  expect(isOp(screen.getByRole('menuitem', { name: '상대법 숨기기' }))).toBe(true);
  expect(isOp(screen.getByRole('menuitem', { name: '예전 문서 수정 기록' }))).toBe(true);
  const other = screen.getByRole('button', { name: '빌드 2 더보기' });
  fireEvent.mouseDown(other); // 바깥을 누르면 앞의 메뉴는 닫힌다
  fireEvent.click(other);
  expect(screen.queryByRole('menuitem', { name: '상대법 숨기기' })).toBeNull();
  expect(isOp(screen.getByRole('menuitem', { name: '빌드 숨기기' }))).toBe(true);
  expect(isOp(screen.getByRole('link', { name: '빌드 수정' }))).toBe(false);
  expect(isOp(screen.getByRole('button', { name: '수정 기록' }))).toBe(false);
  expect(isOp(screen.getByRole('link', { name: '+ 새 빌드' }))).toBe(false);
  const menu = await openMenu();
  expect(isOp(menu.getByRole('link', { name: '관리' }))).toBe(true);
  expect(isOp(menu.getByRole('link', { name: '마이페이지' }))).toBe(false);
});

test('운영자: 챔피언 화면의 [숨기기] [순서 변경]은 운영자 색', async () => {
  asOperator();
  start('/champion/Darius');
  expect(isOp(await screen.findByRole('link', { name: '순서 변경' }))).toBe(true);
  expect(isOp(screen.getByRole('button', { name: '퀸 숨기기' }))).toBe(true);
  expect(isOp(screen.getByRole('link', { name: '+ 상대법 등록' }))).toBe(false);
});

test('운영자 페이지: 처리 버튼·메모 확정은 운영자 색, 메모 [취소]는 보통 색', async () => {
  TABLES.edit_proposals.push(fakeProposal());
  asOperator();
  start('/admin');
  const row = await screen.findByRole('listitem', { name: '[문서 수정] 퀸으로 다리우스 이기는 법' });
  for (const name of ['승인', '재검토 요청', '거절']) expect(isOp(within(row).getByRole('button', { name }))).toBe(true);
  expect(isOp(within(row).getByRole('link', { name: '자세히' }))).toBe(true);
  fireEvent.click(within(row).getByRole('button', { name: '거절' }));
  expect(isOp(within(row).getByRole('button', { name: '거절 확정' }))).toBe(true);
  expect(isOp(within(row).getByRole('button', { name: '취소' }))).toBe(false);
});

test('색은 tokens.css 한 곳에서만: index.css에는 색 값이 없다', () => {
  const css = readFileSync('src/index.css', 'utf8');
  expect(css.match(/#[0-9a-f]{3,8}\b|rgba?\(/gi)).toBeNull();
  const tokens = readFileSync('src/styles/tokens.css', 'utf8');
  expect(tokens).toMatch(/--op: #a48bff;/);
});
