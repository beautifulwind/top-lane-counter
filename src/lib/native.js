import { Capacitor } from '@capacitor/core';

// 안드로이드·iOS 앱(Capacitor로 감싼 화면)으로 열렸는가 (SPEC 6-55).
// 웹사이트(브라우저·홈 화면에 추가한 PWA)에서는 false — 기존 동작 그대로.
// 앱에서는 화면 파일이 앱 안에 들어 있어 서비스 워커·[앱 설치]·새 버전 알림이 필요 없다(새 버전은 앱 업데이트로).
export function isNativeApp() {
  try {
    return Capacitor.isNativePlatform();
  } catch {
    return false;
  }
}

/**
 * iOS 앱인가 (SPEC 6-58: Apple 로그인은 iOS 앱에서만 보인다). 웹·안드로이드 앱은 false.
 */
export function isIosApp() {
  try {
    return Capacitor.isNativePlatform() && Capacitor.getPlatform?.() === 'ios';
  } catch {
    return false;
  }
}
