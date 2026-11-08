import { applyUpdate, useUpdateAvailable } from '../lib/sw';

/** 새 버전이 배포되면 화면 아래에 알림 (SPEC 2장 PWA). 누르기 전에는 지금 화면이 그대로 유지된다 */
export default function UpdateBanner() {
  const available = useUpdateAvailable();
  if (!available) return null;
  return (
    <div className="update-banner" role="status">
      <span>새 버전이 있습니다.</span>
      <button type="button" className="btn btn-primary" onClick={applyUpdate}>새로고침</button>
    </div>
  );
}
