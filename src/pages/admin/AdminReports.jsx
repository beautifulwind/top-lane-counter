import { displayNickname } from '../../lib/nickname';
import { useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { REPORT_REASONS, dismissReports, getOpenReports, hideComment, hideDocComment, hidePost } from '../../api/board';
import { getChampionMap } from '../../api/ddragon';
import { useAsync } from '../../lib/useAsync';
import { fmtDateTime } from '../../lib/format';
import { ErrorBox, Loading } from '../../components/Status';
import { RequireStaff } from '../../components/RequireOperator';
import { useAuth } from '../../lib/auth';
import UserName from '../../components/UserName';
import NoteForm from '../../components/NoteForm';
import { matchupTitle } from '../../lib/josa';
import { FlagIcon } from '../../components/Icons';
import WikiReportList from '../../components/WikiReportAdmin';
import LinkReportList from '../../components/LinkReportAdmin';
import { DismissForm } from '../../components/DismissForm';

/**
 * 운영진: 신고 (/admin/reports). 탭 — "글·댓글 신고"(기본) / "오류 신고"(?tab=wiki, 043 상대법·빌드 내용 오류)
 * / "링크 신고"(?tab=links, 047·048 장인 외부 링크 — 운영자만).
 * 글·댓글 신고: 자유게시판·문서 댓글. 같은 글·댓글의 신고는 한 줄로 묶는다.
 * [숨기기] = 메모 필수, 작성자에게 알림, 그 대상의 신고는 "처리됨" / [신고 기각] = 메모 선택, 글·댓글은 그대로
 * 자동 숨김은 없다 (운영자가 보고 정한다)
 */
export default function AdminReports() {
  return (
    <RequireStaff>
      <ReportsPage />
    </RequireStaff>
  );
}

function ReportsPage() {
  const { isOperator } = useAuth();
  const [params, setParams] = useSearchParams();
  // 'board'(기본) | 'wiki' | 'links'(운영자만 — 047·048 링크 신고 목록·기각은 운영자 전용)
  const asked = params.get('tab');
  const current = asked === 'wiki' || (asked === 'links' && isOperator) ? asked : 'board';
  const tab = (key, label) => {
    const on = key === current;
    return (
      <button
        type="button" role="tab" aria-selected={on} className={`build-tab${on ? ' on' : ''}`}
        onClick={() => setParams(key === 'board' ? {} : { tab: key }, { replace: true })}
      >
        <span className="build-tab-name">{label}</span>
      </button>
    );
  };
  return (
    <article>
      <nav className="crumbs"><Link to="/admin" className="op-link">← 운영자 페이지</Link></nav>
      <h1 className="doc-title page-title"><FlagIcon size={26} className="title-icon op" /> 신고</h1>
      <div className="build-tabs" role="tablist" aria-label="신고 종류">
        {tab('board', '글·댓글 신고')}
        {tab('wiki', '오류 신고')}
        {isOperator && tab('links', '링크 신고')}
      </div>
      {current === 'wiki' ? <WikiReportList /> : current === 'links' ? <LinkReportList /> : <ReportList />}
    </article>
  );
}

function ReportList() {
  const auth = useAuth();
  const [done, setDone] = useState(null);
  const { data, error, loading, retry } = useAsync(async () => {
    const [champs, groups] = await Promise.all([getChampionMap(), getOpenReports(auth.isModerator)]);
    return { champs, groups };
  }, []);
  const finished = (message) => {
    setDone(message);
    retry();
  };
  return (
    <section aria-label="글·댓글 신고">
      {data && <p><span className="count-badge">{data.groups.length}개</span></p>}
      {done && <p className="notice" role="status">{done}</p>}
      <p className="hint">같은 글·댓글의 신고는 한 줄로 묶었습니다. 숨기면 작성자에게 메모와 함께 알림이 갑니다. 기각하면 그대로 두고 신고만 닫습니다.</p>
      {loading && <Loading />}
      {error && <ErrorBox error={error} onRetry={retry} />}
      {data && data.groups.length === 0 && <p className="empty">처리할 신고가 없습니다.</p>}
      {data && data.groups.length > 0 && (
        <ul className="proposal-list" aria-label="신고 목록">
          {data.groups.map((g) => <ReportGroup key={g.key} group={g} champs={data.champs} onDone={finished} />)}
        </ul>
      )}
    </section>
  );
}

function ReportGroup({ group: g, champs, onDone }) {
  const { isModerator } = useAuth();
  const [mode, setMode] = useState(null); // 'hide' | 'dismiss'
  const isPost = g.postId != null;
  const isDoc = g.docCommentId != null;
  const target = isPost ? g.post : isDoc ? g.docComment : g.comment;
  const deleted = isPost && g.post?.deleted_at != null;
  const preview = isPost ? (deleted ? '(삭제된 글)' : g.post?.title) : target?.body;
  const what = isPost ? '글' : isDoc ? '문서 댓글' : '댓글';
  const label = `${what} 신고 ${g.reports.length}건`;
  const counter = g.docComment?.counter;
  const name = (id) => champs[id]?.name ?? id;
  const matchup = counter && `${matchupTitle(name(counter.counter_champion), name(counter.target_champion))}`;
  const goTo = isDoc
    ? counter && (counter.status === 'approved'
      ? `/champion/${counter.target_champion}/counter/${counter.counter_champion}#comments`
      : `/admin/preview/${counter.target_champion}/${counter.counter_champion}`)
    : `/board/${isPost ? g.postId : g.comment?.post_id}`;

  return (
    <li className="proposal-row report-row" aria-label={label}>
      <div className="proposal-main">
        <span className="proposal-type">{what}</span> <span className="report-count">신고 {g.reports.length}건</span>
      </div>
      {matchup && <p className="hint">{matchup}{counter.status !== 'approved' && ' (숨긴 상대법)'}</p>}
      <p className="report-preview">{preview}</p>
      {isPost && !deleted && g.post?.body && <p className="report-preview body">{g.post.body.slice(0, 200)}{g.post.body.length > 200 ? '…' : ''}</p>}
      <div className="proposal-meta">
        <span>작성자: {target?.author ? <UserName profile={target.author} /> : '(탈퇴한 유저)'}</span>
        {g.hides && (
          // 반복 위반 판단용 (021). 제재 기능은 아직 없다 — SPEC 6-11
          <span className={g.hides.count > 0 ? 'op-badge hide-count' : 'hide-count'}>최근 {g.hides.days}일 숨김 {g.hides.count}회</span>
        )}
        {target?.status === 'hidden' && <span className="op-badge">이미 숨김</span>}
      </div>
      <ul className="log-list" aria-label="신고 내용">
        {g.reports.map((r) => (
          <li key={r.id}>
            <strong>{REPORT_REASONS[r.reason] ?? r.reason}</strong>
            {r.detail && <> — {r.detail}</>}
            <small> ({!isModerator && <>{displayNickname(r.reporter)}, </>}{fmtDateTime(r.created_at)})</small>
          </li>
        ))}
      </ul>
      {mode === null && (
        <div className="row-actions">
          {target?.status !== 'hidden' && !deleted && (
            <button type="button" className="btn btn-small btn-op" onClick={() => setMode('hide')}>숨기기</button>
          )}
          <button type="button" className="btn btn-small btn-op" onClick={() => setMode('dismiss')}>신고 기각</button>
          {goTo && <Link to={goTo} className="btn btn-small btn-op">보러 가기</Link>}
        </div>
      )}
      {mode === 'hide' && (
        <NoteForm
          id={`hide-${g.key}`}
          label="숨기는 사유 (필수, 작성자에게 보입니다)"
          confirmLabel="숨기기 확정"
          busyLabel="숨기는 중…"
          onCancel={() => setMode(null)}
          onSubmit={async (note) => {
            if (isPost) await hidePost(g.postId, note);
            else if (isDoc) await hideDocComment(g.docCommentId, note);
            else await hideComment(g.commentId, note);
            onDone(`${isPost ? '글' : '댓글'}을 숨겼습니다. 신고 ${g.reports.length}건은 처리됨으로 닫았습니다.`);
          }}
        />
      )}
      {mode === 'dismiss' && (
        <DismissForm
          id={`dismiss-${g.key}`}
          onCancel={() => setMode(null)}
          onSubmit={async (note) => {
            const n = await dismissReports({ postId: g.postId, commentId: g.commentId, docCommentId: g.docCommentId }, note);
            onDone(`신고 ${n ?? g.reports.length}건을 기각했습니다.`);
          }}
        />
      )}
    </li>
  );
}
