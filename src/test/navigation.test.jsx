import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
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
  await act(async () => { start('/'); }); // 1-B2: 홈의 장인 줄도 처음에 요청을 보내므로, 그 응답까지 act 안에서 받는다
  const darius = await screen.findByText('다리우스');
  await waitFor(() => expect(document.querySelector('.home-inf')).toBeNull()); // 1-B2: 홈의 장인 줄 불러오기가 끝난 뒤에 이동 (장인이 없으면 줄이 사라짐)
  fireEvent.click(darius);
  expect(await screen.findByText(/다리우스 상대법/)).toBeDefined();
  expect(screen.getByText(RIOT_NOTICE)).toBeDefined();

  fireEvent.click(screen.getByText('퀸'));
  expect(await screen.findByText(/퀸으로 다리우스 이기는 법/)).toBeDefined();
  expect(await screen.findByRole('tab', { name: '빌드 2 추천 5' })).toBeDefined();
  expect(screen.getByText(RIOT_NOTICE)).toBeDefined();

  fireEvent.click(screen.getByRole('link', { name: '다리우스' }));
  expect(await screen.findByText(/다리우스 상대법/)).toBeDefined();
  await act(async () => { fireEvent.click(screen.getByRole('link', { name: '홈' })); }); // 1-B2: 돌아온 홈의 장인 줄 응답도 act 안에서
  expect(await screen.findByRole('combobox')).toBeDefined();
  await waitFor(() => expect(document.querySelector('.home-inf')).toBeNull()); // 1-B2: 홈의 장인 줄 불러오기가 끝난 뒤에 확인 (장인이 없으면 줄이 사라짐)
  expect(console.error).not.toHaveBeenCalled();
});

test('이동 직후 데이터가 오기 전에는 로딩 문구가 보인다', async () => {
  start('/');
  fireEvent.click(await screen.findByText('다리우스'));
  expect(screen.getByText('불러오는 중…')).toBeDefined();
  await screen.findByText(/다리우스 상대법/);
});

test('예시 데이터는 다리우스 상대 퀸 하나뿐이다', async () => {
  start('/champion/Darius');
  await screen.findByText(/다리우스 상대법/);
  const rows = document.querySelectorAll('.counter-row');
  expect([...rows].map((r) => r.querySelector('strong').textContent)).toEqual(['퀸']);
});

test.each(['Garen', 'Vayne', 'Teemo'])('예시가 없는 챔피언(%s)은 초대 문구 "아직 비어 있습니다. 첫 기여자가 되어 주세요."가 보인다', async (id) => {
  start(`/champion/${id}`);
  expect(await screen.findByText('아직 비어 있습니다. 첫 기여자가 되어 주세요.')).toBeDefined();
  expect(document.querySelectorAll('.counter-row')).toHaveLength(0);
});
