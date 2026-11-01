import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeLogin, fakeProposal, fakeState } from './fakeSupabase';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

function Where() { const l = useLocation(); return <output data-testid="where">{l.pathname}</output>; }
const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /><Where /></MemoryRouter>);
const where = () => screen.getByTestId('where').textContent;
const type = (label, value) => fireEvent.change(screen.getByLabelText(label), { target: { value } });
const send = () => fireEvent.click(screen.getByRole('button', { name: '제안 보내기' }));

test('로그인 안 했으면 [새 카운터 제안]은 로그인 화면으로 보낸다', async () => {
  start('/champion/Darius');
  fireEvent.click(await screen.findByRole('link', { name: '+ 새 카운터 제안' }));
  expect(await screen.findByRole('heading', { name: '로그인' })).toBeDefined();
  expect(where()).toBe('/login');
});

test('새 카운터 제안: 이미 있는 카운터는 못 고르고, 필수 칸을 채워야 보내지고, 보내면 /me에 대기 중으로 보인다', async () => {
  fakeLogin('u-old');
  start('/champion/Darius');
  fireEvent.click(await screen.findByRole('link', { name: '+ 새 카운터 제안' }));
  expect(await screen.findByRole('heading', { name: '다리우스을(를) 이기는 챔피언 제안' })).toBeDefined();
  expect(screen.getByRole('button', { name: /퀸 \(등록됨\)/ }).disabled).toBe(true);
  expect(screen.queryByRole('button', { name: /다리우스/ })).toBeNull(); // 자기 자신은 목록에 없음

  fireEvent.change(screen.getByLabelText('이기는 챔피언 검색'), { target: { value: 'ㄱㄹ' } });
  fireEvent.click(screen.getByRole('button', { name: '가렌' }));
  expect(screen.getByRole('heading', { name: /가렌\(으\)로 다리우스 잡는 법/ })).toBeDefined();

  send();
  expect(screen.getByRole('alert').textContent).toBe('한 줄 요약을 적어 주세요.');
  type('한 줄 요약 (필수)', ' 사거리 싸움 ');
  for (const lv of [1, 2, 3, 6, 11]) type(`${lv}레벨 (필수)`, `${lv}렙 공략`);
  send();
  expect(screen.getByRole('alert').textContent).toBe('9레벨 딜교법은 꼭 적어야 해요.');
  type('9레벨 (필수)', '9렙 공략');
  fireEvent.change(screen.getByLabelText('레벨 추가'), { target: { value: '4' } });
  fireEvent.click(screen.getByRole('button', { name: '칸 추가' }));
  type('4레벨', '4렙 추가');
  send();

  expect(await screen.findByRole('heading', { name: /기존유저/ })).toBeDefined();
  expect(where()).toBe('/me');
  expect(fakeState.inserts).toEqual([{
    table: 'edit_proposals',
    values: {
      type: 'new_counter', target_champion: 'Darius', counter_champion: 'Garen', proposer_id: 'u-old',
      content: {
        summary: '사거리 싸움',
        level_notes: { 1: '1렙 공략', 2: '2렙 공략', 3: '3렙 공략', 4: '4렙 추가', 6: '6렙 공략', 9: '9렙 공략', 11: '11렙 공략' },
        lane_cautions: '',
      },
    },
  }]);
  expect(screen.getByText(/새 카운터 제안을 보냈어요. 운영자가 승인하면 반영돼요/)).toBeDefined();
  const row = (await screen.findByText('가렌(으)로 다리우스 잡는 법')).closest('li');
  expect(within(row).getByText('새 카운터')).toBeDefined();
  expect(within(row).getByText('대기 중')).toBeDefined();
});

test('등록 안 된 매치업 화면의 [새 카운터 제안]은 그 챔피언을 미리 골라 둔다', async () => {
  fakeLogin('u-old');
  start('/champion/Darius/counter/Teemo');
  fireEvent.click(await screen.findByRole('link', { name: '+ 새 카운터 제안' }));
  expect(await screen.findByRole('heading', { name: /티모\(으\)로 다리우스 잡는 법/ })).toBeDefined();
  expect(screen.getByRole('button', { name: '다시 고르기' })).toBeDefined();
});

test('DB가 막으면(예: 그 사이 누가 등록) 그 이유를 보여 주고 화면에 머문다', async () => {
  fakeLogin('u-old');
  fakeState.insertError = '이미 등록된 카운터예요. 문서 수정 제안을 이용해 주세요.';
  start('/champion/Darius/propose?counter=Garen');
  await screen.findByLabelText('한 줄 요약 (필수)');
  type('한 줄 요약 (필수)', '요약');
  for (const lv of [1, 2, 3, 6, 9, 11]) type(`${lv}레벨 (필수)`, 'x');
  send();
  expect(await screen.findByText('이미 등록된 카운터예요. 문서 수정 제안을 이용해 주세요.')).toBeDefined();
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
  expect(screen.getByRole('alert').textContent).toBe('지금 문서와 달라진 내용이 없어요.');
  type('라인전 주의사항', 'E 사거리 주의\n궁 조심');
  fireEvent.click(screen.getByRole('button', { name: '4레벨 칸 빼기' }));
  send();
  expect(await screen.findByRole('heading', { name: /기존유저/ })).toBeDefined();
  expect(fakeState.inserts[0].values).toMatchObject({
    type: 'doc_edit', counter_id: 1, target_champion: 'Darius', counter_champion: 'Quinn', base_revision_id: 7,
    content: { lane_cautions: 'E 사거리 주의\n궁 조심', level_notes: { 1: '1렙 내용', 2: '2렙', 3: '3렙', 6: '6렙', 9: '9렙', 11: '11렙' } },
  });
});

test('/me: 거절된 제안은 거절 사유를, 승인된 제안은 문서 링크를 보여 준다', async () => {
  TABLES.edit_proposals.push(
    fakeProposal({ id: 1, status: 'rejected', reject_reason: '근거가 부족해요', reviewed_at: '2026-11-02T00:00:00Z' }),
    fakeProposal({ id: 2, type: 'new_counter', counter_champion: 'Garen', counter_id: null, status: 'pending' }),
  );
  fakeLogin('u-old');
  start('/me');
  const rejected = (await screen.findByText('거절')).closest('li');
  expect(within(rejected).getByText('거절 사유: 근거가 부족해요')).toBeDefined();
  expect(within(rejected).getByRole('link', { name: '퀸(으)로 다리우스 잡는 법' })).toBeDefined();
  const pending = screen.getByText('가렌(으)로 다리우스 잡는 법').closest('li');
  expect(within(pending).queryByRole('link')).toBeNull(); // 아직 없는 문서라 링크 없음
  expect(within(pending).getByText('대기 중')).toBeDefined();
});
