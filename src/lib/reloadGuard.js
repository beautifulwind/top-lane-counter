// 새 버전 배포 뒤 옛 조각 파일을 못 받았을 때의 자동 새로고침 표시 (App.jsx lazyPage가 쓴다).
// 화면의 [새로고침](새 버전 알림)은 새로고침 직전에 이 표시를 지워, 그 뒤에도 안전장치가 한 번 더 쓸 수 있게 한다.
export const CHUNK_RELOAD_KEY = 'tlc:chunk-reloaded';
