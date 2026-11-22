import { afterEach, describe, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';

const cap = vi.hoisted(() => ({ native: false }));
vi.mock('@capacitor/core', () => ({ Capacitor: { isNativePlatform: () => cap.native } }));

const { default: StoreLinks } = await import('../components/StoreLinks');
const { AppRoutes } = await import('../App');
const { fakeFetch } = await import('./fakeDdragon');
const { APP_STORE_URL, INSTAGRAM_URL } = await import('../lib/storeLinks');

afterEach(() => { cleanup(); vi.restoreAllMocks(); cap.native = false; });

describe('스토어 이동 버튼 (SPEC 6-70)', () => {
  test('웹: 세 버튼이 보이고 App Store·인스타그램은 새 탭 링크', () => {
    render(<StoreLinks />);
    const apple = screen.getByRole('link', { name: /App Store/ });
    expect(apple.getAttribute('href')).toBe(APP_STORE_URL);
    expect(apple.getAttribute('target')).toBe('_blank');
    expect(apple.getAttribute('rel')).toBe('noopener noreferrer');
    const ig = screen.getByRole('link', { name: /인스타그램/ });
    expect(ig.getAttribute('href')).toBe(INSTAGRAM_URL);
    expect(ig.getAttribute('target')).toBe('_blank');
    expect(ig.getAttribute('rel')).toBe('noopener noreferrer');
  });

  test('Google Play는 주소가 비어 있으면 이동 없이 "준비 중입니다"', () => {
    render(<StoreLinks size="sm" />);
    fireEvent.click(screen.getByRole('button', { name: /Google Play/ }));
    expect(screen.getByRole('status').textContent).toBe('준비 중입니다');
  });

  test('네이티브 앱(iOS·Android): 스토어 배지는 없고 작은 단색 [인스타그램] 링크만 (6-78)', () => {
    cap.native = true;
    const { container } = render(<StoreLinks />);
    expect(screen.queryByText(/Google Play|App Store/)).toBeNull();
    expect(screen.queryByRole('button')).toBeNull();
    expect(container.querySelector('.store-pill')).toBeNull();
    const ig = screen.getByRole('link', { name: '인스타그램' });
    expect(ig.getAttribute('href')).toBe(INSTAGRAM_URL);
    expect(ig.getAttribute('target')).toBe('_blank');
    expect(ig.getAttribute('rel')).toBe('noopener noreferrer');
    expect(container.querySelector('linearGradient, [fill*="url("]')).toBeNull(); // 공식 그라데이션 로고 아님
  });

  test('네이티브 앱의 작은 변형(size="sm", 로그인 창)은 예전처럼 아무것도 그리지 않는다', () => {
    cap.native = true;
    const { container } = render(<StoreLinks size="sm" />);
    expect(container.innerHTML).toBe('');
  });

  describe('배치', () => {
    const start = (path) => {
      vi.spyOn(globalThis, 'fetch').mockImplementation(fakeFetch());
      vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
      render(<MemoryRouter initialEntries={[path]}><AppRoutes /></MemoryRouter>);
    };

    test('다른 페이지 푸터에는 묶음이 있다', async () => {
      start('/terms');
      await screen.findByRole('heading', { level: 1, name: '이용약관' });
      expect(within(screen.getByRole('contentinfo')).getByRole('link', { name: /App Store/ })).toBeDefined();
    });

    test('로그인 화면: 푸터에는 없고 로그인 창 안의 작은 묶음만 한 개 있다', async () => {
      start('/login');
      await screen.findByRole('heading', { level: 1, name: /로그인/ });
      expect(within(screen.getByRole('contentinfo')).queryByRole('link', { name: /App Store/ })).toBeNull();
      expect(screen.getAllByRole('link', { name: /App Store/ })).toHaveLength(1);
      expect(document.querySelector('.login-card .store-links-sm')).not.toBeNull();
    });

    test('네이티브 앱 로그인 화면: 인스타그램 링크도 없다 (예전 그대로)', async () => {
      cap.native = true;
      start('/login');
      await screen.findByRole('heading', { level: 1, name: /로그인/ });
      expect(screen.queryByRole('link', { name: /App Store/ })).toBeNull();
      expect(screen.queryByRole('link', { name: /인스타그램/ })).toBeNull();
    });

    test('네이티브 앱 다른 화면 푸터: 인스타그램 링크만 있다', async () => {
      cap.native = true;
      start('/terms');
      await screen.findByRole('heading', { level: 1, name: '이용약관' });
      const footer = within(screen.getByRole('contentinfo'));
      expect(footer.getByRole('link', { name: '인스타그램' })).toBeDefined();
      expect(footer.queryByRole('link', { name: /App Store/ })).toBeNull();
      expect(footer.queryByText(/Google Play/)).toBeNull();
    });
  });
});
