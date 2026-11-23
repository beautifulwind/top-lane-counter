import { useEffect, useState } from 'react';
import { Link, useLocation } from 'react-router-dom';
import { fmtDateTime } from '../lib/format';
import { installWriteGuard, onWriteBlocked, useRestriction, useRestrictionRefresher } from '../lib/restriction';

/** [문의하기] → 분류 「이의 제기」가 골라진 문의 화면 */
export const APPEAL_PATH = '/inquiries?category=appeal';

/** 띠·안내 상자 공통 문장: 「활동이 제한된 상태입니다. ○○에 풀립니다. 사유: …」 */
export const restrictionText = (r) => `${fmtDateTime(r.ends_at)}에 풀립니다. 사유: ${r.reason}`;

/**
 * 활동 제한 띠 (068, SPEC 6-85): 제한 중이면 모든 화면 위에 「활동이 제한된 상태입니다. ○○에 풀립니다. 사유: … [문의하기]」.
 * 흐린 쓰기 버튼(data-write)을 누르면 아래쪽에 같은 이유의 안내 상자를 띄운다 (동작은 하지 않음).
 * 실제로 막는 것은 DB — 이 띠는 알려 주기만 한다.
 */
export default function RestrictionBanner({ userId }) {
  useRestrictionRefresher(userId);
  const { restriction } = useRestriction(userId);
  const [blocked, setBlocked] = useState(null);
  const { pathname } = useLocation();
  useEffect(() => {
    const uninstall = installWriteGuard(document);
    const unsubscribe = onWriteBlocked((r) => setBlocked({ ...r, at: Date.now() }));
    return () => { uninstall(); unsubscribe(); };
  }, []);
  useEffect(() => { setBlocked(null); }, [pathname]); // 화면을 옮기면 안내 상자는 닫는다
  if (!restriction) return null;
  return (
    <>
      <div className="login-error restriction-band" role="status" aria-label="활동 제한 안내">
        <p><strong>활동이 제한된 상태입니다.</strong> {restrictionText(restriction)}</p>
        <small className="restriction-band-hint">읽기·내 글 지우기·팔로우 취소·차단·알림 설정·문의는 그대로 할 수 있습니다.</small>
        <div className="login-error-actions">
          <Link to={APPEAL_PATH} className="btn">문의하기</Link>
        </div>
      </div>
      {blocked && (
        <div className="restriction-toast" role="alert" key={blocked.at}>
          <p><strong>활동이 제한된 상태입니다.</strong> {restrictionText(blocked)}</p>
          <div className="login-error-actions">
            <Link to={APPEAL_PATH} className="btn btn-small" onClick={() => setBlocked(null)}>문의하기</Link>
            <button type="button" className="btn btn-small" onClick={() => setBlocked(null)}>닫기</button>
          </div>
        </div>
      )}
    </>
  );
}
