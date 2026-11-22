import { useCallback, useEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { useLocation } from 'react-router-dom';
import InfluencerSearch from './InfluencerSearch';
import { SearchIcon, XIcon } from './Icons';

const FOCUSABLE = 'a[href], button:not([disabled]), input, select, textarea, [tabindex]:not([tabindex="-1"])';

/**
 * 상단 바 돋보기 [장인 찾기] (SPEC 6-82, 예전 ☰ 메뉴 [장인찾기] 050을 옮김). 누구나 (로그인 전 포함).
 * 누르면 상단 바 바로 아래에 검색 칸(InfluencerSearch — 장인 닉네임 검색, 결과 → 장인 페이지, [내가 팔로우한 장인의 빌드 보기]).
 * 닫힘: 바깥 누르기, Esc, [X], 결과를 눌러 이동, 다른 화면으로 이동. 열리면 입력 칸으로 초점, 닫히면 돋보기로 돌아온다.
 * 앱(안드로이드) 뒤로가기는 role=dialog + aria-modal이라 lib/backButton이 Esc를 보내 먼저 닫는다 (이전 화면으로 가지 않음).
 * 상단 바의 뒤 흐림(backdrop-filter) 때문에 ☰ 메뉴처럼 body에 그린다.
 */
export default function TopSearch() {
  const [open, setOpen] = useState(false);
  const opener = useRef(null);
  const panel = useRef(null);
  const { pathname } = useLocation();

  const close = useCallback((backToButton = true) => {
    setOpen(false);
    if (backToButton) opener.current?.focus();
  }, []);

  // 다른 화면으로 가면 닫는다 (결과를 눌렀을 때 포함 — 초점은 새 화면이 가져간다)
  useEffect(() => { setOpen(false); }, [pathname]);

  const onKeyDown = (e) => {
    if (e.key === 'Escape') {
      e.stopPropagation();
      close();
      return;
    }
    if (e.key !== 'Tab') return;
    const items = [...(panel.current?.querySelectorAll(FOCUSABLE) ?? [])];
    if (items.length === 0) return;
    const first = items[0];
    const last = items[items.length - 1];
    if (e.shiftKey && document.activeElement === first) {
      e.preventDefault();
      last.focus();
    } else if (!e.shiftKey && document.activeElement === last) {
      e.preventDefault();
      first.focus();
    }
  };

  return (
    <>
      <button
        type="button" ref={opener} className="top-search-btn" aria-label="장인 찾기"
        aria-haspopup="dialog" aria-expanded={open} aria-controls={open ? 'top-search' : undefined}
        onClick={() => (open ? close() : setOpen(true))}
      >
        <SearchIcon size={22} />
      </button>
      {open && createPortal(
        <div className="top-search-layer">
          <div className="top-search-backdrop" aria-hidden="true" onClick={() => close()} />
          <div className="top-search-panel" id="top-search" role="dialog" aria-modal="true" aria-label="장인 찾기" ref={panel} onKeyDown={onKeyDown}>
            <div className="top-search-head">
              <strong>장인 찾기</strong>
              <button type="button" className="icon-btn" aria-label="장인 찾기 닫기" onClick={() => close()}><XIcon /></button>
            </div>
            <InfluencerSearch id="top-inf-search" onGo={() => close(false)} />
          </div>
        </div>,
        document.body,
      )}
    </>
  );
}
