import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { getChampions } from '../api/ddragon';
import {
  MY_CHAMPION_LIMIT, MY_CHAMPION_LIMIT_TEXT, getMyChampionBuilds, getMyChampions, setMyChampion,
} from '../api/myChampions';
import { isBlocked, useAuth } from '../lib/auth';
import { rankChampions, tokenize } from '../lib/championSearch';
import { useAsync } from '../lib/useAsync';
import { useBuildDifficulties } from '../lib/useBuildDifficulties';
import Pagination, { clampPage, usePaging } from './Pagination';
import BuildRow from './BuildRow';
import SearchField from './SearchField';
import { ChampIcon } from './InfluencerBuildCard';
import { ErrorBox, Loading } from './Status';

export const NO_MY_CHAMPION_TEXT = '내가 하는 챔피언을 검색해서 선택하면, 그 챔피언의 빌드를 한곳에서 볼 수 있습니다.';
export const NO_MY_CHAMPION_BUILDS_TEXT = '선택한 챔피언의 공개 빌드가 아직 없습니다. 새 빌드가 올라오면 여기에 모입니다.';
/** 검색 결과 줄 수 (넘으면 더 좁혀 달라는 안내) */
const RESULT_ROWS = 8;

/**
 * 「내 챔피언」 탭 (080, SPEC 6-116) — 내 목록(/lists?tab=champions)과 팔로우 모아보기(/following?tab=champions)가 같이 쓴다.
 * - 위: 검색창 하나. 입력하면 아래에 줄 단위 결과(작은 챔피언 아이콘 + 이름 + 오른쪽 「선택」/「선택됨」). 줄을 누르면 선택, 「선택됨」을 다시 누르면 해제.
 *   검색은 메인 검색과 같은 규칙(tokenize + rankChampions: 한글 이름·초성·영문 id·별명, 띄어쓰기 단어 AND).
 * - 가운데: 선택한 챔피언 이름 칩 한 줄(새로 고른 것이 맨 앞, 넘치면 옆으로 밀기 — 스크롤바 숨김, 오른쪽 끝 흐림).
 *   칩을 누르면 그 챔피언의 빌드만(?champ=), 한 번 더 누르면 전체. 칩의 ×는 해제.
 * - 10개를 고른 뒤 또 고르면 버튼은 그대로 두고 누를 때 안내(MY_CHAMPION_LIMIT_TEXT). 서버도 10개를 지킨다(TL413 → 같은 안내).
 * - 아래: 빌드 목록 = 저장한 빌드·전체 빌드와 같은 BuildRow 카드, 20개씩 쪽 번호(?page=). 순서는 서버(/builds 추천순).
 *   차단한 사람의 빌드는 서버가 빼고 개수를 알려 준다. 별점은 보이는 쪽의 id로 build_difficulties(기존 방식).
 * 080 전 DB면 「준비 중」 안내만. 비회원(게스트)도 쓸 수 있다(비로그인은 바깥 화면이 로그인 안내).
 */
export default function MyChampions({ userId }) {
  const champions = useAsync(getChampions, []);
  const list = useAsync(getMyChampions, [userId]);
  const [picked, setPicked] = useState({ base: null, items: [] }); // 이 화면에서 바꾼 목록 (처음 받은 목록이 바뀌면 다시)
  const items = picked.base === list.data ? picked.items : (list.data?.items ?? []);
  const setItems = (next) => setPicked({ base: list.data, items: next });
  const [query, setQuery] = useState('');
  const [busy, setBusy] = useState(null); // 처리 중인 챔피언 id
  const [note, setNote] = useState(null); // { kind: 'limit' | 'error', text }
  const [version, setVersion] = useState(0); // 등록이 바뀌면 빌드 목록을 다시
  const [params, setParams] = useSearchParams();
  const filter = items.includes(params.get('champ')) ? params.get('champ') : null;

  const byId = useMemo(() => Object.fromEntries((champions.data ?? []).map((c) => [c.id, c])), [champions.data]);
  const nameOf = (id) => byId[id]?.name ?? id;
  const tokens = useMemo(() => tokenize(query), [query]);
  const found = useMemo(() => rankChampions(tokens, champions.data ?? []), [tokens, champions.data]);

  const setFilter = (id) => {
    setNote(null);
    const next = new URLSearchParams(params);
    next.delete('page'); // 칩을 바꾸면 1쪽으로
    if (id) next.set('champ', id);
    else next.delete('champ');
    setParams(next, { replace: true });
  };

  const toggle = async (id) => {
    if (busy) return;
    const selected = items.includes(id);
    if (!selected && items.length >= MY_CHAMPION_LIMIT) {
      setNote({ kind: 'limit', text: MY_CHAMPION_LIMIT_TEXT });
      return;
    }
    setBusy(id);
    setNote(null);
    try {
      await setMyChampion(id, !selected);
      setItems(selected ? items.filter((x) => x !== id) : [id, ...items]);
      if (selected && filter === id) setFilter(null);
      setVersion((v) => v + 1);
    } catch (e) {
      setNote({ kind: e.limit ? 'limit' : 'error', text: e.message });
    } finally {
      setBusy(null);
    }
  };

  if (list.loading && !list.data) return <Loading />;
  if (list.error) {
    if (list.error.missing) return <p className="notice" role="status">{list.error.message}</p>;
    return <ErrorBox error={list.error} onRetry={list.retry} />;
  }

  return (
    <section aria-label="내 챔피언" className="my-champs">
      <SearchField
        value={query} onChange={setQuery} label="내 챔피언 검색" placeholder="챔피언 이름·초성으로 검색" maxLength={40}
        className="my-champs-search"
      />
      {tokens.length > 0 && (champions.error ? (
        <p className="form-error" role="alert">챔피언 목록을 불러오지 못했습니다. 잠시 뒤 다시 시도해 주세요.</p>
      ) : !champions.data ? (
        <Loading />
      ) : found.length === 0 ? (
        <p className="status">{`‘${query.trim()}’에 맞는 챔피언이 없습니다.`}</p>
      ) : (
        <>
          <ul className="mc-results" aria-label="검색 결과">
            {found.slice(0, RESULT_ROWS).map((c) => {
              const on = items.includes(c.id);
              return (
                <li key={c.id}>
                  <button
                    type="button" className={on ? 'mc-result on' : 'mc-result'} aria-pressed={on}
                    aria-label={`${c.name} ${on ? '선택됨' : '선택'}`} disabled={busy === c.id} onClick={() => toggle(c.id)}
                    data-write={!on || undefined} /* 068·081: 등록은 막고 해제는 그대로 */
                  >
                    <ChampIcon champ={c} />
                    <span className="mc-result-name">{c.name}</span>
                    <span className="mc-result-state" aria-hidden="true">{on ? '선택됨' : '선택'}</span>
                  </button>
                </li>
              );
            })}
          </ul>
          {found.length > RESULT_ROWS && <p className="hint">{`${found.length - RESULT_ROWS}개 더 있습니다. 이름을 조금 더 입력해 주세요.`}</p>}
        </>
      ))}
      {note && <p className={note.kind === 'limit' ? 'notice mc-note' : 'form-error mc-note'} role="alert">{note.text}</p>}

      {items.length === 0 ? (
        <p className="empty">{NO_MY_CHAMPION_TEXT}</p>
      ) : (
        <>
          <ChipRow items={items} nameOf={nameOf} filter={filter} busy={busy} onPick={(id) => setFilter(filter === id ? null : id)} onRemove={toggle} />
          <ChampionBuilds key={version} champion={filter} championName={filter ? nameOf(filter) : null} count={items.length} champs={byId} />
        </>
      )}
    </section>
  );
}

/** 선택한 챔피언 칩 한 줄: 넘치면 옆으로 밀고(스크롤바 숨김), 더 밀 수 있으면 오른쪽 끝을 흐리게 */
function ChipRow({ items, nameOf, filter, busy, onPick, onRemove }) {
  const ref = useRef(null);
  const [more, setMore] = useState(false);
  useLayoutEffect(() => {
    const el = ref.current;
    if (!el) return undefined;
    const read = () => setMore(el.scrollWidth - el.clientWidth - el.scrollLeft > 2);
    read();
    el.addEventListener('scroll', read, { passive: true });
    let ro = null;
    if (typeof ResizeObserver === 'function') { ro = new ResizeObserver(read); ro.observe(el); }
    return () => { el.removeEventListener('scroll', read); ro?.disconnect(); };
  }, [items.length]);
  useEffect(() => { ref.current?.scrollTo?.({ left: 0 }); }, [items[0]]); // eslint-disable-line react-hooks/exhaustive-deps -- 새로 고른 챔피언(맨 앞)이 보이게

  return (
    <div className={more ? 'mc-chips-wrap more' : 'mc-chips-wrap'}>
      <ul className="mc-chips" ref={ref} aria-label={`내 챔피언 ${items.length}개 (최대 ${MY_CHAMPION_LIMIT}개) · 누르면 그 챔피언의 빌드만`}>
        {items.map((id) => {
          const on = filter === id;
          const name = nameOf(id);
          return (
            <li key={id} className={on ? 'mc-chip on' : 'mc-chip'}>
              <button type="button" className="mc-chip-name" aria-pressed={on} onClick={() => onPick(id)}>{name}</button>
              <button type="button" className="mc-chip-x" aria-label={`${name} 해제`} disabled={busy === id} onClick={() => onRemove(id)}>
                <span aria-hidden="true">×</span>
              </button>
            </li>
          );
        })}
      </ul>
    </div>
  );
}

/** 내 챔피언의 공개 빌드 (서버가 20개씩 나눠 준다 — 쪽은 주소 ?page=) */
function ChampionBuilds({ champion, championName, count, champs }) {
  const auth = useAuth();
  const [params] = useSearchParams();
  const [known, setKnown] = useState(null); // 마지막으로 받은 total (쪽 수 계산용 — 새 쪽을 받는 동안에도 쪽 번호 줄이 흔들리지 않게)
  const pg = usePaging(known ?? 0);
  // 처음(개수를 모를 때)은 주소의 쪽을 그대로 묻고, 개수를 안 뒤에는 그 안으로 맞춘 쪽
  const page = known == null ? clampPage(params.get('page'), Number.MAX_SAFE_INTEGER) : pg.page;
  const { data, error, loading, retry } = useAsync(() => getMyChampionBuilds({ champion, page }), [champion, page]);
  useEffect(() => { if (data) setKnown(data.total); }, [data]);
  const visible = (data?.items ?? []).filter((b) => !isBlocked(auth, b.author_id)); // 방금 차단한 사람도 바로 숨김 (서버는 다음에 받을 때 뺀다)
  const ratings = useBuildDifficulties(visible.map((b) => b.id));

  if (loading && !data) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  const blocked = data.blocked + (data.items.length - visible.length);

  return (
    <div className="mc-builds">
      {data.total > 0 && (
        <p className="hint">
          {champion
            ? `${championName} 빌드 ${data.total.toLocaleString('ko-KR')}개 · 장인 빌드 먼저, 추천 많은 순서입니다.`
            : `내 챔피언 ${count}개의 빌드 ${data.total.toLocaleString('ko-KR')}개 · 장인 빌드 먼저, 추천 많은 순서입니다.`}
        </p>
      )}
      {blocked > 0 && <p className="hint" role="note">{`차단한 사용자의 빌드 ${blocked}개는 숨겼습니다.`}</p>}
      {visible.length === 0 ? (
        <p className="empty">
          {data.total > 0 ? '보여 줄 빌드가 없습니다.'
            : champion ? `${championName}의 공개 빌드가 아직 없습니다.` : NO_MY_CHAMPION_BUILDS_TEXT}
        </p>
      ) : (
        <ul className="build-cards all-builds my-champ-builds" ref={pg.listRef} aria-label={champion ? `${championName} 빌드` : '내 챔피언 빌드'}>
          {visible.map((b) => <BuildRow key={b.id} b={{ ...b, difficulty: ratings[b.id] ?? null }} champs={champs} />)}
        </ul>
      )}
      <Pagination {...pg} />
    </div>
  );
}
