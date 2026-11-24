import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { getInfluencerDirectory } from '../api/follow';
import { isBlocked, useAuth } from '../lib/auth';
import { HOME_INFLUENCER_COUNT, HOME_INFLUENCER_FETCH } from '../lib/homeLayout';
import { INFLUENCER_SORT } from '../lib/influencerList';
import { photoFirst } from '../lib/influencerOrder';
import ProfilePhoto from './ProfilePhoto';
import SectionHead from './SectionHead';
import { ArrowRightIcon, UsersIcon } from './Icons';

/**
 * 메인 화면의 장인 줄 (1.3 패치 1-B2, SPEC 6-94·6-95): 최근 활동 장인(사진 없는 장인은 맨 뒤) HOME_INFLUENCER_COUNT명을 사진 원 + 닉네임으로 가로로 보여 준다.
 * 오른쪽의 「전체」는 제자리에 있고(스크롤 영역 밖) 장인 원들만 그 왼쪽에서 밀린다 → /influencers.
 * 불러오는 동안은 같은 높이의 빈 자리만 잡고, 실패하거나 장인이 없으면 줄 전체를 조용히 숨긴다(오류 상자 없음 — 메인 화면은 그대로).
 */
export default function HomeInfluencers() {
  const auth = useAuth();
  const [state, setState] = useState({ status: 'loading', total: 0, items: [] });
  useEffect(() => {
    let alive = true;
    getInfluencerDirectory({ query: '', sort: INFLUENCER_SORT, page: 1, size: HOME_INFLUENCER_FETCH }).then(
      (d) => alive && setState({ status: 'ok', total: Number(d?.total) || 0, items: d?.items ?? [] }),
      () => alive && setState({ status: 'hidden', total: 0, items: [] }),
    );
    return () => { alive = false; };
  }, []);

  if (state.status === 'hidden') return null;
  // 061: 내가 차단한 장인은 뺀다 (/influencers와 같음) → 사진 없는 장인은 맨 뒤 → 앞 HOME_INFLUENCER_COUNT명
  const items = photoFirst(state.items.filter((p) => !isBlocked(auth, p.id))).slice(0, HOME_INFLUENCER_COUNT);
  if (state.status === 'ok' && items.length === 0) return null;

  if (state.status === 'loading') {
    return (
      <section className="section home-inf" aria-hidden="true">
        <div className="section-head"><span className="home-inf-hold" /></div>
        <div className="home-inf-row"><div className="home-inf-hold-row" /></div>
      </section>
    );
  }

  return (
    <section className="section home-inf" aria-labelledby="home-inf-title">
      <SectionHead icon={UsersIcon} count={state.total} unit="명" id="home-inf-title">장인</SectionHead>
      <div className="home-inf-row">
        <ul className="home-inf-scroll" aria-label="장인 목록">
          {items.map((p) => (
            <li key={p.id}>
              <Link to={`/u/${p.id}`} className="home-inf-item" aria-label={`${p.nickname} 장인 페이지`}>
                <span className="home-inf-avatar" aria-hidden="true">
                  <ProfilePhoto
                    path={p.photo_path} alt="" className="home-inf-photo"
                    fallback={<span className="home-inf-initial">{Array.from(p.nickname ?? '?')[0]}</span>}
                  />
                </span>
                <span className="home-inf-name" aria-hidden="true">{p.nickname}</span>
              </Link>
            </li>
          ))}
        </ul>
        <Link to="/influencers" className="home-inf-item home-inf-all" aria-label="장인 전체 보기">
          <span className="home-inf-avatar home-inf-all-circle" aria-hidden="true"><ArrowRightIcon size={22} /></span>
          <span className="home-inf-name" aria-hidden="true">전체</span>
        </Link>
      </div>
    </section>
  );
}
