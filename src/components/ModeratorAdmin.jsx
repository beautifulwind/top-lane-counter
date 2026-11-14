import { useState } from 'react';
import { getModerationLog, setModerator } from '../api/moderation';
import { fmtDateTime } from '../lib/format';
import { useAsync } from '../lib/useAsync';
import { ErrorBox, Loading } from './Status';
import NoteForm from './NoteForm';

// 감독관 지정·해제와 처리 기록의 부품. 화면은 회원 관리(MemberAdmin, /admin/members) 한 곳이다 (042).
// 실제 권한 검사는 DB 함수·RLS가 한다 (감독관 지정·해제·처리 기록은 운영자만).

export const ACTION_LABEL = {
  hide: '숨김', restore: '다시 공개', delete: '삭제', dismiss_reports: '신고 기각',
  approve_proposal: '제안 승인', reject_proposal: '제안 거절', request_revision: '재검토 요청', edit_proposal: '제안 내용 수정',
  answer_inquiry: '문의 답변', move_inquiry: '문의 분류 변경',
  grant_moderator: '감독관 지정', revoke_moderator: '감독관 해제',
  revert: '빌드 되돌리기', resolve_report: '오류 신고 처리', dismiss_report: '오류 신고 기각', // 043
  grant_influencer: '장인 직접 지정', // 049
  grant_title: '칭호 지급', revoke_title: '칭호 회수', // 053
};
export const KIND_LABEL = {
  post: '글', comment: '댓글', doc_comment: '문서 댓글', proposal: '제안', inquiry: '문의', build: '빌드', wiki_report: '오류 신고',
};
export const ROLE_LABEL = { admin: '운영자', moderator: '감독관', user: '일반 회원' };

/** 처리 대상 한 마디: 지정·해제는 닉네임, 나머지는 "글 #12" */
export const WITHDRAWN_USER = '탈퇴한 이용자';
export const targetText = (r) => {
  if (r.target_kind === 'user') return r.target_nickname?.trim() || WITHDRAWN_USER;
  const kind = KIND_LABEL[r.target_kind] ?? r.target_kind;
  return r.target_id == null ? `${kind} (${WITHDRAWN_USER})` : `${kind} #${r.target_id}`;
};

/** 운영진 처리 기록 (최근 순, 운영자만 읽는다) */
export function ModerationLog({ refreshKey = 0 }) {
  const { data, error, loading, retry } = useAsync(() => getModerationLog(), [refreshKey]);
  if (loading && !data) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  return (
    <details className="build-summary">
      <summary>처리 기록 (최근 {data.length}개)</summary>
      {data.length === 0 ? (
        <p className="empty">처리 기록이 없습니다.</p>
      ) : (
        <ul className="log-list" aria-label="처리 기록">
          {data.map((r) => (
            <li key={r.id}>
              {fmtDateTime(r.created_at)} · {ACTION_LABEL[r.action] ?? r.action} · {targetText(r)}
              {' · '}{r.actor_nickname ?? '(알 수 없음)'} ({ROLE_LABEL[r.actor_role] ?? r.actor_role})
              {r.note && <> · {r.note}</>}
            </li>
          ))}
        </ul>
      )}
    </details>
  );
}

/**
 * 감독관 지정·해제 버튼 + 메모 칸 (메모 필수, 그 사람에게 알림, 처리 기록에 남는다).
 * 운영자 본인·비회원은 지정할 수 없다 (DB도 막는다). onDone(안내 문장)
 */
export function ModeratorToggle({ member: m, onDone }) {
  const [open, setOpen] = useState(false);
  if (m.role === 'admin') return null;
  if (m.is_guest) return <p className="hint">비회원은 감독관으로 지정할 수 없습니다.</p>;
  const on = m.role !== 'moderator';
  const label = on ? '지정' : '해제';
  return (
    <>
      <div className="row-actions">
        <button type="button" className="btn btn-small btn-op" onClick={() => setOpen((v) => !v)} aria-expanded={open} aria-label={`${m.nickname} 감독관 ${label}`}>
          감독관 {label}
        </button>
      </div>
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
            setOpen(false);
            onDone(`${m.nickname}: 감독관 ${label}했습니다.`);
          }}
        />
      )}
    </>
  );
}
