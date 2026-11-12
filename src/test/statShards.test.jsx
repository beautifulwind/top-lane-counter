// 능력치 파편 아이콘: 체력(5011)과 성장 체력(5001)의 아이콘 파일은 이름과 거꾸로다 (게임 클라이언트 perks.json 기준).
// 5011 체력 = StatModsHealthScalingIcon(그냥 하트), 5001 성장 체력 = StatModsHealthPlusIcon(화살표 하트)
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, render, screen, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { fakeLogin } from './fakeSupabase';
import { SHARD_ROWS, STAT_SHARDS, getRunes } from '../api/ddragon';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /></MemoryRouter>);
const HEALTH = /\/StatModsHealthScalingIcon\.png$/;
const HEALTH_SCALING = /\/StatModsHealthPlusIcon\.png$/;

test('파편 정의: 5011 체력은 ScalingIcon, 5001 성장 체력은 PlusIcon, 표는 3×3 그대로', async () => {
  expect(STAT_SHARDS[5011].name).toBe('체력');
  expect(STAT_SHARDS[5011].icon).toMatch(HEALTH);
  expect(STAT_SHARDS[5001].name).toBe('성장 체력');
  expect(STAT_SHARDS[5001].icon).toMatch(HEALTH_SCALING);
  expect(SHARD_ROWS).toEqual([[5008, 5005, 5007], [5008, 5010, 5001], [5011, 5013, 5001]]);
  // 빌드 작성 화면과 빌드 카드는 모두 getRunes().shards = 이 정의 하나를 쓴다
  expect((await getRunes()).shards).toBe(STAT_SHARDS);
});

test('빌드 작성 화면: 방어 줄 체력·성장 체력 버튼의 아이콘, 고르지 않은 칸은 흐린 .pick', async () => {
  fakeLogin('u-old');
  start('/champion/Darius/counter/Quinn/build/new');
  const row = await screen.findByRole('group', { name: '능력치 파편 방어' });
  const health = within(row).getByRole('button', { name: '방어 체력' });
  const scaling = within(row).getByRole('button', { name: '방어 성장 체력' });
  expect(health.querySelector('img').getAttribute('src')).toMatch(HEALTH);
  expect(scaling.querySelector('img').getAttribute('src')).toMatch(HEALTH_SCALING);
  const flex = screen.getByRole('group', { name: '능력치 파편 유연' });
  expect(within(flex).getByRole('button', { name: '유연 성장 체력' }).querySelector('img').getAttribute('src')).toMatch(HEALTH_SCALING);
  expect(scaling.className).toBe('pick'); // 고르지 않으면 'pick'(흐림), 고르면 'pick on'
});

test('빌드 카드: 체력 파편 아이콘은 ScalingIcon', async () => {
  start('/champion/Darius/counter/Quinn');
  const card = (await screen.findAllByRole('article', { name: /^빌드: / }))[0];
  expect(within(card).getByRole('img', { name: '체력' }).getAttribute('src')).toMatch(HEALTH);
});
