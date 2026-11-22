// 추천·비추천 안내 문장 (SPEC 6-79). 서버(DB)가 돌려주는 거절 사유를 이용자가 알아볼 문장으로 바꾼다.
// 서버 문구는 짧은 말투로 오므로 글 끝이 아니라 핵심 낱말로 알아본다.

export const MSG = {
  login: '로그인하면 추천할 수 있습니다.',
  nickname: '닉네임을 정하면 추천할 수 있습니다.',
  ownBuild: '내가 쓴 빌드에는 추천·비추천할 수 없습니다.',
  ownPost: '내가 쓴 글에는 추천할 수 없습니다.',
  notPublic: '지금은 공개되지 않은 빌드라 추천할 수 없습니다. 화면을 새로고침해 주세요.',
  postGone: '지워졌거나 숨겨진 글이라 추천할 수 없습니다.',
  guest: '비회원은 추천할 수 없습니다. 구글·카카오를 연결하면 할 수 있습니다.',
  network: '인터넷 연결이 불안정합니다. 잠시 뒤 다시 눌러 주세요.',
  denied: '추천할 권한이 없습니다. 로그인했는지 확인해 주세요.',
  stale: '추천을 처리하지 못했습니다. 화면을 새로고침한 뒤 다시 눌러 주세요.',
};

const RULES = [
  [/권한이 없습니다|permission denied|row-level security/i, MSG.denied],
  [/로그인이 필요/, MSG.login],
  [/닉네임을 정/, MSG.nickname],
  [/공개된 빌드에만/, MSG.notPublic],
  [/내 빌드에는/, MSG.ownBuild],
  [/내 글은/, MSG.ownPost],
  [/비회원은/, MSG.guest],
  [/추천할 수 없는 글|글을 찾지 못/, MSG.postGone],
  [/투표 값/, MSG.stale],
  [/failed to fetch|networkerror|load failed|network request failed|fetch failed/i, MSG.network],
];

/** 빌드 저장(북마크, 066) 안내 — 추천 버튼과 같은 방식(6-79) */
export const SAVE_MSG = {
  login: '로그인하면 빌드를 저장할 수 있습니다.',
  nickname: '닉네임을 정하면 빌드를 저장할 수 있습니다.',
  notPublic: '지금은 공개되지 않은 빌드라 저장할 수 없습니다. 화면을 새로고침해 주세요.',
  saved: '저장했습니다. 메뉴의 [내 목록 보기]에서 볼 수 있습니다.',
  unsaved: '저장을 해제했습니다.',
};

/** 서버·네트워크 오류 → 이용자 문장. 모르는 사유는 서버 문장을 그대로 덧붙인다(한글일 때만) */
export function voteErrorText(error) {
  const msg = String(error?.message ?? error ?? '');
  for (const [re, text] of RULES) if (re.test(msg)) return text;
  return /[가-힣]/.test(msg) ? `추천하지 못했습니다. ${msg}` : '추천하지 못했습니다. 잠시 뒤 다시 눌러 주세요.';
}

/** 로그인·닉네임 화면으로 보내기 전 안내를 보여 주고 이동하기까지 기다리는 시간(ms). 안내를 읽을 만큼만 */
export const GO_DELAY_MS = 700;
