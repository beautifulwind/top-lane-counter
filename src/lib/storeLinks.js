// 스토어·인스타그램 이동 주소 (SPEC 6-70).
// 구글 플레이 출시 후 아래 PLAY_STORE_URL 한 줄만 채우면 [Google Play] 버튼이 링크로 바뀐다.
// 값: https://play.google.com/store/apps/details?id=com.topsinbyeongja.app
export const PLAY_STORE_URL = '';
export const APP_STORE_URL = 'https://apps.apple.com/kr/app/id6835358085';
export const INSTAGRAM_URL = 'https://www.instagram.com/topsinbyeongza';

// 앱 업데이트 안내 배너(6-99)가 [업데이트]로 보내는 곳. Play 주소가 비어 있으면(위 PLAY_STORE_URL 출시 전) 패키지 이름으로 만든 주소를 쓴다.
export const PLAY_STORE_FALLBACK_URL = 'https://play.google.com/store/apps/details?id=com.topsinbyeongja.app';
export const storeUrlFor = (platform) => (platform === 'ios' ? APP_STORE_URL : platform === 'android' ? (PLAY_STORE_URL || PLAY_STORE_FALLBACK_URL) : '');
