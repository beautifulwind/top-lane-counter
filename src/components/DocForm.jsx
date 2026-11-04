import { useState } from 'react';
import { Link } from 'react-router-dom';
import { ALL_LEVELS, LIMITS, REQUIRED_LEVELS, docProblem, sameDoc, sortedLevels } from '../lib/docContent';

/** 입력칸 예시 (022): 말파이트로 트린다미어 상대하는 공략. 필수 레벨 칸에만 보인다 */
export const SUMMARY_EXAMPLE = '트린 평타를 틀어막는 착취·E선마·얼심 말파';
export const LEVEL_EXAMPLES = {
  1: 'E를 찍는다. 트린이 CS를 막으려고 들어오면, 아직 분노가 없을 때라 E+평타로 맞딜교해도 이긴다. 단, 트린 분노가 쌓인 상태라면 맞딜교하지 않는다.',
  2: '트린이 들어오면 E+Q+평타를 넣고 바로 빠진다.',
  3: '여기서부터는 내가 유리한 딜교가 가능하다. 착취를 쌓고 W+평타로 짧게 때린다. 트린이 맞딜교하러 오면 E+Q를 넣고 바로 빠진다.',
  6: '계속 먼저 착취로 짧은 딜교를 건다. 트린이 들어오면 받아치고, Q로 훔친 이동 속도로 빠지면서 다시 짧게 때린다.',
};

/** 저장된 문서 내용 → 입력 값 (필수 레벨 칸은 비어 있어도 보이게) */
export function docToForm(initial) {
  const notes = { ...(initial?.level_notes ?? {}) };
  for (const lv of REQUIRED_LEVELS) notes[lv] ??= '';
  return { summary: initial?.summary ?? '', level_notes: notes, lane_cautions: initial?.lane_cautions ?? '' };
}

/**
 * 매치업 문서 입력 폼 (새 카운터 제안·문서 수정 제안·다시 제출 공용)
 * initial: 시작 내용 / requireChange: true면 initial과 같을 때 제출 불가 (changedElsewhere: 빌드 등 다른 곳을 고쳤으면 통과)
 * children: 한 줄 요약 바로 아래(레벨별 딜교법 위)에 들어갈 것 (새 카운터 제안·다시 제출의 빌드 입력, 022: 문서 순서와 같게)
 * blocked: 보내기를 막는 이유 (예: 빌드를 아직 다 안 고름) → 글 검사 다음에 이 문구로 막는다
 * onSubmit(content): 실패하면 Error를 던진다 → 폼 아래에 문구로 보여 준다
 * cancelTo: [취소]를 누르면 갈 곳 (원래 보던 화면), busyLabel: 보내는 동안 버튼 글자
 */
export default function DocForm({
  initial, onSubmit, submitLabel = '제안', requireChange = false, changedElsewhere = false,
  unchangedMessage = '지금 문서와 달라진 내용이 없습니다.', children, blocked = null, cancelTo, busyLabel = '보내는 중…',
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
      <DocFields value={content} onChange={setContent} afterSummary={children} />

      {error && <p className="form-error" role="alert">{error}</p>}
      <div className="actions">
        <button type="submit" className="btn" disabled={busy}>{busy ? busyLabel : submitLabel}</button>
        {cancelTo && <Link to={cancelTo} className="btn">취소</Link>}
      </div>
      <p className="hint">보낸 제안은 운영자가 승인하면 반영됩니다. 진행 상황은 [마이페이지]에서 볼 수 있습니다.</p>
    </form>
  );
}

/**
 * 매치업 문서 칸 (한 줄 요약·레벨별 딜교법·특이사항). value = {summary, level_notes, lane_cautions} (docToForm 모양)
 * 제안 폼과 운영자 [승인](고쳐서 승인) 공용. afterSummary: 한 줄 요약과 레벨별 딜교법 사이에 넣을 것 (빌드 입력)
 */
export function DocFields({ value, onChange, afterSummary = null }) {
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
      <small className="hint" id="doc-summary-hint">예) {SUMMARY_EXAMPLE}</small>
      <input
        id="doc-summary"
        value={summary}
        onChange={(e) => set({ summary: e.target.value })}
        maxLength={LIMITS.summary + 20}
        placeholder={`예) ${SUMMARY_EXAMPLE}`}
        aria-describedby="doc-summary-hint"
      />
      <small className="count">{[...summary.trim()].length}/{LIMITS.summary}자</small>

      {afterSummary}

      <fieldset>
        <legend>레벨별 딜교법</legend>
        {sortedLevels(notes).map((lv) => {
          const required = REQUIRED_LEVELS.includes(lv);
          return (
            <div key={lv} className="doc-level">
              <label htmlFor={`lv-${lv}`}>
                {lv}레벨{required ? ' (필수)' : ''}
              </label>
              <textarea
                id={`lv-${lv}`} rows={3} value={notes[lv]} onChange={(e) => setNote(lv, e.target.value)}
                placeholder={LEVEL_EXAMPLES[lv] ? `예) ${LEVEL_EXAMPLES[lv]}` : undefined}
              />
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
