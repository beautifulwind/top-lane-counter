import { useEffect, useState } from 'react';
import { Link, Navigate, useLocation } from 'react-router-dom';
import { PROVIDERS, getIdentities, linkProvider } from '../api/auth';
import { getChampionMap, getItems, getLatestVersion, getRunes, getSummonerSpells } from '../api/ddragon';
import { approvedWithEdits, getMyProposals, getMyUnreadNotifications, markNotificationsRead } from '../api/proposals';
import { getMyBuilds } from '../api/builds';
import { getMyRewards } from '../api/rewards';
import { BUILD_STATUS_LABEL, STATUS_LABEL, TYPE_LABEL, fmtDateTime } from '../lib/format';
import { useAuth } from '../lib/auth';
import { useAsync } from '../lib/useAsync';
import { ErrorBox, Loading } from '../components/Status';
import UserName from '../components/UserName';
import BuildCard from '../components/BuildCard';
import DiffView from '../components/DiffView';
import MyRewards from '../components/MyRewards';
import { matchupTitle } from '../lib/josa';

/**
 * 내 활동 (/me): 내 제안·내 빌드 목록과 상태, 로그인 연결.
 * 레벨·경험치·칭호는 6단계에서 채운다 (SPEC 3장).
 */
export default function Me() {
  const auth = useAuth();
  const sent = useLocation().state?.sent;
  if (auth.status === 'loading') return <Loading />;
  if (auth.status === 'signedOut') return <Navigate to="/login" replace state={{ from: '/me' }} />;
  if (auth.profileError) return <ErrorBox error={auth.profileError} />;
  if (!auth.profile) return <Loading />;

  return (
    <article className="me-page">
      <h1 className="doc-title" data-page-title="내 활동">
        <UserName profile={auth.profile} />
      </h1>
      {sent && (
        <p className="notice" role="status">
          {sent} 운영자가 승인하면 반영돼요.
        </p>
      )}
      <MyActivity userId={auth.user.id} operator={auth.isOperator} />
      <LinkedLogins userId={auth.user.id} />
    </article>
  );
}

function MyActivity({ userId, operator }) {
  const { data, error, loading, retry } = useAsync(async () => {
    const [champs, proposals, builds, unread, items, runes, spells, latest, rewards] = await Promise.all([
      getChampionMap(), getMyProposals(userId), getMyBuilds(userId), getMyUnreadNotifications(userId),
      getItems(), getRunes(), getSummonerSpells(), getLatestVersion(),
      operator ? null : getMyRewards(userId),
    ]);
    return { champs, proposals, builds, unread, rewards, game: { items, runes, spells, latest } };
  }, [userId, operator]);

  // 화면에 보인 알림 = 확인한 것 → 읽음 처리 (상단 빨간 점이 꺼진다).
  // "새 알림" 표시는 이번에 불러온 화면에서만 보인다. 재검토 요청 내용과 [고쳐서 다시 제출]은 제안 상태라 그대로 남는다.
  const unread = data?.unread;
  useEffect(() => {
    if (unread?.length) markNotificationsRead(unread.map((n) => n.id)).catch(() => {}); // 실패하면 다음에 다시 확인
  }, [unread]);

  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  return (
    <>
      {operator ? (
        <section className="me-section" aria-labelledby="my-level">
          <h2 id="my-level">레벨·경험치</h2>
          <p className="hint">운영자는 경험치·레벨·칭호가 없어요 (항상 Lv.0).</p>
        </section>
      ) : (
        <MyRewards rewards={data.rewards} unread={data.unread} champs={data.champs} />
      )}
      <BoardNotices unread={data.unread} champs={data.champs} />
      <MyProposals data={data} />
      <MyBuilds data={data} />
    </>
  );
}

const BOARD_KINDS = [
  'post_comment', 'post_hidden', 'post_restored', 'comment_hidden', 'comment_restored',
  'doc_comment', 'doc_comment_hidden', 'doc_comment_restored',
];

/** 댓글·게시판 알림 (새 댓글·숨김·다시 공개): 이번에 처음 보는 것만, [글 보기]·[문서 보기]로 이동 */
function BoardNotices({ unread, champs }) {
  const list = unread.filter((n) => BOARD_KINDS.includes(n.kind));
  if (list.length === 0) return null;
  const name = (id) => champs[id]?.name ?? id;
  return (
    <section className="me-section" aria-labelledby="board-notices">
      <h2 id="board-notices">댓글·게시판 알림</h2>
      <ul className="proposal-list">
        {list.map((n) => (
          <li key={n.id} className="proposal-row">
            <p className="board-notice-msg"><span className="new-badge">새 알림</span>{n.message}</p>
            <div className="proposal-meta">
              {n.counter && <span>{matchupTitle(name(n.counter.counter_champion), name(n.counter.target_champion))}</span>}
              <span>{fmtDateTime(n.created_at)}</span>
              {n.post_id && !['post_hidden'].includes(n.kind) && <Link to={`/board/${n.post_id}`}>글 보기</Link>}
              {n.counter?.status === 'approved' && (
                <Link to={`/champion/${n.counter.target_champion}/counter/${n.counter.counter_champion}#comments`}>문서 보기</Link>
              )}
            </div>
          </li>
        ))}
      </ul>
    </section>
  );
}

/** 이번에 처음 보는 "재검토 요청 취소" 알림 (메모) — 해야 할 일이 없어지므로 알림으로만 알려 준다 */
function CancelledNotice({ unread, match }) {
  const n = unread.find((x) => x.kind === 'revision_cancelled' && match(x));
  return n ? <p className="notice">운영자가 재검토 요청을 취소했어요. 보낸 내용 그대로 승인 대기 중이에요. 메모: {n.message}</p> : null;
}

/** 운영자가 고쳐서 승인했을 때: 원래 제안 → 고친 내용 비교 */
function EditedCompare({ before, after, beforeBuild, afterBuild, author, game }) {
  return (
    <details className="edited-by-operator">
      <summary>운영자가 고쳐서 승인했어요 — 원래 제안 → 고친 내용 보기</summary>
      {after && <DiffView before={before} after={after} />}
      {afterBuild && (
        <div className="build-compare">
          <div>
            <h3>원래 빌드</h3>
            <BuildCard build={{ ...beforeBuild, author }} {...game} />
          </div>
          <div>
            <h3>고친 빌드</h3>
            <BuildCard build={{ ...afterBuild, author }} {...game} />
          </div>
        </div>
      )}
    </details>
  );
}

function MyProposals({ data }) {
  const name = (id) => data.champs[id]?.name ?? id;
  const isNew = (p) => data.unread.some((n) => n.proposal_id === p.id);

  return (
    <section className="me-section" aria-labelledby="my-proposals">
      <h2 id="my-proposals">내 제안</h2>
      {data && data.proposals.length === 0 && <p className="empty">아직 보낸 제안이 없어요.</p>}
      {data && data.proposals.length > 0 && (
        <ul className="proposal-list">
          {data.proposals.map((p) => {
            const title = `${matchupTitle(name(p.counter_champion), name(p.target_champion))}`;
            const live = p.status === 'approved' || (p.type === 'doc_edit' && !['revoked', 'revision_requested'].includes(p.status));
            return (
              <li key={p.id} className={`proposal-row ${p.status}`}>
                <div className="proposal-main">
                  {isNew(p) && <span className="new-badge">새 알림</span>}
                  <span className="proposal-type">{TYPE_LABEL[p.type]}</span>{' '}
                  <Link to={`/me/proposals/${p.id}`}>{title}</Link>
                </div>
                <div className="proposal-meta">
                  <span className={`status-badge ${p.status}`}>{STATUS_LABEL[p.status]}</span>
                  <span>보낸 날 {fmtDateTime(p.created_at)}</span>
                  {p.edited_at && p.status === 'pending' && <span>고친 때 {fmtDateTime(p.edited_at)}</span>}
                  {p.reviewed_at && <span>처리 {fmtDateTime(p.reviewed_at)}</span>}
                </div>
                {p.status === 'approved' && p.approve_note && <p className="approve-note">승인 메모: {p.approve_note}</p>}
                {approvedWithEdits(p) && (
                  <EditedCompare
                    before={p.content} after={p.approved_content} beforeBuild={p.build} afterBuild={p.approved_build}
                    author={p.proposer} game={data.game}
                  />
                )}
                <CancelledNotice unread={data.unread} match={(n) => n.proposal_id === p.id} />
                {p.status === 'rejected' && <p className="reject-reason">거절 사유: {p.reject_reason}</p>}
                {p.status === 'revoked' && (
                  <p className="reject-reason">
                    승인 취소 사유: {p.revoke_reason}
                    {p.revoked_at && <> ({fmtDateTime(p.revoked_at)})</>}
                  </p>
                )}
                {p.status === 'revision_requested' && (
                  <div className="revision-note">
                    <p>
                      <strong>재검토 요청</strong>
                      {p.revision_requested_at && <small> ({fmtDateTime(p.revision_requested_at)})</small>}
                    </p>
                    <p>운영자 메모: {p.revision_note}</p>
                    <Link to={`/me/proposals/${p.id}/edit`} className="btn btn-small">고쳐서 다시 보내기</Link>
                  </div>
                )}
                {p.type === 'new_counter' && p.build && (
                  <details className="build-summary">
                    <summary>제안한 빌드 보기</summary>
                    <BuildCard build={{ ...p.build, author: p.proposer }} {...data.game} />
                  </details>
                )}
                <div className="row-actions">
                  <Link to={`/me/proposals/${p.id}`} className="btn btn-small">자세히</Link>
                  {p.status === 'pending' && <Link to={`/me/proposals/${p.id}/edit`} className="btn btn-small">고치기</Link>}
                  {live && <Link to={`/champion/${p.target_champion}/counter/${p.counter_champion}`} className="btn btn-small">문서 보기</Link>}
                </div>
              </li>
            );
          })}
        </ul>
      )}
    </section>
  );
}

/** 내 빌드: 상태·메모·따봉 수, [이 빌드로 다시 쓰기] (승인된 빌드는 고치지 않고 새 빌드로 보낸다) */
function MyBuilds({ data }) {
  const name = (id) => data.champs[id]?.name ?? id;
  const isNew = (b) => data.unread.some((n) => n.build_id === b.id);

  return (
    <section className="me-section" aria-labelledby="my-builds">
      <h2 id="my-builds">내 빌드</h2>
      {data.builds.length === 0 && <p className="empty">아직 보낸 빌드가 없어요. 매치업 문서의 [+ 빌드 등록]에서 보낼 수 있어요.</p>}
      {data.builds.length > 0 && (
        <ul className="proposal-list">
          {data.builds.map((b) => {
            const c = b.counter;
            const title = c ? `${matchupTitle(name(c.counter_champion), name(c.target_champion))}` : '(숨긴 카운터)';
            const path = c && `/champion/${c.target_champion}/counter/${c.counter_champion}`;
            const open = c?.status === 'approved';
            return (
              <li key={b.id} className={`proposal-row ${b.status}`} aria-label={`내 빌드: ${title}`}>
                <div className="proposal-main">
                  {isNew(b) && <span className="new-badge">새 알림</span>}
                  <span className="proposal-type">빌드</span>{' '}
                  <Link to={`/me/builds/${b.id}`}>{title}</Link>
                </div>
                <div className="proposal-meta">
                  <span className={`status-badge ${b.status}`}>{BUILD_STATUS_LABEL[b.status]}</span>
                  <span>보낸 날 {fmtDateTime(b.created_at)}</span>
                  {b.edited_at && b.status === 'pending' && <span>고친 때 {fmtDateTime(b.edited_at)}</span>}
                  {b.reviewed_at && <span>처리 {fmtDateTime(b.reviewed_at)}</span>}
                  {['approved', 'hidden'].includes(b.status) && <span>👍 {b.up} · 👎 {b.down}</span>}
                </div>
                {b.status === 'approved' && b.approve_note && <p className="approve-note">승인 메모: {b.approve_note}</p>}
                {b.original_build && ['approved', 'hidden'].includes(b.status) && (
                  <EditedCompare beforeBuild={b.original_build} afterBuild={b} author={b.author} game={data.game} />
                )}
                <CancelledNotice unread={data.unread} match={(n) => n.build_id === b.id} />
                {b.status === 'revision_requested' && (
                  <div className="revision-note">
                    <p>
                      <strong>재검토 요청</strong>
                      {b.revision_requested_at && <small> ({fmtDateTime(b.revision_requested_at)})</small>}
                    </p>
                    <p>운영자 메모: {b.revision_note}</p>
                    <Link to={`/me/builds/${b.id}/edit`} className="btn btn-small">고쳐서 다시 보내기</Link>
                  </div>
                )}
                {b.status === 'rejected' && <p className="reject-reason">거절 사유: {b.reject_reason}</p>}
                {b.status === 'hidden' && (
                  <p className="reject-reason">
                    숨긴 사유: {b.hide_reason}
                    {b.hidden_at && <> ({fmtDateTime(b.hidden_at)})</>}
                  </p>
                )}
                <details className="build-summary">
                  <summary>빌드 보기</summary>
                  <BuildCard build={b} {...data.game} />
                </details>
                <div className="row-actions">
                  <Link to={`/me/builds/${b.id}`} className="btn btn-small">자세히</Link>
                  {open && b.status === 'pending' && <Link to={`/me/builds/${b.id}/edit`} className="btn btn-small">고치기</Link>}
                  {open && b.status === 'approved' && <Link to={`${path}#builds`} className="btn btn-small">문서 보기</Link>}
                  {open && <Link to={`${path}/build/new?from=${b.id}`} className="btn btn-small">이 빌드로 다시 쓰기</Link>}
                </div>
              </li>
            );
          })}
        </ul>
      )}
    </section>
  );
}

function LinkedLogins({ userId }) {
  const { data: identities, error, loading, retry } = useAsync(getIdentities, [userId]);
  const [busy, setBusy] = useState(null);
  const [linkError, setLinkError] = useState(null);

  const link = async (provider) => {
    setBusy(provider);
    setLinkError(null);
    try {
      await linkProvider(provider); // 성공하면 구글/카카오 화면으로 이동한다
    } catch (e) {
      setLinkError(e.message);
      setBusy(null);
    }
  };

  return (
    <section className="me-section" aria-labelledby="linked-logins">
      <h2 id="linked-logins">로그인 연결</h2>
      <p className="lead">둘 다 연결하면 구글·카카오 어느 쪽으로 로그인해도 이 계정으로 들어와요.</p>
      {loading && <Loading />}
      {error && <ErrorBox error={error} onRetry={retry} />}
      {identities && (
        <ul className="identity-list">
          {Object.entries(PROVIDERS).map(([provider, name]) => {
            const linked = identities.find((i) => i.provider === provider);
            return (
              <li key={provider} className="identity-row">
                <span>
                  <span className="identity-name">{name}</span>
                  {linked?.email && <small>{linked.email}</small>}
                </span>
                {linked ? (
                  <span className="identity-linked">✓ 연결됨</span>
                ) : (
                  <button
                    type="button"
                    className={`btn login-btn-sm ${provider}`}
                    onClick={() => link(provider)}
                    disabled={busy !== null}
                  >
                    {busy === provider ? `${name}로 이동 중…` : `${name} 연결하기`}
                  </button>
                )}
              </li>
            );
          })}
        </ul>
      )}
      {linkError && <p className="form-error" role="alert">{linkError}</p>}
    </section>
  );
}
