import { useEffect, useState } from 'react';
import { useParams } from 'react-router-dom';
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
import { LayersIcon } from '../components/Icons';
import { INFLUENCER_KINDS, displayNickname } from '../lib/nickname';
import { useAuth } from '../lib/auth';
import { useAsync } from '../lib/useAsync';
import NotFound from './NotFound';

const day = (ts) => (ts ? String(ts).slice(0, 10) : '');

/**
 * 장인 페이지 (/u/:id — 047 공개 프로필을 050에서 빌드 중심으로, SPEC 6-34 · 6-36).
 * 위: 닉네임 + 장인 표시 + 유형 · 팔로워 수 · [팔로우] · 링크(작게). 본문: 그 장인이 처음 만든 공개 빌드(influencer_builds, 최근 수정순, 20개씩 [더보기]).
 * 팔로워 수는 누구나, 팔로워 목록은 로그인한 사람에게만 [팔로워 목록] 버튼(20개씩).
 * DB가 장인이 아니거나 없는 id·모양이 틀린 id에 모두 null을 주므로 화면도 모두 같은 "없는 페이지".
 * 이메일·라이엇 닉네임·역할·레벨은 DB가 주지 않는다.
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
  return (
    <Profile
      key={`${id}:${me}`} data={data} me={me} signedIn={signedIn} notice={notice}
      onDone={(message) => { setNotice(message); retry(); }}
    />
  );
}

function Profile({ data, me, signedIn, notice, onDone }) {
  const { profile, champs } = data;
  const [follow, setFollow] = useState({ following: data.following, count: Number(data.first.follower_count) || 0 });
  const [builds, setBuilds] = useState({ items: data.first.items, total: Number(data.first.total) || 0, page: 1 });
  const [more, setMore] = useState({ busy: false, error: null });
  const [showFollowers, setShowFollowers] = useState(false);
  const kind = INFLUENCER_KINDS[profile.influencer];
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
          <h1 className="doc-title" data-page-title={`${profile.nickname} 프로필`}>
            <InfluencerName profile={profile} />
          </h1>
          {me !== profile.id && (
            <FollowButton
              id={profile.id} nickname={profile.nickname} following={follow.following}
              onChange={(r) => setFollow({ following: !!r?.following, count: Number(r?.follower_count) || 0 })}
            />
          )}
        </div>
        <p className="doc-sub inf-meta">
          {kind && <><span className="inf-kind">{`인증된 ${kind}`}</span>{' · '}</>}
          <span>팔로워 <strong className="follower-count">{follow.count.toLocaleString()}</strong>명</span>
          {signedIn ? (
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
        {profile.links.length > 0 && <p className="hint">장인이 올린 외부 사이트입니다. 탑신병자가 내용을 보증하지 않습니다.</p>}
      </header>
      {showFollowers && <Followers id={profile.id} count={follow.count} />}
      {notice && <p className="notice" role="status">{notice}</p>}

      <section className="me-section" aria-labelledby="pp-builds">
        <SectionHead icon={LayersIcon} id="pp-builds" count={builds.total}>처음 만든 빌드</SectionHead>
        {builds.items.length === 0 ? (
          <p className="empty">공개된 빌드가 없습니다.</p>
        ) : (
          <ul className="profile-builds inf-build-list">
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

/** 팔로워 목록 (로그인한 사람만 — DB도 막는다). 최근 팔로우 순, 20개씩 [더보기] */
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
          {state.items.map((f) => (
            <li key={f.id}>
              {f.nickname ? <InfluencerName profile={f} linkTo={f.influencer ? f.id : null} /> : <span className="muted">{displayNickname(f, '닉네임을 정하지 않은 사용자')}</span>}
              <small className="muted">{day(f.followed_at)} 팔로우</small>
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
