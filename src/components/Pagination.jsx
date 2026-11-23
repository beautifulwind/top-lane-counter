import { useEffect, useRef, useState } from 'react';
import { useSearchParams } from 'react-router-dom';

/** 빌드 목록 한 쪽 개수 (전체 빌드 /builds·저장한 빌드 /lists, SPEC 6-87) */
export const BUILD_PAGE_SIZE = 20;

/** 폰 폭(이하)에서는 번호를 줄여 한 줄에 넣는다: 이전 · 1 … 5 … 12 · 다음 (누르는 칸 44px 유지) */
const COMPACT_QUERY = '(max-width: 480px)';

/** 주소의 ?page= → 1~pages로 맞춘 쪽 번호 (없거나 이상하면 1, 너무 크면 마지막 쪽) */
export function clampPage(raw, pages) {
  const n = Number.parseInt(raw ?? '', 10);
  return Number.isFinite(n) && n >= 1 ? Math.min(n, Math.max(1, pages)) : 1;
}

/**
 * 쪽 번호 줄: [{ kind: 'page', n } | { kind: 'gap', key }].
 * 넓은 화면: 처음·끝·지금 쪽과 앞뒤 한 쪽 (예: 1 … 4 5 6 … 12, 사이가 한 쪽뿐이면 점 대신 그 번호).
 * compact(폰): 처음·지금·끝만 (예: 1 … 5 … 12). 4쪽 이하면 둘 다 전부 보인다. 쪽이 하나면 빈 목록.
 */
export function pageItems(page, pages, compact = false) {
  if (pages <= 1) return [];
  if (pages <= (compact ? 4 : 7)) return Array.from({ length: pages }, (_, i) => ({ kind: 'page', n: i + 1 }));
  const keep = new Set([1, pages, page]);
  if (!compact) { keep.add(page - 1); keep.add(page + 1); }
  const sorted = [...keep].filter((n) => n >= 1 && n <= pages).sort((a, b) => a - b);
  const out = [];
  let prev = 0;
  sorted.forEach((n) => {
    if (prev && n - prev === 2 && !compact) out.push({ kind: 'page', n: prev + 1 });
    else if (prev && n - prev > 1) out.push({ kind: 'gap', key: `gap-${prev}` });
    out.push({ kind: 'page', n });
    prev = n;
  });
  return out;
}

function useCompact() {
  const get = () => (typeof window !== 'undefined' && typeof window.matchMedia === 'function' ? window.matchMedia(COMPACT_QUERY).matches : false);
  const [compact, setCompact] = useState(get);
  useEffect(() => {
    if (typeof window === 'undefined' || typeof window.matchMedia !== 'function') return undefined;
    const mq = window.matchMedia(COMPACT_QUERY);
    const on = () => setCompact(mq.matches);
    on();
    mq.addEventListener?.('change', on);
    return () => mq.removeEventListener?.('change', on);
  }, []);
  return compact;
}

/**
 * 쪽 나누기 상태 (SPEC 6-87): 쪽 번호는 주소 ?page=에 남아(1쪽이면 주소에 없음) 상대법에 갔다 뒤로 와도 같은 쪽이다.
 * go(n): 쪽을 바꾸면 목록 맨 위로 스크롤하고 새 쪽의 첫 줄로 초점(스크린리더). 주소 기록은 쌓지 않는다(replace).
 * 쓰는 곳: const pg = usePaging(visible.length); visible.slice(pg.start, pg.end) + <ul ref={pg.listRef}> + <Pagination {...pg} />
 */
export function usePaging(total, size = BUILD_PAGE_SIZE) {
  const [params, setParams] = useSearchParams();
  const pages = Math.max(1, Math.ceil(total / size));
  const page = clampPage(params.get('page'), pages);
  const listRef = useRef(null);
  const moved = useRef(false);

  useEffect(() => {
    if (!moved.current) return;
    moved.current = false;
    const list = listRef.current;
    list?.scrollIntoView?.({ block: 'start' });
    list?.querySelector('li a')?.focus({ preventScroll: true });
  });

  const go = (n) => {
    const next = new URLSearchParams(params);
    if (n <= 1) next.delete('page');
    else next.set('page', String(n));
    next.delete('n'); // 예전 [더보기] 주소의 찌꺼기
    moved.current = true;
    setParams(next, { replace: true });
  };
  return { page, pages, start: (page - 1) * size, end: page * size, go, listRef };
}

/**
 * 이전 · 1 2 3 … · 다음. 지금 쪽은 aria-current="page". 처음·끝에서는 이전·다음이 흐려진다(자리는 그대로).
 * 모든 칸이 44px 이상. 쪽이 하나뿐이면 아무것도 그리지 않는다.
 */
export default function Pagination({ page, pages, go }) {
  const compact = useCompact();
  if (pages <= 1) return null;
  const items = pageItems(page, pages, compact);
  return (
    <nav className="pagination" aria-label="쪽 이동">
      <ul>
        <li>
          <button type="button" className="pg-btn pg-step" onClick={() => go(page - 1)} disabled={page <= 1} aria-label="이전 쪽">
            <span aria-hidden="true">{compact ? '‹' : '이전'}</span>
          </button>
        </li>
        {items.map((it) => (it.kind === 'gap' ? (
          <li key={it.key} className="pg-gap" aria-hidden="true">…</li>
        ) : (
          <li key={it.n}>
            <button
              type="button" className={it.n === page ? 'pg-btn on' : 'pg-btn'} onClick={() => go(it.n)}
              aria-current={it.n === page ? 'page' : undefined} aria-label={`${it.n}쪽`}
            >
              {it.n}
            </button>
          </li>
        )))}
        <li>
          <button type="button" className="pg-btn pg-step" onClick={() => go(page + 1)} disabled={page >= pages} aria-label="다음 쪽">
            <span aria-hidden="true">{compact ? '›' : '다음'}</span>
          </button>
        </li>
      </ul>
    </nav>
  );
}
