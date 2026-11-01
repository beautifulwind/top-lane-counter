import { titleName } from '../lib/titles';

/**
 * 닉네임 표시: "Lv.7 수석 연구원 · 탑신병자"
 * 대표 칭호가 없으면 칭호 자리를 아예 빼고 "Lv.3 탑신병자"
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
