// 016: 매치업 문서 댓글 + 고치기 시간 제한 (글 60분, 댓글 10분, 열면 5분 유예)
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeComment, fakeDocComment, fakeLogin, fakePost, fakeState } from './fakeSupabase';
import { canEditNow, editDeadline } from '../lib/editWindow';
import { moreNames, openMore, pickMore } from './moreMenu';

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
const asOp = () => fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0, main_title: null });
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
  expect(within(sec).getByRole('heading').textContent).toBe('4. 댓글');
  expect(sec.querySelector('.count-badge').textContent).toBe('1개');
  expect(within(sec).getByText('퀸 꿀팁')).toBeDefined();
  expect(within(sec).getByText(/하면 댓글을 달 수 있습니다/)).toBeDefined();
  expect(screen.getByRole('link', { name: '댓글' }).getAttribute('href')).toBe('#comments');
});

test('문서 댓글 달기 → 바로 보임 / 남의 댓글은 신고 / 빌드 카드에는 댓글 없음', async () => {
  TABLES.doc_comments.push(fakeDocComment(1, { author_id: 'u-x', author: OTHER, body: '남의 문서 댓글' }));
  fakeLogin('u-old');
  start(MATCHUP);
  const sec = await section();
  fireEvent.change(within(sec).getByLabelText('댓글 쓰기'), { target: { value: '좋은 문서입니다' } });
  fireEvent.click(within(sec).getByRole('button', { name: '댓글 올리기' }));
  await vi.waitFor(() => expect(sec.querySelector('.count-badge').textContent).toBe('2개'));
  expect(rpcs('create_doc_comment')).toEqual([{ p_counter: 1, p_body: '좋은 문서입니다' }]);
  expect(document.querySelectorAll('.build-card .comment-list')).toHaveLength(0);

  const other = within(within(sec).getByRole('list', { name: '댓글' })).getAllByRole('listitem')[0];
  pickMore(within(other), '신고', '댓글 더보기');
  const reasons = within(other).getAllByRole('radio').map((r) => r.closest('label').textContent);
  expect(reasons.map((t) => t.split(' (')[0])).toEqual(['욕설·인신공격', '혐오·비하', '신상 공개·개인정보', '도배·광고', '기타']);
  expect(reasons[1]).toContain('실존 인물·고인 비하');
  fireEvent.click(within(other).getByLabelText(/^혐오·비하/));
  fireEvent.click(within(other).getByRole('button', { name: '신고 보내기' }));
  expect(await screen.findByText('신고했습니다. 운영진이 확인하겠습니다.')).toBeDefined();
  expect(rpcs('report_doc_comment')).toEqual([{ p_id: 1, p_reason: 'hate', p_detail: null }]);
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
  expect(moreNames(within(old), '댓글 더보기')).toEqual(['지우기']);

  pickMore(within(fresh), '고치기', '댓글 더보기');
  const box = await within(fresh).findByLabelText('댓글 고치기');
  expect(rpcs('begin_edit')).toEqual([{ p_kind: 'doc_comment', p_id: 1 }]);
  expect(within(fresh).getByText(/까지 저장할 수 있습니다/)).toBeDefined();

  // 저장 전에 시간이 지나면 DB가 막는다 → 안내, 쓴 내용은 그대로
  fireEvent.change(box, { target: { value: '고친 내용' } });
  fakeState.boardError = '고칠 수 있는 시간이 지났습니다. 지우고 다시 쓸 수는 있습니다.';
  fireEvent.click(within(fresh).getByRole('button', { name: '고친 내용 저장' }));
  expect((await within(fresh).findByRole('alert')).textContent).toBe('고칠 수 있는 시간이 지났습니다. 지우고 다시 쓸 수는 있습니다.');
  expect(within(fresh).getByLabelText('댓글 고치기').value).toBe('고친 내용');
});

test('[고치기]를 누를 때 이미 마감이면 안내만', async () => {
  TABLES.doc_comments.push(fakeDocComment(1, { body: '9분 59초', created_at: ago(9) }));
  fakeLogin('u-old');
  start(MATCHUP);
  const sec = await section();
  fakeState.boardError = '고칠 수 있는 시간이 지났습니다. 지우고 다시 쓸 수는 있습니다.';
  pickMore(within(sec), '고치기', '댓글 더보기');
  expect((await within(sec).findByRole('alert')).textContent).toContain('고칠 수 있는 시간이 지났습니다.');
  expect(within(sec).queryByLabelText('댓글 고치기')).toBeNull();
});

test('게시판 글: 1시간 지나면 [고치기] 없음 / 고치기 주소로 와도 안내', async () => {
  TABLES.posts.push(fakePost(1, { created_at: ago(61) }));
  TABLES.post_comments.push(fakeComment(11, 1, { created_at: ago(11), body: '오래된 내 댓글' }));
  fakeLogin('u-old');
  const { unmount } = start('/board/1');
  await screen.findByText('본문 1');
  expect(moreNames(screen, '글 더보기')).toEqual(['지우기']);
  const c = within(screen.getByRole('list', { name: '댓글' })).getByRole('listitem');
  expect(moreNames(within(c), '댓글 더보기')).toEqual(['지우기']);
  unmount();

  fakeState.boardError = '고칠 수 있는 시간이 지났습니다. 지우고 다시 쓸 수는 있습니다.';
  start('/board/1/edit');
  expect(await screen.findByText('고칠 수 있는 시간이 지났습니다. 지우고 다시 쓸 수는 있습니다.')).toBeDefined();
  expect(screen.getByRole('link', { name: '← 글로 돌아가기' }).getAttribute('href')).toBe('/board/1');
});

test('운영자: 문서 댓글 [숨기기](메모 필수) → 숨김 띠 → [다시 공개]', async () => {
  TABLES.doc_comments.push(fakeDocComment(1, { author_id: 'u-x', author: OTHER, body: '욕설 댓글' }));
  asOp();
  start(MATCHUP);
  const sec = await section();
  const hide = openMore(within(sec), '댓글 더보기').getByRole('menuitem', { name: '숨기기' });
  expect(hide.classList.contains('op')).toBe(true);
  fireEvent.click(hide);
  fireEvent.change(within(sec).getByLabelText('숨기는 사유 (필수, 작성자에게 보입니다)'), { target: { value: '욕설' } });
  fireEvent.click(within(sec).getByRole('button', { name: '숨기기 확정' }));
  expect(await screen.findByText('댓글을 숨겼습니다. 작성자에게 알림이 갔습니다.')).toBeDefined();
  expect(rpcs('hide_doc_comment')).toEqual([{ p_id: 1, p_note: '욕설' }]);
  await vi.waitFor(() => expect(sec.querySelector('.op-band')?.textContent).toContain('메모: 욕설'));
  fireEvent.click(within(sec.querySelector('.op-band')).getByRole('button', { name: '다시 공개' }));
  fireEvent.change(within(sec).getByLabelText('다시 공개 메모 (필수, 작성자에게 보입니다)'), { target: { value: '괜찮음' } });
  fireEvent.click(within(sec).getByRole('button', { name: '다시 공개 확정' }));
  expect(await screen.findByText('댓글을 다시 공개했습니다.')).toBeDefined();
  expect(rpcs('restore_doc_comment')).toEqual([{ p_id: 1, p_note: '괜찮음' }]);
});

test('숨긴 카운터: 일반 사용자에게 댓글 안 보임, 운영자 미리보기에는 댓글(새 댓글 없음)', async () => {
  TABLES.counters[0].status = 'hidden';
  TABLES.doc_comments.push(fakeDocComment(1, { author_id: 'u-x', author: OTHER, body: '숨긴 문서의 댓글' }));
  asOp();
  start('/admin/preview/Darius/Quinn');
  const sec = (await screen.findByText('1개', { selector: '#comments .count-badge' })).closest('section');
  expect(within(sec).getByText('숨긴 문서의 댓글')).toBeDefined();
  expect(within(sec).getByText('숨긴 카운터라 새 댓글은 달 수 없습니다.')).toBeDefined();
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
  expect(row.textContent).toContain('퀸으로 다리우스 이기는 법');
  expect(within(row).getByRole('link', { name: '보러 가기' }).getAttribute('href')).toBe('/champion/Darius/counter/Quinn#comments');
  fireEvent.click(within(row).getByRole('button', { name: '숨기기' }));
  fireEvent.change(within(row).getByLabelText('숨기는 사유 (필수, 작성자에게 보입니다)'), { target: { value: '광고' } });
  fireEvent.click(within(row).getByRole('button', { name: '숨기기 확정' }));
  expect(await screen.findByText('댓글을 숨겼습니다. 신고 1건은 처리됨으로 닫았습니다.')).toBeDefined();
  expect(rpcs('hide_doc_comment')).toEqual([{ p_id: 5, p_note: '광고' }]);
});

