// 7단계: 자유게시판 — 목록·검색·쪽, 글쓰기·고치기·지우기(삭제된 글로 남기기), 추천, 댓글, 신고, 운영자 숨기기·다시 공개·신고 처리, 알림
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeComment, fakeLogin, fakePost, fakeState } from './fakeSupabase';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

let where = null;
function Where() {
  const l = useLocation();
  where = l.pathname + l.search;
  return null;
}
const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /><Where /></MemoryRouter>);
const OTHER = { nickname: '남의글', level: 2, main_title: null };
const asOp = () => fakeLogin('u-op', { nickname: '영자(운)', role: 'admin', level: 0, main_title: null });
const rpcs = (name) => fakeState.rpcCalls.filter((c) => c.name === name).map((c) => c.args);

test('상단에 게시판 링크', async () => {
  start('/');
  expect(screen.getByRole('link', { name: '게시판' }).getAttribute('href')).toBe('/board');
});

test('비로그인 목록: 최신순, 댓글 수·추천, 삭제된 글, 숨긴 글은 안 보임, [로그인하고 글쓰기]', async () => {
  TABLES.posts.push(
    fakePost(1, { title: '오래된 글', comment_count: 2 }),
    fakePost(2, { title: '새 글', up_count: 3, author_id: 'u-x', author: OTHER }),
    fakePost(3, { title: '', body: '', deleted_at: '2026-11-01T05:00:00Z', comment_count: 1 }),
    fakePost(4, { title: '숨긴 글', status: 'hidden', hidden_note: '광고' }),
  );
  start('/board');
  const list = await screen.findByRole('list', { name: '글 목록' });
  const rows = within(list).getAllByRole('listitem').map((li) => li.querySelector('.post-title').textContent);
  expect(rows).toEqual(['(삭제된 글)', '새 글', '오래된 글']);
  expect(within(list).getByLabelText('댓글 2개')).toBeDefined();
  expect(within(list).getByLabelText('추천 3')).toBeDefined();
  expect(screen.queryByText('숨긴 글')).toBeNull();
  expect(screen.getByRole('link', { name: '로그인하고 글쓰기' })).toBeDefined();
});

test('검색: 주소에 남고, [검색 지우기]로 돌아온다 / 쪽 이동', async () => {
  for (let i = 1; i <= 25; i += 1) {
    TABLES.posts.push(fakePost(i, { title: i === 7 ? '퀸 공략' : `잡담 ${i}`, created_at: `2026-11-01T00:${String(i).padStart(2, '0')}:00Z` }));
  }
  start('/board');
  const list = await screen.findByRole('list', { name: '글 목록' });
  expect(within(list).getAllByRole('listitem')).toHaveLength(20);
  fireEvent.click(screen.getByRole('button', { name: '2쪽' }));
  await vi.waitFor(() => expect(where).toBe('/board?page=2'));
  expect(await screen.findByText('잡담 5')).toBeDefined();
  expect(within(screen.getByRole('list', { name: '글 목록' })).getAllByRole('listitem')).toHaveLength(5);

  fireEvent.change(screen.getByLabelText('제목·본문 검색'), { target: { value: '퀸' } });
  fireEvent.click(screen.getByRole('button', { name: '검색' }));
  await vi.waitFor(() => expect(where).toBe('/board?q=%ED%80%B8'));
  expect(await screen.findByText(/‘퀸’ 검색 결과 1개/)).toBeDefined();
  expect(screen.getByText('퀸 공략')).toBeDefined();
  expect(fakeState.rpcCalls).toContainEqual({ name: 'board_page', args: { p_q: '퀸', p_page: 1, p_size: 20 } });
  fireEvent.click(screen.getByRole('button', { name: '검색 지우기' }));
  await vi.waitFor(() => expect(where).toBe('/board'));
  expect(screen.getByLabelText('제목·본문 검색').value).toBe('');
});

test('글쓰기: 빈 칸이면 못 보냄, 올리면 글로 이동 / 도배 간격 오류는 그대로 보여 준다', async () => {
  fakeLogin('u-old');
  start('/board/new');
  const send = await screen.findByRole('button', { name: '올리기' });
  expect(send.disabled).toBe(true);
  fireEvent.change(screen.getByLabelText('제목'), { target: { value: '  첫 글 ' } });
  fireEvent.change(screen.getByLabelText('본문'), { target: { value: '안녕\n하세요' } });
  expect(screen.getByText('3/100')).toBeDefined(); // 앞뒤 공백 빼고
  fakeState.boardError = '글은 30초에 한 번 쓸 수 있어요. 12초 뒤에 다시 해 주세요.';
  fireEvent.click(send);
  expect((await screen.findByRole('alert')).textContent).toBe('글은 30초에 한 번 쓸 수 있어요. 12초 뒤에 다시 해 주세요.');
  expect(screen.getByLabelText('제목').value).toBe('  첫 글 '); // 쓴 내용 그대로

  fakeState.boardError = null;
  fireEvent.click(send);
  expect(await screen.findByText('글을 올렸어요.')).toBeDefined();
  expect(where).toBe('/board/700');
  expect(screen.getByRole('heading', { level: 1 }).textContent).toBe('첫 글');
  expect(document.querySelector('.post-body').textContent).toBe('안녕\n하세요');
  expect(rpcs('create_post')).toEqual([
    { p_title: '  첫 글 ', p_body: '안녕\n하세요' }, { p_title: '  첫 글 ', p_body: '안녕\n하세요' },
  ]);
});

test('비로그인 글 보기: 본문·댓글, 추천은 숫자만, 댓글은 로그인 안내', async () => {
  TABLES.posts.push(fakePost(1, { author_id: 'u-x', author: OTHER, up_count: 2, comment_count: 1 }));
  TABLES.post_comments.push(fakeComment(11, 1, { body: '좋은 글', edited_at: '2026-11-01T12:00:00Z' }));
  start('/board/1');
  expect(await screen.findByText('본문 1')).toBeDefined();
  const c = within(screen.getByRole('list', { name: '댓글' })).getByRole('listitem');
  expect(c.textContent).toContain('좋은 글');
  expect(within(c).getByText('수정됨')).toBeDefined();
  expect(screen.getByLabelText('추천 2')).toBeDefined();
  expect(screen.queryByRole('button', { name: /추천/ })).toBeNull();
  expect(screen.queryByRole('button', { name: '신고' })).toBeNull();
  expect(screen.getByText(/하면 댓글을 달 수 있어요/)).toBeDefined();
});

test('숨긴 글·없는 글은 "글을 찾지 못했어요"', async () => {
  TABLES.posts.push(fakePost(1, { status: 'hidden', hidden_note: '광고' }));
  start('/board/1');
  expect(await screen.findByText('지워졌거나 운영자가 숨긴 글이에요.')).toBeDefined();
});

test('남의 글: 추천 누르기·취소, 신고(이유 필수, 기타는 내용 필수)', async () => {
  TABLES.posts.push(fakePost(1, { author_id: 'u-x', author: OTHER, up_count: 1 }));
  TABLES.post_votes.push({ post_id: 1, user_id: 'u-y' });
  fakeLogin('u-old');
  start('/board/1');
  const vote = await screen.findByRole('button', { name: '👍 추천 1' });
  expect(vote.getAttribute('aria-pressed')).toBe('false');
  fireEvent.click(vote);
  expect(await screen.findByRole('button', { name: '👍 추천 2' })).toBeDefined();
  expect(screen.getByRole('button', { name: '👍 추천 2' }).getAttribute('aria-pressed')).toBe('true');
  fireEvent.click(screen.getByRole('button', { name: '👍 추천 2' }));
  expect(await screen.findByRole('button', { name: '👍 추천 1' })).toBeDefined();
  expect(screen.queryByRole('button', { name: '고치기' })).toBeNull();

  fireEvent.click(screen.getByRole('button', { name: '신고' }));
  const form = screen.getByRole('group', { name: '글 신고 — 이유를 골라 주세요' }).closest('form');
  const send = within(form).getByRole('button', { name: '신고하기' });
  expect(send.disabled).toBe(true);
  fireEvent.click(within(form).getByLabelText('기타'));
  expect(send.disabled).toBe(true); // 기타는 내용 필수
  fireEvent.change(within(form).getByLabelText('내용 (필수)'), { target: { value: '홍보 링크' } });
  fireEvent.click(send);
  expect(await screen.findByText('신고했어요. 운영자가 확인할게요.')).toBeDefined();
  expect(rpcs('report_post')).toEqual([{ p_id: 1, p_reason: 'other', p_detail: '홍보 링크' }]);

  // 같은 글을 또 신고하면 DB가 막는다
  fireEvent.click(await screen.findByRole('button', { name: '신고' }));
  fireEvent.click(screen.getByLabelText('도배·광고'));
  fireEvent.click(screen.getByRole('button', { name: '신고하기' }));
  expect((await screen.findByRole('alert')).textContent).toBe('이미 신고한 글이에요.');
});

test('내 글: 고치기 → 수정됨, 지우기 (남의 댓글 있으면 "삭제된 글"로 남음)', async () => {
  TABLES.posts.push(fakePost(1, { comment_count: 1 }));
  TABLES.post_comments.push(fakeComment(11, 1, { author_id: 'u-x', author: OTHER, body: '남의 댓글' }));
  fakeLogin('u-old');
  start('/board/1');
  fireEvent.click(await screen.findByRole('link', { name: '고치기' }));
  const title = await screen.findByLabelText('제목');
  expect(title.value).toBe('글 1');
  fireEvent.change(title, { target: { value: '글 1 (고침)' } });
  fireEvent.click(screen.getByRole('button', { name: '고친 내용 저장' }));
  expect(await screen.findByText('글을 고쳤어요.')).toBeDefined();
  expect(screen.getByRole('heading', { level: 1 }).textContent).toBe('글 1 (고침)');
  expect(document.querySelector('.post-meta .edited').textContent).toBe('수정됨');
  expect(screen.queryByRole('button', { name: /추천/ })).toBeNull(); // 내 글은 추천 못 함

  fireEvent.click(screen.getByRole('button', { name: '지우기' }));
  const confirm = screen.getByRole('group', { name: '글을 지울까요? 다른 사람 댓글은 남아요.' });
  fireEvent.click(within(confirm).getByRole('button', { name: '지우기' }));
  expect(await screen.findByText('글을 지웠어요. 다른 사람 댓글이 있어서 "삭제된 글"로 남아요.')).toBeDefined();
  await vi.waitFor(() => expect(screen.getByRole('heading', { level: 1 }).textContent).toBe('(삭제된 글)'));
  expect(screen.getByText('남의 댓글')).toBeDefined();
  expect(screen.getByText('삭제된 글에는 댓글을 달 수 없어요.')).toBeDefined();
});

test('내 글: 남의 댓글이 없으면 완전히 지우고 목록으로', async () => {
  TABLES.posts.push(fakePost(1));
  fakeLogin('u-old');
  start('/board/1');
  fireEvent.click(await screen.findByRole('button', { name: '지우기' }));
  fireEvent.click(within(screen.getByRole('group', { name: '글을 지울까요?' })).getByRole('button', { name: '지우기' }));
  expect(await screen.findByText('글을 지웠어요.')).toBeDefined();
  expect(where).toBe('/board');
  expect(await screen.findByText('아직 글이 없어요. 첫 글을 써 보세요!')).toBeDefined();
});

test('남의 글 고치기 주소로 들어오면 막는다', async () => {
  TABLES.posts.push(fakePost(1, { author_id: 'u-x', author: OTHER }));
  fakeLogin('u-old');
  start('/board/1/edit');
  expect(await screen.findByText('고칠 수 있는 내 글이 아니에요.')).toBeDefined();
});

test('댓글: 달기(빈 칸이면 못 보냄) → 바로 보임, 내 댓글 고치기·지우기, 남의 댓글은 신고', async () => {
  TABLES.posts.push(fakePost(1, { author_id: 'u-x', author: OTHER, comment_count: 1 }));
  TABLES.post_comments.push(fakeComment(11, 1, { author_id: 'u-x', author: OTHER, body: '남의 댓글' }));
  fakeLogin('u-old');
  start('/board/1');
  const send = await screen.findByRole('button', { name: '댓글 달기' });
  expect(send.disabled).toBe(true);
  fireEvent.change(screen.getByLabelText('댓글 쓰기'), { target: { value: '내 댓글이에요' } });
  fireEvent.click(send);
  expect(await screen.findByRole('heading', { name: '댓글 2' })).toBeDefined();
  expect(within(screen.getByRole('list', { name: '댓글' })).getByText('내 댓글이에요')).toBeDefined();
  expect(screen.getByLabelText('댓글 쓰기').value).toBe('');
  expect(rpcs('create_comment')).toEqual([{ p_post: 1, p_body: '내 댓글이에요' }]);

  const [other, mine] = within(screen.getByRole('list', { name: '댓글' })).getAllByRole('listitem');
  expect(within(other).queryByRole('button', { name: '고치기' })).toBeNull();
  expect(within(other).getByRole('button', { name: '신고' })).toBeDefined();
  expect(within(mine).queryByRole('button', { name: '신고' })).toBeNull();

  fireEvent.click(within(mine).getByRole('button', { name: '고치기' }));
  fireEvent.change(within(mine).getByLabelText('댓글 고치기'), { target: { value: '고친 댓글' } });
  fireEvent.click(within(mine).getByRole('button', { name: '저장' }));
  await vi.waitFor(() => expect(document.querySelectorAll('.comment-body')[1]?.textContent).toBe('고친 댓글'));
  const mine2 = within(screen.getByRole('list', { name: '댓글' })).getAllByRole('listitem')[1];
  expect(within(mine2).getByText('수정됨')).toBeDefined();

  fireEvent.click(within(mine2).getByRole('button', { name: '지우기' }));
  fireEvent.click(within(within(mine2).getByRole('group', { name: '댓글을 지울까요?' })).getByRole('button', { name: '지우기' }));
  await vi.waitFor(() => expect(screen.queryByText('고친 댓글')).toBeNull());
  expect(screen.getByRole('heading', { name: '댓글 1' })).toBeDefined();
});

test('운영자: 글 [숨기기](보라, 메모 필수) → 숨김 띠·메모 → [다시 공개]', async () => {
  TABLES.posts.push(fakePost(1, { author_id: 'u-x', author: OTHER }));
  asOp();
  start('/board/1');
  const hide = await screen.findByRole('button', { name: '숨기기' });
  expect(hide.classList.contains('btn-op')).toBe(true);
  expect(screen.queryByRole('button', { name: '신고' })).toBeNull();
  fireEvent.click(hide);
  const ok = screen.getByRole('button', { name: '숨기기 확정' });
  expect(ok.disabled).toBe(true);
  fireEvent.change(screen.getByLabelText('숨기는 이유 (필수, 작성자에게 보여요)'), { target: { value: '광고 글' } });
  fireEvent.click(ok);
  expect(await screen.findByText('글을 숨겼어요. 작성자에게 알림이 갔어요.')).toBeDefined();
  expect(rpcs('hide_post')).toEqual([{ p_id: 1, p_note: '광고 글' }]);
  await vi.waitFor(() => expect(document.querySelector('.op-band')).not.toBeNull());
  const band = document.querySelector('.op-band');
  expect(band.textContent).toContain('메모: 광고 글');
  expect(band.textContent).toContain('운영자에게만 보여요.');

  fireEvent.click(within(band).getByRole('button', { name: '다시 공개' }));
  fireEvent.change(screen.getByLabelText('다시 공개 메모 (필수, 작성자에게 보여요)'), { target: { value: '오해' } });
  fireEvent.click(screen.getByRole('button', { name: '다시 공개 확정' }));
  expect(await screen.findByText('글을 다시 공개했어요.')).toBeDefined();
  await vi.waitFor(() => expect(document.querySelector('.op-band')).toBeNull());
});

test('운영자: 숨긴 댓글도 보이고 [다시 공개], 보이는 댓글은 [숨기기]', async () => {
  TABLES.posts.push(fakePost(1, { comment_count: 1 }));
  TABLES.post_comments.push(
    fakeComment(11, 1, { author_id: 'u-x', author: OTHER, body: '욕설 댓글', status: 'hidden', hidden_note: '욕설', hidden_at: '2026-11-01T13:00:00Z' }),
    fakeComment(12, 1, { author_id: 'u-x', author: OTHER, body: '보통 댓글' }),
  );
  asOp();
  start('/board/1');
  const [hidden, normal] = within(await screen.findByRole('list', { name: '댓글' })).getAllByRole('listitem');
  expect(hidden.textContent).toContain('메모: 욕설');
  fireEvent.click(within(normal).getByRole('button', { name: '숨기기' }));
  fireEvent.change(within(normal).getByLabelText('숨기는 이유 (필수, 작성자에게 보여요)'), { target: { value: '도배' } });
  fireEvent.click(within(normal).getByRole('button', { name: '숨기기 확정' }));
  expect(await screen.findByText('댓글을 숨겼어요. 작성자에게 알림이 갔어요.')).toBeDefined();
  expect(rpcs('hide_comment')).toEqual([{ p_id: 12, p_note: '도배' }]);
});

test('운영자 /admin/reports: 대상별로 묶음 → 숨기기 / 신고 기각', async () => {
  TABLES.posts.push(fakePost(1, { author_id: 'u-x', author: OTHER, title: '광고 글' }));
  TABLES.post_comments.push(fakeComment(11, 1, { author_id: 'u-x', author: OTHER, body: '나쁜 댓글' }));
  const rep = (id, extra) => ({
    id, reporter_id: `u-r${id}`, post_id: null, comment_id: null, reason: 'spam', detail: null, status: 'open',
    created_at: `2026-11-01T0${id}:00:00Z`, reporter: { nickname: `신고자${id}`, level: 1, main_title: null }, ...extra,
  });
  TABLES.reports.push(rep(1, { post_id: 1 }), rep(2, { post_id: 1, reason: 'other', detail: '홍보' }), rep(3, { comment_id: 11, reason: 'abuse' }));
  asOp();
  start('/admin/reports');
  const list = await screen.findByRole('list', { name: '신고 목록' });
  const postGroup = within(list).getByRole('listitem', { name: '글 신고 2건' });
  expect(postGroup.textContent).toContain('광고 글');
  expect(postGroup.textContent).toContain('기타 — 홍보');
  expect(postGroup.textContent).toContain('신고자1');
  const commentGroup = within(list).getByRole('listitem', { name: '댓글 신고 1건' });
  expect(commentGroup.textContent).toContain('욕설·비하');

  fireEvent.click(within(postGroup).getByRole('button', { name: '숨기기' }));
  fireEvent.change(within(postGroup).getByLabelText('숨기는 이유 (필수, 작성자에게 보여요)'), { target: { value: '광고' } });
  fireEvent.click(within(postGroup).getByRole('button', { name: '숨기기 확정' }));
  expect(await screen.findByText('글을 숨겼어요. 신고 2건은 처리됨으로 닫았어요.')).toBeDefined();
  expect(rpcs('hide_post')).toEqual([{ p_id: 1, p_note: '광고' }]);

  const left = await screen.findByRole('listitem', { name: '댓글 신고 1건' });
  const dismiss = within(left).getByRole('button', { name: '신고 기각' });
  expect(dismiss.classList.contains('btn-op')).toBe(true);
  fireEvent.click(dismiss);
  fireEvent.click(within(left).getByRole('button', { name: '기각 확정' })); // 메모는 선택
  expect(await screen.findByText('신고 1건을 기각했어요.')).toBeDefined();
  expect(rpcs('dismiss_reports')).toEqual([{ p_post: null, p_comment: 11, p_note: null }]);
  expect(await screen.findByText('처리할 신고가 없어요.')).toBeDefined();
});

test('운영자 /admin: 자유게시판 칸 — 처리할 신고 수, 숨긴 글·댓글 [다시 공개]', async () => {
  TABLES.posts.push(fakePost(1, { status: 'hidden', title: '숨긴 글', hidden_note: '광고', hidden_at: '2026-11-01T10:00:00Z' }));
  TABLES.reports.push({ id: 1, reporter_id: 'u-r', post_id: 2, comment_id: null, reason: 'spam', detail: null, status: 'open', created_at: '2026-11-01T00:00:00Z', reporter: null });
  TABLES.posts.push(fakePost(2));
  asOp();
  start('/admin');
  const link = await screen.findByRole('link', { name: '처리할 신고 1건' });
  expect(link.getAttribute('href')).toBe('/admin/reports');
  const row = within(screen.getByRole('list', { name: '숨긴 글·댓글' })).getByRole('listitem');
  expect(row.textContent).toContain('메모: 광고');
  fireEvent.click(within(row).getByRole('button', { name: '다시 공개' }));
  fireEvent.change(within(row).getByLabelText('다시 공개 메모 (필수, 작성자에게 보여요)'), { target: { value: '괜찮음' } });
  fireEvent.click(within(row).getByRole('button', { name: '다시 공개 확정' }));
  expect(await screen.findByText('글을 다시 공개했어요.')).toBeDefined();
  expect(rpcs('restore_post')).toEqual([{ p_id: 1, p_note: '괜찮음' }]);
});

test('/me: 게시판 알림 (새 댓글은 [글 보기], 숨김은 링크 없음)', async () => {
  TABLES.notifications.push(
    { id: 1, user_id: 'u-old', kind: 'post_comment', post_id: 5, message: '내 글 「첫 글」에 새 댓글 3개가 달렸어요.', created_at: '2026-11-02T00:00:00Z', read_at: null },
    { id: 2, user_id: 'u-old', kind: 'post_hidden', post_id: 6, message: '내 글 「광고」을 운영자가 숨겼어요. 메모: 광고', created_at: '2026-11-02T00:00:00Z', read_at: null },
  );
  fakeLogin('u-old');
  start('/me');
  const sec = (await screen.findByRole('heading', { name: '게시판 알림' })).closest('section');
  const [comment, hidden] = within(sec).getAllByRole('listitem');
  expect(comment.textContent).toContain('새 댓글 3개');
  expect(within(comment).getByRole('link', { name: '글 보기' }).getAttribute('href')).toBe('/board/5');
  expect(within(hidden).queryByRole('link')).toBeNull();
  await vi.waitFor(() => expect(TABLES.notifications.every((n) => n.read_at)).toBe(true));
});
