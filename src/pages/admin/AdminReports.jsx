import { useState } from 'react';
import { Link } from 'react-router-dom';
import { REPORT_REASONS, dismissReports, getOpenReports, hideComment, hideDocComment, hidePost } from '../../api/board';
import { getChampionMap } from '../../api/ddragon';
import { useAsync } from '../../lib/useAsync';
import { fmtDateTime } from '../../lib/format';
import { ErrorBox, Loading } from '../../components/Status';
import RequireOperator from '../../components/RequireOperator';
import UserName from '../../components/UserName';
import NoteForm from '../../components/NoteForm';
import { matchupTitle } from '../../lib/josa';
import { FlagIcon } from '../../components/Icons';

/**
 * 운영자: 자유게시판·문서 댓글 신고 (/admin/reports). 같은 글·댓글의 신고는 한 줄로 묶는다.
 * [숨기기] = 메모 필수, 작성자에게 알림, 그 대상의 신고는 "처리됨" / [신고 기각] = 메모 선택, 글·댓글은 그대로
 * 자동 숨김은 없다 (운영자가 보고 정한다)
 */
export default function AdminReports() {
  return (
    <RequireOperator>
      <ReportList />
    </RequireOperator>
  );
}

function ReportList() {
  const [done, setDone] = useState(null);
  const { data, error, loading, retry } = useAsync(async () => {
    const [champs, groups] = await Promise.all([getChampionMap(), getOpenReports()]);
    return { champs, groups };
  }, []);
  const finished = (message) => {
    setDone(message);
    retry();
  };
  return (
    <article>
      <nav className="crumbs"><Link to="/admin" className="op-link">← 운영자 페이지</Link></nav>
      <div className="page-head">
        <h1 className="doc-title page-title"><FlagIcon size={26} className="title-icon op" /> 신고</h1>
        {data && <span className="count-badge">{data.groups.length}개</span>}
      </div>
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
    </article>
  );
}

function ReportGroup({ group: g, champs, onDone }) {
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
      {matchup && <p className="hint">{matchup}{counter.status !== 'approved' && ' (숨긴 카운터)'}</p>}
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
            <small> ({r.reporter?.nickname ?? '탈퇴한 유저'}, {fmtDateTime(r.created_at)})</small>
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

/** 신고 기각: 메모는 선택 (작성자·신고자에게 가지 않고 기록만) */
function DismissForm({ id, onSubmit, onCancel }) {
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const submit = async (e) => {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await onSubmit(note.trim());
    } catch (err) {
      setError(err.message);
      setBusy(false);
    }
  };
  return (
    <form className="note-form" onSubmit={submit} onKeyDown={(e) => e.key === 'Escape' && !busy && onCancel()}>
      <label htmlFor={id}>기각 메모 (선택, 기록용 — 아무에게도 알림이 가지 않습니다)</label>
      <textarea id={id} rows={2} maxLength={500} value={note} onChange={(e) => setNote(e.target.value)} />
      <div className="note-form-actions">
        <button type="submit" className="btn btn-small btn-op" disabled={busy}>{busy ? '처리하는 중…' : '기각 확정'}</button>
        <button type="button" className="btn btn-small" onClick={onCancel} disabled={busy}>취소</button>
      </div>
      {error && <p className="form-error" role="alert">{error}</p>}
    </form>
  );
}
