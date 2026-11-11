// 043 오류 신고 (SPEC 6-30): 상대법·빌드 ⋮ "오류 신고" → 정식 회원만 보내기 (비회원은 연결 안내, 로그인 전은 로그인으로),
// 운영진 [관리] → 신고 → "오류 신고" 탭에서 처리됨·기각 (메모 필수, 같은 대상 함께), 신고자에게 결과 알림, 감독관은 자기 신고 처리 불가
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { AppRoutes } from '../App';
import { describeNotification } from '../lib/notifications';
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
const report = (extra) => ({
  id: 900 + TABLES.wiki_reports.length, counter_id: 1, build_id: 102, reporter_id: 'u-old', reason: 'wrong', memo: '룬이 틀렸어요',
  status: 'open', created_at: `2026-11-0${TABLES.wiki_reports.length + 1}T00:00:00Z`, handled_by: null, handled_at: null, handled_note: null, ...extra,
});

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

describe('보내기', () => {
  test('정식 회원: 빌드 ⋮ "오류 신고" → 이유 5가지 + 메모 → report_wiki, 그 자리에 안내', async () => {
    fakeLogin('u-old');
    start(`${MATCHUP}?build=102`);
    await screen.findByText(/퀸으로 다리우스 이기는 법/);
    pickMore(screen, '오류 신고', '빌드 2 더보기');
    const form = screen.getByRole('group', { name: /빌드 2 오류 신고 — 이유를 골라 주세요/ });
    expect(within(form).getAllByRole('radio').map((r) => r.value)).toEqual(['wrong', 'outdated', 'vandal', 'duplicate', 'other']);
    fireEvent.click(within(form).getByRole('radio', { name: /패치가 지남/ }));
    fireEvent.change(screen.getByLabelText('메모 (선택)'), { target: { value: '  14.22 패치 아이템이 바뀜 ' } });
    fireEvent.click(screen.getByRole('button', { name: '신고 보내기' }));
    expect(await screen.findByText('오류 신고를 보냈습니다. 운영진이 확인합니다.')).toBeDefined();
    expect(fakeState.rpcCalls).toContainEqual({
      name: 'report_wiki', args: { p_counter: 1, p_build: 102, p_reason: 'outdated', p_memo: '14.22 패치 아이템이 바뀜' },
    });
    expect(TABLES.wiki_reports).toHaveLength(1);
  });

  test('상대법 전체 신고는 이유 3가지 (패치·중복 없음), "기타"는 메모가 있어야 보낼 수 있다', async () => {
    fakeLogin('u-old');
    start(MATCHUP);
    await screen.findByText(/퀸으로 다리우스 이기는 법/);
    pickMore(screen, '오류 신고', '상대법 더보기');
    const form = screen.getByRole('group', { name: /상대법 오류 신고/ });
    expect(within(form).getAllByRole('radio').map((r) => r.value)).toEqual(['wrong', 'vandal', 'other']);
    fireEvent.click(within(form).getByRole('radio', { name: /기타/ }));
    expect(screen.getByRole('button', { name: '신고 보내기' })).toBeDisabled();
    fireEvent.change(screen.getByLabelText('메모 (필수)'), { target: { value: '제목이 이상합니다' } });
    fireEvent.click(screen.getByRole('button', { name: '신고 보내기' }));
    await screen.findByText('오류 신고를 보냈습니다. 운영진이 확인합니다.');
    expect(fakeState.rpcCalls.at(-1).args).toMatchObject({ p_build: null, p_reason: 'other', p_memo: '제목이 이상합니다' });
  });

  test('같은 대상을 또 신고하면 DB 안내가 그대로 보인다', async () => {
    TABLES.wiki_reports.push(report());
    fakeLogin('u-old');
    start(`${MATCHUP}?build=102`);
    await screen.findByText(/퀸으로 다리우스 이기는 법/);
    pickMore(screen, '오류 신고', '빌드 2 더보기');
    fireEvent.click(screen.getByRole('radio', { name: /내용이 틀림/ }));
    fireEvent.click(screen.getByRole('button', { name: '신고 보내기' }));
    expect((await screen.findByRole('alert')).textContent).toMatch(/이미 신고한 내용/);
  });

  test('비회원: 신고 칸 대신 구글·카카오 연결 안내', async () => {
    fakeLogin('u-guest', { nickname: '손님', is_guest: true });
    start(MATCHUP);
    await screen.findByText(/퀸으로 다리우스 이기는 법/);
    pickMore(screen, '오류 신고', '상대법 더보기');
    expect(screen.queryByRole('button', { name: '신고 보내기' })).toBeNull();
    expect(screen.getByText(/오류 신고를 할/)).toBeDefined();
    fireEvent.click(screen.getByRole('button', { name: '닫기' }));
    expect(screen.queryByText(/오류 신고를 할/)).toBeNull();
  });

  test('로그인 전: ⋮ "오류 신고"는 로그인 화면으로', async () => {
    start(MATCHUP);
    await screen.findByText(/퀸으로 다리우스 이기는 법/);
    expect(moreNames(screen, '상대법 더보기')).toEqual(['오류 신고']);
    pickMore(screen, '오류 신고', '상대법 더보기');
    expect(where()).toBe('/login');
  });
});

describe('운영진 처리 (/admin/reports?tab=wiki)', () => {
  test('운영자: 탭 전환, 처리 전 목록(신고자 보임) → [처리됨] + 메모 + 같은 대상 함께 → 처리된 것에 결과, 신고자에게 알림', async () => {
    TABLES.profiles.push({ id: 'u-2', nickname: '탑초보', role: 'user', level: 1 });
    TABLES.wiki_reports.push(report(), report({ reporter_id: 'u-2', reason: 'outdated', memo: null }), report({ build_id: null, reason: 'vandal', memo: '장난' }));
    fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0 });
    start('/admin/reports');
    expect(await screen.findByRole('tab', { name: '글·댓글 신고', selected: true })).toBeDefined();
    fireEvent.click(screen.getByRole('tab', { name: '오류 신고' }));
    expect(where()).toBe('/admin/reports?tab=wiki');
    const list = await screen.findByRole('list', { name: '오류 신고 목록' });
    const rows = within(list).getAllByRole('listitem', { name: /오류 신고$/ });
    expect(rows).toHaveLength(3);
    const first = rows[0];
    expect(first.textContent).toMatch(/빌드/);
    expect(first.textContent).toMatch(/내용이 틀림/);
    expect(first.textContent).toMatch(/퀸으로 다리우스 이기는 법 · 빌드 2/);
    expect(first.textContent).toMatch(/신고자: 기존유저/);
    expect(first.textContent).toMatch(/같은 대상의 처리 전 신고 2건/);
    expect(within(first).getByRole('link', { name: '보러 가기' }).getAttribute('href')).toBe(`${MATCHUP}?build=102`);
    expect(rows[2].getAttribute('aria-label')).toBe('상대법 오류 신고');

    fireEvent.click(within(first).getByRole('button', { name: '처리됨' }));
    const confirm = within(first).getByRole('button', { name: '처리됨 확정' });
    expect(confirm).toBeDisabled();
    fireEvent.change(within(first).getByLabelText(/처리 메모/), { target: { value: '룬 고침' } });
    fireEvent.click(within(first).getByRole('checkbox', { name: '같은 대상의 처리 전 신고 2건 함께 처리' }));
    fireEvent.click(confirm);
    expect(await screen.findByText('오류 신고 2건을 처리됨으로 닫았습니다.')).toBeDefined();
    expect(fakeState.rpcCalls).toContainEqual({ name: 'handle_wiki_report', args: { p_id: 900, p_status: 'resolved', p_note: '룬 고침', p_same_target: true } });
    await vi.waitFor(() => expect(within(screen.getByRole('list', { name: '오류 신고 목록' })).getAllByRole('listitem', { name: /오류 신고$/ })).toHaveLength(1));
    expect(TABLES.notifications.filter((n) => n.kind === 'error_report_handled').map((n) => n.user_id).sort()).toEqual(['u-2', 'u-old']);

    fireEvent.click(screen.getByRole('button', { name: '처리된 것' }));
    const done = await screen.findByRole('list', { name: '오류 신고 목록' });
    expect(within(done).getAllByRole('listitem', { name: /오류 신고$/ })).toHaveLength(2);
    expect(done.textContent).toMatch(/처리됨 · \(운\)영자 · .* — 룬 고침/);
    expect(within(done).queryByRole('button', { name: '처리됨' })).toBeNull();
  });

  test('[기각]: 메모 필수, 결과 알림 문구', async () => {
    TABLES.wiki_reports.push(report());
    fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0 });
    start('/admin/reports?tab=wiki');
    const row = await screen.findByRole('listitem', { name: '빌드 오류 신고' });
    expect(within(row).queryByRole('checkbox')).toBeNull();
    fireEvent.click(within(row).getByRole('button', { name: '기각' }));
    fireEvent.change(within(row).getByLabelText(/기각 메모/), { target: { value: '맞는 내용' } });
    fireEvent.click(within(row).getByRole('button', { name: '기각 확정' }));
    expect(await screen.findByText('오류 신고를 기각으로 닫았습니다.')).toBeDefined();
    expect(await screen.findByText('처리할 오류 신고가 없습니다.')).toBeDefined();
    expect(TABLES.notifications.at(-1)).toMatchObject({ user_id: 'u-old', kind: 'error_report_handled', message: expect.stringMatching(/기각했습니다/) });
  });

  test('감독관: 신고자는 안 보이고, 자기가 낸 신고는 [처리됨]·[기각] 대신 안내', async () => {
    fakeLogin('u-mod', { nickname: '감독', role: 'moderator', level: 3 });
    TABLES.wiki_reports.push(report(), report({ reporter_id: 'u-mod', build_id: 103 }));
    start('/admin/reports?tab=wiki');
    const list = await screen.findByRole('list', { name: '오류 신고 목록' });
    const [other, mine] = within(list).getAllByRole('listitem', { name: /오류 신고$/ });
    expect(list.textContent).not.toMatch(/신고자:/);
    expect(within(other).getByRole('button', { name: '처리됨' })).toBeDefined();
    expect(mine.textContent).toMatch(/내가 낸 신고/);
    expect(within(mine).queryByRole('button', { name: '처리됨' })).toBeNull();
    expect(mine.textContent).toMatch(/내가 낸 신고는 다른 운영진이 처리합니다/);
  });

  test('일반 회원은 신고 화면을 볼 수 없다', async () => {
    fakeLogin('u-old');
    start('/admin/reports?tab=wiki');
    expect(await screen.findByText(/운영진만 볼 수 있습니다|운영자만 볼 수 있습니다/)).toBeDefined();
    expect(screen.queryByRole('list', { name: '오류 신고 목록' })).toBeNull();
  });
});

describe('알림', () => {
  const counter = { target_champion: 'Darius', counter_champion: 'Quinn', status: 'approved' };
  test('운영진: 새 오류 신고 → 신고 화면 오류 신고 탭, [빌드]/[상대법] 표시', () => {
    const n = { kind: 'error_reported', message: '새 오류 신고가 들어왔습니다. (내용이 틀림)', build_id: 102, counter, build: { counter } };
    expect(describeNotification(n, (id) => ({ Darius: '다리우스', Quinn: '퀸' })[id])).toMatchObject({
      title: n.message, subject: '[빌드] 퀸으로 다리우스 이기는 법', to: '/admin/reports?tab=wiki',
    });
    expect(describeNotification({ ...n, build_id: null, build: null }).subject).toMatch(/^\[상대법\]/);
  });
  test('신고자: 처리 결과 → 그 상대법·빌드로 (숨긴 상대법이면 링크 없음)', () => {
    const n = { kind: 'error_report_handled', message: '보내 주신 오류 신고를 처리했습니다. 고맙습니다.', build_id: 102, counter_id: 1, counter, build: { counter } };
    expect(describeNotification(n)).toMatchObject({ icon: 'check', title: n.message, to: `${MATCHUP}?build=102` });
    expect(describeNotification({ ...n, message: '보내 주신 오류 신고를 검토했지만 고칠 내용이 없어 기각했습니다.' }).icon).toBe('ban');
    expect(describeNotification({ ...n, counter: { ...counter, status: 'hidden' } }).to).toBeNull();
  });
});
