import { Link } from 'react-router-dom';
import { useRestriction } from '../lib/restriction';

/** 조건 숫자 기본값 — 실제 값은 DB xp_rules (member_page_min_builds · title_builder) */
export const MEMBER_PAGE_MIN_BUILDS = 5;
export const BUILDER_TITLE_BUILDS = 10;

/** 공개 빌드 = 빌드도 상대법도 공개 중 (DB member_page·빌드 설계자와 같은 기준, SPEC 6-108) */
export const publicBuildCount = (builds) => builds.filter((b) => b.status === 'approved' && b.counter?.status === 'approved').length;

/**
 * 마이페이지 진행 안내 (SPEC 6-111): 개인 페이지 공개(5개)와 칭호 「빌드 설계자」(10개)까지의 공개 빌드 수.
 * 수는 마이페이지가 이미 읽은 내 빌드 목록에서 센다(새 요청·새 DB 함수 없음).
 * - 개인 페이지 줄: 장인(장인 페이지가 따로 있음)·비회원·닉네임 없음에게는 없다. 활동 제한 중이면 페이지가 닫혀 있어 링크 대신 안내.
 * - 빌드 설계자 줄: 도감에 그 칭호가 있을 때만. 이미 받았으면(한 번 얻으면 유지) 빌드가 줄어도 「달성했습니다」.
 * 운영자 계정에는 부모가 그리지 않는다.
 */
export default function MyProgress({ auth, builds, book, rules = {} }) {
  const { restriction } = useRestriction(auth.user.id);
  const { profile } = auth;
  const count = publicBuildCount(builds);
  const pageMin = rules.member_page_min_builds ?? MEMBER_PAGE_MIN_BUILDS;
  const builderMin = rules.title_builder ?? BUILDER_TITLE_BUILDS;
  const builder = book.items.find((t) => t.key === 'builder');
  const showPage = !profile.influencer && !profile.is_guest && !!profile.nickname;
  if (!showPage && !builder) return null;

  const pageDone = count >= pageMin;
  const builderDone = !!builder?.owned || count >= builderMin;
  const line = (done, min, todo) => (done ? `공개 빌드 ${min}/${min} — 달성했습니다` : `공개 빌드 ${count}/${min} — ${todo}`);

  return (
    <section className="me-section me-card my-progress" aria-label="공개 빌드 진행 안내">
      <ul>
        {showPage && (
          <li>
            <span>{line(pageDone, pageMin, `${pageMin}개부터 내 개인 페이지가 공개됩니다`)}</span>
            {pageDone && (restriction
              ? <small className="muted">활동 제한 중에는 개인 페이지가 공개되지 않습니다.</small>
              : <Link to={`/u/${auth.user.id}`} className="btn btn-small">내 개인 페이지 보기</Link>)}
          </li>
        )}
        {builder && (
          <li>
            <span>{line(builderDone, builderMin, `${builderMin}개를 채우면 칭호 「${builder.name ?? '빌드 설계자'}」를 받습니다`)}</span>
          </li>
        )}
      </ul>
    </section>
  );
}
