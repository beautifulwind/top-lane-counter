import { useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { getChampionMap, getItems, getLatestVersion, getRunes, getSummonerSpells } from '../api/ddragon';
import { getMatchup } from '../api/content';
import { getBuilds } from '../api/builds';
import { useAsync } from '../lib/useAsync';
import { useAuth } from '../lib/auth';
import { ErrorBox, Loading } from '../components/Status';
import BuildCard from '../components/BuildCard';
import NoteForm from '../components/NoteForm';
import { hideCounter } from '../api/proposals';
import { REQUIRED_LEVELS } from '../lib/docContent';
import NotFound from './NotFound';


export default function Matchup() {
  const { targetId, counterId } = useParams();
  const { isOperator, user } = useAuth();
  const userId = user?.id ?? null;
  const navigate = useNavigate();
  const [hiding, setHiding] = useState(false);
  const [buildNotice, setBuildNotice] = useState(null);
  const { data, error, loading, retry } = useAsync(
    async () => {
      const [champs, matchup] = await Promise.all([getChampionMap(), getMatchup(targetId, counterId)]);
      const builds = matchup ? await getBuilds(matchup.counter.id, userId) : [];
      const [items, runes, spells, latest] = await Promise.all([
        getItems(),
        getRunes(),
        getSummonerSpells(),
        getLatestVersion(),
      ]);
      return { champs, matchup, builds, items, runes, spells, latest };
    },
    [targetId, counterId, userId],
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
          <li><a href="#cautions">특이사항</a></li>
          <li><a href="#builds">빌드</a></li>
        </ol>
      </nav>

      <section className="section" id="levels">
        <h2 className="section-title"><span className="num">1.</span> 레벨별 딜교법</h2>
        <LevelList doc={doc} />
      </section>

      <section className="section" id="cautions">
        <h2 className="section-title"><span className="num">2.</span> 특이사항</h2>
        {doc?.lane_cautions ? (
          <div className="prose">{doc.lane_cautions}</div>
        ) : (
          <p className="empty">아직 작성된 내용이 없어요.</p>
        )}
        <div className="actions">
          <Link to={`/champion/${targetId}/counter/${counterId}/edit`} className="btn">문서 수정 제안</Link>
          {isOperator && <Link to={`/admin/history/${targetId}/${counterId}`} className="btn">수정 기록</Link>}
          {isOperator && (
            <button type="button" className="btn" onClick={() => setHiding((v) => !v)} aria-expanded={hiding}>
              카운터 숨기기
            </button>
          )}
        </div>
        {hiding && (
          <NoteForm
            id="hide-reason"
            label="숨기는 사유 (필수, 제안자에게 보여요)"
            hint="숨기면 다른 사람에게 이 카운터·문서·빌드가 안 보여요. 이 카운터를 만든 제안은 승인 취소가 돼요. 운영자 페이지에서 다시 공개할 수 있어요."
            confirmLabel="숨기기 확정"
            busyLabel="숨기는 중…"
            onCancel={() => setHiding(false)}
            onSubmit={async (reason) => {
              await hideCounter(data.matchup.counter.id, reason);
              navigate(`/champion/${targetId}`, { state: { done: `숨겼어요: ${counter.name}(으)로 ${target.name} 잡는 법` } });
            }}
          />
        )}
      </section>

      <section className="section" id="builds">
        <h2 className="section-title"><span className="num">3.</span> 빌드</h2>
        <p className="hint">점수(따봉 − 비추)가 높은 순서예요. 점수가 같으면 투표가 많은 빌드, 그다음 최근 빌드가 먼저예요.</p>
        {buildNotice && <p className="notice" role="status">{buildNotice}</p>}
        {data.builds.length === 0 ? (
          <p className="empty">아직 등록된 빌드가 없어요.</p>
        ) : (
          data.builds.map((b) => (
            <BuildCard
              key={b.id}
              build={b}
              {...data}
              interactive
              lastOne={data.builds.length === 1}
              onHidden={(message) => {
                setBuildNotice(message);
                retry();
              }}
            />
          ))
        )}
        <div className="actions">
          <Link to={`/champion/${targetId}/counter/${counterId}/build/new`} className="btn">+ 빌드 등록</Link>
        </div>
      </section>
    </article>
  );
}

/** 레벨별 딜교법 목록 (매치업 문서·운영자 미리보기 공용) */
export function LevelList({ doc }) {
  const levels = doc
    ? Object.entries(doc.level_notes ?? {})
        .map(([lv, text]) => [Number(lv), text])
        .sort((a, b) => a[0] - b[0])
    : [];
  if (levels.length === 0) return <p className="empty">아직 작성된 내용이 없어요.</p>;
  return (
    <dl className="level-list">
      {levels.map(([lv, text]) => (
        <div key={lv} className={REQUIRED_LEVELS.includes(lv) ? 'level req' : 'level'}>
          <dt>{lv}레벨</dt>
          <dd>{text}</dd>
        </div>
      ))}
    </dl>
  );
}
