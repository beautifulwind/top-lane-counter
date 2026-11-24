import { useState } from 'react';

/**
 * [공유] 버튼 (1.3 패치 1-C, SPEC 6-98). url을 공유한다: 기기의 공유 창(navigator.share)이 있으면 그것을, 없거나 못 쓰면 주소를 복사한다.
 * 공유 창을 닫은 것(AbortError)은 오류가 아니다. 복사도 막히면 주소를 글자로 보여 준다.
 */
export default function ShareButton({ url, title, label = '공유' }) {
  const [state, setState] = useState(null); // null | 'done' | 'manual'
  const press = async () => {
    setState(null);
    if (typeof navigator.share === 'function') {
      try {
        await navigator.share({ title, url });
        return;
      } catch (e) {
        if (e?.name === 'AbortError') return;
      }
    }
    try {
      await navigator.clipboard.writeText(url);
      setState('done');
    } catch {
      setState('manual');
    }
  };
  return (
    <span className="share">
      <button type="button" className="btn share-btn" onClick={press}>{label}</button>
      {state === 'done' && <small className="hint share-msg" role="status">주소를 복사했습니다.</small>}
      {state === 'manual' && (
        <small className="hint share-msg" role="status">
          복사하지 못했습니다. 아래 주소를 길게 눌러 복사해 주세요.
          <input className="copy-manual" readOnly value={url} onFocus={(e) => e.target.select()} aria-label="공유할 주소" />
        </small>
      )}
    </span>
  );
}
