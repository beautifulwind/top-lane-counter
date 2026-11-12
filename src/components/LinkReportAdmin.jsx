import { useState } from 'react';
import { Link } from 'react-router-dom';
import { dismissLinkReports, getLinkReports, removeLink } from '../api/links';
import { getChampionMap } from '../api/ddragon';
import { useAsync } from '../lib/useAsync';
import { fmtDateTime } from '../lib/format';
import { LINK_REPORT_REASONS } from '../lib/links';
import { displayNickname } from '../lib/nickname';
import { matchupShort } from '../lib/josa';
import { ErrorBox, Loading } from './Status';
import UserName from './UserName';
import NoteForm from './NoteForm';
import ExternalLink from './ExternalLink';
import { DismissForm } from './DismissForm';

/**
 * 운영자: 링크 신고 탭 (/admin/reports?tab=links, 047·048 SPEC 6-34 3b). 같은 링크의 신고는 한 줄로 묶는다(오래된 신고 먼저).
 * [링크 삭제] = 사유 필수, 올린 장인에게 link_removed 알림, 그 링크의 신고 줄도 함께 사라진다
 * [신고 기각] = 메모 선택, 링크는 그대로 / [프로필 보기]·[빌드 보기]
 * 목록·기각은 운영자만 (감독관은 링크 옆 ⋮에서 일반 장인 링크만 삭제할 수 있다)
 */
export default function LinkReportList() {
  const [done, setDone] = useState(null);
  const { data, error, loading, retry } = useAsync(async () => {
    const [champs, page] = await Promise.all([getChampionMap().catch(() => ({})), getLinkReports(1, 50)]);
    return { champs, page };
  }, []);
  const finished = (message) => {
    setDone(message);
    retry();
  };
  const links = data?.page?.links ?? [];
  const total = Number(data?.page?.total) || 0;
  return (
    <section aria-label="링크 신고">
      {data && <p><span className="count-badge">{total}개</span></p>}
      {done && <p className="notice" role="status">{done}</p>}
      <p className="hint">장인이 올린 외부 링크의 신고입니다. 같은 링크의 신고는 한 줄로 묶었습니다. 삭제하면 올린 장인에게 사유와 함께 알림이 갑니다. 기각하면 링크는 그대로 두고 신고만 닫습니다.</p>
      {loading && <Loading />}
      {error && <ErrorBox error={error} onRetry={retry} />}
      {data && links.length === 0 && <p className="empty">처리할 링크 신고가 없습니다.</p>}
      {links.length > 0 && (
        <ul className="proposal-list" aria-label="링크 신고 목록">
          {links.map((l) => <LinkReportRow key={l.id} link={l} champs={data.champs} onDone={finished} />)}
        </ul>
      )}
      {total > links.length && <p className="hint">오래된 신고 {links.length}개만 보여 줍니다. 처리하면 다음 신고가 나옵니다.</p>}
    </section>
  );
}

function LinkReportRow({ link: l, champs, onDone }) {
  const [mode, setMode] = useState(null); // 'remove' | 'dismiss'
  const reports = l.reports ?? [];
  const b = l.build;
  const name = (c) => champs?.[c]?.name ?? c;
  const buildPath = b && (b.status === 'approved'
    ? `/champion/${b.target_champion}/counter/${b.counter_champion}?build=${b.id}`
    : `/admin/preview/${b.target_champion}/${b.counter_champion}`);
  return (
    <li className="proposal-row report-row" aria-label={`링크 신고 ${reports.length}건`}>
      <div className="proposal-main">
        <span className="proposal-type">{b ? '빌드 링크' : '프로필 링크'}</span> <span className="report-count">신고 {reports.length}건</span>
      </div>
      <p className="report-preview"><ExternalLink link={l} /></p>
      <p className="hint"><code>{l.url}</code></p>
      {b && <p className="hint">{matchupShort(name(b.counter_champion), name(b.target_champion))} · {b.name || `빌드 ${b.seq ?? ''}`.trim()}</p>}
      <div className="proposal-meta">
        <span>올린 장인: {l.owner ? <UserName profile={l.owner} /> : '(탈퇴한 유저)'}</span>
        {l.visible === false && <span className="op-badge">지금 숨김 (허용 사이트에서 빠짐)</span>}
      </div>
      <ul className="log-list" aria-label="신고 내용">
        {reports.map((r) => (
          <li key={r.id}>
            <strong>{LINK_REPORT_REASONS[r.reason] ?? r.reason}</strong>
            {r.detail && <> — {r.detail}</>}
            <small> ({displayNickname(r.reporter)}, {fmtDateTime(r.created_at)})</small>
          </li>
        ))}
      </ul>
      {mode === null && (
        <div className="row-actions">
          <button type="button" className="btn btn-small btn-op" onClick={() => setMode('remove')}>링크 삭제</button>
          <button type="button" className="btn btn-small btn-op" onClick={() => setMode('dismiss')}>신고 기각</button>
          {l.owner?.id && <Link to={`/u/${l.owner.id}`} className="btn btn-small btn-op">프로필 보기</Link>}
          {buildPath && <Link to={buildPath} className="btn btn-small btn-op">빌드 보기</Link>}
        </div>
      )}
      {mode === 'remove' && (
        <NoteForm
          id={`remove-link-report-${l.id}`}
          label="삭제 사유 (필수, 링크를 올린 장인에게 보입니다)"
          confirmLabel="링크 삭제 확정"
          busyLabel="삭제하는 중…"
          onCancel={() => setMode(null)}
          onSubmit={async (note) => {
            await removeLink(l.id, note);
            onDone(`링크를 삭제했습니다. 올린 장인에게 알림이 갔고, 신고 ${reports.length}건도 함께 닫혔습니다.`);
          }}
        />
      )}
      {mode === 'dismiss' && (
        <DismissForm
          id={`dismiss-link-${l.id}`}
          onCancel={() => setMode(null)}
          onSubmit={async (note) => {
            const n = await dismissLinkReports(l.id, note);
            onDone(`링크 신고 ${n ?? reports.length}건을 기각했습니다.`);
          }}
        />
      )}
    </li>
  );
}
