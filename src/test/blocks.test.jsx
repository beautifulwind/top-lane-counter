// 061 사용자 차단 (SPEC 6-67, App Store 심사 가이드 1.2): ⋮ [이 사용자 차단] → 확인 → 새로고침 없이 숨김,
// 계정 설정의 "차단한 사용자" 목록·해제, 자기 자신·운영자 차단 불가, 비로그인은 로그인으로, 탈퇴하면 정리, 알림 거르기, 061 전 DB에서도 동작
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeComment, fakeDocComment, fakeLogin, fakePost, fakeState, fakeWithdraw } from './fakeSupabase';
import { moreNames, openMore } from './moreMenu';
import { blockUser, unblockUser } from '../api/blocks';
import { createComment } from '../api/board';
import { BLOCK_CONFIRM, BLOCKED_COMMENT, BLOCKED_DONE, BLOCKED_POST } from '../lib/blocks';
import { NO_RESULT } from '../components/BuildSearch';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

function Where() { const l = useLocation(); return <output data-testid="where">{l.pathname + l.search}</output>; }
const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /><Where /></MemoryRouter>);
const where = () => screen.getByTestId('where').textContent;
const MATCHUP = '/champion/Darius/counter/Quinn';

const ME = 'u-me';
const BAD = { nickname: '악플러', role: 'user', level: 2, main_title: null };
const GOOD = { nickname: '착한이', role: 'user', level: 3, main_title: null };
const addPeople = () => TABLES.profiles.push(
  { id: 'u-bad', xp: 0, ...BAD },
  { id: 'u-good', xp: 0, ...GOOD },
  { id: 'u-op', nickname: '영자', role: 'admin', xp: 0, level: 0, main_title: null },
);
const asMe = () => fakeLogin(ME, { nickname: '나', level: 1 });

/** ⋮에서 [이 사용자 차단] → 메뉴 안 확인 문구 → [이 사용자 차단] */
async function blockFrom(scope, label) {
  const menu = openMore(scope, label);
  fireEvent.click(menu.getByRole('menuitem', { name: '이 사용자 차단' }));
  const ask = await screen.findByRole('alertdialog', { name: '이 사용자 차단' });
  expect(ask.textContent).toContain(BLOCK_CONFIRM);
  fireEvent.click(within(ask).getByRole('button', { name: '이 사용자 차단' }));
}

test('글 차단: 확인 → 새로고침 없이 "차단한 사용자의 글입니다." → 목록·검색에서도 빠짐 → 설정에서 해제하면 다시 보임', async () => {
  addPeople();
  TABLES.posts.push(
    fakePost(1, { title: '나쁜 글', author_id: 'u-bad', author: BAD }),
    fakePost(2, { title: '좋은 글', author_id: 'u-good', author: GOOD }),
  );
  asMe();
  start('/board/1');
  expect(await screen.findByText('본문 1')).toBeDefined();
  const reads = fakeState.queryLog.filter((q) => q.table === 'posts').length;
  await blockFrom(screen, '글 더보기');
  expect(await screen.findByRole('heading', { level: 1, name: BLOCKED_POST })).toBeDefined();
  expect(screen.getByText(BLOCKED_DONE)).toBeDefined();
  expect(screen.queryByText('본문 1')).toBeNull();
  expect(fakeState.queryLog.filter((q) => q.table === 'posts').length).toBe(reads); // 다시 불러오지 않고 바로
  expect(TABLES.user_blocks).toEqual([expect.objectContaining({ blocker_id: ME, blocked_id: 'u-bad' })]);
  expect(screen.getByRole('link', { name: '계정 설정' }).getAttribute('href')).toBe('/me/settings');

  // 목록·검색: 서버(board_page)가 뺀다
  cleanup();
  start('/board');
  expect(await screen.findByText('좋은 글')).toBeDefined();
  expect(screen.queryByText('나쁜 글')).toBeNull();
  cleanup();
  start('/board?q=글');
  expect(await screen.findByText('좋은 글')).toBeDefined();
  expect(screen.queryByText('나쁜 글')).toBeNull();

  // 계정 설정 → 차단한 사용자 목록 → 해제
  cleanup();
  start('/me/settings');
  const list = await screen.findByRole('list', { name: '차단한 사용자 목록' });
  expect(list.textContent).toContain('악플러');
  fireEvent.click(within(list).getByRole('button', { name: '악플러 차단 해제' }));
  expect(await screen.findByText('차단한 사용자가 없습니다.')).toBeDefined();
  expect(screen.getByText('악플러 님의 차단을 해제했습니다.')).toBeDefined();
  expect(TABLES.user_blocks).toEqual([]);
  cleanup();
  start('/board/1');
  expect(await screen.findByText('본문 1')).toBeDefined();
  cleanup();
  start('/board');
  expect(await screen.findByText('나쁜 글')).toBeDefined();
});

test('댓글 차단: 그 사람의 댓글·답글이 바로 사라지고, 다른 사람 답글이 달린 부모 자리는 "차단한 사용자의 댓글입니다."', async () => {
  addPeople();
  TABLES.posts.push(fakePost(1, { author_id: 'u-good', author: GOOD, comment_count: 4 }));
  TABLES.post_comments.push(
    fakeComment(11, 1, { author_id: 'u-bad', author: BAD, body: '나쁜 댓글' }),
    fakeComment(12, 1, { author_id: 'u-good', author: GOOD, body: '착한 답글', parent_id: 11 }),
    fakeComment(13, 1, { author_id: 'u-good', author: GOOD, body: '착한 댓글' }),
    fakeComment(14, 1, { author_id: 'u-bad', author: BAD, body: '나쁜 답글', parent_id: 13 }),
  );
  asMe();
  start('/board/1');
  const first = (await screen.findByText('나쁜 댓글')).closest('li');
  await blockFrom(within(first), '댓글 더보기');
  await waitFor(() => expect(screen.queryByText('나쁜 댓글')).toBeNull());
  expect(screen.queryByText('나쁜 답글')).toBeNull();
  expect(screen.getByText(BLOCKED_COMMENT)).toBeDefined();
  expect(screen.getByText('착한 답글')).toBeDefined();
  expect(screen.getByText('착한 댓글')).toBeDefined();
  expect(screen.getByText(BLOCKED_DONE)).toBeDefined();
  // 글 작성자(차단하지 않은 사람)의 글은 그대로
  expect(screen.getByText('본문 1')).toBeDefined();
});

test('문서 댓글·빌드 차단: 매치업에서 그 사람이 처음 만든 빌드 탭과 문서 댓글이 사라진다', async () => {
  TABLES.profiles.push({ id: 'u-102', xp: 0, nickname: '탑고수', role: 'user', level: 7, main_title: null });
  TABLES.doc_comments.push(fakeDocComment(31, { author_id: 'u-102', author: { nickname: '탑고수', level: 7, main_title: null }, body: '고수 문서 댓글' }));
  asMe();
  start(MATCHUP);
  expect(await screen.findByText('고수 문서 댓글')).toBeDefined();
  expect(screen.getAllByRole('tab').map((t) => t.textContent).some((t) => t.includes('빌드 2'))).toBe(true);
  const buildMenu = screen.getAllByRole('button', { name: /^빌드 2 더보기$/ })[0];
  expect(moreNames(within(buildMenu.parentElement), '빌드 2 더보기')).toContain('이 사용자 차단');
  await blockFrom(within(buildMenu.parentElement), '빌드 2 더보기');
  await waitFor(() => expect(screen.queryByText('고수 문서 댓글')).toBeNull());
  expect(screen.getAllByRole('tab').map((t) => t.textContent).some((t) => t.includes('빌드 2'))).toBe(false);
  expect(screen.getByText(BLOCKED_DONE)).toBeDefined();
});

test('내 글·댓글과 운영자 계정에는 [이 사용자 차단]이 없고, 자기 자신·운영자 차단은 DB가 막는다', async () => {
  addPeople();
  asMe();
  TABLES.posts.push(fakePost(1, { author_id: ME, author: { nickname: '나', level: 1 } }), fakePost(2, { author_id: 'u-op', author: { nickname: '영자', role: 'admin', level: 0 } }));
  TABLES.post_comments.push(fakeComment(11, 1, { author_id: ME, author: { nickname: '나', level: 1 }, body: '내 댓글' }));
  start('/board/1');
  await screen.findByText('내 댓글');
  expect(moreNames(screen, '글 더보기')).not.toContain('이 사용자 차단');
  expect(moreNames(screen, '댓글 더보기')).not.toContain('이 사용자 차단');
  cleanup();
  start('/board/2');
  await screen.findByText('본문 2');
  expect(moreNames(screen, '글 더보기')).not.toContain('이 사용자 차단');
  await expect(blockUser(ME, ME)).rejects.toThrow('자기 자신은 차단할 수 없습니다.');
  await expect(blockUser(ME, 'u-op')).rejects.toThrow('운영자 계정은 차단할 수 없습니다.');
  await expect(blockUser('u-good', 'u-bad')).rejects.toThrow('로그인한 뒤 차단할 수 있습니다.'); // 남의 이름으로
  expect(TABLES.user_blocks).toEqual([]);
  // 같은 사람을 두 번 차단해도 오류 없이 한 줄
  await blockUser(ME, 'u-bad');
  await blockUser(ME, 'u-bad');
  expect(TABLES.user_blocks.length).toBe(1);
});

test('비로그인: ⋮ [이 사용자 차단]은 확인 없이 로그인 화면으로, API로도 차단할 수 없다', async () => {
  addPeople();
  TABLES.posts.push(fakePost(1, { author_id: 'u-bad', author: BAD }));
  start('/board/1');
  await screen.findByText('본문 1');
  fireEvent.click(openMore(screen, '글 더보기').getByRole('menuitem', { name: '이 사용자 차단' }));
  await waitFor(() => expect(where()).toBe('/login'));
  expect(screen.queryByRole('alertdialog')).toBeNull();
  await expect(blockUser(null, 'u-bad')).rejects.toThrow('로그인한 뒤 차단할 수 있습니다.');
  expect(TABLES.user_blocks).toEqual([]);
});

test('알림: 차단한 사람의 댓글로는 알림이 오지 않고, 다른 사람 댓글 알림은 온다. 차단당한 사람에게는 아무것도 알리지 않는다', async () => {
  addPeople();
  TABLES.profiles.push({ id: ME, nickname: '나', role: 'user', xp: 0, level: 1, main_title: null });
  TABLES.posts.push(fakePost(1, { title: '내 글', author_id: ME, author: { nickname: '나', level: 1 } }));
  fakeLogin(ME);
  await blockUser(ME, 'u-bad');
  fakeLogin('u-bad');
  await createComment(1, '차단된 사람 댓글');
  fakeLogin('u-good');
  await createComment(1, '착한 댓글');
  expect(TABLES.notifications.filter((n) => n.user_id === ME).map((n) => n.kind)).toEqual(['post_comment']);
  expect(TABLES.notifications.filter((n) => n.user_id === 'u-bad')).toEqual([]); // 차단 사실 알림 없음
  fakeLogin(ME);
  start('/notifications');
  expect(await screen.findByText(/새 댓글이 달렸습니다/)).toBeDefined();
  expect(screen.getAllByText(/새 댓글이 달렸습니다/).length).toBe(1);
  // 차단당한 사람은 내 글에 댓글을 달 수 있고(차단 사실이 드러나지 않게), 내 화면에서만 안 보인다
  cleanup();
  start('/board/1');
  expect(await screen.findByText('착한 댓글')).toBeDefined();
  expect(screen.queryByText('차단된 사람 댓글')).toBeNull();
});

test('탈퇴하면 차단 줄이 정리된다 (차단한 사람·차단당한 사람 모두)', async () => {
  addPeople();
  TABLES.profiles.push({ id: ME, nickname: '나', role: 'user', xp: 0, level: 1, main_title: null });
  fakeLogin(ME);
  await blockUser(ME, 'u-bad');
  await blockUser(ME, 'u-good');
  fakeLogin('u-good');
  await blockUser('u-good', 'u-bad');
  fakeWithdraw('u-bad');
  expect(TABLES.user_blocks).toEqual([expect.objectContaining({ blocker_id: ME, blocked_id: 'u-good' })]);
  fakeWithdraw(ME);
  expect(TABLES.user_blocks).toEqual([]);
});

test('061 실행 전 DB(차단 표 없음): 화면은 그대로 동작하고, 차단은 "준비 중" 안내, 설정 목록은 비어 있다', async () => {
  addPeople();
  fakeState.blocksMissing = true;
  TABLES.posts.push(fakePost(1, { author_id: 'u-bad', author: BAD }));
  asMe();
  start('/board/1');
  expect(await screen.findByText('본문 1')).toBeDefined();
  await blockFrom(screen, '글 더보기');
  expect(await screen.findByText('차단 기능을 준비하고 있습니다. 잠시 뒤 다시 시도해 주세요.')).toBeDefined();
  expect(screen.getByText('본문 1')).toBeDefined();
  cleanup();
  start('/board');
  expect(await screen.findByText('글 1')).toBeDefined();
  cleanup();
  start('/me/settings');
  expect(await screen.findByText('차단한 사용자가 없습니다.')).toBeDefined();
  await expect(unblockUser(ME, 'u-bad')).rejects.toThrow('차단 기능을 준비하고 있습니다');
});

test('홈 검색·챔피언 화면: 차단한 사람이 처음 만든 빌드는 검색 후보와 한 줄 요약에서 빠진다', async () => {
  TABLES.profiles.push({ id: 'u-102', xp: 0, nickname: '탑고수', role: 'user', level: 7, main_title: null });
  const b102 = TABLES.builds.find((b) => b.id === 102);
  Object.assign(b102, { name: '고수 감전 견제', summary: '고수만의 요약' });
  asMe();
  start('/champion/Darius');
  expect(await screen.findByText('고수만의 요약')).toBeDefined(); // 추천 1등(102)의 요약
  cleanup();
  TABLES.user_blocks.push({ blocker_id: ME, blocked_id: 'u-102', created_at: '2026-11-17T00:00:00Z' });
  start('/champion/Darius');
  expect(await screen.findByText('사거리로 일방적인 견제')).toBeDefined(); // 다음 빌드의 요약으로
  expect(screen.queryByText('고수만의 요약')).toBeNull();
  cleanup();
  start('/');
  fireEvent.change(await screen.findByRole('combobox', { name: '챔피언·빌드 검색' }), { target: { value: '고수 감전' } });
  expect(await screen.findByText(NO_RESULT)).toBeDefined();
});
