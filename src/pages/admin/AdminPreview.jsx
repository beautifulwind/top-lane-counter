import { Link, useParams } from 'react-router-dom';
import { getChampionMap, getItems, getLatestVersion, getRunes, getSummonerSpells } from '../../api/ddragon';
import { getBuilds } from '../../api/builds';
import { getHiddenMatchup } from '../../api/proposals';
import { useAsync } from '../../lib/useAsync';
import { ErrorBox, Loading } from '../../components/Status';
import RequireOperator from '../../components/RequireOperator';
import { LevelList } from '../Matchup';
import BuildCard from '../../components/BuildCard';

/** 숨긴 카운터 미리보기 (읽기 전용): /admin/preview/:targetId/:counterId — 숨긴 문서·빌드는 DB가 운영자에게만 보여 준다 */
export default function AdminPreview() {
  return (
    <RequireOperator>
      <Preview />
    </RequireOperator>
  );
}

function Preview() {
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
  const doc = data.matchup.doc;

  return (
    <article>
      {crumbs}
      <p className="warn" role="note">숨긴 카운터 미리보기 — 다른 사람에게는 보이지 않아요.</p>
      <h1 className="doc-title">{title}</h1>
      {doc?.summary && <p className="doc-sub">{doc.summary}</p>}

      <section className="section">
        <h2 className="section-title"><span className="num">1.</span> 레벨별 딜교법</h2>
        <LevelList doc={doc} />
      </section>
      <section className="section">
        <h2 className="section-title"><span className="num">2.</span> 특이사항</h2>
        {doc?.lane_cautions ? <div className="prose">{doc.lane_cautions}</div> : <p className="empty">아직 작성된 내용이 없어요.</p>}
      </section>
      <section className="section">
        <h2 className="section-title"><span className="num">3.</span> 빌드</h2>
        {data.builds.length === 0 ? (
          <p className="empty">등록된 빌드가 없어요.</p>
        ) : (
          data.builds.map((b) => <BuildCard key={b.id} build={b} {...data} />)
        )}
      </section>
      <div className="actions">
        <Link to="/admin" className="btn">운영자 페이지로</Link>
      </div>
    </article>
  );
}
