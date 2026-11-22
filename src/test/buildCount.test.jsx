// 첫 화면 "등록된 빌드 수" (SPEC 6-78)
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import { BUILD_COUNT_TTL_MS, invalidateBuildCount } from '../api/buildCount';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeBuild, fakeLogin, fakeState } from './fakeSupabase';

beforeEach(() => {
  invalidateBuildCount();
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); vi.useRealTimers(); });

const start = () => render(<MemoryRouter initialEntries={['/']}><AppRoutes /></MemoryRouter>);
const asked = () => fakeState.queryLog.filter((q) => q.table === 'builds' && q.select === 'id').length;
const notice = () => document.querySelector('.build-count');

test('비로그인(게스트)도 공개된 빌드 수를 본다 (승인 대기 1개는 제외)', async () => {
  start();
  await waitFor(() => expect(notice()).not.toBeNull());
  expect(notice().textContent).toBe('지금까지 4개의 빌드가 등록되었습니다.');
});

test('내가 차단한 사람의 빌드도 센다 (전체 기준)', async () => {
  fakeLogin('u-me', { nickname: '나', role: 'member', level: 1, main_title: null });
  TABLES.user_blocks.push({ blocker_id: 'u-me', blocked_id: 'u-102' });
  start();
  await waitFor(() => expect(notice()).not.toBeNull());
  expect(notice().textContent).toContain('4개');
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
  await waitFor(() => expect(notice()?.textContent).toContain('4개'));
  first.unmount();
  TABLES.builds.push(fakeBuild(110, null, {}));
  invalidateBuildCount();
  start();
  await waitFor(() => expect(notice()?.textContent).toContain('5개'));
});
