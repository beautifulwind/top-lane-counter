// 6-88: 방침·약관 판(시행일) 전환 — 2026-12-14판은 그대로, 2026-12-23판은 시행일(한국 0시)부터 현행.
// 시행일 전에는 ?version=2026-12-23으로 미리 보고, 시행일 뒤에는 ?version=2026-12-14로 지난 판을 본다.
import { readFileSync } from 'node:fs';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { AppRoutes } from '../App';
import { LEGAL, kstDate, resolveLegalVersion } from '../lib/legal';
import { fakeFetch } from './fakeDdragon';

const SAVED = { ...LEGAL, revisions: [...LEGAL.revisions] };
const BEFORE = '2026-11-23T03:00:00Z'; // 오늘 (한국 12:00)
const LAST_MOMENT = '2026-12-22T14:59:59Z'; // 한국 12-22 23:59:59 — 아직 12-14판
const FIRST_MOMENT = '2026-12-22T15:00:00Z'; // 한국 12-23 00:00:00 — 새 판 시작
const AFTER = '2026-12-30T03:00:00Z';

beforeEach(() => {
  vi.useFakeTimers({ toFake: ['Date'] });
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); vi.useRealTimers(); Object.assign(LEGAL, SAVED); });

function Where() { const l = useLocation(); return <output data-testid="where">{l.pathname + l.search}</output>; }
const open = async (path, now, heading) => {
  vi.setSystemTime(new Date(now));
  render(<MemoryRouter initialEntries={[path]}><AppRoutes /><Where /></MemoryRouter>);
  await screen.findByRole('heading', { level: 1, name: heading });
  return document.querySelector('article.legal');
};
const PRIVACY = '개인정보처리방침';
const TERMS = '이용약관';
const note = () => screen.queryByRole('note', { name: '판 안내' });
/** 판 안내 상자를 뺀 본문 글 (판 본문이 그대로인지 비교하려고) */
const bodyText = (article) => {
  const copy = article.cloneNode(true);
  copy.querySelector('.legal-version')?.remove();
  return copy.textContent;
};
/** 더 안 쪼개지는 글 덩이(li·p·h2·h3·td·th) 글 목록 — 판끼리 비교하려고 */
const leaves = (article) => [...article.querySelectorAll('li, p, h2, h3, td, th')]
  .filter((el) => !el.closest('.legal-version') && !el.querySelector('li, p, ul, ol, table'))
  .map((el) => el.textContent);
/** 앞 판의 글 덩이 중 새 판에 같은 글이 없는 것 (새 판이 고친 문장만 나와야 한다) */
const changedLeaves = (oldLeaves, newLeaves) => { const set = new Set(newLeaves); return oldLeaves.filter((t) => !set.has(t)); };
const golden = (name) => readFileSync(`src/test/fixtures/legal-2026-12-14-${name}.txt`, 'utf8');
const date = (iso) => new Date(iso).getTime();
// 방침의 첫 판(2026-11-25) = 12-14 약관과 함께 저장해 둔 방침 글 + 「내 챔피언」 4줄 + 시행일 (6-119)
const CHAMPION_LINES = [
  '내 챔피언: 이용자가 [내 챔피언]에서 직접 등록한 챔피언 목록(최대 10개 — 계정 식별 번호, 챔피언, 등록한 시각). 서비스 화면에서는 본인에게만 보이며, 등록을 해제하거나 회원 탈퇴·비회원 계정 정리 때 삭제합니다.',
  '내 챔피언: 이용자가 등록한 챔피언의 빌드만 모아서 보여 주기',
  '내 챔피언: 등록한 챔피언은 해제하면 바로 지우고, 회원 탈퇴·비회원 기록 지우기를 하거나 오래 쓰지 않은 비회원(게스트) 계정이 정리되면 함께 삭제합니다.',
  '내 챔피언에 등록한 챔피언 목록은 서비스 화면에서 본인에게만 표시되며, 다른 이용자에게 공개하지 않습니다.',
];
const squash = (t) => t.replace(/\s+/g, ' ').trim();
// 6-121: 11-25판에 더한 앱 알림 토큰·개인 페이지 (덩이째 더한 것)
const ADDED_1125 = [
  '앱 휴대폰 알림을 켠 경우(iOS·Android 앱): 기기 종류, Apple 또는 Google의 알림 서비스가 앱에 발급한 알림 토큰, 앱 버전, 등록한 시각, 마지막으로 확인한 시각',
  '앱의 알림 토큰은 이용자가 앱에서 알림을 허용하면 만들어지며, 로그인한 상태로 앱을 열 때 다시 확인해 저장합니다.',
  '앱 휴대폰 알림 보내기',
  '개인 페이지: 공개 빌드가 5개 이상인 회원의 공개 빌드와 칭호를 모아 보여 주기',
  '앱 알림 토큰: 앱에서 알림을 끄거나 로그아웃하면 지웁니다(연결이 끊겨 지우지 못하면 남을 수 있습니다). Apple·Google이 더 이상 쓸 수 없는 토큰이라고 알려 오면 지웁니다. 한 계정에 10대까지 저장하며, 넘으면 가장 오래전에 확인한 기기부터 지웁니다. 회원 탈퇴·비회원 기록 지우기·비회원 계정 정리 때 함께 삭제합니다.',
  '개인 페이지: 개인 페이지는 공개 빌드가 5개 미만이 되거나 활동 제한 중이면 닫히며, 탈퇴하면 사라집니다.',
];
const APP_PUSH_ROW = '앱 푸시 서비스: Apple Inc.(Apple 푸시 알림 서비스, APNs), Google LLC(Firebase 클라우드 메시징, FCM) (미국 등)';
// 6-121: 11-25판이 바꾼 문장 [지금, 12-14판]
const MEMBER_PAGE_NEW = '장인이 아닌 회원(비회원·운영자 제외)은 공개 빌드가 5개 이상이면 개인 페이지가 열리며, 닉네임, 대표 칭호와 가진 칭호(비밀 칭호는 대표로 고른 것만), 공개 빌드 목록과 그 수를 로그인하지 않은 사람도 볼 수 있습니다. 이메일·레벨·경험치·가입일은 이 페이지에 보이지 않습니다.';
const REPLACED_1125 = [
  [MEMBER_PAGE_NEW, '장인이 아닌 회원의 공개 프로필은 없습니다.'],
  ['·공지·새 팔로워·댓글)', '·공지·새 팔로워)'],
];
/** 지금 방침(11-25판)에서 11-25판이 더한 덩이를 빼고, 바꾼 문장을 되돌리고, 시행일을 12-14로 바꾸면 저장해 둔 12-14판 글과 같아야 한다 */
const withoutChampion = (article) => {
  const copy = article.cloneNode(true);
  const added = [...CHAMPION_LINES, ...ADDED_1125];
  copy.querySelectorAll('li, p').forEach((el) => { if (added.includes(squash(el.textContent))) el.remove(); });
  copy.querySelectorAll('tr').forEach((tr) => { if (squash(tr.querySelector('th')?.textContent ?? '') === APP_PUSH_ROW) tr.remove(); });
  let text = bodyText(copy);
  for (const [now, old] of REPLACED_1125) {
    expect(text).toContain(now);
    text = text.replace(now, old);
  }
  return text.replaceAll('2026-11-25', '2026-12-14');
};

// 새 판에서 더한 말 (공지 내용)
const NEW_PRIVACY = ['저장한 빌드: 회원이 [저장]한 빌드 목록', '빌드 수정 알림: 빌드가 수정되거나 되돌려지면', '경고·활동 제한 기록: 운영자가 경고하거나 활동을 제한하면'];
const NEW_TERMS = '제7조의2 (경고와 이용 제한)';

test('판 정하기: 시행일(한국 0시)이 지나야 새 판, 그 전에는 12-14판, 첫 판 시행 전(정식 공개 전)에도 첫 판', () => {
  const at = (iso, asked) => resolveLegalVersion(asked, date(iso));
  expect(kstDate(date(LAST_MOMENT))).toBe('2026-12-22');
  expect(kstDate(date(FIRST_MOMENT))).toBe('2026-12-23');
  expect(at(BEFORE).current).toBe('2026-12-14'); // 12-14 전이어도 첫 판 (예전부터 이렇게 보임)
  expect(at('2026-12-14T00:00:00Z').current).toBe('2026-12-14');
  expect(at(LAST_MOMENT).current).toBe('2026-12-14');
  expect(at(FIRST_MOMENT).current).toBe('2026-12-23');
  expect(at(AFTER).current).toBe('2026-12-23');
  expect(at(BEFORE, '2026-12-23')).toMatchObject({ shown: '2026-12-23', current: '2026-12-14', shownIdx: 1, currentIdx: 0 }); // 미리 보기
  expect(at(AFTER, '2026-12-14')).toMatchObject({ shown: '2026-12-14', current: '2026-12-23' }); // 지난 판 보기
  expect(at(BEFORE, '2030-01-01').shown).toBe('2026-12-14'); // 모르는 판은 현행
  expect(at(BEFORE, 'abc').shown).toBe('2026-12-14');
});

test('시행일 전: 개인정보처리방침은 11-25판(저장해 둔 글 + 「내 챔피언」 4줄) + 시행 예정 안내와 미리 보기 링크', async () => {
  const article = await open('/privacy', BEFORE, PRIVACY);
  expect(withoutChampion(article)).toBe(golden('privacy'));
  expect(article.textContent).toContain('시행일: 2026-11-25');
  const box = within(note());
  expect(box.getByText('2026-12-23부터 새 판이 시행됩니다.')).toBeDefined();
  expect(note().textContent).toContain('저장한 빌드, 빌드 수정 알림, 경고·활동 제한 기록을 처리하는 항목에 더했습니다.');
  NEW_PRIVACY.forEach((t) => expect(article.textContent).not.toContain(t));
  expect(box.getByRole('link', { name: '시행 예정 판 미리 보기' })).toHaveAttribute('href', '/privacy?version=2026-12-23');
});

test('시행일 전: 이용약관도 12-14판 그대로 + 시행 예정 안내 (제7조의2 없음)', async () => {
  const article = await open('/terms', BEFORE, TERMS);
  expect(bodyText(article)).toBe(golden('terms'));
  expect(screen.queryByRole('heading', { name: NEW_TERMS })).toBeNull();
  expect(note().textContent).toContain('2026-12-23부터 새 판이 시행됩니다. 운영자의 경고와 활동 제한(제7조의2)을 더했습니다.');
  expect(within(note()).getByRole('link', { name: '시행 예정 판 미리 보기' })).toHaveAttribute('href', '/terms?version=2026-12-23');
});

test('시행일 전 [시행 예정 판 미리 보기]: 새 판 내용과 시행일 2026-12-23, 현행 판으로 돌아가는 링크', async () => {
  const article = await open('/privacy', BEFORE, PRIVACY);
  fireEvent.click(within(note()).getByRole('link', { name: '시행 예정 판 미리 보기' }));
  await screen.findByText(/이 판은 2026-12-23부터 시행됩니다\. 지금은 미리 보는 화면입니다\./);
  expect(screen.getByTestId('where').textContent).toBe('/privacy?version=2026-12-23');
  const now = document.querySelector('article.legal');
  expect(now.textContent).toContain('시행일: 2026-12-23');
  NEW_PRIVACY.forEach((t) => expect(now.textContent).toContain(t));
  expect(note().textContent).toContain('지금 시행 중인 판은 2026-11-25판입니다.');
  fireEvent.click(within(note()).getByRole('link', { name: '지금 시행 중인 판 보기' }));
  await screen.findByText('2026-12-23부터 새 판이 시행됩니다.');
  expect(withoutChampion(document.querySelector('article.legal'))).toBe(golden('privacy'));
  expect(article).toBeDefined();
});

test('방침 새 판 내용: 공지에 올린 세 가지가 의미 그대로 들어가고, 알림 보관 90일·탈퇴 처리와 맞다', async () => {
  const article = await open('/privacy?version=2026-12-23', BEFORE, PRIVACY);
  const t = article.textContent;
  // 1 저장한 빌드
  expect(t).toContain('저장한 빌드: 회원이 [저장]한 빌드 목록(계정 식별 번호, 빌드, 저장한 시각). 저장한 본인만 볼 수 있으며, 회원 탈퇴 또는 빌드 삭제 때 함께 삭제합니다.');
  // 2 빌드 수정 알림
  expect(t).toContain('수정한 회원의 닉네임이 들어간 알림을 보냅니다.');
  expect(t).toContain('운영자, 그 빌드를 처음 만든 회원, 이전에 그 빌드를 고친 회원에게');
  expect(t).toContain('이 닉네임은 빌드의 [수정 기록]에 이미 공개된 정보입니다.');
  expect(t).toContain('알림은 만든 날부터 90일 동안 보관하며, 수정한 회원이 탈퇴하면 알림 속 닉네임은 “탈퇴한 사용자”로 바뀝니다.');
  expect(t).toContain('[계정 설정]의 알림 설정에서 받지 않도록 끌 수 있습니다.');
  expect(t).toContain('사이트 알림(상대법·빌드 처리, 댓글, 레벨·칭호 등)은 만든 날부터 90일이 지나면 자동으로 지웁니다. 빌드 수정 알림도 같습니다.'); // 4번 보관 기간과 같은 90일
  expect(t).toContain('받을 알림 종류 설정(운영진 알림·내 상대법·빌드 다시 공개·팔로우한 장인의 새 빌드·공지·새 팔로워·빌드 수정·댓글)');
  // 3 경고·활동 제한 기록
  expect(t).toContain('그 사유, 기간(시작·끝 시각), 처리한 운영자, 해제한 시각과 메모, 경고를 확인한 시각을 기록합니다.');
  expect(t).toContain('이 기록은 본인과 운영자만 볼 수 있고, 탈퇴하면 바로 삭제합니다.');
  // 탈퇴·공개 범위·권리
  expect(t).toContain('탈퇴하면 바로 삭제: 내가 저장한 빌드 목록');
  expect(t).toContain('경고·활동 제한 기록은 본인과 운영자만 볼 수 있으며, 감독관과 다른 이용자에게는 공개하지 않습니다.');
  // 앞 판의 「내 챔피언」 4줄은 새 판에도 있다
  CHAMPION_LINES.forEach((line) => expect(leaves(article).map(squash)).toContain(line));
  // 앞 판의 글은 새 판에도 그대로 있다: 새 판이 고친 문장은 날짜 2곳 + 알림 종류 설정 + 알림 보관 문단뿐 (나머지는 더하기만)
  const now = leaves(article);
  cleanup();
  const prev = leaves(await open('/privacy?version=2026-11-25', BEFORE, PRIVACY));
  const changed = changedLeaves(prev, now);
  expect(changed.map((c) => c.slice(0, 12)).sort()).toEqual(['시행일: 2026-11', '시행일: 2026-11', '알림: 사이트 알림(상', '휴대폰 알림을 켠 경우']);
  expect(now.length - prev.length).toBe(3 + 3 + 1 + 1 + 1); // 수집 항목 3 + 이용 목적 3 + 탈퇴 삭제 1 + 공개 1 + 권리 1
});

test('약관 새 판: 제7조의2(경고와 이용 제한) 4개 항, 제7조에서 연결, 앞 판 조항은 그대로', async () => {
  const article = await open('/terms?version=2026-12-23', BEFORE, TERMS);
  const sec = screen.getByRole('heading', { name: NEW_TERMS }).closest('section');
  const items = within(sec).getAllByRole('listitem').map((li) => li.textContent);
  expect(items).toHaveLength(4);
  expect(items[0]).toBe('운영자는 이용자가 이 약관이나 운영 정책을 어기면 경고를 하거나, 1일 이상 365일 이하의 기간을 정해 활동을 제한할 수 있습니다. 경고와 활동 제한은 따로 할 수도 있고 함께 할 수도 있습니다.');
  expect(items[1]).toContain('활동이 제한된 동안에는 빌드·상대법의 등록·수정·되돌리기·제안, 추천, 글·댓글 쓰기와 고치기, 신고, 팔로우, 빌드 저장, 장인 신청, 사진·링크 올리기, 닉네임·대표 칭호 바꾸기를 할 수 없습니다.');
  expect(items[1]).toContain('읽기, 로그인, 내 글 지우기, 팔로우 취소, 차단, 알림 설정, 문의, 탈퇴는 그대로 할 수 있습니다.');
  expect(items[2]).toContain('정한 기간이 지나면 제한은 따로 신청하지 않아도 저절로 풀립니다.');
  expect(items[3]).toContain('[문의하기](/inquiries)에서 “이의 제기”를 골라 이의를 제기할 수 있습니다.');
  expect(within(sec).getByRole('link', { name: '/inquiries' })).toHaveAttribute('href', '/inquiries');
  expect(screen.getByRole('heading', { name: '제7조 (운영자의 조치)' }).closest('section').textContent).toContain('경고와 활동 제한은 제7조의2에 따릅니다.');
  // 제7조 바로 뒤, 제8조 앞
  const heads = [...article.querySelectorAll('h2')].map((h) => h.textContent);
  expect(heads.indexOf(NEW_TERMS)).toBe(heads.indexOf('제7조 (운영자의 조치)') + 1);
  expect(article.textContent).toContain('시행일: 2026-12-23');
  // 앞 판 조항은 새 판에도 그대로: 고친 문장은 날짜 2곳 + 제7조 끝 항(제7조의2 연결)뿐
  const now = leaves(article);
  cleanup();
  const prev = leaves(await open('/terms?version=2026-12-14', BEFORE, TERMS));
  expect(changedLeaves(prev, now).map((c) => c.slice(0, 12)).sort()).toEqual(['시행일: 2026-12', '시행일: 2026-12', '제6조를 어기면 운영자']);
  expect(now.length - prev.length).toBe(1 + 4); // 제7조의2 제목 1 + 항 4
});


test('시행일(한국 0시) 직전까지 앞 판 + 시행 예정 안내, 0시부터 새 판이 현행(안내 상자 없음)', async () => {
  const last = await open('/privacy', LAST_MOMENT, PRIVACY);
  expect(withoutChampion(last)).toBe(golden('privacy'));
  expect(note().textContent).toContain('2026-12-23부터 새 판이 시행됩니다.');
  cleanup();
  const first = await open('/privacy', FIRST_MOMENT, PRIVACY);
  NEW_PRIVACY.forEach((t) => expect(first.textContent).toContain(t));
  expect(first.textContent).toContain('시행일: 2026-12-23');
  expect(note()).toBeNull(); // 더 새 판이 없고 현행이면 안내 상자 없음
});

test('시행일 뒤: 새 판이 현행(안내 상자 없이 새 내용), ?version=2026-12-14로 지난 판을 볼 수 있다 (그대로, 지난 판 표시)', async () => {
  const cur = await open('/terms', AFTER, TERMS);
  expect(screen.getByRole('heading', { name: NEW_TERMS })).toBeDefined();
  expect(cur.textContent).toContain('시행일: 2026-12-23');
  expect(note()).toBeNull(); // 더 새 판이 없고 현행이면 안내 상자 없음
  cleanup();
  const old = await open('/terms?version=2026-12-14', AFTER, TERMS);
  expect(bodyText(old)).toBe(golden('terms'));
  expect(note().textContent).toContain('이 판은 지난 판(2026-12-14판)입니다.');
  expect(note().textContent).toContain('지금은 2026-12-23판이 시행 중입니다.');
  expect(within(note()).getByRole('link', { name: '지금 시행 중인 판 보기' })).toHaveAttribute('href', '/terms');
});

test('시행일 뒤 방침: 새 내용이 기본, 지난 판은 ?version=2026-11-25', async () => {
  const cur = await open('/privacy', AFTER, PRIVACY);
  NEW_PRIVACY.forEach((t) => expect(cur.textContent).toContain(t));
  expect(cur.textContent).toContain('시행일: 2026-12-23');
  expect(note()).toBeNull();
  cleanup();
  const old = await open('/privacy?version=2026-11-25', AFTER, PRIVACY);
  expect(withoutChampion(old)).toBe(golden('privacy'));
});

test('판이 하나뿐이면 안내 상자가 없고, 첫 판 시행일이 비면 노란 칸', async () => {
  LEGAL.revisions = [];
  const one = await open('/privacy', BEFORE, PRIVACY);
  expect(note()).toBeNull();
  expect(withoutChampion(one)).toBe(golden('privacy'));
  cleanup();
  LEGAL.revisions = ['2026-12-23'];
  LEGAL.effectiveDate = null;
  LEGAL.privacyEffectiveDate = null;
  await open('/terms', BEFORE, TERMS);
  expect(screen.getAllByText('【채워 주세요: 시행일】').length).toBe(2);
});

test('약관 제12조(약관의 변경) 문장은 새 판에서도 그대로', async () => {
  const article = await open('/terms?version=2026-12-23', BEFORE, TERMS);
  expect(article.textContent).toContain('약관을 바꾸면 시행 7일 전부터 이 페이지에 알립니다. 이용자에게 불리한 변경은 시행 30일 전부터 알립니다.');
});

// 6-119: 방침의 첫 판 2026-11-25 — 「내 챔피언」 고지가 오늘부터 시행, 약관은 12-14 그대로
test('오늘(2026-11-25) 방침: 시행일 11-25, 「내 챔피언」 4줄이 현행 판에 있고, 안내 상자는 12-23판만. 약관에는 영향 없음', async () => {
  const today = '2026-11-25T03:00:00Z';
  const article = await open('/privacy', today, PRIVACY);
  const lines = leaves(article).map(squash);
  CHAMPION_LINES.forEach((line) => expect(lines).toContain(line));
  expect(article.textContent).toContain('시행일: 2026-11-25');
  expect(article.textContent).not.toContain('2026-12-25');
  expect(note().textContent).toContain('2026-12-23부터 새 판이 시행됩니다.');
  expect(note().textContent).not.toContain('내 챔피언');
  expect(resolveLegalVersion(null, date(today), 'privacy')).toMatchObject({ versions: ['2026-11-25', '2026-12-23'], current: '2026-11-25' });
  expect(resolveLegalVersion(null, date(today)).versions).toEqual(['2026-12-14', '2026-12-23']);
  cleanup();
  const terms = await open('/terms', today, TERMS);
  expect(bodyText(terms)).toBe(golden('terms'));
});

// 6-121: 11-25판에 바로 넣은 앱 알림 토큰(1·2·3·4·6번)·댓글 알림 설정·개인 페이지(3·4·5번)
test('방침 11-25판: 앱 알림 토큰·댓글 설정·개인 페이지 문구, 위탁 표에 앱 푸시(제목·내용이 Apple·Google에 전달), 시행일 그대로', async () => {
  const article = await open('/privacy', '2026-11-25T03:00:00Z', PRIVACY);
  const lines = leaves(article).map(squash);
  ADDED_1125.forEach((line) => expect(lines).toContain(line));
  const t = squash(article.textContent);
  expect(t).toContain(MEMBER_PAGE_NEW);
  expect(t).not.toContain('장인이 아닌 회원의 공개 프로필은 없습니다');
  expect(t).toContain('공지·새 팔로워·댓글)');
  expect(article.textContent).toContain('시행일: 2026-11-25');
  const row = [...article.querySelectorAll('tr')].find((tr) => squash(tr.querySelector('th')?.textContent ?? '') === APP_PUSH_ROW);
  expect(squash(row.textContent)).toContain('알림 제목과 내용');
  expect(squash(row.textContent)).toContain('Apple·Google이 제목과 내용을 받아 처리합니다');
  expect(squash(row.textContent)).not.toContain('볼 수 없습니다');
  // 개인 페이지 문구에 사진은 없다 (일반 사용자는 사진을 올릴 수 없음)
  expect(MEMBER_PAGE_NEW).not.toContain('사진');
});
