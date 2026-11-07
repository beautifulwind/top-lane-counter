// 028: 핵심 템트리 종류(전설·서사·신발, 전설 1개 이상), 서사 태그, 아이템 고르기 전체 목록 + 종류 거르기 + 검색
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { fakeLogin } from './fakeSupabase';
import { coreItemProblem } from '../lib/buildContent';
import { isCoreItem, itemKind } from '../lib/itemKinds';
import { getItems } from '../api/ddragon';
import { fillBuild, pick } from './buildHelpers';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /></MemoryRouter>);
const NEW_BUILD = '/champion/Darius/counter/Quinn/build/new';
const asUser = () => fakeLogin('u-old');
const names = (group) => within(group).getAllByRole('button').map((b) => b.getAttribute('aria-label'));

// ---------------- 종류 ----------------

test('종류: 협곡 상점 아이템으로 이어지면 서사 (다른 모드 아이템은 무시), 신발로 만드는 것은 신발, 서포터템 따로', () => {
  const data = {
    1029: { from: [], into: ['3076'] },
    3076: { from: ['1029'], into: ['323075', '3075'] },
    3075: { from: ['3076'] },
    3077: { from: ['1036'], into: ['223077'] }, // 협곡에 없는 아이템으로만 이어짐 → 전설
    3006: { tags: ['Boots'], from: ['1001'] },
    3172: { tags: ['AttackSpeed'], from: ['3006'] }, // 건메탈 군화: Boots 표시 없음
    3869: { tags: ['GoldPer'], from: ['3867'] },
    2003: { tags: ['Consumable'], consumed: true },
    3340: { tags: ['Trinket'] },
  };
  const shop = new Set(['1029', '3076', '3075', '3077', '3006', '3172', '3869', '2003', '3340']);
  const kind = (id) => itemKind(data[id], data, shop);
  expect(['1029', '3076', '3075', '3077', '3006', '3172', '3869', '2003', '3340'].map(kind))
    .toEqual(['basic', 'epic', 'legendary', 'legendary', 'boots', 'boots', 'support', 'consumable', 'trinket']);
});

test('규칙: 핵심 템트리는 지금 상점의 전설·서사·신발만, 전설 1개 이상', async () => {
  const items = await getItems();
  expect(isCoreItem(items['3076'])).toBe(true);
  expect(isCoreItem(items['1036'])).toBe(false); // 기본템 (롱소드)
  expect(coreItemProblem(['3076', '3075', '3047'], items)).toBeNull();
  expect(coreItemProblem(['3076', '3044', '3047'], items)).toBe('핵심 템트리에 전설 아이템을 1개 이상 넣어 주세요.');
  expect(coreItemProblem(['2003', '3075', '3047'], items)).toBe('핵심 템트리에 넣을 수 없는 아이템이 있습니다: 체력 물약 (전설·서사·신발만)');
  expect(coreItemProblem(['3400', '3075', '3047'], items)).toMatch(/넣을 수 없는 아이템/); // 상점에서 못 사는 아이템
});

// ---------------- 고르기 목록 ----------------

test('핵심 템트리: 전체 목록에 전설·서사·신발만, [전체][전설][서사][신발] 거르기', async () => {
  asUser();
  start(NEW_BUILD);
  const all = await screen.findByRole('group', { name: '핵심 템트리 고르기' });
  expect(screen.queryByRole('button', { name: /^더보기/ })).toBeNull();
  expect(screen.queryByText('자주 쓰는 아이템')).toBeNull();
  expect(names(all)).toContain('칠흑의 양날 도끼');
  expect(names(all)).toContain('탐식의 망치 (서사)');
  // 기본템·소모품은 핵심 템트리에 없다
  for (const n of ['롱소드', '도란의 검', '체력 물약', '천 갑옷']) expect(names(all)).not.toContain(n);

  const kinds = screen.getByRole('group', { name: '핵심 템트리 종류' });
  expect(within(kinds).getAllByRole('button').map((b) => b.textContent)).toEqual(['전체', '전설', '서사', '신발']);
  fireEvent.click(within(kinds).getByRole('button', { name: '서사' }));
  expect(names(screen.getByRole('group', { name: '핵심 템트리 고르기' }))).toEqual(['탐식의 망치 (서사)', '덤불 조끼 (서사)']);
  fireEvent.click(within(kinds).getByRole('button', { name: '신발' }));
  expect(names(screen.getByRole('group', { name: '핵심 템트리 고르기' }))).toEqual(['강철판 장화', '광전사의 군화', '장화']);
});

test('핵심 템트리 검색: 전체에서 (초성 포함), 결과에도 서사 태그', async () => {
  asUser();
  start(NEW_BUILD);
  await screen.findByRole('group', { name: '핵심 템트리 고르기' });
  fireEvent.change(screen.getByLabelText('핵심 템트리 검색'), { target: { value: 'ㄷㅂㅈㄲ' } });
  expect(names(screen.getByRole('group', { name: '핵심 템트리 고르기' }))).toEqual(['덤불 조끼 (서사)']);
  fireEvent.change(screen.getByLabelText('핵심 템트리 검색'), { target: { value: '롱소드' } });
  expect(screen.getByText('찾는 아이템이 없습니다.')).toBeDefined(); // 기본템은 검색해도 없음
});

test('시작 아이템: 전체 목록(싼 순) + [전체][기본][소모품] 거르기', async () => {
  asUser();
  start(NEW_BUILD);
  const all = await screen.findByRole('group', { name: '시작 아이템 고르기' });
  expect(names(all)).toContain('체력 물약');
  expect(names(all)).toContain('롱소드');
  const kinds = screen.getByRole('group', { name: '시작 아이템 종류' });
  expect(within(kinds).getAllByRole('button').map((b) => b.textContent)).toEqual(['전체', '기본', '소모품']);
  fireEvent.click(within(kinds).getByRole('button', { name: '소모품' }));
  const consumables = names(screen.getByRole('group', { name: '시작 아이템 고르기' }));
  expect(consumables).toContain('체력 물약');
  expect(consumables).not.toContain('롱소드');
});

test('빌드 입력: 서사템에 "서사" 태그, 전설이 없으면 "전설 1개 이상" 안내', async () => {
  asUser();
  start(NEW_BUILD);
  await screen.findByRole('group', { name: '핵심 템트리 고르기' });
  fillBuild({ withSkill: true });
  for (const n of ['스테락의 도전', '선혈포식자']) fireEvent.click(screen.getByRole('button', { name: `${n} 빼기` }));
  pick('핵심 템트리 고르기', '덤불 조끼 (서사)');
  pick('핵심 템트리 고르기', '탐식의 망치 (서사)');
  expect(screen.getByText('아직 고를 것: 핵심 템트리에 전설 아이템을 1개 이상 넣어 주세요.')).toBeDefined();
  expect(screen.getByRole('button', { name: '빌드 보내기' })).toBeDisabled();
  const picked = screen.getByRole('list', { name: '고른 핵심 템트리' });
  expect(within(picked).getAllByText('서사')).toHaveLength(2);
  pick('핵심 템트리 고르기', '선혈포식자');
  expect(screen.queryByText(/전설 아이템을 1개 이상/)).toBeNull();
  const preview = screen.getByRole('article', { name: '빌드: 기존유저' });
  expect(within(preview).getByRole('img', { name: '덤불 조끼 (서사)' })).toBeDefined();
  expect(within(preview).getAllByText('서사')).toHaveLength(2);
});
