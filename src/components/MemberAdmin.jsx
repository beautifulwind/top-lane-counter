import { useEffect, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { getAllNewMembers, getMemberList, getMemberStats } from '../api/moderation';
import { fmtDateTime } from '../lib/format';
import { useAsync } from '../lib/useAsync';
import { ErrorBox, Loading } from './Status';
import { ModerationLog, ROLE_LABEL } from './ModeratorAdmin';
import UserName from './UserName';

const PAGE_SIZE = 20;
const PROVIDER_LABEL = { google: '구글', kakao: '카카오' };
const NEW_HOURS = 24;
// 신규 가입자 정렬 (정렬은 이 목록에서만 — 전체 회원은 검색으로만 본다)
const SORTS = {
  newest: { label: '최근 가입 순', cmp: (a, b) => String(b.created_at).localeCompare(String(a.created_at)) },
  oldest: { label: '오래된 가입 순', cmp: (a, b) => String(a.created_at).localeCompare(String(b.created_at)) },
  nickname: { label: '닉네임 순', cmp: (a, b) => (a.nickname ?? '\uFFFF').localeCompare(b.nickname ?? '\uFFFF', 'ko') },
};

/**
 * 운영자: 회원 관리 (042 → 046 정리, /admin/members, SPEC 6-33 2c).
 * 기본 화면 = 가입자 수 + 닉네임 검색창 + [감독관 목록 보기] + 신규 가입자(24시간) 목록. 처리 기록은 맨 아래 접힌 칸.
 * 전체 회원은 검색으로만 본다(부분 일치, 20명씩, 검색어가 비면 결과 없음 — admin_member_list). 감독관 목록 = admin_member_list 역할 거르기.
 * 줄을 누르면 회원 정보(/admin/members/:id)로 가서 감독관 지정·해제, 장인 해제·닉네임 바꾸기를 한다. 이메일·로그인 ID는 DB가 돌려주지 않는다.
 */
export default function MemberAdmin() {
  const [params] = useSearchParams();
  return (
    <>
      <MemberStats />
      <p className="hint">
        회원을 누르면 회원 정보에서 감독관 지정·해제, 장인 인증 해제, 닉네임 바꾸기를 합니다. 감독관은 화면에 운영자와 똑같이 (운)으로 보입니다.
        이메일·로그인 ID는 볼 수 없습니다.
      </p>
      <MemberSearch />
      <ModeratorList startOpen={params.get('role') === 'moderator'} />
      <NewMembers />
      <ModerationLog />
    </>
  );
}

/** 회원 한 줄 (회원 정보로 가는 링크 + 등급·가입일) */
function MemberRow({ m, extra = null }) {
  const name = m.nickname ?? '(닉네임 정하기 전)';
  return (
    <li className="proposal-row" aria-label={name}>
      <div className="proposal-meta">
        <Link to={`/admin/members/${m.id}`} className="op-link" aria-label={`${name} 회원 정보`}>
          {m.level !== undefined && m.nickname ? <UserName profile={m} /> : name}
        </Link>
        {' '}<small className="hint">{ROLE_LABEL[m.role] ?? m.role}{m.is_guest ? ' · 비회원' : ''} · 가입 {fmtDateTime(m.created_at)}{extra}</small>
      </div>
    </li>
  );
}

function Pager({ page, pages, setPage }) {
  if (pages <= 1) return null;
  return (
    <nav className="row-actions" aria-label="쪽 이동">
      <button type="button" className="btn btn-small" disabled={page <= 1} onClick={() => setPage(page - 1)}>이전</button>
      <span className="hint">{page} / {pages}쪽</span>
      <button type="button" className="btn btn-small" disabled={page >= pages} onClick={() => setPage(page + 1)}>다음</button>
    </nav>
  );
}

/** 닉네임 부분 일치 검색 (전체 회원은 여기서만). 검색어가 비면 부르지 않고 결과도 없다 */
function MemberSearch() {
  const [input, setInput] = useState('');
  const [query, setQuery] = useState('');
  const [page, setPage] = useState(1);
  const [hint, setHint] = useState(null);
  const { data, error, loading, retry } = useAsync(
    () => (query ? getMemberList({ query, page, size: PAGE_SIZE }) : Promise.resolve(null)),
    [query, page],
  );
  const search = (e) => {
    e.preventDefault();
    const q = input.trim();
    setHint(q ? null : '닉네임을 한 글자 이상 적어 주세요.');
    setQuery(q);
    setPage(1);
  };
  const pages = data ? Math.max(1, Math.ceil(data.total / PAGE_SIZE)) : 1;
  return (
    <section className="section" aria-label="회원 검색">
      <form className="row-actions" onSubmit={search}>
        <label htmlFor="member-search" className="sr-only">닉네임으로 회원 검색</label>
        <input id="member-search" type="search" value={input} placeholder="닉네임으로 회원 검색 (일부만 적어도 됨)" maxLength={20} onChange={(e) => setInput(e.target.value)} />
        <button type="submit" className="btn btn-small btn-op">검색</button>
      </form>
      {hint && <p className="hint" role="status">{hint}</p>}
      {query && loading && !data && <Loading />}
      {error && <ErrorBox error={error} onRetry={retry} />}
      {query && data && (
        <>
          <p className="hint">「{query}」 검색 결과 {data.total}명 · 최근 가입 순</p>
          {data.members.length === 0 ? (
            <p className="empty">찾은 회원이 없습니다.</p>
          ) : (
            <ul className="proposal-list" aria-label="검색 결과">
              {data.members.map((m) => <MemberRow key={m.id} m={m} />)}
            </ul>
          )}
          <Pager page={page} pages={pages} setPage={setPage} />
        </>
      )}
    </section>
  );
}

/** [감독관 목록 보기]: admin_member_list의 역할 거르기(moderator). 예전 /admin/moderators 주소는 열린 채로 온다 */
function ModeratorList({ startOpen }) {
  const [open, setOpen] = useState(startOpen);
  const [page, setPage] = useState(1);
  useEffect(() => { if (startOpen) setOpen(true); }, [startOpen]);
  const { data, error, loading, retry } = useAsync(
    () => (open ? getMemberList({ role: 'moderator', page, size: PAGE_SIZE }) : Promise.resolve(null)),
    [open, page],
  );
  const pages = data ? Math.max(1, Math.ceil(data.total / PAGE_SIZE)) : 1;
  return (
    <section className="section" aria-label="감독관">
      <div className="row-actions">
        <button type="button" className="btn btn-small btn-op" aria-expanded={open} onClick={() => setOpen((v) => !v)}>
          {open ? '감독관 목록 닫기' : '감독관 목록 보기'}
        </button>
      </div>
      {open && loading && !data && <Loading />}
      {open && error && <ErrorBox error={error} onRetry={retry} />}
      {open && data && (
        <>
          <p className="hint">감독관 {data.total}명</p>
          {data.members.length === 0 ? (
            <p className="empty">감독관이 없습니다.</p>
          ) : (
            <ul className="proposal-list" aria-label="감독관 목록">
              {data.members.map((m) => <MemberRow key={m.id} m={m} />)}
            </ul>
          )}
          <Pager page={page} pages={pages} setPage={setPage} />
        </>
      )}
    </section>
  );
}

/** 신규 가입자 (24시간, 정식 회원만 — admin_new_members). 정렬은 이 목록에서만, 20명씩 */
function NewMembers() {
  const [sort, setSort] = useState('newest');
  const [page, setPage] = useState(1);
  const { data, error, loading, retry } = useAsync(() => getAllNewMembers(NEW_HOURS), []);
  const sorted = data ? [...data.members].sort(SORTS[sort].cmp) : [];
  const pages = Math.max(1, Math.ceil(sorted.length / PAGE_SIZE));
  const shown = sorted.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);
  const providers = (m) => (m.providers ?? []).map((p) => PROVIDER_LABEL[p] ?? p).join('·') || '알 수 없음';
  return (
    <section className="section" aria-labelledby="new-members">
      <h2 className="section-title" id="new-members">신규 가입자 ({NEW_HOURS}시간)</h2>
      <div className="row-actions">
        <label htmlFor="new-members-sort">정렬</label>
        <select id="new-members-sort" value={sort} onChange={(e) => { setSort(e.target.value); setPage(1); }}>
          {Object.entries(SORTS).map(([k, s]) => <option key={k} value={k}>{s.label}</option>)}
        </select>
        {data && <span className="count-badge">{data.total}명</span>}
      </div>
      {loading && !data && <Loading />}
      {error && <ErrorBox error={error} onRetry={retry} />}
      {data && (shown.length === 0 ? (
        <p className="empty">최근 {NEW_HOURS}시간 동안 가입한 정식 회원이 없습니다.</p>
      ) : (
        <ul className="proposal-list" aria-label="신규 가입자 목록">
          {shown.map((m) => <MemberRow key={m.id} m={m} extra={` · ${providers(m)}`} />)}
        </ul>
      ))}
      <Pager page={page} pages={pages} setPage={setPage} />
    </section>
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
