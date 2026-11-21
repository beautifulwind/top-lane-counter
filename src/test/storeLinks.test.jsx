import { afterEach, describe, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';

const cap = vi.hoisted(() => ({ native: false }));
vi.mock('@capacitor/core', () => ({ Capacitor: { isNativePlatform: () => cap.native } }));

const { default: StoreLinks } = await import('../components/StoreLinks');
const { APP_STORE_URL, INSTAGRAM_URL } = await import('../lib/storeLinks');

afterEach(() => { cleanup(); cap.native = false; });

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

  test('네이티브 앱(iOS·Android)에서는 아무것도 그리지 않는다', () => {
    cap.native = true;
    const { container } = render(<StoreLinks />);
    expect(container.innerHTML).toBe('');
  });
});
