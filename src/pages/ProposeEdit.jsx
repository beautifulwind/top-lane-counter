import { Link, useNavigate, useParams } from 'react-router-dom';
import { getChampionMap } from '../api/ddragon';
import { getMatchup } from '../api/content';
import { proposeDocEdit } from '../api/proposals';
import { useAuth } from '../lib/auth';
import { useAsync } from '../lib/useAsync';
import { ErrorBox, Loading } from '../components/Status';
import DocForm from '../components/DocForm';
import { RequireLogin } from '../components/RequireOperator';
import NotFound from './NotFound';

/** 매치업 문서 수정 제안: /champion/:targetId/counter/:counterId/edit */
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
  const { data, error, loading, retry } = useAsync(async () => {
    const [champs, matchup] = await Promise.all([getChampionMap(), getMatchup(targetId, counterId)]);
    return { champs, matchup };
  }, [targetId, counterId]);

  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  const target = data.champs[targetId];
  const counter = data.champs[counterId];
  if (!target || !counter || !data.matchup) return <NotFound />;
  const doc = data.matchup.doc;
  const title = `${counter.name}(으)로 ${target.name} 잡는 법`;

  const submit = async (content) => {
    await proposeDocEdit(auth.user.id, data.matchup.counter, content, doc?.revision_id);
    navigate('/me', { state: { sent: `${title} — 문서 수정 제안을 보냈어요.` } });
  };

  return (
    <article>
      <nav className="crumbs">
        <Link to="/">홈</Link> › <Link to={`/champion/${targetId}`}>{target.name}</Link> ›{' '}
        <Link to={`/champion/${targetId}/counter/${counterId}`}>{counter.name}</Link> › 수정 제안
      </nav>
      <h1 className="doc-title">{title} — 수정 제안</h1>
      <p className="lead">지금 문서 내용이 채워져 있어요. 고칠 부분만 바꿔서 보내 주세요.</p>
      <DocForm initial={doc} onSubmit={submit} requireChange />
    </article>
  );
}
