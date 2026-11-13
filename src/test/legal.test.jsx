import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { AppRoutes } from '../App';
import { RIOT_NOTICE } from '../components/Layout';
import { LEGAL } from '../lib/legal';
import { fakeFetch } from './fakeDdragon';
import { fakeLogin } from './fakeSupabase';

const SAVED = { ...LEGAL };
beforeEach(() => {
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); Object.assign(LEGAL, SAVED); });

function Where() { const l = useLocation(); return <output data-testid="where">{l.pathname}</output>; }
const start = (path) => render(<MemoryRouter initialEntries={[path]}><AppRoutes /><Where /></MemoryRouter>);
const where = () => screen.getByTestId('where').textContent;
const footer = () => screen.getByRole('contentinfo');

test('푸터: 개인정보처리방침·이용약관 링크로 이동하고, Riot 고지 문구는 그대로 있다 (로그인 없이)', async () => {
  start('/');
  const links = within(footer()).getByRole('navigation', { name: '사이트 정책' });
  expect(within(footer()).getByText(RIOT_NOTICE)).toBeDefined();
  fireEvent.click(within(links).getByRole('link', { name: '개인정보처리방침' }));
  expect(await screen.findByRole('heading', { level: 1, name: '개인정보처리방침' })).toBeDefined();
  expect(where()).toBe('/privacy');
  fireEvent.click(within(footer()).getByRole('link', { name: '이용약관' }));
  expect(await screen.findByRole('heading', { level: 1, name: '이용약관' })).toBeDefined();
  expect(where()).toBe('/terms');
  expect(within(footer()).getByText(RIOT_NOTICE)).toBeDefined();
});

test('빈칸(운영자 이메일·Supabase 지역·시행일)은 노란 칸 "채워 주세요"로 보인다', async () => {
  Object.assign(LEGAL, { contactEmail: null, supabaseRegion: null, effectiveDate: null });
  start('/privacy');
  await screen.findByRole('heading', { level: 1, name: '개인정보처리방침' });
  const blanks = [...document.querySelectorAll('mark.fill-me')].map((m) => m.textContent);
  expect(new Set(blanks)).toEqual(new Set(['【채워 주세요: 운영자 이메일】', '【채워 주세요: Supabase 서버 지역】', '【채워 주세요: 시행일】']));
  cleanup();
  start('/terms');
  await screen.findByRole('heading', { level: 1, name: '이용약관' });
  expect(screen.getAllByText('【채워 주세요: 운영자 이메일】').length).toBeGreaterThan(0);
  expect(screen.getAllByText('【채워 주세요: 시행일】').length).toBeGreaterThan(0);
});

test('legal.js에 값을 넣으면 그 값이 보이고(이메일은 메일 링크), 노란 칸은 사라진다', async () => {
  Object.assign(LEGAL, { contactEmail: 'op@example.com', supabaseRegion: '대한민국 (서울)', effectiveDate: '2026년 11월 15일' });
  start('/privacy');
  await screen.findByRole('heading', { level: 1, name: '개인정보처리방침' });
  expect(document.querySelector('mark.fill-me')).toBeNull();
  expect(screen.getAllByRole('link', { name: 'op@example.com' })[0].getAttribute('href')).toBe('mailto:op@example.com');
  expect(screen.getByText(/대한민국 \(서울\)/)).toBeDefined();
  expect(screen.getAllByText(/2026년 11월 15일/).length).toBeGreaterThan(0);
});

test('개인정보처리방침: 수집 항목·탈퇴 요청·만 14세 미만 안내가 있다', async () => {
  start('/privacy');
  await screen.findByRole('heading', { level: 1, name: '개인정보처리방침' });
  expect(screen.getByText('구글 계정 이메일, 이름, 프로필 사진')).toBeDefined();
  expect(screen.getByText('카카오계정 이메일(필수 동의), 카카오 닉네임, 프로필 사진')).toBeDefined();
  expect(screen.getByRole('heading', { name: '9. 회원 탈퇴(계정 삭제)' })).toBeDefined();
  expect(screen.getByText(/만 14세 미만 아동의 회원 가입을 받지 않습니다/)).toBeDefined();
});

test('개인정보처리방침 (037): 휴대폰 알림 수집 항목·삭제 시점·전달 업체', async () => {
  start('/privacy');
  await screen.findByRole('heading', { level: 1, name: '개인정보처리방침' });
  const text = document.querySelector('article.legal').textContent;
  expect(text).toContain('휴대폰 알림을 켠 경우: 기기(브라우저)마다 브라우저 푸시 서비스가 만든 알림 주소와 암호화 키');
  expect(text).toContain('그 기기에서 알림을 끄거나 로그아웃하면 바로 지웁니다');
  expect(text).toContain('휴대폰 알림 주소와 알림 종류 설정');
  expect(text).toContain('브라우저 푸시 서비스: Google LLC');
});

test('방침·약관 (046 장인 인증): 수집·보관·공개 범위, 인증 절차, 사칭 금지 / 시행일은 그대로', async () => {
  const before = { ...LEGAL };
  start('/privacy');
  await screen.findByRole('heading', { level: 1, name: '개인정보처리방침' });
  const privacy = document.querySelector('article.legal').textContent;
  expect(privacy).toContain('공식 이메일과 라이엇 닉네임#태그는 심사가 끝나면 삭제하고, 중복 신청 방지를 위한 암호화 값(해시)은 인증이 유지되는 동안 보관한 뒤 해제·탈퇴 때 삭제합니다.');
  expect(privacy).toContain('신청한 본인과 운영자만 보며, 감독관과 다른 이용자에게는 공개하지 않습니다');
  expect(privacy).toContain('끝난 날(해제는 해제한 날)부터 1년');
  expect(privacy).not.toContain('시초');
  expect(privacy).not.toContain('캡처');
  cleanup();
  start('/terms');
  await screen.findByRole('heading', { level: 1, name: '이용약관' });
  const apply = screen.getByRole('heading', { name: '제4조의2 (장인 인증)' }).closest('section').textContent;
  expect(apply).toContain('크리에이터·프로게이머(이메일 회신)');
  expect(apply).toContain('그랜드마스터 이상(친구 요청)');
  expect(apply).toContain('운영자는 요청을 수락하지 않고');
  expect(apply).not.toContain('캡처');
  const nick = screen.getByRole('heading', { name: '제4조 (닉네임)' }).closest('section').textContent;
  expect(nick).toContain('“[장인]”·“(장인)”이 들어간 닉네임');
  expect(nick).toContain('“장인 ”으로 시작하는 닉네임');
  expect(LEGAL).toEqual(before);
});

test('이용약관 (021): 실존 인물·고인 비하, 혐오 표현, 신상 공개 금지 / 실존 인물 이름 닉네임은 허용', async () => {
  start('/terms');
  await screen.findByRole('heading', { level: 1, name: '이용약관' });
  const banned = screen.getByRole('heading', { name: '제6조 (금지 행위)' }).closest('section').textContent;
  expect(banned).toContain('실존 인물(프로게이머·방송인 등)과 고인을 비하하거나 조롱하는 행위');
  expect(banned).toContain('혐오 표현');
  expect(banned).toContain('신상 공개');
  const nick = screen.getByRole('heading', { name: '제4조 (닉네임)' }).closest('section').textContent;
  expect(nick).toContain('실존 인물(프로게이머·방송인 등)의 이름이 들어간 닉네임은 쓸 수 있습니다');
  expect(nick).toContain('비하하거나 조롱하는 표현');
  expect(nick).toContain('신상 정보');
  expect(screen.getByText(/자동으로 걸러 내는 금칙어는 쓰지 않습니다/)).toBeDefined();
});

test('닉네임을 아직 안 정한 로그인 상태에서도 두 페이지(와 다른 읽기 화면)는 닉네임 설정으로 끌려가지 않는다', async () => {
  fakeLogin('u-new'); // 닉네임 없음
  start('/privacy');
  expect(await screen.findByRole('heading', { level: 1, name: '개인정보처리방침' })).toBeDefined();
  expect(where()).toBe('/privacy');
  fireEvent.click(within(footer()).getByRole('link', { name: '이용약관' }));
  expect(await screen.findByRole('heading', { level: 1, name: '이용약관' })).toBeDefined();
  expect(where()).toBe('/terms');
  fireEvent.click(screen.getByRole('link', { name: '탑신병자' }));
  await vi.waitFor(() => expect(where()).toBe('/')); // 읽기 화면은 닉네임 없이도 (017)
});

test('로그인 화면: 버튼 아래 동의 문구와 두 링크, 만 14세 이상 안내', async () => {
  start('/login');
  await screen.findByRole('heading', { name: '로그인 · 가입' });
  const consent = document.querySelector('.login-consent');
  expect(consent.textContent).toMatch(/이용약관과 개인정보처리방침에 동의하는 것으로 봅니다/);
  expect(consent.textContent).toMatch(/만 14세 이상만 가입할 수 있습니다/);
  expect(within(consent).getByRole('link', { name: '이용약관' }).getAttribute('href')).toBe('/terms');
  expect(within(consent).getByRole('link', { name: '개인정보처리방침' }).getAttribute('href')).toBe('/privacy');
});

test('지금 legal.js에는 빈칸이 없다 (배포 전 체크)', async () => {
  start('/privacy');
  await screen.findByRole('heading', { level: 1, name: '개인정보처리방침' });
  expect(document.querySelector('mark.fill-me')).toBeNull();
  expect(screen.getByText(/대한민국\(서울\), AWS ap-northeast-2/)).toBeDefined();
});

test('칭호 도감 문구: 약관 제4조의4, 방침의 수집·처리 기록·공개 정보, 시행일은 그대로', async () => {
  start('/terms');
  await screen.findByRole('heading', { level: 1, name: '이용약관' });
  const sec = screen.getByRole('heading', { name: '제4조의4 (칭호 도감)' }).closest('section');
  expect(sec.textContent).toMatch(/활동 칭호.*장인 칭호.*한정판 칭호/s);
  expect(sec.textContent).toMatch(/운영자가 직접 지급하고 회수/);
  expect(sec.textContent).toMatch(/기간이 끝나도 이미 받은 칭호는 유지/);
  expect(sec.textContent).toMatch(/부정한 방법으로 칭호를 얻은 것이 확인되면/);
  cleanup();
  start('/privacy');
  await screen.findByRole('heading', { level: 1, name: '개인정보처리방침' });
  const text = document.querySelector('article').textContent;
  expect(text).toMatch(/장인 칭호는 따로 기록하지 않고 장인 인증 상태로 표시/);
  expect(text).toMatch(/한정판 칭호 지급·회수.*메모는 최대 500자/);
  expect(text).toMatch(/한정판 칭호와 장인 칭호\(장인 표시\)도 다른 이용자에게 보일 수 있습니다/);
  expect(LEGAL.effectiveDate).toBe('2026-11-09');
});
