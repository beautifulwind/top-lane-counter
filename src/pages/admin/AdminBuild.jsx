import { useState } from 'react';
import { Link, useNavigate, useParams, useSearchParams } from 'react-router-dom';
import { getChampionMap } from '../../api/ddragon';
import {
  approveBuild, cancelBuildRevision, getBuildForReview, getBuildGame, hideBuild, rejectBuild, requestBuildRevision, restoreBuild,
} from '../../api/builds';
import { buildReviewFlags, patchMinor } from '../../lib/buildContent';
import { BUILD_STATUS_LABEL, fmtDateTime } from '../../lib/format';
import { useAsync } from '../../lib/useAsync';
import { ErrorBox, Loading } from '../../components/Status';
import RequireOperator from '../../components/RequireOperator';
import UserName from '../../components/UserName';
import NoteForm from '../../components/NoteForm';
import BuildCard, { BuildAuthor } from '../../components/BuildCard';
import ApproveEditor from '../../components/ApproveEditor';
import { EditedBadge, useAuthorChanged } from '../../components/AuthorChanged';
import NotFound from '../NotFound';
import { matchupTitle } from '../../lib/josa';

/**
 * 운영자: 빌드 하나 자세히 (/admin/builds/:id) — 확인할 점, 처리 기록,
 * [승인](고쳐서 승인 가능)·[재검토 요청]·[거절]·[요청 취소]·숨기기·다시 공개. ?approve=1이면 [승인]을 연 채로
 */
export default function AdminBuild() {
  return (
    <RequireOperator>
      <Review />
    </RequireOperator>
  );
}

const LOG_LABEL = {
  approve: '승인', reject: '거절', hide: '숨김', restore: '다시 공개',
  revision_request: '재검토 요청', revision_cancel: '재검토 요청 취소', resubmit: '다시 보냄',
};

function Review() {
  const { id } = useParams();
  const navigate = useNavigate();
  const [search] = useSearchParams();
  const [open, setOpen] = useState(search.get('approve') ? 'approve' : null);
  const { data, error, loading, retry } = useAsync(async () => {
    const [champs, review, game] = await Promise.all([
      getChampionMap(), getBuildForReview(Number(id)), getBuildGame(),
    ]);
    return { champs, review, game };
  }, [id]);
  const { guard, notice } = useAuthorChanged(retry, '작성자');

  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  if (!data.review) return <NotFound />;
  const { build: b, approved } = data.review;
  const name = (cid) => data.champs[cid]?.name ?? cid;
  const c = b.counter;
  const title = c ? `${matchupTitle(name(c.counter_champion), name(c.target_champion))}` : '(알 수 없는 매치업)';
  const flags = buildReviewFlags(b, data.game, approved);
  const who = b.author?.nickname ?? '탈퇴한 유저';
  const done = (message) => navigate('/admin', { state: { done: message } });
  const toggle = (kind) => setOpen(open === kind ? null : kind);

  const checks = [
    flags.hiddenCounter && { bad: true, text: '숨긴 카운터의 빌드입니다. 승인할 수 없습니다 (거절해 주세요).' },
    flags.duplicate && { bad: true, text: '똑같은 빌드가 이미 공개돼 있습니다. 그대로는 승인할 수 없습니다 (고쳐서 승인하거나 거절해 주세요).' },
    flags.unknown && { bad: false, text: `${flags.unknown} (아이콘이 "?"로 보입니다)` },
    flags.layout && { bad: false, text: flags.layout },
    flags.gold && b.status !== 'approved' && { bad: true, text: `${flags.gold} 그대로는 승인할 수 없습니다 (고쳐서 승인하거나 재검토를 요청해 주세요).` },
    flags.outdated && { bad: false, text: `지금 패치(${patchMinor(data.game.latest)})와 다른 패치(${patchMinor(b.patch)})로 등록됐습니다.` },
  ].filter(Boolean);
  // 똑같은 빌드가 공개 중이어도 고쳐서 승인할 수는 있다 (그대로 승인하면 DB가 거부)
  const cannotApprove = flags.hiddenCounter;
  const lastOne = b.status === 'approved' && !approved.some((x) => x.id !== b.id);

  return (
    <article>
      <nav className="crumbs"><Link to="/admin">운영자 페이지</Link> › 빌드 자세히</nav>
      <h1 className="doc-title">[빌드] {title}</h1>
      <div className="proposal-meta">
        <span className={`status-badge ${b.status}`}>{BUILD_STATUS_LABEL[b.status]}</span>
        <span>작성자: <BuildAuthor build={b} /></span>
        <span>보낸 날 {fmtDateTime(b.created_at)}</span>
        <EditedBadge row={b} who="작성자" />
        {c?.status === 'approved' && <Link to={`/champion/${c.target_champion}/counter/${c.counter_champion}#builds`}>매치업 문서</Link>}
      </div>

      <section className="section">
        <h2 className="section-title">확인할 점</h2>
        {checks.length === 0 ? (
          <p className="hint">걸리는 점이 없습니다.</p>
        ) : (
          <ul className="check-list">
            {checks.map((x) => <li key={x.text} className={x.bad ? 'block-reason' : 'hint'}>{x.text}</li>)}
          </ul>
        )}
        <BuildCard build={b} {...data.game} />
      </section>

      <section className="section">
        <h2 className="section-title">처리</h2>
        {notice}
        {b.status === 'pending' && (
          <div className="row-actions">
            <button type="button" className="btn btn-small btn-op" onClick={() => toggle('approve')} disabled={cannotApprove} aria-expanded={open === 'approve'}>
              승인
            </button>
            <button type="button" className="btn btn-small btn-op" onClick={() => toggle('revision')} aria-expanded={open === 'revision'} disabled={flags.hiddenCounter}>
              재검토 요청
            </button>
            <button type="button" className="btn btn-small btn-op" onClick={() => toggle('reject')} aria-expanded={open === 'reject'}>
              거절
            </button>
          </div>
        )}
        {b.status === 'revision_requested' && (
          <>
            <div className="revision-note" role="note">
              <p><strong>재검토 요청 중</strong> — 작성자가 고쳐서 다시 내기를 기다리고 있습니다.{b.revision_requested_at && <small> ({fmtDateTime(b.revision_requested_at)})</small>}</p>
              <p>보낸 메모: {b.revision_note}</p>
            </div>
            <div className="row-actions">
              <button type="button" className="btn btn-small btn-op" onClick={() => toggle('cancel')} aria-expanded={open === 'cancel'}>요청 취소</button>
              <button type="button" className="btn btn-small btn-op" onClick={() => toggle('reject')} aria-expanded={open === 'reject'}>거절</button>
            </div>
          </>
        )}
        {b.status === 'approved' && (
          <div className="row-actions">
            <button type="button" className="btn btn-small btn-op" onClick={() => toggle('hide')} aria-expanded={open === 'hide'} disabled={lastOne}>
              빌드 숨기기
            </button>
            {lastOne && <small className="hint">마지막 공개 빌드라 숨길 수 없습니다. 다른 빌드를 먼저 승인하거나, 카운터를 숨겨 주세요.</small>}
          </div>
        )}
        {b.status === 'hidden' && (
          <>
            <p className="reject-reason">숨긴 사유: {b.hide_reason}</p>
            <div className="row-actions">
              <button type="button" className="btn btn-small btn-op" onClick={() => toggle('restore')} aria-expanded={open === 'restore'}>다시 공개</button>
            </div>
          </>
        )}
        {b.status === 'rejected' && <p className="reject-reason">거절 사유: {b.reject_reason}</p>}
        {b.status === 'approved' && b.approve_note && <p className="approve-note">승인 메모: {b.approve_note}</p>}
        {b.original_build && ['approved', 'hidden'].includes(b.status) && (
          <div className="edited-by-operator">
            <p className="hint">운영자가 고쳐서 승인한 빌드입니다 (원래 빌드 → 고친 빌드).</p>
            <div className="build-compare">
              <div>
                <h3>원래 빌드</h3>
                <BuildCard build={{ ...b.original_build, author: b.author }} {...data.game} />
              </div>
              <div>
                <h3>고친 빌드</h3>
                <BuildCard build={b} {...data.game} />
              </div>
            </div>
          </div>
        )}

        {open === 'approve' && b.status === 'pending' && !cannotApprove && (
          <ApproveEditor
            build={b}
            game={data.game}
            author={b.author}
            noteLabel="승인 메모 (필수, 작성자에게 보입니다)"
            hint={checks.length > 0 ? '위의 확인할 점을 보고 승인해 주세요.' : undefined}
            onCancel={() => setOpen(null)}
            onSubmit={guard(async ({ note, build }) => {
              await approveBuild(b, note, build, data.game.latest);
              done(`빌드를 ${build ? '고쳐서 ' : ''}승인했습니다: ${title} (${who})`);
            })}
          />
        )}
        {open === 'revision' && (
          <NoteForm
            id="revision-build"
            label="재검토 요청 메모 (필수, 작성자에게 보입니다)"
            hint="작성자가 [마이페이지]에서 고쳐서 다시 내면 승인 대기로 돌아옵니다."
            confirmLabel="재검토 요청 확정"
            busyLabel="보내는 중…"
            onCancel={() => setOpen(null)}
            onSubmit={guard(async (note) => {
              await requestBuildRevision(b, note);
              done(`빌드 재검토를 요청했습니다: ${title} (${who})`);
            })}
          />
        )}
        {open === 'cancel' && (
          <NoteForm
            id="cancel-build"
            label="요청 취소 메모 (필수, 작성자에게 보입니다)"
            hint="원래 빌드 그대로 승인 대기로 돌아갑니다."
            confirmLabel="요청 취소 확정"
            busyLabel="취소하는 중…"
            onCancel={() => setOpen(null)}
            onSubmit={async (note) => {
              await cancelBuildRevision(b.id, note);
              done(`빌드 재검토 요청을 취소했습니다: ${title} (${who})`);
            }}
          />
        )}
        {open === 'reject' && (
          <NoteForm
            id="reject-build"
            label="거절 사유 (필수, 작성자에게 보입니다)"
            confirmLabel="거절 확정"
            busyLabel="거절 중…"
            onCancel={() => setOpen(null)}
            onSubmit={guard(async (reason) => {
              await rejectBuild(b, reason);
              done(`빌드를 거절했습니다: ${title} (${who})`);
            })}
          />
        )}
        {open === 'hide' && (
          <NoteForm
            id="hide-build"
            label="숨기는 사유 (필수, 작성자에게 보입니다)"
            hint="숨기면 다른 사람에게 이 빌드가 안 보입니다. 추천 수는 그대로 남습니다."
            confirmLabel="숨기기 확정"
            busyLabel="숨기는 중…"
            onCancel={() => setOpen(null)}
            onSubmit={async (reason) => {
              await hideBuild(b.id, reason);
              done(`빌드를 숨겼습니다: ${title} (${who})`);
            }}
          />
        )}
        {open === 'restore' && (
          <NoteForm
            id="restore-build"
            label="다시 공개 메모 (필수, 작성자에게 보입니다)"
            confirmLabel="다시 공개 확정"
            busyLabel="공개하는 중…"
            onCancel={() => setOpen(null)}
            onSubmit={async (note) => {
              await restoreBuild(b.id, note);
              done(`빌드를 다시 공개했습니다: ${title} (${who})`);
            }}
          />
        )}
      </section>

      <section className="section">
        <h2 className="section-title">처리 기록 ({b.logs.length})</h2>
        {b.logs.length === 0 ? (
          <p className="empty">아직 처리 기록이 없습니다.</p>
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
