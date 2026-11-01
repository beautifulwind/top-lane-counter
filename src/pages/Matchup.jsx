import { Link, useParams } from 'react-router-dom';
import { getChampionMap, getItems, getLatestVersion, getRunes, getSummonerSpells } from '../api/ddragon';
import { getBuilds, getMatchup } from '../api/content';
import { useAsync } from '../lib/useAsync';
import { useAuth } from '../lib/auth';
import { ErrorBox, Loading, PendingButton } from '../components/Status';
import UserName from '../components/UserName';
import { REQUIRED_LEVELS } from '../lib/docContent';
import NotFound from './NotFound';


export default function Matchup() {
  const { targetId, counterId } = useParams();
  const { isOperator } = useAuth();
  const { data, error, loading, retry } = useAsync(
    async () => {
      const [champs, matchup] = await Promise.all([getChampionMap(), getMatchup(targetId, counterId)]);
      const builds = matchup ? await getBuilds(matchup.counter.id) : [];
      const [items, runes, spells, latest] = await Promise.all([
        getItems(),
        getRunes(),
        getSummonerSpells(),
        getLatestVersion(),
      ]);
      return { champs, matchup, builds, items, runes, spells, latest };
    },
    [targetId, counterId],
  );

  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  const target = data.champs[targetId];
  const counter = data.champs[counterId];
  if (!target || !counter) return <NotFound />;

  const crumbs = (
    <nav className="crumbs">
      <Link to="/">홈</Link> › <Link to={`/champion/${targetId}`}>{target.name}</Link> › {counter.name}
    </nav>
  );

  if (!data.matchup) {
    return (
      <article>
        {crumbs}
        <h1 className="doc-title">
          {counter.name}(으)로 {target.name} 잡는 법
        </h1>
        <p className="empty">아직 등록되지 않은 카운터예요. 새 카운터로 제안할 수 있어요.</p>
        <div className="actions">
          <Link to={`/champion/${targetId}/propose?counter=${counterId}`} className="btn">+ 새 카운터 제안</Link>
        </div>
      </article>
    );
  }

  const doc = data.matchup.doc;
  const levels = doc
    ? Object.entries(doc.level_notes)
        .map(([lv, text]) => [Number(lv), text])
        .sort((a, b) => a[0] - b[0])
    : [];

  return (
    <article>
      {crumbs}
      <header className="doc-head">
        <span className="vs-icons">
          <img src={counter.icon} alt="" width="52" height="52" />
          <span className="vs">vs</span>
          <img src={target.icon} alt="" width="52" height="52" className="loser" />
        </span>
      </header>
      <h1 className="doc-title">
        {counter.name}(으)로 {target.name} 잡는 법
      </h1>
      {doc?.updated_at && <p className="doc-sub">최근 수정: {doc.updated_at}</p>}

      <nav className="toc" aria-label="목차">
        <strong>목차</strong>
        <ol>
          <li><a href="#levels">레벨별 딜교법</a></li>
          <li><a href="#cautions">라인전 주의사항</a></li>
          <li><a href="#builds">빌드</a></li>
        </ol>
      </nav>

      <section className="section" id="levels">
        <h2 className="section-title"><span className="num">1.</span> 레벨별 딜교법</h2>
        {levels.length === 0 ? (
          <p className="empty">아직 작성된 내용이 없어요.</p>
        ) : (
          <dl className="level-list">
            {levels.map(([lv, text]) => (
              <div key={lv} className={REQUIRED_LEVELS.includes(lv) ? 'level req' : 'level'}>
                <dt>{lv}레벨</dt>
                <dd>{text}</dd>
              </div>
            ))}
          </dl>
        )}
      </section>

      <section className="section" id="cautions">
        <h2 className="section-title"><span className="num">2.</span> 라인전 주의사항</h2>
        {doc?.lane_cautions ? (
          <div className="prose">{doc.lane_cautions}</div>
        ) : (
          <p className="empty">아직 작성된 내용이 없어요.</p>
        )}
        <div className="actions">
          <Link to={`/champion/${targetId}/counter/${counterId}/edit`} className="btn">문서 수정 제안</Link>
          {isOperator && <Link to={`/admin/history/${targetId}/${counterId}`} className="btn">수정 기록</Link>}
          {isOperator && <Link to={`/admin/hide/${targetId}/${counterId}`} className="btn">카운터 숨기기</Link>}
        </div>
      </section>

      <section className="section" id="builds">
        <h2 className="section-title"><span className="num">3.</span> 빌드</h2>
        <p className="hint">따봉 점수(따봉 − 반대)가 높은 순서예요.</p>
        {data.builds.length === 0 ? (
          <p className="empty">아직 등록된 빌드가 없어요.</p>
        ) : (
          data.builds.map((b) => <BuildCard key={b.id} build={b} {...data} />)
        )}
        <div className="actions">
          <PendingButton>+ 빌드 등록</PendingButton>
        </div>
      </section>
    </article>
  );
}

function Icon({ entry, size = 32, round = false }) {
  if (!entry) return null;
  return (
    <img
      src={entry.icon}
      alt={entry.name}
      title={entry.name}
      width={size}
      height={size}
      className={round ? 'ico round' : 'ico'}
      loading="lazy"
    />
  );
}

function BuildCard({ build, items, runes, spells, latest }) {
  const r = build.runes;
  const outdated = build.patch !== latest;
  const score = build.up - build.down;
  return (
    <div className="build">
      <div className="build-head">
        <span className="build-author">
          {build.author ? <UserName profile={build.author} /> : '예시 빌드'}
        </span>
        <span className={outdated ? 'badge old' : 'badge'}>
          {outdated ? `구버전 · ${build.patch}` : `패치 ${build.patch}`}
        </span>
      </div>

      <div className="build-row">
        <span className="label">특성</span>
        <div className="icons">
          <Icon entry={runes.runes[r.keystone]} size={40} round />
          {r.primary.map((id) => <Icon key={id} entry={runes.runes[id]} size={28} round />)}
          <span className="sep" />
          <Icon entry={runes.paths[r.secondaryPath]} size={22} round />
          {r.secondary.map((id) => <Icon key={id} entry={runes.runes[id]} size={28} round />)}
          <span className="sep" />
          {r.shards.map((id, i) => <Icon key={i} entry={runes.shards[id]} size={20} round />)}
        </div>
      </div>

      <div className="build-row">
        <span className="label">주문</span>
        <div className="icons">
          {build.summoner_spells.map((id) => <Icon key={id} entry={spells[id]} />)}
        </div>
      </div>

      <div className="build-row">
        <span className="label">시작</span>
        <div className="icons">
          {build.starting_items.map((id, i) => <Icon key={i} entry={items[id]} />)}
        </div>
      </div>

      <div className="build-row">
        <span className="label">템트리</span>
        <div className="icons">
          {build.core_items.map((id, i) => (
            <span key={i} className="step">
              {i > 0 && <span className="arrow">›</span>}
              <Icon entry={items[id]} />
            </span>
          ))}
        </div>
      </div>

      <div className="build-row">
        <span className="label">스킬</span>
        <div className="skills">
          {build.skill_order.map((k, i) => (
            <span key={k} className="step">
              {i > 0 && <span className="arrow">›</span>}
              <kbd>{k}</kbd>
            </span>
          ))}
        </div>
      </div>

      <div className="votes">
        <button type="button" className="vote" onClick={() => alert('투표는 로그인 기능 이후에 연결됩니다.')}>
          👍 {build.up}
        </button>
        <button type="button" className="vote" onClick={() => alert('투표는 로그인 기능 이후에 연결됩니다.')}>
          👎 {build.down}
        </button>
        <span className="score">점수 {score > 0 ? `+${score}` : score}</span>
      </div>
    </div>
  );
}
