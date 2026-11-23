// 6-77: 상대법 빌드 탭이 넘치면 [더보기] → 빌드 전부를 담은 창. 창 안에도 "장인 빌드"가 전부 붙고, 지금 고른 빌드가 표시된다
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeBuild, fakeLogin } from './fakeSupabase';

const PRO = { nickname: '장인A', level: 1, main_title: null, influencer: 'pro' };
const PRO2 = { nickname: '장인B', level: 1, main_title: null, influencer: 'creator' };
const EX = { nickname: '해제됨', level: 1, main_title: null, influencer: null };
const plain = (n) => ({ nickname: `일반${n}`, level: 1, main_title: null });
const MATCHUP = '/champion/Darius/counter/Quinn';

// jsdom은 폭을 재지 않는다 → 폭을 정해 준다. 줄(.build-tabs-row) 400, [+ 새 빌드] 80, 탭 하나 100(overflow) 또는 30
const widths = (overflow) => {
  vi.spyOn(HTMLElement.prototype, 'offsetWidth', 'get').mockImplementation(function w() {
    if (this.classList?.contains('build-tab')) return overflow ? 100 : 30;
    if (this.classList?.contains('new-build')) return 80;
    return 0;
  });
  vi.spyOn(Element.prototype, 'clientWidth', 'get').mockImplementation(function w() {
    return this.classList?.contains('build-tabs-row') ? 400 : 0;
  });
};

// 추천 수가 다 달라 순서가 정해진다 (추천 많은 순): 108(8) 107(7) … 101(1)
const EIGHT = () => [
  fakeBuild(101, PRO, { up_count: 1, name: '장인 하나' }),
  fakeBuild(102, plain(2), { up_count: 2 }),
  fakeBuild(103, PRO2, { up_count: 3 }),
  fakeBuild(104, plain(4), { up_count: 4, name: '일반 넷' }),
  fakeBuild(105, EX, { up_count: 5, name: '해제된 장인' }),
  fakeBuild(106, null, { up_count: 6, name: '탈퇴한 작성자' }),
  fakeBuild(107, plain(7), { up_count: 7 }),
  fakeBuild(108, PRO, { up_count: 8, name: '장인 여덟' }),
];

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

const start = async (path = MATCHUP) => {
  render(<MemoryRouter initialEntries={[path]}><AppRoutes /></MemoryRouter>);
  await screen.findByText(/퀸으로 다리우스 이기는 법/);
};
const moreBtn = () => screen.queryByRole('button', { name: /^더보기/ });
const openPicker = () => {
  fireEvent.click(moreBtn());
  return screen.getByRole('dialog', { name: /빌드 고르기/ });
};
const rows = (dialog) => within(dialog).getAllByRole('button').filter((b) => b.classList.contains('build-pick'));

test('탭이 넘치지 않으면 [더보기]가 없다 (넓은 화면)', async () => {
  TABLES.builds = EIGHT();
  widths(false);
  await start();
  expect(screen.getAllByRole('tab')).toHaveLength(8);
  expect(moreBtn()).toBeNull();
});

test('탭이 넘치면 [더보기] → 창에 빌드 전부, 장인 빌드에는 모두 "장인 빌드"(해제·탈퇴는 없음), 탭과 같은 표시', async () => {
  TABLES.builds = EIGHT();
  widths(true);
  await start();
  expect(moreBtn()).not.toBeNull();
  expect(moreBtn().getAttribute('aria-expanded')).toBe('false');
  const dialog = openPicker();
  expect(moreBtn().getAttribute('aria-expanded')).toBe('true');
  const list = rows(dialog);
  expect(list).toHaveLength(8);
  // 줄마다 배지 붙은 빌드: 108·103·101 = 지금 장인이 처음 만든 빌드 전부
  const tagged = list.filter((b) => b.querySelector('.inf-build-tag')).map((b) => b.querySelector('.build-pick-name').textContent);
  expect(tagged).toEqual(['장인 빌드 장인 여덟', '장인 빌드', '장인 빌드 장인 하나']);
  // 6-87: 줄도 왼쪽 강조선 카드 — 배지가 있는 줄만 주황(is-influencer), 나머지는 회색
  expect(list.map((b) => b.classList.contains('is-influencer'))).toEqual(list.map((b) => !!b.querySelector('.inf-build-tag')));
  // 탭 줄과 창의 이름이 똑같다 (같은 BuildTitle)
  const tabNames = screen.getAllByRole('tab').map((t) => t.querySelector('.build-tab-name').textContent);
  expect(list.map((b) => b.querySelector('.build-pick-name').textContent)).toEqual(tabNames);
  expect(tabNames).toContain('해제된 장인');
  expect(tabNames).toContain('탈퇴한 작성자');
});

test('지금 고른 빌드가 ✓·aria-current로 표시되고 열면 거기에 초점, 다른 빌드를 고르면 바뀌고 창이 닫힌다', async () => {
  TABLES.builds = EIGHT();
  widths(true);
  await start(`${MATCHUP}?build=104`);
  let dialog = openPicker();
  const on = rows(dialog).filter((b) => b.getAttribute('aria-current') === 'true');
  expect(on).toHaveLength(1);
  expect(on[0].textContent).toContain('일반 넷');
  expect(on[0].textContent).toContain('지금 보는 빌드');
  expect(on[0].querySelector('.build-pick-check').textContent).toBe('✓');
  expect(document.activeElement).toBe(on[0]);

  fireEvent.click(rows(dialog).find((b) => b.textContent.includes('장인 하나')));
  expect(screen.queryByRole('dialog')).toBeNull();
  expect(screen.getByRole('heading', { level: 3 }).textContent).toBe('장인 빌드 장인 하나');
  const tab = screen.getByRole('tab', { selected: true });
  expect(tab.textContent).toContain('장인 하나');
  expect(document.activeElement).toBe(tab);

  // 다시 열면 새로 고른 빌드가 표시된다
  dialog = openPicker();
  expect(rows(dialog).find((b) => b.getAttribute('aria-current') === 'true').textContent).toContain('장인 하나');
});

test('키보드: ↓↑·Home·End로 옮기고 Enter로 고른다, Esc로 닫으면 [더보기]로 초점', async () => {
  TABLES.builds = EIGHT();
  widths(true);
  await start();
  let dialog = openPicker();
  const list = rows(dialog);
  expect(document.activeElement).toBe(list[0]); // 기본은 맨 앞(추천 1등) 빌드
  fireEvent.keyDown(document.activeElement, { key: 'ArrowDown' });
  expect(document.activeElement).toBe(list[1]);
  fireEvent.keyDown(document.activeElement, { key: 'End' });
  expect(document.activeElement).toBe(list[7]);
  fireEvent.keyDown(document.activeElement, { key: 'ArrowDown' }); // 끝에서 더 내려가지 않는다
  expect(document.activeElement).toBe(list[7]);
  fireEvent.keyDown(document.activeElement, { key: 'Home' });
  expect(document.activeElement).toBe(list[0]);
  fireEvent.keyDown(document.activeElement, { key: 'ArrowUp' });
  expect(document.activeElement).toBe(list[0]);

  fireEvent.keyDown(document.activeElement, { key: 'Escape' });
  expect(screen.queryByRole('dialog')).toBeNull();
  expect(document.activeElement).toBe(moreBtn());

  // Tab은 창 안에서만 돈다: 마지막([닫기])에서 Tab → 첫 줄
  dialog = openPicker();
  const close = within(dialog).getByRole('button', { name: '닫기' });
  close.focus();
  fireEvent.keyDown(close, { key: 'Tab' });
  expect(document.activeElement).toBe(rows(dialog)[0]);
});

test('바깥(어두운 바탕)을 누르거나 [닫기]를 누르면 닫히고 빌드는 그대로', async () => {
  TABLES.builds = EIGHT();
  widths(true);
  await start();
  const before = screen.getByRole('heading', { level: 3 }).textContent;
  let dialog = openPicker();
  fireEvent.click(dialog.parentElement);
  expect(screen.queryByRole('dialog')).toBeNull();
  dialog = openPicker();
  fireEvent.click(within(dialog).getByRole('button', { name: '닫기' }));
  expect(screen.queryByRole('dialog')).toBeNull();
  expect(screen.getByRole('heading', { level: 3 }).textContent).toBe(before);
});

test('차단한 사람이 처음 만든 빌드는 탭과 창 모두에서 빠진다', async () => {
  TABLES.builds = EIGHT();
  TABLES.user_blocks.push({ blocker_id: 'u-me', blocked_id: 'u-108', created_at: '2026-11-17T00:00:00Z' });
  fakeLogin('u-me', { nickname: '나', level: 1 });
  widths(true);
  await start();
  const dialog = openPicker();
  expect(rows(dialog)).toHaveLength(7);
  expect(dialog.textContent).not.toContain('장인 여덟');
  expect(screen.getAllByRole('tab')).toHaveLength(7);
});

test('좁은 폰: 탭이 [+ 새 빌드] 옆에 안 들어가면 탭 줄을 한 줄 전체로, 그래도 넘칠 때만 [더보기] (빌드 하나면 없음)', async () => {
  vi.stubGlobal('matchMedia', (q) => ({ matches: q === '(max-width: 420px)', media: q, addEventListener() {}, removeEventListener() {} }));
  const row = () => document.querySelector('.build-tabs-row');
  // (jsdom은 간격을 0으로 준다) 탭 2개 × 150 + 4 = 304 → 옆 자리(400 − 80 = 320)에 들어간다 → 그대로
  vi.spyOn(HTMLElement.prototype, 'offsetWidth', 'get').mockImplementation(function w() {
    if (this.classList?.contains('build-tab')) return 150;
    if (this.classList?.contains('new-build')) return 80;
    return 0;
  });
  vi.spyOn(Element.prototype, 'clientWidth', 'get').mockImplementation(function w() {
    return this.classList?.contains('build-tabs-row') ? 400 : 0;
  });
  TABLES.builds = EIGHT().slice(0, 2);
  await start();
  expect(row().classList.contains('wrap')).toBe(false);
  expect(moreBtn()).toBeNull();
  cleanup();
  // 탭 3개 = 3×150 + 4 = 454 → 옆 자리(320)도 한 줄 전체(400)도 넘친다 → 줄 바꿈 + [더보기]
  TABLES.builds = EIGHT().slice(0, 3);
  await start();
  expect(row().classList.contains('wrap')).toBe(true);
  expect(moreBtn()).not.toBeNull();
  cleanup();
  // 탭 2개 × 180 + 4 = 364 → 옆 자리는 넘치지만 한 줄 전체(400)에는 들어간다 → 줄 바꿈만, [더보기] 없음
  vi.spyOn(HTMLElement.prototype, 'offsetWidth', 'get').mockImplementation(function w() {
    if (this.classList?.contains('build-tab')) return 180;
    if (this.classList?.contains('new-build')) return 80;
    return 0;
  });
  TABLES.builds = EIGHT().slice(0, 2);
  await start();
  expect(row().classList.contains('wrap')).toBe(true);
  expect(moreBtn()).toBeNull();
  cleanup();
  // 빌드 하나: 넘쳐도 [더보기]·줄 바꿈 없음
  TABLES.builds = EIGHT().slice(0, 1);
  await start();
  expect(row().classList.contains('wrap')).toBe(false);
  expect(moreBtn()).toBeNull();
  vi.unstubAllGlobals();
});
