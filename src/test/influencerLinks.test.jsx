// 장인 3a 화면 (047, SPEC 6-34): 링크 관리 /me/links · 빌드 링크 칸 · 외부 링크 표시와 이동 확인 창 · 공개 프로필 /u/:id · 닉네임 → 프로필
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import UserName from '../components/UserName';
import ExternalLink from '../components/ExternalLink';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeLogin, fakeState } from './fakeSupabase';
import { LEAVE_TEXT, LINK_REL, linkProblem, siteName } from '../lib/links';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /></MemoryRouter>);
const MATCHUP = '/champion/Darius/counter/Quinn';
const rpcCalls = (name) => fakeState.rpcCalls.filter((c) => c.name === name).map((c) => c.args);
const DOMAINS = () => TABLES.link_domains;

/** 빌드 102(탑고수, 추천 5 — 처음 고르는 빌드)를 만든 분을 장인으로, 그 계정으로 로그인 */
function asInfluencer() {
  const b = TABLES.builds.find((x) => x.id === 102);
  b.author = { ...b.author, influencer: 'creator' };
  fakeLogin('u-102', { nickname: '탑고수', level: 7, main_title: null, influencer: 'creator', influencer_at: '2026-11-12T00:00:00Z' });
  return b;
}
const addLink = (owner, url, extra = {}) => {
  const host = url.slice(8).split(/[/?#]/)[0];
  const row = { id: 500 + TABLES.ext_links.length, owner_id: owner, build_id: null, url, host, sort: TABLES.ext_links.length, ...extra };
  TABLES.ext_links.push(row);
  return row;
};

// ---------------- 주소 검사 (DB와 같은 기준, 쉬운 말) ----------------

test('주소 검사: 안 되는 이유를 쉬운 말로', () => {
  const d = DOMAINS();
  expect(linkProblem('https://www.youtube.com/@faker', d)).toBeNull();
  expect(linkProblem('https://youtu.be/abc?t=3', d)).toBeNull();
  expect(linkProblem('http://youtube.com/@a', d)).toMatch(/https:\/\/로 바꿔/);
  expect(linkProblem('youtube.com/@a', d)).toMatch(/https:\/\/로 시작하는 주소/);
  expect(linkProblem('https://youtube.com/@장인', d)).toMatch(/쓸 수 없는 글자/);
  expect(linkProblem('https://youtube.com/@a b', d)).toMatch(/쓸 수 없는 글자/);
  expect(linkProblem(`https://youtube.com/@a${String.fromCharCode(0x200B)}`, d)).toMatch(/쓸 수 없는 글자/);
  expect(linkProblem('https://youtube.com@evil.com/', d)).toMatch(/계정 정보/);
  expect(linkProblem('https://youtube.com:8080/', d)).toMatch(/포트/);
  expect(linkProblem('https://bit.ly/abc', d)).toMatch(/허용된 사이트\(숲·치지직·인스타그램·트위치·X·유튜브\)의 주소만/);
  expect(linkProblem('https://youtube.com.evil.com/', d)).toMatch(/허용된 사이트/);
  expect(linkProblem('https://l.instagram.com/?u=x', d)).toMatch(/단축.*우회 주소/);
  expect(linkProblem('https://www.youtube.com/redirect?q=x', d)).toMatch(/단축.*우회 주소/);
  expect(linkProblem('https://www.youtube.com/watch?next=https%3A%2F%2Fevil.com', d)).toMatch(/단축.*우회 주소/);
  expect(linkProblem('https://a%zz.youtube.com', d)).toMatch(/쓸 수 없는 글자/);
});

test('사이트 이름: 하위 주소도 같은 이름', () => {
  expect(siteName('www.youtube.com')).toBe('유튜브');
  expect(siteName('youtu.be')).toBe('유튜브');
  expect(siteName('chzzk.naver.com')).toBe('치지직');
  expect(siteName('m.twitch.tv')).toBe('트위치');
  expect(siteName('play.sooplive.co.kr')).toBe('숲');
  expect(siteName('example.com', [{ domain: 'example.com', label: '예시 (설명)' }])).toBe('예시');
});

// ---------------- 외부 링크 + 이동 확인 창 ----------------

test('외부 링크: 새 창 + rel, 누르면 바로 가지 않고 확인 창(주소·[이동]·[취소]), [취소]에 초점', () => {
  const link = { id: 1, url: 'https://www.youtube.com/@faker', host: 'www.youtube.com' };
  render(<MemoryRouter><ExternalLink link={link} /></MemoryRouter>);
  const a = screen.getByRole('link', { name: /유튜브/ });
  expect(a.getAttribute('target')).toBe('_blank');
  expect(a.getAttribute('rel')).toBe(LINK_REL);
  expect(LINK_REL).toBe('noopener noreferrer nofollow ugc');
  expect(a.getAttribute('href')).toBe(link.url);
  expect(a.textContent).toContain('youtube.com/@faker');

  const notPrevented = fireEvent.click(a);
  expect(notPrevented).toBe(false); // 바로 이동하지 않는다
  const dialog = screen.getByRole('alertdialog');
  expect(LEAVE_TEXT).toBe('탑신병자를 떠나 외부 사이트로 이동합니다. 주소를 확인하세요.');
  expect(within(dialog).getByText(LEAVE_TEXT)).toBeTruthy();
  expect(within(dialog).getByText(link.url)).toBeTruthy();
  const go = within(dialog).getByRole('link', { name: '이동' });
  expect(go.getAttribute('href')).toBe(link.url);
  expect(go.getAttribute('rel')).toBe(LINK_REL);
  expect(go.getAttribute('target')).toBe('_blank');
  expect(document.activeElement).toBe(within(dialog).getByRole('button', { name: '취소' }));
  fireEvent.keyDown(dialog, { key: 'Escape' });
  expect(screen.queryByRole('alertdialog')).toBeNull();
  expect(document.activeElement).toBe(a);

  fireEvent.click(a);
  fireEvent.click(screen.getByRole('link', { name: '이동' }));
  expect(screen.queryByRole('alertdialog')).toBeNull();
});

// ---------------- 닉네임 → 공개 프로필 ----------------

test('장인 닉네임: linkTo를 준 자리에서만 공개 프로필 링크 (장인이 아니면 링크 없음)', () => {
  const inf = render(<MemoryRouter><UserName profile={{ nickname: '페이커', level: 7, influencer: 'pro' }} linkTo="u-9" /></MemoryRouter>);
  const a = inf.container.querySelector('a.inf-link');
  expect(a.getAttribute('href')).toBe('/u/u-9');
  expect(a.querySelector('.inf-tag').textContent).toBe('장인');
  cleanup();
  const plain = render(<MemoryRouter><UserName profile={{ nickname: '페이커', level: 7, influencer: 'pro' }} /></MemoryRouter>);
  expect(plain.container.querySelector('a')).toBeNull(); // 줄 전체가 링크인 자리(회원 목록 등)는 그대로
  cleanup();
  const user = render(<MemoryRouter><UserName profile={{ nickname: '보통', level: 1 }} linkTo="u-1" /></MemoryRouter>);
  expect(user.container.querySelector('a')).toBeNull();
});

test('빌드 작성자가 장인이면 닉네임을 눌러 공개 프로필로 간다', async () => {
  const b = TABLES.builds.find((x) => x.id === 102);
  b.author = { ...b.author, influencer: 'creator' };
  TABLES.profiles.push({ id: 'u-102', nickname: '탑고수', role: 'user', level: 7, main_title: null, influencer: 'creator' });
  start(MATCHUP);
  await screen.findByText(/퀸으로 다리우스 이기는 법/);
  const author = document.querySelector('.build-author a.inf-link');
  expect(author.getAttribute('href')).toBe('/u/u-102');
  fireEvent.click(author);
  expect(await screen.findByRole('heading', { level: 1 })).toHaveProperty('textContent', expect.stringContaining('탑고수'));
  expect(screen.getByText('인증된 크리에이터')).toBeTruthy();
});

// ---------------- 공개 프로필 ----------------

test('공개 프로필: 닉네임·장인 표시·링크·최근 빌드(빌드 링크 포함), 개인정보 없음', async () => {
  TABLES.profiles.push({ id: 'u-102', nickname: '탑고수', role: 'user', level: 7, main_title: null, influencer: 'pro', email: 'secret@x.com' });
  addLink('u-102', 'https://www.youtube.com/@toptop');
  addLink('u-102', 'https://chzzk.naver.com/live/toptop');
  addLink('u-102', 'https://youtu.be/build102', { build_id: 102 });
  start('/u/u-102');
  const h1 = await screen.findByRole('heading', { level: 1 });
  expect(h1.querySelector('.inf-tag').textContent).toBe('장인');
  expect(h1.textContent).toContain('탑고수');
  expect(screen.getByText('인증된 프로게이머')).toBeTruthy();
  const linkList = screen.getByRole('heading', { name: '링크' }).closest('section');
  expect(within(linkList).getAllByRole('link').map((a) => a.textContent.replace(/\s*\(외부 사이트, 새 창\)$/, '')))
    .toEqual(['유튜브 youtube.com/@toptop', '치지직 chzzk.naver.com/live/toptop']);
  expect(within(linkList).getByText(/탑신병자가 내용을 보증하지 않습니다/)).toBeTruthy();
  const builds = screen.getByRole('heading', { name: '처음 만든 빌드' }).closest('section');
  const go = within(builds).getByRole('link', { name: /퀸으로 다리우스 · 빌드 2/ });
  expect(go.getAttribute('href')).toBe('/champion/Darius/counter/Quinn?build=102');
  expect(within(builds).getByRole('link', { name: /youtu\.be\/build102/ })).toBeTruthy();
  expect(document.body.textContent).not.toContain('secret@x.com');
  expect(document.body.textContent).not.toMatch(/Lv\.7/);
  expect(document.title).toBe('탑고수 프로필 - 탑신병자');
});

test('공개 프로필: 장인이 아니거나 없는 id는 같은 "없는 페이지"', async () => {
  start('/u/u-old'); // 장인이 아닌 회원
  expect(await screen.findByText('문서를 찾을 수 없습니다')).toBeTruthy();
  const a = document.querySelector('main')?.textContent ?? document.body.textContent;
  cleanup();
  start('/u/nobody');
  expect(await screen.findByText('문서를 찾을 수 없습니다')).toBeTruthy();
  expect(document.querySelector('main')?.textContent ?? document.body.textContent).toBe(a);
});

// ---------------- 링크 관리 /me/links ----------------

test('링크 관리: 장인이 아니면 안내만 (마이페이지에도 버튼 없음)', async () => {
  fakeLogin('u-old', { nickname: '기존유저' });
  start('/me/links');
  expect(await screen.findByText(/인증된 장인/)).toBeTruthy();
  expect(screen.queryByRole('button', { name: '저장' })).toBeNull();
  cleanup();
  start('/me');
  await screen.findByRole('heading', { level: 1 });
  expect(screen.queryByRole('link', { name: /링크 관리/ })).toBeNull();
});

test('링크 관리: 허용 사이트 안내, 칸별 이유, 순서 바꾸기, 저장, 5개 제한', async () => {
  asInfluencer();
  start('/me');
  const manage = await screen.findByRole('link', { name: /링크 관리/ });
  expect(screen.getByRole('link', { name: '내 공개 프로필' }).getAttribute('href')).toBe('/u/u-102');
  fireEvent.click(manage);
  await screen.findByRole('heading', { name: '장인 링크 관리' });
  const sites = screen.getByRole('list', { name: '올릴 수 있는 사이트' });
  expect(within(sites).getAllByRole('listitem').map((li) => li.textContent)).toEqual(['숲', '치지직', '인스타그램', '트위치', 'X', '유튜브']);
  expect(screen.getByText('아직 올린 링크가 없습니다.')).toBeTruthy();

  fireEvent.click(screen.getByRole('button', { name: '+ 링크 추가' }));
  fireEvent.click(screen.getByRole('button', { name: '+ 링크 추가' }));
  fireEvent.change(screen.getByLabelText('링크 1'), { target: { value: 'http://youtube.com/@toptop' } });
  fireEvent.change(screen.getByLabelText('링크 2'), { target: { value: 'https://bit.ly/x' } });
  fireEvent.click(screen.getByRole('button', { name: '저장' }));
  expect(screen.getByText(/https:\/\/로 바꿔 보세요/)).toBeTruthy();
  expect(screen.getByText(/허용된 사이트\(.*\)의 주소만/)).toBeTruthy();
  expect(screen.getByLabelText('링크 1').getAttribute('aria-invalid')).toBe('true');
  expect(rpcCalls('set_profile_links')).toEqual([]);

  fireEvent.change(screen.getByLabelText('링크 1'), { target: { value: 'https://www.youtube.com/@toptop' } });
  fireEvent.change(screen.getByLabelText('링크 2'), { target: { value: 'https://twitch.tv/toptop' } });
  fireEvent.click(screen.getByRole('button', { name: '링크 2 위로' }));
  fireEvent.click(screen.getByRole('button', { name: '저장' }));
  await screen.findByText('저장했습니다.');
  expect(rpcCalls('set_profile_links')).toEqual([{ p_urls: ['https://twitch.tv/toptop', 'https://www.youtube.com/@toptop'] }]);
  expect(TABLES.ext_links.map((l) => [l.url, l.sort])).toEqual([['https://twitch.tv/toptop', 0], ['https://www.youtube.com/@toptop', 1]]);

  for (let i = 0; i < 3; i += 1) fireEvent.click(await screen.findByRole('button', { name: '+ 링크 추가' }));
  expect(screen.getByRole('button', { name: '+ 링크 추가' }).disabled).toBe(true);
  expect(screen.getByText('프로필 링크는 5개까지 올릴 수 있습니다.')).toBeTruthy();
});

test('링크 관리: DB가 거부한 이유를 그대로, 지우기 뒤 저장하면 빈 목록', async () => {
  asInfluencer();
  addLink('u-102', 'https://x.com/toptop');
  start('/me/links');
  await screen.findByRole('heading', { name: '장인 링크 관리' });
  expect(screen.getByLabelText('링크 1').value).toBe('https://x.com/toptop');
  fakeState.rpcError = '같은 주소를 두 번 올릴 수 없습니다.';
  fakeState.rpcErrorCode = '23514';
  fireEvent.click(screen.getByRole('button', { name: '저장' }));
  expect(await screen.findByText('같은 주소를 두 번 올릴 수 없습니다.')).toBeTruthy();
  fakeState.rpcError = null;
  fireEvent.click(screen.getByRole('button', { name: '링크 1 지우기' }));
  fireEvent.click(screen.getByRole('button', { name: '저장' }));
  await screen.findByText('저장했습니다.');
  expect(rpcCalls('set_profile_links').at(-1)).toEqual({ p_urls: [] });
  expect(TABLES.ext_links).toEqual([]);
});

test('링크 관리: 허용 사이트에서 빠진 링크는 "보이지 않습니다" 안내', async () => {
  asInfluencer();
  addLink('u-102', 'https://twitch.tv/toptop');
  TABLES.link_domains = TABLES.link_domains.filter((d) => d.domain !== 'twitch.tv');
  start('/me/links');
  expect(await screen.findByText(/지금은 다른 사람에게 보이지 않습니다/)).toBeTruthy();
});

// ---------------- 빌드 링크 ----------------

test('빌드 링크: 처음 만든 장인에게만 "장인 링크" 칸, [빌드 수정]과 따로', async () => {
  asInfluencer();
  start(MATCHUP);
  await screen.findByText(/퀸으로 다리우스 이기는 법/);
  const box = screen.getByRole('heading', { name: /장인 링크/, level: 3 }).closest('section');
  expect(box.className).toBe('build-link-box');
  expect(within(box).queryByRole('link', { name: '빌드 수정' })).toBeNull();
  expect(screen.getByRole('link', { name: '빌드 수정' }).closest('.build-link-box')).toBeNull();

  // 다른 빌드(작성자가 다른 분)를 고르면 칸이 없다
  fireEvent.click(screen.getByRole('tab', { name: /^빌드 3/ }));
  expect(screen.queryByRole('heading', { name: /장인 링크/, level: 3 })).toBeNull();
});

test('빌드 링크: 장인이 아니면(내 빌드라도) 칸이 없다, 다른 장인에게도 없다', async () => {
  fakeLogin('u-102', { nickname: '탑고수', level: 7, main_title: null }); // 장인 아님
  start(MATCHUP);
  await screen.findByText(/퀸으로 다리우스 이기는 법/);
  expect(screen.queryByRole('heading', { name: /장인 링크/, level: 3 })).toBeNull();
  cleanup();
  fakeLogin('u-other', { nickname: '다른장인', influencer: 'pro' });
  start(MATCHUP);
  await screen.findByText(/퀸으로 다리우스 이기는 법/);
  expect(screen.queryByRole('heading', { name: /장인 링크/, level: 3 })).toBeNull();
});

test('빌드 링크: 달기 → 제목 아래 표시(누구에게나) → 고치기 → 지우기', async () => {
  const b = asInfluencer();
  const version = b.version;
  start(MATCHUP);
  await screen.findByText(/퀸으로 다리우스 이기는 법/);
  fireEvent.click(screen.getByRole('button', { name: '링크 달기' }));
  fireEvent.change(screen.getByLabelText('링크 주소'), { target: { value: 'http://youtu.be/abc' } });
  fireEvent.click(screen.getByRole('button', { name: '저장' }));
  expect(screen.getByText(/https:\/\/로 바꿔/)).toBeTruthy(); // 화면이 먼저 알려 줌
  expect(rpcCalls('set_build_link')).toEqual([]);
  fireEvent.change(screen.getByLabelText('링크 주소'), { target: { value: 'https://bit.ly/abc' } });
  fireEvent.click(screen.getByRole('button', { name: '저장' }));
  expect(await screen.findByText(/허용된 사이트/)).toBeTruthy(); // 허용 사이트는 DB가 판단해 알려 줌
  fireEvent.change(screen.getByLabelText('링크 주소'), { target: { value: 'https://youtu.be/abc' } });
  fireEvent.click(screen.getByRole('button', { name: '저장' }));
  expect(await screen.findByText('빌드 링크를 달았습니다.')).toBeTruthy();
  expect(rpcCalls('set_build_link').at(-1)).toEqual({ p_build: 102, p_url: 'https://youtu.be/abc' });
  const shown = await screen.findByText('장인 링크', { selector: '.build-link-row .muted' });
  expect(within(shown.parentElement).getByRole('link').getAttribute('href')).toBe('https://youtu.be/abc');
  expect(b.version).toBe(version); // 빌드 내용(버전)은 그대로

  fireEvent.click(screen.getByRole('button', { name: '링크 고치기' }));
  expect(screen.getByLabelText('링크 주소').value).toBe('https://youtu.be/abc');
  fireEvent.change(screen.getByLabelText('링크 주소'), { target: { value: 'https://youtu.be/xyz' } });
  fireEvent.click(screen.getByRole('button', { name: '저장' }));
  expect(await screen.findByText('빌드 링크를 고쳤습니다.')).toBeTruthy();

  fireEvent.click(screen.getByRole('button', { name: '링크 지우기' }));
  fireEvent.click(screen.getByRole('button', { name: '지우기' }));
  expect(await screen.findByText('빌드 링크를 지웠습니다.')).toBeTruthy();
  expect(rpcCalls('set_build_link').at(-1)).toEqual({ p_build: 102, p_url: null });
  await waitFor(() => expect(document.querySelector('.build-panel > .build-link-row')).toBeNull());
});

test('빌드 링크: 로그인하지 않은 사람에게도 표시만 된다 (칸은 없음)', async () => {
  const b = TABLES.builds.find((x) => x.id === 102);
  b.author = { ...b.author, influencer: 'creator' };
  TABLES.profiles.push({ id: 'u-102', nickname: '탑고수', role: 'user', level: 7, main_title: null, influencer: 'creator' });
  addLink('u-102', 'https://youtu.be/abc', { build_id: 102 });
  start(MATCHUP);
  await screen.findByText(/퀸으로 다리우스 이기는 법/);
  const row = document.querySelector('.build-panel > .build-link-row');
  expect(within(row).getByRole('link').getAttribute('rel')).toBe(LINK_REL);
  expect(screen.queryByRole('heading', { name: /장인 링크/, level: 3 })).toBeNull();
});
