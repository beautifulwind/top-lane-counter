import { useState } from 'react';
import { Link } from 'react-router-dom';
import { getHiddenBoard, getOpenReports, restoreComment, restoreDocComment, restorePost } from '../api/board';
import { getChampionMap } from '../api/ddragon';
import { canRestore, useAuth } from '../lib/auth';
import { useAsync } from '../lib/useAsync';
import { fmtDateTime } from '../lib/format';
import { ErrorBox, Loading } from './Status';
import UserName from './UserName';
import NoteForm from './NoteForm';
import { matchupTitle } from '../lib/josa';

/** 운영자 페이지의 "자유게시판·댓글" 칸: 처리할 신고 수 → /admin/reports, 숨긴 글·댓글·문서 댓글 + [다시 공개] */
export default function BoardAdmin() {
  const auth = useAuth();
  const [done, setDone] = useState(null);
  const { data, error, loading, retry } = useAsync(async () => {
    const [reports, hidden, champs] = await Promise.all([getOpenReports(auth.isModerator), getHiddenBoard(), getChampionMap()]);
    return { reports, hidden, champs };
  }, []);
  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  const finished = (message) => {
    setDone(message);
    retry();
  };
  const rows = [
    ...data.hidden.posts.map((p) => ({ kind: 'post', row: p })),
    ...data.hidden.comments.map((c) => ({ kind: 'comment', row: c })),
    ...data.hidden.docComments.map((c) => ({ kind: 'doc_comment', row: c })),
  ].sort((a, b) => String(b.row.hidden_at).localeCompare(String(a.row.hidden_at)));

  return (
    <>
      {done && <p className="notice" role="status">{done}</p>}
      <p>
        <Link to="/admin/reports" className="btn btn-op">
          처리할 신고 {data.reports.length}건
        </Link>
      </p>
      <div className="sub-head">
        <h3>숨긴 글·댓글</h3>
        <span className="count-badge">{rows.length}개</span>
      </div>
      {rows.length === 0 ? (
        <p className="empty">숨긴 글·댓글이 없습니다.</p>
      ) : (
        <ul className="proposal-list" aria-label="숨긴 글·댓글">
          {rows.map(({ kind, row }) => (
            <HiddenBoardRow key={`${kind}-${row.id}`} kind={kind} row={row} champs={data.champs} onDone={finished} />
          ))}
        </ul>
      )}
    </>
  );
}

const KIND_LABEL = { post: '글', comment: '댓글', doc_comment: '문서 댓글' };

function HiddenBoardRow({ kind, row, champs, onDone }) {
  const auth = useAuth();
  const [open, setOpen] = useState(false);
  const isPost = kind === 'post';
  const text = isPost ? row.title : row.body;
  const k = row.counter;
  const name = (id) => champs[id]?.name ?? id;
  const goTo = kind === 'doc_comment'
    ? k && (k.status === 'approved'
      ? `/champion/${k.target_champion}/counter/${k.counter_champion}#comments`
      : `/admin/preview/${k.target_champion}/${k.counter_champion}`)
    : `/board/${isPost ? row.id : row.post_id}`;
  return (
    <li className="proposal-row" aria-label={`[숨긴 ${KIND_LABEL[kind]}] ${text}`}>
      <div className="proposal-main">
        <span className="proposal-type">{KIND_LABEL[kind]}</span> <span className="report-preview">{text}</span>
      </div>
      {k && <p className="hint">{matchupTitle(name(k.counter_champion), name(k.target_champion))}</p>}
      <div className="proposal-meta">
        <span>작성자: {row.author ? <UserName profile={row.author} /> : '(탈퇴한 유저)'}</span>
        <span>숨긴 날 {fmtDateTime(row.hidden_at)}</span>
      </div>
      <p className="reject-reason">메모: {row.hidden_note}</p>
      <div className="row-actions">
        {canRestore(auth, row) && (
          <button type="button" className="btn btn-small btn-op" onClick={() => setOpen((v) => !v)} aria-expanded={open}>다시 공개</button>
        )}
        {goTo && <Link to={goTo} className="btn btn-small btn-op">보러 가기</Link>}
      </div>
      {open && (
        <NoteForm
          id={`restore-${kind}-${row.id}`}
          label="다시 공개 메모 (필수, 작성자에게 보입니다)"
          confirmLabel="다시 공개 확정"
          busyLabel="공개하는 중…"
          onCancel={() => setOpen(false)}
          onSubmit={async (note) => {
            if (isPost) await restorePost(row.id, note);
            else if (kind === 'doc_comment') await restoreDocComment(row.id, note);
            else await restoreComment(row.id, note);
            onDone(`${isPost ? '글' : '댓글'}을 다시 공개했습니다.`);
          }}
        />
      )}
    </li>
  );
}
