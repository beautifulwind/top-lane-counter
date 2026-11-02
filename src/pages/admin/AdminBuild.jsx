import { useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { getChampionMap, getItems, getLatestVersion, getRunes, getSummonerSpells } from '../../api/ddragon';
import { approveBuild, getBuildForReview, hideBuild, rejectBuild, restoreBuild } from '../../api/builds';
import { buildReviewFlags, patchMinor } from '../../lib/buildContent';
import { BUILD_STATUS_LABEL, fmtDateTime } from '../../lib/format';
import { useAsync } from '../../lib/useAsync';
import { ErrorBox, Loading } from '../../components/Status';
import RequireOperator from '../../components/RequireOperator';
import UserName from '../../components/UserName';
import NoteForm from '../../components/NoteForm';
import BuildCard, { BuildAuthor } from '../../components/BuildCard';
import NotFound from '../NotFound';

/** 운영자: 빌드 하나 자세히 (/admin/builds/:id) — 확인할 점, 처리 기록, 승인·거절·숨기기·다시 공개 */
export default function AdminBuild() {
  return (
    <RequireOperator>
      <Review />
    </RequireOperator>
  );
}

const LOG_LABEL = { approve: '승인', reject: '거절', hide: '숨김', restore: '다시 공개' };

function Review() {
  const { id } = useParams();
  const navigate = useNavigate();
  const [open, setOpen] = useState(null);
  const { data, error, loading, retry } = useAsync(async () => {
    const [champs, review, items, runes, spells, latest] = await Promise.all([
      getChampionMap(), getBuildForReview(Number(id)), getItems(), getRunes(), getSummonerSpells(), getLatestVersion(),
    ]);
    return { champs, review, game: { items, runes, spells, latest } };
  }, [id]);

  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  if (!data.review) return <NotFound />;
  const { build: b, approved } = data.review;
  const name = (cid) => data.champs[cid]?.name ?? cid;
  const c = b.counter;
  const title = c ? `${name(c.counter_champion)}(으)로 ${name(c.target_champion)} 잡는 법` : '(알 수 없는 매치업)';
  const flags = buildReviewFlags(b, data.game, approved);
  const who = b.author?.nickname ?? '탈퇴한 유저';
  const done = (message) => navigate('/admin', { state: { done: message } });
  const toggle = (kind) => setOpen(open === kind ? null : kind);

  const checks = [
    flags.hiddenCounter && { bad: true, text: '숨긴 카운터의 빌드예요. 승인할 수 없어요 (거절해 주세요).' },
    flags.duplicate && { bad: true, text: '똑같은 빌드가 이미 공개돼 있어요. 승인할 수 없어요 (거절해 주세요).' },
    flags.unknown && { bad: false, text: `${flags.unknown} (아이콘이 "?"로 보여요)` },
    flags.layout && { bad: false, text: flags.layout },
    flags.outdated && { bad: false, text: `지금 패치(${patchMinor(data.game.latest)})와 다른 패치(${patchMinor(b.patch)})로 등록됐어요.` },
  ].filter(Boolean);
  const cannotApprove = flags.hiddenCounter || flags.duplicate;
  const lastOne = b.status === 'approved' && !approved.some((x) => x.id !== b.id);

  return (
    <article>
      <nav className="crumbs"><Link to="/admin">운영자 페이지</Link> › 빌드 자세히</nav>
      <h1 className="doc-title">{title} — 빌드</h1>
      <div className="proposal-meta">
        <span className={`status-badge ${b.status}`}>{BUILD_STATUS_LABEL[b.status]}</span>
        <span>작성자: <BuildAuthor build={b} /></span>
        <span>보낸 날 {fmtDateTime(b.created_at)}</span>
        {c?.status === 'approved' && <Link to={`/champion/${c.target_champion}/counter/${c.counter_champion}#builds`}>매치업 문서</Link>}
      </div>

      <section className="section">
        <h2 className="section-title">확인할 점</h2>
        {checks.length === 0 ? (
          <p className="hint">걸리는 점이 없어요.</p>
        ) : (
          <ul className="check-list">
            {checks.map((x) => <li key={x.text} className={x.bad ? 'block-reason' : 'hint'}>{x.text}</li>)}
          </ul>
        )}
        <BuildCard build={b} {...data.game} />
      </section>

      <section className="section">
        <h2 className="section-title">처리</h2>
        {b.status === 'pending' && (
          <div className="row-actions">
            <button type="button" className="btn btn-small" onClick={() => toggle('approve')} disabled={cannotApprove} aria-expanded={open === 'approve'}>
              승인
            </button>
            <button type="button" className="btn btn-small" onClick={() => toggle('reject')} aria-expanded={open === 'reject'}>
              거절
            </button>
          </div>
        )}
        {b.status === 'approved' && (
          <div className="row-actions">
            <button type="button" className="btn btn-small" onClick={() => toggle('hide')} aria-expanded={open === 'hide'} disabled={lastOne}>
              빌드 숨기기
            </button>
            {lastOne && <small className="hint">마지막 공개 빌드라 숨길 수 없어요. 다른 빌드를 먼저 승인하거나, 카운터를 숨겨 주세요.</small>}
          </div>
        )}
        {b.status === 'hidden' && (
          <>
            <p className="reject-reason">숨긴 사유: {b.hide_reason}</p>
            <div className="row-actions">
              <button type="button" className="btn btn-small" onClick={() => toggle('restore')} aria-expanded={open === 'restore'}>다시 공개</button>
            </div>
          </>
        )}
        {b.status === 'rejected' && <p className="reject-reason">거절 사유: {b.reject_reason}</p>}
        {b.status === 'approved' && b.approve_note && <p className="approve-note">승인 메모: {b.approve_note}</p>}

        {open === 'approve' && (
          <NoteForm
            id="approve-build"
            label="승인 메모 (필수, 작성자에게 보여요)"
            hint={checks.length > 0 ? '위의 확인할 점을 보고 승인해 주세요.' : undefined}
            confirmLabel="승인 확정"
            busyLabel="승인 중…"
            onCancel={() => setOpen(null)}
            onSubmit={async (note) => {
              await approveBuild(b.id, note);
              done(`빌드를 승인했어요: ${title} (${who})`);
            }}
          />
        )}
        {open === 'reject' && (
          <NoteForm
            id="reject-build"
            label="거절 사유 (필수, 작성자에게 보여요)"
            confirmLabel="거절 확정"
            busyLabel="거절 중…"
            onCancel={() => setOpen(null)}
            onSubmit={async (reason) => {
              await rejectBuild(b.id, reason);
              done(`빌드를 거절했어요: ${title} (${who})`);
            }}
          />
        )}
        {open === 'hide' && (
          <NoteForm
            id="hide-build"
            label="숨기는 사유 (필수, 작성자에게 보여요)"
            hint="숨기면 다른 사람에게 이 빌드가 안 보여요. 따봉 수는 그대로 남아요."
            confirmLabel="숨기기 확정"
            busyLabel="숨기는 중…"
            onCancel={() => setOpen(null)}
            onSubmit={async (reason) => {
              await hideBuild(b.id, reason);
              done(`빌드를 숨겼어요: ${title} (${who})`);
            }}
          />
        )}
        {open === 'restore' && (
          <NoteForm
            id="restore-build"
            label="다시 공개 메모 (필수, 작성자에게 보여요)"
            confirmLabel="다시 공개 확정"
            busyLabel="공개하는 중…"
            onCancel={() => setOpen(null)}
            onSubmit={async (note) => {
              await restoreBuild(b.id, note);
              done(`빌드를 다시 공개했어요: ${title} (${who})`);
            }}
          />
        )}
      </section>

      <section className="section">
        <h2 className="section-title">처리 기록 ({b.logs.length})</h2>
        {b.logs.length === 0 ? (
          <p className="empty">아직 처리 기록이 없어요.</p>
        ) : (
          <ul className="log-list">
            {b.logs.map((l) => (
              <li key={l.id}>
                {fmtDateTime(l.created_at)} · {LOG_LABEL[l.action]} · {l.actor ? <UserName profile={l.actor} /> : '—'} · {l.reason}
              </li>
            ))}
          </ul>
        )}
      </section>
    </article>
  );
}
