import { useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { getDeletedWritings, getMemberDetail } from '../../api/moderation';
import { getChampionMap } from '../../api/ddragon';
import RequireOperator from '../../components/RequireOperator';
import { ErrorBox, Loading } from '../../components/Status';
import { ACTION_LABEL, ModeratorToggle, ROLE_LABEL, WITHDRAWN_USER, targetText } from '../../components/ModeratorAdmin';
import UserName from '../../components/UserName';
import { GrantInfluencer, RenameMember, RevokeInfluencer } from '../../components/InfluencerAdmin';
import { UsersIcon } from '../../components/Icons';
import { fmtDateTime } from '../../lib/format';
import { matchupTitle } from '../../lib/josa';
import { titleName, useTitleInfo } from '../../lib/titles';
import { INFLUENCER_KINDS } from '../../lib/nickname';
import { useAsync } from '../../lib/useAsync';
import NoteForm from '../../components/NoteForm';
import ProfilePhoto from '../../components/ProfilePhoto';
import { getMemberPhotoPath, removeProfilePhoto } from '../../api/profilePhoto';
import RestrictionAdmin, { RestrictionPanel, activeRestriction, restrictBlockedBy } from '../../components/RestrictionAdmin';
import WarningAdmin, { WarningPanel, unackedWarnings, warnBlockedBy } from '../../components/WarningAdmin';
import { getMemberRestrictions } from '../../api/restrictions';
import { getMemberWarnings } from '../../api/warnings';
import { MEMBER_TABS, PREVIEW_COUNT } from '../../lib/adminView';
import AdminTabs, { TabPanel, useTabParam } from '../../components/AdminTabs';
import LimitedList, { NoneLine } from '../../components/LimitedList';

const PROVIDER_LABEL = { google: '구글', kakao: '카카오' };
const PROVIDER_LABEL_EN = { google: 'Google', kakao: 'Kakao' };
const WITHDRAWN = WITHDRAWN_USER;

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

/** 이름 옆 상태 칩: 가입 방식·등급·레벨·제한 상태·경고 (제한·경고는 기록을 읽은 뒤에만, 068·069 전 DB면 생략) */
function StatusChips({ info, restrictions, warnings }) {
  const providers = (info.providers ?? []).map((p) => PROVIDER_LABEL_EN[p] ?? p);
  const join = info.is_guest ? '비회원' : providers.length ? providers.join('·') : '알 수 없음';
  const grades = [info.role === 'admin' ? '운영자' : info.role === 'moderator' ? '감독관' : null, info.influencer ? '장인' : null].filter(Boolean);
  const active = activeRestriction(restrictions.data);
  const unacked = unackedWarnings(warnings.data);
  return (
    <ul className="chip-row" aria-label="회원 상태">
      <li className="chip">가입 {join}</li>
      <li className="chip">등급 {grades.length ? grades.join('·') : '일반'}</li>
      <li className="chip">Lv.{info.level}</li>
      {restrictions.data && <li className={active ? 'chip chip-bad' : 'chip'}>{active ? '제한 중' : '제한 없음'}</li>}
      {warnings.data && (
        <li className={unacked > 0 ? 'chip chip-bad' : 'chip'}>
          경고 {warnings.data.length}건{unacked > 0 && ` · 미확인 ${unacked}`}
        </li>
      )}
    </ul>
  );
}

function MemberPage() {
  const { id } = useParams();
  const [done, setDone] = useState(null);
  const [tab, setTab] = useTabParam(MEMBER_TABS);
  const [panel, setPanel] = useState(null); // 'restrict' | 'lift' | 'warn' — 열린 칸은 한 번에 하나
  const [rv, setRv] = useState(0);
  const [wv, setWv] = useState(0);
  const { data, error, loading, retry } = useAsync(async () => {
    const [champs, detail] = await Promise.all([getChampionMap(), getMemberDetail(id)]);
    return { champs, ...detail };
  }, [id]);
  // 활동 제한·경고 기록은 여기서 한 번만 읽어 칩·칸·버튼이 같이 쓴다
  const restrictions = useAsync(() => getMemberRestrictions(id), [id, rv], { enabled: !!data });
  const warnings = useAsync(() => getMemberWarnings(id), [id, wv], { enabled: !!data });
  const withdrawn = error?.code === 'P0002';
  const say = (text) => setDone(text);
  const rBlock = data ? restrictBlockedBy(data.info, activeRestriction(restrictions.data)) : null;
  const wBlock = data ? warnBlockedBy(data.info) : null;
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
          <StatusChips info={data.info} restrictions={restrictions} warnings={warnings} />
          {done && <p className="notice" role="status">{done}</p>}
          <AdminTabs tabs={MEMBER_TABS} active={tab} onChange={setTab} label="회원 정보 탭" idPrefix="member" />

          <TabPanel tabKey="info" active={tab} idPrefix="member">
            <Info info={data.info} onDone={(text) => { setDone(text); retry(); }} />
            {(restrictions.data || warnings.data) && (
              <div className="row-actions member-actions" aria-label="조치">
                {restrictions.data && (
                  <button
                    type="button" className="btn btn-small btn-op" disabled={!!rBlock} aria-expanded={panel === 'restrict'}
                    onClick={() => setPanel((p) => (p === 'restrict' ? null : 'restrict'))}
                  >
                    활동 제한 걸기
                  </button>
                )}
                {warnings.data && (
                  <button
                    type="button" className="btn btn-small btn-op" disabled={!!wBlock} aria-expanded={panel === 'warn'}
                    onClick={() => setPanel((p) => (p === 'warn' ? null : 'warn'))}
                  >
                    경고 보내기
                  </button>
                )}
              </div>
            )}
            {restrictions.data && rBlock && <small className="hint">{rBlock}</small>}
            {warnings.data && wBlock && <small className="hint">{wBlock}</small>}
            <RestrictionPanel
              member={data.info} state={restrictions} panel={panel} setPanel={setPanel}
              onChanged={() => setRv((n) => n + 1)} onDone={say}
            />
            <WarningPanel
              member={data.info} open={panel === 'warn'} setOpen={(v) => setPanel(v ? 'warn' : null)}
              onChanged={() => setWv((n) => n + 1)} onDone={say}
            />
            <RestrictionAdmin state={restrictions} onLift={() => setPanel('lift')} />
            <WarningAdmin state={warnings} />
          </TabPanel>

          <TabPanel tabKey="activity" active={tab} idPrefix="member">
            <Writings data={data} />
            <EditedBuilds data={data} />
          </TabPanel>

          <TabPanel tabKey="records" active={tab} idPrefix="member">
            <ModerationHistory rows={data.moderation} />
            <DeletedWritings userId={id} />
          </TabPanel>
        </>
      )}
    </article>
  );
}

function Info({ info, onDone }) {
  useTitleInfo(); // 054: 칭호 이름은 앱이 처음 읽은 칭호 정보에서 (한정판 포함, 모르는 키는 키 그대로)
  const titles = (info.titles ?? []).map(titleName);
  return (
    <section className="section" aria-label="기본 정보">
      <h2 className="section-title">기본 정보</h2>
      <p><UserName profile={info} /></p>
      <ul className="log-list info-grid" aria-label={`${info.nickname} 회원 정보`}>
        <li>가입일 {fmtDateTime(info.created_at)}</li>
        <li>가입 방식 {joinedWith(info)}</li>
        <li className="wide">등급 {ROLE_LABEL[info.role] ?? info.role}{info.influencer && ` · 장인 (${INFLUENCER_KINDS[info.influencer] ?? info.influencer})`}{info.nickname_state === 'pending' && ' · 장인 인증 대기'}{info.nickname_state === 'yielding' && ' · 닉네임 변경 예정'}</li>
        <li className="wide">레벨 {info.level} · 경험치 {info.xp}{info.main_title ? ` · 대표 칭호 ${titleName(info.main_title)}` : ''}</li>
        <li className="wide">얻은 칭호 {titles.length ? titles.join(', ') : '없음'}</li>
        <li className="wide">활동 글 {info.posts}개 · 댓글 {info.comments}개 · 상대법 {info.matchups}개 · 빌드 {info.builds}개</li>
        {(info.deleted_posts > 0 || info.deleted_comments > 0) && (
          <li className="wide">지운 글 {info.deleted_posts}개 · 지운 댓글 {info.deleted_comments}개 <small className="hint">(1년 보관, 운영자만)</small></li>
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
      {info.influencer && <MemberPhoto member={info} onDone={onDone} />}
    </section>
  );
}

/** 062: 장인의 지금 프로필 사진 + [프로필 사진 삭제] (사유 필수, 장인에게 알림). 신고가 없어도 운영자가 바로 지울 수 있다 */
function MemberPhoto({ member, onDone }) {
  const [removing, setRemoving] = useState(false);
  const { data: path, loading } = useAsync(() => getMemberPhotoPath(member.id), [member.id]);
  if (loading || !path) return null;
  return (
    <div className="member-photo" aria-label="프로필 사진">
      <ProfilePhoto path={path} alt={`${member.nickname} 프로필 사진`} className="inf-hero-photo" fallback={<p className="hint">사진을 불러오지 못했습니다.</p>} />
      {!removing ? (
        <div className="row-actions">
          <button type="button" className="btn btn-small btn-op" onClick={() => setRemoving(true)}>프로필 사진 삭제</button>
        </div>
      ) : (
        <NoteForm
          id={`remove-member-photo-${member.id}`}
          label="삭제 사유 (필수, 장인에게 보입니다)"
          confirmLabel="프로필 사진 삭제 확정"
          busyLabel="삭제하는 중…"
          onCancel={() => setRemoving(false)}
          onSubmit={async (note) => {
            await removeProfilePhoto(member.id, note);
            setRemoving(false);
            onDone('프로필 사진을 삭제했습니다. 장인에게 알림이 갔습니다.');
          }}
        />
      )}
    </div>
  );
}

const L = PREVIEW_COUNT.logs;

function Writings({ data }) {
  const name = (cid) => data.champs[cid]?.name ?? cid;
  const docTitle = (c) => matchupTitle(name(c.counter_champion), name(c.target_champion));
  return (
    <section className="section" aria-label="쓴 글·댓글">
      <h2 className="section-title">쓴 글 (최근 {data.posts.length}개)</h2>
      <LimitedList
        items={data.posts} limit={L} className="log-list" label="쓴 글"
        renderItem={(p) => (
          <li key={p.id}>
            <Link to={`/board/${p.id}`} className="op-link">{p.title}</Link>
            {p.status === 'hidden' && <> <span className="hint">(숨김)</span></>}
            {' · '}{fmtDateTime(p.created_at)} · 댓글 {p.comment_count}개
            {p.excerpt && <><br /><small className="hint">{p.excerpt}</small></>}
          </li>
        )}
      />
      <h2 className="section-title">쓴 댓글 (최근 {data.comments.length}개)</h2>
      <LimitedList
        items={data.comments} limit={L} className="log-list" label="쓴 댓글"
        renderItem={(c) => (
          <li key={`${c.kind}-${c.id}`}>
            {c.kind === 'post'
              ? <Link to={`/board/${c.post_id}`} className="op-link">글 「{c.post_title}」</Link>
              : <Link to={`/champion/${c.target_champion}/counter/${c.counter_champion}#comments`} className="op-link">상대법 「{docTitle(c)}」</Link>}
            {c.status === 'hidden' && <> <span className="hint">(숨김)</span></>}
            {' · '}{fmtDateTime(c.created_at)}
            <br /><small className="hint">{c.excerpt}</small>
          </li>
        )}
      />
    </section>
  );
}

function EditedBuilds({ data }) {
  const name = (cid) => data.champs[cid]?.name ?? cid;
  return (
    <section className="section" aria-label="고친 빌드">
      <h2 className="section-title">고친 빌드 (최근 {data.edited_builds.length}개)</h2>
      <LimitedList
        items={data.edited_builds} limit={L} className="log-list" label="고친 빌드 목록"
        renderItem={(b) => (
          <li key={b.build_id}>
            <Link to={`/champion/${b.target_champion}/counter/${b.counter_champion}?build=${b.build_id}`} className="op-link">
              {matchupTitle(name(b.counter_champion), name(b.target_champion))} · 빌드 {b.seq}{b.name ? ` (${b.name})` : ''}
            </Link>
            {b.status === 'hidden' && <> <span className="hint">(숨김)</span></>}
            {' · '}{b.edits}번 고침 · 마지막 {fmtDateTime(b.last_at)}
          </li>
        )}
      />
    </section>
  );
}

function ModerationHistory({ rows }) {
  return (
    <section className="section" aria-label="처리 이력">
      <h2 className="section-title">처리 이력 (최근 {rows.length}개)</h2>
      <LimitedList
        items={rows} limit={L} className="log-list" label="처리 이력 목록"
        renderItem={(r) => (
          <li key={r.id}>
            {fmtDateTime(r.created_at)} · {ACTION_LABEL[r.action] ?? r.action} · {r.target_kind === 'user' ? '회원' : targetText(r)}
            {' · '}{r.actor_nickname || WITHDRAWN_USER} ({ROLE_LABEL[r.actor_role] ?? r.actor_role})
            {r.note && <> · {r.note}</>}
          </li>
        )}
      />
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
  if (rows.length === 0) return <NoneLine />;
  return (
    <>
      <p className="hint">지운 날부터 {data.keep_days}일 보관한 뒤 완전히 삭제됩니다. 다른 회원에게는 보이지 않습니다.</p>
      <LimitedList
        items={rows} limit={L} className="log-list" label="지운 글·댓글"
        renderItem={(r) => (
          <li key={r.key}>
            [{r.kind}] {r.title} · {fmtDateTime(r.row.deleted_at)} · {WHO[r.row.delete_kind] ?? r.row.delete_kind}
            {r.row.deleted_by?.nickname && r.row.delete_kind === 'staff' && <> ({r.row.deleted_by.nickname})</>}
            {r.row.delete_note && <> · 사유: {r.row.delete_note}</>}
            {r.body && <><br /><small className="hint">{r.body}</small></>}
          </li>
        )}
      />
    </>
  );
}
