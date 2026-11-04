import { useCallback, useEffect, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { Link, useLocation } from 'react-router-dom';
import { signOut } from '../api/auth';
import { getMyUnreadNotifications, onNotificationsChanged } from '../api/proposals';
import { isGuest, useAuth } from '../lib/auth';
import { isCurrentNav, navItemsFor } from '../lib/navItems';
import { MenuIcon, MessageIcon, ShieldIcon, UserIcon, XIcon } from './Icons';
import UserName from './UserName';

/**
 * 계정 종류. 메뉴(와 나중의 아래 탭 바)가 이 값 하나로 항목을 정한다.
 * 'loading'(로그인 확인·프로필 읽는 중 — 메뉴 항목 없음) | 'signedOut' | 'guest'(비회원: 로그아웃 없음) | 'noNickname'(로그인했지만 닉네임 전) | 'member' | 'operator'
 */
export function accountKind(auth) {
  if (auth.status === 'loading') return 'loading';
  if (auth.status !== 'signedIn') return 'signedOut';
  if (auth.profile === undefined) return 'loading'; // 로그인은 됐고 프로필을 읽는 중
  if (isGuest(auth)) return 'guest';
  if (!auth.profile?.nickname) return 'noNickname';
  return auth.isOperator ? 'operator' : 'member';
}

export const logout = () => signOut().catch((e) => alert(e.message));

const ICONS = { user: UserIcon, message: MessageIcon, shield: ShieldIcon };

/**
 * 안 읽은 알림 개수 (빨간 점). 페이지를 옮길 때와 읽음 처리했을 때 다시 센다.
 * 마이페이지에서 알림을 확인하면 꺼진다.
 */
function useUnreadCount(userId, pathname) {
  const [count, setCount] = useState(0);
  const [changed, setChanged] = useState(0);
  useEffect(() => {
    const off = onNotificationsChanged(() => setChanged((n) => n + 1));
    return off; // 구독 해제
  }, []);
  useEffect(() => {
    if (!userId) return undefined;
    let alive = true;
    getMyUnreadNotifications(userId).then((rows) => alive && setCount(rows.length), () => {}); // 알림은 실패해도 조용히
    return () => { alive = false; };
  }, [userId, pathname, changed]);
  return userId ? count : 0;
}

const FOCUSABLE = 'a[href], button:not([disabled]), input, select, textarea, [tabindex]:not([tabindex="-1"])';

/**
 * 상단 바 오른쪽 ☰ + 오른쪽에서 나오는 메뉴 패널 (SPEC 3장 상단 바·메뉴). PC·폰 같은 방식.
 * - 패널 맨 위: 닉네임·Level·칭호(비회원 표시) / 로그인 전 [로그인 · 가입] / 닉네임 전 [닉네임 정하기]
 * - 항목: src/lib/navItems.js (마이페이지●·자유게시판·관리(운영자, 보라)), 맨 아래 [로그아웃](비회원·로그인 전에는 없음)
 * - 새 알림 빨간 점: ☰와 메뉴의 마이페이지 둘 다
 * - 닫힘: 바깥 누르기, Esc, [X], 항목을 눌러 이동, 로그아웃. 열리면 초점이 패널 안으로, 닫히면 ☰로 돌아온다
 * 상단 바에 뒤 흐림(backdrop-filter)이 있어 그 안의 fixed가 바에 갇히므로 패널은 body에 그린다.
 */
export default function SiteMenu() {
  const auth = useAuth();
  const { pathname, search } = useLocation();
  const kind = accountKind(auth);
  const named = !!auth.profile?.nickname;
  const unread = useUnreadCount(named ? auth.user?.id : null, pathname);
  const [open, setOpen] = useState(false);
  const opener = useRef(null);
  const panel = useRef(null);

  const close = useCallback((backToButton = true) => {
    setOpen(false);
    if (backToButton) opener.current?.focus();
  }, []);

  // 열린 동안 뒤 화면 스크롤 막기
  useEffect(() => {
    if (!open) return undefined;
    const before = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    return () => { document.body.style.overflow = before; };
  }, [open]);
  // 초점을 패널 안 첫 항목으로 ([X] 다음). 로그인 확인 중에 열었으면 항목이 생길 때 다시
  useEffect(() => {
    if (!open || !panel.current) return;
    const items = panel.current.querySelectorAll(FOCUSABLE);
    const now = document.activeElement;
    if (panel.current.contains(now) && now !== items[0]) return; // 이미 패널 안 다른 곳에 있으면 그대로
    (items[1] ?? items[0])?.focus();
  }, [open, kind]);

  const onKeyDown = (e) => {
    if (e.key === 'Escape') {
      e.stopPropagation();
      close();
      return;
    }
    if (e.key !== 'Tab') return;
    // Tab이 패널 밖으로 나가지 않게 (처음 ↔ 끝)
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

  const go = () => close(false); // 항목을 눌러 이동: 초점은 새 페이지가 가져간다
  const canLogout = kind === 'member' || kind === 'operator' || kind === 'noNickname';

  return (
    <>
      <button
        type="button" ref={opener} className="menu-btn" onClick={() => setOpen(true)}
        aria-label={unread > 0 ? `메뉴 열기, 새 알림 ${unread}개` : '메뉴 열기'}
        aria-haspopup="dialog" aria-expanded={open} aria-controls={open ? 'site-menu' : undefined}
      >
        <MenuIcon size={24} />
        {unread > 0 && <span className="alert-dot" aria-hidden="true" />}
      </button>
      {open && createPortal(
        <div className="menu-layer">
          <div className="menu-backdrop" aria-hidden="true" onClick={() => close()} />
          <div
            className="menu-panel" id="site-menu" role="dialog" aria-modal="true" aria-label="메뉴"
            ref={panel} onKeyDown={onKeyDown}
          >
            <div className="menu-head">
              <button type="button" className="icon-btn menu-close" aria-label="메뉴 닫기" onClick={() => close()}>
                <XIcon />
              </button>
            </div>
            <MenuAccount auth={auth} kind={kind} from={pathname + search} onGo={go} />
            <nav aria-label="메뉴 항목">
              <ul className="menu-list">
                {navItemsFor('menu', kind).map((it) => {
                  const Icon = ICONS[it.icon];
                  const here = isCurrentNav(it, pathname);
                  const dot = it.dot === 'unread' && unread > 0;
                  return (
                    <li key={it.key}>
                      <Link
                        to={it.to} onClick={go}
                        className={['menu-item', it.tone === 'op' && 'op-link', here && 'on'].filter(Boolean).join(' ')}
                        aria-current={here ? 'page' : undefined}
                        aria-label={dot ? `${it.label}, 새 알림 ${unread}개` : undefined}
                      >
                        {Icon && <Icon size={20} className="menu-icon" />}
                        <span className="menu-label">{it.label}</span>
                        {dot && <span className="alert-dot" aria-hidden="true" title={`새 알림 ${unread}개`} />}
                      </Link>
                    </li>
                  );
                })}
              </ul>
            </nav>
            {canLogout && (
              <div className="menu-foot">
                <button type="button" className="menu-item menu-logout" onClick={() => { close(); logout(); }}>
                  로그아웃
                </button>
              </div>
            )}
          </div>
        </div>,
        document.body,
      )}
    </>
  );
}

/** 패널 맨 위: 누가 로그인했는지 (또는 로그인·닉네임 정하기 버튼) */
function MenuAccount({ auth, kind, from, onGo }) {
  if (kind === 'loading') return null;
  if (kind === 'signedOut') {
    return (
      <div className="menu-account">
        <Link to="/login" state={{ from }} className="btn btn-primary menu-login" onClick={onGo}>로그인 · 가입</Link>
      </div>
    );
  }
  if (kind === 'noNickname') {
    return (
      <div className="menu-account">
        <p className="menu-account-note">닉네임을 아직 정하지 않았습니다.</p>
        <Link to="/welcome" state={{ from }} className="btn btn-primary menu-login" onClick={onGo}>닉네임 정하기</Link>
      </div>
    );
  }
  if (!auth.profile) return null; // 프로필을 읽는 중
  // 운영자도 역할 글자 없이 "Lv.0 닉네임"으로만 표시 (SPEC 3장). 글자만 — 누르는 동작 없음
  return (
    <div className="menu-account">
      <p className="menu-user"><UserName profile={auth.profile} /></p>
    </div>
  );
}
