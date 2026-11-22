import { useEffect, useRef } from 'react';
import { useSearchParams } from 'react-router-dom';
import { getAllPublicBuilds } from '../api/allBuilds';
import { getChampionMap } from '../api/ddragon';
import { isBlocked, useAuth } from '../lib/auth';
import { useAsync } from '../lib/useAsync';
import { ErrorBox, Loading } from '../components/Status';
import BuildRow, { BUILD_ROWS_STEP, shownCount } from '../components/BuildRow';
import { LayersIcon } from '../components/Icons';

/** 한 번에 더 보이는 개수 */
export const ALL_BUILDS_STEP = BUILD_ROWS_STEP;

/**
 * 전체 빌드 목록 /builds (SPEC 6-81) — 첫 화면 "지금까지 N개의 빌드" 배지를 누르면 온다. 누구나(비로그인·닉네임 없음도) 본다.
 * 정렬: 장인 빌드 먼저 → 추천 많은 순 → 같으면 최신순 (compareAllBuilds). 20개씩 [더보기] — 펼친 개수는 주소(?n=40)에 남겨
 * 상대법에 갔다가 뒤로 와도 그대로. 내가 차단한 사람의 빌드는 숨기고(061) 몇 개 숨겼는지 알려 준다.
 * 줄 = 챔피언 아이콘 2개 + "내 챔피언 vs 상대" + 빌드 이름(장인 빌드 뱃지) + 선마 + 추천 수, 누르면 그 상대법의 그 빌드로.
 */
export default function AllBuilds() {
  const auth = useAuth();
  const [params, setParams] = useSearchParams();
  const n = shownCount(params.get('n'));
  const { data, error, loading, retry } = useAsync(async () => {
    const [rows, champs] = await Promise.all([getAllPublicBuilds(), getChampionMap().catch(() => ({}))]);
    return { rows, champs };
  }, []);
  const listRef = useRef(null);
  const focusFrom = useRef(null); // [더보기] 뒤 새로 보인 첫 줄로 초점

  useEffect(() => {
    if (focusFrom.current == null) return;
    const link = listRef.current?.querySelectorAll('li > a')[focusFrom.current];
    focusFrom.current = null;
    link?.focus();
  });

  if (loading && !data) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;

  const visible = data.rows.filter((b) => !isBlocked(auth, b.author_id));
  const hidden = data.rows.length - visible.length;
  const shown = visible.slice(0, n);
  const more = () => {
    focusFrom.current = shown.length;
    const next = new URLSearchParams(params);
    next.set('n', String(n + ALL_BUILDS_STEP));
    setParams(next, { replace: true });
  };

  return (
    <article>
      <h1 className="doc-title page-title"><LayersIcon size={26} className="title-icon" /> 전체 빌드</h1>
      <p className="lead">
        공개된 빌드 {data.rows.length.toLocaleString('ko-KR')}개 · 장인 빌드가 먼저, 그다음 추천 많은 순(같으면 최신순)입니다.
        누르면 그 상대법으로 갑니다.
      </p>
      {hidden > 0 && <p className="hint" role="note">{`차단한 사용자의 빌드 ${hidden}개는 숨겼습니다.`}</p>}

      {visible.length === 0 ? (
        <p className="empty">{data.rows.length === 0 ? '아직 공개된 빌드가 없습니다.' : '보여 줄 빌드가 없습니다.'}</p>
      ) : (
        <ul className="profile-builds inf-build-list all-builds" ref={listRef}>
          {shown.map((b) => <BuildRow key={b.id} b={b} champs={data.champs} />)}
        </ul>
      )}

      {shown.length < visible.length && (
        <div className="actions">
          <button type="button" className="btn" onClick={more}>
            {`더보기 (${shown.length}/${visible.length})`}
          </button>
        </div>
      )}
    </article>
  );
}
