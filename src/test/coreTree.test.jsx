// 056: 핵심 템트리 1~10칸, 같은 아이템 여러 번, 상점 아이템 전부. 안내는 "가야 하는 순서대로 적어 주세요."만.
// 시작 아이템(1~4개)·룬·주문은 그대로. 이미 저장된 빌드는 그대로 보인다.
import { readFileSync } from 'node:fs';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeBuild, fakeLogin, fakeState } from './fakeSupabase';
import { fillWikiBuild, pick } from './buildHelpers';
import { ITEM_LIMITS, buildProblem, buildToForm } from '../lib/buildContent';
import { buildDiff, lineDiff } from '../lib/diff';
import BuildCard from '../components/BuildCard';
import DiffView from '../components/DiffView';
import { getItems, getRunes } from '../api/ddragon';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /></MemoryRouter>);
const MATCHUP = '/champion/Darius/counter/Quinn';
const rpcCalls = (name) => fakeState.rpcCalls.filter((c) => c.name === name).map((c) => c.args);
const coreGroup = () => screen.getByRole('group', { name: '핵심 템트리 고르기' });
const pickedCore = () => screen.getByRole('list', { name: '고른 핵심 템트리' });
/** 빌드 카드의 "템트리" 줄에 보이는 아이콘 이름 (순서대로) */
const treeIcons = (root) => {
  const row = within(root).getByText('템트리').closest('.build-row');
  return within(row).getAllByRole('img').map((img) => img.getAttribute('alt'));
};

// 도란의 방패 > 여신의 눈물 > 점화석 역할(선혈포식자) 3번 > 장화 > 물약 2번 > 장신구 > 무한의 대검 = 10칸
const TEN = ['1054', '3070', '6631', '6631', '6631', '1001', '2003', '2003', '3340', '3031'];
const TEN_NAMES = ['도란의 방패', '여신의 눈물', '선혈포식자', '선혈포식자', '선혈포식자', '장화', '체력 물약', '체력 물약', '투명 와드', '무한의 대검'];

test('칸 수: 시작 아이템 1~4개 그대로, 핵심 템트리만 1~10개', () => {
  expect(ITEM_LIMITS).toEqual({ starting: [1, 4], core: [1, 10] });
});

test('규칙: 핵심 템트리 1칸, 같은 아이템 여러 번, 10칸은 통과 / 0칸·11칸은 안내', async () => {
  const items = await getItems();
  const base = buildToForm(fakeBuild(201, null));
  const game = { items, runes: null, spells: null };
  const check = (core_items) => buildProblem({ ...base, core_items });
  expect(check(['3070'])).toBeNull();
  expect(check(['6631', '6631'])).toBeNull();
  expect(check(TEN)).toBeNull();
  expect(check([])).toBe('핵심 템트리는 1~10개 골라 주세요.');
  expect(check([...TEN, '6631'])).toBe('핵심 템트리는 1~10개 골라 주세요.');
  // 시작 아이템 규칙은 그대로
  expect(buildProblem({ ...base, starting_items: ['1055', '2003', '2003', '2003', '2003'] })).toBe('시작 아이템은 1~4개 골라 주세요.');
  expect(game.items['1054'].kind).toBe('basic');
});

test('빌드 입력: 안내는 "가야 하는 순서대로 적어 주세요."만, 같은 아이템 3번·기본템 포함 10칸, 10칸이면 더 못 고름, 보낸 값 그대로', async () => {
  fakeLogin('u-old');
  start(`${MATCHUP}/build/new`);
  await screen.findByRole('heading', { name: /새 빌드/ });
  const fs = coreGroup().closest('fieldset');
  expect(within(fs).getByText('가야 하는 순서대로 적어 주세요.')).toBeDefined();
  // 개수·구성 제한 문구는 없음
  for (const re of [/~10개/, /1~/, /전설/, /서사·/, /신발/, /끌어서/]) expect(within(fs).queryByText(re, { selector: 'small' })).toBeNull();

  fillWikiBuild();
  for (const n of ['스테락의 도전', '강철판 장화', '선혈포식자']) fireEvent.click(within(pickedCore()).getByRole('button', { name: `${n} 빼기` }));
  for (const n of TEN_NAMES) pick('핵심 템트리 고르기', n);
  // 고른 목록: 같은 아이템도 줄마다 따로, 순서 그대로
  expect(within(pickedCore()).getAllByRole('button', { name: / 빼기$/ }).map((b) => b.getAttribute('aria-label').replace(/ 빼기$/, '')))
    .toEqual(TEN_NAMES);
  // 10칸이 차면 모든 고르기 버튼이 꺼지고 그때만 알려 줌
  expect(within(coreGroup()).getAllByRole('button').every((b) => b.disabled)).toBe(true);
  expect(within(fs).getByText('10개까지 고를 수 있습니다.')).toBeDefined();
  // 시작 아이템 칸은 영향 없음 (물약 또 고를 수 있음)
  expect(within(screen.getByRole('group', { name: '시작 아이템 고르기' })).getByRole('button', { name: '체력 물약' })).toBeEnabled();
  // 미리보기 카드: 10칸 순서대로
  expect(treeIcons(screen.getByRole('article', { name: '빌드: 기존유저' }))).toEqual(TEN_NAMES);

  // 중간의 선혈포식자 하나만 빼면 나머지 둘은 남고 다시 고를 수 있음
  fireEvent.click(within(pickedCore()).getAllByRole('button', { name: '선혈포식자 빼기' })[1]);
  expect(within(pickedCore()).getAllByRole('button', { name: '선혈포식자 빼기' })).toHaveLength(2);
  expect(within(coreGroup()).getAllByRole('button').some((b) => !b.disabled)).toBe(true);
  pick('핵심 템트리 고르기', '선혈포식자');

  fireEvent.click(screen.getByRole('button', { name: '빌드 등록' }));
  await vi.waitFor(() => expect(rpcCalls('create_build')).toHaveLength(1));
  const sent = rpcCalls('create_build')[0].p_build;
  expect(sent.core_items).toEqual(['1054', '3070', '6631', '6631', '1001', '2003', '2003', '3340', '3031', '6631']);
  expect(sent.starting_items).toEqual(['1055', '2003']);
}, 15000); // 고르기를 20번 넘게 눌러서 전체 검사 중에는 기본 5초를 넘길 수 있다

test('상대법 화면: 저장된 10칸(중복 포함) 빌드가 순서대로, 예전 3칸 빌드는 그대로', async () => {
  TABLES.builds.find((b) => b.id === 102).core_items = [...TEN];
  start(`${MATCHUP}?build=102`);
  const card = await screen.findByRole('article', { name: '빌드: 탑고수' });
  expect(treeIcons(card)).toEqual(TEN_NAMES);
  expect(card.querySelectorAll('.build-row .arrow')).toHaveLength(9);
  cleanup();
  start(`${MATCHUP}?build=103`);
  const old = await screen.findByRole('article', { name: '빌드: 칭호없음' });
  expect(treeIcons(old)).toEqual(['크라켄 학살자', '광전사의 군화', '무한의 대검']);
});

test('빌드 카드: 10칸이 한 줄에 다 안 들어가면 줄바꿈되는 칸(.icons) 안에 그린다', async () => {
  const [items, runes] = await Promise.all([getItems(), getRunes()]);
  render(<BuildCard build={fakeBuild(201, null, { core_items: [...TEN] })} items={items} runes={runes} spells={{}} />);
  const row = screen.getByText('템트리').closest('.build-row');
  const icons = row.querySelector('.icons');
  expect(icons.querySelectorAll('.step')).toHaveLength(10);
  // CSS: .icons는 flex-wrap: wrap (320px 화면에서 넘치지 않게)
  const css = readFileSync('src/index.css', 'utf8');
  expect(css).toMatch(/\.icons, \.skills \{[^}]*flex-wrap: wrap/);
});

test('변경 비교: 같은 아이템이 여러 번 든 템트리도 줄마다 비교', async () => {
  const items = await getItems();
  const before = { core_items: ['6631', '6631', '3031'] };
  const after = { core_items: ['1054', '6631', '6631', '6631', '3031'] };
  const core = buildDiff(before, after, { items }).find((f) => f.key === 'core');
  expect(core.changed).toBe(true);
  expect(lineDiff(core.before, core.after)).toEqual([
    { type: 'add', text: '도란의 방패' },
    { type: 'same', text: '선혈포식자' },
    { type: 'same', text: '선혈포식자' },
    { type: 'add', text: '선혈포식자' },
    { type: 'same', text: '무한의 대검' },
  ]);
  render(<DiffView fields={buildDiff({ core_items: [] }, { core_items: [...TEN] }, { items })} before={{}} />);
  const section = screen.getByRole('region', { name: '템트리 변경' });
  expect(section.querySelectorAll('.diff-line.add')).toHaveLength(10);
});
