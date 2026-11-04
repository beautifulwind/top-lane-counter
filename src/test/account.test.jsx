// 묶음 B (017): 닉네임 없이 둘러보기 · 닉네임 바꾸기(30일에 한 번) · 회원 탈퇴
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeLogin, fakeState } from './fakeSupabase';
import { openMenu } from './menu';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

function Where() { const l = useLocation(); return <output data-testid="where">{l.pathname}</output>; }
const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /><Where /></MemoryRouter>);
const where = () => screen.getByTestId('where').textContent;
const MATCHUP = '/champion/Darius/counter/Quinn';
const card = (nickname) => screen.getByRole('article', { name: `빌드: ${nickname}` });
const section = (name) => screen.getByRole('region', { name });

// ---------------- 닉네임 없이 둘러보기 ----------------

test('닉네임 없음: 매치업 문서는 읽히고, 댓글 칸 대신 안내, 추천은 닉네임 설정으로', async () => {
  fakeLogin('u-new');
  start(MATCHUP);
  await screen.findByText(/퀸으로 다리우스 잡는 법/);
  expect(screen.getByText(/닉네임을 정하면 제안·빌드·투표·글·댓글을 쓸 수 있어요/)).toBeDefined();
  expect(await screen.findByText((_, el) => el?.tagName === 'P' && el.textContent === '닉네임을 정하면 댓글을 달 수 있어요.')).toBeDefined();
  fireEvent.click(within(card('탑고수')).getByRole('button', { name: '추천 5' }));
  expect(await screen.findByRole('heading', { name: '닉네임 정하기' })).toBeDefined();
  expect(fakeState.rpcCalls.filter((c) => c.name === 'vote_build')).toEqual([]);
});

test.each(['/board/new', '/me'])('닉네임 없음: 쓰기·내 정보 화면(%s)은 닉네임 설정으로', async (path) => {
  fakeLogin('u-new');
  start(path);
  expect(await screen.findByRole('heading', { name: '닉네임 정하기' })).toBeDefined();
  expect(where()).toBe('/welcome');
});

test('[나중에 정할게요]: 읽던 화면으로, 쓰기 화면에서 왔으면 홈으로', async () => {
  fakeLogin('u-new');
  start('/champion/Darius');
  fireEvent.click(await screen.findByRole('link', { name: '닉네임 정하기' }));
  fireEvent.click(await screen.findByRole('link', { name: '나중에 정할게요' }));
  await vi.waitFor(() => expect(where()).toBe('/champion/Darius'));
  cleanup();
  start('/board/new');
  fireEvent.click(await screen.findByRole('link', { name: '나중에 정할게요' }));
  await vi.waitFor(() => expect(where()).toBe('/'));
});

// ---------------- 닉네임 바꾸기 ----------------

test('닉네임 바꾸기: 열고 저장하면 바뀌고, [취소]·Esc로 닫힌다', async () => {
  fakeLogin('u-old');
  start('/me');
  const nick = await screen.findByRole('region', { name: '닉네임 바꾸기' });
  const before = TABLES.profiles.find((p) => p.id === 'u-old').nickname;
  fireEvent.click(await within(nick).findByRole('button', { name: '닉네임 바꾸기' }));
  expect(within(nick).getByLabelText('새 닉네임').value).toBe(before);
  expect(within(nick).getByText('저장하면 30일 동안 다시 바꿀 수 없어요.')).toBeDefined();
  fireEvent.click(within(nick).getByRole('button', { name: '고친 내용 저장' }));
  expect(await within(nick).findByRole('alert')).toHaveProperty('textContent', '지금 닉네임과 같아요.');
  fireEvent.keyDown(within(nick).getByLabelText('새 닉네임'), { key: 'Escape' });
  expect(within(nick).queryByLabelText('새 닉네임')).toBeNull();

  fireEvent.click(within(nick).getByRole('button', { name: '닉네임 바꾸기' }));
  fireEvent.change(within(nick).getByLabelText('새 닉네임'), { target: { value: '새탑' } });
  fireEvent.click(within(nick).getByRole('button', { name: '고친 내용 저장' }));
  expect(await within(nick).findByRole('status')).toHaveProperty('textContent', '닉네임을 "새탑"으로 바꿨어요.');
  expect(TABLES.profiles.find((p) => p.id === 'u-old').nickname).toBe('새탑');
});

test('닉네임 바꾸기: 30일 안에 바꿨으면 버튼 대신 다음 날짜', async () => {
  fakeLogin('u-old');
  TABLES.nickname_changes.push({ id: 1, user_id: 'u-old', old_nickname: 'a', new_nickname: 'b', changed_at: new Date(Date.now() - 86400000).toISOString() });
  start('/me');
  const nick = await screen.findByRole('region', { name: '닉네임 바꾸기' });
  expect(await within(nick).findByText(/부터 바꿀 수 있어요/)).toBeDefined();
  expect(within(nick).queryByRole('button', { name: '닉네임 바꾸기' })).toBeNull();
});

// ---------------- 회원 탈퇴 ----------------

test('운영자는 탈퇴 버튼이 없다', async () => {
  fakeLogin('u-op', { nickname: '영자(운)', role: 'admin', level: 0, main_title: null });
  start('/me');
  const del = await screen.findByRole('region', { name: '회원 탈퇴' });
  expect(within(del).getByText('운영자 계정은 탈퇴할 수 없어요.')).toBeDefined();
  expect(within(del).queryByRole('button')).toBeNull();
});

test('탈퇴: 닉네임을 그대로 적어야 [탈퇴 확정]이 켜지고, 끝나면 홈에서 인사', async () => {
  fakeLogin('u-old');
  const nickname = TABLES.profiles.find((p) => p.id === 'u-old').nickname;
  start('/me');
  const del = await screen.findByRole('region', { name: '회원 탈퇴' });
  fireEvent.click(within(del).getByRole('button', { name: '탈퇴' }));
  const confirm = within(del).getByRole('button', { name: '탈퇴 확정' });
  expect(confirm.disabled).toBe(true);
  fireEvent.change(within(del).getByRole('textbox'), { target: { value: `${nickname}x` } });
  expect(confirm.disabled).toBe(true);
  fireEvent.change(within(del).getByRole('textbox'), { target: { value: ` ${nickname} ` } });
  expect(confirm.disabled).toBe(false);
  fireEvent.click(confirm);
  expect(await screen.findByText(/탈퇴했어요/)).toBeDefined();
  expect(where()).toBe('/');
  expect(fakeState.functionCalls).toEqual([{ name: 'delete-account', body: { confirm: nickname } }]);
  expect((await openMenu()).getByRole('link', { name: '로그인 · 가입' })).toBeDefined();
});

test('탈퇴 실패: 서버 문구를 보여 주고 그대로 남는다', async () => {
  fakeLogin('u-old');
  const nickname = TABLES.profiles.find((p) => p.id === 'u-old').nickname;
  fakeState.functionError = '확인 칸에 내 닉네임을 그대로 적어 주세요.';
  start('/me');
  const del = await screen.findByRole('region', { name: '회원 탈퇴' });
  fireEvent.click(within(del).getByRole('button', { name: '탈퇴' }));
  fireEvent.change(within(del).getByRole('textbox'), { target: { value: nickname } });
  fireEvent.click(within(del).getByRole('button', { name: '탈퇴 확정' }));
  expect(await within(del).findByRole('alert')).toHaveProperty('textContent', '확인 칸에 내 닉네임을 그대로 적어 주세요.');
  expect(where()).toBe('/me');
  fireEvent.click(within(del).getByRole('button', { name: '취소' }));
  expect(within(del).queryByRole('textbox')).toBeNull();
});
