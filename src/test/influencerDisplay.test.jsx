// 장인 2a 화면 (046, SPEC 6-33): 장인 표시(InfluencerName)\u00B7인증 대기\u00B7닉네임 변경 예정, 장인 빌드 라벨, 시초 뱃지 제거, 사칭 금지, 닉네임 규칙
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import UserName from '../components/UserName';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeLogin, fakeState } from './fakeSupabase';
import { INFLUENCER_TIP, mimicsInfluencer } from '../lib/nickname';
import { nicknameProblem } from '../api/auth';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /></MemoryRouter>);
const MATCHUP = '/champion/Darius/counter/Quinn';
const tabs = () => screen.getAllByRole('tab').map((t) => t.textContent);
const ch = (code) => String.fromCharCode(code);
const profile = (id) => TABLES.profiles.find((p) => p.id === id);

// ---------------- 닉네임 표시 ----------------

test('장인: 진홍 "장인" 태그 + 닉네임을 감싼 칸, 말풍선, 레벨\u00B7칭호는 그대로', () => {
  const { container } = render(<UserName profile={{ nickname: '페이커', level: 7, main_title: 'solid_heavy', influencer: 'pro' }} />);
  const box = container.querySelector('.inf-name');
  expect(box).not.toBeNull();
  expect(box.getAttribute('title')).toBe(INFLUENCER_TIP);
  expect(INFLUENCER_TIP).toBe('인증된 장인(크리에이터\u00B7그랜드마스터 이상\u00B7프로게이머)');
  expect(box.querySelector('.inf-tag').textContent).toBe('장인');
  expect(box.querySelector('.user-nick').textContent).toBe('페이커');
  expect(container.querySelector('.user-lv').textContent).toBe('Lv.7');
  expect(container.querySelector('.title-badge')).not.toBeNull();
});

test('빌드 표시(plain): 레벨\u00B7칭호는 빼고 장인 태그는 보인다', () => {
  const { container } = render(<UserName plain profile={{ nickname: '페이커', level: 7, main_title: 'solid_heavy', influencer: 'creator' }} />);
  expect(container.querySelector('.user-lv')).toBeNull();
  expect(container.querySelector('.title-badge')).toBeNull();
  expect(container.querySelector('.inf-tag').textContent).toBe('장인');
});

test('닉네임 글자에 "장인"이 들어 있어도 장인 칸은 생기지 않는다', () => {
  const { container } = render(<UserName profile={{ nickname: '장인정신', level: 3, main_title: null }} />);
  expect(container.querySelector('.inf-name, .inf-tag')).toBeNull();
  expect(container.textContent).toBe('Lv.3 장인정신');
});

test('인증 대기: 회색 점선 + 모래시계 + "인증 대기", 닉네임 변경 예정: 회색 태그', () => {
  const a = render(<UserName profile={{ nickname: '희망닉', level: 2, main_title: null, nickname_state: 'pending' }} />);
  const pending = a.container.querySelector('.nick-pending');
  expect(pending.textContent).toBe('\u23F3 희망닉 인증 대기');
  expect(a.container.querySelector('.inf-tag')).toBeNull();
  cleanup();
  const b = render(<UserName profile={{ nickname: '겹친닉', level: 2, main_title: null, nickname_state: 'yielding' }} />);
  expect(b.container.querySelector('.nick-yield-tag').textContent).toBe('닉네임 변경 예정');
  expect(b.container.textContent).toBe('Lv.2 겹친닉 닉네임 변경 예정');
});

test('긴 닉네임(20자)도 감싼 칸이 줄을 바꿀 수 있다 (폰에서 넘치지 않음)', () => {
  const long = '가나다라마바사아자차카타파하가나다라마바';
  const { container } = render(<UserName profile={{ nickname: long, level: 1, main_title: null, influencer: 'grandmaster' }} />);
  expect(container.querySelector('.inf-name .user-nick').textContent).toHaveLength(20);
  // 감싼 칸은 inline(줄바꿈 가능) \u2014 index.css .inf-name { display: inline; box-decoration-break: clone; overflow-wrap: anywhere }
  expect(container.querySelector('.inf-name').tagName).toBe('SPAN');
});

// ---------------- 장인 빌드 라벨 ----------------

test('장인 빌드: 처음 만든 분이 장인이면 탭\u00B7제목 앞에 "장인 빌드", 제목 옆에 "이후 N명이 수정했습니다"', async () => {
  const b = TABLES.builds.find((x) => x.id === 102);
  b.author = { ...b.author, influencer: 'creator' };
  b.name = '정복자 딜교형';
  const unnamed = TABLES.builds.find((x) => x.id === 103);
  unnamed.author = { ...unnamed.author, influencer: 'pro' };
  fakeState.editorCounts = { 102: 2, 103: 0 };
  start(MATCHUP);
  await screen.findByText(/퀸으로 다리우스 이기는 법/);
  expect(tabs()).toEqual(['장인 빌드 정복자 딜교형 추천 5', '장인 빌드 추천 2', '빌드 1 추천 1', '빌드 5 추천 0']);
  expect(fakeState.rpcCalls).toContainEqual({ name: 'build_editor_counts', args: { p_counter: 1 } });
  const title = screen.getByRole('heading', { level: 3 });
  expect(title.textContent).toBe('장인 빌드 정복자 딜교형 이후 2명이 수정했습니다');
  expect(title.querySelector('.inf-build-tag').textContent).toBe('장인 빌드');
  // 작성자 칸: 닉네임 + 장인 태그, 레벨\u00B7칭호\u00B7시초 뱃지 없음
  const author = document.querySelector('.build-author');
  expect(author.querySelector('.inf-tag')).not.toBeNull();
  expect(author.querySelector('.user-lv, .title-badge, .origin-badge')).toBeNull();

  fireEvent.click(screen.getByRole('tab', { name: /^장인 빌드 추천 2/ }));
  expect(screen.getByRole('heading', { level: 3 }).textContent).toBe('장인 빌드'); // 아무도 안 고쳤으면 수 없음
});

test('장인이 아니면(해제\u00B7탈퇴 포함) 라벨이 없다', async () => {
  fakeState.editorCounts = { 102: 4 };
  start(MATCHUP);
  await screen.findByText(/퀸으로 다리우스 이기는 법/);
  expect(tabs()[0]).toBe('빌드 2 추천 5');
  expect(screen.getByRole('heading', { level: 3 }).textContent).toBe('빌드 2');
  expect(document.querySelector('.inf-build-tag')).toBeNull();
});

// ---------------- 사칭 금지 (DB nickname_mimics_influencer와 같은 기준) ----------------

test('사칭 금지: [장인]\u00B7(장인) 변형, "장인 "으로 시작 \u2192 막고, 붙여 쓴 "장인정신"은 된다', () => {
  for (const bad of ['[장인]티', '(장인)티', '티(장인)', '\u3010 장 인 \u3011티', '\uFF08장인\uFF09', '장인 티', '장인_티', '장인|티', '장인\u00B7티', `장인${ch(0x200b)} 티`, `[장${ch(0x200b)}인]`]) {
    expect([bad, mimicsInfluencer(bad)]).toEqual([bad, true]);
  }
  for (const good of ['장인정신', '티장인', '장인', '대장인 티', '장 인']) {
    expect([good, mimicsInfluencer(good)]).toEqual([good, false]);
  }
  expect(nicknameProblem('[장인]티')).toBe('닉네임에는 [장인]\u00B7(장인)을 쓸 수 없고, "장인 "으로 시작할 수 없습니다.');
  expect(nicknameProblem('장인정신')).toBeNull();
});

// ---------------- 닉네임 바꾸기 규칙 ----------------

test('장인은 닉네임을 직접 못 바꾼다: 버튼 대신 [문의하기] 안내', async () => {
  fakeLogin('u-old');
  profile('u-old').influencer = 'creator';
  start('/me/settings');
  const nick = await screen.findByRole('region', { name: '닉네임 바꾸기' });
  expect(await within(nick).findByText(/인증된 장인은 닉네임을 직접 바꿀 수 없습니다/)).toBeDefined();
  expect(within(nick).queryByRole('button', { name: '닉네임 바꾸기' })).toBeNull();
});

test('인증 대기 중에는 닉네임을 못 바꾼다', async () => {
  fakeLogin('u-old');
  profile('u-old').nickname_state = 'pending';
  start('/me/settings');
  const nick = await screen.findByRole('region', { name: '닉네임 바꾸기' });
  expect(await within(nick).findByText(/심사하는 동안에는 닉네임을 바꿀 수 없습니다/)).toBeDefined();
  expect(within(nick).queryByRole('button', { name: '닉네임 바꾸기' })).toBeNull();
});

test('닉네임 변경 예정: 30일 안에 바꿨어도 바로 바꿀 수 있고, 바꾸면 표시가 사라진다', async () => {
  fakeLogin('u-old');
  Object.assign(profile('u-old'), { nickname_state: 'yielding', nickname_reset_at: '2026-11-15T03:00:00Z' });
  TABLES.nickname_changes.push({ id: 1, user_id: 'u-old', old_nickname: 'a', new_nickname: 'b', kind: 'user', changed_at: new Date(Date.now() - 86400000).toISOString() });
  start('/me/settings');
  const nick = await screen.findByRole('region', { name: '닉네임 바꾸기' });
  expect(await within(nick).findByText(/임시 닉네임으로 바뀝니다/)).toBeDefined();
  fireEvent.click(within(nick).getByRole('button', { name: '닉네임 바꾸기' }));
  fireEvent.change(within(nick).getByLabelText('새 닉네임'), { target: { value: '새탑' } });
  fireEvent.click(within(nick).getByRole('button', { name: '고친 내용 저장' }));
  expect(await within(nick).findByRole('status')).toHaveProperty('textContent', '닉네임을 "새탑"으로 바꿨습니다.');
  expect(profile('u-old')).toMatchObject({ nickname: '새탑', nickname_state: null });
  expect(within(nick).queryByText(/임시 닉네임으로 바뀝니다/)).toBeNull();
});

test('마지막 변경이 운영자\u00B7되돌림\u00B7임시 닉네임이면 30일 제한 없이 바꿀 수 있다', async () => {
  fakeLogin('u-old');
  const day = (n) => new Date(Date.now() - n * 86400000).toISOString();
  TABLES.nickname_changes.push(
    { id: 1, user_id: 'u-old', old_nickname: 'a', new_nickname: 'b', kind: 'apply', changed_at: day(5) },
    { id: 2, user_id: 'u-old', old_nickname: 'b', new_nickname: 'a', kind: 'revert', changed_at: day(1) },
  );
  start('/me/settings');
  const nick = await screen.findByRole('region', { name: '닉네임 바꾸기' });
  expect(await within(nick).findByRole('button', { name: '닉네임 바꾸기' })).toBeDefined();
  expect(within(nick).queryByText(/부터 바꿀 수 있습니다/)).toBeNull();
});

test('DB가 비슷한 닉네임을 막으면 그 이유를 보여 준다', async () => {
  fakeLogin('u-old');
  TABLES.profiles.push({ id: 'u-x', nickname: 'Faker', role: 'user', level: 1 });
  start('/me/settings');
  const nick = await screen.findByRole('region', { name: '닉네임 바꾸기' });
  fireEvent.click(await within(nick).findByRole('button', { name: '닉네임 바꾸기' }));
  fireEvent.change(within(nick).getByLabelText('새 닉네임'), { target: { value: 'faker' } });
  fireEvent.click(within(nick).getByRole('button', { name: '고친 내용 저장' }));
  expect(await within(nick).findByRole('alert')).toHaveProperty('textContent', '이미 사용 중인 닉네임입니다. 비슷한 닉네임도 쓸 수 없습니다.');
});
