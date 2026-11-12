import { useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { getPublicProfile } from '../api/links';
import { getChampionMap } from '../api/ddragon';
import { ErrorBox, Loading } from '../components/Status';
import SectionHead from '../components/SectionHead';
import ExternalLink from '../components/ExternalLink';
import LinkActions from '../components/LinkActions';
import { InfluencerName } from '../components/UserName';
import { LayersIcon, LinkIcon } from '../components/Icons';
import { INFLUENCER_KINDS } from '../lib/nickname';
import { matchupShort } from '../lib/josa';
import { patchMinor } from '../lib/buildContent';
import { useAsync } from '../lib/useAsync';
import NotFound from './NotFound';

/**
 * 장인 공개 프로필 (047, SPEC 6-34 · /u/:id): 닉네임 + 장인 표시 + 유형, 링크, 최근 공개 빌드.
 * DB(public_profile)가 장인이 아니거나 없는 id·모양이 틀린 id에 모두 null을 주므로 화면도 모두 같은 "없는 페이지".
 * 이메일·라이엇 닉네임·레벨·경험치·가입일은 DB가 주지 않는다.
 */
export default function PublicProfile() {
  const { id } = useParams();
  const [notice, setNotice] = useState(null); // 신고·삭제 뒤 안내 (다시 읽어도 남는다)
  const { data, error, loading, retry } = useAsync(async () => {
    const [profile, champs] = await Promise.all([getPublicProfile(id), getChampionMap().catch(() => ({}))]);
    return { profile, champs };
  }, [id]);

  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  const { profile, champs } = data;
  if (!profile) return <NotFound />;
  const name = (c) => champs?.[c]?.name ?? c;
  const done = (message) => { setNotice(message); retry(); };
  // 3b: 링크 옆 ⋮ — 신고(정식 회원) / 삭제(운영진). 공개 프로필은 역할을 주지 않으므로 운영진의 링크인지는 DB가 가른다
  const actions = (l) => <LinkActions link={l} ownerId={profile.id} label="링크 더보기" onDone={done} />;

  return (
    <article className="me-page public-profile">
      <header className="me-hero">
        <p className="me-hero-label">장인 프로필</p>
        <h1 className="doc-title" data-page-title={`${profile.nickname} 프로필`}>
          <InfluencerName profile={profile} />
        </h1>
        {INFLUENCER_KINDS[profile.influencer] && <p className="doc-sub">인증된 {INFLUENCER_KINDS[profile.influencer]}</p>}
      </header>
      {notice && <p className="notice" role="status">{notice}</p>}

      <section className="me-section" aria-labelledby="pp-links">
        <SectionHead icon={LinkIcon} id="pp-links" count={profile.links.length}>링크</SectionHead>
        {profile.links.length === 0 ? (
          <p className="empty">올린 링크가 없습니다.</p>
        ) : (
          <ul className="link-list">
            {profile.links.map((l) => <li key={l.id} className="link-item"><ExternalLink link={l} />{actions(l)}</li>)}
          </ul>
        )}
        <p className="hint">장인이 올린 외부 사이트입니다. 탑신병자가 내용을 보증하지 않습니다.</p>
      </section>

      <section className="me-section" aria-labelledby="pp-builds">
        <SectionHead icon={LayersIcon} id="pp-builds" count={profile.build_count}>처음 만든 빌드</SectionHead>
        {profile.builds.length === 0 ? (
          <p className="empty">공개된 빌드가 없습니다.</p>
        ) : (
          <ul className="profile-builds">
            {profile.builds.map((b) => (
              <li key={b.id}>
                <Link to={`/champion/${b.target_champion}/counter/${b.counter_champion}?build=${b.id}`}>
                  {matchupShort(name(b.counter_champion), name(b.target_champion))} · {b.name || `빌드 ${b.seq ?? ''}`.trim()}
                </Link>
                <small className="muted">{b.patch ? `패치 ${patchMinor(b.patch)} · ` : ''}{String(b.created_at).slice(0, 10)}</small>
                {b.link && <div className="link-item"><ExternalLink link={b.link} />{actions(b.link)}</div>}
              </li>
            ))}
          </ul>
        )}
        {profile.build_count > profile.builds.length && <p className="hint">최근 {profile.builds.length}개만 보여 줍니다.</p>}
      </section>
    </article>
  );
}
