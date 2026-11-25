import { useEffect, useState } from 'react';
import { checkAppUpdate, isSnoozed, snooze } from '../lib/appUpdate';
import { storeUrlFor } from '../lib/storeLinks';

/**
 * 앱 업데이트 안내 띠 (1.3 패치 1-F, SPEC 6-99). 네이티브 앱에서만, 앱이 켜질 때 한 번 확인한다. 화면을 막지 않는 위쪽 띠 — 강제 업데이트 아님.
 * [업데이트] = 그 플랫폼의 스토어 페이지, [나중에] = 24시간 숨김(더 높은 새 버전이 올라오면 다시 보임). 확인이 어떤 이유로든 실패하면 아무것도 그리지 않는다.
 */
export default function AppUpdateBanner() {
  const [info, setInfo] = useState(null);
  useEffect(() => {
    let alive = true;
    checkAppUpdate().then((r) => { if (alive && r && !isSnoozed(r.latest)) setInfo(r); }).catch(() => {});
    return () => { alive = false; };
  }, []);
  if (!info) return null;
  return (
    <div className="app-update-band" role="status">
      <span>새 버전이 나왔습니다</span>
      <span className="app-update-actions">
        <a className="btn btn-primary btn-small" href={storeUrlFor(info.platform)} target="_blank" rel="noopener noreferrer">업데이트</a>
        <button type="button" className="btn btn-small" onClick={() => { snooze(info.latest); setInfo(null); }}>나중에</button>
      </span>
    </div>
  );
}
