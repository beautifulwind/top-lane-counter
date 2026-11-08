import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import {
  DndContext, KeyboardSensor, PointerSensor, closestCenter, useSensor, useSensors,
} from '@dnd-kit/core';
import {
  SortableContext, arrayMove, sortableKeyboardCoordinates, useSortable, verticalListSortingStrategy,
} from '@dnd-kit/sortable';
import { CSS } from '@dnd-kit/utilities';
import { getChampionMap } from '../../api/ddragon';
import { getCountersFor } from '../../api/content';
import { reorderCounters } from '../../api/proposals';
import { useAsync } from '../../lib/useAsync';
import { ErrorBox, Loading } from '../../components/Status';
import RequireOperator from '../../components/RequireOperator';
import NotFound from '../NotFound';

/** 카운터 순서 변경: 드래그(손잡이 ⠿) 또는 ▲▼ 버튼 → [순서 저장] */
export default function AdminOrder() {
  return (
    <RequireOperator>
      <OrderEditor />
    </RequireOperator>
  );
}

function OrderEditor() {
  const { championId } = useParams();
  const { data, error, loading, retry } = useAsync(async () => {
    const [champs, counters] = await Promise.all([getChampionMap(), getCountersFor(championId)]);
    return { champs, counters };
  }, [championId]);
  const [saved, setSaved] = useState(null); // DB에 저장된 순서 (id 목록). null = 아직 불러오는 중
  const [order, setOrder] = useState(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState(null);
  const [saveError, setSaveError] = useState(null);

  useEffect(() => {
    if (!data) return;
    const ids = data.counters.map((c) => c.id);
    setSaved(ids);
    setOrder(ids);
  }, [data]);

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 4 } }),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates }),
  );

  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  const target = data.champs[championId];
  if (!target) return <NotFound />;
  if (!order) return <Loading />;
  const byId = Object.fromEntries(data.counters.map((c) => [c.id, c]));
  const changed = order.join() !== saved.join();

  const move = (from, to) => {
    if (to < 0 || to >= order.length) return;
    setOrder((o) => arrayMove(o, from, to));
    setMessage(null);
  };
  const onDragEnd = ({ active, over }) => {
    if (over && active.id !== over.id) move(order.indexOf(active.id), order.indexOf(over.id));
  };
  const save = async () => {
    setBusy(true);
    setSaveError(null);
    try {
      await reorderCounters(championId, order);
      setSaved(order);
      setMessage('순서를 저장했습니다.');
    } catch (e) {
      setSaveError(e.message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <article>
      <nav className="crumbs">
        <Link to="/admin">운영자 페이지</Link> › <Link to={`/champion/${championId}`}>{target.name}</Link> › 순서 변경
      </nav>
      <h1 className="doc-title">{target.name} 카운터 순서</h1>
      <p className="hint">위에 있을수록 더 확실한 카운터입니다. ⠿를 끌거나 ▲▼로 옮긴 뒤 [순서 저장]을 눌러 주세요.</p>

      {order.length === 0 ? (
        <p className="empty">아직 등록된 카운터가 없습니다.</p>
      ) : (
        <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={onDragEnd}>
          <SortableContext items={order} strategy={verticalListSortingStrategy}>
            <ol className="order-list">
              {order.map((cid, i) => (
                <OrderRow
                  key={cid}
                  id={cid}
                  rank={i + 1}
                  champ={data.champs[byId[cid]?.counter_champion]}
                  fallback={byId[cid]?.counter_champion}
                  onUp={() => move(i, i - 1)}
                  onDown={() => move(i, i + 1)}
                  first={i === 0}
                  last={i === order.length - 1}
                />
              ))}
            </ol>
          </SortableContext>
        </DndContext>
      )}

      <div className="actions">
        <button type="button" className="btn btn-op" onClick={save} disabled={!changed || busy}>
          {busy ? '저장 중…' : '순서 저장'}
        </button>
        {changed && (
          <button type="button" className="btn btn-op" onClick={() => setOrder(saved)} disabled={busy}>
            되돌리기
          </button>
        )}
      </div>
      {message && <p className="notice" role="status">{message}</p>}
      {saveError && <p className="form-error" role="alert">{saveError}</p>}
    </article>
  );
}

function OrderRow({ id, rank, champ, fallback, onUp, onDown, first, last }) {
  const { attributes, listeners, setNodeRef, setActivatorNodeRef, transform, transition, isDragging } = useSortable({ id });
  const name = champ?.name ?? fallback;
  return (
    <li
      ref={setNodeRef}
      className={isDragging ? 'order-row dragging' : 'order-row'}
      style={{ transform: CSS.Transform.toString(transform), transition }}
    >
      <button type="button" className="drag-handle" ref={setActivatorNodeRef} {...attributes} {...listeners} aria-label={`${name} 끌어서 옮기기`}>
        ⠿
      </button>
      <span className="rank">{rank}</span>
      {champ && <img src={champ.icon} alt="" width="36" height="36" />}
      <span className="order-name">{name}</span>
      <span className="order-moves">
        <button type="button" className="btn btn-small btn-op" onClick={onUp} disabled={first} aria-label={`${name} 위로`}>▲</button>
        <button type="button" className="btn btn-small btn-op" onClick={onDown} disabled={last} aria-label={`${name} 아래로`}>▼</button>
      </span>
    </li>
  );
}
