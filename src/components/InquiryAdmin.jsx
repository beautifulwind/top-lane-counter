import { Link } from 'react-router-dom';
import { getStaffInquiries } from '../api/inquiries';
import { useAuth } from '../lib/auth';
import { useAsync } from '../lib/useAsync';
import { ErrorBox, Loading } from './Status';

/** /admin의 "문의" 구역 (SPEC 6-19): 답변 대기 수와 [문의 보기]. 감독관에게는 DB가 "계정·탈퇴"를 빼고 돌려준다 */
export default function InquiryAdmin() {
  const { user } = useAuth();
  const { data, error, loading, retry } = useAsync(() => getStaffInquiries(user.id), [user.id]);
  return (
    <>
      {loading && <Loading />}
      {error && <ErrorBox error={error} onRetry={retry} />}
      {data && (
        <div className="inquiry-section-link">
          <p>{data.waiting.length === 0 ? '답변을 기다리는 문의가 없습니다.' : `답변을 기다리는 문의가 ${data.waiting.length}건 있습니다.`}</p>
          <Link to="/admin/inquiries" className="btn btn-small btn-op">문의 보기</Link>
        </div>
      )}
    </>
  );
}
