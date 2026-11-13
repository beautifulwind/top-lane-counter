import { Link } from 'react-router-dom';
import { titleInfo, useTitleInfo } from '../lib/titles';
import { INFLUENCER_TIP, displayNickname } from '../lib/nickname';
import TitleMedal, { BUILTIN_TITLE, titleColorClass, titleColorStyle } from './TitleMedal';

/**
 * 칭호 배지 (022, 054): 테두리·색이 있는 작은 칸 — 사이트 이름 "탑신병자"와 구분된다.
 * 이름·그림·색은 앱이 켜질 때 한 번 읽은 칭호 정보(054 public_title_info)에서. 모르는 키·숨김 칭호는 배지를 그리지 않는다.
 * - 기존 6개 활동 칭호(그림·색 없음): 예전 그대로 글자 칸 + 칭호색(tokens.css)
 * - 그 밖(한정판 등): 높이 22px 칸에 작은 훈장 + 이름. icon이 있으면 그림 파일, 없으면 공통 훈장에 color
 * space: 배지 뒤에 띄어쓰기 한 칸 (배지가 없으면 띄어쓰기도 없음)
 */
export function TitleBadge({ titleKey, space = false }) {
  useTitleInfo();
  const item = titleInfo(titleKey);
  if (!item) return null;
  const tip = `칭호 '${item.name}'`;
  const plain = BUILTIN_TITLE(item) && !item.icon && !item.color;
  const badge = plain
    ? <span className={`title-badge ${item.key}`} title={tip}>{item.name}</span>
    : (
      <span className={['title-badge', 'title-badge-art', titleColorClass(item)].filter(Boolean).join(' ')} style={titleColorStyle(item)} title={tip}>
        <span className="title-badge-medal" aria-hidden="true"><TitleMedal item={item} box={[18, 18]} /></span>
        {item.name}
      </span>
    );
  return space ? <>{badge}{' '}</> : badge;
}

/**
 * 닉네임 글자 + 장인 표시 (046, SPEC 6-32). 닉네임 글자와 따로 그린 칸이라 닉네임에 "장인"을 넣어도 같은 모양이 되지 않는다.
 * - 장인(profile.influencer): 진홍 "장인" 글자 태그 + 닉네임을 진홍 둥근 실선으로 감싼다. 말풍선 "인증된 장인(…)"
 * - 인증 대기(nickname_state = 'pending'): 회색 점선 + ⏳ + "인증 대기"
 * - 닉네임 변경 예정(nickname_state = 'yielding'): 닉네임 뒤 회색 태그
 * 긴 닉네임(20자)도 폰에서 줄을 바꿔 넘치지 않는다 (index.css .inf-name·.nick-pending)
 */
export function InfluencerName({ profile, linkTo = null }) {
  const nick = <span className="user-nick">{displayNickname(profile)}</span>;
  if (profile?.influencer) {
    const inner = (
      <>
        <span className="inf-tag" aria-hidden="true">장인</span>
        <span className="sr-only">{INFLUENCER_TIP} </span>
        {nick}
      </>
    );
    // 047: 장인 공개 프로필로 가는 링크 (linkTo = 회원 id). 다른 링크 안에 있는 자리에서는 넘기지 않는다(링크 안의 링크 방지)
    if (linkTo) {
      return (
        <Link to={`/u/${linkTo}`} className="inf-name inf-link" title={`${INFLUENCER_TIP} — 프로필 보기`}>
          {inner}<span className="sr-only"> (프로필 보기)</span>
        </Link>
      );
    }
    return <span className="inf-name" title={INFLUENCER_TIP}>{inner}</span>;
  }
  if (profile?.nickname_state === 'pending') {
    return (
      <span className="nick-pending" title="장인 인증을 기다리는 닉네임">
        <span aria-hidden="true">{'⏳'}</span> {nick} <small className="nick-pending-tag">인증 대기</small>
      </span>
    );
  }
  if (profile?.nickname_state === 'yielding') {
    return <>{nick}{' '}<span className="nick-yield-tag" title="장인과 같은 닉네임이라 곧 바뀝니다">닉네임 변경 예정</span></>;
  }
  return nick;
}

/**
 * 닉네임 표시: "Lv.7 [단단묵직] 탑고수" (칭호는 배지)
 * 대표 칭호가 없으면 칭호 자리를 아예 빼고 "Lv.3 탑고수"
 * 비회원(020)은 닉네임 뒤에 "비회원" 표시
 * 운영자·감독관은 role을 보고 닉네임 앞에 똑같이 (운)을 붙인다: "Lv.0 (운)영자", "Lv.7 [칭호] (운)감독" (다른 역할 글자는 붙이지 않는다)
 * plain: 레벨·칭호를 빼고 닉네임(+ 장인 표시)만 — 빌드 작성자·기여자·수정 기록 (046)
 * linkTo: 회원 id를 주면 장인일 때만 닉네임이 공개 프로필(/u/:id) 링크가 된다 (047). 줄 전체가 이미 링크인 자리(회원 목록 등)에는 주지 않는다
 */
export default function UserName({ profile, plain = false, linkTo = null }) {
  return (
    <span className="user-name">
      {!plain && <><span className="user-lv">Lv.{profile.level}</span>{' '}</>}
      {!plain && <TitleBadge titleKey={profile.main_title} space />}
      <InfluencerName profile={profile} linkTo={linkTo} />
      {profile.is_guest && <>{' '}<span className="guest-badge">비회원</span></>}
    </span>
  );
}
