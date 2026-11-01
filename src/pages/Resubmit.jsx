import { Link, useNavigate, useParams } from 'react-router-dom';
import { getChampionMap } from '../api/ddragon';
import { getMyProposal, resubmitProposal } from '../api/proposals';
import { useAuth } from '../lib/auth';
import { useAsync } from '../lib/useAsync';
import { fmtDateTime } from '../lib/format';
import { ErrorBox, Loading } from '../components/Status';
import DocForm from '../components/DocForm';
import { RequireLogin } from '../components/RequireOperator';

/** 재검토 요청 받은 내 제안을 고쳐서 다시 제출: /me/resubmit/:id */
export default function Resubmit() {
  return (
    <RequireLogin>
      <ResubmitForm />
    </RequireLogin>
  );
}

function ResubmitForm() {
  const { id } = useParams();
  const auth = useAuth();
  const navigate = useNavigate();
  const { data, error, loading, retry } = useAsync(async () => {
    const [champs, proposal] = await Promise.all([getChampionMap(), getMyProposal(auth.user.id, Number(id))]);
    return { champs, proposal };
  }, [auth.user.id, id]);

  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  const p = data.proposal;
  const crumbs = <nav className="crumbs"><Link to="/me">내 활동</Link> › 다시 제출</nav>;
  if (!p || p.status !== 'revision_requested') {
    return (
      <article>
        {crumbs}
        <h1 className="doc-title">다시 제출</h1>
        <p className="empty">재검토 요청을 받은 제안이 아니에요. 이미 다시 제출했거나, 운영자가 요청을 취소했을 수 있어요.</p>
      </article>
    );
  }
  const name = (cid) => data.champs[cid]?.name ?? cid;
  const title = `${name(p.counter_champion)}(으)로 ${name(p.target_champion)} 잡는 법`;

  const submit = async (content) => {
    await resubmitProposal(p.id, content);
    navigate('/me', { state: { sent: `${title} — 고친 내용을 다시 제출했어요.` } });
  };

  return (
    <article>
      {crumbs}
      <h1 className="doc-title">{title} — 고쳐서 다시 제출</h1>
      <div className="revision-note" role="note">
        <strong>운영자 메모</strong>
        {p.revision_requested_at && <small> ({fmtDateTime(p.revision_requested_at)})</small>}
        <p>{p.revision_note}</p>
      </div>
      <p className="lead">숨기기 전의 문서 내용이 채워져 있어요. 메모를 보고 고친 뒤 다시 제출해 주세요.</p>
      <DocForm initial={p.content} onSubmit={submit} submitLabel="다시 제출" requireChange />
    </article>
  );
}
