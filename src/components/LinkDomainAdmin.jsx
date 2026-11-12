import { useState } from 'react';
import { addLinkDomain, getLinkDomains, removeLinkDomain } from '../api/links';
import { useAsync } from '../lib/useAsync';
import { ErrorBox, Loading } from './Status';
import NoteForm from './NoteForm';

/**
 * 운영자: 장인 링크 허용 사이트 (047 link_domains, SPEC 6-34 3b). 운영자 페이지 안의 칸.
 * [더하기] 도메인(예: youtube.com) + 사이트 이름 — 주소 모양은 DB가 정리·검사한다 (https:// · www. · 끝 / 는 떼어 줌)
 * [빼기] 사유 필수. 그 사이트 링크는 지우지 않고 숨긴다(다시 더하면 다시 보인다). 숨겨진 링크 수를 알려 준다
 * 평소엔 접혀 있고 [모두 보기]를 누르면 목록·더하기·빼기가 펼쳐진다 (다시 누르면 접힘)
 * 하위 도메인도 같은 사이트로 친다 (m.youtube.com → youtube.com)
 */
export default function LinkDomainAdmin() {
  const [done, setDone] = useState(null);
  const [open, setOpen] = useState(false); // 평소엔 접어 둔다: "허용 사이트 N개" + [모두 보기]
  const [adding, setAdding] = useState(false);
  const [removing, setRemoving] = useState(null); // 빼는 중인 도메인
  const { data, error, loading, retry } = useAsync(() => getLinkDomains(), []);
  const finished = (message) => {
    setDone(message);
    setAdding(false);
    setRemoving(null);
    retry();
  };
  return (
    <>
      {done && <p className="notice" role="status">{done}</p>}
      <p className="hint">장인이 링크로 올릴 수 있는 사이트입니다. 빼면 그 사이트 링크는 지워지지 않고 숨겨지며, 다시 더하면 다시 보입니다.</p>
      {loading && <Loading />}
      {error && <ErrorBox error={error} onRetry={retry} />}
      {data && (
        <div className="row-actions">
          <span>허용 사이트 {data.length}개</span>
          <button type="button" className="btn btn-small" aria-expanded={open} onClick={() => setOpen((v) => !v)}>
            {open ? '접기' : '모두 보기'}
          </button>
        </div>
      )}
      {data && open && (
        <ul className="proposal-list" aria-label="허용 사이트">
          {data.map((d) => (
            <li key={d.domain} className="proposal-row">
              <div className="proposal-main">
                <strong>{d.label}</strong> <code>{d.domain}</code>
                {removing !== d.domain && (
                  <button type="button" className="btn btn-small btn-op" onClick={() => { setDone(null); setAdding(false); setRemoving(d.domain); }}
                    aria-label={`${d.label} 빼기`}>빼기</button>
                )}
              </div>
              {removing === d.domain && (
                <NoteForm
                  id={`remove-domain-${d.domain}`}
                  label={`빼는 사유 — ${d.label} ${d.domain} (필수, 처리 기록에 남습니다)`}
                  confirmLabel="빼기 확정"
                  busyLabel="빼는 중…"
                  hint="이 사이트 링크는 지워지지 않고 숨겨집니다."
                  onCancel={() => setRemoving(null)}
                  onSubmit={async (note) => {
                    const hidden = await removeLinkDomain(d.domain, note);
                    finished(`허용 사이트에서 뺐습니다: ${d.label} ${d.domain}${hidden > 0 ? ` (숨겨진 링크 ${hidden}개)` : ''}`);
                  }}
                />
              )}
            </li>
          ))}
          {data.length === 0 && <li className="empty">허용 사이트가 없습니다. 장인이 링크를 올릴 수 없습니다.</li>}
        </ul>
      )}
      {data && open && !adding && (
        <div className="row-actions">
          <button type="button" className="btn btn-small btn-op" onClick={() => { setDone(null); setRemoving(null); setAdding(true); }}>사이트 더하기</button>
        </div>
      )}
      {open && adding && <AddDomainForm onCancel={() => setAdding(false)} onDone={finished} />}
    </>
  );
}

function AddDomainForm({ onCancel, onDone }) {
  const [domain, setDomain] = useState('');
  const [label, setLabel] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const ready = domain.trim() !== '' && label.trim() !== '';
  const submit = async (e) => {
    e.preventDefault();
    if (!ready || busy) return;
    setBusy(true);
    setError(null);
    try {
      const saved = await addLinkDomain(domain.trim(), label.trim());
      onDone(`허용 사이트에 더했습니다: ${label.trim()} ${saved ?? domain.trim()}`);
    } catch (err) {
      setError(err.message);
      setBusy(false);
    }
  };
  return (
    <form className="note-form" onSubmit={submit} onKeyDown={(e) => e.key === 'Escape' && !busy && onCancel()}>
      <label htmlFor="add-domain">도메인 (예: youtube.com)</label>
      {/* eslint-disable-next-line jsx-a11y/no-autofocus -- 버튼을 눌러 연 입력칸 */}
      <input id="add-domain" type="text" inputMode="url" autoComplete="off" maxLength={100} value={domain} onChange={(e) => setDomain(e.target.value)} autoFocus />
      <label htmlFor="add-domain-label">사이트 이름 (링크 앞에 보입니다, 예: 유튜브)</label>
      <input id="add-domain-label" type="text" autoComplete="off" maxLength={40} value={label} onChange={(e) => setLabel(e.target.value)} />
      <div className="note-form-actions">
        <button type="submit" className="btn btn-small btn-op" disabled={!ready || busy}>{busy ? '더하는 중…' : '더하기 확정'}</button>
        <button type="button" className="btn btn-small" onClick={onCancel} disabled={busy}>취소</button>
      </div>
      {error && <p className="form-error" role="alert">{error}</p>}
    </form>
  );
}
