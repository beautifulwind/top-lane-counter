// 장인 3b 화면 (047·048, SPEC 6-34): 링크 신고(정식 회원) · 링크 삭제(운영자 전부, 감독관은 일반 장인 링크만) ·
// /admin/reports 링크 신고 탭(운영자만) · 처리 대기 건수(운영자만) · 허용 사이트 관리(운영자만) · 방침·약관
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeLogin, fakeState } from './fakeSupabase';
import { openMenu } from './menu';
import { LEGAL } from '../lib/legal';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /></MemoryRouter>);
const MATCHUP = '/champion/Darius/counter/Quinn';
const rpcCalls = (name) => fakeState.rpcCalls.filter((c) => c.name === name).map((c) => c.args);
const asOperator = (extra = {}) => fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0, main_title: null, ...extra });
const asMod = () => fakeLogin('u-mod', { nickname: '감독', role: 'moderator', level: 3, main_title: null });
const asMember = () => fakeLogin('u-v', { nickname: '구경꾼', level: 2, main_title: null });

/** 탑고수(u-102, 일반 회원)를 장인으로 — 빌드 102를 처음 만든 분 */
function influencer(role = 'user') {
  const b = TABLES.builds.find((x) => x.id === 102);
  b.author = { ...b.author, role, influencer: 'creator' };
  if (!TABLES.profiles.some((p) => p.id === 'u-102')) {
    TABLES.profiles.push({ id: 'u-102', nickname: '탑고수', role, level: 7, main_title: null, influencer: 'creator' });
  }
  return b;
}
const addLink = (owner, url, extra = {}) => {
  const host = url.slice(8).split(/[/?#]/)[0];
  const row = { id: 600 + TABLES.ext_links.length, owner_id: owner, build_id: null, url, host, sort: TABLES.ext_links.length, ...extra };
  TABLES.ext_links.push(row);
  return row;
};
const linkMenu = (name = '링크 더보기') => screen.findAllByRole('button', { name });
const openLinkMenu = async (name, i = 0) => {
  fireEvent.click((await linkMenu(name))[i]);
  return within(await screen.findByRole('menu', { name }));
};

// ---------------- 링크 신고 (정식 회원) ----------------

test('링크 신고: 정식 회원은 공개 프로필 링크 ⋮ → 이유(기타는 내용 필수) → 보내기', async () => {
  influencer();
  const l = addLink('u-102', 'https://www.youtube.com/@toptop');
  asMember();
  start('/u/u-102');
  const menu = await openLinkMenu('링크 더보기');
  expect(menu.queryByRole('menuitem', { name: '링크 삭제' })).toBeNull();
  fireEvent.click(menu.getByRole('menuitem', { name: '링크 신고' }));

  const form = screen.getByRole('group', { name: /링크 신고 — 이유를 골라 주세요/ }).closest('form');
  const send = within(form).getByRole('button', { name: '신고 보내기' });
  expect(within(form).getAllByRole('radio').map((r) => r.parentElement.textContent.trim()))
    .toEqual(['광고·도박', '음란·잔혹', '악성·피싱 사이트', '본인 채널이 아님(사칭)', '기타']);
  expect(within(form).getByText('신고 내용은 운영자만 봅니다.')).toBeTruthy();
  expect(send).toBeDisabled();
  fireEvent.click(within(form).getByLabelText('기타'));
  expect(send).toBeDisabled(); // 기타는 내용 필수
  fireEvent.click(within(form).getByLabelText('본인 채널이 아님(사칭)'));
  fireEvent.change(within(form).getByLabelText('내용 (선택)'), { target: { value: '다른 사람 채널' } });
  fireEvent.click(send);
  expect(await screen.findByText('링크를 신고했습니다. 운영자가 확인하겠습니다.')).toBeTruthy();
  expect(rpcCalls('report_link')).toEqual([{ p_link: l.id, p_reason: 'not_own', p_detail: '다른 사람 채널' }]);
  expect(TABLES.link_reports).toHaveLength(1);
});

test('링크 신고: 로그인 전·비회원은 누를 수 없는 항목 + 이유, 내 링크에는 ⋮가 없다', async () => {
  influencer();
  addLink('u-102', 'https://www.youtube.com/@toptop');
  start('/u/u-102');
  let menu = await openLinkMenu('링크 더보기');
  const item = menu.getByRole('menuitem', { name: '링크 신고' });
  expect(item).toHaveAttribute('aria-disabled', 'true');
  expect(menu.getByText('로그인하면 신고할 수 있습니다.')).toBeTruthy();
  fireEvent.click(item);
  expect(screen.queryByRole('button', { name: '신고 보내기' })).toBeNull();
  cleanup();

  fakeLogin('u-g', { nickname: '손님', is_guest: true });
  start('/u/u-102');
  menu = await openLinkMenu('링크 더보기');
  expect(menu.getByRole('menuitem', { name: '링크 신고' })).toHaveAttribute('aria-disabled', 'true');
  expect(menu.getByText(/비회원은 신고할 수 없습니다/)).toBeTruthy();
  cleanup();

  fakeLogin('u-102');
  start('/u/u-102');
  await screen.findByRole('heading', { level: 1 });
  expect(screen.queryByRole('button', { name: '링크 더보기' })).toBeNull();
});

test('링크 신고: 빌드 제목 아래 장인 링크에도 ⋮', async () => {
  influencer();
  const l = addLink('u-102', 'https://youtu.be/build102', { build_id: 102 });
  asMember();
  start(MATCHUP);
  const menu = await openLinkMenu('장인 링크 더보기');
  fireEvent.click(menu.getByRole('menuitem', { name: '링크 신고' }));
  fireEvent.click(screen.getByLabelText('광고·도박'));
  fireEvent.click(screen.getByRole('button', { name: '신고 보내기' }));
  expect(await screen.findByText('링크를 신고했습니다. 운영자가 확인하겠습니다.')).toBeTruthy();
  expect(rpcCalls('report_link')).toEqual([{ p_link: l.id, p_reason: 'spam', p_detail: null }]);
});

// ---------------- 링크 삭제 (운영자·감독관, 사유 필수) ----------------

test('링크 삭제: 감독관은 일반 장인의 빌드 링크를 사유와 함께 삭제 → 장인에게 알림, 링크가 사라진다', async () => {
  influencer();
  const l = addLink('u-102', 'https://youtu.be/build102', { build_id: 102 });
  asMod();
  start(MATCHUP);
  const menu = await openLinkMenu('장인 링크 더보기');
  expect(menu.queryByRole('menuitem', { name: '링크 신고' })).toBeNull(); // 삭제할 수 있으면 신고 대신 삭제
  const del = menu.getByRole('menuitem', { name: '링크 삭제' });
  expect(del.className).toContain('op');
  fireEvent.click(del);
  const confirm = screen.getByRole('button', { name: '링크 삭제 확정' });
  expect(confirm).toBeDisabled(); // 사유 필수
  fireEvent.change(screen.getByLabelText('삭제 사유 (필수, 링크를 올린 장인에게 보입니다)'), { target: { value: '도박 광고' } });
  fireEvent.click(confirm);
  expect(await screen.findByText('링크를 삭제했습니다. 올린 장인에게 알림이 갔습니다.')).toBeTruthy();
  expect(rpcCalls('remove_link')).toEqual([{ p_link: l.id, p_note: '도박 광고' }]);
  await waitFor(() => expect(document.querySelector('.build-link-row')).toBeNull());
  expect(TABLES.notifications.find((n) => n.user_id === 'u-102' && n.kind === 'link_removed').message)
    .toBe('빌드에 올린 링크가 운영 원칙에 따라 삭제됐습니다. 사유: 도박 광고');
});

test('링크 삭제: 감독관에게 운영진(감독관)이 올린 빌드 링크는 [링크 삭제]가 없고, 공개 프로필에서는 DB가 이유와 함께 거부', async () => {
  influencer('moderator');
  addLink('u-102', 'https://youtu.be/build102', { build_id: 102 });
  addLink('u-102', 'https://www.youtube.com/@toptop');
  asMod();
  start(MATCHUP);
  const menu = await openLinkMenu('장인 링크 더보기');
  expect(menu.queryByRole('menuitem', { name: '링크 삭제' })).toBeNull();
  cleanup();

  start('/u/u-102'); // 공개 프로필은 역할을 주지 않는다 → 항목은 보이고 DB가 거부
  const m2 = await openLinkMenu('링크 더보기');
  fireEvent.click(m2.getByRole('menuitem', { name: '링크 삭제' }));
  fireEvent.change(screen.getByLabelText(/삭제 사유/), { target: { value: '테스트' } });
  fireEvent.click(screen.getByRole('button', { name: '링크 삭제 확정' }));
  expect((await screen.findByRole('alert')).textContent).toBe('운영진이 올린 링크는 운영자만 삭제할 수 있습니다.');
  expect(TABLES.ext_links).toHaveLength(2);
});

test('링크 삭제: 운영자는 공개 프로필 링크도 삭제, 운영자 모드를 끄면 항목이 없다', async () => {
  influencer();
  const l = addLink('u-102', 'https://www.youtube.com/@toptop');
  asOperator();
  start('/u/u-102');
  const menu = await openLinkMenu('링크 더보기');
  fireEvent.click(menu.getByRole('menuitem', { name: '링크 삭제' }));
  fireEvent.change(screen.getByLabelText(/삭제 사유/), { target: { value: '사칭 채널' } });
  fireEvent.click(screen.getByRole('button', { name: '링크 삭제 확정' }));
  expect(await screen.findByText('링크를 삭제했습니다. 올린 장인에게 알림이 갔습니다.')).toBeTruthy();
  expect(rpcCalls('remove_link')).toEqual([{ p_link: l.id, p_note: '사칭 채널' }]);
  await waitFor(() => expect(screen.queryByRole('list', { name: '링크' })).toBeNull()); // 050: 링크가 없으면 장인 페이지 위쪽 링크 줄이 사라진다
  cleanup();

  addLink('u-102', 'https://www.youtube.com/@again');
  TABLES.profiles.find((p) => p.id === 'u-op').operator_mode = false;
  start('/u/u-102');
  await screen.findByRole('heading', { level: 1 });
  // 운영자 모드가 꺼져 있으면 운영진이 아니다 → 삭제 없음, 운영자 계정은 정식 회원이므로 신고만
  const m2 = await openLinkMenu('링크 더보기');
  expect(m2.queryByRole('menuitem', { name: '링크 삭제' })).toBeNull();
  expect(m2.getByRole('menuitem', { name: '링크 신고' })).toBeTruthy();
});

// ---------------- /admin/reports 링크 신고 탭 (운영자만) ----------------

function reported() {
  influencer();
  const l = addLink('u-102', 'https://youtu.be/build102', { build_id: 102 });
  TABLES.profiles.push({ id: 'u-r', nickname: '신고자', role: 'user', level: 1, main_title: null });
  TABLES.link_reports.push(
    { id: 1, link_id: l.id, reporter_id: 'u-r', reason: 'malicious', detail: '이상한 사이트', status: 'open', created_at: '2026-11-12T01:00:00Z' },
    { id: 2, link_id: l.id, reporter_id: 'u-v', reason: 'spam', detail: null, status: 'open', created_at: '2026-11-12T02:00:00Z' },
  );
  return l;
}

test('신고 화면: 운영자에게 [링크 신고] 탭 — 링크·올린 장인·빌드·신고 내용, [신고 기각](메모 선택)', async () => {
  const l = reported();
  asOperator();
  start('/admin/reports?tab=links');
  const tab = await screen.findByRole('tab', { name: '링크 신고' });
  expect(tab).toHaveAttribute('aria-selected', 'true');
  const row = await screen.findByRole('listitem', { name: '링크 신고 2건' });
  expect(within(row).getByText('빌드 링크')).toBeTruthy();
  expect(within(row).getByRole('link', { name: /유튜브 youtu\.be\/build102/ })).toBeTruthy();
  expect(within(row).getByText('악성·피싱 사이트')).toBeTruthy();
  expect(within(row).getByText(/이상한 사이트/)).toBeTruthy();
  expect(within(row).getByText(/신고자,/)).toBeTruthy();
  expect(within(row).getByText(/퀸으로 다리우스/)).toBeTruthy();
  expect(within(row).getByRole('link', { name: '프로필 보기' })).toHaveAttribute('href', '/u/u-102');
  expect(within(row).getByRole('link', { name: '빌드 보기' })).toHaveAttribute('href', '/champion/Darius/counter/Quinn?build=102');

  fireEvent.click(within(row).getByRole('button', { name: '신고 기각' }));
  fireEvent.click(screen.getByRole('button', { name: '기각 확정' }));
  expect(await screen.findByText('링크 신고 2건을 기각했습니다.')).toBeTruthy();
  expect(rpcCalls('dismiss_link_reports')).toEqual([{ p_link: l.id, p_note: null }]);
  expect(await screen.findByText('처리할 링크 신고가 없습니다.')).toBeTruthy();
  expect(TABLES.ext_links).toHaveLength(1); // 링크는 그대로
});

test('신고 화면: [링크 삭제]는 사유 필수, 삭제하면 신고도 함께 닫힌다', async () => {
  const l = reported();
  asOperator();
  start('/admin/reports?tab=links');
  const row = await screen.findByRole('listitem', { name: '링크 신고 2건' });
  fireEvent.click(within(row).getByRole('button', { name: '링크 삭제' }));
  const ok = screen.getByRole('button', { name: '링크 삭제 확정' });
  expect(ok).toBeDisabled();
  fireEvent.change(screen.getByLabelText(/삭제 사유/), { target: { value: '피싱' } });
  fireEvent.click(ok);
  expect(await screen.findByText('링크를 삭제했습니다. 올린 장인에게 알림이 갔고, 신고 2건도 함께 닫혔습니다.')).toBeTruthy();
  expect(rpcCalls('remove_link')).toEqual([{ p_link: l.id, p_note: '피싱' }]);
  expect(TABLES.link_reports).toHaveLength(0);
});

test('신고 화면: 감독관에게는 [링크 신고] 탭이 없고 ?tab=links여도 글·댓글 신고를 보여 준다', async () => {
  reported();
  asMod();
  start('/admin/reports?tab=links');
  await screen.findByRole('tab', { name: '글·댓글 신고' });
  expect(screen.queryByRole('tab', { name: '링크 신고' })).toBeNull();
  expect(screen.getByRole('tab', { name: '글·댓글 신고' })).toHaveAttribute('aria-selected', 'true');
  expect(screen.queryByText(/이상한 사이트/)).toBeNull();
});

// ---------------- 처리 대기 건수 (운영자에게만 링크 신고 수) ----------------

test('처리 대기 건수: 운영자는 ☰ [관리] 숫자·풍선과 운영자 페이지에 링크 신고 수', async () => {
  reported();
  asOperator();
  fakeState.pendingCounts = { inquiries: 1 };
  start('/admin');
  const menu = await openMenu();
  const link = await menu.findByRole('link', { name: '관리, 처리 대기 2건' });
  expect(link.querySelector('.menu-count').getAttribute('title')).toBe('문의 1 · 링크 신고 1');
  fireEvent.keyDown(await menu.findByRole('button', { name: '메뉴 닫기' }), { key: 'Escape' });
  expect(await screen.findByRole('link', { name: '처리할 링크 신고 1건' })).toHaveAttribute('href', '/admin/reports?tab=links');
});

test('처리 대기 건수: 감독관은 링크 신고를 세지 않는다', async () => {
  reported();
  asMod();
  fakeState.pendingCounts = { inquiries: 1 };
  start('/admin');
  const menu = await openMenu();
  expect(await menu.findByRole('link', { name: '관리, 처리 대기 1건' })).toBeTruthy();
  fireEvent.keyDown(await menu.findByRole('button', { name: '메뉴 닫기' }), { key: 'Escape' });
  await screen.findByRole('link', { name: /처리할 신고/ });
  expect(screen.queryByRole('link', { name: /처리할 링크 신고/ })).toBeNull();
});

// ---------------- 허용 사이트 관리 (운영자만) ----------------

test('허용 사이트: 운영자 페이지에서 목록·더하기(도메인+이름)·빼기(사유 필수, 숨겨진 링크 수)', async () => {
  influencer();
  addLink('u-102', 'https://www.twitch.tv/toptop');
  asOperator();
  start('/admin');
  const section = (await screen.findByRole('heading', { name: '장인 링크 허용 사이트' })).closest('section');
  // 평소엔 접혀 있다: "허용 사이트 9개" + [모두 보기]만
  expect(await within(section).findByText('허용 사이트 9개')).toBeTruthy();
  expect(within(section).queryByRole('list', { name: '허용 사이트' })).toBeNull();
  expect(within(section).queryByRole('button', { name: '사이트 더하기' })).toBeNull();
  fireEvent.click(within(section).getByRole('button', { name: '모두 보기' }));
  const list = await within(section).findByRole('list', { name: '허용 사이트' });
  expect(within(list).getAllByRole('listitem')).toHaveLength(9);

  fireEvent.click(within(section).getByRole('button', { name: '사이트 더하기' }));
  const add = within(section).getByRole('button', { name: '더하기 확정' });
  expect(add).toBeDisabled();
  fireEvent.change(within(section).getByLabelText('도메인 (예: youtube.com)'), { target: { value: 'https://www.kick.com/' } });
  fireEvent.change(within(section).getByLabelText(/사이트 이름/), { target: { value: '킥' } });
  fireEvent.click(add);
  expect(await within(section).findByText('허용 사이트에 더했습니다: 킥 kick.com')).toBeTruthy();
  expect(rpcCalls('admin_add_link_domain')).toEqual([{ p_domain: 'https://www.kick.com/', p_label: '킥' }]);
  await waitFor(() => expect(within(section).getAllByRole('listitem')).toHaveLength(10));

  fireEvent.click(within(section).getByRole('button', { name: '트위치 빼기' }));
  const out = within(section).getByRole('button', { name: '빼기 확정' });
  expect(out).toBeDisabled();
  expect(within(section).getByText('이 사이트 링크는 지워지지 않고 숨겨집니다.')).toBeTruthy();
  fireEvent.change(within(section).getByLabelText(/빼는 사유/), { target: { value: '정책 변경' } });
  fireEvent.click(out);
  expect(await within(section).findByText('허용 사이트에서 뺐습니다: 트위치 twitch.tv (숨겨진 링크 1개)')).toBeTruthy();
  expect(rpcCalls('admin_remove_link_domain')).toEqual([{ p_domain: 'twitch.tv', p_note: '정책 변경' }]);
  expect(TABLES.ext_links).toHaveLength(1); // 지우지 않고 숨김

  fireEvent.click(await within(section).findByRole('button', { name: '접기' })); // 다시 누르면 접힌다
  expect(within(section).queryByRole('list', { name: '허용 사이트' })).toBeNull();
  expect(await within(section).findByText('허용 사이트 9개')).toBeTruthy();
});

test('허용 사이트: 감독관 화면에는 칸이 없다, 잘못된 도메인은 DB 이유 그대로', async () => {
  asMod();
  start('/admin');
  await screen.findByRole('link', { name: /처리할 신고/ });
  expect(screen.queryByRole('heading', { name: '장인 링크 허용 사이트' })).toBeNull();
  cleanup();

  asOperator();
  start('/admin');
  const section = (await screen.findByRole('heading', { name: '장인 링크 허용 사이트' })).closest('section');
  fireEvent.click(await within(section).findByRole('button', { name: '모두 보기' }));
  fireEvent.click(await within(section).findByRole('button', { name: '사이트 더하기' }));
  fireEvent.change(within(section).getByLabelText('도메인 (예: youtube.com)'), { target: { value: 'youtube.com' } });
  fireEvent.change(within(section).getByLabelText(/사이트 이름/), { target: { value: '유튜브' } });
  fireEvent.click(within(section).getByRole('button', { name: '더하기 확정' }));
  expect((await within(section).findByRole('alert')).textContent).toBe('이미 허용된 사이트입니다.');
});

// ---------------- 방침·약관 (시행일 2026-11-13) ----------------

test('방침·약관 (3b): 외부 링크 보증 안 함, 신고·삭제 절차, 인증 해제·탈퇴 때 링크 삭제 / 시행일 2026-11-13', async () => {
  const dates = { ...LEGAL };
  start('/terms');
  await screen.findByRole('heading', { name: /제4조의2/ });
  const terms = document.body.textContent;
  expect(terms).toMatch(/탑신병자는 외부 사이트의 내용을 보증하지 않으며/);
  expect(terms).toMatch(/링크 옆 ⋮ 메뉴의 “링크 신고”/);
  expect(terms).toMatch(/감독관도 일반 장인의 링크를 삭제할 수 있습니다\(운영진이 올린 링크는 운영자만\)/);
  expect(terms).toMatch(/삭제할 때는 사유를 남기고, 링크를 올린 장인에게 \[알림\]으로 알립니다/);
  expect(terms).toMatch(/장인 인증이 해제되거나 탈퇴하면 올린 링크는 바로 지워집니다/);
  expect(terms).toMatch(/광고·도박·음란·악성\(피싱 등\) 사이트나 본인 것이 아닌 채널/);
  cleanup();

  start('/privacy');
  await screen.findByRole('heading', { name: /보유 기간과 파기/ });
  const privacy = document.body.textContent;
  expect(privacy).toMatch(/장인 외부 링크: 장인이 지우거나, 장인 인증이 해제되거나 탈퇴하면 바로 지웁니다/);
  expect(privacy).toMatch(/링크 신고 내용과 신고한 사람은 운영자만 보며/);
  expect(privacy).toMatch(/이메일·라이엇 닉네임#태그·레벨·경험치·가입일은 보이지 않습니다/);
  expect(privacy).toMatch(/장인이 올린 외부 링크, 내가 보낸 링크 신고/);
  expect(LEGAL).toEqual(dates);
});
