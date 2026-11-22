import { Link } from 'react-router-dom';
import BuildTitle from './BuildTitle';
import { ChampIcon } from './InfluencerBuildCard';
import { ThumbIcon } from './Icons';

/** 한 번에 더 보이는 개수 (전체 빌드 목록·저장한 빌드 [더보기]) */
export const BUILD_ROWS_STEP = 20;

/** 주소의 ?n= (몇 개까지 펼쳤나) → 20의 배수, 최소 20 */
export const shownCount = (raw) => {
  const n = Number.parseInt(raw ?? '', 10);
  return Number.isFinite(n) && n > BUILD_ROWS_STEP ? Math.ceil(n / BUILD_ROWS_STEP) * BUILD_ROWS_STEP : BUILD_ROWS_STEP;
};

/**
 * 빌드 한 줄 (전체 빌드 목록 /builds 6-81, 저장한 빌드 /lists 6-82가 같이 쓴다).
 * 챔피언 아이콘 2개 + "내 챔피언 vs 상대" + 빌드 이름(장인 빌드 뱃지) + 선마 + 추천 수, 누르면 그 상대법의 그 빌드로.
 * b = { id, name, seq, max_skill, up, author: { influencer }, target, mine }, champs = Data Dragon 챔피언 표
 */
export default function BuildRow({ b, champs }) {
  const name = (id) => champs[id]?.name ?? id;
  return (
    <li>
      <Link className="inf-build-card all-build" to={`/champion/${b.target}/counter/${b.mine}?build=${b.id}`}>
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
