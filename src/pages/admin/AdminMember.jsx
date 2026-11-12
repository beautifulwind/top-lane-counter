import { useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { getDeletedWritings, getMemberDetail } from '../../api/moderation';
import { getChampionMap } from '../../api/ddragon';
import RequireOperator from '../../components/RequireOperator';
import { ErrorBox, Loading } from '../../components/Status';
import { ACTION_LABEL, KIND_LABEL, ModeratorToggle, ROLE_LABEL } from '../../components/ModeratorAdmin';
import UserName from '../../components/UserName';
import { GrantInfluencer, RenameMember, RevokeInfluencer } from '../../components/InfluencerAdmin';
import { UsersIcon } from '../../components/Icons';
import { fmtDateTime } from '../../lib/format';
import { matchupTitle } from '../../lib/josa';
import { titleName } from '../../lib/titles';
import { INFLUENCER_KINDS } from '../../lib/nickname';
import { useAsync } from '../../lib/useAsync';

const PROVIDER_LABEL = { google: '구글', kakao: '카카오' };
const WITHDRAWN = '탈퇴한 이용자';

/** 가입 방식 한 마디 (연결한 로그인 방식 이름만 — 이메일·로그인 ID는 화면에 오지 않는다) */
const joinedWith = (m) => {
  if (m.is_guest) return '비회원 (구글·카카오 연결 전)';
  const names = (m.providers ?? []).map((p) => PROVIDER_LABEL[p] ?? p);
  return names.length ? names.join(', ') : '알 수 없음';
};

/** 운영자: 회원 정보 (042, /admin/members/:id) — 회원 관리에서 회원을 누르면 열린다 */
export default function AdminMember() {
  return (
    <RequireOperator>
      <MemberPage />
    </RequireOperator>
  );
}

function MemberPage() {
  const { id } = useParams();
  const [done, setDone] = useState(null);
  const { data, error, loading, retry } = useAsync(async () => {
    const [champs, detail] = await Promise.all([getChampionMap(), getMemberDetail(id)]);
    return { champs, ...detail };
  }, [id]);
  const withdrawn = error?.code === 'P0002';
  return (
    <article>
      <nav className="crumbs"><Link to="/admin/members" className="op-link">← 회원 관리</Link></nav>
      <h1 className="doc-title page-title">
        <UsersIcon size={26} className="title-icon op" /> {data ? data.info.nickname : withdrawn ? WITHDRAWN : '회원 정보'}
      </h1>
      {loading && <Loading />}
      {withdrawn && <p className="empty">{WITHDRAWN}입니다. 탈퇴했거나 없는 회원이라 정보를 볼 수 없습니다.</p>}
      {error && !withdrawn && <ErrorBox error={error} onRetry={retry} />}
      {data && (
        <>
          {done && <p className="notice" role="status">{done}</p>}
          <Info info={data.info} onDone={(text) => { setDone(text); retry(); }} />
          <Writings data={data} />
          <EditedBuilds data={data} />
          <ModerationHistory rows={data.moderation} />
          <DeletedWritings userId={id} />
        </>
      )}
    </article>
  );
}

function Info({ info, onDone }) {
  const titles = (info.titles ?? []).map(titleName);
  return (
    <section className="section" aria-label="기본 정보">
      <h2 className="section-title">기본 정보</h2>
      <p><UserName profile={info} /></p>
      <ul className="log-list" aria-label={`${info.nickname} 회원 정보`}>
        <li>가입일 {fmtDateTime(info.created_at)}</li>
        <li>가입 방식 {joinedWith(info)}</li>
        <li>등급 {ROLE_LABEL[info.role] ?? info.role}{info.influencer && ` · 장인 (${INFLUENCER_KINDS[info.influencer] ?? info.influencer})`}{info.nickname_state === 'pending' && ' · 장인 인증 대기'}{info.nickname_state === 'yielding' && ' · 닉네임 변경 예정'}</li>
        <li>레벨 {info.level} · 경험치 {info.xp}{info.main_title ? ` · 대표 칭호 ${titleName(info.main_title)}` : ''}</li>
        <li>얻은 칭호 {titles.length ? titles.join(', ') : '없음'}</li>
        <li>활동 글 {info.posts}개 · 댓글 {info.comments}개 · 상대법 {info.matchups}개 · 빌드 {info.builds}개</li>
        {(info.deleted_posts > 0 || info.deleted_comments > 0) && (
          <li>지운 글 {info.deleted_posts}개 · 지운 댓글 {info.deleted_comments}개 <small className="hint">(1년 보관, 운영자만)</small></li>
        )}
      </ul>
      <ModeratorToggle member={info} onDone={onDone} />
      {info.role !== 'admin' && (
        <div className="row-actions" aria-label="장인·닉네임">
          {/* 049: 장인이 아니면 [장인으로 직접 지정], 지정되면 같은 자리에 [인증 해제] */}
          <GrantInfluencer member={info} onDone={onDone} />
          <RevokeInfluencer member={info} onDone={onDone} />
          <RenameMember member={info} onDone={onDone} />
        </div>
      )}
    </section>
  );
}

function Writings({ data }) {
  const name = (cid) => data.champs[cid]?.name ?? cid;
  const docTitle = (c) => matchupTitle(name(c.counter_champion), name(c.target_champion));
  return (
    <section className="section" aria-label="쓴 글·댓글">
      <h2 className="section-title">쓴 글 (최근 {data.posts.length}개)</h2>
      {data.posts.length === 0 ? <p className="empty">쓴 글이 없습니다.</p> : (
        <ul className="log-list" aria-label="쓴 글">
          {data.posts.map((p) => (
            <li key={p.id}>
              <Link to={`/board/${p.id}`} className="op-link">{p.title}</Link>
              {p.status === 'hidden' && <> <span className="hint">(숨김)</span></>}
              {' · '}{fmtDateTime(p.created_at)} · 댓글 {p.comment_count}개
              {p.excerpt && <><br /><small className="hint">{p.excerpt}</small></>}
            </li>
          ))}
        </ul>
      )}
      <h2 className="section-title">쓴 댓글 (최근 {data.comments.length}개)</h2>
      {data.comments.length === 0 ? <p className="empty">쓴 댓글이 없습니다.</p> : (
        <ul className="log-list" aria-label="쓴 댓글">
          {data.comments.map((c) => (
            <li key={`${c.kind}-${c.id}`}>
              {c.kind === 'post'
                ? <Link to={`/board/${c.post_id}`} className="op-link">글 「{c.post_title}」</Link>
                : <Link to={`/champion/${c.target_champion}/counter/${c.counter_champion}#comments`} className="op-link">상대법 「{docTitle(c)}」</Link>}
              {c.status === 'hidden' && <> <span className="hint">(숨김)</span></>}
              {' · '}{fmtDateTime(c.created_at)}
              <br /><small className="hint">{c.excerpt}</small>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

function EditedBuilds({ data }) {
  const name = (cid) => data.champs[cid]?.name ?? cid;
  return (
    <section className="section" aria-label="고친 빌드">
      <h2 className="section-title">고친 빌드 (최근 {data.edited_builds.length}개)</h2>
      {data.edited_builds.length === 0 ? <p className="empty">고친 빌드가 없습니다.</p> : (
        <ul className="log-list" aria-label="고친 빌드 목록">
          {data.edited_builds.map((b) => (
            <li key={b.build_id}>
              <Link to={`/champion/${b.target_champion}/counter/${b.counter_champion}?build=${b.build_id}`} className="op-link">
                {matchupTitle(name(b.counter_champion), name(b.target_champion))} · 빌드 {b.seq}{b.name ? ` (${b.name})` : ''}
              </Link>
              {b.status === 'hidden' && <> <span className="hint">(숨김)</span></>}
              {' · '}{b.edits}번 고침 · 마지막 {fmtDateTime(b.last_at)}
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

function ModerationHistory({ rows }) {
  return (
    <section className="section" aria-label="처리 이력">
      <h2 className="section-title">처리 이력 (최근 {rows.length}개)</h2>
      {rows.length === 0 ? <p className="empty">처리 이력이 없습니다.</p> : (
        <ul className="log-list" aria-label="처리 이력 목록">
          {rows.map((r) => (
            <li key={r.id}>
              {fmtDateTime(r.created_at)} · {ACTION_LABEL[r.action] ?? r.action} · {r.target_kind === 'user' ? '회원' : `${KIND_LABEL[r.target_kind] ?? r.target_kind} #${r.target_id}`}
              {' · '}{r.actor_nickname ?? '(알 수 없음)'} ({ROLE_LABEL[r.actor_role] ?? r.actor_role})
              {r.note && <> · {r.note}</>}
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

/** 지운 글·댓글 (운영자만, 1년 보관): 열었을 때만 불러온다. 감독관에게는 이 화면 자체가 없고 DB도 막는다 */
function DeletedWritings({ userId }) {
  const [open, setOpen] = useState(false);
  return (
    <details className="build-summary" onToggle={(e) => setOpen(e.currentTarget.open)}>
      <summary>지운 글·댓글 (운영자만 볼 수 있음)</summary>
      {open && <DeletedList userId={userId} />}
    </details>
  );
}

const WHO = { author: '작성자가 지움', staff: '운영진이 지움' };

function DeletedList({ userId }) {
  const { data, error, loading, retry } = useAsync(async () => {
    const [champs, writings] = await Promise.all([getChampionMap(), getDeletedWritings(userId)]);
    return { champs, ...writings };
  }, [userId]);
  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  const rows = [
    ...data.posts.map((p) => ({ key: `p${p.id}`, kind: '글', title: p.title, body: p.body, row: p })),
    ...data.comments.map((c) => ({ key: `c${c.id}`, kind: '댓글', title: `글 「${c.post_title || '지운 글'}」`, body: c.body, row: c })),
    ...data.doc_comments.map((d) => ({ key: `d${d.id}`, kind: '문서 댓글', title: `상대법 「${matchupTitle(data.champs[d.counter_champion]?.name ?? d.counter_champion, data.champs[d.target_champion]?.name ?? d.target_champion)}」`, body: d.body, row: d })),
  ].sort((a, b) => String(b.row.deleted_at).localeCompare(String(a.row.deleted_at)));
  if (rows.length === 0) return <p className="empty">지운 글·댓글이 없습니다.</p>;
  return (
    <>
      <p className="hint">지운 날부터 {data.keep_days}일 보관한 뒤 완전히 삭제됩니다. 다른 회원에게는 보이지 않습니다.</p>
      <ul className="log-list" aria-label="지운 글·댓글">
        {rows.map((r) => (
          <li key={r.key}>
            [{r.kind}] {r.title} · {fmtDateTime(r.row.deleted_at)} · {WHO[r.row.delete_kind] ?? r.row.delete_kind}
            {r.row.deleted_by?.nickname && r.row.delete_kind === 'staff' && <> ({r.row.deleted_by.nickname})</>}
            {r.row.delete_note && <> · 사유: {r.row.delete_note}</>}
            {r.body && <><br /><small className="hint">{r.body}</small></>}
          </li>
        ))}
      </ul>
    </>
  );
}
