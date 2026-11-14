// 038 상대법 = 빌드 묶음 화면: 빌드 수정(위키)·기여자 팝업·⋮ 메뉴·챔피언 목록 요약
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { AppRoutes } from '../App';
import MoreMenu from '../components/MoreMenu';
import { describeNotification } from '../lib/notifications';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeGuestLogin, fakeLogin, fakeState } from './fakeSupabase';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

function Where() { const l = useLocation(); return <output data-testid="where">{l.pathname + l.search}</output>; }
const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /><Where /></MemoryRouter>);
const where = () => screen.getByTestId('where').textContent;
const MATCHUP = '/champion/Darius/counter/Quinn';
const rpcCalls = (name) => fakeState.rpcCalls.filter((c) => c.name === name).map((c) => c.args);
const b = (id) => TABLES.builds.find((x) => x.id === id);

// ---------------- 빌드 수정 ----------------

test('[빌드 수정]: 지금 내용이 채워져 있고, 바뀐 게 없으면 안 보내고, 고치면 edit_build(버전) → 그 빌드가 고른 상대법 화면', async () => {
  fakeLogin('u-old');
  start(`${MATCHUP}?build=103`);
  fireEvent.click(await screen.findByRole('link', { name: '빌드 수정' }));
  expect(await screen.findByRole('heading', { name: '퀸으로 다리우스 이기는 법 — 빌드 3 수정' })).toBeDefined();
  expect(where()).toBe(`${MATCHUP}/build/103/edit`);
  expect(screen.queryByText(/신중히 수정해 주세요/)).toBeNull(); // 추천 2 < 3
  expect(screen.getByLabelText('한 줄 요약 (필수)')).toHaveValue('사거리로 일방적인 견제');
  expect(screen.getByLabelText('특이사항')).toHaveValue('E 사거리 주의');
  fireEvent.click(screen.getByRole('button', { name: '수정 저장' }));
  expect(screen.getByRole('alert')).toHaveTextContent('바뀐 내용이 없습니다.');
  fireEvent.change(screen.getByLabelText('빌드 이름 (선택)'), { target: { value: '견제형' } });
  fireEvent.change(screen.getByLabelText('특이사항'), { target: { value: 'E 사거리 주의\n궁 조심' } });
  fireEvent.click(screen.getByRole('button', { name: '수정 저장' }));
  await vi.waitFor(() => expect(where()).toBe(`${MATCHUP}?build=103`));
  const [args] = rpcCalls('edit_build');
  expect(args).toMatchObject({ p_id: 103, p_version: 1 });
  expect(args.p_build).toMatchObject({ name: '견제형', lane_cautions: 'E 사거리 주의\n궁 조심', summary: '사거리로 일방적인 견제', patch: '99.1.1' });
  expect(await screen.findByText('빌드를 수정했습니다.')).toBeDefined();
  expect(screen.getByRole('tab', { name: /^견제형/ })).toHaveAttribute('aria-selected', 'true');
});

test('추천이 3개 이상인 빌드는 "많은 분이 추천한 빌드입니다. 신중히 수정해 주세요."', async () => {
  fakeLogin('u-old');
  start(`${MATCHUP}/build/102/edit`);
  expect(await screen.findByText('많은 분이 추천한 빌드입니다. 신중히 수정해 주세요.')).toBeDefined();
});

test('다른 분이 먼저 고쳤으면(TL412) 이유와 [최신 내용 불러오기] → 최신 내용으로 다시 채운다', async () => {
  fakeLogin('u-old');
  start(`${MATCHUP}/build/103/edit`);
  await screen.findByRole('heading', { name: /빌드 3 수정/ });
  fireEvent.change(screen.getByLabelText('한 줄 요약 (필수)'), { target: { value: '내가 고친 요약' } });
  Object.assign(b(103), { version: 2, summary: '남이 먼저 고친 요약' }); // 그 사이 다른 분이 고침
  fireEvent.click(screen.getByRole('button', { name: '수정 저장' }));
  const alert = await screen.findByRole('alert');
  expect(alert).toHaveTextContent('다른 분이 먼저 수정했습니다. 최신 내용을 확인해 주세요.');
  expect(within(alert).getByText('불러오면 지금 고친 내용은 지워집니다.')).toBeDefined();
  fireEvent.click(within(alert).getByRole('button', { name: '최신 내용 불러오기' }));
  expect(await screen.findByText('최신 내용을 불러왔습니다. 다시 고쳐 주세요.')).toBeDefined();
  expect(screen.getByLabelText('한 줄 요약 (필수)')).toHaveValue('남이 먼저 고친 요약');
  fireEvent.change(screen.getByLabelText('한 줄 요약 (필수)'), { target: { value: '다시 고친 요약' } });
  fireEvent.click(screen.getByRole('button', { name: '수정 저장' }));
  await vi.waitFor(() => expect(where()).toBe(`${MATCHUP}?build=103`));
  expect(rpcCalls('edit_build').map((a) => a.p_version)).toEqual([1, 2]);
});

test('비회원: 남의 빌드는 고칠 수 없다는 안내와 [+ 새 빌드], 내 빌드는 고칠 수 있다', async () => {
  fakeGuestLogin('guest-1', { nickname: '손님' });
  start(`${MATCHUP}/build/103/edit`);
  expect(await screen.findByText(/다른 분의 빌드는 구글·카카오로 로그인한 회원만 수정할 수 있습니다/)).toBeDefined();
  expect(screen.queryByLabelText('한 줄 요약 (필수)')).toBeNull();
  expect(screen.getByRole('link', { name: '+ 새 빌드' }).getAttribute('href')).toBe(`${MATCHUP}/build/new?from=103`);
  cleanup();
  b(103).author_id = 'guest-1';
  start(`${MATCHUP}/build/103/edit`);
  expect(await screen.findByLabelText('한 줄 요약 (필수)')).toBeDefined();
  expect(screen.queryByText(/구글·카카오로 로그인한 회원만/)).toBeNull();
});

test('비회원이 남의 빌드를 고치려 하면 DB도 막는다 (화면 안내를 지나쳐도)', async () => {
  fakeLogin('u-old'); // 화면은 회원으로 열고
  start(`${MATCHUP}/build/103/edit`);
  await screen.findByLabelText('한 줄 요약 (필수)');
  TABLES.profiles.find((p) => p.id === 'u-old').is_guest = true; // 그 사이 DB 기준으로는 비회원
  fireEvent.change(screen.getByLabelText('한 줄 요약 (필수)'), { target: { value: '고침' } });
  fireEvent.click(screen.getByRole('button', { name: '수정 저장' }));
  expect(await screen.findByRole('alert')).toHaveTextContent('다른 분의 빌드는 구글·카카오로 로그인한 회원만 수정할 수 있습니다.');
});

test('숨겨졌거나 없는 빌드는 고칠 수 없다', async () => {
  fakeLogin('u-old');
  b(103).status = 'hidden';
  start(`${MATCHUP}/build/103/edit`);
  expect(await screen.findByText('공개된 빌드만 수정할 수 있습니다. 숨겨졌거나 없는 빌드입니다.')).toBeDefined();
});

test('빌드 수정 화면은 로그인부터, 닉네임이 없으면 닉네임 정하기부터', async () => {
  start(`${MATCHUP}/build/103/edit`);
  expect(await screen.findByRole('heading', { name: '로그인 · 가입' })).toBeDefined();
  cleanup();
  fakeLogin('u-new');
  start(`${MATCHUP}/build/103/edit`);
  expect(await screen.findByRole('heading', { name: '닉네임 정하기' })).toBeDefined();
});

test('빌드 이름은 20자까지', async () => {
  fakeLogin('u-old');
  start(`${MATCHUP}/build/103/edit`);
  await screen.findByLabelText('빌드 이름 (선택)');
  fireEvent.change(screen.getByLabelText('빌드 이름 (선택)'), { target: { value: '가'.repeat(21) } });
  expect(screen.getByText('21/20자')).toBeDefined();
  fireEvent.click(screen.getByRole('button', { name: '수정 저장' }));
  expect(screen.getByRole('alert')).toHaveTextContent('빌드 이름은 20자 이하로 적어 주세요.');
  expect(rpcCalls('edit_build')).toEqual([]);
});

// ---------------- [수정 기록]: 기여자 팝업 ----------------

test('[수정 기록] → 기여자 팝업: 처음 만든 분 먼저, 닉네임만(레벨·칭호·시초 뱃지 없음, 046), 탈퇴한 이용자, Esc로 닫으면 버튼으로 초점', async () => {
  fakeState.contributors[102] = [
    { user_id: 'u-102', nickname: '탑고수', role: 'user', is_guest: false, level: 7, main_title: 'solid_heavy', is_origin: true },
    { user_id: 'u-9', nickname: '시초', role: 'user', is_guest: true, level: 2, main_title: null, is_origin: false },
    { user_id: null, nickname: null, role: null, is_guest: false, level: null, main_title: null, is_origin: false },
  ];
  start(MATCHUP);
  const open = await screen.findByRole('button', { name: '수정 기록' });
  fireEvent.click(open);
  const dialog = await screen.findByRole('dialog', { name: '빌드 2 기여자' });
  expect(rpcCalls('build_contributors')).toEqual([{ p_build: 102 }]);
  const rows = await within(dialog).findAllByRole('listitem');
  expect(rows.map((r) => r.textContent)).toEqual([
    '탑고수', '시초 비회원', '탈퇴한 이용자',
  ]);
  expect(dialog.querySelectorAll('.origin-badge, .title-badge, .user-lv')).toHaveLength(0);
  expect(document.activeElement).toBe(within(dialog).getByRole('button', { name: '닫기' }));
  fireEvent.keyDown(dialog, { key: 'Escape' });
  expect(screen.queryByRole('dialog')).toBeNull();
  expect(document.activeElement).toBe(open);
});

test('기여자 팝업: 바깥(어두운 바탕)을 누르거나 [닫기]로 닫히고, 초점은 팝업 안에 갇힌다', async () => {
  start(MATCHUP);
  fireEvent.click(await screen.findByRole('button', { name: '수정 기록' }));
  const dialog = await screen.findByRole('dialog');
  await within(dialog).findByRole('listitem');
  const close = within(dialog).getByRole('button', { name: '닫기' });
  fireEvent.keyDown(dialog, { key: 'Tab' }); // 마지막(닫기)에서 Tab → 처음으로 (버튼이 하나뿐이면 그대로)
  expect(document.activeElement).toBe(close);
  fireEvent.click(dialog); // 팝업 안을 누르면 그대로
  expect(screen.getByRole('dialog')).toBeDefined();
  fireEvent.click(dialog.parentElement); // 바깥
  expect(screen.queryByRole('dialog')).toBeNull();
  fireEvent.click(screen.getByRole('button', { name: '수정 기록' }));
  fireEvent.click(await screen.findByRole('button', { name: '닫기' }));
  expect(screen.queryByRole('dialog')).toBeNull();
});

// ---------------- 공용 ⋮ 메뉴 ----------------

function renderMenu(items) {
  return render(<MemoryRouter><MoreMenu items={items} label="글 더보기" /><button type="button">바깥</button></MemoryRouter>);
}

test('⋮ 메뉴: 보일 항목이 없으면 버튼도 없다', () => {
  renderMenu([null, false]);
  expect(screen.queryByRole('button', { name: '글 더보기' })).toBeNull();
});

test('⋮ 메뉴: 44px 버튼(aria-label "더보기"), 열면 첫 항목에 초점, ↑↓·Home·End 이동, Esc는 닫고 버튼으로 초점', () => {
  const picked = [];
  renderMenu([
    { label: '고치기', onSelect: () => picked.push('고치기') },
    { label: '신고', onSelect: () => picked.push('신고') },
    { label: '숨기기', op: true, onSelect: () => picked.push('숨기기') },
  ]);
  const btn = screen.getByRole('button', { name: '글 더보기' });
  expect(btn).toHaveAttribute('aria-haspopup', 'menu');
  expect(btn).toHaveAttribute('aria-expanded', 'false');
  expect(btn).toHaveClass('more-btn'); // 크기는 index.css .more-btn = var(--tap-min) 44px
  fireEvent.click(btn);
  expect(btn).toHaveAttribute('aria-expanded', 'true');
  const menu = screen.getByRole('menu', { name: '글 더보기' });
  const items = within(menu).getAllByRole('menuitem');
  expect(items.map((i) => i.textContent)).toEqual(['고치기', '신고', '숨기기']);
  expect(document.activeElement).toBe(items[0]);
  fireEvent.keyDown(document.activeElement, { key: 'ArrowDown' });
  expect(document.activeElement).toBe(items[1]);
  fireEvent.keyDown(document.activeElement, { key: 'End' });
  expect(document.activeElement).toBe(items[2]);
  fireEvent.keyDown(document.activeElement, { key: 'ArrowDown' }); // 끝에서 다시 처음으로
  expect(document.activeElement).toBe(items[0]);
  fireEvent.keyDown(document.activeElement, { key: 'ArrowUp' });
  expect(document.activeElement).toBe(items[2]);
  expect(items[2]).toHaveClass('op');
  fireEvent.keyDown(document.activeElement, { key: 'Escape' });
  expect(screen.queryByRole('menu')).toBeNull();
  expect(document.activeElement).toBe(btn);
  // ↓로도 열린다, 고르면 닫히고 실행
  fireEvent.keyDown(btn, { key: 'ArrowDown' });
  fireEvent.click(screen.getAllByRole('menuitem')[1]);
  expect(picked).toEqual(['신고']);
  expect(screen.queryByRole('menu')).toBeNull();
});

test('⋮ 메뉴: 바깥을 누르면 닫힌다', () => {
  renderMenu([{ label: '신고', onSelect: () => {} }]);
  fireEvent.click(screen.getByRole('button', { name: '글 더보기' }));
  expect(screen.getByRole('menu')).toBeDefined();
  fireEvent.mouseDown(screen.getByRole('button', { name: '바깥' }));
  expect(screen.queryByRole('menu')).toBeNull();
});

test('⋮ 메뉴: 지우기는 빨간 글자이고, 한 번 더 묻는다 ([취소]에 초점, 확인해야 실행)', () => {
  const picked = [];
  renderMenu([{ label: '삭제', danger: true, confirm: '이 글을 지울까요? 지운 글은 되돌릴 수 없습니다.', onSelect: () => picked.push('삭제') }]);
  fireEvent.click(screen.getByRole('button', { name: '글 더보기' }));
  const del = screen.getByRole('menuitem', { name: '삭제' });
  expect(del).toHaveClass('danger');
  fireEvent.click(del);
  expect(picked).toEqual([]);
  const ask = screen.getByRole('alertdialog', { name: '삭제' });
  expect(within(ask).getByText(/지운 글은 되돌릴 수 없습니다/)).toBeDefined();
  expect(document.activeElement).toBe(within(ask).getByRole('button', { name: '취소' }));
  fireEvent.click(within(ask).getByRole('button', { name: '취소' }));
  expect(screen.queryByRole('alertdialog')).toBeNull();
  expect(picked).toEqual([]);
  fireEvent.click(screen.getByRole('button', { name: '글 더보기' }));
  fireEvent.click(screen.getByRole('menuitem', { name: '삭제' }));
  const yes = within(screen.getByRole('alertdialog')).getByRole('button', { name: '삭제' });
  expect(yes).toHaveClass('btn-danger');
  fireEvent.click(yes);
  expect(picked).toEqual(['삭제']);
});

// ---------------- 챔피언 목록 ----------------

test('챔피언 목록의 한 줄 요약 = 그 상대법의 맨 앞 빌드(추천 많은 순) 요약', async () => {
  b(103).summary = '칭호없음 빌드 요약';
  b(103).up_count = 9;
  b(104).summary = '대기 빌드 요약'; // 공개 안 된 빌드는 안 쓴다
  b(104).up_count = 99;
  start('/champion/Darius');
  const row = await screen.findByRole('link', { name: /퀸/ });
  expect(within(row).getByText('칭호없음 빌드 요약')).toBeDefined();
});

// ---------------- 운영자 알림 ----------------

test('운영자 알림: 새 상대법·새 빌드 → 누르면 그 상대법(그 빌드를 고른 채로)', () => {
  const name = (id) => ({ Darius: '다리우스', Quinn: '퀸' })[id] ?? id;
  const counter = { target_champion: 'Darius', counter_champion: 'Quinn', status: 'approved' };
  const m = describeNotification({ id: 1, kind: 'matchup_created', message: '새 상대법이 등록됐습니다.', counter_id: 1, build_id: 7, counter, build: { counter } }, name);
  expect(m).toMatchObject({ title: '새 상대법이 등록됐습니다.', subject: '[상대법] 퀸으로 다리우스 이기는 법', to: '/champion/Darius/counter/Quinn?build=7' });
  const bn = describeNotification({ id: 2, kind: 'build_created', message: '새 빌드가 등록됐습니다.', counter_id: null, build_id: 9, counter: null, build: { counter } }, name);
  expect(bn).toMatchObject({ subject: '[빌드] 퀸으로 다리우스 이기는 법', to: '/champion/Darius/counter/Quinn?build=9' });
});
