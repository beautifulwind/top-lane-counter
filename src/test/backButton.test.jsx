import { afterEach, describe, expect, test, vi } from 'vitest';
import { useState } from 'react';
import { MemoryRouter } from 'react-router-dom';
import { act, cleanup, fireEvent, render, screen } from '@testing-library/react';

// 안드로이드 뒤로가기 (앱에서만, SPEC 6-56): 열린 창 닫기 → 이전 화면 → 첫 화면이면 종료
vi.mock('@capacitor/app', () => ({ App: { addListener: vi.fn(), exitApp: vi.fn() } }));
vi.mock('@capacitor/core', () => ({ Capacitor: { isNativePlatform: () => false } }));

const { handleBackButton, startBackButton } = await import('../lib/backButton');
const { default: MoreMenu } = await import('../components/MoreMenu');

afterEach(cleanup);

const deps = () => ({ history: { back: vi.fn() }, exitApp: vi.fn() });
const press = (e, d) => { let r; act(() => { r = handleBackButton(e, d); }); return r; };

// Esc로 닫히는 모달 하나 (실제 창들과 같은 방식)
function Modal({ name }) {
  const [open, setOpen] = useState(true);
  if (!open) return null;
  return (
    <div role="dialog" aria-modal="true" aria-label={name} onKeyDown={(e) => e.key === 'Escape' && setOpen(false)}>
      <button type="button">{name} 안 버튼</button>
    </div>
  );
}

describe('handleBackButton', () => {
  test('⋮ 메뉴가 열려 있으면 닫기만 한다 (이전 화면으로 가지 않음)', () => {
    render(<MemoryRouter><MoreMenu items={[{ label: '신고', onSelect: () => {} }]} /></MemoryRouter>);
    fireEvent.click(screen.getByRole('button', { name: '더보기' }));
    expect(screen.getByRole('menu')).toBeDefined();
    const d = deps();
    expect(press({ canGoBack: true }, d)).toBe('closed');
    expect(screen.queryByRole('menu')).toBeNull();
    expect(d.history.back).not.toHaveBeenCalled();
    expect(d.exitApp).not.toHaveBeenCalled();
  });

  test('⋮ 메뉴 안 [지우기] 확인을 묻는 중이면 그 확인을 닫는다', () => {
    render(<MemoryRouter><MoreMenu items={[{ label: '지우기', onSelect: () => {}, confirm: '지울까요?' }]} /></MemoryRouter>);
    fireEvent.click(screen.getByRole('button', { name: '더보기' }));
    fireEvent.click(screen.getByRole('menuitem', { name: '지우기' }));
    expect(screen.getByText('지울까요?')).toBeDefined();
    expect(press({ canGoBack: true }, deps())).toBe('closed');
    expect(screen.queryByText('지울까요?')).toBeNull();
  });

  test('창이 겹쳐 있으면 맨 위 것부터 하나씩 닫는다', () => {
    render(<><Modal name="아래 창" /><Modal name="위 창" /></>);
    expect(press({ canGoBack: true }, deps())).toBe('closed');
    expect(screen.queryByRole('dialog', { name: '위 창' })).toBeNull();
    expect(screen.getByRole('dialog', { name: '아래 창' })).toBeDefined();
    expect(press({ canGoBack: true }, deps())).toBe('closed');
    expect(screen.queryByRole('dialog')).toBeNull();
  });

  test('열린 창이 없으면 이전 화면으로', () => {
    const d = deps();
    expect(press({ canGoBack: true }, d)).toBe('back');
    expect(d.history.back).toHaveBeenCalledTimes(1);
    expect(d.exitApp).not.toHaveBeenCalled();
  });

  test('첫 화면(돌아갈 곳 없음)이면 앱 종료', () => {
    const d = deps();
    expect(press({ canGoBack: false }, d)).toBe('exit');
    expect(d.exitApp).toHaveBeenCalledTimes(1);
    expect(d.history.back).not.toHaveBeenCalled();
  });
});

describe('startBackButton', () => {
  test('웹: 뒤로가기를 잡지 않는다 (브라우저 기본 동작 그대로)', () => {
    const app = { addListener: vi.fn(), exitApp: vi.fn() };
    expect(startBackButton(false, app)).toBe(false);
    expect(app.addListener).not.toHaveBeenCalled();
  });

  test('앱: backButton을 잡고, 첫 화면에서 누르면 종료한다', () => {
    const app = { addListener: vi.fn(), exitApp: vi.fn() };
    expect(startBackButton(true, app)).toBe(true);
    expect(app.addListener).toHaveBeenCalledWith('backButton', expect.any(Function));
    app.addListener.mock.calls[0][1]({ canGoBack: false });
    expect(app.exitApp).toHaveBeenCalledTimes(1);
  });

  test('기본값: 웹(isNativeApp false)이면 잡지 않는다', () => {
    expect(startBackButton()).toBe(false);
  });
});
