import { Link, useParams } from 'react-router-dom';
import { getChampionMap, getItems, getLatestVersion, getRunes, getSummonerSpells } from '../../api/ddragon';
import { getBuilds } from '../../api/builds';
import { getHiddenMatchup } from '../../api/proposals';
import { useAsync } from '../../lib/useAsync';
import { ErrorBox, Loading } from '../../components/Status';
import RequireOperator from '../../components/RequireOperator';
import DocView from '../../components/DocView';
import { useAuth } from '../../lib/auth';
import { DocComments } from '../Matchup';

/** 숨긴 카운터 미리보기 (읽기 전용): /admin/preview/:targetId/:counterId — 숨긴 문서·빌드는 DB가 운영자에게만 보여 준다 */
export default function AdminPreview() {
  return (
    <RequireOperator>
      <Preview />
    </RequireOperator>
  );
}

function Preview() {
  const auth = useAuth();
  const { targetId, counterId } = useParams();
  const { data, error, loading, retry } = useAsync(async () => {
    const [champs, matchup] = await Promise.all([getChampionMap(), getHiddenMatchup(targetId, counterId)]);
    const builds = matchup ? await getBuilds(matchup.counter.id) : [];
    const [items, runes, spells, latest] = await Promise.all([getItems(), getRunes(), getSummonerSpells(), getLatestVersion()]);
    return { champs, matchup, builds, items, runes, spells, latest };
  }, [targetId, counterId]);

  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  const name = (id) => data.champs[id]?.name ?? id;
  const title = `${name(counterId)}(으)로 ${name(targetId)} 잡는 법`;
  const crumbs = <nav className="crumbs"><Link to="/admin">운영자 페이지</Link> › 미리보기</nav>;

  if (!data.matchup) {
    return (
      <article>
        {crumbs}
        <h1 className="doc-title">{title}</h1>
        <p className="empty">숨긴 카운터가 아니에요. 이미 다시 공개했거나 삭제했을 수 있어요.</p>
      </article>
    );
  }
  const { doc } = data.matchup;

  return (
    <article>
      {crumbs}
      <p className="warn" role="note">숨긴 카운터 미리보기 — 다른 사람에게는 보이지 않아요.</p>
      <h1 className="doc-title">{title}</h1>
      <DocView doc={doc ?? {}} builds={data.builds} game={data} />
      <DocComments counterRowId={data.matchup.counter.id} auth={auth} live={false} title="댓글" />
      <div className="actions">
        <Link to="/admin" className="btn btn-op">운영자 페이지로</Link>
      </div>
    </article>
  );
}
