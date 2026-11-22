import { useLocation, useNavigate } from 'react-router-dom';
import { ArrowLeftIcon } from './Icons';

/**
 * 상단 바 왼쪽 ← 뒤로 가기 (SPEC 6-78). 앱·홈 화면 앱(PWA)에는 브라우저 뒤로 가기가 없어서 둔다.
 * 안 보이는 화면:
 *  - 홈(첫 챔피언 선택)·로그인·닉네임 정하기: 돌아갈 곳이 없거나 흐름 중간이라 필요 없다.
 *  - 본문에 이미 "← …" 돌아가기 링크가 있는 화면(자유게시판 글·글쓰기, 운영자 회원·장인·문의·신고 화면): 중복을 피한다.
 */
const NO_BACK = [/^\/$/, /^\/login$/, /^\/welcome$/];
const HAS_OWN_BACK = [/^\/board\/(new|[^/]+|[^/]+\/edit)$/, /^\/admin\/(members|members\/[^/]+|influencers|inquiries|reports)$/];

export function showsBackButton(pathname) {
  const p = pathname.length > 1 ? pathname.replace(/\/+$/, '') : pathname;
  return ![...NO_BACK, ...HAS_OWN_BACK].some((re) => re.test(p));
}

export default function BackButton() {
  const { pathname, key } = useLocation();
  const navigate = useNavigate();
  if (!showsBackButton(pathname)) return null;
  // key가 'default'면 이 앱에서 처음 연 화면(이전 기록 없음) → 홈으로. 아니면 한 걸음 뒤로
  const goBack = () => (key === 'default' ? navigate('/') : navigate(-1));
  return (
    <button type="button" className="back-btn" aria-label="뒤로 가기" onClick={goBack}>
      <ArrowLeftIcon size={22} />
    </button>
  );
}
