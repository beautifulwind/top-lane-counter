import ExternalLink from './ExternalLink';

/**
 * 빌드에 단 영상 링크 (장인이 처음 만든 빌드 1개, 047·SPEC 6-45): "[유튜브] 관련 영상 보기".
 * 사이트 이름은 주소의 도메인으로 판별(ExternalLink → siteName). 새 창 + 이동 확인 창은 ExternalLink 그대로.
 */
export default function VideoLink({ link }) {
  return (
    <ExternalLink link={link} className="video-link">
      <span className="video-text">관련 영상 보기</span>
    </ExternalLink>
  );
}
