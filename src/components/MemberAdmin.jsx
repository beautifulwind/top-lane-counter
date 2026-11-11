import { useState } from 'react';
import { findMembers, getMemberInfo, getMemberStats } from '../api/moderation';
import { fmtDateTime } from '../lib/format';
import { useAsync } from '../lib/useAsync';
import { titleName } from '../lib/titles';
import { ErrorBox, Loading } from './Status';
import UserName from './UserName';

const PROVIDER_LABEL = { google: '구글', kakao: '카카오' };
const ROLE_LABEL = { admin: '운영자', moderator: '감독관', user: '일반 회원' };

/** 가입 방식 한 마디: 비회원이면 "비회원", 아니면 "구글, 카카오" (연결한 로그인 방식 이름만 — 이메일·로그인 ID는 화면에 오지 않는다) */
const joinedWith = (m) => {
  const names = (m.providers ?? []).map((p) => PROVIDER_LABEL[p] ?? p);
  if (m.is_guest) return '비회원 (구글·카카오 연결 전)';
  return names.length ? names.join(', ') : '알 수 없음';
};

/**
 * 운영자: 가입자 수 + 닉네임으로 회원 찾기 (036, /admin). 감독관에게는 이 칸이 없고, DB도 운영자만 허용한다.
 * 이메일·로그인 ID 같은 민감한 정보는 DB가 애초에 돌려주지 않는다.
 */
export default function MemberAdmin() {
  return (
    <>
      <MemberStats />
      <MemberLookup />
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

function MemberLookup() {
  const [query, setQuery] = useState('');
  const [found, setFound] = useState(null);
  const [fail, setFail] = useState(null);
  const [picked, setPicked] = useState(null);
  const search = async (e) => {
    e.preventDefault();
    setFail(null);
    setPicked(null);
    if (!query.trim()) return;
    try {
      setFound(await findMembers(query));
    } catch (err) {
      setFound(null);
      setFail(err.message);
    }
  };
  return (
    <>
      <form className="row-actions" onSubmit={search}>
        <label htmlFor="member-search" className="sr-only">닉네임으로 회원 검색</label>
        <input id="member-search" type="search" value={query} placeholder="닉네임으로 회원 검색" maxLength={20} onChange={(e) => setQuery(e.target.value)} />
        <button type="submit" className="btn btn-small btn-op">검색</button>
      </form>
      <p className="hint">닉네임 일부만 적어도 됩니다. 결과는 최대 10명까지 보입니다. 이메일·로그인 ID는 볼 수 없습니다.</p>
      {fail && <p className="form-error" role="alert">{fail}</p>}
      {found && found.length === 0 && <p className="empty">찾은 회원이 없습니다.</p>}
      {found && found.length > 0 && (
        <ul className="proposal-list" aria-label="검색 결과">
          {found.map((u) => (
            <li key={u.id} className="proposal-row" aria-label={u.nickname}>
              <div className="proposal-meta"><UserName profile={u} /></div>
              <div className="row-actions">
                <button type="button" className="btn btn-small btn-op" aria-expanded={picked === u.id} onClick={() => setPicked(picked === u.id ? null : u.id)}>
                  정보 보기
                </button>
              </div>
              {picked === u.id && <MemberInfo userId={u.id} />}
            </li>
          ))}
        </ul>
      )}
    </>
  );
}

function MemberInfo({ userId }) {
  const { data, error, loading, retry } = useAsync(() => getMemberInfo(userId), [userId]);
  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  const titles = (data.titles ?? []).map(titleName);
  return (
    <ul className="log-list" aria-label={`${data.nickname} 회원 정보`}>
      <li>가입일 {fmtDateTime(data.created_at)}</li>
      <li>가입 방식 {joinedWith(data)}</li>
      <li>등급 {ROLE_LABEL[data.role] ?? data.role} · 레벨 {data.level}{data.main_title ? ` · 대표 칭호 ${titleName(data.main_title)}` : ''}</li>
      <li>얻은 칭호 {titles.length ? titles.join(', ') : '없음'}</li>
      <li>활동 제안 {data.proposals}개 · 글 {data.posts}개 · 빌드 {data.builds}개 · 댓글 {data.comments}개</li>
      {(data.deleted_posts > 0 || data.deleted_comments > 0) && (
        <li>지운 글 {data.deleted_posts}개 · 지운 댓글 {data.deleted_comments}개 <small className="hint">(1년 보관, 운영자만)</small></li>
      )}
    </ul>
  );
}
