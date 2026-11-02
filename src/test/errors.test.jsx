import { afterEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import Layout, { RIOT_NOTICE } from '../components/Layout';
import { fakeFetch } from './fakeDdragon';

afterEach(() => { cleanup(); vi.restoreAllMocks(); vi.useRealTimers(); });

// 게임 데이터 캐시가 테스트끼리 섞이지 않게 매번 새로 불러온다
async function freshApp() {
  vi.resetModules();
  return (await import('../App')).AppRoutes;
}

test('게임 데이터를 못 불러오면 오류 문구가 보이고, 다시 시도하면 회복된다', async () => {
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
  const fetchMock = vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch({ fail: true }));
  const AppRoutes = await freshApp();
  render(<MemoryRouter initialEntries={['/champion/Darius']}><AppRoutes /></MemoryRouter>);
  expect(await screen.findByText(/데이터를 불러오지 못했어요/)).toBeDefined();
  expect(screen.getByText(/인터넷 연결을 확인/)).toBeDefined();
  expect(screen.getByText(RIOT_NOTICE)).toBeDefined();

  fetchMock.mockImplementation(fakeFetch());
  fireEvent.click(screen.getByRole('button', { name: '다시 시도' }));
  expect(await screen.findByText(/다리우스를 이기는 챔피언/)).toBeDefined();
});

test('응답이 없으면 로딩 문구를 보여주다가 시간 초과 오류로 바뀐다', async () => {
  vi.useFakeTimers({ shouldAdvanceTime: true });
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
  vi.spyOn(globalThis, 'fetch').mockImplementation((url, { signal }) =>
    new Promise((_, reject) => signal.addEventListener('abort', () => reject(Object.assign(new Error('aborted'), { name: 'AbortError' })))));
  const AppRoutes = await freshApp();
  render(<MemoryRouter initialEntries={['/']}><AppRoutes /></MemoryRouter>);
  expect(screen.getByText('불러오는 중…')).toBeDefined();
  await vi.advanceTimersByTimeAsync(16000);
  expect(await screen.findByText(/응답이 너무 늦어요/)).toBeDefined();
});

test('화면 그리기 중 오류가 나도 빈 화면 대신 안내가 보이고 고지 문구는 남는다', () => {
  vi.spyOn(console, 'error').mockImplementation(() => {});
  const swallow = (e) => e.preventDefault(); // jsdom이 의도된 오류를 콘솔에 찍지 않게
  window.addEventListener('error', swallow);
  function Broken() { throw new Error('테스트 오류'); }
  render(
    <MemoryRouter>
      <Routes><Route element={<Layout />}><Route index element={<Broken />} /></Route></Routes>
    </MemoryRouter>,
  );
  expect(screen.getByText('화면을 표시하는 중에 문제가 생겼어요.')).toBeDefined();
  expect(screen.getByText('테스트 오류')).toBeDefined();
  expect(screen.getByText(RIOT_NOTICE)).toBeDefined();
  window.removeEventListener('error', swallow);
});
