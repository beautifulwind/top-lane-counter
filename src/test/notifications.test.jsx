// 027: 알림 화면 /notifications — 종류별 아이콘·제목·둘째 줄·이동, 열면 모두 읽음("새"는 이번 방문 동안 남음), 20개씩 [더 보기],
// 로그인한 사람만(비회원 포함), 마이페이지에는 [알림 보기]만
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeBuild, fakeGuestLogin, fakeLogin, fakePost, fakeProposal, fakeState } from './fakeSupabase';
import { noticeTime } from '../lib/notifications';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /></MemoryRouter>);
const ME = 'u-old';
let nextId = 1;
const noti = (kind, extra = {}) => ({
  id: nextId++, user_id: ME, kind, message: null, proposal_id: null, build_id: null, post_id: null, counter_id: null,
  created_at: '2026-11-02T00:00:00Z', read_at: '2026-11-02T01:00:00Z', ...extra,
});
const rowOf = async (text) => (await screen.findByText(text)).closest('li');
const href = (row) => within(row).queryByRole('link')?.getAttribute('href') ?? null;

test('로그인 전에는 로그인 화면으로, 메뉴에도 [알림]이 없다', async () => {
  start('/notifications');
  expect(await screen.findByRole('heading', { name: '로그인 · 가입' })).toBeDefined();
});

test('제안·빌드 알림: 화면이 만든 제목 + [종류] 매치업 + 메모, 누르면 내 제안·빌드 자세히', async () => {
  TABLES.edit_proposals.push(fakeProposal({ id: 501, status: 'approved' }), fakeProposal({ id: 502, type: 'new_counter', counter_champion: 'Garen', status: 'rejected' }));
  TABLES.builds.push(fakeBuild(111, { nickname: '기존유저', level: 1, main_title: null }, { author_id: ME }));
  TABLES.notifications.push(
    noti('proposal_approved', { proposal_id: 501, message: '반영했습니다' }),
    noti('proposal_rejected', { proposal_id: 502, message: '이미 있는 카운터' }),
    noti('build_hidden', { build_id: 111, message: '중복' }),
    noti('revision_cancelled', { build_id: 111, message: '제가 잘못 봤습니다' }),
  );
  fakeLogin(ME);
  start('/notifications');
  const approved = await rowOf('제안이 승인됐습니다');
  expect(approved.textContent).toContain('[문서 수정] 퀸으로 다리우스 이기는 법');
  expect(approved.textContent).toContain('승인 메모: 반영했습니다');
  expect(href(approved)).toBe('/me/proposals/501');
  expect(approved.querySelector('.noti-icon.check svg')).not.toBeNull();
  const rejected = await rowOf('제안이 거절됐습니다');
  expect(rejected.textContent).toContain('[새 카운터] 가렌으로 다리우스 이기는 법');
  expect(rejected.textContent).toContain('거절 사유: 이미 있는 카운터');
  expect(rejected.querySelector('.noti-icon.ban')).not.toBeNull();
  const hidden = await rowOf('운영자가 내 빌드를 숨겼습니다');
  expect(hidden.textContent).toContain('[빌드] 퀸으로 다리우스 이기는 법');
  expect(href(hidden)).toBe('/me/builds/111');
  const cancelled = await rowOf('재검토 요청이 취소됐습니다');
  expect(cancelled.textContent).toContain('보낸 내용 그대로 승인 대기 중입니다. 메모: 제가 잘못 봤습니다');
  // 최신순 (번호 큰 것 위)
  expect(screen.getAllByRole('listitem').map((li) => li.querySelector('.noti-title').textContent)).toEqual([
    '재검토 요청이 취소됐습니다', '운영자가 내 빌드를 숨겼습니다', '제안이 거절됐습니다', '제안이 승인됐습니다',
  ]);
});

test('게시판·문서 댓글 알림: DB 문장이 제목, 메모는 둘째 줄, 숨긴 글·숨긴 카운터는 이동 없음', async () => {
  TABLES.posts.push(fakePost(5), fakePost(6, { status: 'hidden' }));
  TABLES.counters.push({ id: 9, target_champion: 'Darius', counter_champion: 'Teemo', sort_order: 2, status: 'hidden', matchup_docs: null });
  TABLES.notifications.push(
    noti('post_comment', { post_id: 5, message: '내 글 「첫 글」에 새 댓글 3개가 달렸습니다.' }),
    noti('post_hidden', { post_id: 6, message: '내 글 「광고」을 운영자가 숨겼습니다. 메모: 광고' }),
    noti('comment_hidden', { post_id: 5, message: '「첫 글」에 쓴 내 댓글을 운영자가 숨겼습니다. 메모: 욕설' }),
    noti('doc_comment', { counter_id: 1, message: '내가 제안한 카운터 문서에 새 댓글 2개가 달렸습니다.' }),
    noti('doc_comment_restored', { counter_id: 9, message: '숨겨졌던 문서 댓글이 다시 공개됐습니다. 메모: 오해였습니다' }),
  );
  fakeLogin(ME);
  start('/notifications');
  expect(href(await rowOf('내 글 「첫 글」에 새 댓글 3개가 달렸습니다.'))).toBe('/board/5');
  const postHidden = await rowOf('내 글 「광고」을 운영자가 숨겼습니다.');
  expect(postHidden.textContent).toContain('메모: 광고');
  expect(href(postHidden)).toBeNull();
  expect(postHidden.querySelector('.noti-icon.hidden')).not.toBeNull();
  expect(href(await rowOf('「첫 글」에 쓴 내 댓글을 운영자가 숨겼습니다.'))).toBe('/board/5');
  const doc = await rowOf('내가 제안한 카운터 문서에 새 댓글 2개가 달렸습니다.');
  expect(doc.textContent).toContain('퀸으로 다리우스 이기는 법');
  expect(href(doc)).toBe('/champion/Darius/counter/Quinn#comments');
  const restored = await rowOf('숨겨졌던 문서 댓글이 다시 공개됐습니다.');
  expect(restored.textContent).toContain('티모로 다리우스 이기는 법');
  expect(href(restored)).toBeNull(); // 카운터가 숨겨져 있어 갈 곳 없음
});

test('레벨·칭호 알림: 마이페이지로, 칭호는 그 칭호 색 훈장', async () => {
  TABLES.notifications.push(
    noti('level_up', { message: '레벨이 올랐습니다: Lv.3' }),
    noti('title_earned', { message: "칭호 '장군'을 얻었습니다. [마이페이지]에서 대표 칭호로 고를 수 있습니다." }),
  );
  fakeLogin(ME);
  start('/notifications');
  const level = await rowOf('레벨이 올랐습니다: Lv.3');
  expect(href(level)).toBe('/me');
  const title = await rowOf("칭호 '장군'을 얻었습니다. [마이페이지]에서 대표 칭호로 고를 수 있습니다.");
  expect(href(title)).toBe('/me');
  expect(title.querySelector('.noti-icon.title-color.general .medal-icon')).not.toBeNull();
});

test('열면 맨 위 알림까지 모두 읽음 처리, "새" 표시는 이번 방문 동안 남는다', async () => {
  TABLES.notifications.push(
    noti('level_up', { message: '레벨이 올랐습니다: Lv.2' }), // 이미 읽음
    noti('level_up', { message: '레벨이 올랐습니다: Lv.3', read_at: null }),
    noti('level_up', { message: '레벨이 올랐습니다: Lv.4', read_at: null }),
  );
  fakeLogin(ME);
  start('/notifications');
  const top = await rowOf('레벨이 올랐습니다: Lv.4');
  await vi.waitFor(() => expect(fakeState.rpcCalls).toEqual([{ name: 'mark_all_notifications_read', args: { p_upto: TABLES.notifications[2].id } }]));
  await vi.waitFor(() => expect(TABLES.notifications.every((n) => n.read_at)).toBe(true));
  expect(top.className).toBe('noti-row new');
  expect(within(top).getByText('새')).toBeDefined();
  expect((await rowOf('레벨이 올랐습니다: Lv.3')).className).toBe('noti-row new');
  expect((await rowOf('레벨이 올랐습니다: Lv.2')).className).toBe('noti-row');
});

test('20개씩 [더 보기] — 더 오래된 알림을 이어 붙이고, 끝나면 버튼이 없다', async () => {
  for (let i = 1; i <= 25; i++) TABLES.notifications.push(noti('level_up', { message: `알림 ${i}` }));
  TABLES.notifications.push({ ...noti('level_up', { message: '남의 알림' }), user_id: 'u-x' });
  fakeLogin(ME);
  start('/notifications');
  await screen.findByText('알림 25');
  expect(screen.getAllByRole('listitem')).toHaveLength(20);
  expect(screen.queryByText('알림 5')).toBeNull();
  fireEvent.click(screen.getByRole('button', { name: '더 보기' }));
  expect(await screen.findByText('알림 1')).toBeDefined();
  expect(screen.getAllByRole('listitem')).toHaveLength(25);
  expect(screen.queryByText('남의 알림')).toBeNull();
  expect(screen.queryByRole('button', { name: '더 보기' })).toBeNull();
  expect(screen.getByText('알림은 90일 동안 보관됩니다.')).toBeDefined();
  expect(fakeState.rpcCalls).toEqual([]); // 안 읽은 게 없으면 부르지 않음
});

test('알림이 없으면 안내 한 줄, 탭 제목 "알림 - 탑신병자" — 비회원도 볼 수 있다', async () => {
  fakeGuestLogin('g-1', { nickname: '손님' });
  start('/notifications');
  expect(await screen.findByText('아직 받은 알림이 없습니다.')).toBeDefined();
  await vi.waitFor(() => expect(document.title).toBe('알림 - 탑신병자'));
});

test('마이페이지: 알림 칸 없이 [알림 보기] (새 알림 개수), 열어도 읽음 처리하지 않는다', async () => {
  TABLES.notifications.push(
    noti('level_up', { message: '레벨이 올랐습니다: Lv.3', read_at: null }),
    noti('post_comment', { post_id: 5, message: '내 글 「첫 글」에 새 댓글이 달렸습니다.', read_at: null }),
  );
  fakeLogin(ME);
  start('/me');
  const link = await screen.findByRole('link', { name: '알림 보기 (새 알림 2개)' });
  expect(link.getAttribute('href')).toBe('/notifications');
  expect(screen.queryByText('레벨이 올랐습니다: Lv.3')).toBeNull();
  expect(screen.queryByRole('heading', { name: '댓글·자유게시판 알림' })).toBeNull();
  expect(fakeState.rpcCalls.filter((c) => c.name.startsWith('mark_'))).toEqual([]);
});

test('알림 시각: 방금 전 / N분 전 / N시간 전 / 날짜', () => {
  const now = new Date('2026-11-04T12:00:00Z').getTime();
  expect(noticeTime('2026-11-04T11:59:40Z', now)).toBe('방금 전');
  expect(noticeTime('2026-11-04T11:15:00Z', now)).toBe('45분 전');
  expect(noticeTime('2026-11-04T02:00:00Z', now)).toBe('10시간 전');
  expect(noticeTime('2026-11-01T12:00:00Z', now)).toMatch(/^2026-11-0[12]$/);
});
