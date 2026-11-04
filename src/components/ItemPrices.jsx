import { useState } from 'react';
import { getItemPriceInfo, updateItemPrices } from '../api/builds';
import { useAsync } from '../lib/useAsync';
import { ErrorBox, Loading } from './Status';

/**
 * 운영자 페이지의 "아이템 가격표" 칸 (018): DB가 시작 아이템 합계를 검사할 때 쓰는 가격표의 기준 패치.
 * 지금 패치와 다르면 경고, [아이템 가격 갱신]은 지금 Data Dragon 상점 아이템 가격으로 통째로 바꾼다.
 * game = { items, latest, startGoldMax }
 */
export default function ItemPrices({ game }) {
  const { data, error, loading, retry } = useAsync(() => getItemPriceInfo(), []);
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState(null);
  const [fail, setFail] = useState(null);
  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;

  const stale = data.patch !== game.latest;
  const update = async () => {
    setBusy(true);
    setFail(null);
    setDone(null);
    try {
      const n = await updateItemPrices(game.items, game.latest);
      setDone(`아이템 ${n}개 가격을 패치 ${game.latest} 기준으로 바꿨습니다.`);
      retry();
    } catch (e) {
      setFail(e.message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <>
      {done && <p className="notice" role="status">{done}</p>}
      <p>
        DB 가격표: {data.patch ? `패치 ${data.patch} 기준` : '비어 있습니다'} · 지금 패치: {game.latest} · 시작 아이템 합계 상한: {game.startGoldMax}골드
      </p>
      {stale && (
        <p className="warn" role="alert">
          가격표가 지금 패치와 다릅니다. 가격이 바뀐 아이템이나 새 아이템은 빌드 등록 때 DB가 막을 수 있습니다. [아이템 가격 갱신]을 눌러 주세요.
        </p>
      )}
      <p className="hint">상한 금액은 Supabase의 xp_rules 표 starting_gold_max에서 바꿉니다.</p>
      <button type="button" className="btn btn-small btn-op" onClick={update} disabled={busy}>
        {busy ? '갱신하는 중…' : '아이템 가격 갱신'}
      </button>
      {fail && <p className="form-error" role="alert">{fail}</p>}
    </>
  );
}
