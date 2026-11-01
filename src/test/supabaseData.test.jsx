import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, render, screen } from '@testing-library/react';
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

test('닉네임 표시: 대표 칭호가 있으면 "Lv.7 수석 연구원 · 탑신병자"', () => {
  const { container } = render(<UserName profile={{ nickname: '탑신병자', level: 7, main_title: 'senior_researcher' }} />);
  expect(container.textContent).toBe('Lv.7 수석 연구원 · 탑신병자');
});

test('닉네임 표시: 대표 칭호가 없으면 칭호 자리 없이 "Lv.3 닉네임"', () => {
  const { container } = render(<UserName profile={{ nickname: '닉네임', level: 3, main_title: null }} />);
  expect(container.textContent).toBe('Lv.3 닉네임');
  expect(container.querySelector('.user-title')).toBeNull();
});

test('매치업 빌드: 승인된 것만, 따봉 점수 높은 순, 작성자는 레벨·칭호와 함께', async () => {
  start('/champion/Darius/counter/Quinn');
  await screen.findByText(/퀸\(으\)로 다리우스 잡는 법/);
  const authors = [...document.querySelectorAll('.build-author')].map((e) => e.textContent);
  expect(authors).toEqual(['Lv.7 수석 연구원 · 탑신병자', 'Lv.3 칭호없음', '예시 빌드']);
  expect(screen.queryByText(/대기중/)).toBeNull();
  expect(screen.queryByText(/대표 칭호 없음/)).toBeNull();
  expect(screen.getByText('구버전 · 14.1.1')).toBeDefined();
  expect(screen.getByText('최근 수정: 2026-11-01')).toBeDefined();
  expect(screen.getByText('4렙 추가')).toBeDefined();
});

test('승인 안 된 카운터는 매치업 문서가 열리지 않는다', async () => {
  start('/champion/Darius/counter/Vayne');
  expect(await screen.findByText(/아직 등록되지 않은 카운터예요/)).toBeDefined();
});

test('Supabase 오류가 나면 빈 화면 대신 오류 문구가 보인다', async () => {
  fakeState.error = 'connection refused';
  start('/champion/Darius');
  const alert = await screen.findByRole('alert');
  expect(alert.textContent).toContain('데이터를 불러오지 못했어요');
  expect(alert.textContent).toContain('connection refused');
});
