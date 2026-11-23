import { useState } from 'react';
import { fmtDateTime } from '../lib/format';
import { acknowledge, useWarningRefresher, useWarnings } from '../lib/warning';
import { WARNING_NOTICE_TITLE } from '../api/warnings';

/**
 * 운영자 경고 안내 상자 (069, SPEC 6-86): 아직 확인하지 않은 경고가 있으면 모든 화면 위에
 * 「운영자 경고를 받았습니다」 + 받은 시각 + 내용 + [확인했습니다]. 누르면 확인 시각이 남고(알림도 읽음) 상자가 닫힌다.
 * 여러 개면 오래된 것부터 하나씩 (「1/2」). 활동 제한 중에도 누를 수 있다(쓰기 버튼이 아님 — data-write 없음).
 */
export default function WarningBanner({ userId }) {
  useWarningRefresher(userId);
  const warnings = useWarnings(userId);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const w = warnings[0];
  if (!w) return null;
  const ack = async () => {
    if (busy) return;
    setBusy(true);
    setError(null);
    try {
      await acknowledge(userId, w.id);
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };
  return (
    <div className="login-error warning-band" role="alert" aria-label="운영자 경고">
      <p>
        <strong>{WARNING_NOTICE_TITLE}</strong>
        {warnings.length > 1 && <span className="warning-band-count"> (1/{warnings.length})</span>}
        <small className="warning-band-time"> {fmtDateTime(w.created_at)}</small>
      </p>
      <p className="warning-band-memo">{w.memo}</p>
      <div className="login-error-actions">
        <button type="button" className="btn" onClick={ack} disabled={busy}>{busy ? '저장하는 중…' : '확인했습니다'}</button>
      </div>
      {error && <p className="form-error" role="alert">{error}</p>}
    </div>
  );
}
