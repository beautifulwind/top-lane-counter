// 칭호 목록 (SPEC 6-3). DB의 user_titles.title_key / profiles.main_title 값 → 화면 이름.
// 조건·숫자는 DB(xp_rules, sync_rewards)가 정한다. 여기는 이름과 보여 줄 순서·설명만.
// "운영자"·"관리자"라는 단어는 칭호에 쓰지 않는다.
export const TITLES = {
  top_addict: '탑신병자',
  tool_hater: '도구혐오자',
  solid_heavy: '단단묵직',
  butcher_owner: '백정주인',
  general: '장군',
  offmeta: '비주류',
};

/** /me에 보여 줄 조건 설명 (rules = xp_rules 값 { title_tool_hater: 10, ... }) */
export const titleCondition = (key, rules = {}) => ({
  top_addict: '처음으로 승인받은 기여 1개 (카운터·문서 수정·빌드) 또는 게시판 글·댓글·문서 댓글 1개 (숨김·삭제된 것은 빼고)',
  tool_hater: `카운터 관련 승인 ${rules.title_tool_hater ?? 10}개 (새 카운터 + 문서 수정)`,
  solid_heavy: `카운터 관련 승인 ${rules.title_solid_heavy ?? 25}개`,
  butcher_owner: `카운터 관련 승인 ${rules.title_butcher_owner ?? 50}개`,
  general: `공개 중인 내 빌드들의 따봉 합계 ${rules.title_general ?? 100}`,
  offmeta: `비주류 픽 매치업 기여 승인 ${rules.title_offmeta ?? 5}개`,
})[key] ?? '';

export const titleName = (key) => (key ? TITLES[key] ?? key : null);
