import { titleName } from '../lib/titles';
import { INFLUENCER_TIP, displayNickname } from '../lib/nickname';

/** 칭호 배지 (022): 테두리·색이 있는 작은 칸 — 사이트 이름 "탑신병자"와 구분된다. 색은 칭호마다 다르다 (tokens.css) */
export function TitleBadge({ titleKey }) {
  const name = titleName(titleKey);
  if (!name) return null;
  return <span className={`title-badge ${titleKey}`} title={`칭호 '${name}'`}>{name}</span>;
}

/**
 * 닉네임 글자 + 장인 표시 (046, SPEC 6-32). 닉네임 글자와 따로 그린 칸이라 닉네임에 "장인"을 넣어도 같은 모양이 되지 않는다.
 * - 장인(profile.influencer): 진홍 "장인" 글자 태그 + 닉네임을 진홍 둥근 실선으로 감싼다. 말풍선 "인증된 장인(…)"
 * - 인증 대기(nickname_state = 'pending'): 회색 점선 + ⏳ + "인증 대기"
 * - 닉네임 변경 예정(nickname_state = 'yielding'): 닉네임 뒤 회색 태그
 * 긴 닉네임(20자)도 폰에서 줄을 바꿔 넘치지 않는다 (index.css .inf-name·.nick-pending)
 */
export function InfluencerName({ profile }) {
  const nick = <span className="user-nick">{displayNickname(profile)}</span>;
  if (profile?.influencer) {
    return (
      <span className="inf-name" title={INFLUENCER_TIP}>
        <span className="inf-tag" aria-hidden="true">장인</span>
        <span className="sr-only">{INFLUENCER_TIP} </span>
        {nick}
      </span>
    );
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
 */
export default function UserName({ profile, plain = false }) {
  const hasTitle = !plain && !!titleName(profile.main_title);
  return (
    <span className="user-name">
      {!plain && <><span className="user-lv">Lv.{profile.level}</span>{' '}</>}
      {hasTitle && <><TitleBadge titleKey={profile.main_title} />{' '}</>}
      <InfluencerName profile={profile} />
      {profile.is_guest && <>{' '}<span className="guest-badge">비회원</span></>}
    </span>
  );
}
