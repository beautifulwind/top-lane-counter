import { useEffect, useId, useRef, useState } from 'react';
import { Link } from 'react-router-dom';

/**
 * 공용 ⋮ 메뉴 (빌드·상대법, 3단계부터 글·댓글).
 * items: [{ label, onSelect?, to?, danger?, op?, disabled?, hint?, confirm? }]
 *   - to: 누르면 그 주소로 이동 (링크) / onSelect: 누르면 부를 함수
 *   - danger: 지우기 같은 되돌리기 어려운 일 → 빨간 글자 / op: 운영진만 보이는 일 → 보라 글자
 *   - confirm: 문구를 주면 바로 하지 않고 메뉴 안에서 한 번 더 묻는다 ([취소]에 초점)
 *   - disabled + hint: 지금은 할 수 없는 일 (이유를 같이 보여 준다)
 * 보일 항목이 하나도 없으면 ⋮ 버튼도 그리지 않는다.
 * 키보드: ↑↓·Home·End로 항목 이동, Enter·Space로 고르기, Esc로 닫고 ⋮ 버튼으로 초점. 바깥을 누르거나 Tab으로 나가도 닫힌다.
 */
export default function MoreMenu({ items, label = '더보기' }) {
  const shown = (items ?? []).filter(Boolean);
  const [open, setOpen] = useState(false);
  const [asking, setAsking] = useState(null); // confirm을 묻는 중인 항목
  const box = useRef(null);
  const button = useRef(null);
  const panel = useRef(null);
  const id = useId();

  const close = (focusButton = false) => {
    setOpen(false);
    setAsking(null);
    if (focusButton) button.current?.focus();
  };

  // 바깥을 누르면 닫는다
  useEffect(() => {
    if (!open) return undefined;
    const onDown = (e) => {
      if (!box.current?.contains(e.target)) close(false);
    };
    document.addEventListener('pointerdown', onDown);
    document.addEventListener('mousedown', onDown);
    return () => {
      document.removeEventListener('pointerdown', onDown);
      document.removeEventListener('mousedown', onDown);
    };
  }, [open]);

  // 열리면 첫 항목에 초점 (묻는 중이면 [취소]에)
  useEffect(() => {
    if (!open) return;
    const first = panel.current?.querySelector(asking ? '[data-cancel]' : '[role="menuitem"]:not([aria-disabled="true"])');
    first?.focus();
  }, [open, asking]);

  if (shown.length === 0) return null;

  const menuItems = () => [...(panel.current?.querySelectorAll('[role="menuitem"]') ?? [])];
  const onKeyDown = (e) => {
    if (e.key === 'Escape') {
      e.preventDefault();
      e.stopPropagation();
      close(true);
      return;
    }
    if (e.key === 'Tab') {
      close(false);
      return;
    }
    if (asking) return;
    const list = menuItems();
    const at = list.indexOf(document.activeElement);
    const go = (i) => {
      e.preventDefault();
      list[(i + list.length) % list.length]?.focus();
    };
    if (e.key === 'ArrowDown') go(at + 1);
    else if (e.key === 'ArrowUp') go(at - 1);
    else if (e.key === 'Home') go(0);
    else if (e.key === 'End') go(list.length - 1);
  };

  const choose = (item) => {
    if (item.disabled) return;
    if (item.confirm && asking !== item) {
      setAsking(item);
      return;
    }
    close(true);
    item.onSelect?.();
  };

  const cls = (item) => ['more-item', item.danger && 'danger', item.op && 'op'].filter(Boolean).join(' ');

  return (
    <div className="more-menu" ref={box}>
      <button
        ref={button}
        type="button"
        className="more-btn"
        aria-label={label}
        aria-haspopup="menu"
        aria-expanded={open}
        aria-controls={open ? id : undefined}
        onClick={() => (open ? close(false) : setOpen(true))}
        onKeyDown={(e) => {
          if ((e.key === 'ArrowDown' || e.key === 'ArrowUp') && !open) {
            e.preventDefault();
            setOpen(true);
          }
        }}
      >
        <span aria-hidden="true">⋮</span>
      </button>
      {open && (
        <div ref={panel} id={id} className="more-panel" role={asking ? 'group' : 'menu'} aria-label={label} onKeyDown={onKeyDown}>
          {asking ? (
            <div className="more-confirm" role="alertdialog" aria-label={asking.label}>
              <p>{asking.confirm}</p>
              <div className="row-actions">
                <button type="button" className="btn btn-small" data-cancel onClick={() => close(true)}>취소</button>
                <button type="button" className={asking.danger ? 'btn btn-small btn-danger' : 'btn btn-small'} onClick={() => choose(asking)}>
                  {asking.label}
                </button>
              </div>
            </div>
          ) : (
            shown.map((item, i) => (
              <div key={item.label} className="more-row" role="none">
                {item.to && !item.disabled ? (
                  <Link to={item.to} role="menuitem" className={cls(item)} tabIndex={-1} onClick={() => close(false)}>
                    {item.label}
                  </Link>
                ) : (
                  <button
                    type="button"
                    role="menuitem"
                    className={cls(item)}
                    tabIndex={-1}
                    aria-disabled={item.disabled || undefined}
                    aria-describedby={item.hint ? `${id}-hint-${i}` : undefined}
                    onClick={() => choose(item)}
                  >
                    {item.label}
                  </button>
                )}
                {item.hint && <small className="hint more-hint" id={`${id}-hint-${i}`}>{item.hint}</small>}
              </div>
            ))
          )}
        </div>
      )}
    </div>
  );
}
