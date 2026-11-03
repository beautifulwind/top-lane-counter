import { useState } from 'react';
import { getChampions } from '../api/ddragon';
import { addOffmeta, getOffmetaChampions, removeOffmeta } from '../api/rewards';
import { matchesQuery } from '../lib/chosung';
import { useAsync } from '../lib/useAsync';
import { ErrorBox, Loading } from './Status';

/**
 * 운영자: 비주류 픽 목록 (칭호 '비주류'의 기준, SPEC 6-3).
 * 비주류 픽 매치업 = 이기는 쪽 챔피언이 이 목록에 있는 매치업. 기여가 승인될 때 목록에 있었는지를 기록해 고정하므로,
 * 목록을 바꿔도 이미 승인된 기여는 그대로이고 새로 승인되는 것부터 새 목록이 적용된다.
 */
export default function OffmetaPicks() {
  const { data, error, loading, retry } = useAsync(async () => {
    const [list, picks] = await Promise.all([getChampions(), getOffmetaChampions()]);
    return { list, picks };
  }, []);
  const [query, setQuery] = useState('');
  const [busy, setBusy] = useState(null);
  const [message, setMessage] = useState(null);
  const [fail, setFail] = useState(null);

  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  const byId = Object.fromEntries(data.list.map((c) => [c.id, c]));
  const picked = new Set(data.picks.map((p) => p.champion_id));
  const results = query.trim()
    ? data.list.filter((c) => !picked.has(c.id) && matchesQuery(query, c.name, c.id)).slice(0, 8)
    : [];

  const act = async (fn, id, done) => {
    setBusy(id);
    setFail(null);
    try {
      await fn(id);
      setMessage(done);
      setQuery('');
      retry();
    } catch (e) {
      setFail(e.message);
    }
    setBusy(null);
  };

  return (
    <>
      <p className="hint">
        이기는 쪽 챔피언이 이 목록에 있는 매치업의 기여가 칭호 '비주류'에 들어가요. 승인할 때 목록에 있었는지를 기록하므로,
        목록을 바꿔도 이미 승인된 기여는 그대로예요 (새로 승인되는 것부터 적용).
      </p>
      {message && <p className="notice" role="status">{message}</p>}
      {data.picks.length === 0 ? (
        <p className="empty">비주류 픽이 아직 없어요.</p>
      ) : (
        <ul className="offmeta-list" aria-label="비주류 픽 목록">
          {data.picks.map((p) => {
            const c = byId[p.champion_id];
            return (
              <li key={p.champion_id}>
                {c && <img src={c.icon} alt="" width="28" height="28" />}
                <span>{c?.name ?? p.champion_id}</span>
                <button
                  type="button" className="btn btn-small btn-op" disabled={busy !== null}
                  aria-label={`${c?.name ?? p.champion_id} 빼기`}
                  onClick={() => act(removeOffmeta, p.champion_id, `비주류 픽에서 뺐어요: ${c?.name ?? p.champion_id}`)}
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
          placeholder="추가할 챔피언 검색 (예: 칼리스타, ㅋㄹ)" aria-label="비주류 픽에 추가할 챔피언 검색" autoComplete="off"
        />
      </div>
      {results.length > 0 && (
        <ul className="offmeta-list" aria-label="검색 결과">
          {results.map((c) => (
            <li key={c.id}>
              <img src={c.icon} alt="" width="28" height="28" />
              <span>{c.name}</span>
              <button
                type="button" className="btn btn-small btn-op" disabled={busy !== null} aria-label={`${c.name} 추가`}
                onClick={() => act(addOffmeta, c.id, `비주류 픽에 넣었어요: ${c.name}`)}
              >
                추가
              </button>
            </li>
          ))}
        </ul>
      )}
      {fail && <p className="form-error" role="alert">{fail}</p>}
    </>
  );
}
