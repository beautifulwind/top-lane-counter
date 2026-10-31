import { afterEach, expect, test, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { AppRoutes } from './App';
import { RIOT_NOTICE } from './components/Layout';

afterEach(() => vi.restoreAllMocks());

test('모든 페이지 하단에 라이엇 고지 문구가 있다', () => {
  vi.spyOn(globalThis, 'fetch').mockReturnValue(new Promise(() => {}));
  vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
  for (const path of ['/', '/champion/Darius', '/champion/Darius/counter/Quinn', '/없는-페이지']) {
    const { unmount } = render(
      <MemoryRouter initialEntries={[path]}>
        <AppRoutes />
      </MemoryRouter>,
    );
    expect(screen.getByText(RIOT_NOTICE)).toBeDefined();
    unmount();
  }
});
