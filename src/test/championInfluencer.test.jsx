// 챔피언 화면: 요약으로 올라온 빌드가 장인 빌드면 "장인 빌드" 칩 (장인 우선, 해제·탈퇴·비공개는 장인으로 안 침)
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeBuild } from './fakeSupabase';

const SAVED = [...TABLES.builds];
const PRO = { nickname: '장인A', level: 1, main_title: null, influencer: 'pro' };
const PRO2 = { nickname: '장인B', level: 1, main_title: null, influencer: 'creator' };
const EX = { nickname: '해제됨', level: 1, main_title: null, influencer: null };
const plain = { nickname: '일반', level: 1, main_title: null };

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); TABLES.builds = [...SAVED]; });

const show = async (builds) => {
  TABLES.builds = builds;
  render(<MemoryRouter initialEntries={['/champion/Darius']}><AppRoutes /></MemoryRouter>);
  return screen.findByRole('link', { name: /퀸/ });
};
const chip = () => screen.queryAllByText('장인 빌드');

test('장인 빌드가 없으면 기존 맨 앞 빌드 요약, 칩 없음', async () => {
  const row = await show([fakeBuild(101, plain, { up_count: 9, summary: '일반 요약' }), fakeBuild(102, plain, { up_count: 1, summary: '다른 요약' })]);
  expect(row.textContent).toContain('일반 요약');
  expect(chip()).toHaveLength(0);
});

test('장인 빌드가 추천 수가 낮아도 요약으로 올라오고 칩이 붙는다', async () => {
  const row = await show([fakeBuild(101, plain, { up_count: 9, summary: '일반 요약' }), fakeBuild(102, PRO, { up_count: 1, summary: '장인 요약' })]);
  expect(row.textContent).toContain('장인 요약');
  expect(row.textContent).not.toContain('일반 요약');
  expect(chip()).toHaveLength(1);
});

test('장인 빌드가 여럿이면 추천 수 가장 많은 것, 동점이면 기존 정렬(점수→최신)', async () => {
  let row = await show([fakeBuild(101, PRO, { up_count: 2, summary: '장인 둘' }), fakeBuild(102, PRO2, { up_count: 5, summary: '장인 다섯' })]);
  expect(row.textContent).toContain('장인 다섯');
  cleanup();
  row = await show([
    fakeBuild(101, PRO, { up_count: 3, down_count: 2, summary: '점수 낮음' }),
    fakeBuild(102, PRO2, { up_count: 3, down_count: 0, summary: '점수 높음' }),
  ]);
  expect(row.textContent).toContain('점수 높음');
});

test('인증이 해제된 작성자 빌드는 장인으로 치지 않는다', async () => {
  const row = await show([fakeBuild(101, plain, { up_count: 9, summary: '일반 요약' }), fakeBuild(102, EX, { up_count: 1, summary: '해제 요약' })]);
  expect(row.textContent).toContain('일반 요약');
  expect(chip()).toHaveLength(0);
});

test('탈퇴한 작성자(author 없음) 빌드는 장인으로 치지 않는다', async () => {
  const row = await show([fakeBuild(101, plain, { up_count: 9, summary: '일반 요약' }), fakeBuild(102, null, { up_count: 1, summary: '탈퇴 요약' })]);
  expect(row.textContent).toContain('일반 요약');
  expect(chip()).toHaveLength(0);
});

test('비공개·숨김 상태의 장인 빌드는 고르지 않는다', async () => {
  const row = await show([
    fakeBuild(101, plain, { up_count: 1, summary: '일반 요약' }),
    fakeBuild(102, PRO, { up_count: 50, status: 'pending', summary: '대기 요약' }),
    fakeBuild(103, PRO, { up_count: 50, status: 'hidden', summary: '숨김 요약' }),
  ]);
  expect(row.textContent).toContain('일반 요약');
  expect(chip()).toHaveLength(0);
});
