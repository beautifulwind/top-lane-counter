import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { fakeLogin, fakeState } from './fakeSupabase';
import { openMenu } from './menu';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); window.history.replaceState(null, '', '/'); });

/** 구글/카카오 → Supabase를 거쳐 브라우저 주소가 `query`로 돌아온 상황 */
function returnFromGoogle(query, path = '/login') {
  window.history.replaceState(null, '', path + query);
  return render(<MemoryRouter initialEntries={[path]}><AppRoutes /></MemoryRouter>);
}

test('[이번 원인] 키가 망가져 code 교환 요청을 못 보내면, 이유가 화면에 보이고 주소창의 code는 지워진다', async () => {
  fakeState.initError = { message: 'Cannot convert argument to a ByteString because the character at index 11 has a value of 54872' };
  returnFromGoogle('?code=abc&sb_flow_id=f1');
  const alert = await screen.findByText(/로그인하지 못했습니다/);
  expect(alert.closest('[role=alert]').textContent).toMatch(/Supabase 키 설정/);
  expect(screen.getByText(/상세: Cannot convert argument to a ByteString/)).toBeDefined();
  expect(window.location.search).toBe('');
});

test('code는 왔는데 이 브라우저에 로그인 시작 기록이 없으면(다른 주소·브라우저) 그렇게 안내한다', async () => {
  returnFromGoogle('?code=abc');
  expect(await screen.findByText(/시작한 곳과 돌아온 곳이 다릅니다/)).toBeDefined();
});

test('만료되거나 이미 쓴 code면 다시 로그인하라고 안내한다', async () => {
  fakeState.initError = { message: 'invalid flow state, no valid flow state found' };
  returnFromGoogle('?code=abc&sb_flow_id=f1');
  expect(await screen.findByText(/만료됐거나 이미 사용됐습니다/)).toBeDefined();
});

test('구글·카카오 동의 화면에서 취소하면 취소 안내가 보인다', async () => {
  returnFromGoogle('?error=access_denied&error_description=The+user+denied+access');
  expect(await screen.findByText(/취소됐거나 거절됐습니다/)).toBeDefined();
  expect(screen.getByText(/상세: The user denied access/)).toBeDefined();
});

test('[닫기]를 누르면 안내가 사라지고, [다시 로그인]은 로그인 버튼으로 간다', async () => {
  returnFromGoogle('?code=abc', '/champion/Darius');
  await screen.findByText(/로그인하지 못했습니다/);
  fireEvent.click(screen.getByRole('button', { name: '닫기' }));
  expect(screen.queryByText(/로그인하지 못했습니다/)).toBeNull();
});

test('code 교환이 성공하면 안내 없이 로그인되고 주소창도 깨끗해진다', async () => {
  fakeLogin('u-old');
  returnFromGoogle('?code=abc&sb_flow_id=f1', '/');
  expect((await openMenu()).getByRole('button', { name: '로그아웃' })).toBeDefined();
  expect(screen.queryByText(/로그인하지 못했습니다/)).toBeNull();
  expect(window.location.search).toBe('');
});

test('로그인 콜백이 아닌 평소 접속에서는 안내가 뜨지 않는다', async () => {
  fakeState.initError = { message: '아무 오류' };
  returnFromGoogle('', '/');
  expect((await openMenu()).getByRole('link', { name: '로그인 · 가입' })).toBeDefined();
  expect(screen.queryByText(/로그인하지 못했습니다/)).toBeNull();
});

test('Supabase 키 검사: 이번처럼 키 앞에 다른 글자가 붙으면 바로 잡는다', async () => {
  const { configProblem } = await vi.importActual('../api/supabase');
  const url = 'https://tfcfhaddoorirvornrrq.supabase.co';
  expect(configProblem(url, 'sb_publishable_qEbav1dAWOqMOCP22ddHAA_GOcsga6d')).toBeNull();
  expect(configProblem(url, 'Cloudflare 환경변수 넣었어. 다시 배포되게 푸시해줘.sb_publishable_qEbav1d')).toMatch(/KEY 값이 이상합니다/);
  expect(configProblem(url, ' sb_publishable_abc')).toMatch(/KEY 값이 이상합니다/);
  expect(configProblem(url, '')).toMatch(/설정이 없습니다/);
  expect(configProblem('tfcfhaddoorirvornrrq.supabase.co', 'sb_publishable_abc')).toMatch(/URL 값이 이상합니다/);
});
