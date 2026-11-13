// 장인 팔로우 화면 3 뒷부분 (050, SPEC 6-36): 회원 관리 [장인 목록 보기] · 방침·약관의 팔로우 조항
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { AppRoutes } from '../App';
import { LEGAL } from '../lib/legal';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeLogin, fakeState } from './fakeSupabase';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

function Where() { const l = useLocation(); return <output data-testid="where">{l.pathname}</output>; }
const start = (path = '/admin/members') => render(<MemoryRouter initialEntries={[path]}><AppRoutes /><Where /></MemoryRouter>);
const asOp = (extra = {}) => fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0, main_title: null, ...extra });
const calls = () => fakeState.memberCalls.filter((c) => c.name === 'admin_influencer_list');
const inf = (id, nickname, influencer, at) => TABLES.profiles.push({ id, nickname, role: 'user', level: 3, main_title: null, influencer, influencer_at: at });
const follow = (who, whom) => TABLES.influencer_follows.push({ follower_id: who, influencer_id: whom, created_at: '2026-11-10T00:00:00Z' });

test('[장인 목록 보기]: [감독관 목록 보기] 옆, 누르면 펼침 — 닉네임·유형·직접 지정/신청 승인·인증일·팔로워 수, 최근 인증 순', async () => {
  asOp();
  inf('i-1', '먼저장인', 'pro', '2026-11-01T00:00:00Z');
  inf('i-2', '나중장인', 'creator', '2026-11-11T00:00:00Z');
  TABLES.influencer_applications.push({ id: 901, user_id: 'i-2', status: 'approved', direct: true });
  follow('f-1', 'i-1'); follow('f-2', 'i-1'); follow('f-3', 'i-2');
  start();
  const mod = await screen.findByRole('button', { name: '감독관 목록 보기' });
  const btn = screen.getByRole('button', { name: '장인 목록 보기' });
  expect(btn.parentElement).toBe(mod.parentElement); // 한 줄에 나란히
  expect(btn).toHaveAttribute('aria-expanded', 'false');
  expect(calls()).toHaveLength(0); // 펼치기 전엔 부르지 않는다
  fireEvent.click(btn);
  const list = await screen.findByRole('list', { name: '장인 목록' });
  const rows = within(list).getAllByRole('listitem');
  expect(rows.map((li) => within(li).getByRole('link').getAttribute('aria-label'))).toEqual(['나중장인 회원 정보', '먼저장인 회원 정보']);
  expect(rows[0].textContent).toContain('크리에이터 · 직접 지정 · 인증 2026');
  expect(rows[0].textContent).toContain('팔로워 1명');
  expect(rows[1].textContent).toContain('프로게이머 · 신청 승인');
  expect(rows[1].textContent).toContain('팔로워 2명');
  expect(screen.getByText(/인증된 장인 2명/)).toBeDefined();
  expect(calls().at(-1).args).toEqual({ p_page: 1, p_size: 20 });
  fireEvent.click(screen.getByRole('button', { name: '장인 목록 닫기' }));
  expect(screen.queryByRole('list', { name: '장인 목록' })).toBeNull();
});

test('[장인 목록 보기]: 행을 누르면 기존 회원 정보 화면(/admin/members/:id)', async () => {
  asOp();
  inf('i-1', '탑장인', 'creator', '2026-11-01T00:00:00Z');
  fakeState.memberDetail = { 'i-1': { info: { id: 'i-1', nickname: '탑장인', role: 'user', level: 3, main_title: null, is_guest: false, created_at: '2026-10-01T00:00:00Z',
    providers: ['google'], titles: [], proposals: 0, posts: 0, builds: 0, comments: 0, matchups: 0, xp: 0, influencer: 'creator' },
    posts: [], comments: [], edited_builds: [], moderation: [] } };
  start();
  fireEvent.click(await screen.findByRole('button', { name: '장인 목록 보기' }));
  fireEvent.click(await screen.findByRole('link', { name: '탑장인 회원 정보' }));
  expect(screen.getByTestId('where').textContent).toBe('/admin/members/i-1');
  expect(await screen.findByRole('list', { name: '탑장인 회원 정보' })).toBeDefined();
});

test('[장인 목록 보기]: 20명씩 쪽 단위 / 장인이 없으면 안내', async () => {
  asOp();
  for (let i = 0; i < 23; i += 1) inf(`i-${i}`, `장인${String(i).padStart(2, '0')}`, 'creator', `2026-11-${String(i + 1).padStart(2, '0')}T00:00:00Z`);
  start();
  fireEvent.click(await screen.findByRole('button', { name: '장인 목록 보기' }));
  const list = await screen.findByRole('list', { name: '장인 목록' });
  expect(within(list).getAllByRole('listitem')).toHaveLength(20);
  fireEvent.click(screen.getByRole('button', { name: '다음' }));
  await vi.waitFor(() => expect(within(screen.getByRole('list', { name: '장인 목록' })).getAllByRole('listitem')).toHaveLength(3));
  expect(calls().at(-1).args.p_page).toBe(2);
  cleanup();
  TABLES.profiles.splice(0, TABLES.profiles.length, ...TABLES.profiles.filter((p) => !p.influencer));
  start();
  fireEvent.click(await screen.findByRole('button', { name: '장인 목록 보기' }));
  expect(await screen.findByText('인증된 장인이 없습니다.')).toBeDefined();
});

test('운영자 모드를 끈 운영자: 회원 관리는 안내만(계정 설정으로), 장인 목록을 부르지 않는다 / 감독관·일반 회원도 막힘', async () => {
  asOp({ operator_mode: false });
  inf('i-1', '탑장인', 'creator', '2026-11-01T00:00:00Z');
  start();
  expect(await screen.findByText('운영자만 볼 수 있습니다.')).toBeDefined();
  expect(screen.getByText(/운영자 모드가 꺼져 있습니다/)).toBeDefined();
  expect(screen.getByRole('link', { name: '계정 설정' }).getAttribute('href')).toBe('/me/settings');
  expect(screen.queryByRole('button', { name: '장인 목록 보기' })).toBeNull();
  expect(calls()).toHaveLength(0);
  cleanup();
  fakeLogin('u-m', { nickname: '감독님', role: 'moderator' });
  start();
  expect(await screen.findByText('운영자만 볼 수 있습니다.')).toBeDefined();
  expect(screen.queryByText(/운영자 모드가 꺼져 있습니다/)).toBeNull();
  expect(calls()).toHaveLength(0);
});

test('방침·약관 (050 팔로우): 저장 목적·보관 기간·공개 범위, 팔로우·알림 조항 / 시행일은 그대로', async () => {
  const before = { ...LEGAL };
  start('/privacy');
  await screen.findByRole('heading', { level: 1, name: '개인정보처리방침' });
  const privacy = document.querySelector('article.legal').textContent;
  expect(privacy).toContain('누가 어떤 장인을 언제 팔로우했는지');
  expect(privacy).toContain('팔로우한 장인이 새 빌드를 올리면 알림을 보내고');
  expect(privacy).toContain('팔로우를 취소하거나, 그 장인의 인증이 해제되거나, 팔로우한 사람 또는 장인이 탈퇴하거나, 오래 쓰지 않은 비회원(게스트) 계정이 정리되면 바로 지웁니다.');
  expect(privacy).toContain('팔로워 수는 누구나');
  expect(privacy).toContain('팔로워 목록은 로그인한 이용자(비회원 포함)에게');
  expect(privacy).toContain('팔로우한 장인의 새 빌드·'); // 051·052에서 뒤에 공지·새 팔로워가 붙음
  expect(privacy).toContain('장인 목록에서 장인의 닉네임·유형·직접 지정 여부·인증일·팔로워 수를 조회');
  cleanup();
  start('/terms');
  const sec = (await screen.findByRole('heading', { name: '제4조의3 (장인 팔로우와 알림)' })).closest('section').textContent;
  expect(sec).toContain('언제든 취소할 수 있습니다');
  expect(sec).toContain('“팔로우한 장인의 새 빌드”에서 끌 수 있습니다');
  expect(LEGAL).toEqual(before);
  expect(LEGAL.effectiveDate).toBe('2026-11-09');
});
