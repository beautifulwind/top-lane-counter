import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeLogin, fakeProposal, fakeState } from './fakeSupabase';
import { fillBuild, pick } from './buildHelpers';

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

test('새 카운터 제안: 이미 있는 카운터는 못 고르고, 필수 칸을 채워야 보내지고, 보내면 /me에 대기 중으로 보인다', async () => {
  fakeLogin('u-old');
  start('/champion/Darius');
  fireEvent.click(await screen.findByRole('link', { name: '+ 카운터 등록' }));
  expect(await screen.findByRole('heading', { name: '다리우스 카운터 선택' })).toBeDefined();
  expect(screen.getByRole('button', { name: /퀸 \(등록됨\)/ }).disabled).toBe(true);
  expect(screen.queryByRole('button', { name: /다리우스/ })).toBeNull(); // 자기 자신은 목록에 없음

  fireEvent.change(screen.getByLabelText('카운터 챔피언 검색'), { target: { value: 'ㄱㄹ' } });
  fireEvent.click(screen.getByRole('button', { name: '가렌' }));
  expect(screen.getByRole('heading', { name: '2. 상대법' })).toBeDefined(); // 022: 제목(OO로 OO 이기는 법) 대신 "상대법"
  expect(screen.queryByRole('heading', { name: /가렌으로 다리우스 이기는 법/ })).toBeNull();

  send();
  expect(screen.getByRole('alert').textContent).toBe('한 줄 요약을 적어 주세요.');
  type('한 줄 요약 (필수)', ' 사거리 싸움 ');
  // 필수 칸은 1/2/3/6뿐, 9·11레벨 칸은 처음부터 없다 (010)
  expect(screen.queryByLabelText(/^9레벨/)).toBeNull();
  expect(screen.queryByLabelText(/^11레벨/)).toBeNull();
  for (const lv of [1, 2, 3]) type(`${lv}레벨 (필수)`, `${lv}렙 공략`);
  send();
  expect(screen.getByRole('alert').textContent).toBe('6레벨 딜교법은 꼭 적어야 합니다.');
  type('6레벨 (필수)', '6렙 공략');
  fireEvent.change(screen.getByLabelText('레벨 추가'), { target: { value: '4' } });
  fireEvent.click(screen.getByRole('button', { name: '칸 추가' }));
  type('4레벨', '4렙 추가');
  send();
  // 글을 다 써도 빌드가 없으면 못 보낸다
  expect(screen.getByRole('alert').textContent).toBe('빌드를 마저 채워 주세요: 주 경로를 골라 주세요.');
  expect(fakeState.inserts).toEqual([]);
  fillBuild();
  send();
  expect(screen.getByRole('alert').textContent).toBe('빌드를 마저 채워 주세요: 선마(첫 번째로 마스터할 스킬)를 골라 주세요.');
  pick('선마 (첫 번째로 마스터할 스킬)', '선마 Q');
  expect(screen.getByRole('article', { name: '빌드: 기존유저' })).toBeDefined(); // 미리보기
  send();

  expect(await screen.findByRole('heading', { name: /기존유저/ })).toBeDefined();
  expect(where()).toBe('/me');
  expect(fakeState.inserts).toEqual([{
    table: 'edit_proposals',
    values: {
      type: 'new_counter', target_champion: 'Darius', counter_champion: 'Garen', proposer_id: 'u-old',
      content: {
        summary: '사거리 싸움',
        level_notes: { 1: '1렙 공략', 2: '2렙 공략', 3: '3렙 공략', 4: '4렙 추가', 6: '6렙 공략' },
        lane_cautions: '',
      },
      build: {
        runes: { primaryPath: 8000, keystone: 8010, primary: [9111, 9104, 8299], secondaryPath: 8400, secondary: [8446, 8444], shards: [5005, 5008, 5011] },
        summoner_spells: ['SummonerFlash', 'SummonerTeleport'], starting_items: ['1055', '2003'], core_items: ['3053', '3047', '6631'],
        max_skill: 'Q', patch: '99.1.1',
      },
    },
  }]);
  expect(screen.getByText(/새 카운터 제안을 보냈습니다. 운영진이 승인하면 반영됩니다/)).toBeDefined();
  const row = (await screen.findByText('가렌으로 다리우스 이기는 법')).closest('li');
  expect(within(row).getByText('새 카운터')).toBeDefined();
  expect(within(row).getByText('대기 중')).toBeDefined();
});

test('등록 안 된 매치업 화면의 [새 카운터 제안]은 그 챔피언을 미리 골라 둔다', async () => {
  fakeLogin('u-old');
  start('/champion/Darius/counter/Teemo');
  fireEvent.click(await screen.findByRole('link', { name: '+ 카운터 등록' }));
  expect(await screen.findByRole('heading', { name: '2. 상대법' })).toBeDefined();
  expect(screen.getByText('티모', { selector: 'strong' })).toBeDefined();
  expect(screen.getByRole('button', { name: '다시 고르기' })).toBeDefined();
});

test('DB가 막으면(예: 그 사이 누가 등록) 그 이유를 보여 주고 화면에 머문다', async () => {
  fakeLogin('u-old');
  fakeState.insertError = '이미 등록된 카운터입니다. 문서 수정 제안을 이용해 주세요.';
  start('/champion/Darius/propose?counter=Garen');
  await screen.findByLabelText('한 줄 요약 (필수)');
  type('한 줄 요약 (필수)', '요약');
  for (const lv of [1, 2, 3, 6]) type(`${lv}레벨 (필수)`, 'x');
  fillBuild({ withSkill: true });
  send();
  expect(await screen.findByText('이미 등록된 카운터입니다. 문서 수정 제안을 이용해 주세요.')).toBeDefined();
  expect(where()).toBe('/champion/Darius/propose');
});

test('문서 수정 제안: 지금 문서가 채워져 있고, 바뀐 게 없으면 못 보내고, 보내면 보고 있던 버전도 같이 보낸다', async () => {
  fakeLogin('u-old');
  start('/champion/Darius/counter/Quinn');
  fireEvent.click(await screen.findByRole('link', { name: '문서 수정 제안' }));
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

  fireEvent.click(screen.getByRole('link', { name: '문서 수정 제안' }));
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
