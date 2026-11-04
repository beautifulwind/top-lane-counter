// 028: 핵심 템트리 종류(전설·서사·신발, 전설 1개 이상), 서사 태그, 아이템 고르기 "자주 쓰는 아이템" + [더보기], 운영자 관리
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeLogin, fakeState } from './fakeSupabase';
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
const asOperator = () => fakeLogin('u-op', { nickname: '영자(운)', role: 'admin', level: 0, main_title: null });
const names = (group) => within(group).getAllByRole('button').map((b) => b.getAttribute('aria-label'));
const freq = (slot, ...ids) => ids.forEach((id, i) => TABLES.frequent_items.push({ slot, item_id: id, created_at: `2026-11-04T00:00:0${i}Z` }));

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

test('핵심 템트리: 처음에는 자주 쓰는 아이템만, [더보기]를 누르면 나머지 + [전체][전설][서사][신발] 거르기', async () => {
  asUser();
  freq('core', '3071', '3076');
  start(NEW_BUILD);
  const common = await screen.findByRole('group', { name: '핵심 템트리 고르기' });
  expect(names(common)).toEqual(['칠흑의 양날 도끼', '덤불 조끼 (서사)']); // 비싼 순, 서사는 태그
  expect(within(common).getByText('서사')).toBeDefined();
  expect(screen.queryByRole('group', { name: '핵심 템트리 더보기' })).toBeNull();
  expect(screen.queryByRole('group', { name: '핵심 템트리 종류' })).toBeNull(); // 거르기는 더보기 안에

  const more = screen.getByRole('button', { name: /^더보기/ });
  expect(more.getAttribute('aria-expanded')).toBe('false');
  fireEvent.click(more);
  expect(more.getAttribute('aria-expanded')).toBe('true');
  const rest = screen.getByRole('group', { name: '핵심 템트리 더보기' });
  expect(names(rest)).not.toContain('칠흑의 양날 도끼'); // 자주 쓰는 것은 빼고
  expect(names(rest)).toContain('탐식의 망치 (서사)');
  // 기본템·소모품은 핵심 템트리에 없다
  for (const n of ['롱소드', '도란의 검', '체력 물약', '천 갑옷']) expect(names(rest)).not.toContain(n);

  const kinds = screen.getByRole('group', { name: '핵심 템트리 종류' });
  fireEvent.click(within(kinds).getByRole('button', { name: '서사' }));
  expect(names(screen.getByRole('group', { name: '핵심 템트리 더보기' }))).toEqual(['탐식의 망치 (서사)']);
  fireEvent.click(within(kinds).getByRole('button', { name: '신발' }));
  expect(names(screen.getByRole('group', { name: '핵심 템트리 더보기' }))).toEqual(['강철판 장화', '광전사의 군화', '장화']);
  fireEvent.click(screen.getByRole('button', { name: '접기' }));
  expect(screen.queryByRole('group', { name: '핵심 템트리 더보기' })).toBeNull();
});

test('핵심 템트리 검색: 자주 쓰는 것·더보기 구분 없이 전체에서 (초성 포함), 결과에도 서사 태그', async () => {
  asUser();
  freq('core', '3071');
  start(NEW_BUILD);
  await screen.findByRole('group', { name: '핵심 템트리 고르기' });
  fireEvent.change(screen.getByLabelText('핵심 템트리 검색'), { target: { value: 'ㄷㅂㅈㄲ' } });
  expect(names(screen.getByRole('group', { name: '핵심 템트리 고르기' }))).toEqual(['덤불 조끼 (서사)']);
  expect(screen.queryByRole('button', { name: /^더보기/ })).toBeNull();
  fireEvent.change(screen.getByLabelText('핵심 템트리 검색'), { target: { value: '롱소드' } });
  expect(screen.getByText('찾는 아이템이 없습니다.')).toBeDefined(); // 기본템은 검색해도 없음
});

test('자주 쓰는 아이템이 없으면 [더보기]가 펼쳐진 채로 시작한다', async () => {
  asUser();
  start(NEW_BUILD);
  const all = await screen.findByRole('group', { name: '핵심 템트리 고르기' });
  expect(names(all)).toContain('덤불 조끼 (서사)');
  expect(screen.getByRole('group', { name: '핵심 템트리 종류' })).toBeDefined();
  expect(screen.queryByText('자주 쓰는 아이템')).toBeNull();
});

test('시작 아이템도 같은 방식: 자주 쓰는 시작템(싼 순) 먼저, 나머지는 [더보기] (거르기 없음)', async () => {
  asUser();
  freq('starting', '1055', '2003');
  start(NEW_BUILD);
  const common = await screen.findByRole('group', { name: '시작 아이템 고르기' });
  expect(names(common)).toEqual(['체력 물약', '도란의 검']);
  fireEvent.click(within(common.closest('fieldset')).getByRole('button', { name: /^더보기/ }));
  const rest = screen.getByRole('group', { name: '시작 아이템 더보기' });
  expect(names(rest)).toContain('도란의 방패');
  expect(names(rest)).toContain('롱소드'); // 기본템은 시작 아이템에는 남아 있다
  expect(screen.queryByRole('group', { name: '시작 아이템 종류' })).toBeNull();
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

// ---------------- 운영자 ----------------

test('운영자 /admin "자주 쓰는 아이템": 칸별로 보라 [추가]·[빼기], 핵심에는 전설·서사·신발만 검색된다', async () => {
  asOperator();
  freq('core', '3071');
  start('/admin');
  const sec = (await screen.findByRole('heading', { name: '자주 쓰는 아이템' })).closest('section');
  const list = await within(sec).findByRole('list', { name: '자주 쓰는 핵심 템트리' });
  expect(within(list).getByText('칠흑의 양날 도끼')).toBeDefined();
  const search = within(sec).getByLabelText('자주 쓰는 핵심 템트리에 추가할 아이템 검색');
  fireEvent.change(search, { target: { value: '롱소드' } });
  expect(within(sec).getByText('넣을 수 있는 아이템 중에 찾는 것이 없습니다.')).toBeDefined();
  fireEvent.change(search, { target: { value: 'ㄷㅂ' } });
  const add = within(sec).getByRole('button', { name: '덤불 조끼 추가' });
  expect(add.className).toMatch(/btn-op/);
  fireEvent.click(add);
  expect(await within(sec).findByText('자주 쓰는 핵심 템트리에 넣었습니다: 덤불 조끼')).toBeDefined();
  expect(fakeState.rpcCalls.filter((c) => c.name === 'add_frequent_item').map((c) => c.args)).toEqual([{ p_slot: 'core', p_item: '3076' }]);
  const remove = await within(sec).findByRole('button', { name: '칠흑의 양날 도끼 빼기' });
  expect(remove.className).toMatch(/btn-op/);
  fireEvent.click(remove);
  expect(await within(sec).findByText('자주 쓰는 핵심 템트리에서 뺐습니다: 칠흑의 양날 도끼')).toBeDefined();
  expect(TABLES.frequent_items.map((f) => f.item_id)).toEqual(['3076']);

  // 시작 아이템 칸: 500골드 이하만
  fireEvent.click(within(sec).getByRole('button', { name: /^시작 아이템/ }));
  expect(within(sec).getByText('자주 쓰는 아이템이 아직 없습니다. 아래에서 검색해 넣어 주세요.')).toBeDefined();
  const s2 = within(sec).getByLabelText('자주 쓰는 시작 아이템에 추가할 아이템 검색');
  fireEvent.change(s2, { target: { value: '칠흑' } });
  expect(within(sec).queryByRole('button', { name: '칠흑의 양날 도끼 추가' })).toBeNull();
  fireEvent.change(s2, { target: { value: '도란' } });
  expect(within(sec).getByRole('button', { name: '도란의 검 추가' })).toBeDefined();
});
