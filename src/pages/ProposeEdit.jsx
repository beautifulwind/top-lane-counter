import { Link, useNavigate, useParams, useSearchParams } from 'react-router-dom';
import { getChampionMap } from '../api/ddragon';
import { getMatchup } from '../api/content';
import { getMyProposal, proposeDocEdit } from '../api/proposals';
import { useAuth } from '../lib/auth';
import { useAsync } from '../lib/useAsync';
import { ErrorBox, Loading } from '../components/Status';
import DocForm from '../components/DocForm';
import { RequireLogin } from '../components/RequireOperator';
import NotFound from './NotFound';
import { matchupTitle } from '../lib/josa';

/**
 * 매치업 문서 수정 제안: /champion/:targetId/counter/:counterId/edit
 * ?from=내 제안 id: 거절된 내 제안 [다시 쓰기] — 그 글을 채워서 새 제안으로 보낸다 (원래 제안은 그대로)
 */
export default function ProposeEdit() {
  return (
    <RequireLogin>
      <ProposeEditForm />
    </RequireLogin>
  );
}

function ProposeEditForm() {
  const { targetId, counterId } = useParams();
  const auth = useAuth();
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const fromId = Number(params.get('from')) || null;
  const { data, error, loading, retry } = useAsync(async () => {
    const [champs, matchup, mine] = await Promise.all([
      getChampionMap(), getMatchup(targetId, counterId), fromId ? getMyProposal(auth.user.id, fromId) : null,
    ]);
    const from = mine?.type === 'doc_edit' && mine.counter_id === matchup?.counter.id ? mine : null;
    return { champs, matchup, from };
  }, [targetId, counterId, fromId, auth.user.id]);

  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  const target = data.champs[targetId];
  const counter = data.champs[counterId];
  if (!target || !counter || !data.matchup) return <NotFound />;
  const doc = data.matchup.doc;
  const title = `${matchupTitle(counter.name, target.name)}`;

  const submit = async (content) => {
    await proposeDocEdit(auth.user.id, data.matchup.counter, content, doc?.revision_id);
    navigate('/me', { state: { sent: `${title} — 문서 수정 제안을 보냈습니다.` } });
  };

  return (
    <article>
      <nav className="crumbs">
        <Link to="/">홈</Link> › <Link to={`/champion/${targetId}`}>{target.name}</Link> ›{' '}
        <Link to={`/champion/${targetId}/counter/${counterId}`}>{counter.name}</Link> › 수정 제안
      </nav>
      <h1 className="doc-title">{title} — 수정 제안</h1>
      {data.from ? (
        <p className="notice" role="status">
          거절된 내 제안의 글을 채워 뒀습니다. 거절 사유를 보고 고쳐서 보내 주세요. (그 사이 문서가 바뀌었을 수 있습니다)
        </p>
      ) : (
        <p className="lead">지금 문서 내용이 채워져 있습니다. 고칠 부분만 바꿔서 보내 주세요.</p>
      )}
      <DocForm
        initial={data.from?.content ?? doc} onSubmit={submit} requireChange={!data.from}
        cancelTo={`/champion/${targetId}/counter/${counterId}`}
      />
    </article>
  );
}
