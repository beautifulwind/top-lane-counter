import { useState } from 'react';
import { Link } from 'react-router-dom';
import { WIKI_REPORT_REASONS, getWikiReports, handleWikiReport } from '../api/wikiReports';
import { getChampionMap } from '../api/ddragon';
import { useAsync } from '../lib/useAsync';
import { useAuth } from '../lib/auth';
import { fmtDateTime } from '../lib/format';
import { josa, matchupTitle } from '../lib/josa';
import { displayNickname } from '../lib/nickname';
import { buildLabel } from '../lib/wikiBuild';
import { ErrorBox, Loading } from './Status';
import NoteForm from './NoteForm';

const PAGE_SIZE = 20;
const RESULT = { resolved: '처리됨', dismissed: '기각' };

/**
 * 운영진: 상대법·빌드 오류 신고 목록 (043, SPEC 6-30). [관리] → 신고 → "오류 신고" 탭.
 * 처리 전(오래된 순) / 처리된 것(최근 처리 순). [처리됨]·[기각] = 메모 필수, 신고자에게 결과 알림(휴대폰 알림 없음).
 * 신고자는 운영자에게만 보인다. 감독관은 자기가 낸 신고를 처리할 수 없다 (DB도 막는다).
 */
export default function WikiReportList() {
  const [view, setView] = useState('open'); // 'open' | 'handled'
  const [page, setPage] = useState(1);
  const [done, setDone] = useState(null);
  const { data, error, loading, retry } = useAsync(async () => {
    const [champs, list] = await Promise.all([getChampionMap(), getWikiReports(view, page, PAGE_SIZE)]);
    return { champs, list };
  }, [view, page]);
  const pages = data ? Math.max(1, Math.ceil(data.list.total / PAGE_SIZE)) : 1;
  const switchView = (v) => {
    setView(v);
    setPage(1);
    setDone(null);
  };
  const finished = (message) => {
    setDone(message);
    retry();
  };

  return (
    <section aria-label="오류 신고">
      <div className="row-actions" role="group" aria-label="오류 신고 보기">
        <button type="button" className={`btn btn-small${view === 'open' ? ' btn-op' : ''}`} aria-pressed={view === 'open'} onClick={() => switchView('open')}>처리 전</button>
        <button type="button" className={`btn btn-small${view === 'handled' ? ' btn-op' : ''}`} aria-pressed={view === 'handled'} onClick={() => switchView('handled')}>처리된 것</button>
        {data && <span className="count-badge">{data.list.total}건</span>}
      </div>
      {done && <p className="notice" role="status">{done}</p>}
      <p className="hint">
        상대법·빌드 내용이 틀렸다는 신고입니다. 내용을 고친 뒤 [처리됨], 고칠 것이 없으면 [기각]을 누릅니다. 메모는 기록에 남고, 신고자에게는 결과만 알림으로 갑니다.
      </p>
      {loading && <Loading />}
      {error && <ErrorBox error={error} onRetry={retry} />}
      {data && data.list.reports.length === 0 && (
        <p className="empty">{view === 'open' ? '처리할 오류 신고가 없습니다.' : '처리한 오류 신고가 없습니다.'}</p>
      )}
      {data && data.list.reports.length > 0 && (
        <ul className="proposal-list" aria-label="오류 신고 목록">
          {data.list.reports.map((r) => <WikiReportRow key={r.id} report={r} champs={data.champs} onDone={finished} />)}
        </ul>
      )}
      {pages > 1 && (
        <nav className="row-actions" aria-label="쪽 이동">
          <button type="button" className="btn btn-small" disabled={page <= 1} onClick={() => setPage(page - 1)}>이전</button>
          <span className="hint">{page} / {pages}쪽</span>
          <button type="button" className="btn btn-small" disabled={page >= pages} onClick={() => setPage(page + 1)}>다음</button>
        </nav>
      )}
    </section>
  );
}

const personName = (p) => (p?.withdrawn ? '탈퇴한 이용자' : displayNickname(p, '탈퇴한 이용자'));

function WikiReportRow({ report: r, champs, onDone }) {
  const { isOperator, isModerator } = useAuth();
  const [mode, setMode] = useState(null); // 'resolved' | 'dismissed'
  const [same, setSame] = useState(false);
  const name = (id) => champs[id]?.name ?? id;
  const isBuild = r.build_id != null;
  const title = matchupTitle(name(r.counter_champion), name(r.target_champion));
  const build = isBuild ? buildLabel({ name: r.build_name, seq: r.build_seq }) : null;
  const counterHidden = r.counter_status !== 'approved';
  const query = isBuild ? `?build=${r.build_id}` : '';
  const goTo = !counterHidden
    ? `/champion/${r.target_champion}/counter/${r.counter_champion}${query}`
    : isOperator ? `/admin/preview/${r.target_champion}/${r.counter_champion}` : null;
  const open = r.status === 'open';
  const ownBlocked = isModerator && !isOperator && r.mine;
  const others = Math.max(0, (r.same_open ?? 1) - 1);

  const submit = async (note) => {
    const n = await handleWikiReport(r.id, mode, note, same);
    const word = josa(RESULT[mode], '으로/로');
    onDone(n > 1 ? `오류 신고 ${n}건을 ${word} 닫았습니다.` : `오류 신고를 ${word} 닫았습니다.`);
  };

  return (
    <li className="proposal-row report-row" aria-label={`${isBuild ? '빌드' : '상대법'} 오류 신고`}>
      <div className="proposal-main">
        <span className="proposal-type">{isBuild ? '빌드' : '상대법'}</span>{' '}
        <strong>{WIKI_REPORT_REASONS[r.reason] ?? r.reason}</strong>
        {r.mine && <>{' '}<span className="op-badge">내가 낸 신고</span></>}
        {!open && <>{' '}<span className="op-badge">{RESULT[r.status] ?? r.status}</span></>}
      </div>
      <p className="hint">
        {title}{build && <> · {build}</>}
        {counterHidden && ' (숨긴 상대법)'}
        {isBuild && r.build_status === 'hidden' && ' (숨긴 빌드)'}
      </p>
      {r.memo && <p className="report-preview body">{r.memo}</p>}
      <div className="proposal-meta">
        <span>신고: {fmtDateTime(r.created_at)}</span>
        {r.reporter && <span>신고자: {personName(r.reporter)}{r.reporter.is_guest ? ' (비회원)' : ''}</span>}
        {open && others > 0 && <span>같은 대상의 처리 전 신고 {r.same_open}건</span>}
      </div>
      {!open && (
        <p className="hint">
          {RESULT[r.status]} · {personName(r.handler)} · {fmtDateTime(r.handled_at)}
          {r.handled_note && <> — {r.handled_note}</>}
        </p>
      )}
      {mode === null && (
        <div className="row-actions">
          {open && !ownBlocked && (
            <>
              <button type="button" className="btn btn-small btn-op" onClick={() => setMode('resolved')}>처리됨</button>
              <button type="button" className="btn btn-small btn-op" onClick={() => setMode('dismissed')}>기각</button>
            </>
          )}
          {open && ownBlocked && <span className="hint">내가 낸 신고는 다른 운영진이 처리합니다.</span>}
          {goTo && <Link to={goTo} className="btn btn-small btn-op">보러 가기</Link>}
        </div>
      )}
      {mode !== null && (
        <NoteForm
          id={`wiki-report-${r.id}`}
          label={mode === 'resolved' ? '처리 메모 (필수, 기록용 — 무엇을 고쳤는지)' : '기각 메모 (필수, 기록용 — 왜 고칠 것이 없는지)'}
          confirmLabel={mode === 'resolved' ? '처리됨 확정' : '기각 확정'}
          onCancel={() => { setMode(null); setSame(false); }}
          onSubmit={submit}
        >
          {others > 0 && (
            <label className="check-row">
              <input type="checkbox" checked={same} onChange={(e) => setSame(e.target.checked)} />
              <span>같은 대상의 처리 전 신고 {r.same_open}건 함께 처리</span>
            </label>
          )}
        </NoteForm>
      )}
    </li>
  );
}
