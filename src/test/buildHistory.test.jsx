// 043 2b: 운영자 빌드 수정 기록 자세히(/admin/builds/:id/history — 전후 비교·되돌리기·회원 정보 링크),
// 빌드 ⋮ "수정 기록 자세히"(운영자만), 감독관 빌드 숨기기(일반 회원·탈퇴한 분이 처음 만든 빌드만)·운영자 페이지의 숨긴 빌드 다시 공개
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeLogin, fakeState } from './fakeSupabase';
import { moreNames, pickMore } from './moreMenu';

const MATCHUP = '/champion/Darius/counter/Quinn';

function Where() {
  const { pathname, search } = useLocation();
  return <div data-testid="where">{pathname}{search}</div>;
}
function start(path) {
  render(
    <MemoryRouter initialEntries={[path]}>
      <AppRoutes />
      <Where />
    </MemoryRouter>,
  );
}
const where = () => screen.getByTestId('where').textContent;
const asOperator = () => fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0 });
const asModerator = () => fakeLogin('u-mod', { nickname: '감독', role: 'moderator', level: 3 });

const snap = (core, summary = '요약') => ({
  name: null, patch: '14.1.1', runes: null, summoner_spells: ['SummonerFlash'], starting_items: ['1055'], core_items: core,
  max_skill: 'Q', summary, level_notes: { 1: '1렙' }, lane_cautions: '',
});
const V1 = snap(['6672', '3006']);
const V2 = snap(['6672', '3047'], '고친 요약');
const V3 = snap(['3053', '3047'], '장난');
const editor = (id, nickname) => ({ id, nickname, role: 'user', is_guest: false, level: 5, main_title: null });

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
  fakeState.buildRevisions[102] = {
    build: {
      id: 102, counter_id: 1, seq: 2, name: null, status: 'approved', version: 3, is_first: false, target_champion: 'Darius',
      counter_champion: 'Quinn', counter_status: 'approved', author: editor('u-102', '탑고수'), current: V3,
    },
    revisions: [
      { id: 11, kind: 'create', version: 1, revert_of: null, created_at: '2026-11-01T00:00:00Z', editor: editor('u-102', '탑고수'), before: null, after: V1 },
      { id: 12, kind: 'edit', version: 2, revert_of: null, created_at: '2026-11-02T00:00:00Z', editor: null, before: V1, after: V2 },
      { id: 13, kind: 'edit', version: 3, revert_of: null, created_at: '2026-11-03T00:00:00Z', editor: editor('u-9', '장난꾼'), before: V2, after: V3 },
    ],
  };
});
afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

test('운영자: 빌드 ⋮ "수정 기록 자세히" → 수정 기록 화면', async () => {
  asOperator();
  start(`${MATCHUP}?build=102`);
  await screen.findByText(/퀸으로 다리우스 이기는 법/);
  expect(moreNames(screen, '빌드 2 더보기')).toEqual(['오류 신고', '빌드 숨기기', '수정 기록 자세히']);
  pickMore(screen, '수정 기록 자세히', '빌드 2 더보기');
  expect(where()).toBe('/admin/builds/102/history');
  expect(await screen.findByRole('heading', { name: '빌드 수정 기록' })).toBeDefined();
});

test('수정 기록: 최근 순, 고친 분은 회원 정보로, 탈퇴한 이용자, 지금 내용 표시, 전후 비교는 아이템 이름으로', async () => {
  asOperator();
  start('/admin/builds/102/history');
  const list = await screen.findByRole('list', { name: '빌드 수정 기록' });
  const rows = within(list).getAllByRole('listitem');
  expect(rows.map((r) => r.getAttribute('aria-label'))).toEqual(['v3 수정', 'v2 수정', 'v1 처음 등록']);
  expect(rows[0].textContent).toMatch(/지금 내용/);
  expect(within(rows[0]).getByRole('link', { name: /장난꾼/ }).getAttribute('href')).toBe('/admin/members/u-9');
  expect(rows[1].textContent).toMatch(/고친 분: 탈퇴한 이용자/);
  expect(within(rows[0]).queryByRole('button', { name: '이 시점으로 되돌리기' })).toBeNull(); // 지금과 같은 기록
  expect(screen.getAllByRole('link', { name: /탑고수/ })[0].getAttribute('href')).toBe('/admin/members/u-102'); // 처음 만든 분

  fireEvent.click(within(rows[0]).getByRole('button', { name: '전후 비교' }));
  const core = within(rows[0]).getByRole('region', { name: '템트리 변경' });
  expect(core.textContent).toMatch(/− 크라켄 학살자/);
  expect(core.textContent).toMatch(/\+ 스테락의 도전/);
  expect(within(rows[0]).getByRole('region', { name: '한 줄 요약 변경' }).textContent).toMatch(/\+ 장난/);
});

test('되돌리기: 지금 → 되돌린 뒤 비교, 사유 필수 → revert_build(본 버전), 결과 안내, 목록에 "되돌림" 줄', async () => {
  asOperator();
  fakeState.revertRemoved = 1;
  start('/admin/builds/102/history');
  const row = await screen.findByRole('listitem', { name: 'v2 수정' });
  fireEvent.click(within(row).getByRole('button', { name: '이 시점으로 되돌리기' }));
  expect(within(row).getByRole('region', { name: '한 줄 요약 변경' }).textContent).toMatch(/− 장난[\s\S]*\+ 고친 요약/);
  const confirm = within(row).getByRole('button', { name: '되돌리기 확정' });
  expect(confirm).toBeDisabled();
  fireEvent.change(within(row).getByLabelText(/되돌리는 사유/), { target: { value: '훼손 복구' } });
  fireEvent.click(confirm);
  expect(await screen.findByText('v2 시점으로 되돌렸습니다. 지금 버전 v4 · 기여자에서 1명을 뺐습니다.')).toBeDefined();
  expect(fakeState.rpcCalls).toContainEqual({ name: 'revert_build', args: { p_build: 102, p_revision: 12, p_version: 3, p_note: '훼손 복구' } });
  const top = await screen.findByRole('listitem', { name: 'v4 되돌림 (v2 시점으로)' });
  expect(top.textContent).toMatch(/되돌린 분: \(운\)영자/); // 빌드 기록은 레벨·칭호 없이 닉네임만 (046)
  expect(top.textContent).toMatch(/지금 내용/);
});

test('그사이 누가 고쳤으면(TL412) 이유와 [최신 기록 다시 불러오기]', async () => {
  asOperator();
  start('/admin/builds/102/history');
  const row = await screen.findByRole('listitem', { name: 'v1 처음 등록' });
  fakeState.buildRevisions[102].build.version = 4; // 화면이 본 뒤에 누가 고침
  fireEvent.click(within(row).getByRole('button', { name: '이 시점으로 되돌리기' }));
  fireEvent.change(within(row).getByLabelText(/되돌리는 사유/), { target: { value: '복구' } });
  fireEvent.click(within(row).getByRole('button', { name: '되돌리기 확정' }));
  expect(await within(row).findByText(/다른 분이 먼저 수정했습니다/)).toBeDefined();
  fireEvent.click(screen.getByRole('button', { name: '최신 기록 다시 불러오기' }));
  expect(await screen.findByRole('listitem', { name: 'v1 처음 등록' })).toBeDefined();
  expect(screen.queryByRole('button', { name: '최신 기록 다시 불러오기' })).toBeNull();
});

test('기록이 많으면 [이전 기록 더 보기]로 이어 붙인다', async () => {
  asOperator();
  const d = fakeState.buildRevisions[102];
  for (let i = 0; i < 20; i += 1) {
    d.revisions.push({ id: 100 + i, kind: 'edit', version: 4 + i, revert_of: null, created_at: '2026-11-05T00:00:00Z', editor: null, before: V3, after: V3 });
  }
  d.build.version = 23;
  start('/admin/builds/102/history');
  const list = await screen.findByRole('list', { name: '빌드 수정 기록' });
  expect(within(list).getAllByRole('listitem')).toHaveLength(20);
  fireEvent.click(screen.getByRole('button', { name: '이전 기록 더 보기' }));
  await vi.waitFor(() => expect(within(list).getAllByRole('listitem')).toHaveLength(23));
  expect(screen.queryByRole('button', { name: '이전 기록 더 보기' })).toBeNull();
});

test('감독관·일반 회원은 수정 기록 화면을 볼 수 없고, ⋮에도 "수정 기록 자세히"가 없다', async () => {
  asModerator();
  start('/admin/builds/102/history');
  expect(await screen.findByText(/운영자만 볼 수 있습니다/)).toBeDefined();
  cleanup();
  start(`${MATCHUP}?build=102`);
  await screen.findByText(/퀸으로 다리우스 이기는 법/);
  expect(moreNames(screen, '빌드 2 더보기')).not.toContain('수정 기록 자세히');
});

test('감독관: 일반 회원·탈퇴한 분이 처음 만든 빌드는 ⋮ "빌드 숨기기", 운영진이 만든 빌드는 없다', async () => {
  asModerator();
  start(`${MATCHUP}?build=102`);
  await screen.findByText(/퀸으로 다리우스 이기는 법/);
  expect(moreNames(screen, '빌드 2 더보기')).toEqual(['오류 신고', '빌드 숨기기']);
  pickMore(screen, '빌드 숨기기', '빌드 2 더보기');
  fireEvent.change(screen.getByLabelText(/숨기는 사유/), { target: { value: '장난 빌드' } });
  fireEvent.click(screen.getByRole('button', { name: '숨기기 확정' }));
  await screen.findByText(/빌드를 숨겼습니다/);
  expect(fakeState.rpcCalls).toContainEqual({ name: 'hide_build', args: { p_id: 102, p_reason: '장난 빌드' } });
  cleanup();
  start(`${MATCHUP}?build=101`);
  await screen.findByText(/퀸으로 다리우스 이기는 법/);
  expect(moreNames(screen, '빌드 1 더보기')).toEqual(['오류 신고', '빌드 숨기기']); // 탈퇴한 분이 만든 빌드
  cleanup();
  start(`${MATCHUP}?build=105`);
  await screen.findByText(/퀸으로 다리우스 이기는 법/);
  expect(moreNames(screen, '빌드 5 더보기')).toEqual(['오류 신고']); // 운영자가 만든 빌드
});

test('감독관 운영자 페이지: 숨긴 빌드 칸에 [다시 공개](자세히·수정 기록 링크 없음)', async () => {
  const b = TABLES.builds.find((x) => x.id === 103);
  Object.assign(b, { status: 'hidden', hide_reason: '장난', hidden_at: '2026-11-10T00:00:00Z' });
  asModerator();
  start('/admin');
  const row = await screen.findByRole('listitem', { name: /\[숨긴 빌드\]/ });
  expect(within(row).queryByRole('link', { name: '자세히' })).toBeNull();
  expect(within(row).queryByRole('link', { name: '수정 기록' })).toBeNull();
  fireEvent.click(within(row).getByRole('button', { name: '다시 공개' }));
  fireEvent.change(within(row).getByLabelText(/다시 공개 메모/), { target: { value: '오해였음' } });
  fireEvent.click(within(row).getByRole('button', { name: '다시 공개 확정' }));
  await screen.findByText(/빌드를 다시 공개했습니다/);
  expect(fakeState.rpcCalls).toContainEqual({ name: 'restore_build', args: { p_id: 103, p_note: '오해였음' } });
});

test('운영자 운영자 페이지: 숨긴 빌드 줄에 [수정 기록] 링크', async () => {
  const b = TABLES.builds.find((x) => x.id === 103);
  Object.assign(b, { status: 'hidden', hide_reason: '장난', hidden_at: '2026-11-10T00:00:00Z' });
  asOperator();
  start('/admin');
  const row = await screen.findByRole('listitem', { name: /\[숨긴 빌드\]/ });
  expect(within(row).getByRole('link', { name: '수정 기록' }).getAttribute('href')).toBe('/admin/builds/103/history');
});
