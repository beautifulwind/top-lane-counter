import { useState } from 'react';
import { Link, useLocation } from 'react-router-dom';
import { followInfluencer, unfollowInfluencer } from '../api/follow';
import { isGuest, useAuth } from '../lib/auth';

/** 게스트가 팔로우할 때 한 줄 안내 (팔로우는 된다 — DB가 게스트도 허용) */
export const GUEST_FOLLOW_TEXT = '게스트는 기록이 사라질 수 있습니다.';

/**
 * 장인 팔로우 버튼 (050, SPEC 6-36). 누르면 바로 팔로우 → "팔로우중", 한 번 더 누르면 취소.
 * - plus: 빌드 작성자 닉네임 옆 작은 [+] (팔로우 중이면 "팔로우중"). 아니면 장인 페이지의 [팔로우]
 * - 로그인 전: 누르면 로그인 안내 한 줄 / 게스트: 팔로우하고 "게스트는 기록이 사라질 수 있습니다." 한 줄
 * - 실패: DB가 준 이유를 그대로(호출이 너무 잦음 등), 아니면 쉬운 말
 * 자기 자신·장인이 아닌 사람에게는 부모가 버튼을 그리지 않는다. following·onChange는 부모가 들고 있다(목록에서 한꺼번에 불러온 값).
 */
export default function FollowButton({ id, nickname, following = false, onChange, plus = false }) {
  const auth = useAuth();
  const location = useLocation();
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState(null); // { kind: 'login' | 'guest' | 'error', text }

  const press = async () => {
    if (busy) return;
    if (auth.status !== 'signedIn') {
      setMsg({ kind: 'login' });
      return;
    }
    setBusy(true);
    setMsg(null);
    try {
      const r = following ? await unfollowInfluencer(id) : await followInfluencer(id);
      onChange?.(r);
      if (!following && isGuest(auth)) setMsg({ kind: 'guest' });
    } catch (e) {
      setMsg({ kind: 'error', text: e.message });
    } finally {
      setBusy(false);
    }
  };

  const who = nickname ? `${nickname} ` : '';
  const label = following ? `${who}팔로우 취소` : `${who}팔로우`;
  return (
    <span className={plus ? 'follow follow-plus' : 'follow'}>
      <button
        type="button"
        className={`${plus ? 'btn btn-small follow-btn plus' : 'btn follow-btn'}${following ? ' on' : ''}`}
        aria-pressed={following}
        aria-label={label}
        title={following ? '팔로우중입니다. 누르면 취소합니다.' : '팔로우하면 새 빌드 알림을 받습니다.'}
        onClick={press}
        disabled={busy}
      >
        {following ? '팔로우중' : plus ? '+' : '팔로우'}
      </button>
      {msg?.kind === 'login' && (
        <span className="follow-msg hint" role="status">
          로그인하면 팔로우할 수 있습니다. <Link to="/login" state={{ from: `${location.pathname}${location.search}` }}>로그인</Link>
        </span>
      )}
      {msg?.kind === 'guest' && (
        <span className="follow-msg hint guest-hint" role="status">
          {GUEST_FOLLOW_TEXT} <Link to="/me#upgrade">구글·카카오 연결하기</Link>
        </span>
      )}
      {msg?.kind === 'error' && <span className="follow-msg form-error" role="alert">{msg.text}</span>}
    </span>
  );
}
