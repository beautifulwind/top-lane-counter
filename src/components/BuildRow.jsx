import { Link } from 'react-router-dom';
import BuildTitle from './BuildTitle';
import { ChampIcon } from './InfluencerBuildCard';
import { ThumbIcon } from './Icons';
import { isInfluencerBuild } from '../lib/wikiBuild';

/**
 * 빌드 한 줄 = 왼쪽 강조선 카드 (전체 빌드 목록 /builds 6-81, 저장한 빌드 /lists 6-82가 같이 쓴다. 카드 모양은 6-87).
 * 강조선: 장인 빌드("장인 빌드" 뱃지와 같은 isInfluencerBuild)는 주황, 아니면 회색. 목록은 <ul className="build-cards">.
 * 챔피언 아이콘 2개 + "내 챔피언 vs 상대" + 빌드 이름(장인 빌드 뱃지) + 선마 + 추천 수, 누르면 그 상대법의 그 빌드로.
 * b = { id, name, seq, max_skill, up, author: { influencer }, target, mine }, champs = Data Dragon 챔피언 표
 */
export default function BuildRow({ b, champs }) {
  const name = (id) => champs[id]?.name ?? id;
  return (
    <li className={isInfluencerBuild(b) ? 'build-card is-influencer' : 'build-card'}>
      <Link className="build-card-link inf-build-card all-build" to={`/champion/${b.target}/counter/${b.mine}?build=${b.id}`}>
        <span className="inf-build-champs" aria-hidden="true">
          <ChampIcon champ={champs[b.mine]} />
          <span className="vs">vs</span>
          <ChampIcon champ={champs[b.target]} />
        </span>
        <span className="inf-build-text">
          <strong className="inf-build-matchup">{`${name(b.mine)} vs ${name(b.target)}`}</strong>
          <span className="inf-build-name"><BuildTitle build={b} /></span>
          <small className="muted all-build-meta">
            <span className="skill-group">선마 <kbd className="skill-key">{b.max_skill ?? '?'}</kbd></span>
            <span className="vote-count"><ThumbIcon size={12} /><span className="sr-only">추천 </span>{b.up}</span>
          </small>
        </span>
      </Link>
    </li>
  );
}
