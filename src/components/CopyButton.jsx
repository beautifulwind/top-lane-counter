import { useState } from 'react';

/**
 * [복사] 버튼 (046 장인 인증: 운영자 라이엇 닉네임·확인 메일 문구·신청자 라이엇 닉네임). 누르면 "복사했습니다" 안내.
 * 복사가 막힌 브라우저면 글자를 그 자리에 보여 주며 직접 복사해 달라고 한다.
 */
export default function CopyButton({ text, label = '복사', what, op = false }) {
  const [state, setState] = useState(null); // null | 'done' | 'manual'
  const copy = async () => {
    try {
      await navigator.clipboard.writeText(text);
      setState('done');
    } catch {
      setState('manual');
    }
  };
  return (
    <span className="copy-wrap">
      <button type="button" className={`btn btn-small${op ? ' btn-op' : ''}`} onClick={copy} aria-label={what ? `${what} ${label}` : label}>
        {label}
      </button>
      {state === 'done' && <small className="hint copy-done" role="status">복사했습니다.</small>}
      {state === 'manual' && (
        <small className="hint" role="status">
          복사하지 못했습니다. 아래 글자를 길게 눌러 복사해 주세요.
          <textarea className="copy-manual" readOnly value={text} rows={Math.min(8, text.split('\n').length + 1)} onFocus={(e) => e.target.select()} />
        </small>
      )}
    </span>
  );
}
