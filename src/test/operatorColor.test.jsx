// 운영자 전용 버튼·링크는 운영자 색(btn-op / top-btn op / op-link, 색은 src/styles/tokens.css의 --op)
// 일반 사용자 화면에는 운영자 색이 하나도 없어야 한다.
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { readFileSync } from 'node:fs';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeLogin, fakeProposal } from './fakeSupabase';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /></MemoryRouter>);
const asOperator = () => fakeLogin('u-op', { nickname: '영자(운)', role: 'admin', level: 0, main_title: null });
const opMarks = () => document.querySelectorAll('.btn-op, .top-btn.op, .op-link');
const isOp = (el) => el.matches('.btn-op, .top-btn.op, .op-link');

test('일반 사용자: 매치업·챔피언 화면에 운영자 색이 없다', async () => {
  fakeLogin('u-old', { nickname: '기존유저' });
  start('/champion/Darius/counter/Quinn');
  await screen.findByRole('link', { name: '문서 수정 제안' });
  expect(opMarks()).toHaveLength(0);
  cleanup();
  start('/champion/Darius');
  await screen.findByRole('link', { name: '+ 새 카운터 제안' });
  expect(opMarks()).toHaveLength(0);
});

test('운영자: 매치업의 [수정 기록] [카운터 숨기기] [빌드 숨기기]·상단 [관리]는 운영자 색, [문서 수정 제안]은 보통 색', async () => {
  asOperator();
  start('/champion/Darius/counter/Quinn');
  expect(isOp(await screen.findByRole('link', { name: '수정 기록' }))).toBe(true);
  expect(isOp(screen.getByRole('button', { name: '카운터 숨기기' }))).toBe(true);
  for (const b of screen.getAllByRole('button', { name: '빌드 숨기기' })) expect(isOp(b)).toBe(true);
  expect(isOp(screen.getByRole('link', { name: '관리' }))).toBe(true);
  expect(isOp(screen.getByRole('link', { name: '문서 수정 제안' }))).toBe(false);
  expect(isOp(screen.getByRole('link', { name: '+ 빌드 등록' }))).toBe(false);
});

test('운영자: 챔피언 화면의 [숨기기] [순서 변경]은 운영자 색', async () => {
  asOperator();
  start('/champion/Darius');
  expect(isOp(await screen.findByRole('link', { name: '순서 변경' }))).toBe(true);
  expect(isOp(screen.getByRole('button', { name: '퀸 숨기기' }))).toBe(true);
  expect(isOp(screen.getByRole('link', { name: '+ 새 카운터 제안' }))).toBe(false);
});

test('운영자 페이지: 처리 버튼·메모 확정은 운영자 색, 메모 [취소]는 보통 색', async () => {
  TABLES.edit_proposals.push(fakeProposal());
  asOperator();
  start('/admin');
  const row = await screen.findByRole('listitem', { name: '[문서 수정] 퀸(으)로 다리우스 잡는 법' });
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
  expect(tokens).toMatch(/--op: #6f42c1;/);
});
