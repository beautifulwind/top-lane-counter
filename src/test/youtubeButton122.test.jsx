// 6-122: 장인 페이지 유튜브 버튼 — 빨강 알약 + 흰 재생 아이콘 + 「유튜브」, 같은 줄 버튼과 같은 모양, 외부 이동 확인 창 그대로
import { readFileSync } from 'node:fs';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from '../App';
import { fakeFetch } from './fakeDdragon';
import { TABLES } from './fakeSupabase';

const URL_ = 'https://www.youtube.com/@toptop';

beforeEach(() => {
  window.matchMedia = undefined;
  vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

test('빨강 버튼: 재생 아이콘 + 「유튜브」, 읽어 주는 이름 유지, 새 창 + 이동 확인 창', async () => {
  const b = TABLES.builds.find((x) => x.id === 102);
  b.author = { ...b.author, influencer: 'creator' };
  TABLES.profiles.push({ id: 'u-102', nickname: '탑고수', role: 'user', level: 7, main_title: null, influencer: 'creator' });
  TABLES.ext_links.push({ id: 790, owner_id: 'u-102', build_id: null, url: URL_, host: 'www.youtube.com', sort: 0 });
  render(<MemoryRouter initialEntries={['/u/u-102']}><AppRoutes /></MemoryRouter>);
  const link = await screen.findByRole('link', { name: '유튜브 @toptop (외부 사이트, 새 창)' });
  expect(link.className).toBe('ext-link btn yt-btn');
  expect(link.textContent).toBe('유튜브');
  expect(link.querySelector('svg.yt-icon').getAttribute('aria-hidden')).toBe('true');
  expect(link.getAttribute('href')).toBe(URL_);
  expect(link.getAttribute('target')).toBe('_blank');
  expect(link.getAttribute('rel')).toContain('noopener');
  fireEvent.click(link);
  expect(screen.getByRole('alertdialog').textContent).toContain(URL_);
});

test('모양: 버튼 줄은 같은 높이(44px)·글자 크기·알약, ⋮의 위 여백 제거, 색은 tokens.css', () => {
  const css = readFileSync('src/index.css', 'utf8');
  expect(css).toContain('.inf-btn-row .btn { min-height: 44px; border-radius: 999px; font-size: var(--fs-md); line-height: 1; }');
  expect(css).toContain('.inf-btn-row .more-btn { margin-top: 0; }');
  expect(css).toMatch(/\.inf-btn-row \.btn\.yt-btn:active:not\(:disabled\) \{[^}]*background: var\(--yt-red\); border-color: var\(--yt-red\); color: var\(--yt-on\);/);
  const tokens = readFileSync('src/styles/tokens.css', 'utf8');
  expect(tokens).toContain('--yt-red: #cc0000;');
  expect(tokens).toContain('--yt-on: #ffffff;');
});
