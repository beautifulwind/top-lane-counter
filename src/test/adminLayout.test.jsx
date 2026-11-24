// 1.3 패치 1-A (SPEC 6-89): 운영자 페이지 「처리할 일」 카드·탭(?tab=)·안내 접기·「모두 보기」, 회원 상세 상태 칩·탭·나란한 버튼·경고 펼치기
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { AppRoutes } from '../App';
import { PREVIEW_COUNT } from '../lib/adminView';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeLogin, fakeState } from './fakeSupabase';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

function Where() { const l = useLocation(); return <output data-testid="where">{l.pathname + l.search}</output>; }
const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /><Where /></MemoryRouter>);
const where = () => screen.getByTestId('where').textContent;
const asOp = () => fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0, main_title: null });

test('/admin: 처리할 일 카드 3개는 0건이어도 보이고, 누르면 그 탭으로 바뀌며 주소에 ?tab=이 남는다', async () => {
  asOp();
  fakeState.pendingCounts = { inquiries: 2, wiki_reports: 1, influencers: 0 };
  start('/admin');
  const cards = await screen.findByRole('region', { name: '처리할 일' });
  expect(await within(cards).findByRole('button', { name: '처리할 신고 1건' })).toBeDefined();
  expect(within(cards).getByRole('button', { name: '답변 대기 문의 2건' })).toBeDefined();
  expect(within(cards).getByRole('button', { name: '처리할 장인 신청 0건' })).toBeDefined(); // 0건도 표시
  expect(screen.getByRole('tab', { name: '콘텐츠' })).toHaveAttribute('aria-selected', 'true');
  expect(screen.getByRole('heading', { name: '숨긴 상대법' })).toBeDefined();
  expect(screen.queryByRole('heading', { name: '회원 관리' })).toBeNull();

  fireEvent.click(within(cards).getByRole('button', { name: '답변 대기 문의 2건' }));
  expect(await screen.findByRole('heading', { name: '문의' })).toBeDefined();
  expect(where()).toBe('/admin?tab=members');
  expect(screen.getByRole('tab', { name: '회원·장인' })).toHaveAttribute('aria-selected', 'true');
  expect(screen.queryByRole('heading', { name: '숨긴 상대법' })).toBeNull();
});

test('/admin: 탭은 주소 ?tab=로 유지된다 (설정·운영, 모르는 값은 콘텐츠), 긴 안내문은 「안내 ⓘ」 안에 접혀 있다', async () => {
  asOp();
  start('/admin?tab=settings');
  expect(await screen.findByRole('heading', { name: '비주류 픽' })).toBeDefined();
  expect(screen.getByRole('tab', { name: '설정·운영' })).toHaveAttribute('aria-selected', 'true');
  const info = screen.getByText('안내 ⓘ').closest('details');
  expect(info.open).toBe(false);
  expect(info.textContent).toContain('승인 제도는 꺼져 있습니다');
  fireEvent.click(screen.getByRole('tab', { name: '콘텐츠' }));
  expect(where()).toBe('/admin'); // 첫 탭은 주소에 안 남긴다
  cleanup();
  start('/admin?tab=nope');
  expect(await screen.findByRole('tab', { name: '콘텐츠', selected: true })).toBeDefined();
});

test('/admin: 0개인 구역은 점선 상자 대신 한 줄 「없음」', async () => {
  asOp();
  start('/admin');
  const sec = (await screen.findByRole('heading', { name: '숨긴 상대법' })).closest('section');
  expect(within(sec).getByText('없음')).toHaveClass('none-line');
  expect(sec.querySelector('.empty')).toBeNull();
});

test('긴 목록은 기본 개수만 보이고 [모두 보기]로 펼친다 (기본 개수는 adminView.js 한 곳)', async () => {
  asOp();
  fakeState.memberDetail['u-1'] = {
    info: { id: 'u-1', nickname: '탑고수', role: 'user', level: 5, is_guest: false, created_at: '2026-11-01T00:00:00Z', providers: ['google'], titles: [], posts: 0, builds: 0, comments: 0, matchups: 0, xp: 1 },
    posts: Array.from({ length: PREVIEW_COUNT.logs + 3 }, (_, i) => ({ id: 100 + i, title: `글 ${i}`, excerpt: '', created_at: '2026-11-08T00:00:00Z', status: 'visible', comment_count: 0 })),
    comments: [], edited_builds: [], moderation: [],
  };
  TABLES.profiles.push({ id: 'u-1', nickname: '탑고수', role: 'user', level: 5, main_title: null });
  start('/admin/members/u-1?tab=activity');
  const posts = await screen.findByRole('list', { name: '쓴 글' });
  expect(within(posts).getAllByRole('listitem')).toHaveLength(PREVIEW_COUNT.logs);
  fireEvent.click(screen.getByRole('button', { name: `모두 보기 (${PREVIEW_COUNT.logs + 3}개)` }));
  expect(within(screen.getByRole('list', { name: '쓴 글' })).getAllByRole('listitem')).toHaveLength(PREVIEW_COUNT.logs + 3);
  expect(screen.getByText('쓴 댓글 (최근 0개)').closest('section').textContent).toContain('없음'); // 0개 항목은 한 줄 「없음」
});

test('회원 상세: 이름 아래 상태 칩(가입 방식·등급·레벨·제한·경고), 탭 3개, 걸기·경고 버튼 나란히, 비회원은 비활성 버튼 + 작은 설명', async () => {
  asOp();
  TABLES.profiles.push({ id: 'u-g', nickname: '손님', role: 'user', level: 1, main_title: null });
  TABLES.user_warnings.push({ id: 9, user_id: 'u-g', memo: '첫 줄\n둘째 줄', created_at: '2026-11-20T00:00:00Z', created_by: '영자', restriction_id: null, notice_read_at: null, acked_at: null });
  fakeState.memberDetail['u-g'] = {
    info: { id: 'u-g', nickname: '손님', role: 'user', level: 1, is_guest: true, created_at: '2026-11-01T00:00:00Z', providers: [], titles: [], posts: 0, builds: 0, comments: 0, matchups: 0, xp: 0 },
    posts: [], comments: [], edited_builds: [], moderation: [],
  };
  start('/admin/members/u-g');
  const chips = await screen.findByRole('list', { name: '회원 상태' });
  expect(await within(chips).findByText('경고 1건 · 미확인 1')).toHaveClass('chip-bad');
  expect(within(chips).getByText('가입 비회원')).toBeDefined();
  expect(within(chips).getByText('등급 일반')).toBeDefined();
  expect(within(chips).getByText('Lv.1')).toBeDefined();
  expect(within(chips).getByText('제한 없음')).toBeDefined();
  expect(screen.getAllByRole('tab').map((t) => t.textContent)).toEqual(['정보·조치', '활동', '기록']);

  const actions = screen.getByLabelText('조치');
  expect(within(actions).getAllByRole('button').map((b) => b.textContent)).toEqual(['활동 제한 걸기', '경고 보내기']);
  expect(screen.getByRole('button', { name: '감독관 지정' })).toBeDisabled();
  expect(screen.getByText('비회원은 감독관으로 지정할 수 없습니다.').tagName).toBe('SMALL');

  // 경고: 날짜·보낸 사람·확인 여부·첫 줄만, [펼치기]로 전문
  const log = await screen.findByRole('list', { name: '경고 기록' });
  expect(log.textContent).toContain('첫 줄');
  fireEvent.click(within(log).getByRole('button', { name: '펼치기' }));
  expect(log.textContent).toContain('둘째 줄');
  fireEvent.click(screen.getByRole('tab', { name: '기록' }));
  expect(where()).toBe('/admin/members/u-g?tab=records');
});
