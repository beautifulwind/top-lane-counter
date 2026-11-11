// 022: 이름·문구·화면 바꾸기 — 사이트 이름, 홈 제목, 상단 바 자유게시판 위치, 문서·입력 순서, 입력 예시, 강타 빼기, [제안]
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeBuild, fakeLogin } from './fakeSupabase';
import { buildProblem, buildToForm } from '../lib/buildContent';
import { LEVEL_EXAMPLES, SUMMARY_EXAMPLE } from '../components/DocForm';
import { fillBuild, SKILL_GROUP, pick } from './buildHelpers';
import { openMenu } from './menu';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /></MemoryRouter>);
const MATCHUP = '/champion/Darius/counter/Quinn';

test('홈: 제목 "챔피언 선택", 탭 제목 "탑신병자 - 롤 탑 카운터", 상단 바에 사이트 이름·부제', async () => {
  start('/');
  expect(await screen.findByRole('heading', { level: 1, name: '챔피언 선택' })).toBeDefined();
  expect(screen.getByRole('link', { name: '탑신병자' })).toBeDefined();
  expect(screen.getByText('탑은 라인전이 전부')).toBeDefined();
  await vi.waitFor(() => expect(document.title).toBe('탑신병자 - 롤 탑 카운터'));
});

test('자유게시판(예전 이름 노가리방)은 상단 바가 아니라 ☰ 메뉴 안, 마이페이지 다음', async () => {
  start('/');
  await screen.findByRole('heading', { level: 1, name: '챔피언 선택' });
  expect(document.querySelector('.topbar').textContent).not.toContain('자유게시판');
  cleanup();
  fakeLogin('u-old');
  start('/');
  const menu = await openMenu();
  const mypage = menu.getByRole('link', { name: '마이페이지' });
  const link = menu.getByRole('link', { name: '자유게시판' });
  expect(mypage.compareDocumentPosition(link) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  expect(document.body.textContent).not.toContain('노가리방');
});

test('상대법 화면 순서: 빌드 탭 → (고른 빌드) 한 줄 요약 → 룬·아이템 → 레벨별 딜교법 → 특이사항 → 댓글', async () => {
  start(MATCHUP);
  await screen.findByRole('heading', { level: 1, name: '퀸으로 다리우스 이기는 법' });
  const toc = screen.getByRole('navigation', { name: '목차' });
  expect(within(toc).getAllByRole('link').map((a) => a.textContent)).toEqual(['빌드', '레벨별 딜교법', '특이사항', '댓글']);
  await screen.findByRole('heading', { name: /4\. 댓글/ });
  const heads = [...document.querySelectorAll('.section-title')].map((h) => h.textContent.replace(/\s+/g, ' ').trim());
  expect(heads.slice(0, 3)).toEqual(['1. 빌드', '2. 레벨별 딜교법', '3. 특이사항']);
  expect(heads[3]).toMatch(/^4\. 댓글/);
  const summary = document.querySelector('.doc-summary');
  expect(summary).not.toBeNull();
  const after = (a, b) => !!(a.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING);
  expect(after(screen.getByRole('tablist'), summary)).toBe(true);
  expect(after(summary, document.querySelector('article.build'))).toBe(true);
  expect(after(document.querySelector('article.build'), document.getElementById('levels'))).toBe(true);
});

test('새 상대법 등록: 입력 순서는 빌드 이름 → 한 줄 요약 → 빌드 → 레벨별 딜교법 → 특이사항, 예시 문구, [상대법 등록]', async () => {
  fakeLogin('u-old');
  start('/champion/Darius/counter/Teemo');
  fireEvent.click(await screen.findByRole('link', { name: '+ 상대법 등록' }));
  await screen.findByRole('heading', { name: '3. 티모로 다리우스 이기는 법 — 첫 빌드' });
  const form = document.querySelector('form.doc-form');
  const summary = within(form).getByLabelText('한 줄 요약 (필수)');
  expect(summary.getAttribute('placeholder')).toBe('예) 트린 평타를 틀어막는 착취·E선마·얼심 말파');
  expect(within(form).getByText(`예) ${SUMMARY_EXAMPLE}`)).toBeDefined();
  const order = (a, b) => !!(a.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING);
  const rune = within(form).getByRole('group', { name: '주 경로' });
  const lv1 = within(form).getByLabelText('1레벨 (필수)');
  const cautions = within(form).getByLabelText('특이사항');
  expect(order(within(form).getByLabelText('빌드 이름 (선택)'), summary)).toBe(true);
  expect(order(summary, rune) && order(rune, lv1) && order(lv1, cautions)).toBe(true);

  // 레벨 예시는 1·2·3·6레벨 칸에만
  expect(lv1.getAttribute('placeholder')).toBe(`예) ${LEVEL_EXAMPLES[1]}`);
  expect(LEVEL_EXAMPLES[1]).toMatch(/^E를 찍는다\. 트린이 CS를 막으려고/);
  for (const lv of [2, 3, 6]) {
    expect(within(form).getByLabelText(`${lv}레벨 (필수)`).getAttribute('placeholder')).toBe(`예) ${LEVEL_EXAMPLES[lv]}`);
  }
  expect(Object.keys(LEVEL_EXAMPLES)).toEqual(['1', '2', '3', '6']);
  expect(within(form).getByRole('button', { name: '상대법 등록' })).toBeDefined();
  expect(within(form).queryByRole('button', { name: '제안' })).toBeNull();
});

test('강타: 소환사 주문 목록에 없고, 예전 빌드를 다시 쓰면 이유를 보여 주고 뺄 수 있다', async () => {
  fakeLogin('u-old');
  start(`${MATCHUP}/build/new`);
  await screen.findByRole('heading', { name: /새 빌드/ });
  const spells = screen.getByRole('group', { name: '소환사 주문' });
  expect(within(spells).queryByRole('button', { name: '강타' })).toBeNull();
  expect(within(spells).getByRole('button', { name: '점화' })).toBeDefined();
  cleanup();

  TABLES.builds.push(fakeBuild(150, { nickname: '기존유저', level: 1, main_title: null }, {
    author_id: 'u-old', status: 'rejected', summoner_spells: ['SummonerFlash', 'SummonerSmite'],
  }));
  fakeLogin('u-old');
  start(`${MATCHUP}/build/new?from=150`);
  await screen.findByRole('heading', { name: /새 빌드/ });
  fireEvent.click(screen.getByRole('button', { name: '지금 빌드 내용 가져오기' }));
  expect(screen.getByText('아직 고를 것: 강타는 고를 수 없습니다. 다른 소환사 주문을 골라 주세요.')).toBeDefined();
  pick('소환사 주문', '강타'); // 골라져 있던 강타를 빼면 목록에서도 사라진다
  expect(within(screen.getByRole('group', { name: '소환사 주문' })).queryByRole('button', { name: '강타' })).toBeNull();
  pick('소환사 주문', '점화');
  expect(screen.queryByText(/강타는 고를 수 없습니다/)).toBeNull();
});

test('규칙: 강타가 든 빌드는 buildProblem이 막는다', () => {
  const b = buildToForm(fakeBuild(1, null, { summoner_spells: ['SummonerSmite', 'SummonerFlash'] }));
  expect(buildProblem(b)).toBe('강타는 고를 수 없습니다. 다른 소환사 주문을 골라 주세요.');
});

test('빌드 입력: 핵심 템트리는 끌어서 순서 바꾸기 안내, [빼기]는 X 아이콘 버튼', async () => {
  fakeLogin('u-old');
  start(`${MATCHUP}/build/new`);
  await screen.findByRole('heading', { name: /새 빌드/ });
  fillBuild();
  pick(SKILL_GROUP, '선마 Q');
  expect(screen.getByText(/끌어서 순서 바꾸기 \(폰은 꾹 눌러 끌기\)/)).toBeDefined();
  const core = screen.getByRole('list', { name: '고른 핵심 템트리' });
  const x = within(core).getByRole('button', { name: '강철판 장화 빼기' });
  expect(x.textContent).toBe('');
  expect(x.querySelector('svg')).not.toBeNull();
  const start1 = within(screen.getByRole('list', { name: '고른 시작 아이템' })).getByRole('button', { name: '도란의 검 빼기' });
  expect(start1.querySelector('svg')).not.toBeNull();
  expect(screen.getByLabelText('핵심 템트리 검색').getAttribute('placeholder')).toBe('판금장화 ex) ㅍㄱㅈㅎ');
});
