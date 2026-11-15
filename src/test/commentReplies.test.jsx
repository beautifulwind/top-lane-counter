// 058 (SPEC 6-53): 커뮤니티 댓글 답글(2단계) + 빌드 댓글·답글 — 답글 달기, 답글에는 [답글] 없음, 지운 부모는 "삭제된 댓글입니다.",
// 비회원은 안내만, 빌드 댓글은 펼칠 때만 읽기(#build-comments면 펼친 채), 새 알림 종류, 운영진 신고·숨김 목록
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeBuildComment, fakeComment, fakeGuestLogin, fakeLogin, fakePost, fakeState } from './fakeSupabase';
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

// ---------------- 빌드 댓글 ----------------

test('빌드 댓글: 처음엔 개수만(댓글은 안 읽음) → [펼치기]로 읽고, 달기·답글', async () => {
  TABLES.builds.find((b) => b.id === 102).comment_count = 1;
  TABLES.build_comments.push(fakeBuildComment(31, 102, { author_id: 'u-x', author: OTHER, body: '이 빌드 좋네요' }));
  fakeLogin('u-old');
  start(`${MATCHUP}?build=102`);
  const toggle = await screen.findByRole('button', { name: /빌드 댓글/ });
  expect(toggle.getAttribute('aria-expanded')).toBe('false');
  expect(toggle.textContent).toContain('1개');
  expect(toggle.textContent).toContain('펼치기');
  expect(asked('build_comments')).toHaveLength(0);

  fireEvent.click(toggle);
  expect(toggle.getAttribute('aria-expanded')).toBe('true');
  const box = document.getElementById('build-comments');
  const list = await within(box).findByRole('list', { name: '빌드 댓글' });
  expect(asked('build_comments')).toHaveLength(1);
  expect(within(list).getByText('이 빌드 좋네요')).toBeDefined();

  fireEvent.change(within(box).getByLabelText('댓글 쓰기'), { target: { value: '저도 써 봤어요' } });
  fireEvent.click(within(box).getByRole('button', { name: '댓글 올리기' }));
  await vi.waitFor(() => expect(toggle.textContent).toContain('2개'));
  expect(rpcs('create_build_comment')).toEqual([{ p_build: 102, p_body: '저도 써 봤어요' }]);

  const parent = topItems(within(box).getByRole('list', { name: '빌드 댓글' }))[0];
  fireEvent.click(within(parent).getByRole('button', { name: '답글' }));
  fireEvent.change(within(parent).getByLabelText('답글 쓰기'), { target: { value: '감사합니다' } });
  fireEvent.click(within(parent).getByRole('button', { name: '답글 올리기' }));
  expect(await within(parent).findByText('감사합니다')).toBeDefined();
  expect(rpcs('create_build_comment')[1]).toEqual({ p_build: 102, p_body: '감사합니다', p_parent: 31 });
  // 빌드 댓글에는 사진이 없다
  expect(within(box).queryByRole('button', { name: /사진·GIF 추가/ })).toBeNull();
  // 문서 댓글(4. 댓글)은 그대로 따로
  expect(rpcs('create_doc_comment')).toEqual([]);

  fireEvent.click(toggle);
  expect(toggle.textContent).toContain('펼치기');
  expect(document.getElementById('build-comments-body')).toBeNull();
});

test('알림에서 #build-comments로 오면 빌드 댓글을 펼친 채로 연다', async () => {
  TABLES.build_comments.push(fakeBuildComment(31, 102, { author_id: 'u-x', author: OTHER, body: '알림 온 댓글' }));
  fakeLogin('u-old');
  start(`${MATCHUP}?build=102#build-comments`);
  expect(await screen.findByText('알림 온 댓글')).toBeDefined();
  expect(screen.getByRole('button', { name: /빌드 댓글/ }).getAttribute('aria-expanded')).toBe('true');
});

test('빌드 댓글: 비회원은 안내만, 비로그인은 로그인 안내 (읽기는 둘 다 됨)', async () => {
  TABLES.build_comments.push(fakeBuildComment(31, 102, { author_id: 'u-x', author: OTHER, body: '읽을 수 있는 댓글' }));
  fakeGuestLogin('g-1', { nickname: '손님' });
  start(`${MATCHUP}?build=102#build-comments`);
  const box = document.getElementById('build-comments') ?? (await screen.findByText('읽을 수 있는 댓글')).closest('#build-comments');
  await within(box).findByText('읽을 수 있는 댓글');
  expect(within(box).getByText(/비회원은 댓글을 달 수 없습니다/)).toBeDefined();
  expect(within(box).queryByLabelText('댓글 쓰기')).toBeNull();
  expect(within(box).queryByRole('button', { name: '답글' })).toBeNull();
  cleanup();
  fakeState.session = null;
  start(`${MATCHUP}?build=102#build-comments`);
  const box2 = (await screen.findByText('읽을 수 있는 댓글')).closest('#build-comments');
  expect(within(box2).getByText(/하면 댓글을 달 수 있습니다/)).toBeDefined();
});

test('빌드 댓글: 부모를 지우면 답글은 남고 "삭제된 댓글입니다."', async () => {
  TABLES.build_comments.push(
    fakeBuildComment(31, 102, { author_id: 'u-old', body: '내 댓글', created_at: new Date().toISOString() }),
    fakeBuildComment(32, 102, { author_id: 'u-x', author: OTHER, body: '남의 답글', parent_id: 31 }),
  );
  fakeLogin('u-old');
  start(`${MATCHUP}?build=102#build-comments`);
  const box = (await screen.findByText('내 댓글')).closest('#build-comments');
  const mine = topItems(within(box).getByRole('list', { name: '빌드 댓글' }))[0];
  fireEvent.click(within(mine).getByRole('button', { name: '댓글 더보기' }));
  fireEvent.click(await screen.findByRole('menuitem', { name: '지우기' }));
  fireEvent.click(within(within(mine).getByRole('group', { name: /지우시겠습니까/ })).getByRole('button', { name: '지우기' }));
  expect(await within(box).findByText('삭제된 댓글입니다.')).toBeDefined();
  expect(within(box).getByText('남의 답글')).toBeDefined();
  expect(rpcs('delete_my_build_comment')).toEqual([{ p_id: 31 }]);
});

// ---------------- 알림 ----------------

test('새 알림: 빌드 댓글·빌드 답글은 그 빌드 댓글 칸으로, 글의 답글은 그 글로, 숨김은 메모 둘째 줄', async () => {
  const noti = (id, kind, extra) => ({
    id, user_id: 'u-old', kind, message: null, proposal_id: null, build_id: null, post_id: null, counter_id: null,
    created_at: `2026-11-02T0${id}:00:00Z`, read_at: '2026-11-02T10:00:00Z', ...extra,
  });
  TABLES.posts.push(fakePost(5));
  TABLES.notifications.push(
    noti(1, 'build_comment', { build_id: 102, message: '내 빌드에 새 댓글이 달렸습니다.' }),
    noti(2, 'comment_reply', { build_id: 102, message: '내 빌드 댓글에 새 답글이 달렸습니다.' }),
    noti(3, 'comment_reply', { post_id: 5, message: '내 댓글에 새 답글 2개가 달렸습니다.' }),
    noti(4, 'build_comment_hidden', { build_id: 102, message: '운영진이 내 빌드 댓글을 숨겼습니다. 메모: 욕설' }),
  );
  fakeLogin('u-old');
  start('/notifications');
  const row = async (text) => (await screen.findByText(text)).closest('li');
  const href = (li) => within(li).queryByRole('link')?.getAttribute('href') ?? null;
  const b = await row('내 빌드에 새 댓글이 달렸습니다.');
  expect(href(b)).toBe(`${MATCHUP}?build=102#build-comments`);
  expect(b.textContent).toContain('[빌드] 퀸으로 다리우스 이기는 법');
  expect(b.querySelector('.noti-icon.comment')).not.toBeNull();
  expect(href(await row('내 빌드 댓글에 새 답글이 달렸습니다.'))).toBe(`${MATCHUP}?build=102#build-comments`);
  expect(href(await row('내 댓글에 새 답글 2개가 달렸습니다.'))).toBe('/board/5');
  const hidden = await row('운영진이 내 빌드 댓글을 숨겼습니다.');
  expect(hidden.textContent).toContain('메모: 욕설');
  expect(hidden.querySelector('.noti-icon.hidden')).not.toBeNull();
});

// ---------------- 운영진 ----------------

test('운영자 /admin/reports: 빌드 댓글 신고 → 빌드 이름·보러 가기, 숨기기 / 기각은 p_build_comment', async () => {
  TABLES.build_comments.push(
    fakeBuildComment(31, 102, { author_id: 'u-x', author: OTHER, body: '나쁜 빌드 댓글' }),
    fakeBuildComment(32, 102, { author_id: 'u-x', author: OTHER, body: '애매한 빌드 댓글' }),
  );
  const rep = (id, extra) => ({
    id, reporter_id: `u-r${id}`, post_id: null, comment_id: null, doc_comment_id: null, build_comment_id: null, reason: 'spam', detail: null,
    status: 'open', created_at: `2026-11-01T0${id}:00:00Z`, reporter: { nickname: `신고자${id}`, level: 1, main_title: null }, ...extra,
  });
  TABLES.reports.push(rep(1, { build_comment_id: 31 }), rep(2, { build_comment_id: 32 }));
  asOp();
  start('/admin/reports');
  const list = await screen.findByRole('list', { name: '신고 목록' });
  const groups = within(list).getAllByRole('listitem', { name: '빌드 댓글 신고 1건' });
  const bad = groups.find((g) => g.textContent.includes('나쁜 빌드 댓글'));
  expect(bad.textContent).toContain('빌드 2');
  expect(within(bad).getByRole('link', { name: /보러 가기/ }).getAttribute('href')).toBe(`${MATCHUP}?build=102#build-comments`);
  fireEvent.click(within(bad).getByRole('button', { name: '숨기기' }));
  fireEvent.change(within(bad).getByLabelText(/숨기는 사유/), { target: { value: '도배' } });
  fireEvent.click(within(bad).getByRole('button', { name: '숨기기 확정' }));
  await vi.waitFor(() => expect(rpcs('hide_build_comment')).toEqual([{ p_id: 31, p_note: '도배' }]));

  const left = await vi.waitFor(() => {
    const g = within(screen.getByRole('list', { name: '신고 목록' })).getByRole('listitem', { name: '빌드 댓글 신고 1건' });
    expect(g.textContent).toContain('애매한 빌드 댓글');
    return g;
  });
  fireEvent.click(within(left).getByRole('button', { name: '신고 기각' }));
  fireEvent.click(within(left).getByRole('button', { name: '기각 확정' }));
  await vi.waitFor(() => expect(rpcs('dismiss_reports')).toEqual([{ p_post: null, p_comment: null, p_note: null, p_doc_comment: null, p_build_comment: 32 }]));
});

test('운영자 /admin: 숨긴 빌드 댓글도 목록에 → [다시 공개]', async () => {
  TABLES.build_comments.push(fakeBuildComment(31, 102, {
    author_id: 'u-x', author: OTHER, body: '숨긴 빌드 댓글', status: 'hidden', hidden_note: '욕설', hidden_at: '2026-11-02T00:00:00Z',
  }));
  asOp();
  start('/admin');
  const row = await screen.findByRole('listitem', { name: '[숨긴 빌드 댓글] 숨긴 빌드 댓글' });
  expect(within(row).getByRole('link', { name: '보러 가기' }).getAttribute('href')).toBe(`${MATCHUP}?build=102#build-comments`);
  fireEvent.click(within(row).getByRole('button', { name: '다시 공개' }));
  fireEvent.change(within(row).getByLabelText(/다시 공개 메모/), { target: { value: '오해' } });
  fireEvent.click(within(row).getByRole('button', { name: '다시 공개 확정' }));
  await vi.waitFor(() => expect(rpcs('restore_build_comment')).toEqual([{ p_id: 31, p_note: '오해' }]));
});
