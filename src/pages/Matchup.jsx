import { useEffect, useRef, useState } from 'react';
import { Link, useLocation, useNavigate, useParams, useSearchParams } from 'react-router-dom';
import { getChampionMap, getItems, getLatestVersion, getRunes, getSummonerSpells } from '../api/ddragon';
import { getMatchup } from '../api/content';
import { getBuilds, hideBuild } from '../api/builds';
import { DOC_COMMENT_OPS, getDocComments, getEditRules } from '../api/board';
import CommentThread from '../components/CommentThread';
import { useAsync } from '../lib/useAsync';
import { canModerate, useAuth } from '../lib/auth';
import { ErrorBox, Loading } from '../components/Status';
import BuildCard from '../components/BuildCard';
import NoteForm from '../components/NoteForm';
import MoreMenu from '../components/MoreMenu';
import ContributorsDialog from '../components/ContributorsDialog';
import WikiReportBox from '../components/WikiReport';
import { hideCounter } from '../api/proposals';
import { LevelList, SummaryBox } from '../components/DocView';
import SectionHead from '../components/SectionHead';
import { AlertIcon, LayersIcon, ThumbIcon, TrendingUpIcon } from '../components/Icons';
import NotFound from './NotFound';
import { matchupTitle } from '../lib/josa';
import { patchMinor } from '../lib/buildContent';
import { buildTitleText } from '../lib/wikiBuild';
import BuildTitle from '../components/BuildTitle';
import BuildLinkBox from '../components/BuildLinkBox';
import LinkActions from '../components/LinkActions';
import VideoLink from '../components/VideoLink';
import { displayNickname } from '../lib/nickname';
import FollowButton from '../components/FollowButton';
import { getFollowStatus } from '../api/follow';

// 일찍 시작한 요청이 먼저 실패해도 처리 안 된 거부가 되지 않게 결과를 담아 두고, 원래 순서대로 풀어 본다
const settle = (p) => Promise.resolve(p).then((value) => ({ value }), (error) => ({ error }));
const unwrap = (r) => {
  if (r.error) throw r.error;
  return r.value;
};

const day = (ts) => (ts ? String(ts).slice(0, 10) : null);

/**
 * 상대법 화면 (038): 플레이할 챔피언 vs 상대 챔피언. 빌드(공략 한 벌)가 여러 개 → 가로로 넘기는 탭으로 고른다.
 * 처음에는 추천 → 점수 → 최신 순으로 맨 앞 빌드. ?build=빌드 id로 고른 빌드를 주소에 남긴다 (공유·뒤로 가기).
 * 댓글은 빌드가 아니라 상대법에 단다.
 */
export default function Matchup() {
  const { targetId, counterId } = useParams();
  const auth = useAuth();
  const { isOperator, user } = auth;
  const userId = user?.id ?? null;
  const navigate = useNavigate();
  const location = useLocation();
  const [search, setSearch] = useSearchParams();
  const [hiding, setHiding] = useState(null); // 'matchup' | 빌드 id
  const [reporting, setReporting] = useState(null); // 오류 신고 칸: 'matchup' | 빌드 id (043)
  const [notice, setNotice] = useState(location.state?.done ?? null);
  const { data, error, loading, retry } = useAsync(
    async () => {
      // Data Dragon(빌드와 무관)은 맨 처음부터, 상대법 문서와 함께 시작한다. 오류는 예전 순서(챔피언·문서 → 빌드 → 게임 데이터)대로 먼저 난 쪽을 던진다.
      const game = settle(Promise.all([getItems(), getRunes(), getSummonerSpells(), getLatestVersion()]));
      const champsReq = settle(getChampionMap());
      const matchupReq = settle(getMatchup(targetId, counterId));
      const champs = unwrap(await champsReq);
      const matchup = unwrap(await matchupReq);
      // 문서 id(counter.id)를 안 뒤에는 빌드·내 표·편집자 수·링크가 한 번에 가고, 댓글·고치기 규칙도 같이 시작한다 (댓글 칸은 이 결과를 받아 쓴다)
      const comments = matchup ? settle(Promise.all([getDocComments(matchup.counter.id), getEditRules()])) : null;
      const builds = matchup ? unwrap(await settle(getBuilds(matchup.counter.id, userId))) : [];
      const [items, runes, spells, latest] = unwrap(await game);
      return { champs, matchup, builds, items, runes, spells, latest, preload: comments && { counterRowId: matchup.counter.id, result: comments } };
    },
    [targetId, counterId, userId],
    { enabled: auth.status !== 'loading' }, // 로그인 확인이 끝난 뒤 한 번만 불러온다 (확인 전·후로 두 번 도는 것 방지). 기다리는 동안은 같은 로딩 표시
  );
  // 기다리는 동안에도 빌드와 무관한 Data Dragon은 미리 받아 둔다 (캐시돼 있어 로더가 같은 요청을 다시 보내지 않음, 실패는 로더가 다시 시도)
  useEffect(() => {
    [getChampionMap, getItems, getRunes, getSummonerSpells].forEach((f) => f().catch(() => {}));
  }, []);
  // 050: 장인 [+] 팔로우 상태 — 빌드 목록의 장인 작성자를 한 번에 묻는다(follow_status). { 장인 id: true/false }
  const [follows, setFollows] = useState({});
  const loadedBuilds = data?.builds;
  useEffect(() => {
    setFollows({});
    if (!userId || !loadedBuilds) return undefined;
    const ids = loadedBuilds.filter((b) => b.author?.influencer && b.author_id && b.author_id !== userId).map((b) => b.author_id);
    if (ids.length === 0) return undefined;
    let alive = true;
    getFollowStatus(ids).then((m) => alive && setFollows(m));
    return () => { alive = false; };
  }, [loadedBuilds, userId]);

  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  const target = data.champs[targetId];
  const counter = data.champs[counterId];
  if (!target || !counter) return <NotFound />;
  const title = matchupTitle(counter.name, target.name);
  const path = `/champion/${targetId}/counter/${counterId}`;

  const crumbs = (
    <nav className="crumbs">
      <Link to="/">홈</Link> › <Link to={`/champion/${targetId}`}>{target.name}</Link> › {counter.name}
    </nav>
  );

  if (!data.matchup) {
    return (
      <article>
        {crumbs}
        <h1 className="doc-title">{title}</h1>
        <p className="empty">아직 등록되지 않은 상대법입니다. 지금 등록하면 바로 공개됩니다.</p>
        <div className="actions">
          <Link to={`/matchup/new?target=${targetId}&mine=${counterId}`} className="btn">+ 상대법 등록</Link>
        </div>
      </article>
    );
  }

  const { builds } = data;
  const doc = data.matchup.doc;
  const wanted = Number(search.get('build')) || null;
  const index = Math.max(0, builds.findIndex((b) => b.id === wanted));
  const selected = builds[index] ?? null;
  const select = (id) => {
    setSearch((prev) => {
      const next = new URLSearchParams(prev);
      next.set('build', String(id));
      return next;
    }, { replace: true });
    setHiding(null);
    setReporting(null);
  };

  // ⋮ "오류 신고" (043): 누구에게나 보인다. 로그인 전이면 로그인으로, 비회원은 연결 안내, 정식 회원은 신고 칸
  const reportItem = (target) => ({
    label: '오류 신고',
    onSelect: () => {
      if (!user) {
        navigate('/login', { state: { from: `${location.pathname}${location.search}` } });
        return;
      }
      setHiding(null);
      setReporting(target);
    },
  });
  const reported = (message) => {
    setNotice(message);
    setReporting(null);
  };
  const matchupMenu = [
    reportItem('matchup'),
    ...(isOperator ? [
      { label: '상대법 숨기기', op: true, onSelect: () => { setReporting(null); setHiding('matchup'); } },
      { label: '예전 문서 수정 기록', op: true, to: `/admin/history/${targetId}/${counterId}` },
    ] : []),
  ];

  return (
    <article>
      {crumbs}
      <header className="vs-card">
        <div className="vs-side mine">
          <img src={counter.icon} alt="" width="64" height="64" />
          <span className="vs-role">플레이할 챔피언</span>
          <strong>{counter.name}</strong>
        </div>
        <span className="vs" aria-hidden="true">VS</span>
        <div className="vs-side enemy">
          <img src={target.icon} alt="" width="64" height="64" />
          <span className="vs-role">상대</span>
          <strong>{target.name}</strong>
        </div>
      </header>
      <div className="title-row">
        <h1 className="doc-title">{title}</h1>
        <MoreMenu items={matchupMenu} label="상대법 더보기" />
      </div>
      {notice && <p className="notice" role="status">{notice}</p>}
      {reporting === 'matchup' && (
        <WikiReportBox
          id="report-matchup"
          auth={auth}
          counterId={data.matchup.counter.id}
          what="상대법"
          onCancel={() => setReporting(null)}
          onDone={reported}
        />
      )}
      {hiding === 'matchup' && (
        <NoteForm
          id="hide-reason"
          label="숨기는 사유 (필수, 등록한 분에게 보입니다)"
          hint="숨기면 다른 사람에게 이 상대법과 모든 빌드·댓글이 안 보입니다. 운영자 페이지에서 다시 공개할 수 있습니다."
          confirmLabel="숨기기 확정"
          busyLabel="숨기는 중…"
          onCancel={() => setHiding(null)}
          onSubmit={async (reason) => {
            await hideCounter(data.matchup.counter.id, reason);
            navigate(`/champion/${targetId}`, { state: { done: `숨겼습니다: ${title}` } });
          }}
        />
      )}

      <section className="section" id="builds">
        <SectionHead icon={LayersIcon} num={1} count={builds.length}>빌드</SectionHead>
        {builds.length === 0 ? (
          <>
            <p className="empty">공개된 빌드가 없습니다.</p>
            <div className="actions">
              <Link to={`${path}/build/new`} className="btn btn-primary">+ 새 빌드</Link>
            </div>
          </>
        ) : (
          <BuildTabs builds={builds} selected={selected} onSelect={select} newTo={`${path}/build/new?from=${selected.id}`} />
        )}
      </section>

      {selected && (
        <BuildPanel
          key={selected.id}
          build={selected}
          index={index}
          doc={doc}
          data={data}
          path={path}
          isOperator={isOperator}
          canHide={canModerate(auth, selected.author_id, selected.author)}
          lastOne={builds.length === 1}
          canLink={!!auth.profile?.influencer && !!userId && selected.author_id === userId}
          follow={selected.author?.influencer && selected.author_id && selected.author_id !== userId ? {
            following: !!follows[selected.author_id],
            onChange: (r) => setFollows((m) => ({ ...m, [selected.author_id]: !!r?.following })),
          } : null}
          onLinkSaved={(message) => { setNotice(message); retry(); }}
          hiding={hiding === selected.id}
          setHiding={(v) => { setReporting(null); setHiding(v); }}
          reportItem={reportItem(selected.id)}
          reportBox={reporting === selected.id && (
            <WikiReportBox
              id={`report-build-${selected.id}`}
              auth={auth}
              counterId={data.matchup.counter.id}
              buildId={selected.id}
              what={buildTitleText(selected, index)}
              onCancel={() => setReporting(null)}
              onDone={reported}
            />
          )}
          onHidden={(message) => {
            setNotice(message);
            setHiding(null);
            setSearch({}, { replace: true });
            retry();
          }}
        />
      )}

      <DocComments counterRowId={data.matchup.counter.id} auth={auth} live num={4} preload={data.preload} />
    </article>
  );
}

/**
 * 빌드 탭: 가로로 넘긴다 (폰). 이름(없으면 "빌드 N", 장인 빌드면 앞에 "장인 빌드") + 추천 수. ←→·Home·End로 옮기면 바로 그 빌드가 보인다.
 */
function BuildTabs({ builds, selected, onSelect, newTo }) {
  const refs = useRef({});
  const moved = useRef(false);
  useEffect(() => {
    const el = refs.current[selected.id];
    el?.scrollIntoView?.({ block: 'nearest', inline: 'nearest' });
    if (moved.current) el?.focus();
    moved.current = false;
  }, [selected.id]);

  const onKeyDown = (e) => {
    const at = builds.findIndex((b) => b.id === selected.id);
    const to = { ArrowRight: at + 1, ArrowLeft: at - 1, Home: 0, End: builds.length - 1 }[e.key];
    if (to === undefined) return;
    e.preventDefault();
    const next = builds[(to + builds.length) % builds.length];
    moved.current = true;
    if (next.id === selected.id) refs.current[next.id]?.focus();
    else onSelect(next.id);
  };

  return (
    <div className="build-tabs-row">
      <div className="build-tabs" role="tablist" aria-label="빌드 고르기" onKeyDown={onKeyDown}>
        {builds.map((b, i) => {
          const on = b.id === selected.id;
          return (
            <button
              key={b.id}
              ref={(el) => { refs.current[b.id] = el; }}
              type="button"
              role="tab"
              id={`build-tab-${b.id}`}
              aria-selected={on}
              aria-controls="build-panel"
              tabIndex={on ? 0 : -1}
              className={on ? 'build-tab on' : 'build-tab'}
              onClick={() => onSelect(b.id)}
            >
              <span className="build-tab-name"><BuildTitle build={b} index={i} /></span>{' '}
              <span className="build-tab-ups">
                <ThumbIcon size={14} /><span className="sr-only">추천 </span>{b.up}
              </span>
            </button>
          );
        })}
      </div>
      <Link to={newTo} className="btn btn-small new-build">+ 새 빌드</Link>
    </div>
  );
}

/** 고른 빌드 한 벌: 이름·패치·최근 수정 → 한 줄 결론 → 룬·주문·아이템·선마·추천 → 레벨별 딜교법 → 특이사항 → [빌드 수정]·[수정 기록] */
function BuildPanel({ build, index, doc, data, path, isOperator, canHide, lastOne, hiding, setHiding, onHidden, reportItem, reportBox, canLink, onLinkSaved, follow }) {
  const [showPeople, setShowPeople] = useState(false);
  const peopleBtn = useRef(null);
  const label = buildTitleText(build, index);
  // 038 뒤 공개된 빌드는 글이 다 채워져 있다. 혹시 비어 있으면 예전 문서 내용으로
  const summary = build.summary ?? doc?.summary ?? null;
  const notes = build.level_notes ?? doc?.level_notes ?? null;
  const cautions = build.lane_cautions ?? doc?.lane_cautions ?? '';
  const updated = day(build.updated_at ?? build.edited_at ?? build.created_at);

  // 숨기기: 운영자는 전부, 감독관은 일반 회원·탈퇴한 분이 처음 만든 빌드만 (043, 실제 검사는 DB). 수정 기록 자세히·되돌리기는 운영자만
  const menu = [
    reportItem,
    canHide && {
      label: '빌드 숨기기', op: true, disabled: lastOne, onSelect: () => setHiding(build.id),
      hint: lastOne ? '마지막 공개 빌드라 숨길 수 없습니다. 상대법을 숨겨 주세요.' : null,
    },
    isOperator && { label: '수정 기록 자세히', op: true, to: `/admin/builds/${build.id}/history` },
  ];

  return (
    <div id="build-panel" role="tabpanel" aria-labelledby={`build-tab-${build.id}`} className="build-panel">
      <div className="title-row">
        <h3 className="build-name"><BuildTitle build={build} index={index} editors /></h3>
        <MoreMenu items={menu} label={`${label} 더보기`} />
      </div>
      <p className="doc-sub">
        {build.patch && <>패치 {patchMinor(build.patch)}</>}
        {updated && <>{build.patch ? ' · ' : ''}최근 수정 {updated}</>}
      </p>
      {build.link && (
        // 047: 처음 만든 장인이 단 링크 (빌드 내용과 따로). 누르면 이동 확인 창
        <div className="build-link-row link-item">
          <VideoLink link={build.link} />
          {/* 3b: 신고(정식 회원) / 삭제(운영자 전부, 감독관은 일반 장인 링크만) */}
          <LinkActions link={build.link} ownerId={build.author_id} owner={build.author} label="장인 링크 더보기" onDone={onLinkSaved} />
        </div>
      )}
      {reportBox}
      {hiding && (
        <NoteForm
          id={`hide-build-${build.id}`}
          label="숨기는 사유 (필수, 처음 만든 분에게 보입니다)"
          hint="숨기면 다른 사람에게 이 빌드가 안 보입니다. 추천 수는 그대로 남고, 운영자 페이지의 숨긴 빌드에서 다시 공개할 수 있습니다."
          confirmLabel="숨기기 확정"
          busyLabel="숨기는 중…"
          onCancel={() => setHiding(null)}
          onSubmit={async (reason) => {
            await hideBuild(build.id, reason);
            onHidden(`빌드를 숨겼습니다. (${label} · ${displayNickname(build.author)})`);
          }}
        />
      )}
      {summary && <SummaryBox summary={summary} />}

      <nav className="toc" aria-label="목차">
        <strong>목차</strong>
        <ol>
          <li><a href="#builds">빌드</a></li>
          <li><a href="#levels">레벨별 딜교법</a></li>
          <li><a href="#cautions">특이사항</a></li>
          <li><a href="#comments">댓글</a></li>
        </ol>
      </nav>

      <BuildCard
        build={build} {...data} interactive
        authorExtra={follow && (
          // 050: 장인이 처음 만든 빌드의 작성자 옆 [+] (내 빌드·장인 아닌 작성자는 없음). 닉네임을 누르면 장인 페이지 — 그대로
          <>{' '}<FollowButton plus id={build.author_id} nickname={build.author?.nickname} following={follow.following} onChange={follow.onChange} /></>
        )}
      />

      <section className="section" id="levels">
        <SectionHead icon={TrendingUpIcon} num={2}>레벨별 딜교법</SectionHead>
        <LevelList doc={notes ? { level_notes: notes } : null} />
      </section>

      <section className="section" id="cautions">
        <SectionHead icon={AlertIcon} num={3}>특이사항</SectionHead>
        {cautions ? (
          <div className="prose caution-box">{cautions}</div>
        ) : (
          <p className="empty">아직 작성된 내용이 없습니다.</p>
        )}
        <div className="actions">
          <Link to={`${path}/build/${build.id}/edit`} className="btn">빌드 수정</Link>
          <button
            ref={peopleBtn}
            type="button"
            className="btn"
            aria-haspopup="dialog"
            onClick={() => setShowPeople(true)}
          >
            수정 기록
          </button>
        </div>
      </section>
      {canLink && <BuildLinkBox build={build} onSaved={onLinkSaved} />}
      {showPeople && (
        <ContributorsDialog build={build} title={label} opener={peopleBtn} onClose={() => setShowPeople(false)} />
      )}
    </div>
  );
}

/**
 * 문서 댓글 (SPEC 6-5): 문서와 따로 불러온다 → 댓글을 달거나 처리해도 문서 전체가 다시 그려지지 않는다.
 * live = 카운터가 공개 중인가 (숨긴 카운터 미리보기에서는 false: 새 댓글·고치기·신고 없음, 운영자 숨기기·다시 공개만)
 */
export function DocComments({ counterRowId, auth, live, num, preload = null }) {
  const [notice, setNotice] = useState(null);
  // preload = 상대법 화면이 문서를 읽자마자 미리 보낸 요청 { counterRowId, result }. 첫 로딩에만 쓰고, 댓글을 단 뒤 다시 읽을 때는 새로 읽는다
  const early = useRef(preload);
  const { data, error, loading, retry } = useAsync(async () => {
    const p = early.current;
    early.current = null;
    if (p && p.counterRowId === counterRowId) {
      const r = await p.result;
      if (r.error) throw r.error;
      const [comments, rules] = r.value;
      return { comments, rules };
    }
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
        closedHint={live ? null : '숨긴 상대법이라 새 댓글은 달 수 없습니다.'}
        onDone={(message) => {
          setNotice(message);
          retry();
        }}
        onReload={retry}
      />
    </>
  );
}
