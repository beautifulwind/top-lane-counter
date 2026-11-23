import { Link } from 'react-router-dom';
import VideoLink from './VideoLink';
import { InfluencerName } from './UserName';
import { ThumbIcon } from './Icons';
import { matchupShort } from '../lib/josa';
import { patchMinor } from '../lib/buildContent';
import { isInfluencerBuild } from '../lib/wikiBuild';

const day = (ts) => (ts ? String(ts).slice(0, 10) : '');

/** 챔피언 동그라미 아이콘 (36px). 전체 빌드 목록(6-81)도 쓴다 */
export function ChampIcon({ champ }) {
  if (!champ?.icon) return <span className="ico missing inf-champ" />;
  return <img className="ico inf-champ" src={champ.icon} alt="" width={36} height={36} loading="lazy" />;
}

/**
 * 장인 빌드 카드 한 줄 (050 — 장인 페이지 /u/:id · 팔로우 모아보기 /following 공용). b = DB 빌드 카드(follow_build_card 모양).
 * 6-87: 왼쪽 강조선 카드(BuildRow와 같은 .build-card). 두 목록은 DB가 "처음 만든 분이 지금 장인"인 빌드만 주므로 주황선이고,
 * 빌드에 작성자(author)가 실려 있으면 BuildRow와 같은 isInfluencerBuild로 가른다.
 * 챔피언 아이콘 2개(내 챔피언 vs 상대) + 상대법 이름 + 빌드 이름 + 패치·최근 수정·추천 수, 누르면 그 상대법의 그 빌드로.
 * showAuthor: 카드 맨 위에 장인 닉네임 (모아보기). 카드 전체가 링크라 닉네임은 링크가 아니다(링크 안의 링크 방지).
 * linkActions(l): 빌드 링크 옆 ⋮ (장인 페이지에서만)
 */
export default function InfluencerBuildCard({ b, champs, showAuthor = false, linkActions = null }) {
  const name = (c) => champs?.[c]?.name ?? c;
  return (
    <li className={(b.author ? isInfluencerBuild(b) : true) ? 'build-card is-influencer' : 'build-card'}>
      <Link className="build-card-link inf-build-card" to={`/champion/${b.target_champion}/counter/${b.counter_champion}?build=${b.id}`}>
        <span className="inf-build-champs" aria-hidden="true">
          <ChampIcon champ={champs?.[b.counter_champion]} />
          <span className="vs">vs</span>
          <ChampIcon champ={champs?.[b.target_champion]} />
        </span>
        <span className="inf-build-text">
          {showAuthor && b.author && <span className="inf-build-author"><InfluencerName profile={b.author} /></span>}
          <strong className="inf-build-matchup">{matchupShort(name(b.counter_champion), name(b.target_champion))}</strong>
          <span className="inf-build-name">{b.name || `빌드 ${b.seq ?? ''}`.trim()}</span>
          <small className="muted">
            {b.patch ? `패치 ${patchMinor(b.patch)} · ` : ''}최근 수정 {day(b.updated_at ?? b.created_at)}
            {' · '}<ThumbIcon size={12} /><span className="sr-only">추천 </span>{b.up_count ?? 0}
          </small>
        </span>
      </Link>
      {b.link && <div className="link-item inf-video"><VideoLink link={b.link} />{linkActions?.(b.link)}</div>}
    </li>
  );
}
