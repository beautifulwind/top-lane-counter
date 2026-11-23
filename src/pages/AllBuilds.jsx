import { getAllPublicBuilds } from '../api/allBuilds';
import { getChampionMap } from '../api/ddragon';
import { isBlocked, useAuth } from '../lib/auth';
import { useAsync } from '../lib/useAsync';
import { ErrorBox, Loading } from '../components/Status';
import BuildRow from '../components/BuildRow';
import Pagination, { usePaging } from '../components/Pagination';
import { LayersIcon } from '../components/Icons';

/**
 * 전체 빌드 목록 /builds (SPEC 6-81) — 첫 화면 "지금까지 N개의 빌드" 배지를 누르면 온다. 누구나(비로그인·닉네임 없음도) 본다.
 * 정렬: 장인 빌드 먼저 → 추천 많은 순 → 같으면 최신순 (compareAllBuilds). 20개씩 쪽 번호(이전 · 1 2 3 … · 다음, 6-87) — 쪽은 주소(?page=2)에 남겨
 * 상대법에 갔다가 뒤로 와도 그대로. 내가 차단한 사람의 빌드는 숨기고(061) 몇 개 숨겼는지 알려 준다.
 * 줄 = 왼쪽 강조선 카드(장인 빌드 주황·일반 회색): 챔피언 아이콘 2개 + "내 챔피언 vs 상대" + 빌드 이름(장인 빌드 뱃지) + 선마 + 추천 수, 누르면 그 상대법의 그 빌드로.
 * 제목 아래 안내 문장은 없다(6-87) — 스크린리더용 이름은 목록의 aria-label.
 */
export default function AllBuilds() {
  const auth = useAuth();
  const { data, error, loading, retry } = useAsync(async () => {
    const [rows, champs] = await Promise.all([getAllPublicBuilds(), getChampionMap().catch(() => ({}))]);
    return { rows, champs };
  }, []);
  const visible = (data?.rows ?? []).filter((b) => !isBlocked(auth, b.author_id));
  const pg = usePaging(visible.length);

  if (loading && !data) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;

  const hidden = data.rows.length - visible.length;
  const shown = visible.slice(pg.start, pg.end);

  return (
    <article>
      <h1 className="doc-title page-title"><LayersIcon size={26} className="title-icon" /> 전체 빌드</h1>
      {hidden > 0 && <p className="hint" role="note">{`차단한 사용자의 빌드 ${hidden}개는 숨겼습니다.`}</p>}

      {visible.length === 0 ? (
        <p className="empty">{data.rows.length === 0 ? '아직 공개된 빌드가 없습니다.' : '보여 줄 빌드가 없습니다.'}</p>
      ) : (
        <ul className="build-cards all-builds" ref={pg.listRef} aria-label={`공개된 빌드 ${data.rows.length.toLocaleString('ko-KR')}개`}>
          {shown.map((b) => <BuildRow key={b.id} b={b} champs={data.champs} />)}
        </ul>
      )}

      <Pagination {...pg} />
    </article>
  );
}
