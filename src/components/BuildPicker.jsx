import { useEffect, useRef } from 'react';
import BuildTitle from './BuildTitle';
import { ThumbIcon } from './Icons';

/**
 * 빌드 [더보기] 창 (6-77): 상대법 빌드 탭이 화면 밖으로 넘칠 때 빌드 전부를 세로 목록으로 보여 주고 고르게 한다.
 * - 폰(좁은 화면)은 바닥에서 올라오는 창, PC는 가운데 작은 창 (index.css `.dialog-backdrop.sheet`). 목록만 스크롤된다.
 * - 줄마다 탭과 같은 BuildTitle(장인 빌드면 앞에 "장인 빌드") + 추천 수. 지금 고른 빌드는 ✓·강조·aria-current.
 * - 열면 지금 고른 빌드에 초점(목록이 길면 그 줄까지 스크롤). ↑↓·Home·End로 옮기고 Enter·Space로 고른다.
 * - Esc·바깥 누르기·[닫기]로 닫힌다. Tab은 창 안에서만 돈다. 초점을 어디로 돌려줄지는 연 쪽(BuildTabs)이 정한다.
 */
export default function BuildPicker({ builds, selectedId, onPick, onClose }) {
  const panel = useRef(null);
  const items = useRef({});

  useEffect(() => {
    const el = items.current[selectedId] ?? Object.values(items.current)[0];
    el?.focus();
    el?.scrollIntoView?.({ block: 'nearest' });
    // 처음 열 때만 (고르면 창이 닫힌다)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const onKeyDown = (e) => {
    if (e.key === 'Escape') {
      e.stopPropagation();
      onClose();
      return;
    }
    const list = builds.map((b) => items.current[b.id]).filter(Boolean);
    const at = list.indexOf(document.activeElement);
    if (at >= 0) {
      const to = { ArrowDown: at + 1, ArrowUp: at - 1, Home: 0, End: list.length - 1 }[e.key];
      if (to !== undefined) {
        e.preventDefault();
        list[Math.min(list.length - 1, Math.max(0, to))].focus();
        return;
      }
    }
    if (e.key !== 'Tab') return;
    // 초점을 창 안에 가둔다
    const all = [...panel.current.querySelectorAll('button')].filter((el) => !el.disabled);
    const first = all[0];
    const last = all[all.length - 1];
    if (e.shiftKey && document.activeElement === first) {
      e.preventDefault();
      last.focus();
    } else if (!e.shiftKey && document.activeElement === last) {
      e.preventDefault();
      first.focus();
    }
  };

  return (
    // 바깥(어두운 바탕)을 누르면 닫힌다. 키보드는 Esc·[닫기]
    // eslint-disable-next-line jsx-a11y/click-events-have-key-events, jsx-a11y/no-static-element-interactions
    <div className="dialog-backdrop sheet" onClick={(e) => e.target === e.currentTarget && onClose()}>
      <div ref={panel} className="dialog-panel build-picker" role="dialog" aria-modal="true" aria-labelledby="build-picker-title" onKeyDown={onKeyDown}>
        <h2 id="build-picker-title" className="dialog-title">빌드 고르기 <span className="muted">({builds.length}개)</span></h2>
        <ul className="build-picker-list">
          {builds.map((b, i) => {
            const on = b.id === selectedId;
            return (
              <li key={b.id}>
                <button
                  ref={(el) => { items.current[b.id] = el; }}
                  type="button"
                  className={on ? 'build-pick on' : 'build-pick'}
                  aria-current={on ? 'true' : undefined}
                  onClick={() => onPick(b.id)}
                >
                  <span className="build-pick-check" aria-hidden="true">{on ? '✓' : ''}</span>
                  <span className="build-pick-name"><BuildTitle build={b} index={i} /></span>
                  <span className="build-tab-ups">
                    <ThumbIcon size={14} /><span className="sr-only">추천 </span>{b.up}
                  </span>
                  {on && <span className="sr-only"> (지금 보는 빌드)</span>}
                </button>
              </li>
            );
          })}
        </ul>
        <div className="actions build-picker-actions">
          <button type="button" className="btn" onClick={onClose}>닫기</button>
        </div>
      </div>
    </div>
  );
}
