// 058 (SPEC 6-53): 커뮤니티 댓글 답글(2단계) — 답글 달기, 답글에는 [답글] 없음, 지운 부모는 "삭제된 댓글입니다."
// 059 (SPEC 6-60): 문서 댓글 답글 — 비회원은 최상위 댓글만(답글은 안내), 빌드 카드 아래 빌드 댓글 칸은 없앰, 답글 알림 링크,
// 060 전에 남은 빌드 댓글 알림·신고는 문장만 / 건너뜀
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeComment, fakeDocComment, fakeGuestLogin, fakeLogin, fakePost, fakeState } from './fakeSupabase';
import { threadComments } from '../components/CommentThread';
import { moreNames } from './moreMenu';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /></MemoryRouter>);
const OTHER = { nickname: '남의글', level: 2, main_title: null };
const MATCHUP = '/champion/Darius/counter/Quinn';
const rpcs = (name) => fakeState.rpcCalls.filter((c) => c.name === name).map((c) => c.args);
const asked = (table) => fakeState.queryLog.filter((q) => q.table === table);
const asOp = () => fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0, main_title: null });
const topItems = (list) => [...list.children];

test('threadComments: 답글은 부모 밑으로, 부모가 안 보이면 자리만 남긴다 (부모 순서대로)', () => {
  const rows = [
    { id: 1, parent_id: null }, { id: 2, parent_id: 1 }, { id: 3, parent_id: 9 }, { id: 4, parent_id: null }, { id: 5, parent_id: 1 },
  ];
  const t = threadComments(rows);
  expect(t.map((x) => [x.comment?.id ?? null, x.parentId, x.replies.map((r) => r.id)])).toEqual([
    [1, 1, [2, 5]], [4, 4, []], [null, 9, [3]],
  ]);
});

// ---------------- 커뮤니티 글의 답글 ----------------

test('커뮤니티 댓글에 [답글] → p_parent로 올리고 부모 밑에 보임, 답글에는 [답글]이 없다', async () => {
  TABLES.posts.push(fakePost(1, { author_id: 'u-x', author: OTHER, comment_count: 1 }));
  TABLES.post_comments.push(fakeComment(11, 1, { author_id: 'u-x', author: OTHER, body: '부모 댓글' }));
  fakeLogin('u-old');
  start('/board/1');
  const list = await screen.findByRole('list', { name: '댓글' });
  const parent = topItems(list)[0];
  const replyBtn = within(parent).getByRole('button', { name: '답글' });
  expect(replyBtn.getAttribute('aria-expanded')).toBe('false');
  fireEvent.click(replyBtn);
  expect(within(parent).getByRole('button', { name: '답글 닫기' }).getAttribute('aria-expanded')).toBe('true');
  const field = within(parent).getByLabelText('답글 쓰기');
  expect(document.activeElement).toBe(field);
  fireEvent.change(field, { target: { value: '답글입니다' } });
  fireEvent.click(within(parent).getByRole('button', { name: '답글 올리기' }));
  const replies = await within(parent).findByRole('list', { name: '답글' });
  expect(within(replies).getByText('답글입니다')).toBeDefined();
  expect(rpcs('create_comment')).toEqual([{ p_post: 1, p_body: '답글입니다', p_media: [], p_parent: 11 }]);
  // 답글 칸은 닫히고, 답글에는 [답글] 버튼이 없다 (2단계까지)
  expect(within(parent).queryByLabelText('답글 쓰기')).toBeNull();
  const reply = within(replies).getAllByRole('listitem')[0];
  expect(within(reply).queryByRole('button', { name: '답글' })).toBeNull();
  expect(moreNames(within(reply), '답글 더보기')).toEqual(['고치기', '지우기']);
  // 새 댓글(맨 아래 칸)은 그대로 p_parent 없이
  fireEvent.change(screen.getByLabelText('댓글 쓰기'), { target: { value: '그냥 댓글' } });
  fireEvent.click(screen.getByRole('button', { name: '댓글 올리기' }));
  await vi.waitFor(() => expect(rpcs('create_comment')).toHaveLength(2));
  expect(rpcs('create_comment')[1]).toEqual({ p_post: 1, p_body: '그냥 댓글', p_media: [] });
});

test('답글 칸은 [취소]·Esc로 닫힌다', async () => {
  TABLES.posts.push(fakePost(1, { author_id: 'u-x', author: OTHER, comment_count: 1 }));
  TABLES.post_comments.push(fakeComment(11, 1, { author_id: 'u-x', author: OTHER }));
  fakeLogin('u-old');
  start('/board/1');
  const parent = topItems(await screen.findByRole('list', { name: '댓글' }))[0];
  fireEvent.click(within(parent).getByRole('button', { name: '답글' }));
  fireEvent.click(within(parent).getByRole('button', { name: '취소' }));
  expect(within(parent).queryByLabelText('답글 쓰기')).toBeNull();
  fireEvent.click(within(parent).getByRole('button', { name: '답글' }));
  fireEvent.keyDown(within(parent).getByLabelText('답글 쓰기'), { key: 'Escape' });
  expect(within(parent).queryByLabelText('답글 쓰기')).toBeNull();
});

test('부모가 지워졌으면 "삭제된 댓글입니다." 자리 밑에 답글이 남는다 (그 자리에는 [답글] 없음)', async () => {
  TABLES.posts.push(fakePost(1, { author_id: 'u-x', author: OTHER, comment_count: 1 }));
  // 부모 11은 지워져 select에 안 온다 (RLS) — 답글 12만 있다
  TABLES.post_comments.push(fakeComment(12, 1, { author_id: 'u-x', author: OTHER, body: '남은 답글', parent_id: 11 }));
  fakeLogin('u-old');
  start('/board/1');
  const list = await screen.findByRole('list', { name: '댓글' });
  const gone = topItems(list)[0];
  expect(gone.classList.contains('gone-row')).toBe(true);
  expect(within(gone).getByText('삭제된 댓글입니다.')).toBeDefined();
  expect(within(within(gone).getByRole('list', { name: '답글' })).getByText('남은 답글')).toBeDefined();
  expect(within(gone).queryByRole('button', { name: '답글' })).toBeNull();
});

test('비로그인은 답글을 볼 수 있지만 [답글] 버튼은 없다', async () => {
  TABLES.posts.push(fakePost(1, { author_id: 'u-x', author: OTHER, comment_count: 2 }));
  TABLES.post_comments.push(
    fakeComment(11, 1, { author_id: 'u-x', author: OTHER, body: '부모' }),
    fakeComment(12, 1, { author_id: 'u-y', author: OTHER, body: '자식', parent_id: 11 }),
  );
  start('/board/1');
  const list = await screen.findByRole('list', { name: '댓글' });
  expect(within(within(list).getByRole('list', { name: '답글' })).getByText('자식')).toBeDefined();
  expect(screen.queryByRole('button', { name: '답글' })).toBeNull();
  expect(screen.getByText(/하면 댓글을 달 수 있습니다/)).toBeDefined();
});

test('글 보기: 글·댓글·내 추천을 한꺼번에 요청한다', async () => {
  TABLES.posts.push(fakePost(1, { author_id: 'u-x', author: OTHER }));
  fakeLogin('u-old');
  const before = fakeState.queryLog.length;
  start('/board/1');
  await screen.findByRole('list', { name: '댓글' }).catch(() => screen.findByText('아직 댓글이 없습니다.'));
  const tables = fakeState.queryLog.slice(before).map((q) => q.table);
  // 셋 다 첫 응답이 오기 전에 보냈다 → 순서가 posts, post_comments, post_votes로 붙어 있다
  const i = tables.indexOf('posts');
  expect(tables.slice(i, i + 3)).toEqual(['posts', 'post_comments', 'post_votes']);
});

// ---------------- 문서 댓글 답글 (059) ----------------

const docSection = async () => (await screen.findByRole('heading', { name: /4\. 댓글/ })).closest('section');

test('문서 댓글에 [답글] → p_parent로 올리고 부모 밑에 보임, 답글에는 [답글]이 없다 / 빌드 카드 아래 빌드 댓글 칸은 없다', async () => {
  TABLES.doc_comments.push(fakeDocComment(21, { author_id: 'u-x', author: OTHER, body: '부모 문서 댓글' }));
  fakeLogin('u-old');
  start(`${MATCHUP}?build=102`);
  const sec = await docSection();
  const parent = topItems(await within(sec).findByRole('list', { name: '댓글' }))[0];
  fireEvent.click(within(parent).getByRole('button', { name: '답글' }));
  const field = within(parent).getByLabelText('답글 쓰기');
  expect(document.activeElement).toBe(field);
  fireEvent.change(field, { target: { value: '문서 답글입니다' } });
  fireEvent.click(within(parent).getByRole('button', { name: '답글 올리기' }));
  const replies = await within(parent).findByRole('list', { name: '답글' });
  expect(within(replies).getByText('문서 답글입니다')).toBeDefined();
  expect(rpcs('create_doc_comment')).toEqual([{ p_counter: 1, p_body: '문서 답글입니다', p_parent: 21 }]);
  const reply = within(replies).getAllByRole('listitem')[0];
  expect(within(reply).queryByRole('button', { name: '답글' })).toBeNull();
  // 새 댓글(맨 아래 칸)은 그대로 p_parent 없이, 사진 없음
  fireEvent.change(within(sec).getByLabelText('댓글 쓰기'), { target: { value: '그냥 문서 댓글' } });
  fireEvent.click(within(sec).getByRole('button', { name: '댓글 올리기' }));
  await vi.waitFor(() => expect(rpcs('create_doc_comment')).toHaveLength(2));
  expect(rpcs('create_doc_comment')[1]).toEqual({ p_counter: 1, p_body: '그냥 문서 댓글' });
  expect(within(sec).queryByRole('button', { name: /사진·GIF 추가/ })).toBeNull();
  // 058 빌드 댓글 칸은 없앴다: 버튼·요청·빌드 댓글 수 읽기 모두 없음
  expect(screen.queryByRole('button', { name: /빌드 댓글/ })).toBeNull();
  expect(document.getElementById('build-comments')).toBeNull();
  expect(asked('build_comments')).toHaveLength(0);
  expect(asked('builds').some((q) => String(q.select ?? '').includes('comment_count'))).toBe(false);
});

test('문서 댓글: 비회원은 최상위 댓글만 — [답글] 없이 안내 한 줄, 비로그인은 로그인 안내 (답글은 둘 다 읽힘)', async () => {
  TABLES.doc_comments.push(
    fakeDocComment(21, { author_id: 'u-x', author: OTHER, body: '부모' }),
    fakeDocComment(22, { author_id: 'u-y', author: OTHER, body: '자식 답글', parent_id: 21 }),
  );
  fakeGuestLogin('g-1', { nickname: '손님' });
  start(MATCHUP);
  const sec = await docSection();
  expect(await within(sec).findByText('자식 답글')).toBeDefined();
  expect(within(sec).queryByRole('button', { name: '답글' })).toBeNull();
  expect(within(sec).getByText(/비회원은 답글을 달 수 없습니다/)).toBeDefined();
  expect(within(sec).getByLabelText('댓글 쓰기')).toBeDefined();
  fireEvent.change(within(sec).getByLabelText('댓글 쓰기'), { target: { value: '손님 댓글' } });
  fireEvent.click(within(sec).getByRole('button', { name: '댓글 올리기' }));
  await vi.waitFor(() => expect(rpcs('create_doc_comment')).toEqual([{ p_counter: 1, p_body: '손님 댓글' }]));
  cleanup();
  fakeState.session = null;
  start(MATCHUP);
  const sec2 = await docSection();
  expect(await within(sec2).findByText('자식 답글')).toBeDefined();
  expect(within(sec2).queryByRole('button', { name: '답글' })).toBeNull();
  expect(within(sec2).queryByText(/비회원은 답글을/)).toBeNull();
  expect(within(sec2).getByText(/하면 댓글을 달 수 있습니다/)).toBeDefined();
});

test('문서 댓글: 부모를 지우면 답글은 남고 "삭제된 댓글입니다."', async () => {
  TABLES.doc_comments.push(
    fakeDocComment(21, { author_id: 'u-old', body: '내 문서 댓글' }),
    fakeDocComment(22, { author_id: 'u-x', author: OTHER, body: '남의 문서 답글', parent_id: 21 }),
  );
  fakeLogin('u-old');
  start(MATCHUP);
  const sec = await docSection();
  const mine = topItems(await within(sec).findByRole('list', { name: '댓글' }))[0];
  fireEvent.click(within(mine).getByRole('button', { name: '댓글 더보기' }));
  fireEvent.click(await screen.findByRole('menuitem', { name: '지우기' }));
  fireEvent.click(within(within(mine).getByRole('group', { name: /지우시겠습니까/ })).getByRole('button', { name: '지우기' }));
  expect(await within(sec).findByText('삭제된 댓글입니다.')).toBeDefined();
  expect(within(sec).getByText('남의 문서 답글')).toBeDefined();
  expect(rpcs('delete_my_doc_comment')).toEqual([{ p_id: 21 }]);
});

// ---------------- 알림 ----------------

test('답글 알림: 문서 답글은 그 문서의 댓글 칸으로, 글의 답글은 그 글로 / 060 전에 남은 빌드 댓글 알림은 문장만', async () => {
  const noti = (id, kind, extra) => ({
    id, user_id: 'u-old', kind, message: null, proposal_id: null, build_id: null, post_id: null, counter_id: null,
    created_at: `2026-11-02T0${id}:00:00Z`, read_at: '2026-11-02T10:00:00Z', ...extra,
  });
  TABLES.posts.push(fakePost(5));
  TABLES.notifications.push(
    noti(1, 'comment_reply', { counter_id: 1, message: '상대법 문서에 쓴 내 댓글에 새 답글이 달렸습니다.' }),
    noti(2, 'comment_reply', { post_id: 5, message: '내 댓글에 새 답글 2개가 달렸습니다.' }),
    noti(3, 'build_comment', { build_id: 102, counter_id: 1, message: '내 빌드에 새 댓글이 달렸습니다.' }),
    noti(4, 'comment_reply', { build_id: 102, counter_id: 1, message: '빌드 「정석」에 쓴 내 댓글에 새 답글이 달렸습니다.' }),
  );
  fakeLogin('u-old');
  start('/notifications');
  const row = async (text) => (await screen.findByText(text)).closest('li');
  const href = (li) => within(li).queryByRole('link')?.getAttribute('href') ?? null;
  const doc = await row('상대법 문서에 쓴 내 댓글에 새 답글이 달렸습니다.');
  expect(href(doc)).toBe(`${MATCHUP}#comments`);
  expect(doc.textContent).toContain('퀸으로 다리우스 이기는 법');
  expect(doc.querySelector('.noti-icon.comment')).not.toBeNull();
  expect(href(await row('내 댓글에 새 답글 2개가 달렸습니다.'))).toBe('/board/5');
  expect(href(await row('내 빌드에 새 댓글이 달렸습니다.'))).toBeNull();
  expect(href(await row('빌드 「정석」에 쓴 내 댓글에 새 답글이 달렸습니다.'))).toBeNull();
});

// ---------------- 운영진 ----------------

test('운영자 /admin/reports: 060 전에 남은 빌드 댓글 신고는 건너뛰고, 문서 댓글 답글 신고는 그대로 / 숨긴 목록은 빌드 댓글을 안 읽음', async () => {
  TABLES.doc_comments.push(fakeDocComment(22, { author_id: 'u-x', author: OTHER, body: '나쁜 문서 답글', parent_id: 21 }));
  const rep = (id, extra) => ({
    id, reporter_id: `u-r${id}`, post_id: null, comment_id: null, doc_comment_id: null, build_comment_id: null, reason: 'spam', detail: null,
    status: 'open', created_at: `2026-11-01T0${id}:00:00Z`, reporter: { nickname: `신고자${id}`, level: 1, main_title: null }, ...extra,
  });
  TABLES.reports.push(rep(1, { build_comment_id: 31 }), rep(2, { doc_comment_id: 22 }));
  asOp();
  start('/admin/reports');
  const list = await screen.findByRole('list', { name: '신고 목록' });
  expect(within(list).getAllByRole('listitem', { name: /신고 \d+건/ }).map((g) => g.getAttribute('aria-label'))).toEqual(['문서 댓글 신고 1건']);
  const g = within(list).getByRole('listitem', { name: '문서 댓글 신고 1건' });
  expect(g.textContent).toContain('나쁜 문서 답글');
  fireEvent.click(within(g).getByRole('button', { name: '신고 기각' }));
  fireEvent.click(within(g).getByRole('button', { name: '기각 확정' }));
  await vi.waitFor(() => expect(rpcs('dismiss_reports')).toEqual([{ p_post: null, p_comment: null, p_note: null, p_doc_comment: 22 }]));
  cleanup();
  start('/admin');
  await screen.findByRole('heading', { name: '숨긴 글·댓글' });
  expect(asked('build_comments')).toHaveLength(0);
});
