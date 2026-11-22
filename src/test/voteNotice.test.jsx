// 추천·비추천 안내 보강 (SPEC 6-79): 눌러도 못 하는 경우의 안내, 서버 거절 사유 문장, 운영자 경우
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { act, cleanup, fireEvent, render, renderHook, screen, waitFor, within } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { AppRoutes } from '../App';
import { NOTICE_MS, useVoteNotice } from '../components/VoteNotice';
import { GO_DELAY_MS, MSG, voteErrorText } from '../lib/voteMessages';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeBuild, fakeLogin, fakePost, fakeState } from './fakeSupabase';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); vi.useRealTimers(); });

function Where() { const l = useLocation(); return <output data-testid="where">{l.pathname + l.search}</output>; }
const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /><Where /></MemoryRouter>);
const where = () => screen.getByTestId('where').textContent;
const MATCHUP = '/champion/Darius/counter/Quinn';
const card = (nickname) => screen.getByRole('article', { name: `빌드: ${nickname}` });
const rpcCalls = (name) => fakeState.rpcCalls.filter((c) => c.name === name);
const info = () => document.querySelector('.vote-notice-info');

test('문장 변환: 서버 거절 사유마다 이용자 문장', () => {
  const t = (m) => voteErrorText(new Error(m));
  expect(t('공개된 빌드에만 투표할 수 있어요.')).toBe(MSG.notPublic);
  expect(t('내 글은 추천할 수 없어요.')).toBe(MSG.ownPost);
  expect(t('추천할 수 없는 글이에요.')).toBe(MSG.postGone);
  expect(t('글을 찾지 못했어요.')).toBe(MSG.postGone);
  expect(t('닉네임을 정해야 쓸 수 있어요.')).toBe(MSG.nickname);
  expect(t('권한이 없습니다. (로그인이 필요하거나 운영자만 할 수 있는 작업입니다)')).toBe(MSG.denied);
  expect(t('TypeError: Load failed')).toBe(MSG.network);
  expect(t('weird failure')).toBe('추천하지 못했습니다. 잠시 뒤 다시 눌러 주세요.');
  expect(t('처음 보는 한글 사유입니다.')).toBe('추천하지 못했습니다. 처음 보는 한글 사유입니다.');
});

test('안내는 8초 뒤 저절로 사라지고, 새 안내가 오면 시간을 다시 잰다', () => {
  vi.useFakeTimers();
  const { result } = renderHook(() => useVoteNotice());
  act(() => result.current[1]({ kind: 'info', text: 'a' }));
  act(() => { vi.advanceTimersByTime(NOTICE_MS - 1000); });
  act(() => result.current[1]({ kind: 'info', text: 'b' }));
  act(() => { vi.advanceTimersByTime(NOTICE_MS - 1000); });
  expect(result.current[0]?.text).toBe('b');
  act(() => { vi.advanceTimersByTime(1000); });
  expect(result.current[0]).toBeNull();
});

test('닉네임 정하기 전(빌드): 안내를 보여 준 뒤 닉네임 정하기로, 서버 호출 없음', async () => {
  fakeLogin('u-nonick'); // 닉네임 없는 로그인
  start(MATCHUP);
  await screen.findByText(/퀸으로 다리우스 이기는 법/);
  fireEvent.click(within(card('탑고수')).getByRole('button', { name: '추천 5' }));
  expect(info()).toHaveTextContent('닉네임을 정하면 추천할 수 있습니다. 닉네임 정하기로 이동합니다.');
  await waitFor(() => expect(where()).toBe('/welcome'), { timeout: GO_DELAY_MS + 1500 });
  expect(rpcCalls('vote_build')).toEqual([]);
});

test('로그인 전(빌드): 안내가 먼저, 이동은 잠깐 뒤 — 여러 번 눌러도 한 번만', async () => {
  start(MATCHUP);
  await screen.findByText(/퀸으로 다리우스 이기는 법/);
  const up = within(card('탑고수')).getByRole('button', { name: '추천 5' });
  fireEvent.click(up);
  fireEvent.click(up);
  expect(where()).toBe(MATCHUP);
  expect(info()).toHaveTextContent('로그인하면 추천할 수 있습니다. 로그인 화면으로 이동합니다.');
  await waitFor(() => expect(where()).toBe('/login'), { timeout: GO_DELAY_MS + 1500 });
});

test('닉네임 정하기 전·로그인 전(글): 버튼이 보이고 안내 뒤에 이동', async () => {
  TABLES.posts.push(fakePost(1, { author_id: 'u-x', author: { nickname: '남의글', level: 2, main_title: null } }));
  fakeLogin('u-nonick2');
  start('/board/1');
  fireEvent.click(await screen.findByRole('button', { name: /^추천/ }));
  expect(info()).toHaveTextContent('닉네임을 정하면 추천할 수 있습니다.');
  await waitFor(() => expect(where()).toBe('/welcome'), { timeout: GO_DELAY_MS + 1500 });
  expect(rpcCalls('vote_post')).toEqual([]);
});

test('글 추천 거절 사유: 지워졌거나 숨겨진 글', async () => {
  TABLES.posts.push(fakePost(1, { author_id: 'u-x', author: { nickname: '남의글', level: 2, main_title: null } }));
  fakeLogin('u-old', { nickname: '나', role: 'user', level: 1, main_title: null });
  start('/board/1');
  fakeState.rpcError = '추천할 수 없는 글이에요.';
  fireEvent.click(await screen.findByRole('button', { name: /^추천/ }));
  const alert = await screen.findByRole('alert');
  expect(alert).toHaveTextContent('지워졌거나 숨겨진 글이라 추천할 수 없습니다.');
  expect(alert.className).toContain('vote-notice-error');
});

test('성공하면 스크린리더용 상태 문장 (추천했습니다 / 취소했습니다)', async () => {
  fakeLogin('u-old');
  start(MATCHUP);
  await screen.findByText(/퀸으로 다리우스 이기는 법/);
  const c = card('탑고수');
  fireEvent.click(within(c).getByRole('button', { name: '추천 5' }));
  await waitFor(() => expect(c.parentElement.querySelector('.sr-only[role="status"]')).toHaveTextContent('추천했습니다.'));
  fireEvent.click(await within(c).findByRole('button', { name: '추천 6' }));
  await waitFor(() => expect(c.parentElement.querySelector('.sr-only[role="status"]')).toHaveTextContent('추천을 취소했습니다.'));
});

// ---- 운영자 ----
test('운영자가 쓴 빌드: 흐린 버튼 + 이유 (운영자도 내 빌드에는 못 누른다)', async () => {
  fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0, main_title: null });
  TABLES.builds.push(fakeBuild(110, { nickname: '영자', role: 'admin', level: 0, main_title: null }, { author_id: 'u-op', up_count: 9 }));
  start(`${MATCHUP}?build=110`);
  await screen.findByText(/퀸으로 다리우스 이기는 법/);
  const mine = screen.getByRole('article', { name: '빌드: (운)영자' });
  const up = within(mine).getByRole('button', { name: '추천 9' });
  expect(up).toHaveAttribute('aria-disabled', 'true');
  fireEvent.click(up);
  expect(info()).toHaveTextContent('내가 쓴 빌드에는 추천·비추천할 수 없습니다.');
  expect(rpcCalls('vote_build')).toEqual([]);
});

test('운영자가 남의 공개 빌드에 누르면 그대로 된다 (운영자 전용 거절은 없다)', async () => {
  fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0, main_title: null });
  start(MATCHUP);
  await screen.findByText(/퀸으로 다리우스 이기는 법/);
  fireEvent.click(within(card('탑고수')).getByRole('button', { name: '추천 5' }));
  expect(await within(card('탑고수')).findByRole('button', { name: '추천 6' })).toHaveAttribute('aria-pressed', 'true');
});

test('운영자가 보는 사이 다른 운영자가 빌드를 숨기면: 거절 사유를 새로고침 안내로', async () => {
  fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0, main_title: null });
  start(MATCHUP);
  await screen.findByText(/퀸으로 다리우스 이기는 법/);
  fakeState.rpcError = '공개된 빌드에만 투표할 수 있어요.';
  fireEvent.click(within(card('탑고수')).getByRole('button', { name: '추천 5' }));
  expect(await screen.findByRole('alert')).toHaveTextContent('화면을 새로고침해 주세요.');
});
