// 첫 화면 "등록된 빌드 수" (SPEC 6-78)
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { act, cleanup, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import { resetCountUp } from '../components/BuildCountBadge';
import { BUILD_COUNT_TTL_MS, invalidateBuildCount } from '../api/buildCount';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeBuild, fakeLogin, fakeState } from './fakeSupabase';

beforeEach(() => {
  invalidateBuildCount();
  resetCountUp();
  window.matchMedia = undefined;
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); vi.useRealTimers(); });

const start = () => render(<MemoryRouter initialEntries={['/']}><AppRoutes /></MemoryRouter>);
const asked = () => fakeState.queryLog.filter((q) => q.table === 'builds' && q.select === 'id').length;
const notice = () => document.querySelector('.build-count');
const spoken = () => notice()?.querySelector('.sr-only')?.textContent;
const visible = () => notice()?.querySelector('.build-count-visual');

test('비로그인(게스트)도 공개된 빌드 수를 본다 (승인 대기 1개는 제외)', async () => {
  start();
  await waitFor(() => expect(notice()).not.toBeNull());
  expect(spoken()).toBe('지금까지 4개의 빌드가 등록되었습니다.');
});

test('내가 차단한 사람의 빌드도 센다 (전체 기준)', async () => {
  fakeLogin('u-me', { nickname: '나', role: 'member', level: 1, main_title: null });
  TABLES.user_blocks.push({ blocker_id: 'u-me', blocked_id: 'u-102' });
  start();
  await waitFor(() => expect(notice()).not.toBeNull());
  expect(spoken()).toContain('4개');
});

test('0개면 숨긴다', async () => {
  TABLES.builds = [];
  start();
  await screen.findByRole('heading', { level: 1, name: '챔피언 선택' });
  await waitFor(() => expect(asked()).toBe(1));
  expect(notice()).toBeNull();
});

test('불러오기에 실패해도 화면은 그대로, 문구만 없다', async () => {
  fakeState.error = 'boom';
  start();
  await screen.findByRole('heading', { level: 1, name: '챔피언 선택' });
  await waitFor(() => expect(asked()).toBe(1));
  expect(notice()).toBeNull();
  await waitFor(() => expect(document.querySelector('.champ-grid')).not.toBeNull());
});

test('줄을 받지 않고 개수만 센다 + 10분 캐시 (홈을 다시 열어도 다시 묻지 않음)', async () => {
  const first = start();
  await waitFor(() => expect(notice()).not.toBeNull());
  expect(asked()).toBe(1);
  first.unmount();
  start();
  await waitFor(() => expect(notice()).not.toBeNull());
  expect(asked()).toBe(1);
  expect(BUILD_COUNT_TTL_MS).toBe(10 * 60 * 1000);
});

test('빌드가 늘면 새로 센 숫자로 (캐시 비움 뒤)', async () => {
  const first = start();
  await waitFor(() => expect(spoken()).toContain('4개'));
  first.unmount();
  TABLES.builds.push(fakeBuild(110, null, {}));
  invalidateBuildCount();
  start();
  await waitFor(() => expect(spoken()).toContain('5개'));
});

// ---- 6-78 디자인: 제목 옆 알약 배지, 숫자 올라가기, 접근성 ----
function fakeFrames() {
  let now = 0;
  const queue = [];
  vi.spyOn(performance, 'now').mockImplementation(() => now);
  vi.spyOn(window, 'requestAnimationFrame').mockImplementation((cb) => { queue.push(cb); return queue.length; });
  vi.spyOn(window, 'cancelAnimationFrame').mockImplementation(() => {});
  return (ms) => { now += ms; const run = queue.splice(0); act(() => run.forEach((cb) => cb(now))); };
}

test('배지는 "챔피언 선택" 제목과 같은 줄 묶음 안에 있고 아래쪽 문장은 없다', async () => {
  start();
  await waitFor(() => expect(notice()).not.toBeNull());
  const row = document.querySelector('.home-title-row');
  expect(row.querySelector('h1').textContent).toBe('챔피언 선택');
  expect(row.contains(notice())).toBe(true);
  expect(document.querySelectorAll('.build-count')).toHaveLength(1);
  expect(visible().textContent).toMatch(/^지금까지 [\d,]+개의 빌드$/);
});

test('스크린리더: 최종 숫자 문장 하나만, 보이는 부분(올라가는 숫자)은 숨김, aria-live 없음', async () => {
  start();
  await waitFor(() => expect(notice()).not.toBeNull());
  expect(visible().getAttribute('aria-hidden')).toBe('true');
  expect(notice().querySelector('[aria-live], [role="status"]')).toBeNull();
  expect(spoken()).toBe('지금까지 4개의 빌드가 등록되었습니다.');
});

test('숫자는 0에서 최종 값까지 올라가 멈춘다 (천 단위 쉼표), 읽어 주는 문장은 처음부터 최종 값', async () => {
  const step = fakeFrames();
  TABLES.builds = Array.from({ length: 1284 }, (_, i) => fakeBuild(1000 + i, null, {}));
  start();
  await waitFor(() => expect(notice()).not.toBeNull());
  const num = () => notice().querySelector('.build-count-num').textContent;
  expect(num()).toBe('0');
  expect(spoken()).toBe('지금까지 1,284개의 빌드가 등록되었습니다.');
  step(600);
  const mid = Number(num().replace(/,/g, ''));
  expect(mid).toBeGreaterThan(642); // ease-out: 절반 시간에 절반보다 많이
  expect(mid).toBeLessThan(1284);
  step(700);
  expect(num()).toBe('1,284');
  step(500);
  expect(num()).toBe('1,284');
});

test('같은 방문에서 홈으로 다시 오면 효과 없이 바로 최종 숫자', async () => {
  const step = fakeFrames();
  const first = start();
  await waitFor(() => expect(notice()).not.toBeNull());
  step(1300);
  first.unmount();
  start();
  await waitFor(() => expect(notice()).not.toBeNull());
  expect(notice().querySelector('.build-count-num').textContent).toBe('4');
});

test('"움직임 줄이기"면 올라가는 효과 없이 숫자만', async () => {
  window.matchMedia = vi.fn().mockImplementation((q) => ({ matches: q.includes('reduce'), addEventListener() {}, removeEventListener() {} }));
  const raf = vi.spyOn(window, 'requestAnimationFrame');
  start();
  await waitFor(() => expect(notice()).not.toBeNull());
  expect(notice().querySelector('.build-count-num').textContent).toBe('4');
  expect(raf).not.toHaveBeenCalled();
});
