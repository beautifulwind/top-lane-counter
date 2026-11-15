import { App } from '@capacitor/app';
import { isNativeApp } from './native';

// 안드로이드 뒤로가기 버튼 (앱에서만, SPEC 6-56). 웹(브라우저·PWA)은 브라우저가 처리하므로 그대로 둔다.
// 순서: ① 열린 메뉴·확인 창·팝업이 있으면 닫기 → ② 이전 화면으로 → ③ 첫 화면이면 앱 종료.

/**
 * 뒤로가기로 닫을 수 있는 떠 있는 창. 모두 Esc로 닫히게 만들어져 있어, 맨 위 창에 Esc를 보내 닫는다
 * (진행 중(busy)이면 각 창이 Esc를 무시하는 것도 그대로 따른다).
 * - ☰ 메뉴(.menu-panel), 빌드 기여자 목록 등 모달(role=dialog, aria-modal)
 * - 외부 링크 나가기·장인 지정 확인 창(role=alertdialog, aria-modal)
 * - ⋮ 메뉴(.more-panel, 안의 [지우기] 확인 포함), 사진 크게 보기(.media-viewer), 로그인 화면의 계정 연결 창(.guest-dialog)
 * 글·댓글 고치기 같은 화면 안 입력 칸은 닫지 않는다(쓰던 내용이 뒤로가기 한 번에 사라지지 않게) → 이전 화면으로 간다.
 */
export const BACK_CLOSABLE = [
  '[role="dialog"][aria-modal="true"]',
  '[role="alertdialog"][aria-modal="true"]',
  '.more-panel',
  '.media-viewer',
  '.guest-dialog',
].join(', ');

/** 맨 위(문서에서 가장 나중)의 떠 있는 창에 Esc를 보낸다. 창이 있었으면 true. */
export function closeTopOverlay(doc = document) {
  const open = [...doc.querySelectorAll(BACK_CLOSABLE)];
  const top = open[open.length - 1];
  if (!top) return false;
  const target = top.contains(doc.activeElement) ? doc.activeElement : top;
  target.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', code: 'Escape', bubbles: true, cancelable: true }));
  return true;
}

/** 뒤로가기 한 번 처리. 무엇을 했는지 돌려준다: 'closed' | 'back' | 'exit' */
export function handleBackButton({ canGoBack }, { doc = document, history = window.history, exitApp = () => App.exitApp() } = {}) {
  if (closeTopOverlay(doc)) return 'closed';
  if (canGoBack) {
    history.back();
    return 'back';
  }
  exitApp();
  return 'exit';
}

/** 앱에서만 뒤로가기 버튼을 잡는다. 잡았으면 true (웹은 false — 브라우저 기본 동작 그대로). */
export function startBackButton(native = isNativeApp(), app = App) {
  if (!native) return false;
  app.addListener('backButton', (e) => handleBackButton(e, { exitApp: () => app.exitApp() }));
  return true;
}
