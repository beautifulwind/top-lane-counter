import { useState } from 'react';
import { DocFields, docToForm } from './DocForm';
import BuildFields from './BuildFields';
import BuildCard from './BuildCard';
import DiffView from './DiffView';
import NoteForm from './NoteForm';
import { cleanDoc, docProblem, sameDoc } from '../lib/docContent';
import { buildProblem, buildToForm, patchMinor, sameBuild, toRow } from '../lib/buildContent';

/**
 * 운영자 [승인] = 내용 확인·수정 + 메모 (제안·빌드 [자세히] 공용).
 * 제안 내용이 처음부터 고칠 수 있는 상태로 열린다. 안 고치면 그대로, 고치면 고친 내용으로 공개된다.
 * doc: 제안한 글 (없으면 글 칸 없음) / build: 제안한 빌드 (저장 모양, 없으면 빌드 칸 없음)
 * game: Data Dragon { items, runes, spells, latest } / author: 빌드 미리보기에 보일 작성자
 * onSubmit({ note, content, build }): 고친 칸만 채운다 (안 고쳤으면 null). 실패하면 Error를 던진다.
 */
export default function ApproveEditor({ doc = null, build = null, game, author, noteLabel, hint, onSubmit, onCancel }) {
  const [content, setContent] = useState(() => docToForm(doc));
  const [form, setForm] = useState(() => (build ? buildToForm(build) : null));
  const docChanged = !!doc && !sameDoc(doc, content);
  const buildChanged = !!build && !sameBuild(build, form);
  const card = (b) => <BuildCard build={{ ...b, author }} {...game} />;

  const submit = async (note) => {
    const problem = (doc && docProblem(content)) || (build && buildProblem(form, game));
    if (problem) throw new Error(`고친 내용을 확인해 주세요: ${problem}`);
    await onSubmit({ note, content: docChanged ? content : null, build: buildChanged ? form : null });
  };

  return (
    <div className="approve-editor">
      <p className="hint">
        제안 내용을 고쳐서 승인할 수 있습니다. 안 고치면 그대로 공개됩니다. 고치면 원래 제안과 고친 내용이 모두 기록에 남고,
        제안자도 [마이페이지]에서 비교해 볼 수 있습니다. 누가 어느 칸을 고쳤는지는 운영진 처리 기록에 남습니다.
      </p>
      {doc && (
        <fieldset className="doc-form approve-doc">
          <legend>글</legend>
          <DocFields value={content} onChange={setContent} />
        </fieldset>
      )}
      {build && (
        <fieldset className="pick-group build-in-doc">
          <legend>빌드</legend>
          <div className="build-form">
            <BuildFields game={game} value={form} onChange={setForm} author={author} />
          </div>
        </fieldset>
      )}

      <section className="approve-changes" aria-label="고친 부분">
        <h3>고친 부분 (제안 → 운영자 수정)</h3>
        {!docChanged && !buildChanged && <p className="hint">고친 곳이 없습니다. 승인하면 제안 그대로 공개됩니다.</p>}
        {docChanged && <DiffView before={cleanDoc(doc)} after={cleanDoc(content)} />}
        {buildChanged && (
          <>
            <p className="hint">고친 빌드는 지금 패치({patchMinor(game.latest)})로 기록됩니다.</p>
            <div className="build-compare">
              <div>
                <h3>제안한 빌드</h3>
                {card(build)}
              </div>
              <div>
                <h3>고친 빌드</h3>
                {buildProblem(form, game) ? <p className="form-error">{buildProblem(form, game)}</p> : card({ ...toRow(form), patch: game.latest })}
              </div>
            </div>
          </>
        )}
      </section>

      <NoteForm
        id="approve-note"
        label={noteLabel}
        hint={hint}
        confirmLabel={docChanged || buildChanged ? '고친 내용으로 승인 확정' : '승인 확정'}
        busyLabel="승인 중…"
        autoFocus={false}
        onCancel={onCancel}
        onSubmit={submit}
      />
    </div>
  );
}
