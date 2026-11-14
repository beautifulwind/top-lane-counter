import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import UserName from '../components/UserName';
import { fakeFetch } from './fakeDdragon';
import { fakeState } from './fakeSupabase';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /></MemoryRouter>);

test('닉네임 표시: 대표 칭호가 있으면 "Lv.7 단단묵직 탑고수"', () => {
  const { container } = render(<UserName profile={{ nickname: '탑고수', level: 7, main_title: 'solid_heavy' }} />);
  expect(container.textContent).toBe('Lv.7 단단묵직 탑고수');
});

test('닉네임 표시: 대표 칭호가 없으면 칭호 자리 없이 "Lv.3 닉네임"', () => {
  const { container } = render(<UserName profile={{ nickname: '닉네임', level: 3, main_title: null }} />);
  expect(container.textContent).toBe('Lv.3 닉네임');
  expect(container.querySelector('.user-title')).toBeNull();
});

test('상대법 빌드: 승인된 것만 탭으로, 추천 많은 순, 작성자는 레벨·칭호 없이 닉네임만 (046)', async () => {
  start('/champion/Darius/counter/Quinn');
  await screen.findByText(/퀸으로 다리우스 이기는 법/);
  expect(screen.getAllByRole('tab').map((t) => t.textContent)).toEqual(['빌드 2 추천 5', '빌드 3 추천 2', '빌드 1 추천 1', '빌드 5 추천 0']);
  expect(document.querySelector('.build-author').textContent).toBe('탑고수');
  expect(screen.queryByText(/대기중/)).toBeNull();
  expect(screen.queryByText(/대표 칭호 없음/)).toBeNull();
  expect(screen.getByText('패치 99.1')).toBeDefined(); // 앞 두 자리만 표시 (구버전 글자는 화면에 없다)
  expect(screen.getByText('4렙 추가')).toBeDefined();
  fireEvent.click(screen.getByRole('tab', { name: /^빌드 1/ }));
  expect(screen.getByText('패치 14.1')).toBeDefined();
  expect(document.querySelector('.build-panel .doc-sub').textContent).toBe('패치 14.1 · 최근 수정 2026-11-01');
  expect(screen.getByText('탈퇴한 이용자')).toBeDefined();
});

test('승인 안 된 카운터는 매치업 문서가 열리지 않는다', async () => {
  start('/champion/Darius/counter/Vayne');
  expect(await screen.findByText(/아직 등록되지 않은 상대법입니다/)).toBeDefined();
});

test('Supabase 오류가 나면 빈 화면 대신 오류 문구가 보인다', async () => {
  fakeState.error = 'connection refused';
  start('/champion/Darius');
  const alert = await screen.findByRole('alert');
  expect(alert.textContent).toContain('데이터를 불러오지 못했습니다');
  expect(alert.textContent).toContain('connection refused');
});
