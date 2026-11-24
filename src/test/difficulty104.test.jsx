// 6-104 (1.3 패치 3-A·3-B): 빌드 난이도 별점 — 값 규칙 · 입력 별 5개 · 표시 · 저장/읽기 API
import { afterEach, beforeEach, expect, test } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import DifficultyField, { DifficultyBadge } from '../components/Difficulty';
import { cleanDifficulty, difficultyLabel, difficultyText, nextDifficulty, sameDifficulty, starFill } from '../lib/difficulty';
import { getBuildDifficulties, saveDifficultyAfterCreate, setBuildDifficulty } from '../api/builds';
import { TABLES, fakeBuild, fakeState, resetFake } from './fakeSupabase';
import { useState } from 'react';

beforeEach(() => resetFake());
afterEach(() => cleanup());

test('값 다듬기: 0.5 단위 0.5~5.0만 받고 나머지는 비움', () => {
  expect(cleanDifficulty(3.5)).toBe(3.5);
  expect(cleanDifficulty('4')).toBe(4);
  for (const bad of [0, 0.3, 5.5, -1, 'x', null, undefined, '']) expect(cleanDifficulty(bad)).toBeNull();
  expect(difficultyText(4)).toBe('4.0');
  expect(difficultyLabel(3.5)).toBe('난이도 3.5점');
  expect(difficultyLabel(null)).toBe('난이도 선택 안 함');
  expect(sameDifficulty(null, undefined)).toBe(true);
  expect(sameDifficulty(3, 3.5)).toBe(false);
});

test('별 누르기: n점 → 반 칸 → 비움, 별 채움', () => {
  expect(nextDifficulty(null, 3)).toBe(3);
  expect(nextDifficulty(3, 3)).toBe(2.5);
  expect(nextDifficulty(2.5, 3)).toBeNull();
  expect(nextDifficulty(2, 4)).toBe(4);
  expect([1, 2, 3, 4, 5].map((n) => starFill(2.5, n))).toEqual([1, 1, 0.5, 0, 0]);
  expect(starFill(null, 1)).toBe(0);
});

test('표시: 값이 없으면 아무것도 그리지 않고, 있으면 ★ 3.5 + 읽는 문구', () => {
  const { container, rerender } = render(<DifficultyBadge value={null} />);
  expect(container.innerHTML).toBe('');
  rerender(<DifficultyBadge value={3.5} />);
  expect(container.textContent).toContain('★ 3.5');
  expect(container.textContent).toContain('난이도 3.5점');
});

test('입력: 별을 누르면 값이 바뀌고 [선택 안 함]으로 비운다', () => {
  const seen = [];
  function Host() {
    const [v, setV] = useState(null);
    seen.push(v);
    return <DifficultyField value={v} onChange={setV} />;
  }
  render(<Host />);
  expect(screen.getByText('선택 안 함')).toBeTruthy();
  fireEvent.click(screen.getByRole('button', { name: '별 3개' }));
  expect(screen.getByText('3.0점')).toBeTruthy();
  fireEvent.click(screen.getByRole('button', { name: '별 3개' }));
  expect(screen.getByText('2.5점')).toBeTruthy();
  fireEvent.click(screen.getByRole('button', { name: '선택 안 함' }));
  expect(seen.at(-1)).toBeNull();
});

test('저장 API: 잘못된 값은 DB를 부르기 전에 막고, 등록 직후 저장 실패는 던지지 않는다', async () => {
  await expect(setBuildDifficulty(1, 0.3)).rejects.toThrow('0.5 단위');
  expect(fakeState.rpcLog).not.toContain('set_build_difficulty');
  expect(await saveDifficultyAfterCreate(1, null)).toBe(true);
  expect(fakeState.rpcLog).not.toContain('set_build_difficulty');
  expect(await saveDifficultyAfterCreate(1, 3)).toBe(false); // 로그인 안 함 → 실패해도 false
});

test('읽기 API: 별점이 있는 빌드만 키로 오고, 실패하면 failed로 알린다', async () => {
  TABLES.builds.length = 0;
  TABLES.builds.push(fakeBuild(1, 'u1', { difficulty: 3.5 }), fakeBuild(2, 'u1', {}));
  const ok = await getBuildDifficulties([1, 2, 2, 'x']);
  expect(ok.values).toEqual({ 1: 3.5 });
  expect(ok.failed).toEqual([]);
  fakeState.difficultiesError = '실패';
  const bad = await getBuildDifficulties([1, 2]);
  expect(bad.values).toEqual({});
  expect(bad.failed.sort()).toEqual([1, 2]);
  await waitFor(() => expect(fakeState.difficultyReads.length).toBe(2));
});
