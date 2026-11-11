import { MATCHUP_REPORT_REASONS, WIKI_REPORT_HINTS, WIKI_REPORT_MEMO_MAX, WIKI_REPORT_REASONS, reportWiki } from '../api/wikiReports';
import { isGuest } from '../lib/auth';
import { ReportForm } from './BoardParts';
import GuestHint from './GuestHint';

/**
 * 상대법·빌드 ⋮ "오류 신고"를 고르면 그 자리에 열리는 칸 (043, SPEC 6-30).
 * 정식 회원: 이유 + 메모(200자) → 보내기. 비회원: 구글·카카오 연결 안내만 (로그인 전이면 화면이 로그인으로 보낸다).
 * buildId가 없으면 상대법 전체에 대한 신고라 "패치가 지남"·"같은 빌드가 또 있음"은 고를 수 없다. 같은 대상 중복·하루 상한은 DB가 막는다.
 */
export default function WikiReportBox({ id, auth, counterId, buildId = null, what, onDone, onCancel }) {
  if (isGuest(auth)) {
    return (
      <div className="report-box">
        <GuestHint what="오류 신고를 할" />
        <button type="button" className="btn btn-small" onClick={onCancel}>닫기</button>
      </div>
    );
  }
  const reasons = buildId
    ? WIKI_REPORT_REASONS
    : Object.fromEntries(MATCHUP_REPORT_REASONS.map((k) => [k, WIKI_REPORT_REASONS[k]]));
  return (
    <ReportForm
      id={id}
      legend={`${what} 오류 신고 — 이유를 골라 주세요`}
      reasons={reasons}
      hints={WIKI_REPORT_HINTS}
      max={WIKI_REPORT_MEMO_MAX}
      label="메모"
      note="신고는 운영진만 봅니다. 처리되면 [알림]으로 결과를 알려 드립니다."
      onCancel={onCancel}
      onSubmit={async (reason, memo) => {
        await reportWiki({ counterId, buildId, reason, memo });
        onDone('오류 신고를 보냈습니다. 운영진이 확인합니다.');
      }}
    />
  );
}
