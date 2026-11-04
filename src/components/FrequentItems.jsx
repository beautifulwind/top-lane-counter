import { useState } from 'react';
import { getItems } from '../api/ddragon';
import { getStartGoldMax } from '../api/builds';
import { FREQUENT_SLOTS, addFrequentItem, getFrequentItems, removeFrequentItem } from '../api/items';
import { matchesQuery } from '../lib/chosung';
import { isCoreItem } from '../lib/itemKinds';
import { useAsync } from '../lib/useAsync';
import { Icon } from './BuildCard';
import { ErrorBox, Loading } from './Status';

/**
 * 운영자: 자주 쓰는 아이템 (028). 빌드 입력의 아이템 고르기에서 처음에 보이는 아이템 — 나머지는 [더보기].
 * [핵심 템트리] / [시작 아이템] 칸을 바꿔 가며 추가·빼기 (비주류 픽 칸과 같은 모양, 보라 버튼).
 * 넣을 수 있는 것: 핵심 템트리는 전설·서사·신발, 시작 아이템은 상점 아이템 중 시작템 골드 상한 이하 (DB가 다시 확인).
 */
export default function FrequentItems() {
  const { data, error, loading, retry } = useAsync(async () => {
    const [items, frequent, goldMax] = await Promise.all([getItems(), getFrequentItems(), getStartGoldMax()]);
    return { items, frequent, goldMax };
  }, []);
  const [slot, setSlot] = useState('core');
  const [query, setQuery] = useState('');
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState(null);
  const [fail, setFail] = useState(null);

  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  const { items, frequent, goldMax } = data;
  const list = frequent[slot];
  const allowed = (it) => it.shop && (slot === 'core' ? isCoreItem(it) : it.gold <= goldMax);
  const results = query.trim()
    ? Object.values(items).filter((it) => allowed(it) && !list.includes(it.id) && matchesQuery(query, it.name)).slice(0, 8)
    : [];
  const name = (id) => items[id]?.name ?? id;

  const act = async (fn, id, done) => {
    setBusy(true);
    setFail(null);
    try {
      await fn(slot, id);
      setMessage(done);
      setQuery('');
      retry();
    } catch (e) {
      setFail(e.message);
    }
    setBusy(false);
  };

  return (
    <>
      <p className="hint">
        빌드를 입력할 때 아이템 고르기 목록에 먼저 보이는 아이템입니다. 나머지는 [더보기]를 눌러야 보이고, 검색은 언제나 전체에서 합니다.
        {slot === 'core' ? ' 핵심 템트리에는 전설·서사·신발만 넣을 수 있습니다.' : ` 시작 아이템은 ${goldMax}골드 이하만 넣을 수 있습니다.`}
      </p>
      <div className="view-switch" role="group" aria-label="자주 쓰는 아이템 칸">
        {Object.entries(FREQUENT_SLOTS).map(([key, label]) => (
          <button
            key={key} type="button" className="btn btn-small" aria-pressed={slot === key}
            onClick={() => { setSlot(key); setQuery(''); setMessage(null); setFail(null); }}
          >
            {label} ({frequent[key].length})
          </button>
        ))}
      </div>
      {message && <p className="notice" role="status">{message}</p>}
      {list.length === 0 ? (
        <p className="empty">자주 쓰는 아이템이 아직 없습니다. 아래에서 검색해 넣어 주세요.</p>
      ) : (
        <ul className="offmeta-list" aria-label={`자주 쓰는 ${FREQUENT_SLOTS[slot]}`}>
          {list.map((id) => {
            const it = items[id];
            const gone = !it?.shop; // 이번 패치 상점에서 빠진 아이템 → 빌드 입력 화면에는 안 보인다
            return (
              <li key={id} className={gone ? 'gone' : undefined}>
                <Icon entry={it} size={28} />
                <span>{name(id)}</span>
                {gone && <small className="form-error">이번 패치 상점에 없음</small>}
                <button
                  type="button" className="btn btn-small btn-op" disabled={busy} aria-label={`${name(id)} 빼기`}
                  onClick={() => act(removeFrequentItem, id, `자주 쓰는 ${FREQUENT_SLOTS[slot]}에서 뺐습니다: ${name(id)}`)}
                >
                  빼기
                </button>
              </li>
            );
          })}
        </ul>
      )}
      <div className="search">
        <input
          type="search" value={query} onChange={(e) => setQuery(e.target.value)}
          placeholder="추가할 아이템 검색 (예: 덤불 조끼, ㄷㅂㅈㄲ)" aria-label={`자주 쓰는 ${FREQUENT_SLOTS[slot]}에 추가할 아이템 검색`} autoComplete="off"
        />
      </div>
      {results.length > 0 && (
        <ul className="offmeta-list" aria-label="검색 결과">
          {results.map((it) => (
            <li key={it.id}>
              <Icon entry={it} size={28} />
              <span>{it.name}</span>
              <button
                type="button" className="btn btn-small btn-op" disabled={busy} aria-label={`${it.name} 추가`}
                onClick={() => act(addFrequentItem, it.id, `자주 쓰는 ${FREQUENT_SLOTS[slot]}에 넣었습니다: ${it.name}`)}
              >
                추가
              </button>
            </li>
          ))}
        </ul>
      )}
      {query.trim() && results.length === 0 && <p className="hint">넣을 수 있는 아이템 중에 찾는 것이 없습니다.</p>}
      {fail && <p className="form-error" role="alert">{fail}</p>}
    </>
  );
}
