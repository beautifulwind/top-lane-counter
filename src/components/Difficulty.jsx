import { useId, useState } from 'react';
import { DIFFICULTY_HELP, cleanDifficulty, difficultyLabel, difficultyText, nextDifficulty, sameDifficulty, starFill } from '../lib/difficulty';

const STAR_PATH = 'M12 2.5l2.9 6.1 6.6.8-4.9 4.6 1.3 6.6L12 17.3 6.1 20.6l1.3-6.6L2.5 9.4l6.6-.8z';

/** 별 한 개 (fill 0 = 빈 별, 0.5 = 반 칸, 1 = 가득). 색은 글자색 */
function Star({ fill, size = 22 }) {
  return (
    <span className="diff-star" style={{ width: size, height: size }} aria-hidden="true">
      <svg width={size} height={size} viewBox="0 0 24 24" focusable="false" className="diff-star-back"><path d={STAR_PATH} /></svg>
      {fill > 0 && (
        <svg width={size} height={size} viewBox="0 0 24 24" focusable="false" className="diff-star-front" style={fill === 0.5 ? { clipPath: 'inset(0 50% 0 0)' } : undefined}>
          <path d={STAR_PATH} />
        </svg>
      )}
    </span>
  );
}

/**
 * 읽기 전용 별점 표시 「★ 3.5」 (BuildAuthorName 별점 자리·카드 줄에서 쓴다). 값이 없으면 아무것도 그리지 않아 자리도 차지하지 않는다.
 * 읽는 문구는 「난이도 3.5점」 (눈에 보이는 글자는 읽지 않게 숨김).
 */
export function DifficultyBadge({ value, className = '' }) {
  const v = cleanDifficulty(value);
  if (v == null) return null;
  return (
    <span className={`author-rating ${className}`.trim()}>
      <span aria-hidden="true">★ {difficultyText(v)}</span>
      <span className="sr-only">{difficultyLabel(v)}</span>
    </span>
  );
}

/**
 * 난이도 입력 (선택 항목): 별 5개를 누른다.
 *  - 별을 누르면 그 별까지 채움(n점) → 같은 별을 다시 누르면 반 칸(n-0.5점) → 한 번 더 누르면 비움
 *  - 옆 [선택 안 함] 버튼으로도 바로 비움. 비어 있으면 「선택 안 함」
 * value: 0.5 단위 0.5~5.0 | null, onChange(값 | null)
 */
export default function DifficultyField({ value, onChange, disabled = false, label = '난이도' }) {
  const id = useId();
  const v = cleanDifficulty(value);
  return (
    <div className="field difficulty-field">
      <span className="field-label" id={`${id}-label`}>{label} <small className="muted">(선택)</small></span>
      <div className="difficulty-stars" role="group" aria-labelledby={`${id}-label`} aria-describedby={`${id}-help`}>
        {[1, 2, 3, 4, 5].map((n) => (
          <button
            key={n} type="button" className="diff-btn" disabled={disabled}
            aria-label={`별 ${n}개`} aria-pressed={v != null && v >= n - 0.5}
            onClick={() => onChange(nextDifficulty(v, n))}
          >
            <Star fill={starFill(v, n)} />
          </button>
        ))}
        <span className="diff-value" role="status">{v == null ? '선택 안 함' : `${difficultyText(v)}점`}</span>
        {v != null && (
          <button type="button" className="btn btn-small" disabled={disabled} onClick={() => onChange(null)}>선택 안 함</button>
        )}
      </div>
      <small className="hint" id={`${id}-help`}>{DIFFICULTY_HELP}</small>
    </div>
  );
}

/**
 * 내 빌드의 난이도만 따로 고치기 (내 빌드 자세히 /me/builds/:id — 숨겨진 빌드는 빌드 수정 화면이 없어 여기서 고친다).
 * [난이도 저장]을 누르면 onSave(값 | null)을 부르고, 성공하면 저장한 값을 onSaved(값)로 알린다. 빌드 내용·수정 기록·알림은 건드리지 않는다.
 */
export function DifficultyEditor({ saved, onSave, onSaved }) {
  const [value, setValue] = useState(cleanDifficulty(saved));
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState(null); // { ok, text }
  const changed = !sameDifficulty(saved, value);
  const save = async () => {
    if (busy || !changed) return;
    setBusy(true);
    setMessage(null);
    try {
      await onSave(value);
      onSaved(value);
      setMessage({ ok: true, text: '난이도를 저장했습니다.' });
    } catch (e) {
      setMessage({ ok: false, text: e.message });
    }
    setBusy(false);
  };
  return (
    <section className="difficulty-editor" aria-label="내 빌드 난이도">
      <DifficultyField value={value} onChange={setValue} disabled={busy} />
      <div className="actions">
        <button type="button" className="btn btn-small" data-write onClick={save} disabled={busy || !changed}>
          {busy ? '저장하는 중…' : '난이도 저장'}
        </button>
      </div>
      {message && <p className={message.ok ? 'notice' : 'form-error'} role={message.ok ? 'status' : 'alert'}>{message.text}</p>}
    </section>
  );
}
