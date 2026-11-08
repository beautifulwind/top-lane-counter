// 감독관(030, SPEC 6-18): (운) 표시, /admin에 허용된 구역만, 숨기기·다시 공개 조건, 제안은 메모만 쓰고 그대로 승인, 신고자 숨김, 운영자의 지정·해제
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import UserName from '../components/UserName';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeComment, fakeLogin, fakePost, fakeProposal, fakeState } from './fakeSupabase';
import { openMenu } from './menu';
import { describeNotification } from '../lib/notifications';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /></MemoryRouter>);
const asMod = () => fakeLogin('u-mod', { nickname: '감독', role: 'moderator', level: 3, main_title: null });
const asOp = () => fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0, main_title: null });
const rpcs = (name) => fakeState.rpcCalls.filter((c) => c.name === name).map((c) => c.args);
const MEMBER = { nickname: '남의글', role: 'user', level: 2, main_title: null };
const STAFF = { nickname: '다른감독', role: 'moderator', level: 2, main_title: null };
const newCounter = (id, extra = {}) => fakeProposal({
  id, type: 'new_counter', counter_id: null, proposer_id: 'u-old',
  proposer: { nickname: '기존유저', role: 'user', level: 1, main_title: null },
  target_champion: 'Darius', counter_champion: 'Vayne',
  ...extra,
});

test('닉네임 앞 (운): 운영자·감독관 똑같이, 일반 회원은 없음', () => {
  const text = (profile) => {
    const { container, unmount } = render(<MemoryRouter><UserName profile={profile} /></MemoryRouter>);
    const t = container.textContent;
    unmount();
    return t;
  };
  expect(text({ nickname: '감독', role: 'moderator', level: 3 })).toContain('(운)');
  expect(text({ nickname: '영자', role: 'admin', level: 0 })).toContain('(운)');
  expect(text({ nickname: '회원', role: 'user', level: 3 })).not.toContain('(운)');
});

test('일반 회원은 /admin 못 들어가고 메뉴에 [관리]도 없다', async () => {
  fakeLogin('u-old');
  start('/admin');
  expect(await screen.findByText('운영자만 볼 수 있습니다.')).toBeDefined();
  expect((await openMenu()).queryByRole('link', { name: '관리' })).toBeNull();
});

test('감독관 /admin: 메뉴에 [관리], 새 카운터 대기와 자유게시판만. 운영자 전용 구역은 안 보이고 불러오지도 않는다', async () => {
  asMod();
  TABLES.edit_proposals.push(
    newCounter(1),
    newCounter(2, { proposer_id: 'u-mod', counter_champion: 'Kennen' }), // 본인 제안
    newCounter(3, { proposer_id: 'u-m2', proposer: STAFF, counter_champion: 'Teemo' }), // 운영진 제안
    fakeProposal({ id: 4 }), // 문서 수정 제안
  );
  start('/admin');
  expect(await screen.findByRole('heading', { name: /새 카운터 승인 대기/ })).toBeDefined();
  expect((await openMenu()).getByRole('link', { name: '관리' })).toBeDefined();
  expect(await screen.findByRole('heading', { name: /자유게시판·댓글/ })).toBeDefined();
  for (const name of ['감독관 관리', '사진 저장 공간', '비주류 픽', '아이템 가격', '숨긴 카운터', '삭제 기록']) {
    expect(screen.queryByRole('heading', { name: new RegExp(name) })).toBeNull();
  }
  const rows = await vi.waitFor(() => {
    const list = document.querySelectorAll('.proposal-list > li');
    expect(list.length).toBe(1); // 다른 회원의 새 카운터만
    return list;
  });
  expect(within(rows[0]).queryByRole('button', { name: '재검토 요청' })).toBeNull();
  expect(within(rows[0]).getByRole('button', { name: '거절' })).toBeDefined();
});

test('감독관 제안 화면: 안 고치고 메모만 써서 승인할 수 있다 (고친 칸은 null), 재검토 요청 없음', async () => {
  asMod();
  TABLES.edit_proposals.push(newCounter(1));
  start('/admin/proposals/1');
  fireEvent.click(await screen.findByRole('button', { name: '승인' }));
  expect(screen.queryByRole('button', { name: '재검토 요청' })).toBeNull();
  expect(await screen.findByText('한 줄 요약 (필수)')).toBeDefined(); // 033: 감독관도 고쳐서 승인 편집기
  expect(screen.queryByRole('button', { name: '고친 내용으로 승인 확정' })).toBeNull(); // 아직 안 고쳤다
  const ok = screen.getByRole('button', { name: '승인 확정' });
  expect(ok.disabled).toBe(true);
  fireEvent.change(screen.getByLabelText('승인 메모 (필수, 제안자에게 보입니다)'), { target: { value: '좋아요' } });
  fireEvent.click(ok);
  await vi.waitFor(() => expect(rpcs('approve_proposal').length).toBe(1));
  const args = rpcs('approve_proposal')[0];
  expect(args.p_id).toBe(1);
  expect(args.p_note).toBe('좋아요');
  expect(args.p_content ?? null).toBeNull();
  expect(args.p_build ?? null).toBeNull();
});

test('감독관 제안 화면: 글을 고치면 고친 글을 보내 승인한다 (033)', async () => {
  asMod();
  TABLES.edit_proposals.push(newCounter(1));
  start('/admin/proposals/1');
  fireEvent.click(await screen.findByRole('button', { name: '승인' }));
  const summary = await screen.findByLabelText('한 줄 요약 (필수)');
  fireEvent.change(summary, { target: { value: '감독관이 다듬은 요약' } });
  fireEvent.change(screen.getByLabelText('승인 메모 (필수, 제안자에게 보입니다)'), { target: { value: '요약을 다듬었습니다' } });
  fireEvent.click(screen.getByRole('button', { name: '고친 내용으로 승인 확정' }));
  await vi.waitFor(() => expect(rpcs('approve_proposal').length).toBe(1));
  const args = rpcs('approve_proposal')[0];
  expect(args.p_content.summary).toBe('감독관이 다듬은 요약');
  expect(args.p_note).toBe('요약을 다듬었습니다');
});

test('감독관 목록 줄: [내용 고치기] 링크가 보인다 (033)', async () => {
  asMod();
  TABLES.edit_proposals.push(newCounter(1));
  start('/admin');
  fireEvent.click(await screen.findByRole('button', { name: '승인' })); // 줄의 [승인]을 열면 메모 칸 아래에 링크
  const link = await screen.findByRole('link', { name: /내용 고치기/ });
  expect(link.getAttribute('href')).toBe('/admin/proposals/1?approve=1');
});

test.each([
  ['본인 제안', () => newCounter(1, { proposer_id: 'u-mod' })],
  ['운영진 제안', () => newCounter(1, { proposer_id: 'u-m2', proposer: STAFF })],
  ['문서 수정 제안', () => fakeProposal({ id: 1 })],
])('감독관 제안 화면: %s은 처리 버튼 없이 안내만', async (_, make) => {
  asMod();
  TABLES.edit_proposals.push(make());
  start('/admin/proposals/1');
  expect(await screen.findByText(/운영자가 처리하는 제안입니다/)).toBeDefined();
  for (const name of ['승인', '거절', '재검토 요청']) expect(screen.queryByRole('button', { name })).toBeNull();
});

test('감독관 글·댓글: 일반 회원 글은 [숨기기], 운영진의 글은 [신고]만', async () => {
  asMod();
  TABLES.posts.push(fakePost(1, { author_id: 'u-x', author: MEMBER }), fakePost(2, { author_id: 'u-m2', author: STAFF, comment_count: 2 }));
  TABLES.post_comments.push(
    fakeComment(11, 2, { author_id: 'u-x', author: MEMBER, body: '회원 댓글' }),
    fakeComment(12, 2, { author_id: 'u-m2', author: STAFF, body: '감독 댓글' }),
  );
  start('/board/1');
  expect(await screen.findByRole('button', { name: '숨기기' })).toBeDefined();
  expect(screen.queryByRole('button', { name: '신고' })).toBeNull();
  cleanup();
  start('/board/2');
  const [member, staff] = within(await screen.findByRole('list', { name: '댓글' })).getAllByRole('listitem');
  expect(within(member).getByRole('button', { name: '숨기기' })).toBeDefined();
  expect(within(staff).queryByRole('button', { name: '숨기기' })).toBeNull();
  expect(within(staff).getByRole('button', { name: '신고' })).toBeDefined();
  // 글 자체(운영진의 글)도 [숨기기] 없음: 댓글 줄 밖의 숨기기 버튼은 없어야 한다
  const outside = screen.getAllByRole('button', { name: '숨기기' }).filter((b) => !member.contains(b));
  expect(outside).toEqual([]);
});

test('감독관 다시 공개: 다른 감독관이 숨긴 것만, 운영자가 숨긴 것은 버튼 없음', async () => {
  asMod();
  const hidden = { author_id: 'u-x', author: MEMBER, status: 'hidden', hidden_note: '광고', hidden_at: '2026-11-01T13:00:00Z' };
  TABLES.posts.push(fakePost(1, { ...hidden, hider: { role: 'moderator' } }), fakePost(2, { ...hidden, hider: { role: 'admin' } }));
  start('/board/1');
  await vi.waitFor(() => expect(document.querySelector('.op-band')).not.toBeNull());
  expect(within(document.querySelector('.op-band')).getByRole('button', { name: '다시 공개' })).toBeDefined();
  cleanup();
  start('/board/2');
  await vi.waitFor(() => expect(document.querySelector('.op-band')).not.toBeNull());
  expect(within(document.querySelector('.op-band')).queryByRole('button', { name: '다시 공개' })).toBeNull();
});

const report = (id, extra = {}) => ({
  id, post_id: 1, comment_id: null, doc_comment_id: null, reason: 'spam', detail: null, status: 'open',
  created_at: '2026-11-01T00:00:00Z', reporter_id: 'u-r', reporter: { nickname: '신고한사람', level: 1, main_title: null }, ...extra,
});

test('신고 목록: 감독관은 전용 DB 함수로 받고 신고자가 안 보임, 운영자는 그대로 보이고 탈퇴자도 표시', async () => {
  TABLES.posts.push(fakePost(1, { author_id: 'u-x', author: MEMBER }));
  TABLES.reports.push(report(1));
  asMod();
  fakeState.moderatorReportsAsked = false;
  start('/admin/reports');
  const list = await screen.findByRole('list', { name: '신고 내용' });
  expect(fakeState.moderatorReportsAsked).toBe(true);
  expect(list.textContent).not.toContain('신고한사람');
  expect(screen.getByRole('button', { name: '숨기기' })).toBeDefined();
  cleanup();
  asOp();
  TABLES.reports.push(report(2, { reporter_id: null, reporter: null }));
  start('/admin/reports');
  const opList = await screen.findByRole('list', { name: '신고 내용' });
  expect(opList.textContent).toContain('신고한사람');
  expect(opList.textContent).toContain('탈퇴');
});

test('운영자 /admin 감독관 관리: 찾아서 메모 쓰고 지정, 처리 기록, [해제]', async () => {
  asOp();
  TABLES.profiles.push({ id: 'u-new', nickname: '새감독', role: 'user', xp: 0, level: 2, main_title: null });
  TABLES.profiles.push({ id: 'u-g', nickname: '비회원손님', role: 'user', xp: 0, level: 1, main_title: null, is_guest: true });
  start('/admin');
  expect(await screen.findByRole('heading', { name: /감독관 관리/ })).toBeDefined();
  expect(await screen.findByText('감독관이 없습니다.')).toBeDefined();
  fireEvent.change(screen.getByLabelText('닉네임으로 회원 찾기'), { target: { value: '영자' } });
  fireEvent.click(screen.getByRole('button', { name: '찾기' }));
  expect(await screen.findByText('지정할 수 있는 회원을 찾지 못했습니다.')).toBeDefined(); // 운영자 본인은 후보 아님
  fireEvent.change(screen.getByLabelText('닉네임으로 회원 찾기'), { target: { value: '손님' } });
  fireEvent.click(screen.getByRole('button', { name: '찾기' }));
  expect(await screen.findByText('비회원은 감독관으로 지정할 수 없습니다.')).toBeDefined();
  fireEvent.change(screen.getByLabelText('닉네임으로 회원 찾기'), { target: { value: '새감' } });
  fireEvent.click(screen.getByRole('button', { name: '찾기' }));
  fireEvent.click(within(await screen.findByRole('listitem', { name: '새감독' })).getByRole('button', { name: '지정' }));
  expect(screen.getByText(/처리 기록은 탈퇴 후에도 남습니다/)).toBeDefined();
  const ok = screen.getByRole('button', { name: '지정 확정' });
  expect(ok.disabled).toBe(true);
  fireEvent.change(screen.getByLabelText('지정 메모 (필수, 그 사람에게 보입니다)'), { target: { value: '신고 처리 부탁' } });
  fireEvent.click(ok);
  expect(await screen.findByText('새감독: 감독관 지정했습니다.')).toBeDefined();
  expect(rpcs('set_moderator')).toEqual([{ p_user: 'u-new', p_on: true, p_note: '신고 처리 부탁' }]);
  const mods = await screen.findByRole('list', { name: '감독관 목록' });
  expect((await screen.findByRole('list', { name: '처리 기록' })).textContent).toContain('감독관 지정');
  fireEvent.click(within(mods).getByRole('button', { name: '해제' }));
  fireEvent.change(screen.getByLabelText('해제 메모 (필수, 그 사람에게 보입니다)'), { target: { value: '활동 종료' } });
  fireEvent.click(screen.getByRole('button', { name: '해제 확정' }));
  expect(await screen.findByText('새감독: 감독관 해제했습니다.')).toBeDefined();
  expect(TABLES.profiles.find((p) => p.id === 'u-new').role).toBe('user');
});

test('감독관 알림: 지정은 탈퇴 후 기록 안내 + 메모, 해제는 메모', () => {
  const g = describeNotification({ kind: 'moderator_granted', message: '감독관으로 지정됐습니다. 처리 기록은 탈퇴 후에도 남습니다. 메모: 부탁' });
  expect(g.title).toBe('감독관으로 지정됐습니다. 처리 기록은 탈퇴 후에도 남습니다.');
  expect(g.detail).toBe('메모: 부탁');
  expect(g.to).toBe('/admin');
  const r = describeNotification({ kind: 'moderator_revoked', message: '감독관에서 해제됐습니다. 메모: 끝' });
  expect(r.title).toBe('감독관에서 해제됐습니다.');
  expect(r.to).toBeNull();
});
