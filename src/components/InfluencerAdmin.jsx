import { useEffect, useId, useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { getPendingCounts } from '../api/moderation';
import { adminSetNickname, grantInfluencer, revokeInfluencer } from '../api/influencer';
import { INFLUENCER_KINDS } from '../lib/nickname';
import { NICKNAME_MAX, nicknameProblem } from '../api/auth';
import { josaOf } from '../lib/josa';
import { CharCount } from './BoardParts';
import NoteForm from './NoteForm';

/**
 * 운영자: 장인 인증 해제 (046 revoke_influencer). "장인" 표시만 없애고 닉네임은 그대로 — 그 뒤로는 본인이 바꿀 수 있다.
 * 장인 심사 화면(승인된 신청)과 회원 정보에서 같이 쓴다.
 */
export function RevokeInfluencer({ member, onDone }) {
  const [open, setOpen] = useState(false);
  if (!member?.influencer) return null;
  if (!open) return <button type="button" className="btn btn-small btn-op" onClick={() => setOpen(true)}>인증 해제</button>;
  return (
    <NoteForm
      id={`revoke-influencer-${member.id}`}
      label="해제 사유 (필수, 그 회원에게 알림으로 갑니다)"
      hint={'"장인" 표시와 장인 빌드 라벨이 사라집니다. 닉네임은 그대로이고, 그 뒤로는 본인이 바꿀 수 있습니다.'}
      confirmLabel="인증 해제 확정"
      onCancel={() => setOpen(false)}
      onSubmit={async (note) => {
        await revokeInfluencer(member.id, note);
        setOpen(false);
        onDone(`"${member.nickname}" 회원의 장인 인증을 해제했습니다.`);
      }}
    />
  );
}

/** 직접 지정 확인 창 문구 (049) */
export const GRANT_CONFIRM_TEXT = '신청·확인 절차 없이 바로 장인 표시가 붙습니다.';

/**
 * 운영자: 장인으로 직접 지정 (049 grant_influencer, SPEC 6-35). 회원 정보에서만.
 * 유형 + 메모(필수) → 확인 창("신청·확인 절차 없이 바로 장인 표시가 붙습니다.") → [지정]. 닉네임은 그대로.
 * 지정되면 회원 정보를 다시 읽어 같은 자리에 [인증 해제](RevokeInfluencer)가 나온다.
 * 운영자 계정·이미 장인은 버튼 없음, 비회원·신청 처리 전·닉네임 변경 예정은 안내만 (DB도 거부).
 */
export function GrantInfluencer({ member, onDone }) {
  const [open, setOpen] = useState(false);
  const [kind, setKind] = useState('');
  const [note, setNote] = useState('');
  const [asking, setAsking] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const id = `grant-influencer-${member?.id}`;
  if (!member || member.role === 'admin' || member.influencer) return null;
  if (member.is_guest) return <p className="hint">비회원(구글·카카오 연결 전)은 장인으로 지정할 수 없습니다.</p>;
  if (member.nickname_state === 'pending') {
    return (
      <p className="hint">
        장인 인증 신청을 심사 중인 회원이라 직접 지정할 수 없습니다. <Link to="/admin/influencers" className="op-link">장인 인증 심사 화면</Link>에서 그 신청을 승인해 주세요.
      </p>
    );
  }
  if (member.nickname_state === 'yielding') return <p className="hint">닉네임이 바뀔 예정인 회원이라 장인으로 지정할 수 없습니다. 새 닉네임을 정한 뒤 지정해 주세요.</p>;
  const close = () => { setOpen(false); setAsking(false); setKind(''); setNote(''); setError(null); };
  if (!open) return <button type="button" className="btn btn-small btn-op" onClick={() => setOpen(true)}>장인으로 직접 지정</button>;
  const ready = kind !== '' && note.trim() !== '';
  const grant = async () => {
    setBusy(true);
    setError(null);
    try {
      await grantInfluencer(member.id, kind, note.trim());
      close();
      onDone(`"${member.nickname}" 회원을 장인(${INFLUENCER_KINDS[kind]})으로 지정했습니다.`);
    } catch (e) {
      setAsking(false);
      setError(e.message);
    } finally {
      setBusy(false);
    }
  };
  return (
    <form
      className="note-form"
      aria-label="장인으로 직접 지정"
      onSubmit={(e) => { e.preventDefault(); if (ready && !busy) setAsking(true); }}
      onKeyDown={(e) => e.key === 'Escape' && !busy && !asking && close()}
    >
      <fieldset>
        <legend>유형 (필수)</legend>
        {Object.entries(INFLUENCER_KINDS).map(([k, label]) => (
          <label key={k} className="check-row">
            <input type="radio" name={`${id}-kind`} value={k} checked={kind === k} onChange={() => setKind(k)} />
            <span>{label}</span>
          </label>
        ))}
      </fieldset>
      <label htmlFor={`${id}-note`}>지정 메모 (필수, 처리 기록에 남습니다 — 예: 방송 채널 직접 확인)</label>
      <textarea id={`${id}-note`} rows={2} value={note} onChange={(e) => setNote(e.target.value)} maxLength={500} />
      <small className="hint">공식 이메일·라이엇 닉네임·채널 링크는 받지 않습니다. 닉네임은 그대로이고, 그 회원에게 "장인 인증이 완료됐습니다" 알림이 갑니다.</small>
      <div className="note-form-actions">
        <button type="submit" className="btn btn-small btn-op" disabled={!ready || busy}>{busy ? '처리하는 중…' : '지정하기'}</button>
        <button type="button" className="btn btn-small" onClick={close} disabled={busy}>취소</button>
      </div>
      {error && <p className="form-error" role="alert">{error}</p>}
      {asking && (
        <GrantConfirm
          nickname={member.nickname}
          kindLabel={INFLUENCER_KINDS[kind]}
          busy={busy}
          onConfirm={grant}
          onCancel={() => setAsking(false)}
        />
      )}
    </form>
  );
}

/** 직접 지정 확인 창: [지정] [취소] (처음 초점은 [취소] — 실수로 Enter를 눌러도 지정되지 않게) */
function GrantConfirm({ nickname, kindLabel, busy, onConfirm, onCancel }) {
  const cancelBtn = useRef(null);
  const panel = useRef(null);
  const titleId = useId();
  useEffect(() => {
    const back = document.activeElement;
    cancelBtn.current?.focus();
    return () => back?.focus?.();
  }, []);
  const onKeyDown = (e) => {
    if (e.key === 'Escape') {
      e.stopPropagation();
      if (!busy) onCancel();
      return;
    }
    if (e.key !== 'Tab') return;
    const list = [...panel.current.querySelectorAll('button:not([disabled])')];
    if (list.length === 0) return;
    const first = list[0];
    const last = list[list.length - 1];
    if (e.shiftKey && document.activeElement === first) {
      e.preventDefault();
      last.focus();
    } else if (!e.shiftKey && document.activeElement === last) {
      e.preventDefault();
      first.focus();
    }
  };
  return (
    // eslint-disable-next-line jsx-a11y/click-events-have-key-events, jsx-a11y/no-static-element-interactions
    <div className="dialog-backdrop" onClick={(e) => e.target === e.currentTarget && !busy && onCancel()}>
      <div ref={panel} className="dialog-panel" role="alertdialog" aria-modal="true" aria-labelledby={titleId} onKeyDown={onKeyDown}>
        <h2 id={titleId} className="dialog-title">장인으로 직접 지정</h2>
        <p><strong>{GRANT_CONFIRM_TEXT}</strong></p>
        <p>{nickname} · {kindLabel}</p>
        <div className="actions">
          <button type="button" className="btn btn-small btn-op" onClick={onConfirm} disabled={busy}>{busy ? '처리하는 중…' : '지정'}</button>
          <button ref={cancelBtn} type="button" className="btn btn-small" onClick={onCancel} disabled={busy}>취소</button>
        </div>
      </div>
    </div>
  );
}

/** 운영자: 회원 닉네임 바꾸기 (046 admin_set_nickname — 장인은 직접 못 바꾸므로). 사유 필수, 처리 기록 rename_member */
export function RenameMember({ member, onDone }) {
  const [open, setOpen] = useState(false);
  const [nick, setNick] = useState(member?.nickname ?? '');
  if (!member || member.role === 'admin') return null;
  if (!open) {
    return <button type="button" className="btn btn-small btn-op" onClick={() => { setNick(member.nickname ?? ''); setOpen(true); }}>닉네임 바꾸기</button>;
  }
  return (
    <NoteForm
      id={`rename-member-${member.id}`}
      label="바꾸는 사유 (필수, 처리 기록에 남습니다)"
      confirmLabel="닉네임 바꾸기 확정"
      autoFocus={false}
      onCancel={() => setOpen(false)}
      onSubmit={async (note) => {
        const problem = nicknameProblem(nick) ?? (nick.trim() === member.nickname ? '지금 닉네임과 같습니다.' : null);
        if (problem) throw new Error(problem);
        await adminSetNickname(member.id, nick, note);
        setOpen(false);
        onDone(`닉네임을 "${nick.trim()}"${josaOf(nick.trim(), '으로/로')} 바꿨습니다.`);
      }}
    >
      <label htmlFor={`rename-member-nick-${member.id}`}>새 닉네임</label>
      {/* eslint-disable-next-line jsx-a11y/no-autofocus -- [닉네임 바꾸기]를 눌러 연 칸 */}
      <input id={`rename-member-nick-${member.id}`} value={nick} onChange={(e) => setNick(e.target.value)} autoComplete="off" autoFocus />
      <CharCount value={nick.trim()} max={NICKNAME_MAX} />
      <small className="hint">비슷한 닉네임(다른 회원과 겹침)·[장인]·(운) 같은 표시는 쓸 수 없습니다. 바꾼 뒤 그 회원은 30일 제한 없이 다시 바꿀 수 있습니다(장인 제외).</small>
    </NoteForm>
  );
}

/** 운영자 페이지 "장인 인증" 칸: [처리할 장인 신청 N건] → 심사 화면 (건수를 못 읽으면 숫자 없이) */
export function InfluencerLink() {
  const [n, setN] = useState(null);
  useEffect(() => {
    let alive = true;
    getPendingCounts().then((c) => alive && setN(c?.influencers ?? null));
    return () => { alive = false; };
  }, []);
  return (
    <>
      <p className="hint">크리에이터·프로게이머(공식 이메일 회신)와 그랜드마스터 이상(친구 요청) 신청을 심사하고, 인증 해제·닉네임 바꾸기를 합니다. 신청 없이 직접 지정은 회원 정보에서 합니다.</p>
      <div className="row-actions">
        <Link to="/admin/influencers" className="btn btn-small btn-op">처리할 장인 신청{n != null && ` ${n}건`}</Link>
      </div>
    </>
  );
}
