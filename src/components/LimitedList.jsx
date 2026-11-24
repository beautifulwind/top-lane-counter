import { useState } from 'react';
import { PREVIEW_COUNT } from '../lib/adminView';

/** 목록 한 줄 「없음」 (점선 상자 대신) */
export function NoneLine({ children = '없음' }) {
  return <p className="none-line">{children}</p>;
}

/**
 * 긴 목록은 처음 limit개만, 나머지는 [모두 보기]로 펼친다 (다시 누르면 [접기]).
 * items가 비면 한 줄 「없음」(empty로 문구를 바꿀 수 있다). renderItem(item)은 <li>를 돌려준다.
 */
export default function LimitedList({ items, renderItem, limit = PREVIEW_COUNT.cards, className = 'proposal-list', label, empty = '없음', as: Tag = 'ul' }) {
  const [all, setAll] = useState(false);
  if (items.length === 0) return <NoneLine>{empty}</NoneLine>;
  const shown = all ? items : items.slice(0, limit);
  return (
    <>
      <Tag className={className} aria-label={label}>{shown.map(renderItem)}</Tag>
      {items.length > limit && (
        <div className="row-actions">
          <button type="button" className="btn btn-small" aria-expanded={all} onClick={() => setAll((v) => !v)}>
            {all ? '접기' : `모두 보기 (${items.length}개)`}
          </button>
        </div>
      )}
    </>
  );
}
