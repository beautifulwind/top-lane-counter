import { Link, useLocation } from 'react-router-dom';
import { getChampionMap } from '../../api/ddragon';
import { getPendingProposals } from '../../api/proposals';
import { useAsync } from '../../lib/useAsync';
import { TYPE_LABEL, fmtDateTime } from '../../lib/format';
import { ErrorBox, Loading } from '../../components/Status';
import RequireOperator from '../../components/RequireOperator';
import UserName from '../../components/UserName';

/** 운영자 페이지: 승인 대기 목록 (오래된 순) */
export default function AdminHome() {
  return (
    <RequireOperator>
      <PendingList />
    </RequireOperator>
  );
}

function PendingList() {
  const done = useLocation().state?.done;
  const { data, error, loading, retry } = useAsync(async () => {
    const [champs, pending] = await Promise.all([getChampionMap(), getPendingProposals()]);
    return { champs, pending };
  }, []);
  const name = (id) => data.champs[id]?.name ?? id;

  return (
    <article>
      <h1 className="doc-title">운영자 페이지</h1>
      {done && <p className="notice" role="status">{done}</p>}
      <p className="hint">카운터 순서 변경은 각 챔피언 문서의 [순서 변경], 문서 되돌리기는 매치업 문서의 [수정 기록]에서 해요.</p>

      <section className="section">
        <h2 className="section-title">승인 대기 {data ? `(${data.pending.length})` : ''}</h2>
        {loading && <Loading />}
        {error && <ErrorBox error={error} onRetry={retry} />}
        {data && data.pending.length === 0 && <p className="empty">대기 중인 제안이 없어요.</p>}
        {data && data.pending.length > 0 && (
          <ul className="proposal-list">
            {data.pending.map((p) => (
              <li key={p.id} className="proposal-row">
                <Link to={`/admin/proposals/${p.id}`} className="proposal-main">
                  <span className="proposal-type">{TYPE_LABEL[p.type]}</span>{' '}
                  {name(p.counter_champion)}(으)로 {name(p.target_champion)} 잡는 법
                </Link>
                <div className="proposal-meta">
                  {p.proposer ? <UserName profile={p.proposer} /> : <span>(탈퇴한 유저)</span>}
                  <span>{fmtDateTime(p.created_at)}</span>
                </div>
              </li>
            ))}
          </ul>
        )}
      </section>
    </article>
  );
}
