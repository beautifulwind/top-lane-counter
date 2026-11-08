import { useState } from 'react';
import { getModerationLog, getModerators, searchMembers, setModerator } from '../api/moderation';
import { fmtDateTime } from '../lib/format';
import { useAsync } from '../lib/useAsync';
import { ErrorBox, Loading } from './Status';
import NoteForm from './NoteForm';
import UserName from './UserName';

const ACTION_LABEL = {
  hide: '숨김', restore: '다시 공개', dismiss_reports: '신고 기각',
  approve_proposal: '제안 승인', reject_proposal: '제안 거절', edit_proposal: '제안 내용 수정',
  answer_inquiry: '문의 답변', move_inquiry: '문의 분류 변경',
  grant_moderator: '감독관 지정', revoke_moderator: '감독관 해제',
};
const KIND_LABEL = { post: '글', comment: '댓글', doc_comment: '문서 댓글', proposal: '제안' };
const ROLE_LABEL = { admin: '운영자', moderator: '감독관' };

/** 처리 대상 한 마디: 지정·해제는 닉네임, 나머지는 "글 #12" */
const targetText = (r) => (r.target_kind === 'user' ? (r.target_nickname ?? '(알 수 없음)') : `${KIND_LABEL[r.target_kind] ?? r.target_kind} #${r.target_id}`);

/** 운영자: 감독관 지정·해제 + 처리 기록 (/admin). 감독관에게는 이 칸이 없고, DB도 운영자만 허용한다 */
export default function ModeratorAdmin() {
  const [message, setMessage] = useState(null);
  const { data, error, loading, retry } = useAsync(async () => {
    const [moderators, log] = await Promise.all([getModerators(), getModerationLog()]);
    return { moderators, log };
  }, []);
  const finished = (text) => {
    setMessage(text);
    retry();
  };
  if (loading && !data) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  return (
    <>
      <p className="hint">감독관은 신고 처리, 글·댓글 숨김과 다시 공개, 새 카운터 제안 승인(내용 고쳐서 승인 포함)·거절을 합니다. 화면에는 운영자와 똑같이 (운)으로 보입니다.</p>
      {message && <p className="notice" role="status">{message}</p>}
      {data.moderators.length === 0 ? (
        <p className="empty">감독관이 없습니다.</p>
      ) : (
        <ul className="proposal-list" aria-label="감독관 목록">
          {data.moderators.map((m) => <MemberRow key={m.id} member={m} onDone={finished} />)}
        </ul>
      )}
      <MemberSearch moderators={data.moderators} onDone={finished} />
      <details className="build-summary">
        <summary>처리 기록 (최근 {data.log.length}개)</summary>
        {data.log.length === 0 ? (
          <p className="empty">처리 기록이 없습니다.</p>
        ) : (
          <ul className="log-list" aria-label="처리 기록">
            {data.log.map((r) => (
              <li key={r.id}>
                {fmtDateTime(r.created_at)} · {ACTION_LABEL[r.action] ?? r.action} · {targetText(r)}
                {' · '}{r.actor_nickname ?? '(알 수 없음)'} ({ROLE_LABEL[r.actor_role] ?? r.actor_role})
                {r.note && <> · {r.note}</>}
              </li>
            ))}
          </ul>
        )}
      </details>
    </>
  );
}

function MemberSearch({ moderators, onDone }) {
  const [query, setQuery] = useState('');
  const [found, setFound] = useState(null);
  const [fail, setFail] = useState(null);
  const search = async (e) => {
    e.preventDefault();
    setFail(null);
    if (!query.trim()) return;
    try {
      setFound(await searchMembers(query));
    } catch (err) {
      setFail(err.message);
    }
  };
  const results = (found ?? []).filter((u) => !moderators.some((m) => m.id === u.id) && u.role !== 'admin' && u.nickname);
  return (
    <>
      <form className="row-actions" onSubmit={search}>
        <label htmlFor="moderator-search" className="sr-only">닉네임으로 회원 찾기</label>
        <input id="moderator-search" type="search" value={query} placeholder="닉네임으로 찾기" onChange={(e) => setQuery(e.target.value)} />
        <button type="submit" className="btn btn-small btn-op">찾기</button>
      </form>
      {fail && <p className="form-error" role="alert">{fail}</p>}
      {found && results.length === 0 && <p className="empty">지정할 수 있는 회원을 찾지 못했습니다.</p>}
      {results.length > 0 && (
        <ul className="proposal-list" aria-label="찾은 회원">
          {results.map((u) => (
            <MemberRow
              key={u.id} member={u}
              onDone={(text) => {
                setFound(null);
                setQuery('');
                onDone(text);
              }}
            />
          ))}
        </ul>
      )}
    </>
  );
}

/** 회원 한 줄: 감독관이면 [해제], 아니면 [지정] (메모 필수). 비회원은 지정할 수 없다 */
function MemberRow({ member: m, onDone }) {
  const [open, setOpen] = useState(false);
  const on = m.role !== 'moderator';
  const label = on ? '지정' : '해제';
  return (
    <li className="proposal-row" aria-label={m.nickname}>
      <div className="proposal-meta"><UserName profile={m} /></div>
      {m.is_guest ? (
        <p className="hint">비회원은 감독관으로 지정할 수 없습니다.</p>
      ) : (
        <div className="row-actions">
          <button type="button" className="btn btn-small btn-op" onClick={() => setOpen((v) => !v)} aria-expanded={open}>{label}</button>
        </div>
      )}
      {open && (
        <NoteForm
          id={`moderator-${m.id}`}
          label={`${label} 메모 (필수, 그 사람에게 보입니다)`}
          hint={on ? '지정 알림에 "처리 기록은 탈퇴 후에도 남습니다" 안내가 함께 갑니다.' : '해제하면 그 즉시 권한이 사라집니다.'}
          confirmLabel={`${label} 확정`}
          busyLabel="처리하는 중…"
          onCancel={() => setOpen(false)}
          onSubmit={async (note) => {
            await setModerator(m.id, on, note);
            onDone(`${m.nickname}: 감독관 ${label}했습니다.`);
          }}
        />
      )}
    </li>
  );
}
