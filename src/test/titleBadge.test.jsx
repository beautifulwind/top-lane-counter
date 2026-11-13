// 칭호 도감 3단계(054, SPEC 6-41): 한정판 대표 칭호 + 닉네임 옆 배지.
// 배지는 앱이 켜질 때 한 번 읽은 public_title_info(비로그인도)로 그린다 — 게시판·댓글·문서 댓글·회원 관리
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import UserName from '../components/UserName';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeComment, fakeDocComment, fakeLimitedTitle, fakeLogin, fakePost, fakeState } from './fakeSupabase';
import { loadTitleInfo, titleName } from '../lib/titles';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /></MemoryRouter>);
const ME = 'u-old';

/** 가짜 DB 한정판 3개 (모두 장착 가능): 그림+색 / 색만 / 비밀(색). 장착 불가 1개와 숨김 1개는 배지에 안 나온다 */
const addLimited = () => {
  TABLES.title_catalog.push(
    fakeLimitedTitle('cup_winner', { name: '티확찢', how_to: '공모전 1등', description: '공모전 우승', icon: 'cup_winner.png', color: '#c0392b', equippable: true, sort_order: 1 }),
    fakeLimitedTitle('s1_star', { name: '시즌1 별', how_to: '시즌1 이벤트', color: '#7cc4ff', equippable: true, sort_order: 2 }),
    fakeLimitedTitle('secret_one', { name: '숨은 고수', how_to: '아무도 모르는 방법', color: '#33aa55', secret: true, equippable: true, sort_order: 3 }),
    fakeLimitedTitle('joined', { name: '참가자', how_to: '공모전 참가', equippable: false, sort_order: 4 }),
    fakeLimitedTitle('gone', { name: '숨긴 칭호', how_to: '숨김', hidden: true, equippable: true, sort_order: 5 }),
  );
};
const person = (id, nickname, mainTitle) => {
  TABLES.profiles.push({ id, nickname, role: 'user', xp: 0, level: 5, main_title: mainTitle });
  TABLES.user_titles.push({ user_id: id, title_key: mainTitle, earned_at: '2026-11-05T03:00:00Z' });
  return { nickname, level: 5, main_title: mainTitle };
};
const owns = (key) => TABLES.user_titles.push({ user_id: ME, title_key: key, earned_at: '2026-11-05T03:00:00Z' });
const badgeOf = (row) => row.querySelector('.title-badge');

test('공개 정보: 활동 6 + 한정판(숨김 빼고), 비밀은 누군가 대표로 달았을 때만 — 소개·얻는 방법은 없다', async () => {
  addLimited();
  const { db } = await import('./fakeSupabase');
  const keys = async () => (await db().rpc('public_title_info')).data.map((t) => t.key);
  expect(await keys()).toEqual(['top_addict', 'tool_hater', 'solid_heavy', 'butcher_owner', 'general', 'offmeta', 'cup_winner', 's1_star', 'joined']);
  person('u-c', '고수', 'secret_one');
  expect(await keys()).toContain('secret_one');
  const { data } = await db().rpc('public_title_info');
  expect(Object.keys(data.find((t) => t.key === 'secret_one')).sort()).toEqual(['color', 'icon', 'key', 'kind', 'name']);
  expect(JSON.stringify(data)).not.toContain('아무도 모르는 방법');
  expect(fakeState.rpcCalls).toEqual([]); // 앱이 알아서 부르는 것이라 남기지 않음
});

test('비로그인 게시판: 한정판 3개가 닉네임 옆 22px 배지로 — 그림 파일 / 공통 훈장에 색 / 비밀 칭호도 단 사람 것은 이름', async () => {
  addLimited();
  TABLES.posts.push(
    fakePost(1, { title: '그림 칭호 글', author_id: 'u-a', author: person('u-a', '우승자', 'cup_winner') }),
    fakePost(2, { title: '색 칭호 글', author_id: 'u-b', author: person('u-b', '별님', 's1_star') }),
    fakePost(3, { title: '비밀 칭호 글', author_id: 'u-c', author: person('u-c', '고수', 'secret_one') }),
    fakePost(5, { title: '기존 칭호 글', author_id: 'u-d', author: { nickname: '탑고수', level: 7, main_title: 'solid_heavy' } }),
  );
  start('/board');
  const rowOf = async (title) => (await screen.findByText(title)).closest('li');

  await waitFor(async () => expect((await rowOf('그림 칭호 글')).querySelector('.title-badge-art')).not.toBeNull());
  const cup = badgeOf(await rowOf('그림 칭호 글'));
  expect(cup.textContent).toBe('티확찢');
  expect(cup.getAttribute('title')).toBe("칭호 '티확찢'");
  expect(cup.className).toBe('title-badge title-badge-art');
  expect(cup.style.getPropertyValue('--t')).toBe('#c0392b');
  const img = cup.querySelector('.title-badge-medal img.medal-img');
  expect(img.getAttribute('src')).toBe('/titles/cup_winner.png');
  expect([img.getAttribute('width'), img.getAttribute('height')]).toEqual(['18', '18']);
  expect(cup.querySelector('.title-badge-medal').getAttribute('aria-hidden')).toBe('true');

  const star = badgeOf(await rowOf('색 칭호 글'));
  expect(star.textContent).toBe('시즌1 별');
  expect(star.style.getPropertyValue('--t')).toBe('#7cc4ff');
  expect(star.querySelector('svg.medal-icon')).not.toBeNull(); // 그림이 없으면 공통 훈장에 색
  expect(star.querySelector('img')).toBeNull();

  expect(badgeOf(await rowOf('비밀 칭호 글')).textContent).toBe('숨은 고수');

  const old = badgeOf(await rowOf('기존 칭호 글')); // 기존 6개는 예전 글자 칸 그대로
  expect(old.className).toBe('title-badge solid_heavy');
  expect(old.textContent).toBe('단단묵직');
  expect(old.querySelector('svg, img')).toBeNull();
});

test('댓글·문서 댓글에도 한정판 배지', async () => {
  addLimited();
  const a = person('u-a', '우승자', 'cup_winner');
  TABLES.posts.push(fakePost(1, { title: '글', comment_count: 1 }));
  TABLES.post_comments.push(fakeComment(11, 1, { author_id: 'u-a', author: a, body: '댓글 내용' }));
  const { unmount } = start('/board/1');
  const c = (await screen.findByText('댓글 내용')).closest('li');
  await waitFor(() => expect(c.querySelector('.title-badge-art')?.textContent).toBe('티확찢'));
  unmount();

  TABLES.doc_comments.push(fakeDocComment(1, { author_id: 'u-b', author: person('u-b', '별님', 's1_star'), body: '문서 댓글 내용' }));
  start('/champion/Darius/counter/Quinn');
  const d = (await screen.findByText('문서 댓글 내용')).closest('li');
  await waitFor(() => expect(d.querySelector('.title-badge-art')?.textContent).toBe('시즌1 별'));
});

test('모르는 키·숨김 칭호·아무도 안 단 비밀 칭호는 배지를 그리지 않는다 (키 글자도 안 보임)', async () => {
  addLimited();
  await loadTitleInfo();
  for (const key of ['gone', 'secret_one', 'nope']) {
    const { container, unmount } = render(<UserName profile={{ nickname: '누구', level: 3, main_title: key }} />);
    expect(container.querySelector('.title-badge')).toBeNull();
    expect(container.textContent).toBe('Lv.3 누구');
    unmount();
  }
});

test('칭호 정보를 읽기 전(첫 그림)에도 기존 6개 칭호는 그대로 나온다', () => {
  const { container } = render(<UserName profile={{ nickname: '탑고수', level: 7, main_title: 'solid_heavy' }} />);
  expect(container.querySelector('.title-badge.solid_heavy').textContent).toBe('단단묵직');
});

test('마이페이지: 장착 가능한 한정판 [대표로 설정] → 닉네임 옆 배지, [대표 해제]. 장착 불가 한정판·장인은 버튼 없음', async () => {
  addLimited();
  owns('cup_winner'); owns('joined');
  TABLES.profiles.find((p) => p.id === ME).influencer = 'creator';
  fakeLogin(ME);
  start('/me');
  await screen.findByRole('list', { name: '특별 칭호' });
  fireEvent.click(screen.getByRole('button', { name: '더보기' })); // 훈장 11개 > 접힌 10개

  fireEvent.click(screen.getByRole('button', { name: /^참가자/ }));
  expect(within(screen.getByRole('group', { name: '칭호 참가자' })).queryByRole('button')).toBeNull();
  fireEvent.click(screen.getByRole('button', { name: /^장인/ }));
  expect(within(screen.getByRole('group', { name: '칭호 장인' })).queryByRole('button')).toBeNull();

  fireEvent.click(screen.getByRole('button', { name: /^티확찢/ }));
  fireEvent.click(within(screen.getByRole('group', { name: '칭호 티확찢' })).getByRole('button', { name: '대표로 설정' }));
  await waitFor(() => expect(TABLES.profiles.find((p) => p.id === ME).main_title).toBe('cup_winner'));
  await waitFor(() => expect(document.querySelector('.doc-title .title-badge-art')?.textContent).toBe('티확찢'));
  expect(screen.getByRole('button', { name: '티확찢 (대표 칭호)' })).toBeDefined();

  fireEvent.click(within(screen.getByRole('group', { name: '칭호 티확찢' })).getByRole('button', { name: '대표 해제' }));
  await waitFor(() => expect(TABLES.profiles.find((p) => p.id === ME).main_title).toBeNull());
  await waitFor(() => expect(document.querySelector('.doc-title .title-badge')).toBeNull());
  delete TABLES.profiles.find((p) => p.id === ME).influencer;
});

test('마이페이지: 비밀 한정판을 대표로 고르면 다시 읽지 않아도 배지에 이름이 나온다', async () => {
  addLimited();
  owns('secret_one');
  fakeLogin(ME);
  start('/me');
  fireEvent.click(await screen.findByRole('button', { name: /^숨은 고수/ }));
  fireEvent.click(within(screen.getByRole('group', { name: '칭호 숨은 고수' })).getByRole('button', { name: '대표로 설정' }));
  await waitFor(() => expect(document.querySelector('.doc-title .title-badge-art')?.textContent).toBe('숨은 고수'));
});

test('장착 불가 한정판은 DB가 막는다 (화면 우회)', async () => {
  addLimited();
  owns('joined');
  fakeLogin(ME);
  const { setMainTitle } = await import('../api/rewards');
  await expect(setMainTitle(ME, 'joined')).rejects.toThrow('대표 칭호로 고를 수 없습니다');
  TABLES.title_catalog.find((c) => c.key === 'gone').equippable = true;
  owns('gone');
  await expect(setMainTitle(ME, 'gone')).rejects.toThrow('대표 칭호로 고를 수 없습니다'); // 숨김도 불가
});

test('한정판 회수 → 대표 칭호가 저절로 비워진다 (외래 키)', async () => {
  addLimited();
  person('u-a', '우승자', 'cup_winner');
  fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0, main_title: null });
  const { db } = await import('./fakeSupabase');
  const { error } = await db().rpc('revoke_title', { p_user: 'u-a', p_key: 'cup_winner', p_note: '부정 취득' });
  expect(error).toBeNull();
  expect(TABLES.profiles.find((p) => p.id === 'u-a').main_title).toBeNull();
});

test('회원 관리(AdminMember): 대표 칭호·얻은 칭호에 한정판 이름 (도감 정보), 닉네임 옆 배지', async () => {
  addLimited();
  person('u-a', '우승자', 'cup_winner');
  fakeState.memberDetail['u-a'] = {
    info: { id: 'u-a', nickname: '우승자', role: 'user', level: 5, xp: 300, main_title: 'cup_winner', is_guest: false, providers: ['google'],
      titles: ['top_addict', 'cup_winner', 'joined'], posts: 0, comments: 0, matchups: 0, builds: 0, created_at: '2026-11-01T00:00:00Z' },
    posts: [], comments: [], edited_builds: [], moderation: [],
  };
  fakeLogin('u-op', { nickname: '영자', role: 'admin', level: 0, main_title: null });
  start('/admin/members/u-a');
  const list = await screen.findByRole('list', { name: '우승자 회원 정보' });
  await waitFor(() => expect(list.textContent).toContain('대표 칭호 티확찢'));
  expect(list.textContent).toContain('얻은 칭호 탑신병자, 티확찢, 참가자');
  const info = screen.getByRole('region', { name: '기본 정보' });
  expect(info.querySelector('.title-badge-art').textContent).toBe('티확찢');
  expect(titleName('unknown_key')).toBe('unknown_key'); // 모르는 키는 목록에서 키 그대로
});
