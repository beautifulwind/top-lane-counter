import { useState } from 'react';
import {
  RESTRICT_DAY_PRESETS, RESTRICT_DAYS_MAX, RESTRICT_DAYS_MIN, RESTRICT_REASON_MAX,
  liftRestriction, restrictUser,
} from '../api/restrictions';
import { fmtDateTime } from '../lib/format';
import LimitedList from './LimitedList';
import { PREVIEW_COUNT } from '../lib/adminView';
import { CharCount } from './BoardParts';
import { ErrorBox, Loading } from './Status';
import { WITHDRAWN_USER } from './ModeratorAdmin';

const STATE_LABEL = { active: '제한 중', lifted: '해제됨', ended: '기간 끝남' };

/**
 * 운영자: 회원 정보(/admin/members/:id)의 "활동 제한" (068, SPEC 6-85, 1.3 패치 1-A 배치).
 * 회원 상세 페이지가 기록(state = useAsync 결과)을 한 번만 불러와 칩·이 칸·버튼 줄이 같이 쓴다.
 * 걸기·경고 버튼은 페이지의 나란한 버튼 줄에 있고, 이 파일은 ① 지금 상태+기록(RestrictionAdmin) ② 열린 칸(RestrictionPanel)을 그린다.
 * 기간(1·3·7·30일 또는 직접 1~365일) + 사유(본인에게 그대로 보임, 500자) → [제한 걸기 확정]. 제한 중이면 [해제](메모 선택).
 * 막는 규칙(자기 자신·운영자·감독관·이미 제한 중)은 DB가 정한다. 화면은 같은 이유를 버튼 아래 작은 설명으로만 알려 준다.
 */
export const activeRestriction = (rows) => rows?.find((r) => r.state === 'active') ?? null;

/** 버튼을 못 누르는 이유 (없으면 null) */
export function restrictBlockedBy(member, active) {
  if (member.role === 'admin') return '운영자에게는 활동 제한을 걸 수 없습니다.';
  if (member.role === 'moderator') return '감독관에게는 활동 제한을 걸 수 없습니다. 먼저 감독관에서 해제해 주세요.';
  if (active) return '이미 제한 중입니다. 아래 [해제]로 먼저 풀 수 있습니다.';
  return null;
}

export default function RestrictionAdmin({ state, onLift }) {
  const { data, error, loading, retry } = state;
  const active = activeRestriction(data);
  return (
    <section className="section" aria-label="활동 제한">
      <h2 className="section-title">활동 제한</h2>
      {loading && !data && <Loading />}
      {error && (error.code === 'NOT_READY' ? <p className="hint">{error.message}</p> : <ErrorBox error={error} onRetry={retry} />)}
      {data && (
        <>
          {active ? (
            <p className="notice caution" role="status">
              제한 중: {fmtDateTime(active.ends_at)}에 풀립니다. 사유: {active.reason}
            </p>
          ) : (
            <p className="hint">지금은 제한되어 있지 않습니다.</p>
          )}
          {active && (
            <div className="row-actions">
              <button type="button" className="btn btn-small btn-op" onClick={onLift}>해제</button>
            </div>
          )}
          <RestrictionLog rows={data} />
        </>
      )}
    </section>
  );
}

/** 열린 칸: panel === 'restrict'(걸기) | 'lift'(해제). 끝나면 기록을 다시 읽고(onChanged) 안내를 띄운다(onDone) */
export function RestrictionPanel({ member, state, panel, setPanel, onChanged, onDone }) {
  const active = activeRestriction(state.data);
  const done = (text) => { setPanel(null); onChanged(); onDone(text); };
  if (panel === 'restrict' && !active) {
    return (
      <RestrictForm
        member={member}
        onCancel={() => setPanel(null)}
        onSubmit={async (days, reason) => {
          const r = await restrictUser(member.id, days, reason);
          done(`${member.nickname ?? '회원'}님에게 ${days}일 활동 제한을 걸었습니다. ${fmtDateTime(r?.ends_at)}에 풀립니다.`);
        }}
      />
    );
  }
  if (panel === 'lift' && active) {
    return (
      <LiftForm
        id={`lift-restriction-${active.id}`}
        onCancel={() => setPanel(null)}
        onSubmit={async (note) => {
          await liftRestriction(active.id, note);
          done('활동 제한을 해제했습니다.');
        }}
      />
    );
  }
  return null;
}

function RestrictForm({ member, onSubmit, onCancel }) {
  const [days, setDays] = useState(7);
  const [custom, setCustom] = useState('');
  const [reason, setReason] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const chosen = custom !== '' ? Number(custom) : days;
  const daysOk = Number.isInteger(chosen) && chosen >= RESTRICT_DAYS_MIN && chosen <= RESTRICT_DAYS_MAX;
  const reasonLen = reason.trim().length;
  const ready = daysOk && reasonLen >= 1 && reasonLen <= RESTRICT_REASON_MAX;
  const submit = async (e) => {
    e.preventDefault();
    if (!ready || busy) return;
    setBusy(true);
    setError(null);
    try {
      await onSubmit(chosen, reason.trim());
    } catch (err) {
      setError(err.message);
      setBusy(false);
    }
  };
  return (
    <form className="note-form restrict-form" onSubmit={submit} onKeyDown={(e) => e.key === 'Escape' && !busy && onCancel()}>
      <fieldset className="restrict-days">
        <legend>기간</legend>
        <div className="row-actions" role="group" aria-label="기간 고르기">
          {RESTRICT_DAY_PRESETS.map((d) => (
            <button
              key={d} type="button" className={custom === '' && days === d ? 'btn btn-small btn-op on' : 'btn btn-small'}
              aria-pressed={custom === '' && days === d} onClick={() => { setDays(d); setCustom(''); }}
            >
              {d}일
            </button>
          ))}
        </div>
        <label htmlFor="restrict-custom-days">직접 입력 (1~365일)</label>
        <input
          id="restrict-custom-days" type="number" inputMode="numeric" min={RESTRICT_DAYS_MIN} max={RESTRICT_DAYS_MAX}
          value={custom} onChange={(e) => setCustom(e.target.value)} placeholder="예: 14"
        />
        {!daysOk && <small className="form-error">기간은 1일부터 365일까지 정할 수 있습니다.</small>}
      </fieldset>
      <label htmlFor="restrict-reason">사유 (필수, {member.nickname ?? '회원'}님에게 그대로 보입니다)</label>
      <textarea id="restrict-reason" rows={3} value={reason} onChange={(e) => setReason(e.target.value)} />
      <CharCount value={reason.trim()} max={RESTRICT_REASON_MAX} />
      <small className="hint">
        제한 중에는 글·댓글·빌드·상대법·추천·신고·팔로우·저장·장인 신청·사진·링크를 할 수 없습니다.
        읽기, 내 글 지우기, 팔로우 취소, 차단, 알림 설정, 문의하기, 탈퇴는 그대로 할 수 있습니다. 기간이 지나면 저절로 풀립니다.
      </small>
      <div className="note-form-actions">
        <button type="submit" className="btn btn-small btn-op" disabled={!ready || busy}>
          {busy ? '거는 중…' : daysOk ? `${chosen}일 제한 걸기 확정` : '제한 걸기 확정'}
        </button>
        <button type="button" className="btn btn-small" onClick={onCancel} disabled={busy}>취소</button>
      </div>
      {error && <p className="form-error" role="alert">{error}</p>}
    </form>
  );
}

/** 해제: 메모는 선택 (빈 칸으로도 확정할 수 있다) */
function LiftForm({ id, onSubmit, onCancel }) {
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const submit = async (e) => {
    e.preventDefault();
    if (busy) return;
    setBusy(true);
    setError(null);
    try {
      await onSubmit(note.trim());
    } catch (err) {
      setError(err.message);
      setBusy(false);
    }
  };
  return (
    <form className="note-form" onSubmit={submit} onKeyDown={(e) => e.key === 'Escape' && !busy && onCancel()}>
      <label htmlFor={id}>해제 메모 (선택, 기록에만 남습니다)</label>
      {/* eslint-disable-next-line jsx-a11y/no-autofocus -- [해제]를 눌러 연 칸이라 바로 쓰게 한다 */}
      <textarea id={id} rows={2} value={note} onChange={(e) => setNote(e.target.value)} maxLength={500} autoFocus />
      <div className="note-form-actions">
        <button type="submit" className="btn btn-small btn-op" disabled={busy}>{busy ? '해제하는 중…' : '해제 확정'}</button>
        <button type="button" className="btn btn-small" onClick={onCancel} disabled={busy}>취소</button>
      </div>
      {error && <p className="form-error" role="alert">{error}</p>}
    </form>
  );
}

function RestrictionLog({ rows }) {
  if (rows.length === 0) return <p className="none-line">활동 제한 기록이 없습니다.</p>;
  return (
    <LimitedList
      items={rows} limit={PREVIEW_COUNT.logs} className="log-list restriction-log" label="활동 제한 기록"
      renderItem={(r) => (
        <li key={r.id}>
          <strong>{STATE_LABEL[r.state] ?? r.state}</strong>
          {' · '}{r.days}일 · {fmtDateTime(r.starts_at)} ~ {fmtDateTime(r.ends_at)}
          <small className="hint">건 사람: {r.created_by || WITHDRAWN_USER} · 사유: {r.reason}</small>
          {r.lifted_at && (
            <small className="hint">
              해제: {fmtDateTime(r.lifted_at)} {r.lifted_by || WITHDRAWN_USER}{r.lift_note ? ` · ${r.lift_note}` : ''}
            </small>
          )}
        </li>
      )}
    />
  );
}
