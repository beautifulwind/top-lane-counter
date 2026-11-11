import { useEffect, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { getMemberList, getMemberStats } from '../api/moderation';
import { fmtDateTime } from '../lib/format';
import { useAsync } from '../lib/useAsync';
import { ErrorBox, Loading } from './Status';
import { ModerationLog, ModeratorToggle, ROLE_LABEL } from './ModeratorAdmin';
import UserName from './UserName';

const PAGE_SIZE = 20;
const ROLES = ['moderator', 'admin', 'user'];

/**
 * 운영자: 회원 관리 (042, /admin/members). 예전 "회원"(036)과 "감독관 관리"(030)를 한 화면으로 합쳤다.
 * 가입자 수 · 최근 가입 순 목록 · 닉네임 검색 · 감독관 지정·해제 · 처리 기록. 회원을 누르면 회원 정보 페이지로 간다.
 * 이메일·로그인 ID는 DB가 애초에 돌려주지 않는다. 감독관·일반 회원에게는 이 화면이 없고, DB도 운영자만 허용한다.
 */
export default function MemberAdmin() {
  const [params, setParams] = useSearchParams();
  const roleParam = params.get('role');
  const role = ROLES.includes(roleParam) ? roleParam : '';
  const [input, setInput] = useState('');
  const [query, setQuery] = useState('');
  const [page, setPage] = useState(1);
  const [message, setMessage] = useState(null);
  const [logKey, setLogKey] = useState(0);
  const { data, error, loading, retry } = useAsync(() => getMemberList({ query, role, page, size: PAGE_SIZE }), [query, role, page]);
  useEffect(() => { setPage(1); }, [query, role]);
  const search = (e) => {
    e.preventDefault();
    setQuery(input.trim());
  };
  const pickRole = (value) => {
    const next = new URLSearchParams(params);
    if (value) next.set('role', value); else next.delete('role');
    setParams(next, { replace: true });
  };
  const finished = (text) => {
    setMessage(text);
    setLogKey((k) => k + 1);
    retry();
  };
  const pages = data ? Math.max(1, Math.ceil(data.total / PAGE_SIZE)) : 1;
  return (
    <>
      <MemberStats />
      <p className="hint">
        감독관은 신고 처리, 글·댓글 숨김과 다시 공개, 새 상대법 승인·재검토 요청·거절을 합니다. 화면에는 운영자와 똑같이 (운)으로 보입니다.
        이메일·로그인 ID는 볼 수 없습니다.
      </p>
      {message && <p className="notice" role="status">{message}</p>}
      <form className="row-actions" onSubmit={search}>
        <label htmlFor="member-search" className="sr-only">닉네임으로 회원 검색</label>
        <input id="member-search" type="search" value={input} placeholder="닉네임으로 회원 검색" maxLength={20} onChange={(e) => setInput(e.target.value)} />
        <button type="submit" className="btn btn-small btn-op">검색</button>
        <label htmlFor="member-role" className="sr-only">등급으로 거르기</label>
        <select id="member-role" value={role} onChange={(e) => pickRole(e.target.value)}>
          <option value="">모든 등급</option>
          {ROLES.map((r) => <option key={r} value={r}>{ROLE_LABEL[r]}</option>)}
        </select>
      </form>
      {loading && !data && <Loading />}
      {error && <ErrorBox error={error} onRetry={retry} />}
      {data && (
        <>
          <p className="hint">{query || role ? `찾은 회원 ${data.total}명` : `전체 회원 ${data.total}명`} · 최근 가입 순</p>
          {data.members.length === 0 ? (
            <p className="empty">찾은 회원이 없습니다.</p>
          ) : (
            <ul className="proposal-list" aria-label="회원 목록">
              {data.members.map((m) => (
                <li key={m.id} className="proposal-row" aria-label={m.nickname}>
                  <div className="proposal-meta">
                    <Link to={`/admin/members/${m.id}`} className="op-link" aria-label={`${m.nickname} 회원 정보`}><UserName profile={m} /></Link>
                    {' '}<small className="hint">{ROLE_LABEL[m.role] ?? m.role} · 가입 {fmtDateTime(m.created_at)}</small>
                  </div>
                  <ModeratorToggle member={m} onDone={finished} />
                </li>
              ))}
            </ul>
          )}
          {pages > 1 && (
            <nav className="row-actions" aria-label="쪽 이동">
              <button type="button" className="btn btn-small" disabled={page <= 1} onClick={() => setPage(page - 1)}>이전</button>
              <span className="hint">{page} / {pages}쪽</span>
              <button type="button" className="btn btn-small" disabled={page >= pages} onClick={() => setPage(page + 1)}>다음</button>
            </nav>
          )}
        </>
      )}
      <ModerationLog refreshKey={logKey} />
    </>
  );
}

function MemberStats() {
  const { data, error, loading, retry } = useAsync(getMemberStats, []);
  if (loading && !data) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  if (!data) return null;
  return (
    <ul className="log-list" aria-label="가입자 수">
      <li>총 가입자 {data.total}명 (정식 회원 {data.members}명 · 비회원 {data.guests}명)</li>
      <li>가입 방식: 구글 {data.google}명 · 카카오 {data.kakao}명 (둘 다 연결한 회원 {data.both}명은 양쪽에 포함)</li>
      <li>최근 7일 신규 가입 {data.new_7d}명 (정식 회원 {data.new_7d_members}명)</li>
    </ul>
  );
}
