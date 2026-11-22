// 065 (SPEC 6-80): 스킬 찍는 순서 상세 입력·보기 — 규칙(DB와 같은 문구), 칸이 하나씩, 흐린 버튼 + 이유, 여기부터 다시, 전부 지우기,
// q·w·e·r 키, 예외 챔피언, 선마와 어긋남 안내, [상세하게 보기], 수정 기록 비교, 저장 모양(옛 앱 호환: 키 없으면 그대로)
import { useState } from 'react';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import SkillSequenceInput from '../components/SkillSequenceInput';
import SkillSequenceView from '../components/SkillSequenceView';
import { buildDiff } from '../lib/diff';
import {
  SEQ_EXCEPTIONS, firstMaxed, maxSkillMismatch, nextKeyProblem, seqMode, seqProblem, seqProgress, seqSpoken, stepProblem, toSeq,
} from '../lib/skillSequence';
import { emptyWikiBuild, sameWikiBuild, toWikiPayload, wikiBuildProblem, wikiBuildToForm } from '../lib/wikiBuild';
import { fakeFetch } from './fakeDdragon';
import { TABLES, fakeLogin, fakeState } from './fakeSupabase';

beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

const MATCHUP = '/champion/Darius/counter/Quinn';
const rpcCalls = (name) => fakeState.rpcCalls.filter((c) => c.name === name).map((c) => c.args);
const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /></MemoryRouter>);

// ---------------- 규칙 (DB skill_sequence_problem과 같은 문구) ----------------
describe('규칙', () => {
  test('기본 규칙: 정상 순서', () => {
    expect(seqProblem('QWEQQRQEQERWWEERWW', 'Garen')).toBeNull(); // Q5·W5·E5·R3, 18렙
    expect(seqProblem('QWEQQRQ', 'Garen')).toBeNull(); // 7렙까지만
    expect(seqProblem('', 'Garen')).toBeNull();
    expect(seqProblem(null, 'Garen')).toBeNull();
  });
  test('기본 규칙: 막는 경우와 이유', () => {
    expect(seqProblem('QWEQR', 'Garen')).toBe('스킬 순서 5렙: R은 6렙부터 찍을 수 있습니다.');
    expect(seqProblem('QWEQQRQEQR', 'Garen')).toBe('스킬 순서 10렙: 두 번째 R은 11렙부터 찍을 수 있습니다.');
    expect(seqProblem('QWEQQRQEQERWWER', 'Garen')).toBe('스킬 순서 15렙: 세 번째 R은 16렙부터 찍을 수 있습니다.');
    expect(seqProblem('QWEQQRQEQERWWEERWR', 'Garen')).toBe('스킬 순서 18렙: R은 3번까지 찍을 수 있습니다.');
    expect(seqProblem('QQ', 'Garen')).toBe('스킬 순서 2렙: 2렙에는 Q를 1번까지 찍을 수 있습니다.');
    expect(seqProblem('QWQEQQ', 'Garen')).toBe('스킬 순서 6렙: 6렙에는 Q를 3번까지 찍을 수 있습니다.');
    expect(seqProblem('QWQEQRQEQQ', 'Garen')).toBe('스킬 순서 10렙: Q는 5번까지 찍을 수 있습니다.');
    expect(stepProblem('QWE', 'Q')).toBeNull();
    expect(stepProblem('QW', 'Q')).toBeNull(); // 3렙 Q 두 번째는 됨
    expect(stepProblem('QWQ', 'Q')).toBe('4렙에는 Q를 2번까지 찍을 수 있습니다.');
  });
  test('형식: Q·W·E·R만, 1~18칸', () => {
    for (const s of ['qwe', 'QWX', 'QWEQQRQEQERWWEERWWQ']) expect(seqProblem(s, 'Garen')).toBe('스킬 순서는 Q·W·E·R만 1~18칸까지 적을 수 있습니다.');
  });
  test('예외 표: loose는 형식만, hidden은 상세 순서 없음, 표에 없으면 기본', () => {
    expect(SEQ_EXCEPTIONS).toEqual({ Aphelios: 'hidden', Udyr: 'loose', Jayce: 'loose', Elise: 'loose', Nidalee: 'loose', Karma: 'loose' });
    expect(seqMode('Garen')).toBe('strict');
    expect(seqMode(null)).toBe('strict');
    expect(seqProblem('RRRRRRQQ', 'Udyr')).toBeNull();
    expect(seqProblem('RQWE', 'Karma')).toBeNull();
    expect(seqProblem('RX', 'Udyr')).toMatch(/^스킬 순서는/);
    expect(seqProblem('QWE', 'Aphelios')).toBe('이 챔피언은 스킬을 직접 찍지 않아 상세 순서를 적을 수 없습니다.');
    expect(nextKeyProblem('', 'R', 'Jayce')).toBeNull();
    expect(nextKeyProblem('', 'R', 'Garen')).toBe('R은 6렙부터 찍을 수 있습니다.');
    expect(nextKeyProblem('Q'.repeat(18), 'Q', 'Udyr')).toBe('18렙까지 다 적었습니다.');
  });
  test('선마와 어긋남: 처음 5번 찍은 스킬과 다르면 안내 문구 (막지 않음)', () => {
    expect(firstMaxed('QWEQQRQEQ')).toBe('Q');
    expect(firstMaxed('QWE')).toBeNull();
    expect(maxSkillMismatch('QWEQQRQEQ', 'Q')).toBeNull();
    expect(maxSkillMismatch('QWEQQRQEQ', 'E')).toBe('선마와 순서가 다릅니다. 선마는 E인데, 적은 순서에서는 Q를 먼저 5번 찍었습니다.');
    expect(maxSkillMismatch('QWE', 'E')).toBeNull();
  });
  test('읽는 문장·진행 문구·저장 값 정리', () => {
    expect(seqSpoken('QEW')).toBe('1렙 Q, 2렙 E, 3렙 W');
    expect(seqProgress('QWEQQRQ')).toBe('7렙까지 작성하셨습니다 (7/18)');
    expect(seqProgress('')).toBe('아직 적지 않았습니다 (0/18)');
    expect(toSeq('qwe')).toBe('');
    expect(toSeq(null)).toBe('');
    expect(toSeq('QWE')).toBe('QWE');
  });
});

// ---------------- 저장 모양 ----------------
describe('저장 모양', () => {
  test('빈 순서는 null로 명시해서 보낸다 (지움), 있으면 그대로', () => {
    const v = { ...emptyWikiBuild(), summary: '요약' };
    expect(v.skill_sequence).toBe('');
    expect(toWikiPayload(v, '1.1.1')).toHaveProperty('skill_sequence', null);
    expect(toWikiPayload({ ...v, skill_sequence: 'QWE' }, '1.1.1').skill_sequence).toBe('QWE');
    expect(wikiBuildToForm({ skill_sequence: 'QEW' }).skill_sequence).toBe('QEW');
    expect(wikiBuildToForm({}).skill_sequence).toBe('');
  });
  test('순서만 바뀌어도 "바뀐 것 있음", 같으면 "바뀐 것 없음"', () => {
    const a = wikiBuildToForm({ max_skill: 'Q', skill_sequence: 'QWE' });
    expect(sameWikiBuild(a, { ...a })).toBe(true);
    expect(sameWikiBuild(a, { ...a, skill_sequence: 'QWEQ' })).toBe(false);
    expect(sameWikiBuild({ ...a, skill_sequence: '' }, { ...a, skill_sequence: null })).toBe(true);
  });
  test('화면 검사: 순서 문제는 빌드 문제 다음 (챔피언 기준)', () => {
    const v = { ...emptyWikiBuild(), skill_sequence: 'R' };
    expect(wikiBuildProblem(v, null, 'Garen')).not.toMatch(/스킬 순서/); // 아직 룬부터
  });
  test('수정 기록 비교에 "스킬 순서" (예전 기록엔 없음 = 빈칸)', () => {
    const before = { max_skill: 'Q' };
    const after = { max_skill: 'Q', skill_sequence: 'QWER' };
    const row = buildDiff(before, after).find((f) => f.key === 'sequence');
    expect(row).toMatchObject({ label: '스킬 순서', before: '', after: 'Q W E R', changed: true });
    expect(buildDiff(after, after).find((f) => f.key === 'sequence').changed).toBe(false);
  });
});

// ---------------- 입력 ----------------
function Harness({ champion = 'Garen', maxSkill = 'Q', initial = '' }) {
  const [v, setV] = useState(initial);
  return (
    <>
      <SkillSequenceInput value={v} onChange={setV} champion={champion} maxSkill={maxSkill} />
      <output data-testid="value">{v}</output>
    </>
  );
}
const value = () => screen.getByTestId('value').textContent;
const key = (k) => screen.getByRole('button', { name: new RegExp(`^(\\d+렙에 ${k}|${k} \\(지금은 찍을 수 없음\\))$`) });
const slots = () => within(screen.getByRole('list', { name: /적은 순서/ })).queryAllByRole('button');
const panel = () => screen.getByRole('group', { name: '스킬 찍는 순서 (상세)' });

describe('입력', () => {
  test('[상세하게 작성]을 누르면 열리고, 칸은 하나씩(적은 칸 + 다음 칸 하나), 진행 문구가 읽힌다', () => {
    const { container } = render(<Harness />);
    expect(screen.queryByRole('group', { name: '스킬 찍는 순서 (상세)' })).toBeNull();
    const open = screen.getByRole('button', { name: '상세하게 작성' });
    expect(open).toHaveAttribute('aria-expanded', 'false');
    fireEvent.click(open);
    expect(screen.getByRole('button', { name: '상세 순서 접기' })).toHaveAttribute('aria-expanded', 'true');
    expect(document.activeElement).toBe(key('Q')); // 열면 첫 스킬 버튼에 초점
    expect(slots()).toHaveLength(0);
    expect(container.querySelectorAll('.seq-slot.next')).toHaveLength(1);
    expect(screen.getByText('아직 적지 않았습니다 (0/18)')).toHaveAttribute('role', 'status');
    for (const k of 'QWEQQRQ') fireEvent.click(key(k));
    expect(value()).toBe('QWEQQRQ');
    expect(slots().map((b) => b.textContent)).toEqual([...'QWEQQRQ']);
    expect(container.querySelectorAll('.seq-slot.next')).toHaveLength(1); // 다음 칸은 늘 하나
    expect(container.querySelector('.seq-slot.next').previousSibling.textContent).toBe('8'); // 위에 작은 레벨 숫자
    expect(screen.getByText('7렙까지 작성하셨습니다 (7/18)')).toHaveAttribute('role', 'status');
    expect(container.querySelectorAll('.seq-slot.r')).toHaveLength(1); // R 칸은 주황
  });

  test('규칙에 안 맞는 버튼은 흐리게(aria-disabled) — 누르면 이유를 알려 주고 적지 않는다', () => {
    render(<Harness />);
    fireEvent.click(screen.getByRole('button', { name: '상세하게 작성' }));
    const r = key('R');
    expect(r).toHaveAttribute('aria-disabled', 'true');
    expect(r).toHaveClass('is-disabled');
    fireEvent.click(r);
    expect(screen.getByRole('alert')).toHaveTextContent('R은 6렙부터 찍을 수 있습니다.');
    expect(value()).toBe('');
    fireEvent.click(key('Q'));
    expect(screen.queryByRole('alert')).toBeNull(); // 제대로 누르면 안내는 사라짐
    fireEvent.click(key('Q'));
    expect(screen.getByRole('alert')).toHaveTextContent('2렙에는 Q를 1번까지 찍을 수 있습니다.');
    expect(value()).toBe('Q');
    fireEvent.click(key('W'));
    fireEvent.click(key('Q')); // 3렙엔 Q 두 번째 가능
    expect(value()).toBe('QWQ');
    expect(key('Q')).toHaveAttribute('aria-disabled', 'true'); // 4렙에 Q 세 번째는 안 됨
    expect(key('E')).not.toHaveAttribute('aria-disabled');
  });

  test('[← 하나 지우기], 칸을 누르면 그 레벨부터 다시, [전부 지우기] (중간 칸만 바꾸기는 없음)', () => {
    render(<Harness initial="QWEQQRQE" />);
    expect(panel()).toBeDefined(); // 이미 적은 순서가 있으면 열린 채로
    fireEvent.click(screen.getByRole('button', { name: '← 하나 지우기' }));
    expect(value()).toBe('QWEQQRQ');
    const third = screen.getByRole('button', { name: '3렙 E (누르면 3렙부터 다시 적기)' });
    fireEvent.click(third);
    expect(value()).toBe('QW');
    expect(screen.getByText('3렙부터 다시 적어 주세요.')).toHaveAttribute('role', 'status');
    expect(document.activeElement).toBe(key('Q')); // 사라진 칸 대신 스킬 버튼으로 초점
    fireEvent.click(key('E'));
    expect(value()).toBe('QWE');
    fireEvent.click(screen.getByRole('button', { name: '전부 지우기' }));
    expect(value()).toBe('');
    expect(screen.getByText('적은 순서를 모두 지웠습니다.')).toBeDefined();
    expect(screen.getByRole('button', { name: '전부 지우기' })).toBeDisabled();
    expect(screen.getByRole('button', { name: '← 하나 지우기' })).toBeDisabled();
  });

  test('PC: 칸 안에서 q·w·e·r 키로 적고 Backspace로 하나 지운다 (규칙도 같음)', () => {
    render(<Harness />);
    fireEvent.click(screen.getByRole('button', { name: '상세하게 작성' }));
    for (const k of 'qweqq') fireEvent.keyDown(document.activeElement, { key: k });
    expect(value()).toBe('QWEQQ');
    fireEvent.keyDown(panel(), { key: 'r' });
    expect(value()).toBe('QWEQQR');
    fireEvent.keyDown(panel(), { key: 'Backspace' });
    expect(value()).toBe('QWEQQ');
    fireEvent.keyDown(panel(), { key: 'q' }); // 6렙 Q 네 번째는 안 됨
    expect(screen.getByRole('alert')).toHaveTextContent('6렙에는 Q를 3번까지 찍을 수 있습니다.');
    fireEvent.keyDown(panel(), { key: 'q', ctrlKey: true }); // 단축키는 건드리지 않음
    expect(value()).toBe('QWEQQ');
  });

  test('18렙까지 다 적으면 다음 칸이 없고 버튼은 모두 흐림', () => {
    const { container } = render(<Harness initial="QWEQQRQEQERWWEERWW" />);
    expect(container.querySelectorAll('.seq-slot.next')).toHaveLength(0);
    expect(screen.getByText('18렙까지 작성하셨습니다 (18/18)')).toBeDefined();
    for (const k of 'QWER') expect(key(k)).toHaveAttribute('aria-disabled', 'true');
    fireEvent.click(key('W'));
    expect(screen.getByRole('alert')).toHaveTextContent('18렙까지 다 적었습니다.');
  });

  test('예외 챔피언(loose)은 레벨 규칙 없이 형식만 — 안내 문구', () => {
    render(<Harness champion="Udyr" />);
    fireEvent.click(screen.getByRole('button', { name: '상세하게 작성' }));
    expect(screen.getByText(/스킬 찍는 규칙이 달라 레벨 규칙은 검사하지 않습니다/)).toBeDefined();
    fireEvent.click(key('R'));
    fireEvent.click(key('R'));
    expect(value()).toBe('RR');
  });

  test('선마와 순서가 어긋나면 안내만 (막지 않음)', () => {
    render(<Harness maxSkill="E" initial="QWEQQRQEQ" />);
    expect(screen.getByRole('note')).toHaveTextContent('선마와 순서가 다릅니다. 선마는 E인데, 적은 순서에서는 Q를 먼저 5번 찍었습니다.');
  });
});

// ---------------- 보기 ----------------
describe('보기', () => {
  test('순서가 없으면 버튼도 없다', () => {
    const { container } = render(<SkillSequenceView sequence={null} />);
    expect(container.innerHTML).toBe('');
  });
  test('[상세하게 보기] → 작은 글자 칸 (R 주황, 6칸마다 띄움은 CSS), 스크린리더는 한 문장', () => {
    const { container } = render(<SkillSequenceView sequence="QWEQQRQ" />);
    const btn = screen.getByRole('button', { name: '상세하게 보기' });
    expect(btn).toHaveAttribute('aria-expanded', 'false');
    expect(container.querySelector('.seq-chips')).toBeNull();
    fireEvent.click(btn);
    expect(screen.getByRole('button', { name: '상세 접기' })).toHaveAttribute('aria-expanded', 'true');
    const chips = [...container.querySelectorAll('.seq-chips li')];
    expect(chips.map((c) => c.textContent).join('')).toBe('QWEQQRQ');
    expect(chips.filter((c) => c.classList.contains('r'))).toHaveLength(1);
    expect(container.querySelector('.seq-chips')).toHaveAttribute('aria-hidden', 'true');
    expect(screen.getByText('스킬 순서: 1렙 Q, 2렙 W, 3렙 E, 4렙 Q, 5렙 Q, 6렙 R, 7렙 Q')).toHaveClass('sr-only');
  });
});

// ---------------- 화면 전체 (상대법·빌드 수정) ----------------
describe('화면', () => {
  test('상대법 화면: 순서가 있는 빌드만 스킬 줄에 [상세하게 보기]', async () => {
    TABLES.builds.find((x) => x.id === 103).skill_sequence = 'QEWQQR';
    start(`${MATCHUP}?build=103`);
    fireEvent.click(await screen.findByRole('button', { name: '상세하게 보기' }));
    expect(screen.getByText('스킬 순서: 1렙 Q, 2렙 E, 3렙 W, 4렙 Q, 5렙 Q, 6렙 R')).toBeDefined();
    cleanup();
    start(`${MATCHUP}?build=102`);
    await screen.findByRole('link', { name: '빌드 수정' });
    expect(screen.queryByRole('button', { name: '상세하게 보기' })).toBeNull();
  });

  test('빌드 수정: 순서를 적어 저장하면 edit_build에 skill_sequence, 순서만 고쳐도 저장된다', async () => {
    fakeLogin('u-old');
    start(`${MATCHUP}/build/103/edit`);
    fireEvent.click(await screen.findByRole('button', { name: '상세하게 작성' }));
    for (const k of 'QWE') fireEvent.click(key(k));
    expect(screen.getByText('3렙까지 작성하셨습니다 (3/18)')).toBeDefined();
    fireEvent.click(screen.getByRole('button', { name: '수정 저장' }));
    await vi.waitFor(() => expect(rpcCalls('edit_build')).toHaveLength(1));
    expect(rpcCalls('edit_build')[0].p_build.skill_sequence).toBe('QWE');
    expect(TABLES.builds.find((x) => x.id === 103).skill_sequence).toBe('QWE');
  });

  test('빌드 수정: [전부 지우기] 뒤 저장하면 null을 명시해서 보낸다', async () => {
    TABLES.builds.find((x) => x.id === 103).skill_sequence = 'QWE';
    fakeLogin('u-old');
    start(`${MATCHUP}/build/103/edit`);
    expect(await screen.findByText('3렙까지 작성하셨습니다 (3/18)')).toBeDefined();
    fireEvent.click(screen.getByRole('button', { name: '전부 지우기' }));
    fireEvent.click(screen.getByRole('button', { name: '수정 저장' }));
    await vi.waitFor(() => expect(rpcCalls('edit_build')).toHaveLength(1));
    expect(rpcCalls('edit_build')[0].p_build).toHaveProperty('skill_sequence', null);
    expect(TABLES.builds.find((x) => x.id === 103).skill_sequence).toBeNull();
  });

  test('빌드 수정: 다른 칸만 고치면 순서는 그대로 보낸다', async () => {
    TABLES.builds.find((x) => x.id === 103).skill_sequence = 'QWE';
    fakeLogin('u-old');
    start(`${MATCHUP}/build/103/edit`);
    fireEvent.change(await screen.findByLabelText('특이사항'), { target: { value: '바꿈' } });
    fireEvent.click(screen.getByRole('button', { name: '수정 저장' }));
    await vi.waitFor(() => expect(rpcCalls('edit_build')).toHaveLength(1));
    expect(rpcCalls('edit_build')[0].p_build.skill_sequence).toBe('QWE');
  });
});
