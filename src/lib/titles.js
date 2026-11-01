// 칭호 목록 (SPEC 6-3). DB의 user_titles.title_key / profiles.main_title 값 → 화면 이름.
export const TITLES = {
  counter_researcher: '카운터 연구원',
  senior_researcher: '수석 연구원',
  counter_doctor: '카운터 박사',
  build_researcher: '빌드 연구원',
  offmeta_researcher: '비주류 픽 연구원',
  chatterbox: '연구소 수다쟁이',
};

export const titleName = (key) => (key ? TITLES[key] ?? key : null);
