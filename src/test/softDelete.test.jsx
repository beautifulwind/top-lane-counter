// 040: 글·댓글 ⋮ 메뉴의 운영진 삭제(메모 필수), 비회원 신고 안내, 지운 글 알림, 회원 정보의 지운 개수
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeComment, fakeDocComment, fakeGuestLogin, fakeLogin, fakePost, fakeState } from './fakeSupabase';
import { moreNames, openMore, pickMore } from './moreMenu';
import { describeNotification } from '../lib/notifications';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

let where = null;
function Where() {
  where = useLocation().pathname;
  return null;
}
const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /><Where /></MemoryRouter>);
const OTHER = { nickname: '남의글', level: 2, main_title: null };
const asOp = () => fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0, main_title: null });
const rpcs = (name) => fakeState.rpcCalls.filter((c) => c.name === name).map((c) => c.args);

test('운영자: 글 ⋮ [운영진 삭제] → 사유를 써야 [삭제 확정] → staff_delete_post → 목록으로', async () => {
  TABLES.posts.push(fakePost(1, { author_id: 'u-x', author: OTHER }));
  asOp();
  start('/board/1');
  await screen.findByRole('button', { name: '글 더보기' });
  pickMore(screen, '운영진 삭제', '글 더보기');
  const ok = screen.getByRole('button', { name: '삭제 확정' });
  expect(ok.disabled).toBe(true);
  fireEvent.change(screen.getByLabelText('삭제 사유 (필수, 작성자에게 보입니다)'), { target: { value: ' 개인정보 노출 ' } });
  fireEvent.click(ok);
  expect(await screen.findByText('글을 삭제했습니다. 작성자에게 알림이 갔습니다.')).toBeDefined();
  expect(rpcs('staff_delete_post')).toEqual([{ p_id: 1, p_note: '개인정보 노출' }]);
  expect(where).toBe('/board');
});

test('운영자: 댓글 ⋮ [운영진 삭제] → staff_delete_comment, 사라짐 / [취소]로 닫힘', async () => {
  TABLES.posts.push(fakePost(1, { comment_count: 1 }));
  TABLES.post_comments.push(fakeComment(11, 1, { author_id: 'u-x', author: OTHER, body: '도배 댓글' }));
  asOp();
  start('/board/1');
  const row = within(await screen.findByRole('list', { name: '댓글' })).getByRole('listitem');
  pickMore(within(row), '운영진 삭제', '댓글 더보기');
  fireEvent.click(within(row).getByRole('button', { name: '취소' }));
  expect(within(row).queryByLabelText(/삭제 사유/)).toBeNull();
  pickMore(within(row), '운영진 삭제', '댓글 더보기');
  fireEvent.change(within(row).getByLabelText('삭제 사유 (필수, 작성자에게 보입니다)'), { target: { value: '도배' } });
  fireEvent.click(within(row).getByRole('button', { name: '삭제 확정' }));
  expect(await screen.findByText('댓글을 삭제했습니다. 작성자에게 알림이 갔습니다.')).toBeDefined();
  expect(rpcs('staff_delete_comment')).toEqual([{ p_id: 11, p_note: '도배' }]);
  await vi.waitFor(() => expect(screen.queryByText('도배 댓글')).toBeNull());
});

test('운영자: 문서 댓글도 ⋮ [운영진 삭제] → staff_delete_doc_comment', async () => {
  TABLES.doc_comments.push(fakeDocComment(1, { author_id: 'u-x', author: OTHER, body: '욕설 문서 댓글' }));
  asOp();
  start('/champion/Darius/counter/Quinn');
  const sec = (await screen.findByRole('heading', { name: /4\. 댓글/ })).closest('section');
  pickMore(within(sec), '운영진 삭제', '댓글 더보기');
  fireEvent.change(within(sec).getByLabelText('삭제 사유 (필수, 작성자에게 보입니다)'), { target: { value: '욕설' } });
  fireEvent.click(within(sec).getByRole('button', { name: '삭제 확정' }));
  expect(await screen.findByText('댓글을 삭제했습니다. 작성자에게 알림이 갔습니다.')).toBeDefined();
  expect(rpcs('staff_delete_doc_comment')).toEqual([{ p_id: 1, p_note: '욕설' }]);
});

test('운영자 내 글·댓글: [지우기](작성자 삭제)만, [운영진 삭제]는 없음', async () => {
  TABLES.posts.push(fakePost(1, { author_id: 'u-op', author: { nickname: '영자', role: 'admin', level: 0 }, comment_count: 1 }));
  TABLES.post_comments.push(fakeComment(11, 1, { author_id: 'u-op', author: { nickname: '영자', role: 'admin', level: 0 }, body: '내 댓글' }));
  asOp();
  start('/board/1');
  const row = within(await screen.findByRole('list', { name: '댓글' })).getByRole('listitem');
  expect(moreNames(screen, '글 더보기')).not.toContain('운영진 삭제');
  expect(moreNames(within(row), '댓글 더보기')).toEqual(['지우기', '숨기기']);
});

test('비회원: 남의 댓글 ⋮ [신고]는 누를 수 없고 연결 안내가 보인다', async () => {
  TABLES.posts.push(fakePost(1, { author_id: 'u-x', author: OTHER, comment_count: 1 }));
  TABLES.post_comments.push(fakeComment(11, 1, { author_id: 'u-x', author: OTHER, body: '남의 댓글' }));
  fakeGuestLogin('u-guest');
  start('/board/1');
  const row = within(await screen.findByRole('list', { name: '댓글' })).getByRole('listitem');
  await within(row).findByRole('button', { name: '댓글 더보기' });
  const menu = openMore(within(row), '댓글 더보기');
  const report = menu.getByRole('menuitem', { name: '신고' });
  expect(report.getAttribute('aria-disabled')).toBe('true');
  expect(menu.getByText(/비회원은 신고할 수 없습니다/)).toBeDefined();
  fireEvent.click(report);
  expect(screen.queryByRole('button', { name: '신고 보내기' })).toBeNull();
});

test('⋮ 메뉴: 44px 버튼·aria, Esc로 닫으면 ⋮에 초점', async () => {
  TABLES.posts.push(fakePost(1, { author_id: 'u-x', author: OTHER, comment_count: 1 }));
  TABLES.post_comments.push(fakeComment(11, 1, { author_id: 'u-x', author: OTHER, body: '남의 댓글' }));
  fakeLogin('u-old');
  start('/board/1');
  const row = within(await screen.findByRole('list', { name: '댓글' })).getByRole('listitem');
  const btn = await within(row).findByRole('button', { name: '댓글 더보기' });
  expect(btn.getAttribute('aria-haspopup')).toBe('menu');
  expect(btn.classList.contains('more-btn')).toBe(true);
  fireEvent.click(btn);
  expect(btn.getAttribute('aria-expanded')).toBe('true');
  const item = within(row).getByRole('menuitem', { name: '신고' });
  expect(document.activeElement).toBe(item);
  fireEvent.keyDown(item, { key: 'Escape' });
  expect(btn.getAttribute('aria-expanded')).toBe('false');
  expect(document.activeElement).toBe(btn);
});

test('운영진 삭제 알림: 글은 링크 없음, 댓글은 그 글로, 문서 댓글은 그 문서로', () => {
  const post = describeNotification({ kind: 'post_deleted', message: '내 글 「광고」을 운영진이 삭제했습니다. 메모: 광고', post_id: null });
  expect(post).toMatchObject({ icon: 'ban', title: '내 글 「광고」을 운영진이 삭제했습니다.', detail: '메모: 광고', to: null });
  const comment = describeNotification({ kind: 'comment_deleted', message: '「글」에 쓴 내 댓글을 운영진이 삭제했습니다. 메모: 욕설', post_id: 5 });
  expect(comment).toMatchObject({ icon: 'ban', to: '/board/5', detail: '메모: 욕설' });
  const doc = describeNotification({
    kind: 'doc_comment_deleted', message: '문서에 쓴 내 댓글을 운영진이 삭제했습니다. 메모: 도배', counter_id: 1,
    counter: { target_champion: 'Darius', counter_champion: 'Quinn', status: 'approved' },
  });
  expect(doc.to).toBe('/champion/Darius/counter/Quinn#comments');
});

test('운영자 회원 정보: 지운 글·댓글 개수를 따로 보여 준다', async () => {
  fakeState.members = [{ id: 'u-1', nickname: '탑고수', role: 'user', level: 5, main_title: null, is_guest: false, created_at: '2026-11-01T00:00:00Z' }];
  fakeState.memberInfo = {
    'u-1': {
      id: 'u-1', nickname: '탑고수', role: 'user', level: 5, main_title: null, is_guest: false, created_at: '2026-11-01T03:00:00Z',
      providers: ['google'], titles: [], proposals: 0, posts: 3, builds: 0, comments: 11, deleted_posts: 2, deleted_comments: 4,
    },
  };
  asOp();
  start('/admin');
  fireEvent.change(await screen.findByLabelText('닉네임으로 회원 검색'), { target: { value: '탑' } });
  fireEvent.click(screen.getByRole('button', { name: '검색' }));
  fireEvent.click(within(await screen.findByRole('listitem', { name: '탑고수' })).getByRole('button', { name: '정보 보기' }));
  const info = await screen.findByRole('list', { name: '탑고수 회원 정보' });
  expect(info.textContent).toContain('지운 글 2개 · 지운 댓글 4개');
});
