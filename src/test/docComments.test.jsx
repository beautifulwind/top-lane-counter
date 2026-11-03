// 016: 매치업 문서 댓글 + 고치기 시간 제한 (글 60분, 댓글 10분, 열면 5분 유예)
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeComment, fakeDocComment, fakeLogin, fakePost, fakeState } from './fakeSupabase';
import { canEditNow, editDeadline } from '../lib/editWindow';

const COUNTERS = TABLES.counters.map((c) => ({ ...c }));
beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
  TABLES.counters = COUNTERS.map((c) => ({ ...c }));
});

const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /></MemoryRouter>);
const OTHER = { nickname: '남의글', level: 2, main_title: null };
const MATCHUP = '/champion/Darius/counter/Quinn';
const asOp = () => fakeLogin('u-op', { nickname: '영자(운)', role: 'admin', level: 0, main_title: null });
const rpcs = (name) => fakeState.rpcCalls.filter((c) => c.name === name).map((c) => c.args);
const ago = (min) => new Date(Date.now() - min * 60_000).toISOString();
const section = async () => (await screen.findByRole('heading', { name: /4\. 댓글/ })).closest('section');

test('고치기 시간 계산: 글 60분, 댓글 10분, 유예를 받았으면 그때까지', () => {
  const rules = { post: 60, comment: 10, grace: 5 };
  const t0 = Date.parse('2026-11-02T10:00:00Z');
  const row = { created_at: '2026-11-02T10:00:00Z', edit_grace_until: null };
  expect(editDeadline('post', row, rules)).toBe(t0 + 60 * 60_000);
  expect(editDeadline('comment', row, rules)).toBe(t0 + 10 * 60_000);
  expect(canEditNow('comment', row, rules, t0 + 10 * 60_000)).toBe(true);
  expect(canEditNow('comment', row, rules, t0 + 11 * 60_000)).toBe(false);
  const graced = { ...row, edit_grace_until: '2026-11-02T10:14:00Z' };
  expect(canEditNow('doc_comment', graced, rules, t0 + 13 * 60_000)).toBe(true);
  expect(canEditNow('doc_comment', graced, rules, t0 + 15 * 60_000)).toBe(false);
});

test('비로그인: 매치업 문서 "4. 댓글" — 목차, 댓글 보임, 로그인 안내', async () => {
  TABLES.doc_comments.push(fakeDocComment(1, { author_id: 'u-x', author: OTHER, body: '퀸 꿀팁' }));
  start(MATCHUP);
  const sec = await section();
  expect(within(sec).getByRole('heading').textContent).toBe('4. 댓글 1');
  expect(within(sec).getByText('퀸 꿀팁')).toBeDefined();
  expect(within(sec).getByText(/하면 댓글을 달 수 있어요/)).toBeDefined();
  expect(screen.getByRole('link', { name: '댓글' }).getAttribute('href')).toBe('#comments');
});

test('문서 댓글 달기 → 바로 보임 / 남의 댓글은 신고 / 빌드 카드에는 댓글 없음', async () => {
  TABLES.doc_comments.push(fakeDocComment(1, { author_id: 'u-x', author: OTHER, body: '남의 문서 댓글' }));
  fakeLogin('u-old');
  start(MATCHUP);
  const sec = await section();
  fireEvent.change(within(sec).getByLabelText('댓글 쓰기'), { target: { value: '좋은 문서예요' } });
  fireEvent.click(within(sec).getByRole('button', { name: '댓글 올리기' }));
  await vi.waitFor(() => expect(within(sec).getByRole('heading').textContent).toBe('4. 댓글 2'));
  expect(rpcs('create_doc_comment')).toEqual([{ p_counter: 1, p_body: '좋은 문서예요' }]);
  expect(document.querySelectorAll('.build-card .comment-list')).toHaveLength(0);

  const other = within(within(sec).getByRole('list', { name: '댓글' })).getAllByRole('listitem')[0];
  fireEvent.click(within(other).getByRole('button', { name: '신고' }));
  fireEvent.click(within(other).getByLabelText('욕설·비하'));
  fireEvent.click(within(other).getByRole('button', { name: '신고 보내기' }));
  expect(await screen.findByText('신고했어요. 운영자가 확인할게요.')).toBeDefined();
  expect(rpcs('report_doc_comment')).toEqual([{ p_id: 1, p_reason: 'abuse', p_detail: null }]);
});

test('내 문서 댓글: 10분 안이면 [고치기](유예 받고 마감 표시), 지나면 [고치기] 없음·[지우기]는 있음', async () => {
  TABLES.doc_comments.push(
    fakeDocComment(1, { body: '방금 쓴 댓글', created_at: ago(2) }),
    fakeDocComment(2, { body: '오래된 댓글', created_at: ago(11) }),
  );
  fakeLogin('u-old');
  start(MATCHUP);
  const sec = await section();
  const [fresh, old] = within(within(sec).getByRole('list', { name: '댓글' })).getAllByRole('listitem');
  expect(within(old).queryByRole('button', { name: '고치기' })).toBeNull();
  expect(within(old).getByRole('button', { name: '지우기' })).toBeDefined();

  fireEvent.click(within(fresh).getByRole('button', { name: '고치기' }));
  const box = await within(fresh).findByLabelText('댓글 고치기');
  expect(rpcs('begin_edit')).toEqual([{ p_kind: 'doc_comment', p_id: 1 }]);
  expect(within(fresh).getByText(/까지 저장할 수 있어요/)).toBeDefined();

  // 저장 전에 시간이 지나면 DB가 막는다 → 안내, 쓴 내용은 그대로
  fireEvent.change(box, { target: { value: '고친 내용' } });
  fakeState.boardError = '고칠 수 있는 시간이 지났어요. 지우고 다시 쓸 수는 있어요.';
  fireEvent.click(within(fresh).getByRole('button', { name: '고친 내용 저장' }));
  expect((await within(fresh).findByRole('alert')).textContent).toBe('고칠 수 있는 시간이 지났어요. 지우고 다시 쓸 수는 있어요.');
  expect(within(fresh).getByLabelText('댓글 고치기').value).toBe('고친 내용');
});

test('[고치기]를 누를 때 이미 마감이면 안내만', async () => {
  TABLES.doc_comments.push(fakeDocComment(1, { body: '9분 59초', created_at: ago(9) }));
  fakeLogin('u-old');
  start(MATCHUP);
  const sec = await section();
  fakeState.boardError = '고칠 수 있는 시간이 지났어요. 지우고 다시 쓸 수는 있어요.';
  fireEvent.click(within(sec).getByRole('button', { name: '고치기' }));
  expect((await within(sec).findByRole('alert')).textContent).toContain('고칠 수 있는 시간이 지났어요.');
  expect(within(sec).queryByLabelText('댓글 고치기')).toBeNull();
});

test('게시판 글: 1시간 지나면 [고치기] 없음 / 고치기 주소로 와도 안내', async () => {
  TABLES.posts.push(fakePost(1, { created_at: ago(61) }));
  TABLES.post_comments.push(fakeComment(11, 1, { created_at: ago(11), body: '오래된 내 댓글' }));
  fakeLogin('u-old');
  const { unmount } = start('/board/1');
  await screen.findByText('본문 1');
  expect(within(document.querySelector('.post-actions')).getByRole('button', { name: '지우기' })).toBeDefined();
  expect(screen.queryByRole('link', { name: '고치기' })).toBeNull();
  const c = within(screen.getByRole('list', { name: '댓글' })).getByRole('listitem');
  expect(within(c).getByRole('button', { name: '지우기' })).toBeDefined();
  expect(within(c).queryByRole('button', { name: '고치기' })).toBeNull();
  unmount();

  fakeState.boardError = '고칠 수 있는 시간이 지났어요. 지우고 다시 쓸 수는 있어요.';
  start('/board/1/edit');
  expect(await screen.findByText('고칠 수 있는 시간이 지났어요. 지우고 다시 쓸 수는 있어요.')).toBeDefined();
  expect(screen.getByRole('link', { name: '← 글로 돌아가기' }).getAttribute('href')).toBe('/board/1');
});

test('운영자: 문서 댓글 [숨기기](메모 필수) → 숨김 띠 → [다시 공개]', async () => {
  TABLES.doc_comments.push(fakeDocComment(1, { author_id: 'u-x', author: OTHER, body: '욕설 댓글' }));
  asOp();
  start(MATCHUP);
  const sec = await section();
  const hide = within(sec).getByRole('button', { name: '숨기기' });
  expect(hide.classList.contains('op-link')).toBe(true);
  fireEvent.click(hide);
  fireEvent.change(within(sec).getByLabelText('숨기는 사유 (필수, 작성자에게 보여요)'), { target: { value: '욕설' } });
  fireEvent.click(within(sec).getByRole('button', { name: '숨기기 확정' }));
  expect(await screen.findByText('댓글을 숨겼어요. 작성자에게 알림이 갔어요.')).toBeDefined();
  expect(rpcs('hide_doc_comment')).toEqual([{ p_id: 1, p_note: '욕설' }]);
  await vi.waitFor(() => expect(sec.querySelector('.op-band')?.textContent).toContain('메모: 욕설'));
  fireEvent.click(within(sec.querySelector('.op-band')).getByRole('button', { name: '다시 공개' }));
  fireEvent.change(within(sec).getByLabelText('다시 공개 메모 (필수, 작성자에게 보여요)'), { target: { value: '괜찮음' } });
  fireEvent.click(within(sec).getByRole('button', { name: '다시 공개 확정' }));
  expect(await screen.findByText('댓글을 다시 공개했어요.')).toBeDefined();
  expect(rpcs('restore_doc_comment')).toEqual([{ p_id: 1, p_note: '괜찮음' }]);
});

test('숨긴 카운터: 일반 사용자에게 댓글 안 보임, 운영자 미리보기에는 댓글(새 댓글 없음)', async () => {
  TABLES.counters[0].status = 'hidden';
  TABLES.doc_comments.push(fakeDocComment(1, { author_id: 'u-x', author: OTHER, body: '숨긴 문서의 댓글' }));
  asOp();
  start('/admin/preview/Darius/Quinn');
  const sec = (await screen.findByRole('heading', { name: '댓글 1' })).closest('section');
  expect(within(sec).getByText('숨긴 문서의 댓글')).toBeDefined();
  expect(within(sec).getByText('숨긴 카운터라 새 댓글은 달 수 없어요.')).toBeDefined();
  expect(within(sec).queryByLabelText('댓글 쓰기')).toBeNull();
});

test('운영자 /admin/reports: 문서 댓글 신고 — 매치업 이름, [보러 가기], 숨기기', async () => {
  TABLES.doc_comments.push(fakeDocComment(5, { author_id: 'u-x', author: OTHER, body: '나쁜 문서 댓글' }));
  TABLES.reports.push({
    id: 1, reporter_id: 'u-r', post_id: null, comment_id: null, doc_comment_id: 5, reason: 'spam', detail: null, status: 'open',
    created_at: '2026-11-01T00:00:00Z', reporter: { nickname: '신고자', level: 1, main_title: null },
  });
  asOp();
  start('/admin/reports');
  const row = await screen.findByRole('listitem', { name: '문서 댓글 신고 1건' });
  expect(row.textContent).toContain('나쁜 문서 댓글');
  expect(row.textContent).toContain('퀸으로 다리우스 잡는 법');
  expect(within(row).getByRole('link', { name: '보러 가기' }).getAttribute('href')).toBe('/champion/Darius/counter/Quinn#comments');
  fireEvent.click(within(row).getByRole('button', { name: '숨기기' }));
  fireEvent.change(within(row).getByLabelText('숨기는 사유 (필수, 작성자에게 보여요)'), { target: { value: '광고' } });
  fireEvent.click(within(row).getByRole('button', { name: '숨기기 확정' }));
  expect(await screen.findByText('댓글을 숨겼어요. 신고 1건은 처리됨으로 닫았어요.')).toBeDefined();
  expect(rpcs('hide_doc_comment')).toEqual([{ p_id: 5, p_note: '광고' }]);
});

test('/me: 문서 댓글 알림 — 매치업 이름과 [문서 보기], 경험치 내역 "문서 댓글"', async () => {
  TABLES.notifications.push({
    id: 1, user_id: 'u-old', kind: 'doc_comment', counter_id: 1, message: '내가 제안한 카운터 문서에 새 댓글 2개가 달렸어요.',
    created_at: '2026-11-02T00:00:00Z', read_at: null, counter: { target_champion: 'Darius', counter_champion: 'Quinn', status: 'approved' },
  });
  TABLES.xp_events.push({
    id: 1, user_id: 'u-old', type: 'doc_comment', amount: 1, change: 'grant', reason: null,
    target_champion: 'Darius', counter_champion: 'Quinn', created_at: '2026-11-02T00:00:00Z',
  });
  fakeLogin('u-old');
  start('/me');
  const sec = (await screen.findByRole('heading', { name: '댓글·노가리방 알림' })).closest('section');
  const item = within(sec).getByRole('listitem');
  expect(item.textContent).toContain('새 댓글 2개');
  expect(item.textContent).toContain('퀸으로 다리우스 잡는 법');
  expect(within(item).getByRole('link', { name: '문서 보기' }).getAttribute('href')).toBe('/champion/Darius/counter/Quinn#comments');
  const xp = within(screen.getByRole('list', { name: '경험치 내역' })).getByRole('listitem');
  expect(xp.textContent).toContain('문서 댓글 · 퀸으로 다리우스');
});
