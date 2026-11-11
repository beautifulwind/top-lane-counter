import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeLogin, fakeProposal, fakeState } from './fakeSupabase';
import { WIKI_PAYLOAD, fillBuild, fillWikiBuild } from './buildHelpers';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

function Where() { const l = useLocation(); return <output data-testid="where">{l.pathname}</output>; }
const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /><Where /></MemoryRouter>);
const where = () => screen.getByTestId('where').textContent;
const type = (label, value) => fireEvent.change(screen.getByLabelText(label), { target: { value } });
const send = () => fireEvent.click(screen.getByRole('button', { name: '제안' }));

test('로그인 안 했으면 [새 카운터 제안]은 로그인 화면으로 보낸다', async () => {
  start('/champion/Darius');
  fireEvent.click(await screen.findByRole('link', { name: '+ 카운터 등록' }));
  expect(await screen.findByRole('heading', { name: '로그인 · 가입' })).toBeDefined();
  expect(where()).toBe('/login');
});

test('새 상대법(038): 두 챔피언을 고르고 첫 빌드를 채워 등록하면 create_matchup → 바로 그 상대법 화면', async () => {
  fakeLogin('u-old');
  start('/champion/Darius');
  fireEvent.click(await screen.findByRole('link', { name: '+ 카운터 등록' }));
  expect(await screen.findByRole('heading', { name: '새 상대법 등록' })).toBeDefined();
  expect(where()).toBe('/matchup/new');
  // 상대 챔피언은 미리 골라져 있고, 다시 고를 수 있다
  expect(screen.getByText('다리우스', { selector: '.picked-text strong' })).toBeDefined();
  expect(screen.getByRole('button', { name: '상대 챔피언 다시 고르기' })).toBeDefined();
  const mine = await screen.findByRole('list', { name: '플레이할 챔피언 고르기' });
  expect(within(mine).queryByRole('button', { name: /다리우스/ })).toBeNull(); // 자기 자신은 목록에 없음
  // 이미 있는 상대법을 고르면 그 상대법·새 빌드로 안내한다 (입력 칸은 안 보인다)
  fireEvent.click(within(mine).getByRole('button', { name: '퀸 (등록됨)' }));
  expect(screen.getByText('이미 있는 상대법입니다. 그 상대법에 새 빌드를 더해 주세요.')).toBeDefined();
  expect(screen.getByRole('link', { name: '+ 새 빌드' }).getAttribute('href')).toBe('/champion/Darius/counter/Quinn/build/new');
  expect(screen.queryByLabelText('한 줄 요약 (필수)')).toBeNull();
  fireEvent.click(screen.getByRole('button', { name: '플레이할 챔피언 다시 고르기' }));

  fireEvent.change(screen.getByLabelText('플레이할 챔피언 검색'), { target: { value: 'ㄱㄹ' } });
  fireEvent.click(screen.getByRole('button', { name: '가렌' }));
  expect(screen.getByRole('heading', { name: '3. 가렌으로 다리우스 이기는 법 — 첫 빌드' })).toBeDefined();
  const register = () => fireEvent.click(screen.getByRole('button', { name: '상대법 등록' }));
  register();
  expect(screen.getByRole('alert')).toHaveTextContent('한 줄 요약을 적어 주세요.');
  type('한 줄 요약 (필수)', ' 사거리 싸움 ');
  // 필수 칸은 1/2/3/6뿐, 9·11레벨 칸은 처음부터 없다 (010)
  expect(screen.queryByLabelText(/^9레벨/)).toBeNull();
  register();
  expect(screen.getByRole('alert')).toHaveTextContent('주 경로를 골라 주세요.'); // 요약 다음은 빌드 (화면 순서)
  fillBuild({ withSkill: true });
  register();
  expect(screen.getByRole('alert')).toHaveTextContent('1레벨 딜교법은 꼭 적어야 합니다.');
  for (const lv of [1, 2, 3, 6]) type(`${lv}레벨 (필수)`, `${lv}렙 공략`);
  fireEvent.change(screen.getByLabelText('레벨 추가'), { target: { value: '4' } });
  fireEvent.click(screen.getByRole('button', { name: '칸 추가' }));
  type('4레벨', '4렙 추가');
  expect(screen.getByRole('article', { name: '빌드: 기존유저' })).toBeDefined(); // 미리보기
  register();

  await vi.waitFor(() => expect(where()).toBe('/champion/Darius/counter/Garen'));
  expect(fakeState.rpcCalls.filter((c) => c.name === 'create_matchup').map((c) => c.args)).toEqual([{
    p_target: 'Darius', p_mine: 'Garen',
    p_build: WIKI_PAYLOAD({ summary: '사거리 싸움', level_notes: { 1: '1렙 공략', 2: '2렙 공략', 3: '3렙 공략', 4: '4렙 추가', 6: '6렙 공략' } }),
  }]);
  expect(fakeState.inserts).toEqual([]); // 예전 승인 대기 제안은 쓰지 않는다
  expect(await screen.findByText('새 상대법을 등록했습니다.')).toBeDefined();
  expect(screen.getByRole('tab', { name: '빌드 1 추천 0' })).toHaveAttribute('aria-selected', 'true');
  expect(screen.getByText('사거리 싸움')).toBeDefined();
});

test('등록 안 된 상대법 화면의 [+ 카운터 등록]은 두 챔피언을 미리 골라 둔다 (예전 주소도 새 화면으로)', async () => {
  fakeLogin('u-old');
  start('/champion/Darius/counter/Teemo');
  expect(await screen.findByText('아직 등록되지 않은 카운터입니다. 지금 등록하면 바로 공개됩니다.')).toBeDefined();
  fireEvent.click(screen.getByRole('link', { name: '+ 카운터 등록' }));
  expect(await screen.findByRole('heading', { name: '3. 티모로 다리우스 이기는 법 — 첫 빌드' })).toBeDefined();
  expect(screen.getByText('티모', { selector: '.picked-text strong' })).toBeDefined();
  cleanup();
  start('/champion/Darius/propose?counter=Garen');
  expect(await screen.findByRole('heading', { name: '3. 가렌으로 다리우스 이기는 법 — 첫 빌드' })).toBeDefined();
  expect(where()).toBe('/matchup/new');
});

test('DB가 막으면(예: 그 사이 누가 등록) 그 이유를 보여 주고 화면에 머문다', async () => {
  fakeLogin('u-old');
  fakeState.rpcError = '이미 있는 상대법입니다. 그 상대법에 새 빌드를 더해 주세요.';
  start('/matchup/new?target=Darius&mine=Garen');
  await screen.findByLabelText('한 줄 요약 (필수)');
  fillWikiBuild();
  fireEvent.click(screen.getByRole('button', { name: '상대법 등록' }));
  expect(await screen.findByRole('alert')).toHaveTextContent('이미 있는 상대법입니다. 그 상대법에 새 빌드를 더해 주세요.');
  expect(where()).toBe('/matchup/new');
  expect(screen.getByRole('button', { name: '상대법 등록' })).toBeEnabled();
});

test('문서 수정 제안: 지금 문서가 채워져 있고, 바뀐 게 없으면 못 보내고, 보내면 보고 있던 버전도 같이 보낸다', async () => {
  fakeLogin('u-old');
  start('/champion/Darius/counter/Quinn/edit'); // 2b에서 끈다 (상대법 화면에는 링크 없음)
  expect(await screen.findByRole('heading', { name: /수정 제안/ })).toBeDefined();
  expect(screen.getByLabelText('한 줄 요약 (필수)').value).toBe('사거리로 일방적인 견제');
  expect(screen.getByLabelText('4레벨').value).toBe('4렙 추가');

  send();
  expect(screen.getByRole('alert').textContent).toBe('지금 문서와 달라진 내용이 없습니다.');
  type('특이사항', 'E 사거리 주의\n궁 조심');
  fireEvent.click(screen.getByRole('button', { name: '4레벨 칸 빼기' }));
  send();
  expect(await screen.findByRole('heading', { name: /기존유저/ })).toBeDefined();
  expect(fakeState.inserts[0].values).toMatchObject({
    type: 'doc_edit', counter_id: 1, target_champion: 'Darius', counter_champion: 'Quinn', base_revision_id: 7,
    content: { lane_cautions: 'E 사거리 주의\n궁 조심', level_notes: { 1: '1렙 내용', 2: '2렙', 3: '3렙', 6: '6렙', 9: '9렙', 11: '11렙' } },
  });
});

test('문서 수정 제안·새 카운터 제안에도 [취소] → 원래 보던 화면으로 (보내지 않음)', async () => {
  fakeLogin('u-old');
  start('/champion/Darius/counter/Quinn/edit');
  await screen.findByRole('heading', { name: /수정 제안/ });
  fireEvent.click(screen.getByRole('link', { name: '취소' }));
  await vi.waitFor(() => expect(where()).toBe('/champion/Darius/counter/Quinn'));
  cleanup();
  start('/champion/Darius/propose?counter=Garen');
  fireEvent.click(await screen.findByRole('link', { name: '취소' }));
  await vi.waitFor(() => expect(where()).toBe('/champion/Darius'));
  expect(fakeState.inserts).toEqual([]);
});

test('010: 예전 문서의 9·11레벨은 추가 레벨로 보이고, 수정 제안에서 뺄 수 있다', async () => {
  fakeLogin('u-old');
  start('/champion/Darius/counter/Quinn');
  // 문서 보기: 9·11레벨 내용은 그대로 보이지만 필수 표시(req)는 1/2/3/6에만
  const lv9 = (await screen.findByText('9레벨')).closest('.level');
  expect(lv9.className).toBe('level');
  expect(screen.getByText('6레벨').closest('.level').className).toBe('level req');

  expect(screen.queryByRole('link', { name: '문서 수정 제안' })).toBeNull(); // 038: 빌드마다 [빌드 수정]
  cleanup();
  start('/champion/Darius/counter/Quinn/edit');
  expect(await screen.findByRole('heading', { name: /수정 제안/ })).toBeDefined();
  expect(screen.getByLabelText('9레벨').value).toBe('9렙');
  expect(screen.queryByLabelText('9레벨 (필수)')).toBeNull();
  fireEvent.click(screen.getByRole('button', { name: '9레벨 칸 빼기' }));
  fireEvent.click(screen.getByRole('button', { name: '11레벨 칸 빼기' }));
  expect(screen.queryByRole('button', { name: '6레벨 칸 빼기' })).toBeNull();
  send();
  expect(await screen.findByRole('heading', { name: /기존유저/ })).toBeDefined();
  expect(fakeState.inserts[0].values.content.level_notes).toEqual({ 1: '1렙 내용', 2: '2렙', 3: '3렙', 4: '4렙 추가', 6: '6렙' });
});

test('/me: 거절된 제안은 거절 사유를, 승인된 제안은 문서 링크를 보여 준다', async () => {
  TABLES.edit_proposals.push(
    fakeProposal({ id: 1, status: 'rejected', reject_reason: '근거가 부족합니다', reviewed_at: '2026-11-02T00:00:00Z' }),
    fakeProposal({ id: 2, type: 'new_counter', counter_champion: 'Garen', counter_id: null, status: 'pending' }),
  );
  fakeLogin('u-old');
  start('/me');
  const rejected = (await screen.findByText('거절')).closest('li');
  expect(within(rejected).getByText('거절 사유: 근거가 부족합니다')).toBeDefined();
  expect(within(rejected).getByRole('link', { name: '퀸으로 다리우스 이기는 법' }).getAttribute('href')).toBe('/me/proposals/1');
  expect(within(rejected).getByRole('link', { name: '문서 보기' }).getAttribute('href')).toBe('/champion/Darius/counter/Quinn');
  const pending = screen.getByText('가렌으로 다리우스 이기는 법').closest('li');
  expect(within(pending).queryByRole('link', { name: '문서 보기' })).toBeNull(); // 아직 없는 문서라 문서 링크 없음
  expect(within(pending).getByRole('link', { name: '수정' }).getAttribute('href')).toBe('/me/proposals/2/edit');
  expect(within(pending).getByText('대기 중')).toBeDefined();
});
