import { Link } from 'react-router-dom';
import ProfilePhoto from './ProfilePhoto';

/**
 * 장인 카드 한 줄 (장인 목록 /influencers와 팔로우한 장인 목록 /lists·/following이 같이 쓴다, SPEC 6-93·6-115).
 * [사진(없으면 첫 글자 원) · 닉네임 · 「인증」 · 작은 글씨 한 줄] 전체가 /u/:id 링크, 오른쪽에 children(팔로우 버튼 등 — 링크 밖이라 눌러도 이동하지 않음).
 * p = { id, nickname, photo_path?, build_count? }. kind = 장인 유형 이름(있으면 작은 글씨 맨 앞). followerCount = 지금 보여 줄 팔로워 수.
 * build_count가 없으면(079 전 DB의 my_following) 「빌드 N」을 빼고 보여 준다.
 */
export default function InfluencerRow({ p, kind = null, followerCount, children = null }) {
  const meta = [
    kind,
    p.build_count == null ? null : `빌드 ${Number(p.build_count).toLocaleString()}`,
    `팔로워 ${Number(followerCount ?? p.follower_count ?? 0).toLocaleString()}`,
  ].filter(Boolean).join(' · ');
  return (
    <li className="inf-row">
      <Link to={`/u/${p.id}`} className="inf-row-main">
        <span className="inf-row-avatar" aria-hidden="true">
          <ProfilePhoto
            path={p.photo_path} alt="" className="inf-row-photo"
            fallback={<span className="inf-row-initial">{Array.from(p.nickname ?? '?')[0]}</span>}
          />
        </span>
        <span className="inf-row-text">
          <span className="inf-row-name">
            <span className="user-nick">{p.nickname}</span>
            <span className="inf-tag">인증</span>
          </span>
          <small className="muted">{meta}</small>
        </span>
      </Link>
      {children && <div className="inf-row-follow">{children}</div>}
    </li>
  );
}
