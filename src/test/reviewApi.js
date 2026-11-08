import { startProposalReview } from '../api/proposals';

/** 일반 회원이 DB 함수를 직접 불러도 거부당하는지 (가짜 DB가 운영진이 아니면 오류를 돌려줌) */
export const api = async () => {
  try {
    await startProposalReview(501);
    return 'ok';
  } catch (e) {
    return e.message;
  }
};
