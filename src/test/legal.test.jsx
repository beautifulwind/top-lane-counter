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
  expect(screen.getByRole('heading', { name: '9. 회원 탈퇴(계정 삭제) 요청' })).toBeDefined();
  expect(screen.getByText(/만 14세 미만 아동의 회원 가입을 받지 않습니다/)).toBeDefined();
});

test('닉네임을 아직 안 정한 로그인 상태에서도 두 페이지는 닉네임 설정으로 끌려가지 않는다', async () => {
  fakeLogin('u-new'); // 닉네임 없음
  start('/privacy');
  expect(await screen.findByRole('heading', { level: 1, name: '개인정보처리방침' })).toBeDefined();
  expect(where()).toBe('/privacy');
  fireEvent.click(within(footer()).getByRole('link', { name: '이용약관' }));
  expect(await screen.findByRole('heading', { level: 1, name: '이용약관' })).toBeDefined();
  expect(where()).toBe('/terms');
  fireEvent.click(screen.getByRole('link', { name: '탑 카운터 위키' }));
  await vi.waitFor(() => expect(where()).toBe('/welcome')); // 다른 페이지는 그대로 닉네임 설정으로
});

test('로그인 화면: 버튼 아래 동의 문구와 두 링크, 만 14세 이상 안내', async () => {
  start('/login');
  await screen.findByRole('heading', { name: '로그인 · 가입' });
  const consent = document.querySelector('.login-consent');
  expect(consent.textContent).toMatch(/이용약관과 개인정보처리방침에 동의하는 것으로 봐요/);
  expect(consent.textContent).toMatch(/만 14세 이상만 가입할 수 있어요/);
  expect(within(consent).getByRole('link', { name: '이용약관' }).getAttribute('href')).toBe('/terms');
  expect(within(consent).getByRole('link', { name: '개인정보처리방침' }).getAttribute('href')).toBe('/privacy');
});

test('지금 legal.js에는 빈칸이 없다 (배포 전 체크)', async () => {
  start('/privacy');
  await screen.findByRole('heading', { level: 1, name: '개인정보처리방침' });
  expect(document.querySelector('mark.fill-me')).toBeNull();
  expect(screen.getByText(/대한민국\(서울\), AWS ap-northeast-2/)).toBeDefined();
});
