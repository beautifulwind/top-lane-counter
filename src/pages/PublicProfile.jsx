import { useEffect, useState } from 'react';
import { Link, useLocation, useNavigate, useParams, useSearchParams } from 'react-router-dom';
import { getPublicProfile } from '../api/links';
import { getFollowStatus, getFollowers, getInfluencerBuilds } from '../api/follow';
import { getChampionMap } from '../api/ddragon';
import { ErrorBox, Loading } from '../components/Status';
import SectionHead from '../components/SectionHead';
import ExternalLink from '../components/ExternalLink';
import LinkActions from '../components/LinkActions';
import FollowButton from '../components/FollowButton';
import { InfluencerName } from '../components/UserName';
import InfluencerBuildCard from '../components/InfluencerBuildCard';
import { LayersIcon, UserIcon } from '../components/Icons';
import { INFLUENCER_KINDS, displayNickname } from '../lib/nickname';
import { canVote, isBlocked, isGuest, useAuth } from '../lib/auth';
import { BLOCKED_PROFILE, SETTINGS_PATH, blockMenuItem } from '../lib/blocks';
import MoreMenu from '../components/MoreMenu';
import NoteForm from '../components/NoteForm';
import { ReportForm } from '../components/BoardParts';
import ProfilePhoto, { ProfileAvatarEditor } from '../components/ProfilePhoto';
import { PHOTO_REPORT_REASONS, removeProfilePhoto, reportProfilePhoto } from '../api/profilePhoto';
import { useAsync } from '../lib/useAsync';
import NotFound from './NotFound';

/**
 * 장인 페이지 (/u/:id — 047 공개 프로필을 050에서 빌드 중심으로, SPEC 6-34 · 6-36).
 * 위: 닉네임 + 장인 표시 + 유형 · 팔로워 수 · [팔로우] · 링크(작게). 본문: 그 장인이 처음 만든 공개 빌드(influencer_builds, 최근 수정순, 20개씩 [더보기]).
 * 팔로워 수는 누구나. [팔로워 목록] 버튼(20개씩)은 063부터 "내 페이지"일 때만(정식 회원) + 운영자(운영자 모드 켜짐)에게만 — DB도 같은 규칙.
 * 052: ?followers=1(새 팔로워 알림 → /me/followers)로 열면 볼 수 있는 사람에게는 팔로워 목록이 처음부터 펼쳐져 있다.
 * DB가 장인이 아니거나 없는 id·모양이 틀린 id에 모두 null을 주므로 화면도 모두 같은 "없는 페이지".
 * 이메일·라이엇 닉네임·역할·레벨은 DB가 주지 않는다.
 * 062: 장인 프로필 사진(있을 때만 — 없으면 예전 그대로, 보기 전용. 올리기·바꾸기·삭제는 마이페이지 카드에서).
 *      ⋮ 메뉴: [프로필 사진 신고](정식 회원, 남의 사진) / [이 사용자 차단](061) / [프로필 사진 삭제](운영자만, 사유 필수 → 장인에게 알림)
 */
export default function PublicProfile() {
  const { id } = useParams();
  const auth = useAuth();
  const me = auth.user?.id ?? null;
  const signedIn = auth.status === 'signedIn';
  const [notice, setNotice] = useState(null); // 신고·삭제 뒤 안내 (다시 읽어도 남는다)
  const { data, error, loading, retry } = useAsync(async () => {
    const [profile, first, champs, status] = await Promise.all([
      getPublicProfile(id),
      getInfluencerBuilds(id, 1),
      getChampionMap().catch(() => ({})),
      me && me !== id ? getFollowStatus([id]) : {},
    ]);
    return { profile, first, champs, following: !!status[id] };
  }, [id, me]);

  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  if (!data.profile || !data.first) return <NotFound />;
  // 061: 내가 차단한 장인 → 빌드·링크·팔로우 대신 안내만
  if (isBlocked(auth, data.profile.id)) {
    return (
      <article className="me-page public-profile">
        <h1 className="doc-title">{BLOCKED_PROFILE}</h1>
        <p className="empty">
          차단한 사용자의 빌드와 글은 보이지 않습니다. <Link to={SETTINGS_PATH}>계정 설정</Link>에서 차단을 해제할 수 있습니다.
        </p>
      </article>
    );
  }
  return (
    <Profile
      key={`${id}:${me}`} data={data} me={me} signedIn={signedIn} notice={notice}
      onDone={(message) => { setNotice(message); retry(); }}
    />
  );
}

function Profile({ data, me, signedIn, notice, onDone }) {
  const { profile, champs } = data;
  const auth = useAuth();
  const navigate = useNavigate();
  const location = useLocation();
  const [photoMode, setPhotoMode] = useState(null); // 'report' | 'remove'
  const [follow, setFollow] = useState({ following: data.following, count: Number(data.first.follower_count) || 0 });
  const [builds, setBuilds] = useState({ items: data.first.items, total: Number(data.first.total) || 0, page: 1 });
  const [more, setMore] = useState({ busy: false, error: null });
  const [params] = useSearchParams();
  // 063: 팔로워 목록은 장인 본인(비회원 아님)과 운영자만 (DB influencer_followers도 같은 규칙)
  const canSeeFollowers = signedIn && !isGuest(auth) && (me === profile.id || auth.isOperator);
  const [showFollowers, setShowFollowers] = useState(() => canSeeFollowers && params.get('followers') === '1');
  const kind = INFLUENCER_KINDS[profile.influencer];
  // 075: 내 공개 프로필에서는 동그라미가 곧 사진 올리기·바꾸기·삭제 버튼 (인증된 장인 본인만, 062 전 DB면 예전 모양)
  const ownEditable = auth.status === 'signedIn' && auth.user?.id === profile.id && !!auth.profile?.influencer && !auth.profile.is_guest && 'photo_path' in auth.profile;
  // 3b: 링크 옆 ⋮ — 신고(정식 회원) / 삭제(운영진). 장인 페이지는 역할을 주지 않으므로 운영진의 링크인지는 DB가 가른다
  const actions = (l) => <LinkActions link={l} ownerId={profile.id} label="링크 더보기" onDone={onDone} />;

  const loadMore = async () => {
    setMore({ busy: true, error: null });
    try {
      const next = await getInfluencerBuilds(profile.id, builds.page + 1);
      if (!next) throw new Error('장인 인증이 해제돼 빌드를 더 불러올 수 없습니다.');
      setBuilds((b) => {
        const seen = new Set(b.items.map((x) => x.id));
        return { items: [...b.items, ...next.items.filter((x) => !seen.has(x.id))], total: Number(next.total) || 0, page: b.page + 1 };
      });
      setMore({ busy: false, error: null });
    } catch (e) {
      setMore({ busy: false, error: e.message });
    }
  };

  return (
    <article className="me-page public-profile">
      <header className="me-hero inf-hero">
        <p className="me-hero-label">장인</p>
        <div className="inf-hero-top">
          <div className="inf-hero-name">
            {ownEditable ? (
              <ProfileAvatarEditor auth={auth} shell="inf-hero-avatar" fallback={<UserIcon size={28} />} />
            ) : (
              <ProfilePhoto path={profile.photo_path} alt={`${profile.nickname} 프로필 사진`} className="inf-hero-photo" />
            )}
            <h1 className="doc-title" data-page-title={`${profile.nickname} 프로필`}>
              <InfluencerName profile={profile} />
            </h1>
          </div>
          <div className="inf-hero-actions">
            {me !== profile.id && (
              <FollowButton
                id={profile.id} nickname={profile.nickname} following={follow.following}
                onChange={(r) => setFollow({ following: !!r?.following, count: Number(r?.follower_count) || 0 })}
              />
            )}
            <ProfileMenu
              auth={auth} profile={profile} onMode={setPhotoMode}
              onLogin={() => navigate('/login', { state: { from: location.pathname } })} onDone={onDone}
            />
          </div>
        </div>
        {photoMode === 'report' && (
          <div className="link-action-form">
            <ReportForm
              id={`report-photo-${profile.id}`}
              what="프로필 사진"
              reasons={PHOTO_REPORT_REASONS}
              hints={null}
              note="신고 내용은 운영자만 봅니다."
              onCancel={() => setPhotoMode(null)}
              onSubmit={async (reason, detail) => {
                await reportProfilePhoto(profile.id, reason, detail);
                setPhotoMode(null);
                onDone('프로필 사진을 신고했습니다. 운영자가 확인하겠습니다.');
              }}
            />
          </div>
        )}
        {photoMode === 'remove' && (
          <div className="link-action-form">
            <NoteForm
              id={`remove-photo-${profile.id}`}
              label="삭제 사유 (필수, 장인에게 보입니다)"
              confirmLabel="프로필 사진 삭제 확정"
              busyLabel="삭제하는 중…"
              onCancel={() => setPhotoMode(null)}
              onSubmit={async (note) => {
                await removeProfilePhoto(profile.id, note);
                setPhotoMode(null);
                onDone('프로필 사진을 삭제했습니다. 장인에게 알림이 갔습니다.');
              }}
            />
          </div>
        )}
        <p className="doc-sub inf-meta">
          {kind && <><span className="inf-kind">{`인증된 ${kind}`}</span>{' · '}</>}
          <span>팔로워 <strong className="follower-count">{follow.count.toLocaleString()}</strong>명</span>
          {canSeeFollowers ? (
            <>
              {' '}
              <button
                type="button" className="link-btn" aria-expanded={showFollowers} aria-controls="pp-followers"
                onClick={() => setShowFollowers((v) => !v)}
              >
                {showFollowers ? '팔로워 목록 닫기' : '팔로워 목록'}
              </button>
            </>
          ) : null}
        </p>
        {profile.links.length > 0 && (
          <ul className="link-list inf-links" aria-label="링크">
            {profile.links.map((l) => <li key={l.id} className="link-item"><ExternalLink link={l} />{actions(l)}</li>)}
          </ul>
        )}
        {profile.links.length === 0 && me === profile.id && (
          <div className="inf-links-empty">
            <p className="hint">채널 링크를 등록해 보세요.</p>
            <Link to="/me/links" className="btn btn-small">링크 관리로 가기</Link>
          </div>
        )}
        {profile.links.length > 0 && <p className="hint">장인이 올린 외부 사이트입니다. 탑신병자가 내용을 보증하지 않습니다.</p>}
      </header>
      {canSeeFollowers && showFollowers && <Followers id={profile.id} count={follow.count} />}
      {notice && <p className="notice" role="status">{notice}</p>}

      <section className="me-section" aria-labelledby="pp-builds">
        <SectionHead icon={LayersIcon} id="pp-builds" count={builds.total}>처음 만든 빌드</SectionHead>
        {builds.items.length === 0 ? (
          <p className="empty">공개된 빌드가 없습니다.</p>
        ) : (
          <ul className="build-cards">
            {builds.items.map((b) => <InfluencerBuildCard key={b.id} b={b} champs={champs} linkActions={actions} />)}
          </ul>
        )}
        {builds.items.length < builds.total && (
          <div className="actions">
            <button type="button" className="btn" onClick={loadMore} disabled={more.busy}>
              {more.busy ? '불러오는 중…' : `더보기 (${builds.total - builds.items.length}개 남음)`}
            </button>
          </div>
        )}
        {more.error && <p className="form-error" role="alert">{more.error}</p>}
      </section>
    </article>
  );
}

/**
 * 장인 페이지 ⋮ 메뉴 (062). 내 페이지면 아무것도 없다(사진은 마이페이지에서).
 *   [프로필 사진 신고]: 사진이 있을 때. 정식 회원만 — 로그인 전·비회원은 누를 수 없는 항목 + 이유. 운영자에게는 신고 대신 [프로필 사진 삭제]
 *   [이 사용자 차단]: 061과 같음 (차단하면 이 페이지가 바로 "차단한 사용자입니다."로 바뀐다)
 */
function ProfileMenu({ auth, profile, onMode, onLogin, onDone }) {
  if (auth.user?.id === profile.id) return null;
  const hasPhoto = !!profile.photo_path;
  const operator = auth.isOperator;
  const signedOut = auth.status !== 'signedIn';
  const report = !hasPhoto || operator ? null
    : canVote(auth) ? { label: '프로필 사진 신고', write: true, onSelect: () => onMode('report') }
      : signedOut ? { label: '프로필 사진 신고', disabled: true, hint: '로그인하면 신고할 수 있습니다.' }
        : isGuest(auth) ? { label: '프로필 사진 신고', disabled: true, hint: '비회원은 신고할 수 없습니다. 마이페이지에서 구글·카카오를 연결해 주세요.' }
          : null;
  return (
    <MoreMenu
      label="장인 더보기"
      items={[
        report,
        hasPhoto && operator && { label: '프로필 사진 삭제', op: true, danger: true, onSelect: () => onMode('remove') },
        blockMenuItem(auth, profile.id, { nickname: profile.nickname }, { onLogin, onDone }),
      ]}
    />
  );
}

/**
 * 팔로워 목록 (장인 본인·운영자만 — DB도 막는다). 닉네임과 장인 표시만(063: 팔로우한 날 없음). 최근 팔로우 순(DB가 정함), 20개씩 [더보기].
 * 차단 관계(장인↔팔로워, 어느 쪽이든)는 장인 본인이 볼 때만 DB가 빼고 센다. 운영자가 남의 목록을 볼 때는 차단과 상관없이 전부.
 */
function Followers({ id, count }) {
  const [state, setState] = useState({ items: [], total: 0, page: 0, busy: true, error: null });
  const load = async (page) => {
    setState((s) => ({ ...s, busy: true, error: null }));
    try {
      const r = await getFollowers(id, page);
      setState((s) => ({
        items: page === 1 ? r.items : [...s.items, ...r.items.filter((x) => !s.items.some((y) => y.id === x.id))],
        total: Number(r.total) || 0, page, busy: false, error: null,
      }));
    } catch (e) {
      setState((s) => ({ ...s, busy: false, error: e.message }));
    }
  };
  // 팔로우·취소로 수가 바뀌면 처음부터 다시
  useEffect(() => { load(1); }, [id, count]);

  return (
    <section className="me-section followers" id="pp-followers" aria-labelledby="pp-followers-title">
      <h2 className="section-title" id="pp-followers-title">팔로워</h2>
      {state.page === 0 && state.busy && <Loading />}
      {state.page > 0 && state.items.length === 0 && <p className="empty">아직 팔로워가 없습니다.</p>}
      {state.items.length > 0 && (
        <ul className="follower-list">
          {state.items.map((f) => ( // 차단 관계는 DB가 가른다 — 장인 본인에게는 빼고 세고, 운영자에게는 전부 (063)
            <li key={f.id}>
              {f.nickname ? <InfluencerName profile={f} linkTo={f.influencer ? f.id : null} /> : <span className="muted">{displayNickname(f, '닉네임을 정하지 않은 사용자')}</span>}
            </li>
          ))}
        </ul>
      )}
      {state.page > 0 && state.items.length < state.total && (
        <div className="actions">
          <button type="button" className="btn" onClick={() => load(state.page + 1)} disabled={state.busy}>
            {state.busy ? '불러오는 중…' : `더보기 (${state.total - state.items.length}명 남음)`}
          </button>
        </div>
      )}
      {state.error && <p className="form-error" role="alert">{state.error}</p>}
    </section>
  );
}
