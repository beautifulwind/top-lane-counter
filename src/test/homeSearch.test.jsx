// 홈 검색창 (6-61): 챔피언·상대법(조합)·빌드 후보, 한 번만 받는 10분 캐시, 키보드
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { AppRoutes } from '../App';
import { createBuild } from '../api/builds';
import { hideCounter } from '../api/proposals';
import { emptyWikiBuild } from '../lib/wikiBuild';
import { INDEX_TTL_MS } from '../api/searchIndex';
import { INDEX_ERROR, NO_RESULT } from '../components/BuildSearch';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeBuild, fakeLogin, fakeState } from './fakeSupabase';

vi.mock('../lib/champAliases', () => ({ CHAMP_ALIASES: { Quinn: ['날쌘새'], Garen: ['gal'] } }));

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

function Where() { const l = useLocation(); return <output data-testid="where">{l.pathname + l.search}</output>; }
const start = () => render(<MemoryRouter initialEntries={['/']}><AppRoutes /><Where /></MemoryRouter>);
const where = () => screen.getByTestId('where').textContent;
const box = () => screen.findByRole('combobox', { name: '챔피언·빌드 검색' });
const type = async (text) => { const b = await box(); fireEvent.change(b, { target: { value: text } }); return b; };
const list = () => screen.findByRole('listbox', { name: '검색 후보' });
const opt = async (name) => within(await list()).findByRole('option', { name });
const asked = (table) => fakeState.queryLog.filter((q) => q.table === table).length;

const counter = (id, target, mine, extra = {}) => ({ id, target_champion: target, counter_champion: mine, sort_order: id, status: 'approved', matchup_docs: null, ...extra });
const addCounters = () => TABLES.counters.push(counter(3, 'Garen', 'Teemo'), counter(4, 'Quinn', 'Darius'));
const named = (id, title, extra = {}) => {
  const k = TABLES.counters.find((c) => c.id === (extra.counter_id ?? 1));
  return fakeBuild(id, null, { name: title, counter: { id: k.id, target_champion: k.target_champion, counter_champion: k.counter_champion, status: k.status }, ...extra });
};

test('"내 챔피언 + 상대 챔피언": 그 조합의 상대법이 후보로 바로 뜨고 누르면 문서로', async () => {
  start();
  await type('퀸 다리우스');
  const o = await opt(/퀸으로 다리우스/);
  expect(o).toHaveAttribute('href', '/champion/Darius/counter/Quinn');
  expect(o).toHaveTextContent('빌드 4개'); // 공개된 빌드 4개 (대기 중 1개는 제외)
  fireEvent.click(o);
  await waitFor(() => expect(where()).toBe('/champion/Darius/counter/Quinn'));
});

test('초성·영문 id·별명으로도 같은 조합', async () => {
  start();
  await type('ㅋ ㄷㄹㅇㅅ');
  expect(await opt(/퀸으로 다리우스/)).toBeDefined();
  fireEvent.change(await box(), { target: { value: 'quinn darius' } });
  expect(await opt(/퀸으로 다리우스/)).toBeDefined();
  fireEvent.change(await box(), { target: { value: '날쌘새 다리' } });
  expect(await opt(/퀸으로 다리우스/)).toBeDefined();
});

test('챔피언 하나: 챔피언 후보 + 그 챔피언을 상대로 한 상대법 목록', async () => {
  start();
  await type('다리우스');
  const l = await list();
  expect(await within(l).findByRole('option', { name: /다리우스/ })).toHaveAttribute('href', '/champion/Darius');
  expect(await within(l).findByRole('option', { name: /퀸으로 다리우스/ })).toBeDefined();
  expect(within(l).getByRole('group', { name: '챔피언' })).toBeDefined();
  expect(within(l).getByRole('group', { name: '상대법' })).toBeDefined();
});

test('반대 방향만 있는 조합은 방향을 표시해 보조로, 내 방향은 "아직 없음 · 직접 쓰기"', async () => {
  start();
  await type('다리우스 퀸'); // 내 다리우스 + 상대 퀸 → 없음, 퀸 + 다리우스(입력의 반대)만 있음
  const rev = await opt(/퀸으로 다리우스/);
  expect(rev).toHaveTextContent('입력과 반대 방향');
  const miss = await opt(/다리우스로 퀸/);
  expect(miss).toHaveTextContent('아직 없음 · 직접 쓰기');
  expect(miss).toHaveAttribute('href', '/matchup/new?target=Quinn&mine=Darius');
});

test('없는 조합 / 아예 없는 낱말', async () => {
  start();
  await type('가렌 티모');
  expect(await opt(/가렌으로 티모/)).toHaveTextContent('아직 없음 · 직접 쓰기');
  fireEvent.change(await box(), { target: { value: '쀍쀍 쀍' } });
  expect(await screen.findByText(NO_RESULT)).toBeDefined();
  expect(within(await list()).queryAllByRole('option')).toHaveLength(0);
});

test('빌드 제목: 단어 순서가 바뀌어도, 초성이 섞여도 빌드가 뜨고 장인 빌드 표시·?build= 링크', async () => {
  TABLES.builds.push(named(110, '빛망 감전 견제', { author: { nickname: '장인', influencer: 'creator' } }));
  start();
  await type('견제 감전 빛망');
  const o = await opt(/빛망 감전 견제/);
  expect(o).toHaveAttribute('href', '/champion/Darius/counter/Quinn?build=110');
  expect(o).toHaveTextContent('장인 빌드');
  expect(o).toHaveTextContent('퀸으로 다리우스');
  fireEvent.change(await box(), { target: { value: 'ㅂㅁ 퀸' } });
  expect(await opt(/빛망 감전 견제/)).toBeDefined();
  fireEvent.change(await box(), { target: { value: '빛 감전 룬' } }); // 모든 단어가 맞아야 한다
  await screen.findByText(NO_RESULT);
});

test('이름이 없는 빌드는 한 줄 요약으로 찾고, 후보에 "빌드 N"과 요약이 같이 보인다', async () => {
  TABLES.builds.push(named(120, null, { seq: 7, summary: '감전으로 초반 견제 후 이득' }), named(121, '빛망', { summary: '룬은 감전' }));
  start();
  await type('감전 초반');
  const o = await opt(/빌드 7/);
  expect(o).toHaveTextContent('감전으로 초반 견제 후 이득');
  expect(o).toHaveAttribute('href', '/champion/Darius/counter/Quinn?build=120');
  // 이름의 단어 + 요약의 단어
  fireEvent.change(await box(), { target: { value: '감전 빛망' } });
  expect(await opt(/빛망/)).toBeDefined();
});

test('숨긴·대기 빌드와 숨긴 상대법의 빌드는 후보에 없다', async () => {
  addCounters();
  TABLES.counters.push(counter(9, 'Vayne', 'Teemo', { status: 'hidden' }));
  TABLES.builds.push(
    named(111, '보이는 빛망'),
    named(112, '숨긴 빛망', { status: 'hidden' }),
    named(113, '대기 빛망', { status: 'pending' }),
    named(114, '숨긴상대법 빛망', { counter_id: 9 }),
  );
  start();
  await type('빛망');
  expect(await opt(/보이는 빛망/)).toBeDefined();
  expect(within(await list()).queryByRole('option', { name: /숨긴 빛망|대기 빛망|숨긴상대법/ })).toBeNull();
});

test('상대법 1000행 넘으면 range로 쪼개 받는다 (1500행 → 두 번)', async () => {
  for (let i = 0; i < 1500; i += 1) TABLES.counters.push(counter(1000 + i, `T${i}`, `M${i}`));
  start();
  await type('퀸');
  await opt(/퀸/);
  await waitFor(() => expect(asked('counters')).toBe(2));
  expect(asked('builds')).toBe(1);
});

test('키 입력마다 요청하지 않고 10분 캐시, 등록·숨김 직후엔 새로 받는다', async () => {
  fakeLogin('u-admin');
  const now = vi.spyOn(Date, 'now');
  const t0 = Date.now();
  now.mockReturnValue(t0);
  start();
  const b = await box();
  for (const v of ['ㅋ', '퀸', '퀸 ', '퀸 다', '퀸 다리']) fireEvent.change(b, { target: { value: v } });
  await opt(/퀸으로 다리우스/);
  expect(asked('counters')).toBe(1);
  expect(asked('builds')).toBe(1);
  // 지웠다 다시 써도, 입력칸에 다시 들어가도 그대로
  fireEvent.change(b, { target: { value: '' } });
  fireEvent.focus(b);
  fireEvent.change(b, { target: { value: '퀸' } });
  expect(asked('counters')).toBe(1);
  // 10분이 지나면 다음에 포커스할 때 새로
  now.mockReturnValue(t0 + INDEX_TTL_MS + 1);
  fireEvent.focus(b);
  await waitFor(() => expect(asked('counters')).toBe(2));
  // 상대법 숨기기 같은 변경 직후엔 바로 무효화
  fakeState.session = null;
  fakeLogin('u-admin');
  await hideCounter(1, '사유').catch(() => {});
  fireEvent.focus(b);
  await waitFor(() => expect(asked('counters')).toBe(3));
});

test('빌드를 새로 등록하면 캐시를 비워, 방금 쓴 빌드 제목이 바로 검색된다', async () => {
  fakeLogin('u-old');
  start();
  const b = await type('다리우스');
  await opt(/퀸으로 다리우스/);
  expect(asked('builds')).toBe(1);
  await createBuild(1, { ...emptyWikiBuild(), name: '방금쓴 제목', summary: '요약' }, '99.1.1');
  fireEvent.focus(b);
  fireEvent.change(b, { target: { value: '방금쓴' } });
  expect(await opt(/방금쓴 제목/)).toBeDefined();
  expect(asked('builds')).toBe(2);
});

test('목록을 못 받아도 챔피언 후보는 나오고, 안내가 뜬다 (실패는 캐시하지 않는다)', async () => {
  fakeState.error = '연결 끊김';
  start();
  await type('다리우스');
  expect(await opt(/다리우스/)).toBeDefined();
  expect(await screen.findByText(INDEX_ERROR)).toBeDefined();
  fakeState.error = null;
  fireEvent.focus(await box());
  expect(await opt(/퀸으로 다리우스/)).toBeDefined();
  await waitFor(() => expect(screen.queryByText(INDEX_ERROR)).toBeNull());
});

test('키보드: ↑↓로 고르고 Enter로 이동, Esc로 닫기, aria-activedescendant', async () => {
  start();
  const b = await type('다리우스');
  await opt(/퀸으로 다리우스/);
  const options = within(await list()).getAllByRole('option');
  expect(b).toHaveAttribute('aria-expanded', 'true');
  fireEvent.keyDown(b, { key: 'ArrowDown' });
  expect(b).toHaveAttribute('aria-activedescendant', options[0].id);
  fireEvent.keyDown(b, { key: 'ArrowDown' });
  expect(b).toHaveAttribute('aria-activedescendant', options[1].id);
  expect(options[1]).toHaveAttribute('aria-selected', 'true');
  fireEvent.keyDown(b, { key: 'ArrowUp' });
  fireEvent.keyDown(b, { key: 'ArrowUp' }); // 맨 위에서 위로 → 맨 아래
  expect(b).toHaveAttribute('aria-activedescendant', options[options.length - 1].id);
  fireEvent.keyDown(b, { key: 'ArrowDown' }); // 맨 아래에서 아래로 → 맨 위
  fireEvent.keyDown(b, { key: 'ArrowDown' });
  fireEvent.keyDown(b, { key: 'Enter' });
  await waitFor(() => expect(where()).toBe(options[1].getAttribute('href')));
});

test('Enter만 치면 첫 후보로, Esc는 목록을 닫고 다시 입력하면 열린다', async () => {
  start();
  const b = await type('퀸 다리우스');
  await opt(/퀸으로 다리우스/);
  fireEvent.keyDown(b, { key: 'Escape' });
  expect(screen.queryByRole('listbox')).toBeNull();
  fireEvent.change(b, { target: { value: '퀸 다리' } });
  await opt(/퀸으로 다리우스/);
  fireEvent.keyDown(b, { key: 'Enter' });
  await waitFor(() => expect(where()).toBe('/champion/Darius/counter/Quinn'));
});

test('아래 격자: 한 단어면 걸러서 보여 주고, 두 단어 이상이면 후보 목록이 대신한다', async () => {
  start();
  await type('다리');
  expect(await screen.findByRole('link', { name: '다리우스' })).toBeDefined();
  expect(screen.queryByRole('link', { name: '가렌' })).toBeNull();
  fireEvent.change(await box(), { target: { value: '퀸 다리우스' } });
  expect(screen.queryByText('상대 챔피언')).toBeNull();
  expect(screen.queryByText(/에 맞는 챔피언이 없습니다/)).toBeNull();
});
