import { useState } from 'react';
import { Link } from 'react-router-dom';
import { sameWikiBuild, wikiBuildProblem, wikiBuildToForm } from '../lib/wikiBuild';
import WikiBuildFields from './WikiBuildFields';

/**
 * 빌드 한 벌 입력 폼 (새 상대법·새 빌드·빌드 수정 공용). 보내면 바로 공개된다 (승인 없음, 038).
 * initial: 시작 값 (wikiBuild 입력 값 모양) / unchangedFrom: 이 값과 같으면 보내지 않는다 ([빌드 수정])
 * copyFrom: { build, label } — [지금 빌드 내용 가져오기]로 채울 빌드 (새 빌드)
 * onSubmit(value): 실패하면 Error를 던진다 → 폼 아래에 보여 준다. errorExtra(error): 오류 아래에 덧붙일 것 (예: [최신 내용 불러오기])
 * before: 빌드 이름 칸 위에 넣을 것 (챔피언 고르기 등)
 */
export default function WikiBuildForm({
  game, initial, author, onSubmit, submitLabel, busyLabel = '등록하는 중…', cancelTo, unchangedFrom = null,
  copyFrom = null, errorExtra = null, before = null,
}) {
  const [value, setValue] = useState(initial);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const [copied, setCopied] = useState(false);

  const submit = async (e) => {
    e.preventDefault();
    if (busy) return;
    const problem = wikiBuildProblem(value, game)
      ?? (unchangedFrom && sameWikiBuild(unchangedFrom, value) ? '바뀐 내용이 없습니다.' : null);
    if (problem) {
      setError({ message: problem });
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await onSubmit(value);
    } catch (err) {
      setError(err);
      setBusy(false);
    }
  };

  const copy = () => {
    setValue({ ...wikiBuildToForm(copyFrom.build), name: '' });
    setCopied(true);
  };

  return (
    <form className="doc-form wiki-build-form" onSubmit={submit} noValidate>
      {before}
      {copyFrom && (
        <div className="copy-build">
          <button type="button" className="btn" onClick={copy}>지금 빌드 내용 가져오기</button>
          <small className="hint">
            {copied
              ? `${copyFrom.label}의 내용을 채웠습니다. 다른 점만 고쳐 주세요.`
              : `${copyFrom.label}의 룬·아이템·글을 그대로 채웁니다. 비슷한 빌드를 만들 때 편합니다.`}
          </small>
        </div>
      )}
      <WikiBuildFields game={game} value={value} onChange={setValue} author={author} />

      {error && (
        <div className="form-error" role="alert">
          <p>{error.message}</p>
          {errorExtra?.(error)}
        </div>
      )}
      <div className="actions">
        <button type="submit" className="btn btn-primary" disabled={busy}>{busy ? busyLabel : submitLabel}</button>
        {cancelTo && <Link to={cancelTo} className="btn">취소</Link>}
      </div>
      <p className="hint">등록·수정하면 바로 모두에게 보입니다.</p>
    </form>
  );
}
