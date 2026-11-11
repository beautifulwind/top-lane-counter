// 카운터가 하나도 없는 챔피언 페이지: 초대 문구 + [+ 카운터 등록] (로그인 전에는 로그인 안내)
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeLogin } from './fakeSupabase';

const SAVED = [...TABLES.counters];

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); TABLES.counters = [...SAVED]; });

const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /></MemoryRouter>);

test('카운터가 없고 로그인함: 초대 문구와 [+ 카운터 등록] 하나', async () => {
  fakeLogin('u-old');
  TABLES.counters = [];
  start('/champion/Darius');
  expect(await screen.findByText('아직 비어 있습니다. 첫 기여자가 되어 주세요.')).toBeDefined();
  expect(screen.getByText(/를 이기는 챔피언과 공략을 등록해 주세요\. 등록하면 바로 공개됩니다\./)).toBeDefined();
  const links = screen.getAllByRole('link', { name: '+ 카운터 등록' });
  expect(links).toHaveLength(1);
  expect(links[0].getAttribute('href')).toBe('/matchup/new?target=Darius');
  expect(screen.queryByText('카운터를 등록하려면 로그인해 주세요.')).toBeNull();
});

test('카운터가 없고 로그인 전: 로그인 안내와 [로그인하고 카운터 등록]', async () => {
  TABLES.counters = [];
  start('/champion/Darius');
  expect(await screen.findByText('아직 비어 있습니다. 첫 기여자가 되어 주세요.')).toBeDefined();
  expect(screen.getByText('카운터를 등록하려면 로그인해 주세요.')).toBeDefined();
  expect(screen.getByRole('link', { name: '로그인하고 카운터 등록' }).getAttribute('href')).toBe('/login');
  expect(screen.queryByRole('link', { name: '+ 카운터 등록' })).toBeNull();
});

test('카운터가 있으면 초대 문구는 없고 맨 아래 [+ 카운터 등록]만 있다', async () => {
  start('/champion/Darius');
  expect(await screen.findByRole('link', { name: '+ 카운터 등록' })).toBeDefined();
  expect(screen.queryByText('아직 비어 있습니다. 첫 기여자가 되어 주세요.')).toBeNull();
});
