// 묶음 C (018): 시작 아이템 500골드 상한, 선마 하나, 카운터 순위·문구, 자유게시판, 부제, 운영자 아이템 가격표
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeBuild, fakeLogin, fakeState } from './fakeSupabase';
import { buildProblem, buildToForm, emptyBuild, startGold, startGoldProblem } from '../lib/buildContent';
import { SKILL_GROUP, fillBuild, pick } from './buildHelpers';
import { clickMenu } from './menu';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /></MemoryRouter>);
const MATCHUP = '/champion/Darius/counter/Quinn';
const asUser = () => fakeLogin('u-old');
const asOperator = () => fakeLogin('u-op', { nickname: '영자(운)', role: 'admin', level: 0, main_title: null });
const startGroup = () => screen.getByRole('group', { name: '시작 아이템 고르기' });
const rpcCalls = (name) => fakeState.rpcCalls.filter((c) => c.name === name).map((c) => c.args);

// ---------------- 규칙 ----------------

test('규칙: 시작템 합계는 개수만큼 더하고, 상한은 game.startGoldMax (없으면 500)', () => {
  const items = { 1055: { gold: 450 }, 2003: { gold: 50 } };
  expect(startGold(['1055', '2003', '2003'], items)).toBe(550);
  expect(startGoldProblem({ starting_items: ['1055', '2003'] }, { items })).toBeNull();
  expect(startGoldProblem({ starting_items: ['1055', '2003', '2003'] }, { items })).toBe('시작 아이템은 합계 500골드까지 고를 수 있어요. (지금 550골드)');
  expect(startGoldProblem({ starting_items: ['1055', '2003', '2003'] }, { items, startGoldMax: 600 })).toBeNull();
});

test('규칙: 선마는 Q·W·E 하나, 예전 모양(선마 순서)으로 채우면 선마는 비어 있다', () => {
  expect(emptyBuild().max_skill).toBeNull();
  expect(buildProblem({ ...buildToForm({ max_skill: 'E' }), max_skill: 'R' })).toBe('주 경로를 골라 주세요.');
  expect(buildToForm({ max_skill: 'E' }).max_skill).toBe('E');
  expect(buildToForm({ skill_order: ['Q', 'E', 'W'] }).max_skill).toBeNull();
  expect('skill_order' in emptyBuild() || 'early_skills' in emptyBuild()).toBe(false);
});

// ---------------- 빌드 입력 ----------------

test('빌드 등록: 시작 아이템 목록에는 500골드 이하만, 안내 문장 없이 넘기려 할 때만 "500골드를 넘어요" (022)', async () => {
  vi.useFakeTimers({ shouldAdvanceTime: true });
  asUser();
  start(`${MATCHUP}/build/new`);
  await screen.findByRole('heading', { name: /빌드 등록/ });
  // 1100골드 탐식의 망치는 시작 아이템에는 없고 핵심 템트리에는 있다
  expect(within(startGroup()).queryByRole('button', { name: '탐식의 망치' })).toBeNull();
  expect(within(screen.getByRole('group', { name: '핵심 템트리 고르기' })).getByRole('button', { name: '탐식의 망치' })).toBeDefined();
  expect(screen.queryByText(/합계 500골드까지/)).toBeNull();
  expect(screen.queryByText(/1~4개/)).toBeNull();
  expect(screen.queryByLabelText('시작 아이템 골드 합계')).toBeNull();
  expect(screen.queryByText(/남은 골드/)).toBeNull();
  expect(screen.getByLabelText('시작 아이템 검색').getAttribute('placeholder')).toBe('판금장화 ex) ㅍㄱㅈㅎ');

  pick('시작 아이템 고르기', '도란의 검');
  expect(screen.queryByText('500골드를 넘어요')).toBeNull();
  pick('시작 아이템 고르기', '도란의 방패'); // 450 + 450 > 500 → 안 들어가고 잠깐 안내
  expect(screen.getByText('500골드를 넘어요')).toBeDefined();
  const picked = () => within(screen.getByRole('list', { name: '고른 시작 아이템' })).getAllByRole('listitem').map((li) => li.textContent);
  expect(picked()).toEqual(['도란의 검']);
  await vi.advanceTimersByTimeAsync(2100);
  expect(screen.queryByText('500골드를 넘어요')).toBeNull();
  pick('시작 아이템 고르기', '체력 물약');
  expect(picked()).toEqual(['도란의 검', '체력 물약']);

  // [X]로 빼면 다시 고를 수 있다
  fireEvent.click(screen.getByRole('button', { name: '도란의 검 빼기' }));
  pick('시작 아이템 고르기', '도란의 방패');
  expect(picked()).toEqual(['체력 물약', '도란의 방패']);
  vi.useRealTimers();
});

test('빌드 등록: 스킬은 선마 하나만 (1·2·3레벨·선마 순서 칸 없음), 다시 누르면 바뀐다', async () => {
  asUser();
  start(`${MATCHUP}/build/new`);
  await screen.findByRole('heading', { name: /빌드 등록/ });
  expect(screen.queryByRole('group', { name: '1레벨 스킬' })).toBeNull();
  expect(screen.queryByRole('group', { name: '선마 순서' })).toBeNull();
  fillBuild();
  expect(screen.getByText('아직 고를 것: 선마(첫 번째로 마스터할 스킬)를 골라 주세요.')).toBeDefined();
  pick(SKILL_GROUP, '선마 Q');
  pick(SKILL_GROUP, '선마 E');
  const pressed = within(screen.getByRole('group', { name: SKILL_GROUP })).getAllByRole('button')
    .filter((b) => b.getAttribute('aria-pressed') === 'true').map((b) => b.getAttribute('aria-label'));
  expect(pressed).toEqual(['선마 E']);
  // 미리보기 카드에 선마 하나
  const preview = screen.getByRole('article', { name: '빌드: 기존유저' });
  expect(within(preview).getByLabelText('선마: E')).toBeDefined();
});

test('[이 빌드로 다시 쓰기]: 합계를 넘는 예전 빌드는 이유를 보여 주고 보내기가 잠긴다', async () => {
  asUser();
  TABLES.builds.push(fakeBuild(140, { nickname: '기존유저', level: 1, main_title: null }, {
    author_id: 'u-old', status: 'rejected', starting_items: ['1055', '2003', '2003'],
  }));
  start(`${MATCHUP}/build/new?from=140`);
  await screen.findByRole('heading', { name: /빌드 등록/ });
  expect(screen.getByText('아직 고를 것: 시작 아이템은 합계 500골드까지 고를 수 있어요. (지금 550골드)')).toBeDefined();
  expect(screen.getByRole('button', { name: '빌드 보내기' })).toBeDisabled();
});

// ---------------- 빌드 카드 ----------------

test('매치업 문서의 빌드 카드: 스킬 줄은 선마 하나', async () => {
  start(MATCHUP);
  const card = await screen.findByRole('article', { name: '빌드: 탑고수' });
  expect(within(card).getByLabelText('선마: Q')).toBeDefined();
  expect(within(card).queryByLabelText(/1·2·3레벨/)).toBeNull();
});

// ---------------- 운영자 ----------------

test('운영자 빌드 자세히: 시작템 합계를 넘는 대기 빌드는 경고, 목록 줄에서는 [승인]이 잠긴다', async () => {
  asOperator();
  TABLES.builds.push(fakeBuild(141, { nickname: '욕심쟁이', level: 1, main_title: null }, {
    author_id: 'u-old', status: 'pending', starting_items: ['1055', '1054'],
  }));
  start('/admin/builds/141');
  expect(await screen.findByText(/시작 아이템은 합계 500골드까지 고를 수 있어요. \(지금 900골드\) 그대로는 승인할 수 없어요/)).toBeDefined();
  cleanup();
  start('/admin');
  const rows = await screen.findAllByRole('listitem', { name: '[빌드] 퀸으로 다리우스 잡는 법' });
  const row = rows.find((li) => within(li).queryByText(/지금 900골드/));
  expect(within(row).getByText(/지금 900골드/)).toBeDefined();
  expect(within(row).getByRole('button', { name: '승인' })).toBeDisabled();
});

test('운영자: 아이템 가격표 — 기준 패치와 상한을 보여 주고, [아이템 가격 갱신]은 상점 아이템 가격 전체를 보낸다', async () => {
  asOperator();
  TABLES.item_prices = TABLES.item_prices.map((p) => ({ ...p, patch: '98.1.1' }));
  start('/admin');
  const sec = (await screen.findByRole('heading', { name: '아이템 가격표' })).closest('section');
  expect(await within(sec).findByText(/DB 가격표: 패치 98.1.1 기준 · 지금 패치: 99.1.1 · 시작 아이템 합계 상한: 500골드/)).toBeDefined();
  expect(within(sec).getByRole('alert')).toHaveTextContent('가격표가 지금 패치와 달라요');
  fireEvent.click(within(sec).getByRole('button', { name: '아이템 가격 갱신' }));
  expect(await within(sec).findByText(/패치 99.1.1 기준으로 바꿨어요/)).toBeDefined();
  const [args] = rpcCalls('set_item_prices');
  expect(args.p_patch).toBe('99.1.1');
  expect(args.p_prices).toMatchObject({ 1055: 450, 2003: 50, 3044: 1100 });
  expect(args.p_prices['3400']).toBeUndefined(); // 상점에서 못 사는 아이템은 빼고
  expect(await within(sec).findByText(/DB 가격표: 패치 99.1.1 기준/)).toBeDefined();
  expect(within(sec).queryByRole('alert')).toBeNull();
});

// ---------------- 문구 ----------------

test('챔피언 문서: "다리우스 카운터", 순위 숫자, 안내 문구 없음, [+ 카운터 등록] → "다리우스 카운터 선택"', async () => {
  start('/champion/Darius');
  expect(await screen.findByRole('heading', { name: '1. 다리우스 카운터' })).toBeDefined();
  expect(screen.queryByText(/위에 있을수록/)).toBeNull();
  expect(screen.getByLabelText('1위')).toHaveTextContent('1');
  expect(screen.getByLabelText('1위').className).toBe('rank top');
  asUser();
  cleanup();
  start('/champion/Darius');
  fireEvent.click(await screen.findByRole('link', { name: '+ 카운터 등록' }));
  expect(await screen.findByRole('heading', { name: '다리우스 카운터 선택' })).toBeDefined();
  expect(screen.getByRole('heading', { name: '1. 카운터 고르기' })).toBeDefined();
  expect(screen.getByText(/› 카운터 등록/)).toBeDefined();
});

test('상단 바: 사이트 이름 옆에 부제, 메뉴의 자유게시판 링크와 화면 제목', async () => {
  start('/board');
  expect(screen.getByRole('link', { name: '탑신병자' })).toBeDefined();
  expect(screen.getByText('탑은 라인전이 전부')).toBeDefined();
  await clickMenu('자유게시판');
  expect(await screen.findByRole('heading', { name: '자유게시판' })).toBeDefined();
  await vi.waitFor(() => expect(document.title).toBe('자유게시판 - 탑신병자'));
});
