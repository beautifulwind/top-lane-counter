import { getMemberPage } from '../api/links';
import { useAsync } from '../lib/useAsync';
import { useBuildDifficulties } from '../lib/useBuildDifficulties';
import InfluencerBuildCard from './InfluencerBuildCard';
import Pagination, { usePaging } from './Pagination';
import ProfilePhoto from './ProfilePhoto';
import SectionHead from './SectionHead';
import { ErrorBox, Loading } from './Status';
import { TitleBadge } from './UserName';
import { LayersIcon, SparklesIcon, UserIcon } from './Icons';
import { useTitleInfo } from '../lib/titles';

/**
 * 일반 사용자 개인 페이지 (/u/:id — 장인이 아닌 사람, 075 member_page, SPEC 6-111). 장인 페이지와 같은 틀:
 * 위 카드 = 사진 자리(사진이 없으면 기본 아바타) · [대표 칭호] 닉네임 · 「빌드 N」, 아래 「받은 칭호」와 공개 빌드 목록(최근 수정순, 20개씩 ?page=).
 * 인증 배지·유튜브·링크·팔로우·팔로워는 없다. 누구에게 열리는지(공개 빌드 5개 이상 등)는 DB가 정한다.
 * first = member_page 1쪽 응답.
 */
export default function MemberProfile({ first, champs }) {
  const { member } = first;
  const total = Number(first.total) || 0;
  const pg = usePaging(total);
  const direct = pg.page === 1; // 1쪽은 이미 받아 둔 것
  const { data: fetched, error, loading: waiting, retry } = useAsync(async () => {
    const r = await getMemberPage(member.id, pg.page);
    if (!r) throw new Error('지금은 빌드를 불러올 수 없습니다.'); // 그 사이 닫힌 페이지 — 이유는 말하지 않는다
    return r.items;
  }, [member.id, pg.page], { enabled: !direct });
  const loading = !direct && waiting;
  const shown = direct ? first.items : (loading || error ? [] : fetched ?? []);
  const ratings = useBuildDifficulties(shown.map((b) => b.id));
  useTitleInfo(); // 받은 칭호의 이름·그림

  return (
    <article className="me-page public-profile member-profile">
      <header className="me-hero inf-hero">
        <p className="me-hero-label">개인 페이지</p>
        <div className="inf-hero-name">
          <ProfilePhoto
            path={member.photo_path} alt={`${member.nickname} 프로필 사진`} className="inf-hero-photo"
            fallback={<span className="inf-hero-avatar" aria-hidden="true"><UserIcon size={28} /></span>}
          />
          <h1 className="doc-title" data-page-title={`${member.nickname} 프로필`}>
            <TitleBadge titleKey={member.main_title} space />
            <span className="user-nick">{member.nickname}</span>
          </h1>
        </div>
        <p className="doc-sub inf-meta">
          <span>빌드 <strong className="build-total">{total.toLocaleString()}</strong></span>
        </p>
      </header>

      <section className="me-section" aria-labelledby="pp-titles">
        <SectionHead icon={SparklesIcon} id="pp-titles">받은 칭호</SectionHead>
        {member.titles?.length ? (
          <ul className="member-titles" aria-label="받은 칭호 목록">
            {member.titles.map((key) => <li key={key}><TitleBadge titleKey={key} /></li>)}
          </ul>
        ) : (
          <p className="empty">받은 칭호가 없습니다.</p>
        )}
      </section>

      <section className="me-section" aria-labelledby="pp-builds">
        <SectionHead icon={LayersIcon} id="pp-builds" count={total}>공개 빌드</SectionHead>
        {loading && <Loading />}
        {!direct && error && <ErrorBox error={error} onRetry={retry} />}
        {shown.length > 0 && (
          <ul className="build-cards" ref={pg.listRef} aria-label="빌드 목록">
            {shown.map((b) => <InfluencerBuildCard key={b.id} b={{ ...b, link: null, difficulty: ratings[b.id] ?? null }} champs={champs} />)}
          </ul>
        )}
        <Pagination {...pg} />
      </section>
    </article>
  );
}
