// 028: 아이템 종류, 서사 태그, 아이템 고르기 전체 목록 + 검색. 056: 핵심 템트리는 상점 아이템 전부 (전설 → 서사 → 신발 → 기본 → 나머지)
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

test('규칙 (056): 핵심 템트리는 지금 상점 아이템이면 종류 상관없이, 전설 없어도 됨', async () => {
  const items = await getItems();
  for (const id of ['3076', '1036', '1054', '3070', '2003', '3340', '3865', '3047', '6631']) expect(isCoreItem(items[id])).toBe(true);
  expect(isCoreItem(items['3400'])).toBe(false); // 상점에서 못 사는 아이템
  expect(coreItemProblem(['3076', '3044', '3047'], items)).toBeNull(); // 전설 없음
  expect(coreItemProblem(['1054', '3070', '2003', '2003'], items)).toBeNull(); // 기본템·소모품, 중복
  expect(coreItemProblem(['3400', '3075'], items)).toBe('핵심 템트리에 지금 상점에 없는 아이템이 있습니다: 너만 살 수 있는 아이템');
});

// ---------------- 고르기 목록 ----------------

test('핵심 템트리 (056): 처음 15개, [더보기]로 상점 아이템 전부 (전설 → 서사 → 신발 → 기본 → 나머지, 같은 종류는 비싼 순), [접기]', async () => {
  asUser();
  start(NEW_BUILD);
  const first = await screen.findByRole('group', { name: '핵심 템트리 고르기' });
  const firstNames = names(first);
  expect(firstNames).toHaveLength(15);
  expect(screen.queryByRole('group', { name: '핵심 템트리 종류' })).toBeNull();
  for (const n of ['전체', '전설', '서사', '신발']) expect(screen.queryByRole('button', { name: n })).toBeNull();
  expect(firstNames[0]).toBe('무한의 대검'); // 가장 비싼 전설
  expect(firstNames[13]).toBe('시험용 전설 1'); // 전설 14개가 먼저
  expect(firstNames[14]).toBe('탐식의 망치 (서사)'); // 15번째부터 서사 (비싼 순)

  const fs = first.closest('fieldset');
  const more = within(fs).getByRole('button', { name: /^더보기/ });
  expect(more.getAttribute('aria-expanded')).toBe('false');
  fireEvent.click(more);
  const all = names(within(fs).getByRole('group', { name: '핵심 템트리 고르기' }));
  expect(all.slice(0, 15)).toEqual(firstNames);
  expect(all.slice(14)).toEqual([
    '탐식의 망치 (서사)', '덤불 조끼 (서사)', // 서사
    '강철판 장화', '광전사의 군화', '장화', // 신발
    '여신의 눈물', '도란의 검', '도란의 방패', '시험용 시작템 1', '시험용 시작템 2', '시험용 시작템 3', '시험용 시작템 4', '롱소드', '천 갑옷', // 기본
    '세계 지도집', '투명 와드', '체력 물약', // 나머지 (서포터템·장신구·소모품, 비싼 순)
  ]);
  // 상점에 없는 아이템은 그대로 빠짐
  for (const n of ['너만 살 수 있는 아이템', '칼바람 전용']) expect(all).not.toContain(n);
  expect(all.filter((n) => n === '무한의 대검')).toHaveLength(1); // 다른 모드 사본 없음

  fireEvent.click(within(fs).getByRole('button', { name: '접기' }));
  expect(names(within(fs).getByRole('group', { name: '핵심 템트리 고르기' }))).toEqual(firstNames);
});

test('핵심 템트리 검색: 더보기와 상관없이 전체에서 (초성 포함), 결과에도 서사 태그, 기본템도 찾음 (056)', async () => {
  asUser();
  start(NEW_BUILD);
  await screen.findByRole('group', { name: '핵심 템트리 고르기' });
  fireEvent.change(screen.getByLabelText('핵심 템트리 검색'), { target: { value: 'ㄷㅂㅈㄲ' } });
  expect(names(screen.getByRole('group', { name: '핵심 템트리 고르기' }))).toEqual(['덤불 조끼 (서사)']); // 처음 15개 밖이어도 찾는다
  expect(within(screen.getByLabelText('핵심 템트리 검색').closest('fieldset')).queryByRole('button', { name: /^더보기/ })).toBeNull();
  fireEvent.change(screen.getByLabelText('핵심 템트리 검색'), { target: { value: 'ㅇㅅㅇㄴㅁ' } });
  expect(names(screen.getByRole('group', { name: '핵심 템트리 고르기' }))).toEqual(['여신의 눈물']);
  fireEvent.change(screen.getByLabelText('핵심 템트리 검색'), { target: { value: '도란의 방패' } });
  expect(names(screen.getByRole('group', { name: '핵심 템트리 고르기' }))).toEqual(['도란의 방패']);
});

test('시작 아이템: 처음 9개(싼 순), [더보기]로 나머지, [접기]로 되돌림, 거르기 버튼 없음', async () => {
  asUser();
  start(NEW_BUILD);
  const first = await screen.findByRole('group', { name: '시작 아이템 고르기' });
  const firstNames = names(first);
  
  expect(firstNames).toHaveLength(9);
  expect(screen.queryByRole('group', { name: '시작 아이템 종류' })).toBeNull();
  for (const n of ['기본', '소모품']) expect(screen.queryByRole('button', { name: n })).toBeNull();
  const fs = first.closest('fieldset');
  fireEvent.click(within(fs).getByRole('button', { name: /^더보기/ }));
  const all = names(within(fs).getByRole('group', { name: '시작 아이템 고르기' }));
  expect(all).toHaveLength(10);
  expect(all.slice(0, 9)).toEqual(firstNames);
  expect(firstNames[0]).toBe('체력 물약'); // 싼 순
  expect(firstNames).toContain('롱소드');
  fireEvent.click(within(fs).getByRole('button', { name: '접기' }));
  expect(names(within(fs).getByRole('group', { name: '시작 아이템 고르기' }))).toEqual(firstNames);
  // 검색은 처음 9개 밖에서도
  fireEvent.change(screen.getByLabelText('시작 아이템 검색'), { target: { value: all[9] } });
  expect(names(screen.getByRole('group', { name: '시작 아이템 고르기' }))).toEqual([all[9]]);
});

test('빌드 입력: 서사템에 "서사" 태그, 전설이 없어도 안내 없이 미리보기 (056)', async () => {
  asUser();
  start(NEW_BUILD);
  await screen.findByRole('group', { name: '핵심 템트리 고르기' });
  fillBuild({ withSkill: true });
  for (const n of ['스테락의 도전', '선혈포식자']) fireEvent.click(screen.getByRole('button', { name: `${n} 빼기` }));
  pick('핵심 템트리 고르기', '덤불 조끼 (서사)');
  pick('핵심 템트리 고르기', '탐식의 망치 (서사)');
  expect(screen.queryByText(/아직 고를 것/)).toBeNull();
  expect(screen.queryByText(/전설 아이템을 1개 이상/)).toBeNull();
  const picked = screen.getByRole('list', { name: '고른 핵심 템트리' });
  expect(within(picked).getAllByText('서사')).toHaveLength(2);
  const preview = screen.getByRole('article', { name: '빌드: 기존유저' });
  expect(within(preview).getByRole('img', { name: '덤불 조끼 (서사)' })).toBeDefined();
  expect(within(preview).getAllByText('서사')).toHaveLength(2);
});
