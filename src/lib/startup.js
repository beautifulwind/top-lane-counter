import { captureInstallPrompt } from './install';
import { registerServiceWorker } from './sw';
import { isNativeApp } from './native';

/**
 * 앱 시작 때 웹사이트에서만 켜는 것 (index.jsx, SPEC 6-55). 켰으면 true.
 * - [앱 설치] 메뉴용 설치 창 이벤트 잡기
 * - 서비스 워커: 화면 파일 저장·오프라인 안내·새 버전 알림·웹 푸시 (프로덕션 빌드에서만)
 * 앱(Capacitor)에서는 둘 다 끈다 → [앱 설치]는 숨김('none') 그대로, 새 버전 알림도 뜨지 않는다.
 */
export function startWebOnlyFeatures(native = isNativeApp()) {
  if (native) return false;
  captureInstallPrompt();
  registerServiceWorker();
  return true;
}
