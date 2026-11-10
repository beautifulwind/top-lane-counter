// 웹 푸시 — 이 기기에서 알림을 켤 수 있는가 (SPEC 6-24, 037)
// - 안드로이드: 크롬 등 푸시를 지원하는 브라우저면 바로 켤 수 있다 (홈 화면 설치는 없어도 됨)
// - 아이폰·아이패드: iOS 16.4 이상에서 "홈 화면에 추가"한 앱으로 열었을 때만 된다 (Safari 탭에서는 안 됨)
// - 서비스 워커는 프로덕션 빌드에서만 켜지므로(src/lib/sw.js) 개발 서버에서는 켤 수 없다
import { isIos, isStandalone } from './install';

/**
 * 순수 판정: 'ok' | 'ios-browser'(홈 화면 앱이 아님) | 'ios-old'(iOS 16.4 미만) | 'unsupported' | 'denied'(차단됨) | 'dev'
 */
export function pushSupport({ ios, standalone, hasPush, permission, prod }) {
  if (ios && !standalone) return 'ios-browser';
  if (!hasPush) return ios ? 'ios-old' : 'unsupported';
  if (!prod) return 'dev';
  if (permission === 'denied') return 'denied';
  return 'ok';
}

export function currentPushSupport() {
  const hasPush = typeof window !== 'undefined' && 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;
  return pushSupport({
    ios: isIos(),
    standalone: isStandalone(),
    hasPush,
    permission: hasPush ? Notification.permission : 'default',
    prod: import.meta.env.PROD,
  });
}

/** 켤 수 없을 때 보여 줄 안내 */
export const PUSH_HELP = {
  'ios-browser': '아이폰·아이패드는 홈 화면에 추가한 앱에서만 알림을 받을 수 있습니다 (iOS 16.4 이상). Safari 아래쪽 공유 버튼 → [홈 화면에 추가]를 누른 뒤, 홈 화면의 탑신병자 아이콘으로 열어 여기서 켜 주세요.',
  'ios-old': '알림은 iOS 16.4 이상에서 받을 수 있습니다. 설정 → 일반 → 소프트웨어 업데이트에서 iOS를 업데이트한 뒤 다시 열어 주세요.',
  unsupported: '이 브라우저는 알림을 지원하지 않습니다. 안드로이드는 크롬에서, 아이폰은 홈 화면에 추가한 앱에서 켤 수 있습니다.',
  denied: '이 사이트의 알림이 차단돼 있습니다. 휴대폰 설정(또는 브라우저의 사이트 설정)에서 탑신병자 알림을 허용한 뒤 다시 열어 주세요.',
  dev: '개발 서버에서는 알림을 켤 수 없습니다. 배포된 사이트에서 켜 주세요.',
};

/** VAPID 공개 키(base64url 글자) → 브라우저가 받는 바이트 */
export function keyBytes(base64url) {
  const pad = '='.repeat((4 - (base64url.length % 4)) % 4);
  const raw = atob((base64url + pad).replace(/-/g, '+').replace(/_/g, '/'));
  return Uint8Array.from(raw, (c) => c.charCodeAt(0));
}
