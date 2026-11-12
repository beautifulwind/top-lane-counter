import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { getPendingCounts } from '../api/moderation';
import { adminSetNickname, revokeInfluencer } from '../api/influencer';
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
      <p className="hint">크리에이터·프로게이머(공식 이메일 회신)와 그랜드마스터 이상(친구 요청) 신청을 심사하고, 인증 해제·닉네임 바꾸기를 합니다.</p>
      <div className="row-actions">
        <Link to="/admin/influencers" className="btn btn-small btn-op">처리할 장인 신청{n != null && ` ${n}건`}</Link>
      </div>
    </>
  );
}
