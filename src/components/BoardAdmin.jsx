import { useState } from 'react';
import { Link } from 'react-router-dom';
import { getHiddenBoard, getOpenReports, restoreComment, restorePost } from '../api/board';
import { useAsync } from '../lib/useAsync';
import { fmtDateTime } from '../lib/format';
import { ErrorBox, Loading } from './Status';
import UserName from './UserName';
import NoteForm from './NoteForm';

/** 운영자 페이지의 "자유게시판" 칸: 처리할 신고 수 → /admin/reports, 숨긴 글·댓글 + [다시 공개] */
export default function BoardAdmin() {
  const [done, setDone] = useState(null);
  const { data, error, loading, retry } = useAsync(async () => {
    const [reports, hidden] = await Promise.all([getOpenReports(), getHiddenBoard()]);
    return { reports, hidden };
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
  ].sort((a, b) => String(b.row.hidden_at).localeCompare(String(a.row.hidden_at)));

  return (
    <>
      {done && <p className="notice" role="status">{done}</p>}
      <p>
        <Link to="/admin/reports" className="btn btn-op">
          처리할 신고 {data.reports.length}건
        </Link>
      </p>
      <h3>숨긴 글·댓글 ({rows.length})</h3>
      {rows.length === 0 ? (
        <p className="empty">숨긴 글·댓글이 없어요.</p>
      ) : (
        <ul className="proposal-list" aria-label="숨긴 글·댓글">
          {rows.map(({ kind, row }) => <HiddenBoardRow key={`${kind}-${row.id}`} kind={kind} row={row} onDone={finished} />)}
        </ul>
      )}
    </>
  );
}

function HiddenBoardRow({ kind, row, onDone }) {
  const [open, setOpen] = useState(false);
  const isPost = kind === 'post';
  const postId = isPost ? row.id : row.post_id;
  const text = isPost ? row.title : row.body;
  return (
    <li className="proposal-row" aria-label={`[숨긴 ${isPost ? '글' : '댓글'}] ${text}`}>
      <div className="proposal-main">
        <span className="proposal-type">{isPost ? '글' : '댓글'}</span> <span className="report-preview">{text}</span>
      </div>
      <div className="proposal-meta">
        <span>작성자: {row.author ? <UserName profile={row.author} /> : '탈퇴한 유저'}</span>
        <span>숨긴 날 {fmtDateTime(row.hidden_at)}</span>
      </div>
      <p className="reject-reason">메모: {row.hidden_note}</p>
      <div className="row-actions">
        <button type="button" className="btn btn-small btn-op" onClick={() => setOpen((v) => !v)} aria-expanded={open}>다시 공개</button>
        <Link to={`/board/${postId}`} className="btn btn-small btn-op">보러 가기</Link>
      </div>
      {open && (
        <NoteForm
          id={`restore-${kind}-${row.id}`}
          label="다시 공개 메모 (필수, 작성자에게 보여요)"
          confirmLabel="다시 공개 확정"
          busyLabel="공개하는 중…"
          onCancel={() => setOpen(false)}
          onSubmit={async (note) => {
            if (isPost) await restorePost(row.id, note);
            else await restoreComment(row.id, note);
            onDone(`${isPost ? '글' : '댓글'}을 다시 공개했어요.`);
          }}
        />
      )}
    </li>
  );
}
