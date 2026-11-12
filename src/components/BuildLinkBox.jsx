import { useState } from 'react';
import { setBuildLink } from '../api/links';
import { linkProblem } from '../lib/links';
import { ConfirmInline } from './BoardParts';
import ExternalLink from './ExternalLink';

/**
 * 빌드 링크 칸 (047, SPEC 6-34): 그 빌드를 처음 만든 장인에게만 보인다(실제 검사는 DB set_build_link).
 * [빌드 수정](위키) 버튼·화면과 따로인 칸 — 링크를 바꿔도 빌드 내용·버전·수정 기록은 그대로다.
 * onSaved(message): 저장·삭제 뒤 (화면이 빌드를 다시 읽는다)
 */
export default function BuildLinkBox({ build, onSaved }) {
  const current = build.link ?? null;
  const [editing, setEditing] = useState(false);
  const [removing, setRemoving] = useState(false);
  const [url, setUrl] = useState(current?.url ?? '');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const inputId = `build-link-${build.id}`;

  const save = async (e) => {
    e.preventDefault();
    const problem = linkProblem(url);
    if (problem) {
      setError(problem);
      return;
    }
    setBusy(true);
    setError(null);
    try {
      await setBuildLink(build.id, url);
      setEditing(false);
      onSaved(current ? '빌드 링크를 고쳤습니다.' : '빌드 링크를 달았습니다.');
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <section className="build-link-box" aria-labelledby={`${inputId}-title`}>
      <h3 id={`${inputId}-title`}>장인 링크 <small className="muted">(내가 처음 만든 빌드)</small></h3>
      <p className="hint">이 빌드와 관련된 내 영상·방송 주소 1개를 달 수 있습니다. 빌드 내용 수정과는 따로라 다른 분이 빌드를 고쳐도 그대로입니다.</p>
      {!editing && (
        <>
          {current ? <div className="build-link-row"><ExternalLink link={current} /></div> : <p className="empty">아직 단 링크가 없습니다.</p>}
          <div className="row-actions">
            <button type="button" className="btn btn-small" onClick={() => { setUrl(current?.url ?? ''); setError(null); setRemoving(false); setEditing(true); }}>
              {current ? '링크 고치기' : '링크 달기'}
            </button>
            {current && !removing && <button type="button" className="btn btn-small" onClick={() => setRemoving(true)}>링크 지우기</button>}
          </div>
          {removing && (
            <ConfirmInline
              question="이 빌드의 링크를 지우시겠습니까?"
              confirmLabel="지우기"
              onCancel={() => setRemoving(false)}
              onConfirm={async () => {
                await setBuildLink(build.id, null);
                setRemoving(false);
                onSaved('빌드 링크를 지웠습니다.');
              }}
            />
          )}
        </>
      )}
      {editing && (
        <form onSubmit={save} noValidate>
          <label htmlFor={inputId}>링크 주소</label>
          <div className="link-edit-row">
            <input
              id={inputId}
              type="url"
              inputMode="url"
              autoComplete="off"
              placeholder="https://youtu.be/…"
              value={url}
              onChange={(e) => setUrl(e.target.value)}
              aria-invalid={error ? 'true' : undefined}
              aria-describedby={error ? `${inputId}-problem` : undefined}
            />
            <button type="submit" className="btn btn-small btn-primary" disabled={busy}>{busy ? '저장하는 중…' : '저장'}</button>
            <button type="button" className="btn btn-small" onClick={() => setEditing(false)} disabled={busy}>취소</button>
          </div>
          {error && <p id={`${inputId}-problem`} className="link-problem" role="alert">{error}</p>}
          <p className="hint">허용된 사이트(유튜브·치지직 등)의 https:// 주소만 됩니다. 사이트 목록은 마이페이지 › 링크 관리에서 볼 수 있습니다.</p>
        </form>
      )}
    </section>
  );
}
