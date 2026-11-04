import { useRef, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { getChampionMap, getItems, getLatestVersion, getRunes, getSummonerSpells } from '../api/ddragon';
import { getMatchup } from '../api/content';
import { getBuilds } from '../api/builds';
import { DOC_COMMENT_OPS, getDocComments, getEditRules } from '../api/board';
import CommentThread from '../components/CommentThread';
import { useAsync } from '../lib/useAsync';
import { useAuth } from '../lib/auth';
import { ErrorBox, Loading } from '../components/Status';
import BuildCard from '../components/BuildCard';
import NoteForm from '../components/NoteForm';
import { hideCounter } from '../api/proposals';
import { LevelList, SummaryBox } from '../components/DocView';
import SectionHead from '../components/SectionHead';
import { AlertIcon, LayersIcon, MessageIcon, TrendingUpIcon } from '../components/Icons';
import NotFound from './NotFound';
import { matchupTitle } from '../lib/josa';


export default function Matchup() {
  const { targetId, counterId } = useParams();
  const auth = useAuth();
  const { isOperator, user } = auth;
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
          {matchupTitle(counter.name, target.name)}
        </h1>
        <p className="empty">아직 등록되지 않은 카운터입니다. 새 카운터로 제안할 수 있습니다.</p>
        <div className="actions">
          <Link to={`/champion/${targetId}/propose?counter=${counterId}`} className="btn">+ 카운터 등록</Link>
        </div>
      </article>
    );
  }

  const doc = data.matchup.doc;

  return (
    <article>
      {crumbs}
      <header className="vs-card">
        <div className="vs-side mine">
          <img src={counter.icon} alt="" width="64" height="64" />
          <span className="vs-role">카운터</span>
          <strong>{counter.name}</strong>
        </div>
        <span className="vs" aria-hidden="true">VS</span>
        <div className="vs-side enemy">
          <img src={target.icon} alt="" width="64" height="64" />
          <span className="vs-role">상대</span>
          <strong>{target.name}</strong>
        </div>
      </header>
      <h1 className="doc-title">
        {matchupTitle(counter.name, target.name)}
      </h1>
      {doc?.updated_at && <p className="doc-sub">최근 수정: {doc.updated_at}</p>}
      {doc?.summary && <SummaryBox summary={doc.summary} />}

      <nav className="toc" aria-label="목차">
        <strong>목차</strong>
        <ol>
          <li><a href="#builds">빌드</a></li>
          <li><a href="#levels">레벨별 딜교법</a></li>
          <li><a href="#cautions">특이사항</a></li>
          <li><a href="#comments">댓글</a></li>
        </ol>
      </nav>

      <section className="section" id="builds">
        <SectionHead icon={LayersIcon} num={1} count={data.builds.length}>빌드</SectionHead>
        <p className="hint">점수(추천 − 비추천)가 높은 순서입니다. 점수가 같으면 투표가 많은 빌드, 그다음 최근 빌드가 먼저입니다.</p>
        {buildNotice && <p className="notice" role="status">{buildNotice}</p>}
        {data.builds.length === 0 ? (
          <p className="empty">아직 등록된 빌드가 없습니다.</p>
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

      <section className="section" id="levels">
        <SectionHead icon={TrendingUpIcon} num={2}>레벨별 딜교법</SectionHead>
        <LevelList doc={doc} />
      </section>

      <section className="section" id="cautions">
        <SectionHead icon={AlertIcon} num={3}>특이사항</SectionHead>
        {doc?.lane_cautions ? (
          <div className="prose caution-box">{doc.lane_cautions}</div>
        ) : (
          <p className="empty">아직 작성된 내용이 없습니다.</p>
        )}
        <div className="actions">
          <Link to={`/champion/${targetId}/counter/${counterId}/edit`} className="btn">문서 수정 제안</Link>
          {isOperator && <Link to={`/admin/history/${targetId}/${counterId}`} className="btn btn-op">수정 기록</Link>}
          {isOperator && (
            <button type="button" className="btn btn-op" onClick={() => setHiding((v) => !v)} aria-expanded={hiding}>
              카운터 숨기기
            </button>
          )}
        </div>
        {hiding && (
          <NoteForm
            id="hide-reason"
            label="숨기는 사유 (필수, 제안자에게 보입니다)"
            hint="숨기면 다른 사람에게 이 카운터·문서·빌드가 안 보입니다. 이 카운터를 만든 제안은 승인 취소가 됩니다. 운영자 페이지에서 다시 공개할 수 있습니다."
            confirmLabel="숨기기 확정"
            busyLabel="숨기는 중…"
            onCancel={() => setHiding(false)}
            onSubmit={async (reason) => {
              await hideCounter(data.matchup.counter.id, reason);
              navigate(`/champion/${targetId}`, { state: { done: `숨겼습니다: ${matchupTitle(counter.name, target.name)}` } });
            }}
          />
        )}
      </section>

      <DocComments counterRowId={data.matchup.counter.id} auth={auth} live num={4} />
    </article>
  );
}

/**
 * 문서 댓글 (SPEC 6-5): 문서와 따로 불러온다 → 댓글을 달거나 처리해도 문서 전체가 다시 그려지지 않는다.
 * live = 카운터가 공개 중인가 (숨긴 카운터 미리보기에서는 false: 새 댓글·고치기·신고 없음, 운영자 숨기기·다시 공개만)
 */
export function DocComments({ counterRowId, auth, live, num }) {
  const [notice, setNotice] = useState(null);
  const { data, error, loading, retry } = useAsync(async () => {
    const [comments, rules] = await Promise.all([getDocComments(counterRowId), getEditRules()]);
    return { comments, rules };
  }, [counterRowId]);
  const last = useRef(null);
  if (data) last.current = data;
  const shown = data ?? (loading ? last.current : null);

  if (!shown && loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  return (
    <>
      {notice && <p className="notice" role="status">{notice}</p>}
      <CommentThread
        ops={DOC_COMMENT_OPS} parentId={counterRowId} comments={shown.comments} auth={auth} rules={shown.rules}
        open={live} live={live} num={num}
        closedHint={live ? null : '숨긴 카운터라 새 댓글은 달 수 없습니다.'}
        onDone={(message) => {
          setNotice(message);
          retry();
        }}
        onReload={retry}
      />
    </>
  );
}
