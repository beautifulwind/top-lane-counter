import { useState } from 'react';
import { PROVIDERS, linkProvider, startFresh } from '../api/auth';
import { LINK_CHOICES } from '../lib/guest';

/**
 * 비회원이 구글·카카오를 골랐을 때 그 자리에 열리는 선택 창 (마이페이지·로그인 화면).
 * [지금 계정에 연결하기] → linkIdentity (기록 그대로) / [새 계정으로 시작하기] → 한 번 더 확인 → 비회원 세션을 지우고 새로 로그인.
 * [취소]·Esc로 닫힌다. returnTo: 새 계정으로 로그인한 뒤 돌아올 경로
 */
export default function GuestLinkDialog({ provider, returnTo = '/', onClose }) {
  const name = PROVIDERS[provider];
  const [step, setStep] = useState('choose'); // 'choose' | 'fresh'
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);

  const run = async (fn) => {
    setBusy(true);
    setError(null);
    try {
      await fn(); // 성공하면 구글/카카오 화면으로 이동한다
    } catch (e) {
      setError(e.message);
      setBusy(false);
    }
  };

  return (
    <div
      className="guest-dialog"
      role="dialog"
      aria-label={`${name}로 계속하기`}
      onKeyDown={(e) => e.key === 'Escape' && !busy && onClose()}
    >
      {step === 'choose' ? (
        <>
          <p><strong>{name}로 어떻게 할까요?</strong></p>
          <div className="guest-choice">
            <button type="button" className="btn btn-primary" onClick={() => run(() => linkProvider(provider, { guest: true }))} disabled={busy}>
              {LINK_CHOICES.link.label} (추천)
            </button>
            <small className="hint">{LINK_CHOICES.link.hint}</small>
          </div>
          <div className="guest-choice">
            <button type="button" className="btn" onClick={() => setStep('fresh')} disabled={busy}>
              {LINK_CHOICES.fresh.label}
            </button>
            <small className="hint">{LINK_CHOICES.fresh.hint}</small>
          </div>
        </>
      ) : (
        <>
          <p className="warn">{LINK_CHOICES.fresh.warn}</p>
          <div className="row-actions">
            <button type="button" className="btn btn-danger" onClick={() => run(() => startFresh(provider, returnTo))} disabled={busy}>
              {busy ? `${name}로 이동 중…` : `${name} 새 계정으로 시작`}
            </button>
            <button type="button" className="btn" onClick={() => setStep('choose')} disabled={busy}>뒤로</button>
          </div>
        </>
      )}
      <div className="row-actions">
        {/* eslint-disable-next-line jsx-a11y/no-autofocus -- 그 자리에 열린 칸: [취소]에 초점 (SPEC 화면 공통 규칙) */}
        <button type="button" className="btn" onClick={onClose} disabled={busy} autoFocus>취소</button>
      </div>
      {error && <p className="form-error" role="alert">{error}</p>}
    </div>
  );
}
