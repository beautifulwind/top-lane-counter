import { titleName } from '../lib/titles';
import { displayNickname } from '../lib/nickname';

/** 칭호 배지 (022): 테두리·색이 있는 작은 칸 — 사이트 이름 "탑신병자"와 구분된다. 색은 칭호마다 다르다 (tokens.css) */
export function TitleBadge({ titleKey }) {
  const name = titleName(titleKey);
  if (!name) return null;
  return <span className={`title-badge ${titleKey}`} title={`칭호 '${name}'`}>{name}</span>;
}

/**
 * 닉네임 표시: "Lv.7 [단단묵직] 탑고수" (칭호는 배지)
 * 대표 칭호가 없으면 칭호 자리를 아예 빼고 "Lv.3 탑고수"
 * 비회원(020)은 닉네임 뒤에 "비회원" 표시
 * 운영자·감독관은 role을 보고 닉네임 앞에 똑같이 (운)을 붙인다: "Lv.0 (운)영자", "Lv.7 [칭호] (운)감독" (다른 역할 글자는 붙이지 않는다)
 */
export default function UserName({ profile }) {
  const hasTitle = !!titleName(profile.main_title);
  return (
    <span className="user-name">
      <span className="user-lv">Lv.{profile.level}</span>{' '}
      {hasTitle && <><TitleBadge titleKey={profile.main_title} />{' '}</>}
      <span className="user-nick">{displayNickname(profile)}</span>
      {profile.is_guest && <>{' '}<span className="guest-badge">비회원</span></>}
    </span>
  );
}
