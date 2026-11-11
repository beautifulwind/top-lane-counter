// 039: 승인 제도를 끈 상태(lib/features.js APPROVAL_ENABLED = false)의 화면. 승인용 화면은 지우지 않고 끈다.
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, render, screen, within } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { AppRoutes } from '../App';
import { APPROVAL_ENABLED } from '../lib/features';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeBuild, fakeLogin, fakeProposal } from './fakeSupabase';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

function Where() { const l = useLocation(); return <output data-testid="where">{l.pathname + l.search}</output>; }
const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /><Where /></MemoryRouter>);
const where = () => screen.getByTestId('where').textContent;
const asOperator = () => fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0, main_title: null });
const NOTICE = /이제 승인 없이 바로 등록·수정합니다/;

test('스위치는 꺼져 있다 (DB xp_rules.approval_on = 0과 같게)', () => {
  expect(APPROVAL_ENABLED).toBe(false);
});

test('운영자 페이지: 승인 대기·재검토·빌드 승인 대기 구역이 없고, 숨긴 카운터·숨긴 빌드는 그대로', async () => {
  TABLES.edit_proposals.push(fakeProposal()); // 남아 있어도 (039는 0일 때만 실행된다) 목록에 나오지 않는다
  asOperator();
  start('/admin');
  expect(await screen.findByRole('heading', { name: /숨긴 카운터/ })).toBeDefined();
  expect(screen.getByRole('heading', { name: /숨긴 빌드/ })).toBeDefined();
  expect(screen.getByText(/승인 제도는 꺼져 있습니다/)).toBeDefined();
  expect(screen.queryByRole('heading', { name: /승인 대기/ })).toBeNull();
  expect(screen.queryByRole('heading', { name: /재검토 기다리는 중/ })).toBeNull();
  expect(screen.queryByRole('listitem', { name: /\[문서 수정\]/ })).toBeNull();
});

test('감독관 페이지: 새 카운터 승인 대기가 없다', async () => {
  fakeLogin('u-mod', { nickname: '감독', role: 'moderator', level: 3, main_title: null });
  start('/admin');
  expect(await screen.findByRole('heading', { name: /자유게시판·댓글/ })).toBeDefined();
  expect(screen.queryByRole('heading', { name: /승인 대기/ })).toBeNull();
});

test('예전 [문서 수정 제안] 주소 → 상대법 화면 + 안내', async () => {
  fakeLogin('u-old');
  start('/champion/Darius/counter/Quinn/edit');
  expect(await screen.findByText(NOTICE)).toBeDefined();
  expect(where()).toBe('/champion/Darius/counter/Quinn');
  expect(screen.queryByRole('heading', { name: /수정 제안/ })).toBeNull();
});

test('예전 제안·빌드 [고쳐서 다시 보내기] 주소 → 기록 보기 + 안내, 대기 중이어도 [수정] 버튼은 없다', async () => {
  TABLES.edit_proposals.push(fakeProposal({ id: 501, proposer_id: 'u-old', status: 'pending' }));
  TABLES.builds.push(fakeBuild(160, { nickname: '기존유저', level: 1, main_title: null }, { author_id: 'u-old', status: 'pending' }));
  fakeLogin('u-old');
  start('/me/proposals/501/edit');
  expect(await screen.findByText(NOTICE)).toBeDefined();
  expect(where()).toBe('/me/proposals/501');
  expect(screen.queryByRole('link', { name: '수정' })).toBeNull();
  cleanup();
  start('/me/builds/160/edit');
  expect(await screen.findByText(NOTICE)).toBeDefined();
  expect(where()).toBe('/me/builds/160');
  expect(screen.queryByRole('link', { name: '수정' })).toBeNull();
});

test('마이페이지: 보낸 제안이 없으면 "내 제안" 구역이 없고, 있으면 예전 기록이라고 알려 준다', async () => {
  fakeLogin('u-old');
  start('/me');
  expect(await screen.findByRole('heading', { name: /내 빌드/ })).toBeDefined();
  expect(screen.queryByRole('heading', { name: /내 제안/ })).toBeNull();
  expect(screen.getByText('아직 올린 빌드가 없습니다. 상대법 화면의 [+ 새 빌드]에서 올릴 수 있습니다.')).toBeDefined();
  cleanup();
  TABLES.edit_proposals.push(fakeProposal({ id: 502, proposer_id: 'u-old', status: 'approved' }));
  start('/me');
  expect(await screen.findByRole('heading', { name: /내 제안/ })).toBeDefined();
  expect(screen.getByText(/예전 승인 제도 때 보낸 제안 기록입니다/)).toBeDefined();
});

test('내 공개 빌드 자세히: [빌드 수정]으로 바로 고칠 수 있다고 안내', async () => {
  TABLES.builds.push(fakeBuild(161, { nickname: '기존유저', level: 1, main_title: null }, { author_id: 'u-old' }));
  fakeLogin('u-old');
  start('/me/builds/161');
  expect(await screen.findByText(/상대법 화면의 \[빌드 수정\]에서 바로 고칠 수 있습니다/)).toBeDefined();
  expect(screen.getByRole('link', { name: '빌드 수정' }).getAttribute('href')).toBe('/champion/Darius/counter/Quinn/build/161/edit');
  expect(screen.getByRole('link', { name: '문서 보기' }).getAttribute('href')).toBe('/champion/Darius/counter/Quinn?build=161');
});

test('휴대폰 알림 설정: 운영진은 "새 상대법·새 빌드·새 문의", 내 알림은 "다시 공개"만', async () => {
  asOperator();
  start('/me/settings');
  const kinds = await screen.findByRole('group', { name: /받을 알림/ });
  expect(within(kinds).getByRole('checkbox', { name: /운영진 알림: 새 상대법·새 빌드·새 문의/ })).toBeDefined();
  expect(within(kinds).getByRole('checkbox', { name: /내 상대법·빌드 다시 공개/ })).toBeDefined();
  expect(screen.queryByText(/승인·거절·재검토/)).toBeNull();
  expect(screen.queryByText(/새 제안/)).toBeNull();
});
