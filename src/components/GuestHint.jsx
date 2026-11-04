import { Link } from 'react-router-dom';

/** 비회원이 빌드 추천·비추천, 자유게시판 추천, 신고를 하려 할 때 보이는 안내 + 마이페이지 연결 칸으로 가는 링크 (020) */
export default function GuestHint({ what }) {
  return (
    <p className="hint guest-hint" role="status">
      비회원은 {what} 수 없어요. <Link to="/me#upgrade">구글·카카오 연결하기</Link>
    </p>
  );
}
