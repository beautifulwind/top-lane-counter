// 장인 팔로우 화면 2 (050, SPEC 6-36): followed_build_created 알림 문구·아이콘·이동 · 푸시 설정 "팔로우한 장인의 새 빌드" · web-push
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeLogin } from './fakeSupabase';
import { describeNotification, followedBuildTitle } from '../lib/notifications';
import { describePush, followedBuildTitle as pushTitle, handlePush } from '../../supabase/functions/web-push/index.ts';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /></MemoryRouter>);
const ONE = '팔로우한 장인 Faker의 새 빌드가 올라왔습니다.';
const MANY = '팔로우한 장인 Faker의 새 빌드가 3개 올라왔습니다.';
const counter = { target_champion: 'Darius', counter_champion: 'Quinn', status: 'approved' };
const NAMES = (id) => ({ Darius: '다리우스', Quinn: '퀸' })[id];

// ---------------- 문구 ----------------

test('문구: 한 개는 "{닉네임} 님이 새 빌드를 올렸습니다", 묶인 알림은 "{닉네임} 님의 새 빌드가 N개 올라왔습니다"', () => {
  expect(followedBuildTitle(ONE)).toEqual({ nickname: 'Faker', count: 1, title: 'Faker 님이 새 빌드를 올렸습니다' });
  expect(followedBuildTitle(MANY)).toEqual({ nickname: 'Faker', count: 3, title: 'Faker 님의 새 빌드가 3개 올라왔습니다' });
  // 닉네임에 "의"가 들어가도 끝까지 읽는다
  expect(followedBuildTitle('팔로우한 장인 탑의신의 새 빌드가 2개 올라왔습니다.').title).toBe('탑의신 님의 새 빌드가 2개 올라왔습니다');
  // 모양이 다르면 DB 문장 그대로
  expect(followedBuildTitle('새 빌드 소식')).toEqual({ nickname: null, count: 1, title: '새 빌드 소식' });
  // web-push도 같은 규칙
  for (const m of [ONE, MANY, '팔로우한 장인 탑의신의 새 빌드가 2개 올라왔습니다.', '새 빌드 소식']) expect(pushTitle(m)).toBe(followedBuildTitle(m).title);
});

test('알림 한 줄: 빌드 아이콘 + 제목 + [빌드] 상대법, 누르면 그 장인 페이지', () => {
  const n = { id: 1, kind: 'followed_build_created', message: ONE, build_id: 102, counter_id: 1, counter, build: { author_id: 'u-102', counter } };
  expect(describeNotification(n, NAMES)).toEqual({
    icon: 'build', title: 'Faker 님이 새 빌드를 올렸습니다', subject: '[빌드] 퀸으로 다리우스 이기는 법', detail: null, to: '/u/u-102',
  });
  // 빌드가 숨겨져 작성자를 모르면 공개 중인 상대법으로, 상대법도 숨겨졌으면 이동 없음
  expect(describeNotification({ ...n, build: null }).to).toBe('/champion/Darius/counter/Quinn?build=102');
  expect(describeNotification({ ...n, build: null, counter: { ...counter, status: 'hidden' } }).to).toBeNull();
});

test('알림 화면: 묶인 알림 "N개", 빌드 아이콘, 누르면 장인 페이지 (빌드 작성자를 함께 읽는다)', async () => {
  TABLES.builds.find((b) => b.id === 102).author = { nickname: 'Faker', influencer: 'pro' };
  TABLES.profiles.push({ id: 'u-102', nickname: 'Faker', role: 'user', level: 7, main_title: null, influencer: 'pro' });
  TABLES.notifications.push(
    { id: 1, user_id: 'u-fan', kind: 'followed_build_created', message: ONE, build_id: 103, counter_id: 1, post_id: null, proposal_id: null, created_at: '2026-11-12T00:00:00Z', read_at: null },
    { id: 2, user_id: 'u-fan', kind: 'followed_build_created', message: MANY, build_id: 102, counter_id: 1, post_id: null, proposal_id: null, created_at: '2026-11-13T00:00:00Z', read_at: null },
  );
  fakeLogin('u-fan', { nickname: '팬' });
  start('/notifications');
  const many = (await screen.findByText('Faker 님의 새 빌드가 3개 올라왔습니다')).closest('li');
  expect(many.textContent).toContain('[빌드] 퀸으로 다리우스 이기는 법');
  expect(many.querySelector('.noti-icon.build svg')).not.toBeNull();
  expect(within(many).getByRole('link').getAttribute('href')).toBe('/u/u-102');
  const one = screen.getByText('Faker 님이 새 빌드를 올렸습니다').closest('li');
  expect(within(one).getByRole('link').getAttribute('href')).toBe('/u/u-103');
  fireEvent.click(within(many).getByRole('link'));
  expect(await screen.findByRole('heading', { name: '처음 만든 빌드' })).toBeTruthy();
});

// ---------------- 푸시 설정 ----------------

test('푸시 설정: "팔로우한 장인의 새 빌드" 칸(기본 켜짐), 끄면 follow_builds만 꺼서 저장', async () => {
  fakeLogin('u-1', { nickname: '탑고수' });
  start('/me/settings');
  const box = await screen.findByRole('checkbox', { name: /팔로우한 장인의 새 빌드/ });
  expect(box).toBeChecked();
  expect(screen.getByText('같은 장인의 새 빌드는 3시간에 한 번만 알려 줍니다.')).toBeTruthy();
  fireEvent.click(box);
  await waitFor(() => expect(TABLES.push_settings).toEqual([expect.objectContaining({ user_id: 'u-1', staff_new: true, my_results: true, follow_builds: false })]));
  expect(screen.getByRole('checkbox', { name: /팔로우한 장인의 새 빌드/ })).not.toBeChecked();
  // 다른 칸을 바꿔도 follow_builds는 그대로
  fireEvent.click(screen.getByRole('checkbox', { name: /내 상대법·빌드 다시 공개/ }));
  await waitFor(() => expect(TABLES.push_settings[0]).toEqual(expect.objectContaining({ my_results: false, follow_builds: false })));
});

test('푸시 설정: 저장된 follow_builds = false를 읽어 보여 준다 (칸이 없는 옛 줄은 켜짐)', async () => {
  TABLES.push_settings.push({ user_id: 'u-1', staff_new: true, my_results: true, follow_builds: false });
  fakeLogin('u-1', { nickname: '탑고수' });
  start('/me/settings');
  expect(await screen.findByRole('checkbox', { name: /팔로우한 장인의 새 빌드/ })).not.toBeChecked();
  cleanup();
  TABLES.push_settings = [{ user_id: 'u-1', staff_new: true, my_results: true }];
  start('/me/settings');
  expect(await screen.findByRole('checkbox', { name: /팔로우한 장인의 새 빌드/ })).toBeChecked();
});

// ---------------- web-push ----------------

describe('web-push: followed_build_created', () => {
  const n = { id: 9, kind: 'followed_build_created', message: ONE, proposal_id: null, build_id: 102, counter_id: 1, target_champion: 'Darius', counter_champion: 'Quinn' };
  test('제목은 알림 목록과 같고, 장인을 알면 장인 페이지 / 모르면 그 상대법', () => {
    expect(describePush({ ...n, author_id: 'u-102' })).toEqual({
      title: 'Faker 님이 새 빌드를 올렸습니다', body: '눌러서 새 빌드를 확인해 주세요.', url: '/u/u-102', tag: 'n-9',
    });
    expect(describeNotification({ ...n, counter, build: { author_id: 'u-102', counter } }).to).toBe('/u/u-102');
    expect(describePush(n).url).toBe('/champion/Darius/counter/Quinn?build=102');
  });

  const env = { get: (k) => ({ VAPID_PUBLIC_KEY: 'pub', PUSH_WEBHOOK_SECRET: 's' })[k] };
  const post = () => new Request('https://fn.test', { method: 'POST', headers: { 'content-type': 'application/json', 'x-push-secret': 's' }, body: JSON.stringify({ notification_id: 9 }) });
  const deps = (author) => ({
    targets: vi.fn(async () => ({ data: { notification: n, subscriptions: [{ id: 1, endpoint: 'https://e/1', p256dh: 'k', auth: 'a' }] }, error: null })),
    forget: vi.fn(async () => ({ data: 0, error: null })),
    send: vi.fn(async () => {}),
    buildAuthor: vi.fn(author),
  });
  test('handlePush: 빌드 작성자를 읽어 장인 페이지로 보낸다', async () => {
    const d = deps(async () => ({ data: 'u-102', error: null }));
    await handlePush(post(), env, d);
    expect(d.buildAuthor).toHaveBeenCalledWith(102);
    expect(JSON.parse(d.send.mock.calls[0][1]).url).toBe('/u/u-102');
  });
  test('handlePush: 작성자를 못 읽어도 알림은 보낸다 (상대법으로)', async () => {
    vi.spyOn(console, 'error').mockImplementation(() => {});
    const d = deps(async () => { throw new Error('db down'); });
    const res = await (await handlePush(post(), env, d)).json();
    expect(res).toMatchObject({ ok: true, sent: 1 });
    expect(JSON.parse(d.send.mock.calls[0][1]).url).toBe('/champion/Darius/counter/Quinn?build=102');
  });
});

test('다른 종류는 빌드 작성자를 읽지 않는다', async () => {
  const d = {
    targets: async () => ({ data: { notification: { id: 5, kind: 'build_created', message: 'x', proposal_id: null, build_id: 12 }, subscriptions: [{ id: 1, endpoint: 'e', p256dh: 'k', auth: 'a' }] }, error: null }),
    forget: async () => ({ data: 0, error: null }), send: vi.fn(async () => {}), buildAuthor: vi.fn(),
  };
  await handlePush(new Request('https://fn.test', { method: 'POST', headers: { 'x-push-secret': 's' }, body: '{"notification_id":5}' }),
    { get: (k) => ({ PUSH_WEBHOOK_SECRET: 's' })[k] }, d);
  expect(d.buildAuthor).not.toHaveBeenCalled();
  expect(d.send).toHaveBeenCalled();
});


