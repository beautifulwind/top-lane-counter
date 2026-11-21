import { useState } from 'react';
import { Link } from 'react-router-dom';
import {
  PHOTO_REPORT_REASONS, dismissProfilePhotoReports, getProfilePhotoReports, removeProfilePhoto,
} from '../api/profilePhoto';
import { useAsync } from '../lib/useAsync';
import { fmtDateTime } from '../lib/format';
import { WITHDRAWN_USER, displayNickname } from '../lib/nickname';
import { ErrorBox, Loading } from './Status';
import UserName from './UserName';
import NoteForm from './NoteForm';
import ProfilePhoto from './ProfilePhoto';
import { DismissForm } from './DismissForm';

/**
 * 운영자: 프로필 사진 신고 탭 (/admin/reports?tab=photos, 062 SPEC 6-71). 같은 사진의 신고는 한 줄로 묶는다(오래된 신고 먼저).
 * [사진 삭제] = 사유 필수, 장인에게 profile_photo_removed 알림(알림함 + 휴대폰), 그 사진의 신고는 "처리됨"
 * [신고 기각] = 메모 선택, 사진은 그대로 / [프로필 보기]
 * 장인이 사진을 바꾸거나 지우면 그 사진의 신고는 저절로 닫혀 목록에서 빠진다. 운영자만(감독관 불가)
 */
export default function ProfilePhotoReportList() {
  const [done, setDone] = useState(null);
  const { data, error, loading, retry } = useAsync(() => getProfilePhotoReports(1, 50), []);
  const finished = (message) => {
    setDone(message);
    retry();
  };
  const photos = data?.photos ?? [];
  const total = Number(data?.total) || 0;
  return (
    <section aria-label="프로필 사진 신고">
      {data && <p><span className="count-badge">{total}개</span></p>}
      {done && <p className="notice" role="status">{done}</p>}
      <p className="hint">장인 프로필 사진의 신고입니다. 같은 사진의 신고는 한 줄로 묶었습니다. 삭제하면 장인에게 사유와 함께 알림이 갑니다. 기각하면 사진은 그대로 두고 신고만 닫습니다.</p>
      {loading && <Loading />}
      {error && <ErrorBox error={error} onRetry={retry} />}
      {data && photos.length === 0 && <p className="empty">처리할 프로필 사진 신고가 없습니다.</p>}
      {photos.length > 0 && (
        <ul className="proposal-list" aria-label="프로필 사진 신고 목록">
          {photos.map((p) => <PhotoReportRow key={p.photo_path} item={p} onDone={finished} />)}
        </ul>
      )}
      {total > photos.length && <p className="hint">오래된 신고 {photos.length}개만 보여 줍니다. 처리하면 다음 신고가 나옵니다.</p>}
    </section>
  );
}

function PhotoReportRow({ item, onDone }) {
  const [mode, setMode] = useState(null); // 'remove' | 'dismiss'
  const reports = item.reports ?? [];
  const owner = item.owner;
  return (
    <li className="proposal-row report-row" aria-label={`프로필 사진 신고 ${reports.length}건`}>
      <div className="proposal-main">
        <span className="proposal-type">프로필 사진</span> <span className="report-count">신고 {reports.length}건</span>
      </div>
      <ProfilePhoto
        path={item.current ? item.photo_path : null} alt={`${owner?.nickname ?? ''} 프로필 사진 (신고됨)`} className="inf-hero-photo"
        fallback={<p className="hint">사진을 불러오지 못했습니다.</p>}
      />
      <div className="proposal-meta">
        <span>장인: {owner ? <UserName profile={owner} /> : WITHDRAWN_USER}</span>
      </div>
      <ul className="log-list" aria-label="신고 내용">
        {reports.map((r) => (
          <li key={r.id}>
            <strong>{PHOTO_REPORT_REASONS[r.reason] ?? r.reason}</strong>
            {r.detail && <> — {r.detail}</>}
            <small> ({displayNickname(r.reporter)}, {fmtDateTime(r.created_at)})</small>
          </li>
        ))}
      </ul>
      {mode === null && (
        <div className="row-actions">
          <button type="button" className="btn btn-small btn-op" onClick={() => setMode('remove')}>사진 삭제</button>
          <button type="button" className="btn btn-small btn-op" onClick={() => setMode('dismiss')}>신고 기각</button>
          {owner?.id && <Link to={`/u/${owner.id}`} className="btn btn-small btn-op">프로필 보기</Link>}
        </div>
      )}
      {mode === 'remove' && (
        <NoteForm
          id={`remove-photo-report-${owner?.id}`}
          label="삭제 사유 (필수, 장인에게 보입니다)"
          confirmLabel="프로필 사진 삭제 확정"
          busyLabel="삭제하는 중…"
          onCancel={() => setMode(null)}
          onSubmit={async (note) => {
            await removeProfilePhoto(owner.id, note);
            onDone(`프로필 사진을 삭제했습니다. 장인에게 알림이 갔고, 신고 ${reports.length}건은 처리됨으로 닫았습니다.`);
          }}
        />
      )}
      {mode === 'dismiss' && (
        <DismissForm
          id={`dismiss-photo-${owner?.id}`}
          onCancel={() => setMode(null)}
          onSubmit={async (note) => {
            const n = await dismissProfilePhotoReports(owner.id, note);
            onDone(`프로필 사진 신고 ${n ?? reports.length}건을 기각했습니다.`);
          }}
        />
      )}
    </li>
  );
}
