import { useState } from 'react';
import { Link, useLocation } from 'react-router-dom';
import { getChampionMap } from '../../api/ddragon';
import {
  approveBuild, cancelBuildRevision, getBuildGame, getHiddenBuilds, getPendingBuilds, getRevisionBuilds, rejectBuild, requestBuildRevision, restoreBuild,
} from '../../api/builds';
import { buildReviewFlags, quickBuildBlock } from '../../lib/buildContent';
import BuildCard, { BuildAuthor } from '../../components/BuildCard';
import {
  approveProposal, cancelProposalRevision, getDeletions, getHiddenCounters, getPendingProposals, getRevisionProposals, rejectProposal,
  requestProposalRevision, requestRevision, restoreCounter,
} from '../../api/proposals';
import { useAsync } from '../../lib/useAsync';
import { BUILD_STATUS_LABEL, TYPE_LABEL, fmtDateTime } from '../../lib/format';
import { ErrorBox, Loading } from '../../components/Status';
import RequireOperator from '../../components/RequireOperator';
import UserName from '../../components/UserName';
import NoteForm from '../../components/NoteForm';
import { EditedBadge, useAuthorChanged } from '../../components/AuthorChanged';
import OffmetaPicks from '../../components/OffmetaPicks';
import BoardAdmin from '../../components/BoardAdmin';
import ItemPrices from '../../components/ItemPrices';
import MediaUsage from '../../components/MediaUsage';
import { matchupTitle } from '../../lib/josa';

/**
 * 운영자 페이지: 승인 대기·재검토 기다리는 중·숨긴 카운터·빌드 승인 대기·숨긴 빌드를 목록에서 바로 처리
 * (메모 입력이 확인 단계), 자유게시판 신고·숨긴 글, 비주류 픽 목록, 삭제 기록. 승인 대기 줄은 [승인] [재검토 요청] [거절] — 고쳐서 승인은 [자세히]에서
 */
export default function AdminHome() {
  return (
    <RequireOperator>
      <PendingList />
    </RequireOperator>
  );
}

function PendingList() {
  const location = useLocation();
  const [done, setDone] = useState(location.state?.done ?? null);
  const { data, error, loading, retry } = useAsync(async () => {
    const game = await getBuildGame();
    const [champs, pending, hidden, deletions, builds, hiddenBuilds, revisionProposals, revisionBuilds] = await Promise.all([
      getChampionMap(), getPendingProposals(game), getHiddenCounters(), getDeletions(), getPendingBuilds(), getHiddenBuilds(),
      getRevisionProposals(), getRevisionBuilds(),
    ]);
    const pendingBuilds = builds.pending.map((b) => ({
      ...b, block: quickBuildBlock(buildReviewFlags(b, game, builds.approved), b, game.latest),
    }));
    const waiting = [
      ...revisionProposals.map((p) => ({ kind: 'proposal', item: p, at: p.revision_requested_at })),
      ...revisionBuilds.map((b) => ({ kind: 'build', item: b, at: b.revision_requested_at })),
    ].sort((a, b) => String(a.at).localeCompare(String(b.at)));
    return { champs, pending, hidden, deletions, pendingBuilds, hiddenBuilds, waiting, game };
  }, []);
  const name = (id) => data.champs[id]?.name ?? id;
  /** 줄에서 처리를 마치면: 안내를 띄우고 목록을 다시 불러온다 */
  const finished = (message) => {
    setDone(message);
    retry();
  };

  return (
    <article>
      <h1 className="doc-title">운영자 페이지</h1>
      {done && <p className="notice" role="status">{done}</p>}
      <p className="hint">카운터 순서 변경은 각 챔피언 문서의 [순서 변경], 문서 되돌리기는 매치업 문서의 [수정 기록]에서 해요.</p>

      <section className="section">
        <h2 className="section-title">승인 대기 {data ? `(${data.pending.length})` : ''}</h2>
        {loading && <Loading />}
        {error && <ErrorBox error={error} onRetry={retry} />}
        {data && data.pending.length === 0 && <p className="empty">대기 중인 제안이 없어요.</p>}
        {data && data.pending.length > 0 && (
          <ul className="proposal-list">
            {data.pending.map((p) => (
              <PendingRow key={p.id} proposal={p} name={name} game={data.game} onDone={finished} onReload={retry} />
            ))}
          </ul>
        )}
      </section>

      {data && (
        <section className="section">
          <h2 className="section-title">재검토 기다리는 중 ({data.waiting.length})</h2>
          {data.waiting.length === 0 ? (
            <p className="empty">재검토를 기다리는 제안·빌드가 없어요.</p>
          ) : (
            <>
              <p className="hint">제안자가 고쳐서 다시 내면 승인 대기로 돌아와요. [요청 취소]는 원래 내용 그대로 승인 대기로 되돌려요.</p>
              <ul className="proposal-list">
                {data.waiting.map((w) => (
                  <WaitingRow key={`${w.kind}-${w.item.id}`} kind={w.kind} item={w.item} name={name} game={data.game} onDone={finished} />
                ))}
              </ul>
            </>
          )}
        </section>
      )}

      {data && (
        <section className="section">
          <h2 className="section-title">숨긴 카운터 ({data.hidden.length})</h2>
          {data.hidden.length === 0 ? (
            <p className="empty">숨긴 카운터가 없어요.</p>
          ) : (
            <ul className="proposal-list">
              {data.hidden.map((c) => (
                <HiddenRow key={c.id} counter={c} name={name} onDone={finished} />
              ))}
            </ul>
          )}
        </section>
      )}

      {data && (
        <section className="section">
          <h2 className="section-title">빌드 승인 대기 ({data.pendingBuilds.length})</h2>
          {data.pendingBuilds.length === 0 ? (
            <p className="empty">대기 중인 빌드가 없어요.</p>
          ) : (
            <ul className="proposal-list">
              {data.pendingBuilds.map((b) => (
                <PendingBuildRow key={b.id} build={b} game={data.game} name={name} onDone={finished} onReload={retry} />
              ))}
            </ul>
          )}
        </section>
      )}

      {data && (
        <section className="section">
          <h2 className="section-title">숨긴 빌드 ({data.hiddenBuilds.length})</h2>
          {data.hiddenBuilds.length === 0 ? (
            <p className="empty">숨긴 빌드가 없어요.</p>
          ) : (
            <ul className="proposal-list">
              {data.hiddenBuilds.map((b) => (
                <HiddenBuildRow key={b.id} build={b} game={data.game} name={name} onDone={finished} />
              ))}
            </ul>
          )}
        </section>
      )}

      {data && (
        <section className="section">
          <h2 className="section-title">아이템 가격표</h2>
          <ItemPrices game={data.game} />
        </section>
      )}

      <section className="section">
        <h2 className="section-title">자유게시판·댓글</h2>
        <BoardAdmin />
      </section>

      <section className="section">
        <h2 className="section-title">사진 저장 공간</h2>
        <MediaUsage />
      </section>

      <section className="section">
        <h2 className="section-title">비주류 픽</h2>
        <OffmetaPicks />
      </section>

      {data && (
        <section className="section">
          <h2 className="section-title">삭제 기록 ({data.deletions.length})</h2>
          {data.deletions.length === 0 ? (
            <p className="empty">삭제한 카운터가 없어요.</p>
          ) : (
            <ul className="proposal-list">
              {data.deletions.map((d) => (
                <li key={d.id} className="proposal-row">
                  <div className="proposal-main">{matchupTitle(name(d.counter_champion), name(d.target_champion))}</div>
                  <div className="proposal-meta">
                    <span>{fmtDateTime(d.deleted_at)}</span>
                    <span>삭제: {d.deleter ? <UserName profile={d.deleter} /> : '—'}</span>
                    <span>원래 제안자: {d.proposer ? <UserName profile={d.proposer} /> : '없음(초기 데이터)'}</span>
                  </div>
                  <p className="reject-reason">사유: {d.reason}</p>
                  <small className="hint">
                    지운 것: 제안 {d.proposals_count} · 수정 기록 {d.revisions_count} · 빌드 {d.builds_count} · 빌드 추천 {d.votes_count} · 댓글 {d.comments_count ?? 0}
                  </small>
                </li>
              ))}
            </ul>
          )}
        </section>
      )}
    </article>
  );
}

const ACTION_LABEL = {
  hide: '숨김', restore: '다시 공개', revision_request: '재검토 요청', resubmit: '다시 보냄', reject: '다시 낸 제안 거절',
};

/** 숨긴 카운터의 원래 제안 상태 → 운영자에게 보여 줄 문구 */
function originState(origin) {
  if (!origin) return { text: '제안 없이 생긴 카운터 (재검토 요청 불가)', canRequest: false, waiting: false };
  if (origin.status === 'revision_requested') return { text: '재검토 요청 중 (제안자 수정 대기)', canRequest: false, waiting: false };
  if (origin.status === 'pending') return { text: '다시 보냄 (승인 대기 목록에 있음)', canRequest: false, waiting: true };
  if (origin.status === 'rejected') return { text: '다시 낸 제안을 거절함 (재검토 다시 요청 가능)', canRequest: true, waiting: false };
  return { text: null, canRequest: origin.status === 'revoked', waiting: false };
}

/**
 * 승인 대기 한 줄: [승인] [재검토 요청] [거절]은 그 자리에 메모 입력창, 내용은 [자세히].
 * 줄의 [승인]은 그대로 승인 — 고쳐서 승인하려면 [내용 고치기]로 [자세히]의 편집기를 연다.
 */
function PendingRow({ proposal: p, name, game, onDone, onReload }) {
  const [open, setOpen] = useState(null); // 'approve' | 'revision' | 'reject' | null
  const { guard, notice } = useAuthorChanged(onReload);
  const title = `${matchupTitle(name(p.counter_champion), name(p.target_champion))}`;
  const label = p.resubmitted ? '재검토 후 다시 낸 제안' : TYPE_LABEL[p.type];
  const toggle = (kind) => setOpen(open === kind ? null : kind);

  return (
    <li className="proposal-row" aria-label={`[${label}] ${title}`}>
      <div className="proposal-main">
        <span className="proposal-type">{label}</span> {title}
      </div>
      <div className="proposal-meta">
        {p.proposer ? <UserName profile={p.proposer} /> : <span>(탈퇴한 유저)</span>}
        <span>{fmtDateTime(p.created_at)}</span>
        <EditedBadge row={p} />
      </div>
      {notice}
      {p.block && <p className="block-reason">{p.block} 내용을 [자세히]에서 확인해 주세요.</p>}
      {p.type === 'new_counter' && p.build && (
        <details className="build-summary">
          <summary>{p.resubmitted ? '고친 빌드 보기' : '함께 공개될 첫 빌드 보기'}</summary>
          <BuildCard build={{ ...p.build, author: p.proposer }} {...game} />
        </details>
      )}
      <div className="row-actions">
        <button type="button" className="btn btn-small btn-op" onClick={() => toggle('approve')} disabled={!!p.block} aria-expanded={open === 'approve'}>
          승인
        </button>
        <button type="button" className="btn btn-small btn-op" onClick={() => toggle('revision')} aria-expanded={open === 'revision'}>
          재검토 요청
        </button>
        <button type="button" className="btn btn-small btn-op" onClick={() => toggle('reject')} aria-expanded={open === 'reject'}>
          거절
        </button>
        <Link to={`/admin/proposals/${p.id}`} className="btn btn-small btn-op">자세히</Link>
      </div>
      {open === 'approve' && (
        <NoteForm
          id={`approve-note-${p.id}`}
          label="승인 메모 (필수, 제안자에게 보여요)"
          hint={p.resubmitted ? '승인하면 고친 내용으로 다시 공개돼요 (목록 맨 뒤).' : '제안 그대로 승인해요.'}
          confirmLabel="승인 확정"
          busyLabel="승인 중…"
          onCancel={() => setOpen(null)}
          onSubmit={guard(async (note) => {
            await approveProposal(p, note);
            onDone(`${p.resubmitted ? '승인하고 다시 공개' : '승인'}했어요: [${label}] ${title}`);
          })}
        >
          <Link to={`/admin/proposals/${p.id}?approve=1`} className="edit-link op-link">내용 고치기 (고쳐서 승인)</Link>
        </NoteForm>
      )}
      {open === 'revision' && (
        <NoteForm
          id={`revision-p-${p.id}`}
          label="재검토 요청 메모 (필수, 제안자에게 보여요)"
          hint="제안자가 [마이페이지]에서 고쳐서 다시 내면 승인 대기로 돌아와요."
          confirmLabel="재검토 요청 확정"
          busyLabel="보내는 중…"
          onCancel={() => setOpen(null)}
          onSubmit={guard(async (note) => {
            await requestProposalRevision(p, note);
            onDone(`재검토를 요청했어요: [${label}] ${title}`);
          })}
        />
      )}
      {open === 'reject' && (
        <NoteForm
          id={`reject-note-${p.id}`}
          label="거절 사유 (필수, 제안자에게 보여요)"
          confirmLabel="거절 확정"
          busyLabel="거절 중…"
          onCancel={() => setOpen(null)}
          onSubmit={guard(async (reason) => {
            await rejectProposal(p, reason);
            onDone(`거절했어요: [${label}] ${title}`);
          })}
        />
      )}
    </li>
  );
}

/** 숨긴 카운터 한 줄: [재검토 요청] [다시 공개]는 그 자리에 메모 입력창 */
function HiddenRow({ counter: c, name, onDone }) {
  const [open, setOpen] = useState(null); // 'revision' | 'restore' | null
  const title = `${matchupTitle(name(c.counter_champion), name(c.target_champion))}`;
  const lastHide = c.logs.find((l) => l.action === 'hide');
  const state = originState(c.origin);
  const path = `${c.target_champion}/${c.counter_champion}`;
  const toggle = (kind) => setOpen(open === kind ? null : kind);

  return (
    <li className="proposal-row" aria-label={title}>
      <div className="proposal-main">{title}</div>
      {lastHide && (
        <div className="proposal-meta">
          <span>숨긴 날 {fmtDateTime(lastHide.created_at)}</span>
          <span>사유: {lastHide.reason}</span>
        </div>
      )}
      {c.origin?.proposer && (
        <div className="proposal-meta">
          <span>제안자: <UserName profile={c.origin.proposer} /></span>
        </div>
      )}
      {state.text && (
        <p className="hidden-state">
          {state.waiting ? <Link to={`/admin/proposals/${c.origin.id}`}>{state.text}</Link> : state.text}
        </p>
      )}

      <div className="row-actions">
        <button
          type="button"
          className="btn btn-small btn-op"
          onClick={() => toggle('revision')}
          disabled={!state.canRequest}
          aria-expanded={open === 'revision'}
        >
          재검토 요청
        </button>
        <button type="button" className="btn btn-small btn-op" onClick={() => toggle('restore')} disabled={state.waiting} aria-expanded={open === 'restore'}>
          다시 공개
        </button>
        <Link to={`/admin/preview/${path}`} className="btn btn-small btn-op">미리보기</Link>
        {state.waiting ? (
          <button type="button" className="btn btn-small" disabled title="다시 낸 제안부터 승인하거나 거절해 주세요">완전 삭제</button>
        ) : (
          <Link to={`/admin/delete/${path}`} className="btn btn-small btn-danger">완전 삭제</Link>
        )}
      </div>
      {state.waiting && <p className="hint">다시 낸 제안이 승인 대기 중이라 다시 공개·삭제는 잠겨 있어요. 그 제안부터 처리해 주세요.</p>}

      {open === 'revision' && (
        <NoteForm
          id={`revision-note-${c.id}`}
          label="재검토 요청 메모 (필수, 제안자에게 보여요)"
          confirmLabel="재검토 요청 확정"
          busyLabel="보내는 중…"
          onCancel={() => setOpen(null)}
          onSubmit={async (note) => {
            await requestRevision(c.id, note);
            onDone(`재검토를 요청했어요: ${title}`);
          }}
        />
      )}
      {open === 'restore' && (
        <NoteForm
          id={`restore-note-${c.id}`}
          label="다시 공개 메모 (필수)"
          hint={`카운터 목록 맨 뒤로 들어가요.${c.origin?.status === 'revision_requested' ? ' 보낸 재검토 요청은 취소돼요.' : ''}`}
          confirmLabel="다시 공개 확정"
          busyLabel="공개하는 중…"
          onCancel={() => setOpen(null)}
          onSubmit={async (note) => {
            await restoreCounter(c.id, note);
            onDone(`다시 공개했어요: ${title}`);
          }}
        />
      )}

      <details>
        <summary>숨김·공개 기록 {c.logs.length}개</summary>
        <ul className="log-list">
          {c.logs.map((l) => (
            <li key={l.id}>
              {fmtDateTime(l.created_at)} · {ACTION_LABEL[l.action]} · {l.actor ? <UserName profile={l.actor} /> : '—'}
              {l.reason && <> · {l.reason}</>}
            </li>
          ))}
        </ul>
      </details>
    </li>
  );
}

/** 빌드의 매치업 제목 (숨긴 카운터도 운영자는 읽는다) */
function buildTitle(build, name) {
  const c = build.counter;
  return c ? `${matchupTitle(name(c.counter_champion), name(c.target_champion))}` : '(알 수 없는 매치업)';
}

/** 빌드 승인 대기 한 줄: [승인] [재검토 요청] [거절]은 그 자리에 메모 입력창. 위험하면 [승인]을 잠그고 [자세히]로 */
function PendingBuildRow({ build: b, game, name, onDone, onReload }) {
  const [open, setOpen] = useState(null); // 'approve' | 'revision' | 'reject' | null
  const { guard, notice } = useAuthorChanged(onReload, '작성자');
  const title = buildTitle(b, name);
  const toggle = (kind) => setOpen(open === kind ? null : kind);
  const who = b.author?.nickname ?? '탈퇴한 유저';

  return (
    <li className="proposal-row" aria-label={`[빌드] ${title}`}>
      <div className="proposal-main">
        <span className="proposal-type">빌드</span> {title}
      </div>
      <div className="proposal-meta">
        <BuildAuthor build={b} />
        <span>{fmtDateTime(b.created_at)}</span>
        <EditedBadge row={b} who="작성자" />
      </div>
      {notice}
      {b.block && <p className="block-reason">{b.block} 내용을 [자세히]에서 확인해 주세요.</p>}
      <details className="build-summary">
        <summary>빌드 보기</summary>
        <BuildCard build={b} {...game} />
      </details>
      <div className="row-actions">
        <button type="button" className="btn btn-small btn-op" onClick={() => toggle('approve')} disabled={!!b.block} aria-expanded={open === 'approve'}>
          승인
        </button>
        <button type="button" className="btn btn-small btn-op" onClick={() => toggle('revision')} aria-expanded={open === 'revision'} disabled={b.counter?.status !== 'approved'}>
          재검토 요청
        </button>
        <button type="button" className="btn btn-small btn-op" onClick={() => toggle('reject')} aria-expanded={open === 'reject'}>
          거절
        </button>
        <Link to={`/admin/builds/${b.id}`} className="btn btn-small btn-op">자세히</Link>
      </div>
      {open === 'approve' && (
        <NoteForm
          id={`approve-build-${b.id}`}
          label="승인 메모 (필수, 작성자에게 보여요)"
          hint="빌드 그대로 승인해요."
          confirmLabel="승인 확정"
          busyLabel="승인 중…"
          onCancel={() => setOpen(null)}
          onSubmit={guard(async (note) => {
            await approveBuild(b, note);
            onDone(`빌드를 승인했어요: ${title} (${who})`);
          })}
        >
          <Link to={`/admin/builds/${b.id}?approve=1`} className="edit-link op-link">내용 고치기 (고쳐서 승인)</Link>
        </NoteForm>
      )}
      {open === 'revision' && (
        <NoteForm
          id={`revision-build-${b.id}`}
          label="재검토 요청 메모 (필수, 작성자에게 보여요)"
          hint="작성자가 [마이페이지]에서 고쳐서 다시 내면 승인 대기로 돌아와요."
          confirmLabel="재검토 요청 확정"
          busyLabel="보내는 중…"
          onCancel={() => setOpen(null)}
          onSubmit={guard(async (note) => {
            await requestBuildRevision(b, note);
            onDone(`빌드 재검토를 요청했어요: ${title} (${who})`);
          })}
        />
      )}
      {open === 'reject' && (
        <NoteForm
          id={`reject-build-${b.id}`}
          label="거절 사유 (필수, 작성자에게 보여요)"
          confirmLabel="거절 확정"
          busyLabel="거절 중…"
          onCancel={() => setOpen(null)}
          onSubmit={guard(async (reason) => {
            await rejectBuild(b, reason);
            onDone(`빌드를 거절했어요: ${title} (${who})`);
          })}
        />
      )}
    </li>
  );
}

/** 숨긴 빌드 한 줄: [다시 공개]는 그 자리에 메모 입력창 */
function HiddenBuildRow({ build: b, game, name, onDone }) {
  const [open, setOpen] = useState(false);
  const title = buildTitle(b, name);
  const counterHidden = b.counter?.status !== 'approved';
  const who = b.author?.nickname ?? '탈퇴한 유저';

  return (
    <li className="proposal-row" aria-label={`[숨긴 빌드] ${title}`}>
      <div className="proposal-main">
        <span className="proposal-type">빌드</span> {title}
      </div>
      <div className="proposal-meta">
        <BuildAuthor build={b} />
        {b.hidden_at && <span>숨긴 날 {fmtDateTime(b.hidden_at)}</span>}
        <span aria-label={`추천 ${b.up} · 비추천 ${b.down}`}>👍 {b.up} · 👎 {b.down}</span>
      </div>
      <p className="reject-reason">사유: {b.hide_reason}</p>
      {counterHidden && <p className="hint">카운터가 숨겨져 있어서, 다시 공개해도 카운터를 공개하기 전까지는 안 보여요.</p>}
      <details className="build-summary">
        <summary>빌드 보기</summary>
        <BuildCard build={b} {...game} />
      </details>
      <div className="row-actions">
        <button type="button" className="btn btn-small btn-op" onClick={() => setOpen((v) => !v)} aria-expanded={open}>
          다시 공개
        </button>
        <Link to={`/admin/builds/${b.id}`} className="btn btn-small btn-op">자세히</Link>
      </div>
      {open && (
        <NoteForm
          id={`restore-build-${b.id}`}
          label="다시 공개 메모 (필수, 작성자에게 보여요)"
          confirmLabel="다시 공개 확정"
          busyLabel="공개하는 중…"
          onCancel={() => setOpen(false)}
          onSubmit={async (note) => {
            await restoreBuild(b.id, note);
            onDone(`빌드를 다시 공개했어요: ${title} (${who})`);
          }}
        />
      )}
    </li>
  );
}

/** 재검토 기다리는 중 한 줄 (제안·빌드): [요청 취소] [거절]은 그 자리에 메모 입력창 */
function WaitingRow({ kind, item, name, game, onDone }) {
  const [open, setOpen] = useState(null); // 'cancel' | 'reject' | null
  const isBuild = kind === 'build';
  const title = isBuild ? buildTitle(item, name) : `${matchupTitle(name(item.counter_champion), name(item.target_champion))}`;
  const label = isBuild ? '빌드' : TYPE_LABEL[item.type];
  const who = isBuild ? (item.author?.nickname ?? '탈퇴한 유저') : (item.proposer?.nickname ?? '탈퇴한 유저');
  const detail = isBuild ? `/admin/builds/${item.id}` : `/admin/proposals/${item.id}`;
  const toggle = (k) => setOpen(open === k ? null : k);
  const what = `[${label}] ${title} (${who})`;

  return (
    <li className="proposal-row revision_requested" aria-label={`[재검토 중 ${label}] ${title}`}>
      <div className="proposal-main">
        <span className="proposal-type">{label}</span> {title}
      </div>
      <div className="proposal-meta">
        {isBuild ? <BuildAuthor build={item} /> : item.proposer ? <UserName profile={item.proposer} /> : <span>(탈퇴한 유저)</span>}
        <span className="status-badge revision_requested">{BUILD_STATUS_LABEL.revision_requested}</span>
        <span>요청한 날 {fmtDateTime(item.revision_requested_at)}</span>
      </div>
      <p className="hidden-state">보낸 메모: {item.revision_note}</p>
      {isBuild && (
        <details className="build-summary">
          <summary>빌드 보기</summary>
          <BuildCard build={item} {...game} />
        </details>
      )}
      <div className="row-actions">
        <button type="button" className="btn btn-small btn-op" onClick={() => toggle('cancel')} aria-expanded={open === 'cancel'}>요청 취소</button>
        <button type="button" className="btn btn-small btn-op" onClick={() => toggle('reject')} aria-expanded={open === 'reject'}>거절</button>
        <Link to={detail} className="btn btn-small btn-op">자세히</Link>
      </div>
      {open === 'cancel' && (
        <NoteForm
          id={`cancel-${kind}-${item.id}`}
          label={`요청 취소 메모 (필수, ${isBuild ? '작성자' : '제안자'}에게 보여요)`}
          hint="원래 내용 그대로 승인 대기로 돌아가요."
          confirmLabel="요청 취소 확정"
          busyLabel="취소하는 중…"
          onCancel={() => setOpen(null)}
          onSubmit={async (note) => {
            await (isBuild ? cancelBuildRevision(item.id, note) : cancelProposalRevision(item.id, note));
            onDone(`재검토 요청을 취소했어요: ${what}`);
          }}
        />
      )}
      {open === 'reject' && (
        <NoteForm
          id={`reject-${kind}-${item.id}`}
          label={`거절 사유 (필수, ${isBuild ? '작성자' : '제안자'}에게 보여요)`}
          confirmLabel="거절 확정"
          busyLabel="거절 중…"
          onCancel={() => setOpen(null)}
          onSubmit={async (reason) => {
            await (isBuild ? rejectBuild(item, reason) : rejectProposal(item, reason));
            onDone(`거절했어요: ${what}`);
          }}
        />
      )}
    </li>
  );
}
