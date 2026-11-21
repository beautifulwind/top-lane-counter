// 062 장인 프로필 사진 (SPEC 6-71): 마이페이지 카드에서 올리기·바꾸기·삭제(장인만), 공개 프로필 보기 전용 + ⋮(사진 신고·차단·운영자 삭제),
// 사진이 없으면 예전 화면 그대로, 차단한 장인은 사진도 안 보임, 운영자 신고 탭·기각·삭제, 회원 정보에서 삭제, 알림 주소, 정사각형 자르기
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeGuestLogin, fakeLogin, fakeState } from './fakeSupabase';
import { moreNames, openMore, pickMore } from './moreMenu';
import { describeNotification as noticeView, reportsPath } from '../lib/notifications';
import { describePush as pushMessage } from '../../supabase/functions/web-push/index.ts';
import { prepareSquare } from '../lib/imageCompress';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /></MemoryRouter>);
/** 안내 문구 (불러오는 중… 표시도 role=status라 글자로 찾는다) */
const said = (text) => screen.findByText((_, el) => el?.classList?.contains('notice') && el.textContent.includes(text));
const rpcs = (name) => fakeState.rpcCalls.filter((c) => c.name === name).map((c) => c.args);
const INF = 'u-inf';
const asInfluencer = (extra = {}) => fakeLogin(INF, { nickname: '장인님', level: 3, main_title: null, influencer: 'creator', photo_path: null, ...extra });
const addInfluencer = (extra = {}) => {
  TABLES.profiles.push({ id: INF, nickname: '장인님', role: 'user', xp: 0, level: 3, main_title: null, influencer: 'creator', photo_path: null, ...extra });
};
const asOperator = () => fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0, main_title: null });
// jsdom에는 canvas가 없어서 화면 테스트에서는 줄이기만 흉내 (자르기 자체는 아래 prepareSquare 테스트)
const stubSquare = () => {
  const toBlob = vi.fn((cb) => cb(new Blob(['x'], { type: 'image/webp' })));
  vi.spyOn(globalThis, 'createImageBitmap').mockImplementation(async () => ({ width: 800, height: 600 }));
  vi.spyOn(HTMLCanvasElement.prototype, 'getContext').mockImplementation(() => ({ fillRect: vi.fn(), drawImage: vi.fn(), fillStyle: '' }));
  vi.spyOn(HTMLCanvasElement.prototype, 'toBlob').mockImplementation(toBlob);
};
if (typeof globalThis.createImageBitmap !== 'function') globalThis.createImageBitmap = async () => ({ width: 1, height: 1 });
const jpg = (size = 10) => new File([new Uint8Array(size)], 'me.jpg', { type: 'image/jpeg' });

// ---------------- 마이페이지 ----------------

test('마이페이지: 장인이 아니면 사진 버튼이 없고 기본 아이콘 그대로', async () => {
  fakeLogin('u-old');
  start('/me');
  await screen.findByRole('heading', { name: /기존유저/ });
  expect(screen.queryByRole('button', { name: '프로필 사진 변경' })).toBeNull();
  expect(document.querySelector('.avatar-plus')).toBeNull();
  expect(document.querySelector('.me-avatar svg')).not.toBeNull();
  expect(document.querySelector('.me-avatar img')).toBeNull();
});

test('마이페이지: 062 전 DB(사진 칸 없음)면 장인이어도 사진 버튼을 숨긴다', async () => {
  fakeLogin(INF, { nickname: '장인님', influencer: 'creator' }); // photo_path 칸 없음
  start('/me');
  await screen.findByRole('heading', { name: /장인님/ });
  expect(screen.queryByRole('button', { name: '프로필 사진 변경' })).toBeNull();
});

test('마이페이지: 장인이 사진을 올리면 정사각형으로 줄여 내 폴더에 올리고 정한다 → 사진이 보인다', async () => {
  stubSquare();
  asInfluencer();
  start('/me');
  const btn = await screen.findByRole('button', { name: '프로필 사진 변경' });
  expect(document.querySelector('.me-avatar svg')).not.toBeNull(); // 사진 없음: 예전 그대로
  expect(btn.querySelector('.avatar-plus')).not.toBeNull(); // 늘 보이는 + 배지
  expect(document.getElementById('profile-photo-input').getAttribute('accept')).toBe('image/*');
  // 사진이 없으면 동그라미를 누르자마자 사진 고르기가 열린다 (메뉴 없음)
  const click = vi.spyOn(document.getElementById('profile-photo-input'), 'click');
  fireEvent.click(btn);
  expect(click).toHaveBeenCalledTimes(1);
  expect(screen.queryByRole('group', { name: '프로필 사진 메뉴' })).toBeNull();
  fireEvent.change(document.getElementById('profile-photo-input'), { target: { files: [jpg()] } });
  expect(await said('프로필 사진을 올렸습니다.')).toBeDefined();
  const up = fakeState.uploads[0];
  expect(up.bucket).toBe('profile-photos');
  expect(up.path).toMatch(new RegExp(`^${INF}/[\\w-]+\\.webp$`));
  expect(up.mime).toBe('image/webp');
  expect(rpcs('set_profile_photo')).toEqual([{ p_path: up.path }]);
  const img = await screen.findByRole('img', { name: '장인님 프로필 사진' });
  expect(img.getAttribute('src')).toContain(`profile-photos/${up.path}`);
  expect(screen.getByRole('button', { name: '프로필 사진 변경' }).querySelector('.avatar-plus')).not.toBeNull();
});

test('마이페이지: 사진을 바꾸면 새 이름으로 올리고 옛 파일을 바로 지운다 (주소가 바뀌어 옛 사진이 안 남음)', async () => {
  stubSquare();
  asInfluencer({ photo_path: `${INF}/old.webp` });
  start('/me');
  const old = await screen.findByRole('img', { name: '장인님 프로필 사진' });
  expect(old.getAttribute('src')).toContain(`${INF}/old.webp`);
  // 사진이 있으면 동그라미를 눌러 메뉴 → [사진 바꾸기]
  const click = vi.spyOn(document.getElementById('profile-photo-input'), 'click');
  fireEvent.click(screen.getByRole('button', { name: '프로필 사진 변경' }));
  expect(screen.getByRole('button', { name: '취소' })).toBeDefined();
  expect(screen.getByRole('button', { name: '사진 삭제' })).toBeDefined();
  fireEvent.click(screen.getByRole('button', { name: '사진 바꾸기' }));
  expect(click).toHaveBeenCalledTimes(1);
  fireEvent.change(document.getElementById('profile-photo-input'), { target: { files: [jpg()] } });
  expect(await said('프로필 사진을 바꿨습니다.')).toBeDefined();
  const newPath = fakeState.uploads[0].path;
  expect(newPath).not.toBe(`${INF}/old.webp`);
  expect(fakeState.removed).toEqual([{ bucket: 'profile-photos', path: `${INF}/old.webp` }]);
  await waitFor(() => expect(screen.getByRole('img', { name: '장인님 프로필 사진' }).getAttribute('src')).toContain(newPath));
});

test('마이페이지: 정하기가 실패하면 방금 올린 파일을 지우고 이유를 보여 준다', async () => {
  stubSquare();
  asInfluencer();
  fakeState.rpcError = '프로필 사진은 하루에 10번까지 바꿀 수 있습니다. 내일 다시 해 주세요.';
  start('/me');
  await screen.findByRole('button', { name: '프로필 사진 변경' });
  fireEvent.change(document.getElementById('profile-photo-input'), { target: { files: [jpg()] } });
  expect(await screen.findByRole('alert')).toHaveTextContent('하루에 10번까지');
  expect(fakeState.removed.map((r) => r.path)).toEqual([fakeState.uploads[0].path]);
});

test('마이페이지: JPG·PNG·WebP가 아니거나 5MB를 넘으면 올리지 않는다', async () => {
  stubSquare();
  asInfluencer();
  start('/me');
  await screen.findByRole('button', { name: '프로필 사진 변경' });
  fireEvent.change(document.getElementById('profile-photo-input'), { target: { files: [new File(['g'], 'a.gif', { type: 'image/gif' })] } });
  expect(await screen.findByRole('alert')).toHaveTextContent('프로필 사진은 JPG·PNG·WebP만 올릴 수 있습니다.');
  fireEvent.change(document.getElementById('profile-photo-input'), { target: { files: [jpg(5 * 1024 * 1024 + 1)] } });
  await waitFor(() => expect(screen.getByRole('alert')).toHaveTextContent('5MB보다 큰 사진은 올릴 수 없습니다.'));
  expect(fakeState.uploads).toHaveLength(0);
});

test('마이페이지: 사진 삭제는 한 번 더 묻고, 지우면 예전 아이콘으로 돌아온다 (다시 눌러 올릴 수 있음)', async () => {
  asInfluencer({ photo_path: `${INF}/old.webp` });
  start('/me');
  await screen.findByRole('img', { name: '장인님 프로필 사진' });
  const avatar = () => screen.getByRole('button', { name: '프로필 사진 변경' });
  fireEvent.click(avatar());
  fireEvent.click(screen.getByRole('button', { name: '사진 삭제' }));
  fireEvent.click(screen.getByRole('button', { name: '취소' })); // 확인 단계의 취소 → 메뉴로
  expect(rpcs('clear_profile_photo')).toHaveLength(0);
  fireEvent.click(screen.getByRole('button', { name: '취소' })); // 메뉴의 취소 → 닫힘
  expect(screen.queryByRole('group', { name: '프로필 사진 메뉴' })).toBeNull();
  fireEvent.click(avatar());
  fireEvent.click(screen.getByRole('button', { name: '사진 삭제' }));
  fireEvent.click(screen.getByRole('button', { name: '지우기' }));
  expect(await said('프로필 사진을 지웠습니다.')).toBeDefined();
  expect(rpcs('clear_profile_photo')).toHaveLength(1);
  expect(fakeState.removed).toEqual([{ bucket: 'profile-photos', path: `${INF}/old.webp` }]);
  await waitFor(() => expect(screen.queryByRole('img', { name: '장인님 프로필 사진' })).toBeNull());
  expect(document.querySelector('.me-avatar svg')).not.toBeNull();
  expect(avatar().querySelector('.avatar-plus')).not.toBeNull();
});

test('마이페이지: 아바타는 키보드로 누를 수 있는 버튼이고, 메뉴는 Esc로 닫힌다', async () => {
  asInfluencer({ photo_path: `${INF}/old.webp` });
  start('/me');
  await screen.findByRole('img', { name: '장인님 프로필 사진' });
  const avatar = screen.getByRole('button', { name: '프로필 사진 변경' });
  expect(avatar.tagName).toBe('BUTTON');
  expect(avatar.getAttribute('aria-expanded')).toBe('false');
  fireEvent.click(avatar);
  expect(avatar.getAttribute('aria-expanded')).toBe('true');
  fireEvent.keyDown(document, { key: 'Escape' });
  expect(screen.queryByRole('group', { name: '프로필 사진 메뉴' })).toBeNull();
});

// ---------------- 공개 프로필 ----------------

describe('공개 프로필', () => {
  test('사진이 없으면 사진도 사진 신고도 없다 (예전 그대로). ⋮에는 차단만', async () => {
    addInfluencer();
    fakeLogin('u-old');
    start(`/u/${INF}`);
    await screen.findByRole('heading', { name: /장인님/ });
    expect(screen.queryByRole('img', { name: /프로필 사진/ })).toBeNull();
    expect(moreNames(screen, '장인 더보기')).toEqual(['이 사용자 차단']);
  });

  test('사진이 있으면 보이고(보기 전용 — 바꾸기 버튼 없음), 회원은 사진을 신고할 수 있다', async () => {
    addInfluencer({ photo_path: `${INF}/p.webp` });
    fakeLogin('u-old');
    start(`/u/${INF}`);
    const img = await screen.findByRole('img', { name: '장인님 프로필 사진' });
    expect(img.getAttribute('src')).toContain(`profile-photos/${INF}/p.webp`);
    expect(screen.queryByRole('button', { name: /사진 바꾸기|프로필 사진 올리기/ })).toBeNull();
    pickMore(screen, '프로필 사진 신고', '장인 더보기');
    fireEvent.click(screen.getByRole('radio', { name: /다른 사람 사진·사칭/ }));
    fireEvent.click(screen.getByRole('button', { name: '신고 보내기' }));
    expect(await said('프로필 사진을 신고했습니다.')).toBeDefined();
    expect(rpcs('report_profile_photo')).toEqual([{ p_user: INF, p_reason: 'impersonation', p_detail: null }]);
  });

  test('로그인 전·비회원은 사진 신고를 누를 수 없다 (이유 표시)', async () => {
    addInfluencer({ photo_path: `${INF}/p.webp` });
    start(`/u/${INF}`);
    await screen.findByRole('img', { name: '장인님 프로필 사진' });
    let menu = openMore(screen, '장인 더보기');
    expect(menu.getByRole('menuitem', { name: /프로필 사진 신고/ }).getAttribute('aria-disabled')).toBe('true');
    expect(menu.getByText('로그인하면 신고할 수 있습니다.')).toBeDefined();
    cleanup();
    fakeGuestLogin('u-guest', { nickname: '손님' });
    start(`/u/${INF}`);
    await screen.findByRole('img', { name: '장인님 프로필 사진' });
    menu = openMore(screen, '장인 더보기');
    expect(menu.getByText(/비회원은 신고할 수 없습니다/)).toBeDefined();
  });

  test('내 공개 프로필: 사진이 보이고 동그라미가 곧 버튼(+ 배지), ⋮(신고·차단)는 없다', async () => {
    asInfluencer({ photo_path: `${INF}/p.webp` });
    start(`/u/${INF}`);
    await screen.findByRole('img', { name: '장인님 프로필 사진' });
    expect(screen.getByRole('button', { name: '프로필 사진 변경' }).querySelector('.avatar-plus')).not.toBeNull();
    expect(moreNames(screen, '장인 더보기')).toEqual([]);
  });

  test('내 공개 프로필: 사진이 없어도 + 배지 동그라미가 보이고, 누르면 사진 고르기 → 올리면 바로 보인다', async () => {
    stubSquare();
    asInfluencer();
    start(`/u/${INF}`);
    const btn = await screen.findByRole('button', { name: '프로필 사진 변경' });
    const click = vi.spyOn(document.getElementById('profile-photo-input'), 'click');
    fireEvent.click(btn);
    expect(click).toHaveBeenCalledTimes(1);
    fireEvent.change(document.getElementById('profile-photo-input'), { target: { files: [jpg()] } });
    expect(await said('프로필 사진을 올렸습니다.')).toBeDefined();
    expect(await screen.findByRole('img', { name: '장인님 프로필 사진' })).toBeDefined();
  });

  test('남의 장인 페이지: + 배지도 버튼도 없고 사진을 눌러도 아무 일 없다', async () => {
    addInfluencer({ photo_path: `${INF}/p.webp` });
    fakeLogin('u-old');
    start(`/u/${INF}`);
    const img = await screen.findByRole('img', { name: '장인님 프로필 사진' });
    fireEvent.click(img);
    expect(screen.queryByRole('button', { name: '프로필 사진 변경' })).toBeNull();
    expect(document.querySelector('.avatar-plus')).toBeNull();
    expect(document.getElementById('profile-photo-input')).toBeNull();
  });

  test('⋮ [이 사용자 차단] → 바로 "차단한 사용자입니다."로 바뀌고 사진도 안 보인다', async () => {
    addInfluencer({ photo_path: `${INF}/p.webp` });
    fakeLogin('u-old');
    start(`/u/${INF}`);
    await screen.findByRole('img', { name: '장인님 프로필 사진' });
    const menu = openMore(screen, '장인 더보기');
    fireEvent.click(menu.getByRole('menuitem', { name: '이 사용자 차단' }));
    fireEvent.click(await menu.findByRole('button', { name: /차단/ }));
    expect(await screen.findByRole('heading', { name: '차단한 사용자입니다.' })).toBeDefined();
    expect(screen.queryByRole('img', { name: /프로필 사진/ })).toBeNull();
  });

  test('운영자: 신고 대신 [프로필 사진 삭제] (사유 필수) → 장인에게 알림, 사진이 사라진다', async () => {
    addInfluencer({ photo_path: `${INF}/p.webp` });
    asOperator();
    start(`/u/${INF}`);
    await screen.findByRole('img', { name: '장인님 프로필 사진' });
    expect(moreNames(screen, '장인 더보기')).not.toContain('프로필 사진 신고');
    pickMore(screen, '프로필 사진 삭제', '장인 더보기');
    fireEvent.change(screen.getByLabelText(/삭제 사유/), { target: { value: '부적절한 사진' } });
    fireEvent.click(screen.getByRole('button', { name: '프로필 사진 삭제 확정' }));
    expect(await said('프로필 사진을 삭제했습니다.')).toBeDefined();
    expect(rpcs('remove_profile_photo')).toEqual([{ p_user: INF, p_note: '부적절한 사진' }]);
    expect(TABLES.notifications.find((n) => n.user_id === INF).kind).toBe('profile_photo_removed');
    await waitFor(() => expect(screen.queryByRole('img', { name: '장인님 프로필 사진' })).toBeNull());
  });
});

// ---------------- 운영자 신고 탭 / 회원 정보 ----------------

test('운영자 신고 화면 "프로필 사진 신고" 탭: 사진별로 묶어 보여 주고, 기각·삭제할 수 있다', async () => {
  addInfluencer({ photo_path: `${INF}/p.webp` });
  TABLES.photo_reports.push(
    { id: 1, owner_id: INF, photo_path: `${INF}/p.webp`, reporter_id: 'u-old', reason: 'obscene', detail: '선정적', status: 'open', created_at: '2026-11-21T00:00:00Z' },
    { id: 2, owner_id: INF, photo_path: `${INF}/p.webp`, reporter_id: 'u-op', reason: 'spam', detail: null, status: 'open', created_at: '2026-11-21T01:00:00Z' },
  );
  asOperator();
  start('/admin/reports?tab=photos');
  const row = await screen.findByRole('listitem', { name: '프로필 사진 신고 2건' });
  expect(within(row).getByText('음란·잔혹한 사진')).toBeDefined();
  expect(within(row).getByText(/선정적/)).toBeDefined();
  expect(await within(row).findByRole('img', { name: /장인님 프로필 사진/ })).toBeDefined();
  fireEvent.click(within(row).getByRole('button', { name: '사진 삭제' }));
  fireEvent.change(within(row).getByLabelText(/삭제 사유/), { target: { value: '음란물' } });
  fireEvent.click(within(row).getByRole('button', { name: '프로필 사진 삭제 확정' }));
  expect(await said('신고 2건은 처리됨으로 닫았습니다.')).toBeDefined();
  expect(TABLES.photo_reports.map((r) => r.status)).toEqual(['resolved', 'resolved']);
  expect(await screen.findByText('처리할 프로필 사진 신고가 없습니다.')).toBeDefined();
});

test('운영자 신고 탭: [신고 기각]은 사진을 그대로 둔다', async () => {
  addInfluencer({ photo_path: `${INF}/p.webp` });
  TABLES.photo_reports.push({ id: 1, owner_id: INF, photo_path: `${INF}/p.webp`, reporter_id: 'u-old', reason: 'hate', detail: null, status: 'open', created_at: '2026-11-21T00:00:00Z' });
  asOperator();
  start('/admin/reports?tab=photos');
  const row = await screen.findByRole('listitem', { name: '프로필 사진 신고 1건' });
  fireEvent.click(within(row).getByRole('button', { name: '신고 기각' }));
  fireEvent.click(within(row).getByRole('button', { name: /기각/ }));
  expect(await said('프로필 사진 신고 1건을 기각했습니다.')).toBeDefined();
  expect(TABLES.profiles.find((p) => p.id === INF).photo_path).toBe(`${INF}/p.webp`);
});

test('감독관에게는 "프로필 사진 신고" 탭이 없다 (주소로 들어와도 글·댓글 신고)', async () => {
  fakeLogin('u-mod', { nickname: '감독', role: 'moderator' });
  start('/admin/reports?tab=photos');
  await screen.findByRole('tab', { name: '글·댓글 신고' });
  expect(screen.queryByRole('tab', { name: '프로필 사진 신고' })).toBeNull();
  expect(screen.getByRole('tab', { name: '글·댓글 신고' }).getAttribute('aria-selected')).toBe('true');
});

// ---------------- 알림 ----------------

test('알림: 사진 삭제 → 마이페이지(사유는 둘째 줄), 사진 신고 → 프로필 사진 신고 탭. 화면과 휴대폰 알림이 같다', () => {
  const removed = { kind: 'profile_photo_removed', message: '프로필 사진이 운영 원칙에 따라 삭제됐습니다. 사유: 음란물' };
  const v = noticeView(removed);
  expect(v).toMatchObject({ title: '프로필 사진이 운영 원칙에 따라 삭제됐습니다.', detail: '사유: 음란물', to: '/me' });
  expect(pushMessage({ id: 1, proposal_id: null, build_id: null, ...removed })).toMatchObject({ title: '프로필 사진', url: '/me' });
  const report = { kind: 'report_received', message: '새 신고가 들어왔습니다. (프로필 사진)' };
  expect(reportsPath(report.message)).toBe('/admin/reports?tab=photos');
  expect(noticeView(report).to).toBe('/admin/reports?tab=photos');
  expect(pushMessage({ id: 2, proposal_id: null, build_id: null, ...report }).url).toBe('/admin/reports?tab=photos');
  expect(reportsPath('새 신고가 들어왔습니다.')).toBe('/admin/reports');
});

// ---------------- 정사각형 자르기 ----------------

test('prepareSquare: 가운데를 정사각형으로 잘라 512px로 줄이고 다시 저장한다 (작은 사진은 키우지 않음)', async () => {
  const draws = [];
  const sizes = [];
  vi.spyOn(globalThis, 'createImageBitmap').mockImplementation(async () => ({ width: 1000, height: 600 }));
  vi.spyOn(HTMLCanvasElement.prototype, 'getContext').mockImplementation(function ctx() {
    sizes.push([this.width, this.height]);
    return { fillRect: vi.fn(), drawImage: (...a) => draws.push(a.slice(1)), fillStyle: '' };
  });
  vi.spyOn(HTMLCanvasElement.prototype, 'toBlob').mockImplementation((cb, type) => cb(new Blob(['x'], { type })));
  const out = await prepareSquare(jpg());
  expect(out).toMatchObject({ mime: 'image/webp', ext: 'webp' });
  expect(sizes[0]).toEqual([512, 512]);
  expect(draws[0]).toEqual([200, 0, 600, 600, 0, 0, 512, 512]);

  globalThis.createImageBitmap.mockImplementation(async () => ({ width: 300, height: 400 }));
  await prepareSquare(jpg());
  expect(sizes[1]).toEqual([300, 300]);
  expect(draws[1]).toEqual([0, 50, 300, 300, 0, 0, 300, 300]);
  await expect(prepareSquare(new File(['h'], 'a.heic', { type: 'image/heic' }))).rejects.toThrow('JPG·PNG·WebP만');
});
