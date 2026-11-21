// 064 장인 인증 신청 사진 (SPEC 6-76): 신청서에서 동그라미(+ 배지)로 고르기(선택) → 신청이 접수된 뒤 올리기,
// 심사 중 [내 신청]에서 바꾸기·지우기, 064 전 DB면 숨김, 운영자 심사 화면의 사진·[사진은 빼고 승인]·본 사진과 다르면 거부
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeLogin, fakeState } from './fakeSupabase';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /></MemoryRouter>);
const rpcCalls = (name) => fakeState.rpcCalls.filter((c) => c.name === name).map((c) => c.args);
const profile = (id) => TABLES.profiles.find((p) => p.id === id);
const app1 = () => TABLES.influencer_applications.find((a) => a.id === 1);
const type = (label, value) => fireEvent.change(screen.getByLabelText(label), { target: { value } });
const asOperator = () => fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0, main_title: null });
const notice = (text) => screen.findByText((_, el) => el?.classList?.contains('notice') && el.textContent.includes(text));
// jsdom에는 canvas가 없어서 줄이기만 흉내 (자르기 자체는 profilePhoto.test.jsx의 prepareSquare 테스트)
const stubSquare = () => {
  vi.spyOn(globalThis, 'createImageBitmap').mockImplementation(async () => ({ width: 800, height: 600 }));
  vi.spyOn(HTMLCanvasElement.prototype, 'getContext').mockImplementation(() => ({ fillRect: vi.fn(), drawImage: vi.fn(), fillStyle: '' }));
  vi.spyOn(HTMLCanvasElement.prototype, 'toBlob').mockImplementation((cb) => cb(new Blob(['x'], { type: 'image/webp' })));
};
if (typeof globalThis.createImageBitmap !== 'function') globalThis.createImageBitmap = async () => ({ width: 1, height: 1 });
const jpg = () => new File([new Uint8Array(10)], 'me.jpg', { type: 'image/jpeg' });
const pickFile = (file) => fireEvent.change(document.getElementById('application-photo-input'), { target: { files: [file] } });

/** 심사 중 신청 하나 (기존유저 u-old) */
function seedApp(extra = {}) {
  const u = profile('u-old');
  Object.assign(u, { nickname_state: 'pending' });
  TABLES.influencer_applications.push({
    id: 1, user_id: 'u-old', kind: 'creator', nickname: u.nickname, old_nickname: '옛닉', status: 'pending',
    channel_url: 'https://youtube.com/@toptop', official_email: 'biz@toptop.kr', riot_id: null, opgg_url: null,
    created_at: '2026-11-10T00:00:00Z', expires_at: '2026-11-24T00:00:00Z', extended_count: 0, ended_at: null,
    review_note: null, retry_now: false, nickname_reverted: null, revoked_at: null, revoke_note: null, photo_path: null, ...extra,
  });
}

function fillCreator() {
  fireEvent.click(screen.getByRole('radio', { name: /크리에이터/ }));
  type('채널·방송 링크', 'https://youtube.com/@x');
  type('공식 이메일', 'biz@x.kr');
}

// ---------------- 신청서 ----------------

test('신청서: 프로필 사진(선택) 동그라미 + 배지 — 고르면 미리보기만, 신청을 보낸 뒤 내 폴더에 올리고 신청에 붙인다', async () => {
  stubSquare();
  vi.spyOn(URL, 'createObjectURL').mockImplementation(() => 'blob:preview');
  URL.revokeObjectURL ??= () => {};
  fakeLogin('u-old');
  start('/me/influencer');
  const field = await screen.findByRole('group', { name: '프로필 사진 (선택)' });
  expect(field.textContent).toMatch(/고르지 않아도 신청할 수 있습니다/);
  expect(field.textContent).toMatch(/심사 중에는 나와 운영자만 보고, 승인되면 장인 페이지 프로필 사진이 됩니다/);
  const circle = within(field).getByRole('button', { name: '신청 프로필 사진 고르기' });
  expect(circle.querySelector('.avatar-plus')).not.toBeNull();
  expect(circle).not.toHaveAttribute('aria-haspopup'); // 사진이 없으면 바로 고르기

  pickFile(jpg());
  await notice('사진을 골랐습니다. 신청을 보내면 함께 올라갑니다.');
  expect(await within(field).findByRole('img', { name: '고른 프로필 사진' })).toHaveAttribute('src', 'blob:preview');
  expect(fakeState.uploads).toEqual([]); // 아직 안 올림 (신청 전에는 올릴 권한이 없다)

  fillCreator();
  fireEvent.click(screen.getByRole('button', { name: '신청 보내기' }));
  await notice('적어 주신 공식 이메일로 확인 메일이 갑니다.');
  expect(rpcCalls('apply_influencer')).toHaveLength(1);
  expect(fakeState.uploads).toHaveLength(1);
  const up = fakeState.uploads[0];
  expect(up.bucket).toBe('profile-photos');
  expect(up.path).toMatch(/^u-old\/[\w-]+\.webp$/);
  expect(rpcCalls('set_application_photo')).toEqual([{ p_path: up.path }]);
  expect(app1().photo_path).toBe(up.path);
  // 심사 중 카드에 내 신청 사진 동그라미
  const card = await screen.findByRole('region', { name: '내 신청' });
  const mine = await within(card).findByRole('img', { name: '기존유저 신청 프로필 사진' });
  expect(mine.getAttribute('src')).toContain(up.path);
});

test('신청서: 사진 없이 신청하면 아무것도 올리지 않는다, 고른 사진은 [사진 삭제]로 뺄 수 있다', async () => {
  stubSquare();
  fakeLogin('u-old');
  start('/me/influencer');
  const field = await screen.findByRole('group', { name: '프로필 사진 (선택)' });
  pickFile(jpg());
  await notice('사진을 골랐습니다.');
  const circle = within(field).getByRole('button', { name: '신청 프로필 사진 고르기' });
  expect(circle).toHaveAttribute('aria-haspopup', 'true');
  fireEvent.click(circle);
  fireEvent.click(within(field).getByRole('button', { name: '사진 삭제' }));
  expect(within(field).getByText('고른 사진을 빼시겠습니까? 사진 없이도 신청할 수 있습니다.')).toBeDefined();
  fireEvent.click(within(field).getByRole('button', { name: '지우기' }));
  await notice('고른 사진을 뺐습니다.');
  expect(circle).not.toHaveAttribute('aria-haspopup');

  fillCreator();
  fireEvent.click(screen.getByRole('button', { name: '신청 보내기' }));
  await notice('적어 주신 공식 이메일로 확인 메일이 갑니다.');
  expect(fakeState.uploads).toEqual([]);
  expect(rpcCalls('set_application_photo')).toEqual([]);
  expect(app1().photo_path).toBeNull();
});

test('신청서: GIF 등은 고르는 순간 거절 (신청서는 그대로)', async () => {
  fakeLogin('u-old');
  start('/me/influencer');
  const field = await screen.findByRole('group', { name: '프로필 사진 (선택)' });
  pickFile(new File(['x'], 'a.gif', { type: 'image/gif' }));
  expect(await within(field).findByRole('alert')).toHaveTextContent('프로필 사진은 JPG·PNG·WebP만 올릴 수 있습니다.');
  expect(screen.getByRole('button', { name: '신청 보내기' })).toBeDefined();
});

test('신청서: 신청은 됐는데 사진 올리기가 실패하면 — 신청은 그대로, [내 신청]에서 다시 올리라고 안내', async () => {
  stubSquare();
  fakeLogin('u-old');
  start('/me/influencer');
  await screen.findByRole('group', { name: '프로필 사진 (선택)' });
  pickFile(jpg());
  await notice('사진을 골랐습니다.');
  fillCreator();
  fakeState.uploadError = 'network down';
  fireEvent.click(screen.getByRole('button', { name: '신청 보내기' }));
  await notice('다만 프로필 사진은 올리지 못했습니다.');
  expect(screen.getByText((_, el) => el?.classList?.contains('notice') && /\[내 신청\]의 동그라미를 눌러 다시 올려 주세요/.test(el.textContent))).toBeDefined();
  expect(app1()).toMatchObject({ status: 'pending', photo_path: null });
  expect(rpcCalls('set_application_photo')).toEqual([]);
});

test('064 전 DB(photo_ready 없음): 신청서·[내 신청]에 사진 칸이 없다', async () => {
  fakeState.before064 = true;
  fakeLogin('u-old');
  start('/me/influencer');
  await screen.findByRole('button', { name: '신청 보내기' });
  expect(screen.queryByRole('group', { name: '프로필 사진 (선택)' })).toBeNull();
  cleanup();
  seedApp();
  start('/me/influencer');
  await screen.findByRole('region', { name: '내 신청' });
  expect(screen.queryByRole('button', { name: '신청 프로필 사진 변경' })).toBeNull();
});

// ---------------- 심사 중 [내 신청] ----------------

test('심사 중: 사진이 없으면 동그라미를 눌러 바로 올리고, 있으면 [사진 바꾸기] — 옛 파일은 바로 지운다', async () => {
  stubSquare();
  fakeLogin('u-old');
  seedApp();
  start('/me/influencer');
  const card = await screen.findByRole('region', { name: '내 신청' });
  const area = within(card).getByLabelText('신청 프로필 사진');
  expect(area.textContent).toMatch(/프로필 사진 \(선택\)/);
  const circle = within(area).getByRole('button', { name: '신청 프로필 사진 변경' });
  expect(circle.querySelector('.avatar-plus')).not.toBeNull();
  fireEvent.click(circle); // 사진이 없으면 바로 파일 고르기 → 아래에서 파일을 넣는다
  pickFile(jpg());
  await notice('신청 사진을 올렸습니다.');
  const first = fakeState.uploads[0].path;
  expect(rpcCalls('set_application_photo')).toEqual([{ p_path: first }]);
  expect(await within(area).findByRole('img', { name: '기존유저 신청 프로필 사진' })).toBeDefined();

  fireEvent.click(circle);
  fireEvent.click(within(area).getByRole('button', { name: '사진 바꾸기' }));
  pickFile(jpg());
  await notice('신청 사진을 바꿨습니다.');
  const second = fakeState.uploads[1].path;
  expect(second).not.toBe(first);
  expect(app1().photo_path).toBe(second);
  expect(fakeState.removed).toEqual([{ bucket: 'profile-photos', path: first }]);
});

test('심사 중: [사진 삭제] → 한 번 더 확인 → 신청 사진을 비우고 파일을 지운다', async () => {
  fakeLogin('u-old');
  seedApp({ photo_path: 'u-old/old.webp' });
  start('/me/influencer');
  const area = within(await screen.findByRole('region', { name: '내 신청' })).getByLabelText('신청 프로필 사진');
  expect(await within(area).findByRole('img', { name: '기존유저 신청 프로필 사진' })).toBeDefined();
  fireEvent.click(within(area).getByRole('button', { name: '신청 프로필 사진 변경' }));
  fireEvent.click(within(area).getByRole('button', { name: '사진 삭제' }));
  expect(within(area).getByText('신청 사진을 지우시겠습니까? 사진 없이도 심사를 받을 수 있습니다.')).toBeDefined();
  fireEvent.click(within(area).getByRole('button', { name: '지우기' }));
  await notice('신청 사진을 지웠습니다.');
  expect(rpcCalls('clear_application_photo')).toEqual([{}]);
  expect(app1().photo_path).toBeNull();
  expect(fakeState.removed).toEqual([{ bucket: 'profile-photos', path: 'u-old/old.webp' }]);
  expect(within(area).queryByRole('img')).toBeNull();
});

test('끝난 신청(반려 등)에는 사진 칸이 없다', async () => {
  fakeLogin('u-old');
  seedApp({ status: 'rejected', ended_at: '2026-11-12T00:00:00Z', review_note: '회신 없음' });
  Object.assign(profile('u-old'), { nickname_state: null });
  start('/me/influencer');
  await screen.findByRole('region', { name: '내 신청' });
  expect(screen.queryByRole('button', { name: '신청 프로필 사진 변경' })).toBeNull();
});

// ---------------- 운영자 심사 ----------------

test('운영자: 신청 사진이 보이고, 그대로 승인하면 본 사진 경로와 함께 보내 장인 사진이 된다', async () => {
  seedApp({ photo_path: 'u-old/a1.webp' });
  asOperator();
  start('/admin/influencers');
  const row = await screen.findByRole('listitem', { name: '장인 신청: 기존유저' });
  const check = within(row).getByLabelText('신청 프로필 사진');
  const img = await within(check).findByRole('img', { name: '기존유저 신청 프로필 사진' });
  expect(img.getAttribute('src')).toContain('profile-photos/u-old/a1.webp');
  expect(check.textContent).toMatch(/승인하면 장인 페이지에 공개됩니다/);
  fireEvent.click(within(row).getByRole('button', { name: '승인' }));
  const skip = within(row).getByRole('checkbox', { name: /사진은 빼고 승인/ });
  expect(skip).not.toBeChecked();
  fireEvent.change(within(row).getByLabelText(/승인 메모/), { target: { value: '이메일 회신 확인' } });
  fireEvent.click(within(row).getByRole('button', { name: '승인 확정' }));
  await notice('"기존유저" 님을 장인으로 승인했습니다.');
  expect(rpcCalls('approve_influencer')).toEqual([{ p_id: 1, p_note: '이메일 회신 확인', p_photo_path: 'u-old/a1.webp', p_with_photo: true }]);
  expect(profile('u-old')).toMatchObject({ influencer: 'creator', photo_path: 'u-old/a1.webp' });
  expect(TABLES.notifications.at(-1).message).toMatch(/신청 때 고른 프로필 사진도 등록됐습니다/);
});

test('운영자: [사진은 빼고 승인] → 장인이 되고 사진은 없음, 알림 끝에 안내', async () => {
  seedApp({ photo_path: 'u-old/bad.webp' });
  asOperator();
  start('/admin/influencers');
  const row = await screen.findByRole('listitem', { name: '장인 신청: 기존유저' });
  fireEvent.click(within(row).getByRole('button', { name: '승인' }));
  fireEvent.click(within(row).getByRole('checkbox', { name: /사진은 빼고 승인/ }));
  fireEvent.change(within(row).getByLabelText(/승인 메모/), { target: { value: '확인' } });
  fireEvent.click(within(row).getByRole('button', { name: '승인 확정' }));
  await notice('신청 사진은 등록하지 않았습니다.');
  expect(rpcCalls('approve_influencer')).toEqual([{ p_id: 1, p_note: '확인', p_photo_path: 'u-old/bad.webp', p_with_photo: false }]);
  expect(profile('u-old').influencer).toBe('creator');
  expect(profile('u-old').photo_path ?? null).toBeNull();
  expect(TABLES.notifications.at(-1).message).toMatch(/프로필 사진은 운영 원칙에 따라 등록하지 않았습니다\.$/);
});

test('운영자: 화면을 연 뒤 신청자가 사진을 바꾸면 승인이 거부되고 이유가 보인다', async () => {
  seedApp({ photo_path: 'u-old/a1.webp' });
  asOperator();
  start('/admin/influencers');
  const row = await screen.findByRole('listitem', { name: '장인 신청: 기존유저' });
  app1().photo_path = 'u-old/a2.webp'; // 그 사이 신청자가 바꿈
  fireEvent.click(within(row).getByRole('button', { name: '승인' }));
  fireEvent.change(within(row).getByLabelText(/승인 메모/), { target: { value: '확인' } });
  fireEvent.click(within(row).getByRole('button', { name: '승인 확정' }));
  expect(await within(row).findByRole('alert')).toHaveTextContent('신청자가 프로필 사진을 바꿨습니다. 새로고침한 뒤 사진을 다시 확인하고 승인해 주세요.');
  expect(profile('u-old').influencer ?? null).toBeNull();
});

test('운영자: 사진 없는 신청은 "없음", [사진은 빼고 승인]도 없다 / 064 전 DB면 옛 승인 인자 그대로', async () => {
  seedApp();
  asOperator();
  start('/admin/influencers');
  let row = await screen.findByRole('listitem', { name: '장인 신청: 기존유저' });
  expect(within(row).getByLabelText('신청 프로필 사진').textContent).toMatch(/신청 프로필 사진: 없음/);
  fireEvent.click(within(row).getByRole('button', { name: '승인' }));
  expect(within(row).queryByRole('checkbox', { name: /사진은 빼고 승인/ })).toBeNull();
  cleanup();

  fakeState.before064 = true;
  start('/admin/influencers');
  row = await screen.findByRole('listitem', { name: '장인 신청: 기존유저' });
  expect(within(row).queryByLabelText('신청 프로필 사진')).toBeNull();
  fireEvent.click(within(row).getByRole('button', { name: '승인' }));
  fireEvent.change(within(row).getByLabelText(/승인 메모/), { target: { value: '확인' } });
  fireEvent.click(within(row).getByRole('button', { name: '승인 확정' }));
  await waitFor(() => expect(rpcCalls('approve_influencer')).toEqual([{ p_id: 1, p_note: '확인' }]));
});
