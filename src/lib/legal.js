// 개인정보처리방침(/privacy)·이용약관(/terms)에 들어가는 값. 여기 한곳만 채우면 두 페이지에 반영된다.
// 비어 있는(null) 값은 페이지에 노란 칸 "【채워 주세요: …】"로 크게 보인다 → 공개(배포) 전에 반드시 채울 것.
export const LEGAL = {
  /** 운영자 연락 이메일 (문의·열람·정정·탈퇴 요청). 예: 'toplanewiki@gmail.com' */
  contactEmail: 'ghkdrbtjd02@gmail.com',
  /** Supabase 프로젝트 서버 지역 (대시보드 → Project Settings → General). 예: '대한민국 (서울)' */
  supabaseRegion: '대한민국(서울), AWS ap-northeast-2',
  /** 첫 판의 시행일 (비어 있으면 노란 칸). 판마다 'YYYY-MM-DD' 형식이어야 날짜로 전환된다 */
  effectiveDate: '2026-12-14',
  /** 그 뒤 개정판의 시행일 (오래된 것부터). 판을 더할 때는 여기에 날짜를 넣고 Privacy.jsx·Terms.jsx에 <Since v="날짜">로 달라진 부분만 더한다 */
  revisions: ['2026-12-23'],
  /**
   * 개인정보처리방침의 첫 판 시행일. 약관(effectiveDate)과 따로 — 2026-11-25에 「내 챔피언」 고지를 넣어 그날 시행(6-119).
   * revisions의 날짜보다 앞이어야 한다.
   */
  privacyEffectiveDate: '2026-11-25',
};

/** 개정판마다 방침·약관에서 무엇이 달라졌는지 한 줄 (시행 예정 안내 상자에 보인다) */
export const LEGAL_REVISION_NOTES = {
  '2026-12-23': {
    privacy: '저장한 빌드, 빌드 수정 알림, 경고·활동 제한 기록을 처리하는 항목에 더했습니다.',
    terms: '운영자의 경고와 활동 제한(제7조의2)을 더했습니다.',
  },
};

/** 판 목록 (오래된 것부터). kind: 'privacy'면 방침, 아니면 약관. 첫 판의 시행일이 비어 있으면 빈 목록 */
export const legalVersions = (kind) => {
  const first = kind === 'privacy' ? LEGAL.privacyEffectiveDate : LEGAL.effectiveDate;
  return first ? [first, ...(LEGAL.revisions ?? [])] : [];
};

/** 한국 날짜 'YYYY-MM-DD' (시행일은 한국 시각 0시에 바뀐다) */
export const kstDate = (ms = Date.now()) => new Date(ms + 9 * 3600 * 1000).toISOString().slice(0, 10);

/**
 * 어느 판을 보여 줄지. 현행 = 시행일이 오늘(한국)까지 지난 가장 새 판, 하나도 안 지났으면(정식 공개 전) 첫 판.
 * requested(주소의 ?version=)가 판 목록에 있으면 그 판을 보여 주고(시행 예정 미리 보기·이전 판 보기), 아니면 현행.
 * 판 비교는 날짜 문자열이 아니라 목록 순서로 한다(날짜 형식이 달라도 어긋나지 않게).
 */
export function resolveLegalVersion(requested = null, now = Date.now(), kind = undefined) {
  const versions = legalVersions(kind);
  if (versions.length === 0) return { versions, shown: null, shownIdx: -1, current: null, currentIdx: -1 };
  const today = kstDate(now);
  let currentIdx = 0;
  versions.forEach((v, i) => { if (v <= today) currentIdx = i; });
  const asked = requested ? versions.indexOf(requested) : -1;
  const shownIdx = asked >= 0 ? asked : currentIdx;
  return { versions, shown: versions[shownIdx], shownIdx, current: versions[currentIdx], currentIdx };
}

export const SITE_NAME = '탑신병자';
/** 검색용 이름: 홈 탭 제목·사이트 설명·앱 이름 ("탑 카운터"를 같이 넣는다) */
export const SITE_SEO_NAME = '탑신병자 - 롤 탑 카운터';
/** 상단 바에 사이트 이름과 같이 보이는 부제 */
export const SITE_TAGLINE = '탑은 라인전이 전부';
