import { useState } from 'react';
import { Link } from 'react-router-dom';
import { ALL_LEVELS, LIMITS, REQUIRED_LEVELS, docProblem, sameDoc, sortedLevels } from '../lib/docContent';

/** 저장된 문서 내용 → 입력 값 (필수 레벨 칸은 비어 있어도 보이게) */
export function docToForm(initial) {
  const notes = { ...(initial?.level_notes ?? {}) };
  for (const lv of REQUIRED_LEVELS) notes[lv] ??= '';
  return { summary: initial?.summary ?? '', level_notes: notes, lane_cautions: initial?.lane_cautions ?? '' };
}

/**
 * 매치업 문서 입력 폼 (새 카운터 제안·문서 수정 제안·다시 제출 공용)
 * initial: 시작 내용 / requireChange: true면 initial과 같을 때 제출 불가 (changedElsewhere: 빌드 등 다른 곳을 고쳤으면 통과)
 * children: 문서 칸 아래, 보내기 버튼 위에 들어갈 것 (새 카운터 제안·다시 제출의 빌드 입력)
 * blocked: 보내기를 막는 이유 (예: 빌드를 아직 다 안 고름) → 글 검사 다음에 이 문구로 막는다
 * onSubmit(content): 실패하면 Error를 던진다 → 폼 아래에 문구로 보여 준다
 * cancelTo: [취소]를 누르면 갈 곳 (원래 보던 화면), busyLabel: 보내는 동안 버튼 글자
 */
export default function DocForm({
  initial, onSubmit, submitLabel = '제안 보내기', requireChange = false, changedElsewhere = false,
  unchangedMessage = '지금 문서와 달라진 내용이 없어요.', children, blocked = null, cancelTo, busyLabel = '보내는 중…',
}) {
  const [content, setContent] = useState(() => docToForm(initial));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);

  const submit = async (e) => {
    e.preventDefault();
    const problem = docProblem(content) ?? blocked
      ?? (requireChange && !changedElsewhere && sameDoc(initial, content) ? unchangedMessage : null);
    if (problem) return setError(problem);
    setBusy(true);
    setError(null);
    try {
      await onSubmit(content);
    } catch (err) {
      setError(err.message);
      setBusy(false);
    }
  };

  return (
    <form className="doc-form" onSubmit={submit} noValidate>
      <DocFields value={content} onChange={setContent} />

      {children}

      {error && <p className="form-error" role="alert">{error}</p>}
      <div className="actions">
        <button type="submit" className="btn" disabled={busy}>{busy ? busyLabel : submitLabel}</button>
        {cancelTo && <Link to={cancelTo} className="btn">취소</Link>}
      </div>
      <p className="hint">보낸 제안은 운영자가 승인하면 반영돼요. 진행 상황은 [내 활동]에서 볼 수 있어요.</p>
    </form>
  );
}

/**
 * 매치업 문서 칸 (한 줄 요약·레벨별 딜교법·특이사항). value = {summary, level_notes, lane_cautions} (docToForm 모양)
 * 제안 폼과 운영자 [승인](고쳐서 승인) 공용
 */
export function DocFields({ value, onChange }) {
  const { summary, level_notes: notes, lane_cautions: cautions } = value;
  const [addLevel, setAddLevel] = useState('');
  const unused = ALL_LEVELS.filter((lv) => !(lv in notes));
  const set = (patch) => onChange({ ...value, ...patch });
  const setNote = (lv, text) => set({ level_notes: { ...notes, [lv]: text } });
  const removeLevel = (lv) => {
    const { [lv]: _, ...rest } = notes;
    set({ level_notes: rest });
  };
  const add = () => {
    const lv = Number(addLevel || unused[0]);
    if (!lv) return;
    set({ level_notes: { ...notes, [lv]: '' } });
    setAddLevel('');
  };

  return (
    <>
      <label htmlFor="doc-summary">한 줄 요약 (필수)</label>
      <input
        id="doc-summary"
        value={summary}
        onChange={(e) => set({ summary: e.target.value })}
        maxLength={LIMITS.summary + 20}
        placeholder="챔피언 문서 목록에 보일 한 줄"
      />
      <small className="count">{[...summary.trim()].length}/{LIMITS.summary}자</small>

      <fieldset>
        <legend>레벨별 딜교법</legend>
        {sortedLevels(notes).map((lv) => {
          const required = REQUIRED_LEVELS.includes(lv);
          return (
            <div key={lv} className="doc-level">
              <label htmlFor={`lv-${lv}`}>
                {lv}레벨{required ? ' (필수)' : ''}
              </label>
              <textarea id={`lv-${lv}`} rows={3} value={notes[lv]} onChange={(e) => setNote(lv, e.target.value)} />
              {!required && (
                <button type="button" className="btn btn-small" onClick={() => removeLevel(lv)}>
                  {lv}레벨 칸 빼기
                </button>
              )}
            </div>
          );
        })}
        {unused.length > 0 && (
          <div className="doc-add-level">
            <label htmlFor="add-level">레벨 추가</label>
            <select id="add-level" value={addLevel} onChange={(e) => setAddLevel(e.target.value)}>
              {unused.map((lv) => <option key={lv} value={lv}>{lv}레벨</option>)}
            </select>
            <button type="button" className="btn btn-small" onClick={add}>칸 추가</button>
          </div>
        )}
      </fieldset>

      <label htmlFor="doc-cautions">특이사항</label>
      <textarea
        id="doc-cautions"
        rows={5}
        value={cautions}
        onChange={(e) => set({ lane_cautions: e.target.value })}
        placeholder="주의할 점, 이 매치업만의 특징이나 팁"
      />
    </>
  );
}
