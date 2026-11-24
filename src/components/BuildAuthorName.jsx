import { WITHDRAWN_USER } from '../lib/nickname';
import UserName from './UserName';
import ProfilePhoto from './ProfilePhoto';

/**
 * 빌드 작성자 닉네임 표시 — 빌드가 나오는 모든 곳의 공용 칸 (SPEC 6-97).
 * 상대법 빌드 카드·운영자 화면(BuildAuthor)·장인 빌드 카드(/following)·전체 빌드 목록 카드(/builds)가 모두 이것을 쓴다.
 * - author가 없으면 탈퇴한 이용자. 닉네임은 레벨·칭호 없이 닉네임(+ 장인 표시)만 (plain, 046)
 * - rating: 닉네임 옆 별점 자리. 별점 데이터가 아직 없어 지금은 아무 데서도 넘기지 않으며(null) 넘기면 그때 처음 그려진다. 없을 때는 자리도 차지하지 않는다
 * - photo: 장인이면 닉네임 앞에 작은 프로필 사진 동그라미 (사진이 없으면 닉네임 첫 글자 원). 장인이 아니면 사진 칸 없음
 * - linkTo: 장인일 때만 /u/:id 링크 (다른 링크 안에 있는 카드에서는 주지 않는다)
 * 좁은 화면(380px)에서는 닉네임이 줄을 바꾸고, 사진·별점 칸은 줄지 않는다.
 */
export default function BuildAuthorName({ author, linkTo = null, photo = false, rating = null }) {
  if (!author) return <span className="build-author-name">{WITHDRAWN_USER}</span>;
  const showPhoto = photo && !!author.influencer;
  return (
    <span className="build-author-name">
      {showPhoto && (
        <span className="author-avatar" aria-hidden="true">
          <ProfilePhoto
            path={author.photo_path ?? null} alt="" className="author-photo"
            fallback={<span className="author-initial">{Array.from(author.nickname ?? '?')[0]}</span>}
          />
        </span>
      )}
      <UserName profile={author} plain linkTo={linkTo} />
      {rating != null && <span className="author-rating">{rating}</span>}
    </span>
  );
}
