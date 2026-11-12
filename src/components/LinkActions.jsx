import { useState } from 'react';
import { reportLink, removeLink } from '../api/links';
import { canModerate, canVote, isGuest, useAuth } from '../lib/auth';
import { LINK_REPORT_REASONS } from '../lib/links';
import MoreMenu from './MoreMenu';
import NoteForm from './NoteForm';
import { ReportForm } from './BoardParts';

/**
 * 장인 링크 옆 ⋮ 메뉴 (047·048, SPEC 6-34 3b).
 *   - [링크 신고]: 정식 회원(닉네임 있음, 비회원 아님), 내 링크가 아닐 때. 운영진에게 [링크 삭제]가 보이면 신고는 숨긴다(게시판과 같은 방식)
 *     로그인 전·비회원에게는 누를 수 없는 항목 + 이유를 보여 준다
 *   - [링크 삭제]: 운영자는 전부, 감독관은 일반 장인의 링크만(운영진의 링크는 DB가 거부). 사유 필수, 올린 장인에게 알림
 *     내 링크는 마이페이지 › 링크 관리에서 지운다
 * ownerId·owner: 링크를 올린 사람 (owner.role을 모르면 감독관에게도 보이고, 운영진의 링크면 DB가 이유와 함께 거부한다)
 * onDone(message): 신고·삭제 뒤 (부모가 안내를 띄우고 다시 읽는다)
 */
export default function LinkActions({ link, ownerId, owner, label = '링크 더보기', onDone }) {
  const auth = useAuth();
  const [mode, setMode] = useState(null); // 'report' | 'remove'
  const mine = !!auth.user?.id && auth.user.id === ownerId;
  const canRemove = !mine && canModerate(auth, ownerId, owner);
  const signedOut = auth.status !== 'signedIn';
  const reportItem = mine || canRemove ? null
    : canVote(auth) ? { label: '링크 신고', onSelect: () => setMode('report') }
      : signedOut ? { label: '링크 신고', disabled: true, hint: '로그인하면 신고할 수 있습니다.' }
        : isGuest(auth) ? { label: '링크 신고', disabled: true, hint: '비회원은 신고할 수 없습니다. 마이페이지에서 구글·카카오를 연결해 주세요.' }
          : null;

  return (
    <>
      <MoreMenu
        label={label}
        items={[
          reportItem,
          canRemove && { label: '링크 삭제', op: true, danger: true, onSelect: () => setMode('remove') },
        ]}
      />
      {mode === 'report' && (
        <div className="link-action-form">
          <ReportForm
            id={`report-link-${link.id}`}
            what="링크"
            reasons={LINK_REPORT_REASONS}
            hints={null}
            note="신고 내용은 운영자만 봅니다."
            onCancel={() => setMode(null)}
            onSubmit={async (reason, detail) => {
              await reportLink(link.id, reason, detail);
              setMode(null);
              onDone('링크를 신고했습니다. 운영자가 확인하겠습니다.');
            }}
          />
        </div>
      )}
      {mode === 'remove' && (
        <div className="link-action-form">
          <NoteForm
            id={`remove-link-${link.id}`}
            label="삭제 사유 (필수, 링크를 올린 장인에게 보입니다)"
            confirmLabel="링크 삭제 확정"
            busyLabel="삭제하는 중…"
            onCancel={() => setMode(null)}
            onSubmit={async (note) => {
              await removeLink(link.id, note);
              setMode(null);
              onDone('링크를 삭제했습니다. 올린 장인에게 알림이 갔습니다.');
            }}
          />
        </div>
      )}
    </>
  );
}
