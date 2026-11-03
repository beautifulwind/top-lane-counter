import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { StrictMode } from 'react';
import { AppRoutes } from '../App';
import { RIOT_NOTICE } from '../components/Layout';
import { fakeFetch } from './fakeDdragon';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  // 최신 브라우저처럼 scrollTo가 Promise를 돌려주게 해서, cleanup 오용을 잡아낸다
  vi.spyOn(window, 'scrollTo').mockImplementation(() => Promise.resolve());
  vi.spyOn(console, 'error');
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

const start = (path = '/') =>
  render(<StrictMode><MemoryRouter initialEntries={[path]}><AppRoutes /></MemoryRouter></StrictMode>);

test('홈 → 챔피언 문서 → 매치업 문서를 클릭으로 이동해도 화면이 비지 않는다', async () => {
  start('/');
  fireEvent.click(await screen.findByText('다리우스'));
  expect(await screen.findByText(/다리우스 카운터/)).toBeDefined();
  expect(screen.getByText(RIOT_NOTICE)).toBeDefined();

  fireEvent.click(screen.getByText('퀸'));
  expect(await screen.findByText(/퀸으로 다리우스 잡는 법/)).toBeDefined();
  expect(await screen.findByText('(탈퇴한 유저)')).toBeDefined();
  expect(screen.getByText(RIOT_NOTICE)).toBeDefined();

  fireEvent.click(screen.getByRole('link', { name: '다리우스' }));
  expect(await screen.findByText(/다리우스 카운터/)).toBeDefined();
  fireEvent.click(screen.getByRole('link', { name: '홈' }));
  expect(await screen.findByRole('searchbox')).toBeDefined();
  expect(console.error).not.toHaveBeenCalled();
});

test('이동 직후 데이터가 오기 전에는 로딩 문구가 보인다', async () => {
  start('/');
  fireEvent.click(await screen.findByText('다리우스'));
  expect(screen.getByText('불러오는 중…')).toBeDefined();
  await screen.findByText(/다리우스 카운터/);
});

test('예시 데이터는 다리우스 상대 퀸 하나뿐이다', async () => {
  start('/champion/Darius');
  await screen.findByText(/다리우스 카운터/);
  const rows = document.querySelectorAll('.counter-row');
  expect([...rows].map((r) => r.querySelector('strong').textContent)).toEqual(['퀸']);
});

test.each(['Garen', 'Vayne', 'Teemo'])('예시가 없는 챔피언(%s)은 "아직 등록된 카운터가 없어요."가 보인다', async (id) => {
  start(`/champion/${id}`);
  expect(await screen.findByText("아직 등록된 카운터가 없어요.")).toBeDefined();
  expect(document.querySelectorAll('.counter-row')).toHaveLength(0);
});
