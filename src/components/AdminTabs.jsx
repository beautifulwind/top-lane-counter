import { useCallback } from 'react';
import { useSearchParams } from 'react-router-dom';

/** 선택한 탭을 주소 ?tab=에 둔다 (새로고침해도 유지, 주소 기록은 쌓지 않음). 모르는 값은 첫 탭 */
export function useTabParam(tabs) {
  const [params, setParams] = useSearchParams();
  const wanted = params.get('tab');
  const active = tabs.some((t) => t.key === wanted) ? wanted : tabs[0].key;
  const setActive = useCallback((key) => {
    setParams((prev) => {
      const next = new URLSearchParams(prev);
      if (key === tabs[0].key) next.delete('tab');
      else next.set('tab', key);
      return next;
    }, { replace: true });
  }, [setParams, tabs]);
  return [active, setActive];
}

/** 탭 줄 (role=tablist). 380px에서도 한 줄에 들어가게 칸이 똑같이 나눠 쓴다 */
export default function AdminTabs({ tabs, active, onChange, label, idPrefix = 'admin' }) {
  return (
    <div className="admin-tabs" role="tablist" aria-label={label}>
      {tabs.map((t) => (
        <button
          key={t.key} type="button" role="tab" id={`${idPrefix}-tab-${t.key}`}
          aria-selected={active === t.key} aria-controls={`${idPrefix}-panel-${t.key}`}
          className={active === t.key ? 'admin-tab on' : 'admin-tab'} onClick={() => onChange(t.key)}
        >
          {t.label}
        </button>
      ))}
    </div>
  );
}

export function TabPanel({ tabKey, active, idPrefix = 'admin', children }) {
  if (active !== tabKey) return null;
  return <div role="tabpanel" id={`${idPrefix}-panel-${tabKey}`} aria-labelledby={`${idPrefix}-tab-${tabKey}`}>{children}</div>;
}

/** 할 수 없는 조치: 문장 대신 흐린(비활성) 버튼 + 그 아래 작은 회색 이유 */
export function DisabledAction({ label, why }) {
  return (
    <span className="disabled-action">
      <button type="button" className="btn btn-small btn-op" disabled>{label}</button>
      <small className="hint">{why}</small>
    </span>
  );
}
