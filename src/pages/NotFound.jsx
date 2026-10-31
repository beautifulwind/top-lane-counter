import { Link } from 'react-router-dom';

export default function NotFound() {
  return (
    <div className="status">
      <h1 className="doc-title">문서를 찾을 수 없어요</h1>
      <p>
        <Link to="/">홈으로 돌아가기</Link>
      </p>
    </div>
  );
}
