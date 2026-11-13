// 051 공지 + 공지 알림 · 052 장인 새 팔로워 알림 (SPEC 6-37 · 6-38):
// 글쓰기 [공지로 올리기]·[알림 보내기], 목록 고정 공지, 알림 문구·이동, 푸시 설정 "공지"·"새 팔로워", /me/followers, web-push
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeLogin, fakePost, fakeState } from './fakeSupabase';
import { describeNotification, noticeSubject } from '../lib/notifications';
import { LEGAL } from '../lib/legal';
import { describePush, noticeSubject as pushNoticeSubject } from '../../supabase/functions/web-push/index.ts';

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
const asOp = (extra = {}) => fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0, main_title: null, ...extra });
const rpcs = (name) => fakeState.rpcCalls.filter((c) => c.name === name).map((c) => c.args);
const NOTICE = '새 공지가 올라왔습니다. 「점검 안내」';
const DAILY = '오늘 새 팔로워 3명이 생겼습니다.';

async function writePost(title) {
  fireEvent.change(await screen.findByLabelText('제목'), { target: { value: title } });
  fireEvent.change(screen.getByLabelText('본문'), { target: { value: '오늘 밤 점검합니다.' } });
}

// ---------------- 051 공지 쓰기 ----------------

test('운영자 글쓰기: [공지로 올리기]를 켜면 [알림 보내기](기본 켬) → create_notice(알림 켬), 공지 대기 줄에 들어감', async () => {
  asOp();
  start('/board/new');
  await writePost('점검 안내');
  expect(screen.queryByRole('checkbox', { name: /알림 보내기/ })).toBeNull();
  fireEvent.click(screen.getByRole('checkbox', { name: /공지로 올리기/ }));
  const notify = screen.getByRole('checkbox', { name: /알림 보내기/ });
  expect(notify).toBeChecked();
  expect(screen.getByText(/가입자 모두\(게스트 포함\)의 알림함에 쌓이고/)).toBeTruthy();
  fireEvent.click(screen.getByRole('button', { name: '공지 올리기' }));
  expect(await screen.findByText('공지를 올렸습니다. 가입자에게 알림을 차례로 보냅니다.')).toBeTruthy();
  expect(rpcs('create_notice')).toEqual([expect.objectContaining({ p_title: '점검 안내', p_notify: true })]);
  expect(rpcs('create_post')).toEqual([]);
  const id = Number(where.split('/').pop());
  expect(fakeState.noticeQueue).toEqual([id]);
  expect(TABLES.posts.find((p) => p.id === id).is_notice).toBe(true);
});

test('[알림 보내기]를 끄면 알림 없이 공지만 / [공지로 올리기]를 끄면 보통 글', async () => {
  asOp();
  start('/board/new');
  await writePost('조용한 공지');
  fireEvent.click(screen.getByRole('checkbox', { name: /공지로 올리기/ }));
  fireEvent.click(screen.getByRole('checkbox', { name: /알림 보내기/ }));
  expect(screen.getByText('알림 없이 공지만 올라갑니다.')).toBeTruthy();
  fireEvent.click(screen.getByRole('button', { name: '공지 올리기' }));
  expect(await screen.findByText('공지를 올렸습니다. 알림은 보내지 않았습니다.')).toBeTruthy();
  expect(rpcs('create_notice')).toEqual([expect.objectContaining({ p_notify: false })]);
  expect(fakeState.noticeQueue).toEqual([]);
  cleanup();
  start('/board/new');
  await writePost('그냥 글');
  fireEvent.click(screen.getByRole('button', { name: '글 올리기' }));
  expect(await screen.findByText('글을 올렸습니다.')).toBeTruthy();
  expect(rpcs('create_post')).toHaveLength(1);
});

test('공지 칸은 운영자(운영자 모드 켜짐)의 새 글에만 — 일반 회원·감독관·운영자 모드 꺼짐·고치기에는 없음', async () => {
  fakeLogin('u-1', { nickname: '탑고수' });
  start('/board/new');
  await screen.findByLabelText('제목');
  expect(screen.queryByRole('checkbox', { name: /공지로 올리기/ })).toBeNull();
  cleanup();
  fakeLogin('u-mod', { nickname: '감독', role: 'moderator' });
  start('/board/new');
  await screen.findByLabelText('제목');
  expect(screen.queryByRole('checkbox', { name: /공지로 올리기/ })).toBeNull();
  cleanup();
  asOp({ operator_mode: false });
  start('/board/new');
  await screen.findByLabelText('제목');
  expect(screen.queryByRole('checkbox', { name: /공지로 올리기/ })).toBeNull();
  cleanup();
  TABLES.profiles.find((p) => p.id === 'u-op').operator_mode = true;
  TABLES.posts.push(fakePost(5, { title: '내 공지', author_id: 'u-op', is_notice: true, created_at: new Date().toISOString() }));
  start('/board/5/edit');
  await screen.findByRole('heading', { name: /글 고치기/ });
  expect(screen.queryByRole('checkbox', { name: /공지로 올리기/ })).toBeNull();
  expect(screen.queryByRole('checkbox', { name: /알림 보내기/ })).toBeNull();
});

test('목록: 1쪽 위에 최근 공지 3개 고정 + [공지] 표시, 아래 목록에도 제자리에 / 검색에는 고정 없음', async () => {
  TABLES.posts.push(
    fakePost(1, { title: '공지 하나', is_notice: true }),
    fakePost(2, { title: '보통 글' }),
    fakePost(3, { title: '공지 둘', is_notice: true }),
    fakePost(4, { title: '공지 셋', is_notice: true }),
    fakePost(6, { title: '공지 넷', is_notice: true }),
  );
  start('/board');
  const pinned = await screen.findByRole('list', { name: '공지' });
  expect(within(pinned).getAllByRole('link').map((a) => a.textContent.match(/공지 (넷|셋|둘|하나)/)[0])).toEqual(['공지 넷', '공지 셋', '공지 둘']);
  expect(within(pinned).getAllByText('공지', { selector: '.notice-badge' })).toHaveLength(3);
  const list = screen.getByRole('list', { name: '글 목록' });
  expect(within(list).getAllByText('공지', { selector: '.notice-badge' })).toHaveLength(4);
  expect(within(list).getByText('보통 글').closest('li').querySelector('.notice-badge')).toBeNull();
  cleanup();
  start('/board?q=공지');
  await screen.findByRole('list', { name: '글 목록' });
  expect(screen.queryByRole('list', { name: '공지' })).toBeNull();
});

// ---------------- 알림 문구·이동 ----------------

test('알림 한 줄: 공지 = "새 공지가 올라왔습니다" + 「제목」 → 그 공지 / 새 팔로워 = 문장 그대로 → /me/followers', () => {
  expect(noticeSubject(NOTICE)).toBe('점검 안내');
  expect(noticeSubject('제목 없음')).toBeNull();
  const n = { id: 1, kind: 'notice_posted', message: NOTICE, post_id: 7, post: { title: '점검 안내 (시간 변경)' } };
  expect(describeNotification(n)).toEqual({ icon: 'bell', title: '새 공지가 올라왔습니다', subject: '「점검 안내 (시간 변경)」', detail: null, to: '/board/7' });
  // 공지가 숨겨지거나 지워져 글을 못 읽으면 문장 속 제목, 이동 없음
  expect(describeNotification({ ...n, post: null })).toMatchObject({ subject: '「점검 안내」', to: null });
  expect(describeNotification({ id: 2, kind: 'new_followers', message: DAILY })).toEqual({
    icon: 'users', title: '오늘 새 팔로워 3명이 생겼습니다', subject: null, detail: null, to: '/me/followers',
  });
});

test('알림 화면: 공지·새 팔로워 알림이 보이고 누르면 그 공지로', async () => {
  TABLES.posts.push(fakePost(7, { title: '점검 안내', is_notice: true }));
  TABLES.notifications.push(
    { id: 1, user_id: 'u-1', kind: 'notice_posted', message: NOTICE, post_id: 7, build_id: null, counter_id: null, proposal_id: null, created_at: '2026-11-13T00:00:00Z', read_at: null },
    { id: 2, user_id: 'u-1', kind: 'new_followers', message: DAILY, post_id: null, build_id: null, counter_id: null, proposal_id: null, created_at: '2026-11-13T03:00:00Z', read_at: null },
  );
  fakeLogin('u-1', { nickname: '탑고수', influencer: 'creator' });
  start('/notifications');
  const daily = (await screen.findByText('오늘 새 팔로워 3명이 생겼습니다')).closest('li');
  expect(daily.querySelector('.noti-icon.users svg')).not.toBeNull();
  expect(within(daily).getByRole('link').getAttribute('href')).toBe('/me/followers');
  const notice = screen.getByText('새 공지가 올라왔습니다').closest('li');
  expect(notice.textContent).toContain('「점검 안내」');
  expect(within(notice).getByRole('link').getAttribute('href')).toBe('/board/7');
  fireEvent.click(within(notice).getByRole('link'));
  await waitFor(() => expect(where).toBe('/board/7'));
});

// ---------------- 052 /me/followers ----------------

test('/me/followers: 장인은 내 장인 페이지로 가서 팔로워 목록이 펼쳐져 있다 / 장인이 아니면 안내', async () => {
  fakeLogin('u-102', { nickname: '탑고수', influencer: 'creator' });
  TABLES.influencer_follows.push({ follower_id: 'u-fan', influencer_id: 'u-102', created_at: '2026-11-13T00:00:00Z' });
  TABLES.profiles.push({ id: 'u-fan', nickname: '팬', role: 'user', level: 2, main_title: null });
  start('/me/followers');
  expect(await screen.findByRole('heading', { name: '팔로워' })).toBeTruthy();
  expect(where).toBe('/u/u-102?followers=1');
  expect(screen.getByRole('button', { name: '팔로워 목록 닫기' })).toBeTruthy();
  await waitFor(() => expect(document.querySelectorAll('.follower-list li')).toHaveLength(1));
  cleanup();
  fakeLogin('u-1', { nickname: '보통회원' });
  start('/me/followers');
  expect(await screen.findByText('장인 인증이 해제돼 팔로워 목록이 없습니다.')).toBeTruthy();
});

test('장인 페이지를 그냥 열면 팔로워 목록은 접혀 있고, 비로그인은 ?followers=1이어도 목록이 없다', async () => {
  TABLES.profiles.push({ id: 'u-102', nickname: '탑고수', role: 'user', level: 3, main_title: null, influencer: 'creator' });
  fakeLogin('u-fan', { nickname: '팬' });
  start('/u/u-102');
  await screen.findByRole('heading', { name: '처음 만든 빌드' });
  expect(screen.queryByRole('heading', { name: '팔로워' })).toBeNull();
  cleanup();
  fakeState.session = null;
  start('/u/u-102?followers=1');
  await screen.findByRole('heading', { name: '처음 만든 빌드' });
  expect(screen.queryByRole('heading', { name: '팔로워' })).toBeNull();
});

// ---------------- 푸시 설정 ----------------

test('푸시 설정: "공지"(기본 켜짐) — 끄면 notice만 꺼서 저장 / 장인이 아니면 "새 팔로워" 칸 없음', async () => {
  fakeLogin('u-1', { nickname: '탑고수' });
  start('/me/settings');
  const box = await screen.findByRole('checkbox', { name: /공지: 운영자가 새 공지를 올렸을 때/ });
  expect(box).toBeChecked();
  expect(screen.queryByRole('checkbox', { name: /새 팔로워/ })).toBeNull();
  fireEvent.click(box);
  await waitFor(() => expect(TABLES.push_settings).toEqual([expect.objectContaining({
    user_id: 'u-1', staff_new: true, my_results: true, follow_builds: true, notice: false, new_followers: false,
  })]));
  expect(screen.getByRole('checkbox', { name: /공지: 운영자가/ })).not.toBeChecked();
});

test('푸시 설정: 장인에게 "새 팔로워"(기본 꺼짐) — 켜면 new_followers만 켜서 저장, 저장된 값을 읽어 보여 줌', async () => {
  fakeLogin('u-102', { nickname: '탑고수', influencer: 'creator' });
  start('/me/settings');
  const box = await screen.findByRole('checkbox', { name: /새 팔로워/ });
  expect(box).not.toBeChecked();
  expect(screen.getByText(/하루에 한 번\(낮 12시\) 그날 새로 생긴 팔로워 수만 알려 줍니다/)).toBeTruthy();
  fireEvent.click(box);
  await waitFor(() => expect(TABLES.push_settings[0]).toEqual(expect.objectContaining({ new_followers: true, notice: true, follow_builds: true })));
  cleanup();
  start('/me/settings');
  expect(await screen.findByRole('checkbox', { name: /새 팔로워/ })).toBeChecked();
  // 칸이 없는 옛 줄(051·052 전)은 공지 켜짐 / 새 팔로워 꺼짐
  cleanup();
  TABLES.push_settings = [{ user_id: 'u-102', staff_new: true, my_results: true, follow_builds: true }];
  start('/me/settings');
  expect(await screen.findByRole('checkbox', { name: /새 팔로워/ })).not.toBeChecked();
  expect(screen.getByRole('checkbox', { name: /공지: 운영자가/ })).toBeChecked();
});

// ---------------- web-push ----------------

describe('web-push: 공지·새 팔로워', () => {
  test('공지: 제목 "새 공지가 올라왔습니다", 본문 「제목」, 누르면 그 공지 (알림 목록과 같은 규칙)', () => {
    const n = { id: 9, kind: 'notice_posted', message: NOTICE, proposal_id: null, build_id: null, post_id: 7 };
    expect(describePush(n)).toEqual({ title: '새 공지가 올라왔습니다', body: '「점검 안내」', url: '/board/7', tag: 'n-9' });
    expect(describePush(n).title).toBe(describeNotification({ ...n, post: { title: '점검 안내' } }).title);
    expect(describePush(n).url).toBe(describeNotification({ ...n, post: { title: '점검 안내' } }).to);
    for (const m of [NOTICE, '새 공지가 올라왔습니다. 「a「b」」', '모양이 다름']) expect(pushNoticeSubject(m)).toBe(noticeSubject(m));
  });
  test('새 팔로워: 제목 "새 팔로워", 본문은 숫자만 있는 DB 문장, 누르면 /me/followers', () => {
    const n = { id: 10, kind: 'new_followers', message: DAILY, proposal_id: null, build_id: null };
    expect(describePush(n)).toEqual({ title: '새 팔로워', body: DAILY, url: '/me/followers', tag: 'n-10' });
    expect(describePush(n).url).toBe(describeNotification(n).to);
  });
});

// ---------------- 방침·약관 ----------------

test('방침·약관 (051 공지·052 새 팔로워): 수집 항목·이용 목적·보관 기간, 제4조의3 / 시행일 2026-11-13', async () => {
  const before = { ...LEGAL };
  start('/privacy');
  await screen.findByRole('heading', { level: 1, name: '개인정보처리방침' });
  const privacy = document.querySelector('article.legal').textContent;
  expect(privacy).toContain('받을 알림 종류 설정(운영진 알림·내 상대법·빌드 다시 공개·팔로우한 장인의 새 빌드·공지·새 팔로워)');
  expect(privacy).toContain('이미 센 장인·팔로워와 센 시각(같은 사람을 다시 세지 않으려고 30일 보관)');
  expect(privacy).toContain('그날 새로 생긴 팔로워 수만 알리며, 누가 팔로우했는지는 알리지 않습니다.');
  expect(privacy).toContain('공지: 운영자가 올린 공지를 가입자 모두(비회원 포함)의 알림으로 알립니다.');
  expect(privacy).toContain('30일이 지나면 지우고, 그 장인의 인증이 해제되거나, 팔로우한 사람 또는 장인이 탈퇴하거나, 비회원(게스트) 계정이 정리되면 바로 지웁니다.');
  cleanup();
  start('/terms');
  const sec = (await screen.findByRole('heading', { name: '제4조의3 (장인 팔로우와 알림)' })).closest('section').textContent;
  expect(sec).toContain('하루에 한 번 그날 새로 생긴 팔로워 수만 알림으로 보냅니다');
  expect(sec).toContain('누가 팔로우했는지는 알리지 않으며');
  expect(sec).toContain('휴대폰 알림은 처음에 꺼져 있고 [계정 설정]의 “새 팔로워”에서 켤 수 있습니다');
  expect(LEGAL).toEqual(before);
  expect(LEGAL.effectiveDate).toBe('2026-11-13');
});
