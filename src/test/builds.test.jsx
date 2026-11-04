import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeBuild, fakeLogin, fakeState } from './fakeSupabase';
import { buildProblem, compareBuilds, emptyBuild, isOutdated } from '../lib/buildContent';
import { fillBuild, pick } from './buildHelpers';
import { sectionCount } from './sectionCount';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

function Where() { const l = useLocation(); return <output data-testid="where">{l.pathname + l.search}</output>; }
const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /><Where /></MemoryRouter>);
const where = () => screen.getByTestId('where').textContent;
const MATCHUP = '/champion/Darius/counter/Quinn';
const asUser = () => fakeLogin('u-old');
const asOperator = () => fakeLogin('u-op', { nickname: '영자(운)', role: 'admin', level: 0, main_title: null });
const card = (nickname) => screen.getByRole('article', { name: `빌드: ${nickname}` });
const rpcCalls = (name) => fakeState.rpcCalls.filter((c) => c.name === name).map((c) => c.args);
const click = (name, root = document.body) => fireEvent.click(within(root).getByRole('button', { name }));

// ---------------- 규칙 ----------------

test('구버전: 패치 앞 두 자리만 비교한다', () => {
  expect(isOutdated('16.21.1', '16.21.3')).toBe(false);
  expect(isOutdated('16.21', '16.21.3')).toBe(false);
  expect(isOutdated('16.20.1', '16.21.1')).toBe(true);
  expect(isOutdated('14.1.1', '99.1.1')).toBe(true);
});

test('정렬: 점수 → 투표 수 → 최신순', () => {
  const b = (id, up, down, day) => ({ id, up, down, created_at: `2026-11-0${day}T00:00:00Z` });
  const list = [b(1, 1, 0, 1), b(2, 3, 2, 1), b(3, 1, 0, 2), b(4, 5, 0, 1), b(5, 0, 3, 3)];
  expect(list.sort(compareBuilds).map((x) => x.id)).toEqual([4, 2, 3, 1, 5]);
});

test('빈 빌드는 고를 것을 차례로 알려 준다', () => {
  expect(buildProblem(emptyBuild())).toBe('주 경로를 골라 주세요.');
});

// ---------------- 매치업 문서: 투표 ----------------

test('비로그인: 추천을 누르면 로그인 화면으로, [+ 빌드 등록]도 로그인부터', async () => {
  start(MATCHUP);
  await screen.findByText(/퀸으로 다리우스 잡는 법/);
  click('추천 5', card('탑고수'));
  expect(where()).toBe('/login');
  expect(rpcCalls('vote_build')).toEqual([]);
  cleanup();
  start(MATCHUP);
  fireEvent.click(await screen.findByRole('link', { name: '+ 빌드 등록' }));
  expect(await screen.findByRole('heading', { name: '로그인 · 가입' })).toBeDefined();
});

test('추천 → 같은 버튼 다시 누르면 취소 → 비추천으로 바꾸기 (한 사람 한 표)', async () => {
  asUser();
  start(MATCHUP);
  await screen.findByText(/퀸으로 다리우스 잡는 법/);
  const c = card('탑고수');
  click('추천 5', c);
  const up = await within(c).findByRole('button', { name: '추천 6' });
  expect(up.getAttribute('aria-pressed')).toBe('true');
  expect(within(c).getByText('점수 +5')).toBeDefined();
  fireEvent.click(up);
  expect(await within(c).findByRole('button', { name: '추천 5' })).toHaveAttribute('aria-pressed', 'false');
  click('비추천 1', c);
  expect(await within(c).findByRole('button', { name: '비추천 2' })).toHaveAttribute('aria-pressed', 'true');
  expect(rpcCalls('vote_build')).toEqual([
    { p_build_id: 102, p_value: 1 }, { p_build_id: 102, p_value: null }, { p_build_id: 102, p_value: -1 },
  ]);
});

test('내가 이미 누른 표가 보이고, 내 빌드에는 못 누른다', async () => {
  TABLES.build_votes.push({ build_id: 103, user_id: 'u-old', value: 1 });
  TABLES.builds.find((b) => b.id === 102).author_id = 'u-old';
  asUser();
  start(MATCHUP);
  await screen.findByText(/퀸으로 다리우스 잡는 법/);
  expect(within(card('칭호없음')).getByRole('button', { name: '추천 2' })).toHaveAttribute('aria-pressed', 'true');
  const mine = card('탑고수');
  expect(within(mine).getByText('내 빌드')).toBeDefined();
  expect(within(mine).getByRole('button', { name: '추천 5' })).toBeDisabled();
  expect(within(mine).getByRole('button', { name: '비추천 1' })).toBeDisabled();
});

test('투표 실패하면 이유를 보여 주고 숫자는 그대로', async () => {
  asUser();
  start(MATCHUP);
  await screen.findByText(/퀸으로 다리우스 잡는 법/);
  fakeState.rpcError = '공개된 빌드에만 투표할 수 있습니다.';
  click('추천 5', card('탑고수'));
  expect(await screen.findByRole('alert')).toHaveTextContent('공개된 빌드에만 투표할 수 있습니다.');
  expect(within(card('탑고수')).getByRole('button', { name: '추천 5' })).toBeDefined();
});

test('정렬: 점수가 같으면 투표가 많은 빌드가 먼저', async () => {
  TABLES.builds.find((b) => b.id === 103).up_count = 6; // 점수 6
  TABLES.builds.find((b) => b.id === 102).up_count = 8; // 8 − 1 − 1 = 6, 투표 10
  TABLES.builds.find((b) => b.id === 102).down_count = 2;
  start(MATCHUP);
  await screen.findByText(/퀸으로 다리우스 잡는 법/);
  const authors = [...document.querySelectorAll('.build-author')].map((e) => e.textContent);
  expect(authors).toEqual(['Lv.7 단단묵직 탑고수', 'Lv.3 칭호없음', '(탈퇴한 유저)', 'Lv.0 영자(운)']);
});

test('운영자: 매치업 문서에서 빌드를 바로 숨긴다 (사유 = 확인 단계)', async () => {
  asOperator();
  start(MATCHUP);
  await screen.findByText(/퀸으로 다리우스 잡는 법/);
  const c = card('칭호없음');
  click('빌드 숨기기', c);
  const confirm = within(c).getByRole('button', { name: '숨기기 확정' });
  expect(confirm).toBeDisabled();
  fireEvent.change(within(c).getByLabelText(/숨기는 사유/), { target: { value: ' 아이템이 바뀌었습니다 ' } });
  TABLES.builds.find((b) => b.id === 103).status = 'hidden'; // DB 함수가 한 일
  fireEvent.click(confirm);
  expect(await screen.findByText('빌드를 숨겼습니다. (칭호없음)')).toBeDefined();
  expect(rpcCalls('hide_build')).toEqual([{ p_id: 103, p_reason: '아이템이 바뀌었습니다' }]);
  expect(screen.queryByRole('article', { name: '빌드: 칭호없음' })).toBeNull();
});

test('일반 유저에게는 [빌드 숨기기]가 없다', async () => {
  asUser();
  start(MATCHUP);
  await screen.findByText(/퀸으로 다리우스 잡는 법/);
  expect(screen.queryByRole('button', { name: '빌드 숨기기' })).toBeNull();
});

// ---------------- 빌드 등록 ----------------

test('빌드 등록: 다 고르면 미리보기가 보이고, 보내면 승인 대기로 들어간 뒤 /me로', async () => {
  asUser();
  start(`${MATCHUP}/build/new`);
  await screen.findByRole('heading', { name: /빌드 등록/ });
  fillBuild();
  const send = screen.getByRole('button', { name: '빌드 보내기' });
  expect(send).toBeDisabled();
  expect(screen.getByText('아직 고를 것: 선마(첫 번째로 마스터할 스킬)를 골라 주세요.')).toBeDefined();
  pick('선마 (첫 번째로 마스터할 스킬)', '선마 Q');
  // 022: 핵심 템트리는 끌어서 순서를 바꾼다 (▲▼/← 버튼 없음). 여기서는 [X]로 빼고 다시 넣어 순서를 바꾼다
  const core = screen.getByRole('list', { name: '고른 핵심 템트리' });
  expect(within(core).queryByRole('button', { name: /앞으로|위로|아래로/ })).toBeNull();
  expect(within(core).getByRole('button', { name: '강철판 장화 (끌어서 순서 바꾸기)' }).getAttribute('aria-roledescription')).toBe('끌어서 순서 바꾸기');
  fireEvent.click(screen.getByRole('button', { name: '스테락의 도전 빼기' }));
  fireEvent.click(screen.getByRole('button', { name: '선혈포식자 빼기' }));
  pick('핵심 템트리 고르기', '스테락의 도전');
  pick('핵심 템트리 고르기', '선혈포식자');
  expect(screen.getByRole('article', { name: '빌드: 기존유저' })).toBeDefined();
  expect(send).toBeEnabled();
  fireEvent.click(send);
  await vi.waitFor(() => expect(where()).toBe('/me'));
  expect(await screen.findByText(/퀸으로 다리우스 잡는 법 — 빌드를 보냈습니다\./)).toBeDefined();
  expect(fakeState.inserts).toEqual([{
    table: 'builds',
    values: {
      counter_id: 1, author_id: 'u-old', patch: '99.1.1',
      runes: { primaryPath: 8000, keystone: 8010, primary: [9111, 9104, 8299], secondaryPath: 8400, secondary: [8446, 8444], shards: [5005, 5008, 5011] },
      summoner_spells: ['SummonerFlash', 'SummonerTeleport'],
      starting_items: ['1055', '2003'],
      core_items: ['3047', '3053', '6631'],
      max_skill: 'Q',
    },
  }]);
  // /me "내 빌드"에 대기 중으로 보인다
  const row = await screen.findByRole('listitem', { name: '내 빌드: 퀸으로 다리우스 잡는 법' });
  expect(within(row).getByText('대기 중')).toBeDefined();
});

test('빌드 등록: 상점에서 못 사는 아이템·협곡에 없는 주문은 고르기 목록에 없다', async () => {
  asUser();
  start(`${MATCHUP}/build/new`);
  await screen.findByRole('heading', { name: /빌드 등록/ });
  const core = screen.getByRole('group', { name: '핵심 템트리 고르기' });
  expect(within(core).queryByRole('button', { name: '너만 살 수 있는 아이템' })).toBeNull();
  expect(within(core).queryByRole('button', { name: '칼바람 전용' })).toBeNull();
  expect(within(core).getAllByRole('button', { name: '무한의 대검' })).toHaveLength(1); // 모드별 사본은 하나만
  expect(within(screen.getByRole('group', { name: '소환사 주문' })).queryByRole('button', { name: '표식' })).toBeNull();
  // 초성 검색
  fireEvent.change(screen.getByLabelText('핵심 템트리 검색'), { target: { value: 'ㅁㅎㅇㄷㄱ' } });
  // 검색하면 목록이 검색 결과로 바뀐다 (028: 언제나 고를 수 있는 아이템 전체에서)
  const found = screen.getByRole('group', { name: '핵심 템트리 고르기' });
  expect(within(found).getAllByRole('button').map((b) => b.getAttribute('aria-label'))).toEqual(['무한의 대검']);
});

test('빌드 등록: 보조 룬은 같은 줄이면 바뀌고, 2개를 넘으면 먼저 고른 것이 빠진다 / 핵심 템트리는 중복 불가', async () => {
  asUser();
  start(`${MATCHUP}/build/new`);
  await screen.findByRole('heading', { name: /빌드 등록/ });
  pick('보조 경로', '보조 경로 지배');
  const group = '보조 룬 (서로 다른 줄에서 2개)';
  const pressed = () => within(screen.getByRole('group', { name: group })).getAllByRole('button')
    .filter((b) => b.getAttribute('aria-pressed') === 'true').map((b) => b.getAttribute('aria-label'));
  pick(group, '급습');
  pick(group, '비열한 한 방'); // 같은 1줄 → 바뀜
  expect(pressed()).toEqual(['비열한 한 방']);
  pick(group, '좀비 와드');
  pick(group, '궁극의 사냥꾼'); // 3개째 → 먼저 고른 것(비열한 한 방)이 빠짐
  expect(pressed()).toEqual(['좀비 와드', '궁극의 사냥꾼']);
  pick('핵심 템트리 고르기', '선혈포식자');
  expect(within(screen.getByRole('group', { name: '핵심 템트리 고르기' })).getByRole('button', { name: '선혈포식자' })).toBeDisabled();
  pick('시작 아이템 고르기', '체력 물약');
  expect(within(screen.getByRole('group', { name: '시작 아이템 고르기' })).getByRole('button', { name: '체력 물약' })).toBeEnabled();
});

test('빌드 등록: DB가 거절하면 이유를 보여 주고 그대로 남는다', async () => {
  asUser();
  start(`${MATCHUP}/build/new`);
  await screen.findByRole('heading', { name: /빌드 등록/ });
  fillBuild();
  pick('선마 (첫 번째로 마스터할 스킬)', '선마 Q');
  fakeState.insertError = '이 매치업에 이미 승인 대기 중인 내 빌드가 있습니다. 처리된 뒤에 다시 등록해 주세요.';
  fireEvent.click(screen.getByRole('button', { name: '빌드 보내기' }));
  expect(await screen.findByRole('alert')).toHaveTextContent('이미 승인 대기 중인 내 빌드가 있습니다');
  expect(where()).toBe(`${MATCHUP}/build/new`);
  expect(screen.getByRole('button', { name: '빌드 보내기' })).toBeEnabled();
});

test('[이 빌드로 다시 쓰기]: 내 빌드 내용이 채워진 채로 새 빌드를 보낸다 (원래 빌드는 그대로)', async () => {
  TABLES.builds.push(fakeBuild(110, { nickname: '기존유저', level: 1, main_title: null }, {
    author_id: 'u-old', status: 'hidden', hide_reason: '아이템이 바뀌었습니다', hidden_at: '2026-11-05T00:00:00Z', up_count: 3,
  }));
  asUser();
  start('/me');
  const row = await screen.findByRole('listitem', { name: '내 빌드: 퀸으로 다리우스 잡는 법' });
  expect(within(row).getByText('숨김')).toBeDefined();
  expect(within(row).getByText(/숨긴 사유: 아이템이 바뀌었습니다/)).toBeDefined();
  expect(within(row).getByLabelText('추천 3 · 비추천 0')).toBeDefined();
  fireEvent.click(within(row).getByRole('link', { name: '이 빌드로 다시 쓰기' }));
  expect(await screen.findByText(/내 빌드 내용을 채워 뒀습니다/)).toBeDefined();
  expect(where()).toBe(`${MATCHUP}/build/new?from=110`);
  fireEvent.click(screen.getByRole('button', { name: '광전사의 군화 빼기' }));
  pick('핵심 템트리 고르기', '칠흑의 양날 도끼');
  fireEvent.click(screen.getByRole('button', { name: '빌드 보내기' }));
  await vi.waitFor(() => expect(where()).toBe('/me'));
  expect(fakeState.inserts[0].values.core_items).toEqual(['6672', '3031', '3071']);
  expect(fakeState.inserts[0].values.runes.keystone).toBe(8005);
  expect(TABLES.builds.find((b) => b.id === 110).status).toBe('hidden');
});

test('남의 빌드 id로는 채워지지 않는다', async () => {
  asUser();
  start(`${MATCHUP}/build/new?from=102`);
  expect(await screen.findByText(/불러올 내 빌드를 찾지 못했습니다/)).toBeDefined();
  expect(screen.getByRole('button', { name: '빌드 보내기' })).toBeDisabled();
});

// ---------------- /me: 내 빌드 + 알림 ----------------

test('/me 내 빌드: 상태별 메모 (알림은 /notifications — "새 알림" 태그 없음, 읽음 처리 안 함)', async () => {
  const me = { nickname: '기존유저', level: 1, main_title: null };
  TABLES.builds.push(
    fakeBuild(111, me, { author_id: 'u-old', approve_note: '깔끔합니다', reviewed_at: '2026-11-04T00:00:00Z', up_count: 4, down_count: 1 }),
    fakeBuild(112, me, { author_id: 'u-old', status: 'rejected', reject_reason: '이미 있는 빌드', created_at: '2026-11-06T00:00:00Z' }),
  );
  TABLES.notifications.push(
    { id: 1, user_id: 'u-old', kind: 'build_approved', build_id: 111, proposal_id: null, message: '깔끔합니다', created_at: '2026-11-04T00:00:00Z', read_at: null },
  );
  asUser();
  start('/me');
  const rows = await screen.findAllByRole('listitem', { name: '내 빌드: 퀸으로 다리우스 잡는 법' });
  expect(rows).toHaveLength(2);
  const [rejected, approved] = rows; // 최근 순
  expect(within(rejected).getByText('거절 사유: 이미 있는 빌드')).toBeDefined();
  expect(within(rejected).queryByText('새 알림')).toBeNull();
  expect(within(approved).getByText('공개')).toBeDefined();
  expect(within(approved).getByText('승인 메모: 깔끔합니다')).toBeDefined();
  expect(within(approved).queryByText('새 알림')).toBeNull();
  expect(within(approved).getByRole('link', { name: '퀸으로 다리우스 잡는 법' }).getAttribute('href')).toBe('/me/builds/111');
  expect(within(approved).getByRole('link', { name: '문서 보기' }).getAttribute('href')).toBe(`${MATCHUP}#builds`);
  expect(within(rejected).queryByRole('link', { name: '문서 보기' })).toBeNull();
  expect(TABLES.notifications[0].read_at).toBeNull();
});

test('/me 내 제안: 승인 메모는 보이고 "새 알림" 태그는 없다 (알림은 /notifications)', async () => {
  TABLES.edit_proposals.push({
    id: 501, type: 'doc_edit', target_champion: 'Darius', counter_champion: 'Quinn', counter_id: 1, status: 'approved',
    approve_note: '반영했습니다', created_at: '2026-11-01T10:00:00Z', proposer_id: 'u-old', content: {},
  });
  TABLES.notifications.push(
    { id: 2, user_id: 'u-old', kind: 'proposal_approved', proposal_id: 501, build_id: null, message: '반영했습니다', created_at: '2026-11-02T00:00:00Z', read_at: null },
  );
  asUser();
  start('/me');
  expect(await screen.findByText('승인 메모: 반영했습니다')).toBeDefined();
  expect(screen.queryByText('새 알림')).toBeNull();
  expect(screen.getByRole('link', { name: '알림 보기 (새 알림 1개)' }).getAttribute('href')).toBe('/notifications');
});

// ---------------- 운영자 ----------------

const pendingRow = () => screen.getByRole('listitem', { name: '[빌드] 퀸으로 다리우스 잡는 법' });

test('/admin 빌드 승인 대기: 똑같은 빌드가 공개돼 있으면 줄에서 승인 잠금 (거절은 가능)', async () => {
  asOperator();
  start('/admin');
  await sectionCount('빌드 승인 대기', 1);
  const row = pendingRow();
  expect(within(row).getByText(/똑같은 빌드가 이미 공개돼 있습니다/)).toBeDefined();
  expect(within(row).getByRole('button', { name: '승인' })).toBeDisabled();
  click('거절', row);
  fireEvent.change(within(row).getByLabelText(/거절 사유/), { target: { value: '이미 있는 빌드' } });
  TABLES.builds.find((b) => b.id === 104).status = 'rejected';
  click('거절 확정', row);
  expect(await screen.findByText('빌드를 거절했습니다: 퀸으로 다리우스 잡는 법 (대기중)')).toBeDefined();
  expect(rpcCalls('reject_build')).toEqual([{ p_id: 104, p_reason: '이미 있는 빌드', p_version: 1 }]);
  await sectionCount('빌드 승인 대기', 0);
});

test('/admin 빌드 승인 대기: 걸리는 점이 없으면 줄에서 메모 쓰고 바로 승인', async () => {
  TABLES.builds.find((b) => b.id === 104).core_items = ['6631', '3047', '3053'];
  asOperator();
  start('/admin');
  await sectionCount('빌드 승인 대기', 1);
  const row = pendingRow();
  expect(within(row).queryByText(/내용을 \[자세히\]에서/)).toBeNull();
  click('승인', row);
  const confirm = within(row).getByRole('button', { name: '승인 확정' });
  expect(confirm).toBeDisabled();
  fireEvent.change(within(row).getByLabelText(/승인 메모/), { target: { value: '좋습니다' } });
  TABLES.builds.find((b) => b.id === 104).status = 'approved';
  fireEvent.click(confirm);
  expect(await screen.findByText('빌드를 승인했습니다: 퀸으로 다리우스 잡는 법 (대기중)')).toBeDefined();
  expect(rpcCalls('approve_build')).toEqual([{ p_id: 104, p_note: '좋습니다', p_build: null, p_version: 1 }]);
});

test('/admin 빌드 승인 대기: 구버전 패치·게임 데이터에 없는 값·숨긴 카운터는 [자세히]에서만 승인', async () => {
  const b = TABLES.builds.find((x) => x.id === 104);
  Object.assign(b, { core_items: ['6631', '3047', '3053'], patch: '98.3.1' });
  asOperator();
  start('/admin');
  await sectionCount('빌드 승인 대기', 1);
  expect(within(pendingRow()).getByText(/지금 패치\(99\.1\)와 다른 패치\(98\.3\)로 등록됐습니다/)).toBeDefined();
  expect(within(pendingRow()).getByRole('button', { name: '승인' })).toBeDisabled();
  cleanup();
  Object.assign(b, { patch: '99.1.1', core_items: ['6631', '3047', '9999'] });
  start('/admin');
  await sectionCount('빌드 승인 대기', 1);
  expect(within(pendingRow()).getByText(/게임 데이터에 없는 아이템이 있습니다/)).toBeDefined();
  cleanup();
  Object.assign(b, { core_items: ['6631', '3047', '3053'], counter: { ...b.counter, status: 'hidden' } });
  start('/admin');
  await sectionCount('빌드 승인 대기', 1);
  expect(within(pendingRow()).getByText(/숨긴 카운터의 빌드입니다/)).toBeDefined();
});

test('/admin/builds/:id: 구버전이면 경고를 보고 승인할 수 있다', async () => {
  Object.assign(TABLES.builds.find((x) => x.id === 104), {
    core_items: ['6631', '3047', '3053'], patch: '98.3.1',
    logs: [],
  });
  asOperator();
  start('/admin');
  await sectionCount('빌드 승인 대기', 1);
  fireEvent.click(within(pendingRow()).getByRole('link', { name: '자세히' }));
  expect(await screen.findByText(/지금 패치\(99\.1\)와 다른 패치\(98\.3\)로 등록됐습니다/)).toBeDefined();
  click('승인');
  fireEvent.change(screen.getByLabelText(/승인 메모/), { target: { value: '패치 확인함' } });
  click('승인 확정');
  await vi.waitFor(() => expect(where()).toBe('/admin'));
  expect(await screen.findByText('빌드를 승인했습니다: 퀸으로 다리우스 잡는 법 (대기중)')).toBeDefined();
  expect(rpcCalls('approve_build')).toEqual([{ p_id: 104, p_note: '패치 확인함', p_build: null, p_version: 1 }]);
});

test('/admin/builds/:id: 똑같은 빌드가 공개돼 있으면 그대로는 승인 불가(고쳐서 승인은 가능), 처리 기록이 보인다', async () => {
  const op = { nickname: '영자(운)', level: 0, main_title: null };
  Object.assign(TABLES.builds.find((x) => x.id === 104), {
    logs: [{ id: 1, action: 'reject', reason: '예전 거절', created_at: '2026-11-02T00:00:00Z', actor: op }],
  });
  asOperator();
  start('/admin/builds/104');
  expect(await screen.findByText(/똑같은 빌드가 이미 공개돼 있습니다. 그대로는 승인할 수 없습니다 \(고쳐서 승인하거나 거절해 주세요\)/)).toBeDefined();
  expect(screen.getByRole('button', { name: '승인' })).not.toBeDisabled();
  expect(document.querySelector('.log-list li').textContent).toMatch(/거절 · Lv\.0 영자\(운\) · 예전 거절$/);
});

test('/admin 숨긴 빌드: 줄에서 다시 공개 (메모 필수)', async () => {
  TABLES.builds.push(fakeBuild(120, { nickname: '숨김당함', level: 2, main_title: null }, {
    status: 'hidden', hide_reason: '패치로 안 맞음', hidden_at: '2026-11-05T00:00:00Z', up_count: 7,
  }));
  asOperator();
  start('/admin');
  await sectionCount('숨긴 빌드', 1);
  const row = screen.getByRole('listitem', { name: '[숨긴 빌드] 퀸으로 다리우스 잡는 법' });
  expect(within(row).getByText('사유: 패치로 안 맞음')).toBeDefined();
  click('다시 공개', row);
  fireEvent.change(within(row).getByLabelText(/다시 공개 메모/), { target: { value: '다시 맞습니다' } });
  TABLES.builds.find((b) => b.id === 120).status = 'approved';
  click('다시 공개 확정', row);
  expect(await screen.findByText('빌드를 다시 공개했습니다: 퀸으로 다리우스 잡는 법 (숨김당함)')).toBeDefined();
  expect(rpcCalls('restore_build')).toEqual([{ p_id: 120, p_note: '다시 맞습니다' }]);
  await sectionCount('숨긴 빌드', 0);
});

test('일반 유저는 /admin/builds/:id를 볼 수 없다', async () => {
  asUser();
  start('/admin/builds/104');
  expect(await screen.findByText('운영자만 볼 수 있습니다.')).toBeDefined();
});
