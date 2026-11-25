import { useEffect, useState } from 'react';
import { Link, useLocation, useNavigate, useParams, useSearchParams } from 'react-router-dom';
import { getMemberPage, getPublicProfile } from '../api/links';
import { getFollowStatus, getFollowers, getInfluencerBuilds } from '../api/follow';
import { isYoutubeHost, youtubeHandle } from '../lib/links';
import ProfileBuilds from '../components/ProfileBuilds';
import MemberProfile from '../components/MemberProfile';
import ShareButton from '../components/ShareButton';
import { getChampionMap } from '../api/ddragon';
import { ErrorBox, Loading } from '../components/Status';
import ExternalLink from '../components/ExternalLink';
import LinkActions from '../components/LinkActions';
import FollowButton from '../components/FollowButton';
import { InfluencerName } from '../components/UserName';
import { UserIcon } from '../components/Icons';
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
 * 1.3 패치 1-C(6-98): 위 카드 = 사진 · 닉네임 + 장인 표시 + 유형 · 「빌드 N · 팔로워 N」(받은 추천 수는 넣지 않음), 버튼 줄 = [팔로우] [유튜브 @채널명] [공유] (+ 외부 이동 안내 한 줄),
 * 나머지 링크는 작게. 본문: 그 장인이 처음 만든 공개 빌드(ProfileBuilds — 「최신순」(기본, 최근 수정순)·「인기순」 칩, 쪽 번호 20개씩).
 * 팔로워 수는 누구나. [팔로워 목록] 버튼(20개씩 [더보기])은 063부터 "내 페이지"일 때만(정식 회원) + 운영자(운영자 모드 켜짐)에게만 — DB도 같은 규칙.
 * 052: ?followers=1(새 팔로워 알림 → /me/followers)로 열면 볼 수 있는 사람에게는 팔로워 목록이 처음부터 펼쳐져 있다.
 * 6-111: 장인이 아니면(public_profile null) member_page(075)를 불러 일반 사용자 개인 페이지(MemberProfile)를 그린다.
 * 둘 다 null이면(없는 id·모양 틀림·공개 빌드 5개 미만·정지·탈퇴 등) 모두 같은 "없는 페이지" — 어느 쪽인지 화면으로 구분되지 않는다.
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
    const member = profile ? null : await getMemberPage(id, 1); // 장인이 아닐 때만 (장인 화면은 요청이 늘지 않는다)
    return { profile, first, champs, member, following: !!status[id] };
  }, [id, me]);

  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  const influencer = !!data.profile && !!data.first;
  if (!influencer && !data.member) return <NotFound />;
  // 061: 내가 차단한 사용자 → 빌드·링크·팔로우 대신 안내만
  if (isBlocked(auth, influencer ? data.profile.id : data.member.member.id)) {
    return (
      <article className="me-page public-profile">
        <h1 className="doc-title">{BLOCKED_PROFILE}</h1>
        <p className="empty">
          차단한 사용자의 빌드와 글은 보이지 않습니다. <Link to={SETTINGS_PATH}>계정 설정</Link>에서 차단을 해제할 수 있습니다.
        </p>
      </article>
    );
  }
  if (!influencer) return <MemberProfile key={`${id}:${me}`} first={data.member} champs={data.champs} />;
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
  const [params] = useSearchParams();
  // 063: 팔로워 목록은 장인 본인(비회원 아님)과 운영자만 (DB influencer_followers도 같은 규칙)
  const canSeeFollowers = signedIn && !isGuest(auth) && (me === profile.id || auth.isOperator);
  const [showFollowers, setShowFollowers] = useState(() => canSeeFollowers && params.get('followers') === '1');
  const kind = INFLUENCER_KINDS[profile.influencer];
  const buildTotal = Number(data.first.total) || 0; // 공개된 빌드만 (influencer_builds의 total)
  const youtube = profile.links.find((l) => isYoutubeHost(l.host)) ?? null; // 버튼 줄로 올린 링크 — 나머지는 아래 목록
  const otherLinks = profile.links.filter((l) => l !== youtube);
  const shareUrl = `${window.location.origin}/u/${profile.id}`; // 쪽·정렬 같은 주소 꼬리 없이 프로필 주소만
  // 075: 내 공개 프로필에서는 동그라미가 곧 사진 올리기·바꾸기·삭제 버튼 (인증된 장인 본인만, 062 전 DB면 예전 모양)
  const ownEditable = auth.status === 'signedIn' && auth.user?.id === profile.id && !!auth.profile?.influencer && !auth.profile.is_guest && 'photo_path' in auth.profile;
  // 3b: 링크 옆 ⋮ — 신고(정식 회원) / 삭제(운영진). 장인 페이지는 역할을 주지 않으므로 운영진의 링크인지는 DB가 가른다
  const actions = (l) => <LinkActions link={l} ownerId={profile.id} label="링크 더보기" onDone={onDone} />;

  return (
    <article className="me-page public-profile">
      <header className="me-hero inf-hero">
        <p className="me-hero-label">장인</p>
        <div className="inf-hero-top">
          <div className="inf-hero-name">
            {ownEditable ? (
              <ProfileAvatarEditor auth={auth} shell="inf-hero-avatar" fallback={<UserIcon size={28} />} />
            ) : (
              <ProfilePhoto
                path={profile.photo_path} alt={`${profile.nickname} 프로필 사진`} className="inf-hero-photo"
                fallback={<span className="inf-hero-avatar inf-hero-initial" aria-hidden="true">{Array.from(profile.nickname ?? '?')[0]}</span>}
              />
            )}
            <h1 className="doc-title" data-page-title={`${profile.nickname} 프로필`}>
              <InfluencerName profile={profile} />
            </h1>
          </div>
          <div className="inf-hero-actions">
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
          <span>빌드 <strong className="build-total">{buildTotal.toLocaleString()}</strong></span>
          {' · '}
          <span>팔로워 <strong className="follower-count">{follow.count.toLocaleString()}</strong></span>
        </p>
        <div className="inf-btn-row">
          {me !== profile.id && (
            <FollowButton
              id={profile.id} nickname={profile.nickname} following={follow.following}
              onChange={(r) => setFollow({ following: !!r?.following, count: Number(r?.follower_count) || 0 })}
            />
          )}
          {youtube && (
            <span className="link-item inf-yt">
              <ExternalLink link={youtube} className="btn yt-btn">{youtubeHandle(youtube.url) ?? '채널 보기'}</ExternalLink>
              {actions(youtube)}
            </span>
          )}
          <ShareButton url={shareUrl} title={`${profile.nickname} 프로필`} />
        </div>
        {youtube && <p className="hint inf-leave-note">유튜브 버튼은 외부 사이트로 이동합니다. 장인이 올린 링크이며 탑신병자가 내용을 보증하지 않습니다.</p>}
        {canSeeFollowers && (
          <p className="inf-followers-toggle">
            <button
              type="button" className="link-btn" aria-expanded={showFollowers} aria-controls="pp-followers"
              onClick={() => setShowFollowers((v) => !v)}
            >
              {showFollowers ? '팔로워 목록 닫기' : '팔로워 목록'}
            </button>
          </p>
        )}
        {otherLinks.length > 0 && (
          <ul className="link-list inf-links" aria-label="링크">
            {otherLinks.map((l) => <li key={l.id} className="link-item"><ExternalLink link={l} />{actions(l)}</li>)}
          </ul>
        )}
        {profile.links.length === 0 && me === profile.id && (
          <div className="inf-links-empty">
            <p className="hint">채널 링크를 등록해 보세요.</p>
            <Link to="/me/links" className="btn btn-small">링크 관리로 가기</Link>
          </div>
        )}
        {otherLinks.length > 0 && <p className="hint">장인이 올린 외부 사이트입니다. 탑신병자가 내용을 보증하지 않습니다.</p>}
      </header>
      {canSeeFollowers && showFollowers && <Followers id={profile.id} count={follow.count} />}
      {notice && <p className="notice" role="status">{notice}</p>}

      <ProfileBuilds id={profile.id} champs={champs} first={data.first} actions={actions} />
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
