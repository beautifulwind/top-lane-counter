import { titleName } from '../lib/titles';

/**
 * 닉네임 표시: "Lv.7 수석 연구원 · 탑신병자"
 * 대표 칭호가 없으면 칭호 자리를 아예 빼고 "Lv.3 탑신병자"
 * 운영자는 DB에서 항상 Lv.0 · 칭호 없음이라 "Lv.0 영자(운)" (역할 글자는 붙이지 않는다)
 */
export default function UserName({ profile }) {
  const title = titleName(profile.main_title);
  return (
    <span className="user-name">
      <span className="user-lv">Lv.{profile.level}</span>{' '}
      {title && (
        <>
          <span className="user-title">{title}</span>{' · '}
        </>
      )}
      <span className="user-nick">{profile.nickname}</span>
    </span>
  );
}
