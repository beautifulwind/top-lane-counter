// 6-88·6-123: 방침·약관은 2026-11-25판 하나. 본문은 저장해 둔 글과 같아야 하고(뜻하지 않은 문구 변경 방지),
// 판(시행일) 전환 장치는 다음 개정판을 위해 가짜 날짜(2027-01-01)로 계속 검사한다.
import { readFileSync } from 'node:fs';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { AppRoutes } from '../App';
import { LegalVersionProvider, Since } from '../components/LegalVersion';
import { LEGAL, kstDate, resolveLegalVersion } from '../lib/legal';
import { fakeFetch } from './fakeDdragon';

const SAVED = { ...LEGAL, revisions: [...LEGAL.revisions] };
const FIRST = '2026-11-25';
const NEXT = '2027-01-01'; // 검사용 가짜 개정판
const TODAY = '2026-11-25T03:00:00Z'; // 한국 12:00
const LAST_MOMENT = '2026-12-31T14:59:59Z'; // 한국 12-31 23:59:59
const FIRST_MOMENT = '2026-12-31T15:00:00Z'; // 한국 01-01 00:00:00

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
const squash = (t) => t.replace(/\s+/g, ' ').trim();
/** 더 안 쪼개지는 글 덩이(li·p·h2·h3·td·th) 글 목록 */
const leaves = (article) => [...article.querySelectorAll('li, p, h2, h3, td, th')]
  .filter((el) => !el.closest('.legal-version') && !el.querySelector('li, p, ul, ol, table'))
  .map((el) => squash(el.textContent));
const golden = (name) => readFileSync(`src/test/fixtures/legal-${FIRST}-${name}.txt`, 'utf8');
const date = (iso) => new Date(iso).getTime();

test('판은 방침·약관 모두 2026-11-25 하나', () => {
  expect(resolveLegalVersion(null, date(TODAY), 'privacy')).toMatchObject({ versions: [FIRST], current: FIRST });
  expect(resolveLegalVersion(null, date(TODAY))).toMatchObject({ versions: [FIRST], current: FIRST });
});

test.each([['/privacy', 'privacy', PRIVACY], ['/terms', 'terms', TERMS]])('%s: 저장해 둔 11-25판 글 그대로, 안내 상자 없음', async (path, name, heading) => {
  const article = await open(path, TODAY, heading);
  expect(article.textContent).toBe(golden(name));
  expect(article.textContent).toContain(`시행일: ${FIRST}`);
  expect(note()).toBeNull();
});

test.each([`/privacy?version=2026-12-23`, `/privacy?version=2026-12-14`])('없어진 판 주소(%s)는 현행 판', async (path) => {
  const article = await open(path, TODAY, PRIVACY);
  expect(article.textContent).toBe(golden('privacy'));
  expect(note()).toBeNull();
});

test('방침: 저장한 빌드·빌드 수정 알림·경고 기록·내 챔피언·앱 알림 토큰·개인 페이지', async () => {
  const article = await open('/privacy', TODAY, PRIVACY);
  const t = squash(article.textContent);
  [
    '저장한 빌드: 이용자(비회원 포함)가 [저장]한 빌드 목록(계정 식별 번호, 빌드, 저장한 시각).',
    '저장을 해제하거나 회원 탈퇴·비회원 계정 정리·빌드 삭제 때 함께 삭제합니다.',
    '수정한 회원의 닉네임이 들어간 알림을 보냅니다.',
    '알림은 만든 날부터 90일 동안 보관하며, 수정한 회원이 탈퇴하면 알림 속 닉네임은 “탈퇴한 사용자”로 바뀝니다.',
    '빌드 수정 알림도 같습니다.',
    '경고 알림을 읽은 시각과 경고를 확인한 시각을 기록합니다.',
    '이 기록은 본인과 운영자만 볼 수 있고, 탈퇴하면 바로 삭제합니다.',
    '탈퇴하면 바로 삭제: 내가 저장한 빌드 목록',
    '공지·새 팔로워·빌드 수정·댓글)',
    '내 챔피언: 이용자가 [내 챔피언]에서 직접 등록한 챔피언 목록(최대 10개',
    '앱의 알림 토큰은 이용자가 앱에서 알림을 허용하면 만들어지며',
    '장인이 아닌 회원(비회원·운영자 제외)은 공개 빌드가 5개 이상이면 개인 페이지가 열리며',
  ].forEach((line) => expect(t).toContain(line));
  expect(t).not.toContain('장인이 아닌 회원의 공개 프로필은 없습니다');
  const row = [...article.querySelectorAll('tr')].find((tr) => squash(tr.querySelector('th')?.textContent ?? '').startsWith('앱 푸시 서비스'));
  expect(squash(row.textContent)).toContain('Apple·Google이 제목과 내용을 받아 처리합니다');
});

test('방침: 게임 그림을 Riot 서버에서 바로 불러와 접속 정보가 전달될 수 있다는 한 문장', async () => {
  const article = await open('/privacy', TODAY, PRIVACY);
  expect(leaves(article)).toContain('챔피언·아이템·룬 그림 등 게임 자료는 Riot Games 서버에서 바로 불러오며, 이 과정에서 IP 주소·브라우저 정보 같은 접속 정보가 Riot 서버로 전달될 수 있습니다.');
});

test('약관: 제7조의2 4개 항(제한 중 할 수 있는 일·없는 일), 제7조에서 연결, 유지 칭호', async () => {
  const article = await open('/terms', TODAY, TERMS);
  const heading = screen.getByRole('heading', { name: '제7조의2 (경고와 이용 제한)' });
  const items = within(heading.closest('section')).getAllByRole('listitem').map((li) => squash(li.textContent));
  expect(items).toHaveLength(4);
  expect(items[1]).toBe('활동이 제한된 동안에는 빌드·상대법의 등록·수정·되돌리기·제안, 추천, 글·댓글 쓰기와 고치기, 신고, 팔로우, 빌드 저장, 내 챔피언 등록, 장인 신청, 사진·링크 올리기, 닉네임·대표 칭호 바꾸기를 할 수 없습니다. 읽기, 로그인, 내 글 지우기, 팔로우 취소, 빌드 저장 해제, 내 챔피언 해제, 내 사진 지우기, 장인 신청 취소, 차단, 알림 설정, 문의, 탈퇴는 그대로 할 수 있습니다.');
  const heads = [...article.querySelectorAll('h2')];
  expect(heads.indexOf(heading)).toBe(heads.findIndex((h) => h.textContent === '제7조 (운영자의 조치)') + 1);
  expect(squash(article.textContent)).toContain('경고와 활동 제한은 제7조의2에 따릅니다.');
  expect(squash(article.textContent)).toContain('「한 번 얻으면 유지」라고 적힌 칭호는 조건이 더 이상 맞지 않아도 회수하지 않습니다(부정한 방법으로 얻은 경우는 제외합니다).');
  expect(squash(article.textContent)).toContain('약관을 바꾸면 시행 7일 전부터 이 페이지에 알립니다. 이용자에게 불리한 변경은 시행 30일 전부터 알립니다.');
});

test('다음 개정판이 생기면: 시행일(한국 0시) 전에는 앞 판, 0시부터 새 판, ?version=으로 오간다', () => {
  LEGAL.revisions = [NEXT];
  const at = (iso, asked) => resolveLegalVersion(asked, date(iso));
  expect(kstDate(date(LAST_MOMENT))).toBe('2026-12-31');
  expect(kstDate(date(FIRST_MOMENT))).toBe(NEXT);
  expect(at('2026-11-20T00:00:00Z').current).toBe(FIRST); // 첫 판 전이어도 첫 판
  expect(at(LAST_MOMENT).current).toBe(FIRST);
  expect(at(FIRST_MOMENT).current).toBe(NEXT);
  expect(at(TODAY, NEXT)).toMatchObject({ shown: NEXT, current: FIRST, shownIdx: 1, currentIdx: 0 });
  expect(at(FIRST_MOMENT, FIRST)).toMatchObject({ shown: FIRST, current: NEXT });
  expect(at(TODAY, 'abc').shown).toBe(FIRST);
});

test('다음 개정판이 생기면: 시행 예정 안내 → 미리 보기 → 현행 판으로, 시행 뒤 지난 판 표시', async () => {
  LEGAL.revisions = [NEXT];
  await open('/terms', TODAY, TERMS);
  expect(note().textContent).toContain(`${NEXT}부터 새 판이 시행됩니다.`);
  fireEvent.click(within(note()).getByRole('link', { name: '시행 예정 판 미리 보기' }));
  await screen.findByText(`이 판은 ${NEXT}부터 시행됩니다. 지금은 미리 보는 화면입니다.`);
  expect(screen.getByTestId('where').textContent).toBe(`/terms?version=${NEXT}`);
  fireEvent.click(within(note()).getByRole('link', { name: '지금 시행 중인 판 보기' }));
  await screen.findByText(`${NEXT}부터 새 판이 시행됩니다.`);
  cleanup();
  await open(`/terms?version=${FIRST}`, FIRST_MOMENT, TERMS);
  expect(note().textContent).toContain(`이 판은 지난 판(${FIRST}판)입니다.`);
});

test('Since: 그 판부터 보이고 앞 판에서는 안 보인다', () => {
  const versions = [FIRST, NEXT];
  const show = (shownIdx) => {
    render(<LegalVersionProvider value={{ versions, shownIdx }}><Since v={NEXT}>새 문장</Since></LegalVersionProvider>);
    const seen = screen.queryByText('새 문장') !== null;
    cleanup();
    return seen;
  };
  expect(show(0)).toBe(false);
  expect(show(1)).toBe(true);
});

test('첫 판 시행일이 비면 안내 상자 없이 노란 칸', async () => {
  LEGAL.effectiveDate = null;
  await open('/terms', TODAY, TERMS);
  expect(note()).toBeNull();
  expect(screen.getAllByText('【채워 주세요: 시행일】').length).toBe(2);
});
