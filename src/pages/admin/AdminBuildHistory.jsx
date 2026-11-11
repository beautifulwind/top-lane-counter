import { useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { BUILD_CONFLICT, getBuildRevisions, revertBuild } from '../../api/builds';
import { getChampionMap, getItems, getRunes, getSummonerSpells } from '../../api/ddragon';
import { useAsync } from '../../lib/useAsync';
import { fmtDateTime } from '../../lib/format';
import { buildDiff } from '../../lib/diff';
import { matchupTitle } from '../../lib/josa';
import { buildLabel } from '../../lib/wikiBuild';
import { ErrorBox, Loading } from '../../components/Status';
import RequireOperator from '../../components/RequireOperator';
import DiffView from '../../components/DiffView';
import UserName from '../../components/UserName';
import NoteForm from '../../components/NoteForm';
import { OriginBadge } from '../../components/ContributorsDialog';

/**
 * 운영자: 빌드 수정 기록 자세히 (/admin/builds/:id/history, 043 · SPEC 6-30).
 * 모든 등록·수정의 고친 사람·시각·전후 비교, [이 시점으로 되돌리기](메모 필수, 버전 확인 TL412).
 * 고친 사람 닉네임은 회원 정보(/admin/members/:id)로 이어진다. 되돌려도 작성자·수정자에게 알림은 가지 않는다.
 */
export default function AdminBuildHistory() {
  return (
    <RequireOperator>
      <History />
    </RequireOperator>
  );
}

const STATUS = { approved: '공개', hidden: '숨김', pending: '승인 대기', rejected: '거절', revision_requested: '재검토 요청' };

/** 회원 정보로 가는 닉네임 (탈퇴했으면 글자만) */
function Person({ person, none = '탈퇴한 이용자' }) {
  if (!person) return <span>{none}</span>;
  return <Link to={`/admin/members/${person.id}`} className="op-link"><UserName profile={person} /></Link>;
}

function History() {
  const { id } = useParams();
  const buildId = Number(id);
  const [older, setOlder] = useState([]); // [더 보기]로 붙인 기록
  const [more, setMore] = useState(null); // null = 첫 쪽의 has_more를 따른다
  const [loadingMore, setLoadingMore] = useState(false);
  const [moreError, setMoreError] = useState(null);
  const [open, setOpen] = useState(null); // 비교를 펼친 기록 id
  const [reverting, setReverting] = useState(null); // 되돌리기 메모 칸을 연 기록 id
  const [message, setMessage] = useState(null);
  const [conflict, setConflict] = useState(false);
  const { data, error, loading, retry } = useAsync(async () => {
    const [champs, page, items, runes, spells] = await Promise.all([
      getChampionMap(), getBuildRevisions(buildId), getItems(), getRunes(), getSummonerSpells(),
    ]);
    return { champs, page, game: { items, runes, spells } };
  }, [buildId]);

  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  const { build: b, keep_days: keepDays } = data.page;
  const revisions = [...data.page.revisions, ...older];
  const hasMore = more ?? data.page.has_more;
  const name = (cid) => data.champs[cid]?.name ?? cid;
  const title = matchupTitle(name(b.counter_champion), name(b.target_champion));
  const label = buildLabel(b);
  const matchupPath = `/champion/${b.target_champion}/counter/${b.counter_champion}`;
  const versionOf = Object.fromEntries(revisions.map((r) => [r.id, r.version]));
  const sameAsNow = (r) => JSON.stringify(r.after) === JSON.stringify(b.current);
  const canRevert = b.status === 'approved' || b.status === 'hidden';

  const kindText = (r) => {
    if (r.kind === 'create') return '처음 등록';
    if (r.kind === 'migrate') return '예전 문서에서 옮김';
    if (r.kind === 'revert') return `되돌림 (${versionOf[r.revert_of] ? `v${versionOf[r.revert_of]}` : '예전 기록'} 시점으로)`;
    return '수정';
  };

  const reload = () => {
    setOlder([]);
    setMore(null);
    setOpen(null);
    setReverting(null);
    setConflict(false);
    retry();
  };
  const loadMore = async () => {
    setLoadingMore(true);
    setMoreError(null);
    try {
      const next = await getBuildRevisions(buildId, revisions.at(-1)?.id ?? null);
      setOlder((prev) => [...prev, ...next.revisions]);
      setMore(next.has_more);
    } catch (e) {
      setMoreError(e.message);
    }
    setLoadingMore(false);
  };
  const revert = async (r, note) => {
    try {
      const res = await revertBuild(b.id, r.id, b.version, note);
      const removed = res?.removed_contributors ?? 0;
      setMessage(`v${r.version} 시점으로 되돌렸습니다. 지금 버전 v${res?.version ?? b.version + 1}${removed > 0 ? ` · 기여자에서 ${removed}명을 뺐습니다` : ''}.`);
      reload();
    } catch (e) {
      if (e.code === BUILD_CONFLICT) setConflict(true);
      throw e;
    }
  };

  return (
    <article>
      <nav className="crumbs">
        <Link to="/admin" className="op-link">운영자 페이지</Link> ›{' '}
        {b.counter_status === 'approved'
          ? <Link to={`${matchupPath}?build=${b.id}`}>{title} · {label}</Link>
          : <>{title} · {label}</>}
        {' '}› 수정 기록
      </nav>
      <h1 className="doc-title page-title">빌드 수정 기록</h1>
      <p className="doc-sub">
        {title} · {label} · {STATUS[b.status] ?? b.status} · 지금 v{b.version}
        {b.counter_status !== 'approved' && ' · 숨긴 상대법'}
      </p>
      <p className="proposal-meta">
        <span>처음 만든 분: <Person person={b.author} />{b.author && <>{' '}<OriginBadge /></>}</span>
        {b.is_first && <span>이 상대법의 첫 빌드</span>}
      </p>
      <p className="hint">
        고치기 전과 후 내용은 고친 날부터 {keepDays}일이 지나면 자동으로 지워집니다. 되돌려도 작성자·고친 분에게 알림은 가지 않으며,
        되돌린 범위의 수정만 한 분은 기여자 목록에서 빠집니다.
      </p>
      {message && <p className="notice" role="status">{message}</p>}
      {conflict && (
        <p className="notice" role="alert">
          그사이 누군가 이 빌드를 고쳤습니다.{' '}
          <button type="button" className="btn btn-small" onClick={reload}>최신 기록 다시 불러오기</button>
        </p>
      )}
      {revisions.length === 0 && <p className="empty">남아 있는 수정 기록이 없습니다.</p>}

      <ol className="revision-list" aria-label="빌드 수정 기록">
        {revisions.map((r) => {
          const isNow = r.version === b.version && sameAsNow(r);
          const fields = open === r.id ? buildDiff(r.before, r.after, data.game) : null;
          return (
            <li key={r.id} className={isNow ? 'revision current' : 'revision'} aria-label={`v${r.version} ${kindText(r)}`}>
              <div className="proposal-main">
                <strong>v{r.version}</strong> {kindText(r)}
                {isNow && <>{' '}<span className="badge">지금 내용</span></>}
              </div>
              <div className="proposal-meta">
                <span>
                  {r.kind === 'revert' ? '되돌린 분' : '고친 분'}:{' '}
                  <Person person={r.editor} none={r.kind === 'migrate' ? '— (예전 문서)' : '탈퇴한 이용자'} />
                </span>
                <span>{fmtDateTime(r.created_at)}</span>
              </div>
              <div className="row-actions">
                <button
                  type="button" className="btn btn-small" aria-expanded={open === r.id}
                  onClick={() => setOpen(open === r.id ? null : r.id)}
                >
                  {open === r.id ? '비교 접기' : '전후 비교'}
                </button>
                {canRevert && !sameAsNow(r) && reverting !== r.id && (
                  <button type="button" className="btn btn-small btn-op" onClick={() => { setReverting(r.id); setMessage(null); }}>
                    이 시점으로 되돌리기
                  </button>
                )}
              </div>
              {fields && <DiffView fields={fields} before={r.before} />}
              {reverting === r.id && (
                <div className="revert-box">
                  <p className="hint">되돌리면 지금 내용이 아래처럼 바뀝니다 (− 지금 / + 되돌린 뒤).</p>
                  <DiffView fields={buildDiff(b.current, r.after, data.game)} before={b.current} />
                  <NoteForm
                    id={`revert-${r.id}`}
                    label="되돌리는 사유 (필수, 기록용 — 작성자·고친 분에게 알림은 가지 않습니다)"
                    confirmLabel="되돌리기 확정"
                    busyLabel="되돌리는 중…"
                    autoFocus={false}
                    onCancel={() => setReverting(null)}
                    onSubmit={(note) => revert(r, note)}
                  />
                </div>
              )}
            </li>
          );
        })}
      </ol>
      {hasMore && (
        <div className="actions">
          <button type="button" className="btn" onClick={loadMore} disabled={loadingMore}>{loadingMore ? '불러오는 중…' : '이전 기록 더 보기'}</button>
          {moreError && <p className="form-error" role="alert">{moreError}</p>}
        </div>
      )}
    </article>
  );
}
