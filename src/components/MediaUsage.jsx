import { getMediaUsage } from '../api/media';
import { useAsync } from '../lib/useAsync';
import { ErrorBox, Loading } from './Status';

const MB = 1024 * 1024;
const fmtMb = (bytes) => `${Number((bytes / MB).toFixed(1))}MB`;

/**
 * 운영자 페이지의 "사진 저장 공간" 칸 (023): 자유게시판 사진이 쓰는 공간 (무료 1GB 기준).
 * 경고 선(800MB)을 넘으면 보라 경고, 막는 선(900MB)을 넘으면 새 첨부가 막혔다고 알려 준다.
 */
export default function MediaUsage() {
  const { data: u, error, loading, retry } = useAsync(() => getMediaUsage(), []);
  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;

  const usedMb = u.bytes / MB;
  const blocked = usedMb >= u.block_mb;
  const warned = !blocked && usedMb >= u.warn_mb;
  const pct = Math.min(100, (usedMb / u.total_mb) * 100);
  return (
    <div className="media-usage">
      <p>
        <strong>{fmtMb(u.bytes)}</strong> / {u.total_mb}MB 사용 · 사진 {u.files}개 (GIF {u.gifs}개, {fmtMb(u.gif_bytes)})
      </p>
      <div
        className={blocked ? 'usage-bar blocked' : warned ? 'usage-bar warned' : 'usage-bar'}
        role="meter" aria-label="사진 저장 공간" aria-valuemin={0} aria-valuemax={u.total_mb} aria-valuenow={Math.round(usedMb)}
      >
        <span style={{ width: `${pct}%` }} />
      </div>
      {blocked && <p className="notice warn" role="alert">{u.block_mb}MB를 넘어 새 사진 첨부가 막혔습니다. 숨긴 글을 지우거나 숫자(media_block_mb)를 조정해 주세요.</p>}
      {warned && <p className="notice op-notice" role="status">{u.warn_mb}MB를 넘었습니다. {u.block_mb}MB가 되면 새 사진 첨부가 막힙니다.</p>}
      <ul className="usage-facts">
        <li>숨긴 글·댓글의 사진: {fmtMb(u.hidden_bytes)}</li>
        <li>최근 7일 올림: {u.recent_files}개, {fmtMb(u.recent_bytes)}</li>
        <li>지울 차례 (매일 정리): {u.trash}개 · 글에 안 붙은 사진: {u.orphans}개</li>
      </ul>
      {u.top?.length > 0 && (
        <>
          <h3 className="sub-title">많이 올린 사람</h3>
          <ol className="usage-top">
            {u.top.map((t) => (
              <li key={t.nickname ?? '?'}>
                {t.nickname ?? '(닉네임 없음)'} — {t.files}개, {fmtMb(t.bytes)}
              </li>
            ))}
          </ol>
        </>
      )}
    </div>
  );
}
