import { useEffect, useState } from 'react';
import { endProposalReview, endProposalReviewOnLeave, startProposalReview } from '../api/proposals';
import { displayNickname } from '../lib/nickname';

/** 같은 제안을 지금 보고 있는 다른 운영진 경고 (대기 목록 줄·[자세히] 공용). 막지 않고 알려 주기만 한다 */
export function ReviewersWarning({ reviewers, detail = false }) {
  if (!reviewers?.length) return null;
  return (
    <div className="warn review-warn" role="status">
      {reviewers.map((r) => (
        <p key={`${r.nickname}-${r.started_at}`}>{displayNickname(r)} 검토 중</p>
      ))}
      {detail && <small>같은 제안을 동시에 처리하지 않도록 확인해 주세요. 먼저 처리한 쪽이 반영됩니다.</small>}
    </div>
  );
}

// DB 표시는 10분 뒤 사라진다. 내용을 고치느라 오래 열어 두어도 표시가 끊기지 않게 그보다 짧은 간격으로 다시 남긴다 (033)
export const REVIEW_REFRESH_MS = 4 * 60 * 1000;

/**
 * [자세히]를 여는 동안 "검토 중" 표시를 남긴다 (DB가 10분 뒤 저절로 지움 — 열어 두는 동안은 4분마다 다시 남긴다).
 * 화면을 닫거나 다른 곳으로 가면 바로 지우고, 탭을 닫을 때도 지우려고 한다.
 * 처리(승인·거절 …)하면 DB 트리거가 지운다. 표시를 남기지 못해도 화면은 그대로 쓴다.
 */
export default function ReviewPresence({ proposalId }) {
  const [others, setOthers] = useState([]);
  useEffect(() => {
    let alive = true;
    const mark = () => startProposalReview(proposalId).then(
      (list) => alive && setOthers(Array.isArray(list) ? list : []),
      () => {},
    );
    mark();
    const timer = setInterval(mark, REVIEW_REFRESH_MS);
    const onLeave = () => endProposalReviewOnLeave(proposalId);
    window.addEventListener('pagehide', onLeave);
    return () => {
      alive = false;
      clearInterval(timer);
      window.removeEventListener('pagehide', onLeave);
      endProposalReview(proposalId).catch(() => {});
    };
  }, [proposalId]);
  return <ReviewersWarning reviewers={others} detail />;
}
