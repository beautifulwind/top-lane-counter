import { Link } from 'react-router-dom';
import RequireOperator from '../../components/RequireOperator';
import MemberAdmin from '../../components/MemberAdmin';
import { UsersIcon } from '../../components/Icons';

/** 운영자: 회원 관리 (042, /admin/members) — 가입자 수·회원 목록·검색·감독관 지정·해제·처리 기록 한 화면. 감독관에게는 없다 */
export default function AdminMembers() {
  return (
    <RequireOperator>
      <article>
        <nav className="crumbs"><Link to="/admin" className="op-link">← 운영자 페이지</Link></nav>
        <h1 className="doc-title page-title"><UsersIcon size={26} className="title-icon op" /> 회원 관리</h1>
        <MemberAdmin />
      </article>
    </RequireOperator>
  );
}
