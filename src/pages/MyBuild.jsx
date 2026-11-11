import { useState } from 'react';
import { Link, useLocation, useParams } from 'react-router-dom';
import { getChampionMap, getItems, getLatestVersion, getRunes, getSummonerSpells } from '../api/ddragon';
import { getMyBuild } from '../api/builds';
import { BUILD_STATUS_LABEL, fmtDateTime } from '../lib/format';
import { useAuth } from '../lib/auth';
import { useAsync } from '../lib/useAsync';
import { ErrorBox, Loading } from '../components/Status';
import { RequireLogin } from '../components/RequireOperator';
import DocView from '../components/DocView';
import { APPROVAL_ENABLED } from '../lib/features';
import { matchupTitle } from '../lib/josa';
import VoteTally from '../components/VoteTally';

/**
 * 내 빌드 자세히: /me/builds/:id — 보낸 빌드를 매치업 문서의 빌드 모양으로.
 * 상태별: 승인 대기 [수정] / 재검토 요청 [고쳐서 다시 제출] / 공개 [문서 보기] / 거절 [다시 쓰기] / 숨김 없음
 */
export default function MyBuild() {
  return (
    <RequireLogin>
      <Detail />
    </RequireLogin>
  );
}

function Detail() {
  const { id } = useParams();
  const auth = useAuth();
  const sent = useLocation().state?.sent;
  const { data, error, loading, retry } = useAsync(async () => {
    const [champs, build, items, runes, spells, latest] = await Promise.all([
      getChampionMap(), getMyBuild(auth.user.id, Number(id)), getItems(), getRunes(), getSummonerSpells(), getLatestVersion(),
    ]);
    return { champs, build, game: { items, runes, spells, latest } };
  }, [auth.user.id, id]);

  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  const b = data.build;
  const crumbs = <nav className="crumbs"><Link to="/me">마이페이지</Link> › 빌드 #{id}</nav>;
  if (!b) {
    return (
      <article>
        {crumbs}
        <h1 className="doc-title">빌드 자세히</h1>
        <p className="empty">빌드를 찾지 못했습니다. 내가 보낸 빌드만 볼 수 있습니다.</p>
      </article>
    );
  }
  return <BuildView b={b} data={data} crumbs={crumbs} sent={sent} />;
}

function BuildView({ b, data, crumbs, sent }) {
  const auth = useAuth();
  const name = (cid) => data.champs[cid]?.name ?? cid;
  const c = b.counter;
  const title = c ? `${matchupTitle(name(c.counter_champion), name(c.target_champion))}` : '(숨긴 카운터)';
  const path = c && `/champion/${c.target_champion}/counter/${c.counter_champion}`;
  const open = c?.status === 'approved';
  const edited = !!b.original_build && ['approved', 'hidden'].includes(b.status);
  const [shown, setShown] = useState('sent');
  const published = shown === 'published';
  const author = b.author ?? auth.profile;
  const view = edited && !published ? { ...b.original_build, author } : { ...b, author };

  return (
    <article>
      {crumbs}
      {sent && <p className="notice" role="status">{sent}</p>}
      <h1 className="doc-title">
        [빌드] {title}
      </h1>
      <div className="proposal-meta">
        <span className={`status-badge ${b.status}`}>{BUILD_STATUS_LABEL[b.status]}</span>
        <span>보낸 날 {fmtDateTime(b.created_at)}</span>
        {b.edited_at && b.status === 'pending' && <span>고친 때 {fmtDateTime(b.edited_at)}</span>}
        {b.resubmitted_at && <span>다시 보낸 날 {fmtDateTime(b.resubmitted_at)}</span>}
        {b.reviewed_at && <span>처리 {fmtDateTime(b.reviewed_at)}</span>}
        {['approved', 'hidden'].includes(b.status) && <VoteTally up={b.up} down={b.down} />}
      </div>

      {b.status === 'pending' && APPROVAL_ENABLED && (
        <div className="status-box">
          <p>승인 대기 중입니다. 운영자가 처리하기 전까지는 직접 고칠 수 있습니다. 고쳐도 대기 순서는 그대로입니다.</p>
          {open && <div className="actions"><Link to={`/me/builds/${b.id}/edit`} className="btn">수정</Link></div>}
        </div>
      )}
      {b.status === 'revision_requested' && APPROVAL_ENABLED && (
        <div className="revision-note">
          <p>
            <strong>재검토 요청</strong>
            {b.revision_requested_at && <small> ({fmtDateTime(b.revision_requested_at)})</small>}
          </p>
          <p>운영자 메모: {b.revision_note}</p>
          <Link to={`/me/builds/${b.id}/edit`} className="btn btn-small">고쳐서 다시 보내기</Link>
        </div>
      )}
      {b.status === 'approved' && (
        <div className="status-box">
          {b.approve_note && <p className="approve-note">승인 메모: {b.approve_note}</p>}
          <p className="hint">
            {APPROVAL_ENABLED
              ? '공개된 빌드는 고칠 수 없습니다. 바꾸고 싶으면 [이 빌드로 다시 쓰기]로 새 빌드를 보내 주세요.'
              : '공개된 빌드는 상대법 화면의 [빌드 수정]에서 바로 고칠 수 있습니다. 비슷한 빌드를 따로 올리려면 [이 빌드로 다시 쓰기]를 눌러 주세요.'}
          </p>
          {open && (
            <div className="actions">
              <Link to={`${path}?build=${b.id}`} className="btn">문서 보기</Link>
              {!APPROVAL_ENABLED && <Link to={`${path}/build/${b.id}/edit`} className="btn">빌드 수정</Link>}
              <Link to={`${path}/build/new?from=${b.id}`} className="btn">이 빌드로 다시 쓰기</Link>
            </div>
          )}
        </div>
      )}
      {b.status === 'rejected' && (
        <div className="status-box">
          <p className="reject-reason">거절 사유: {b.reject_reason}</p>
          {open && (
            <>
              <p className="hint">보낸 빌드를 채운 채로 새로 쓸 수 있습니다.</p>
              <div className="actions"><Link to={`${path}/build/new?from=${b.id}`} className="btn">다시 쓰기</Link></div>
            </>
          )}
        </div>
      )}
      {b.status === 'hidden' && (
        <p className="reject-reason">
          숨긴 사유: {b.hide_reason}
          {b.hidden_at && <> ({fmtDateTime(b.hidden_at)})</>}
        </p>
      )}

      {edited && (
        <div className="view-switch" role="group" aria-label="볼 내용">
          <button type="button" className="btn btn-small" aria-pressed={!published} onClick={() => setShown('sent')}>보낸 빌드</button>
          <button type="button" className="btn btn-small" aria-pressed={published} onClick={() => setShown('published')}>
            공개된 빌드 (운영자가 고침)
          </button>
        </div>
      )}
      <DocView doc={null} builds={[view]} game={data.game} />
    </article>
  );
}
