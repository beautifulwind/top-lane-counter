import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { NICKNAME_MAX, deleteMyAccount, getNicknameRule, nicknameProblem, saveNickname, setOperatorMode } from '../api/auth';
import { useAsync } from '../lib/useAsync';
import { fmtDateTime } from '../lib/format';
import { josaOf } from '../lib/josa';
import { CharCount } from './BoardParts';
import { ErrorBox, Loading } from './Status';
import { isGuest } from '../lib/guest';
import SectionHead from './SectionHead';
import { PencilIcon, ShieldIcon, TrashIcon } from './Icons';
import PushSettings from './PushSettings';

/** /me/settings "계정": 운영자 모드(운영자 계정만, 034) · 휴대폰 알림(037) · 닉네임 바꾸기(30일에 한 번) · 회원 탈퇴 (SPEC 6-8) */
export default function AccountSettings({ auth }) {
  return (
    <>
      {auth.isOperatorAccount && <OperatorMode auth={auth} />}
      <PushSettings auth={auth} />
      <NicknameChange auth={auth} />
      <DeleteAccount auth={auth} />
    </>
  );
}

/**
 * 운영자 모드 켜기/끄기 (034, SPEC 6-21). 끄면 일반 회원과 같은 화면·같은 처리 길로 동작한다
 * (관리 메뉴·운영진 알림이 안 보이고, 운영자 권한이 필요한 일은 DB가 거부). 이 칸은 모드와 관계없이 항상 보여서
 * 같은 자리에서 다시 켤 수 있다. 바꾸면 프로필을 다시 읽어 화면 전체에 바로 반영한다.
 */
function OperatorMode({ auth }) {
  const on = auth.isOperator;
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);

  const toggle = async () => {
    if (busy) return;
    setBusy(true);
    setError(null);
    try {
      auth.setProfile(await setOperatorMode(auth.user.id, !on));
    } catch (e) {
      setError(e.message);
    }
    setBusy(false);
  };

  return (
    <section className="me-section" aria-labelledby="operator-mode">
      <SectionHead icon={ShieldIcon} id="operator-mode">운영자 모드</SectionHead>
      <p className="operator-mode-state" role="status">
        지금 <strong>{on ? '켜짐' : '꺼짐'}</strong>
      </p>
      {on ? (
        <p className="hint">켜져 있으면 관리 메뉴와 운영진 알림이 보이고, 제안·빌드·문의를 운영자로 처리합니다.</p>
      ) : (
        <p className="hint">
          꺼져 있는 동안은 일반 회원과 같은 화면으로 보이고, 제안·문의도 일반 회원처럼 승인 대기로 들어갑니다.
          관리 메뉴와 운영진 알림은 숨겨지고(알림은 다시 켜면 그대로 보입니다), 닉네임의 (운) 표시와 Lv.0은 그대로입니다.
        </p>
      )}
      <button type="button" className={`btn btn-small${on ? '' : ' btn-op'}`} onClick={toggle} disabled={busy} aria-pressed={on}>
        {busy ? '바꾸는 중…' : on ? '운영자 모드 끄기' : '운영자 모드 켜기'}
      </button>
      {error && <p className="form-error" role="alert">{error}</p>}
    </section>
  );
}

function NicknameChange({ auth }) {
  const { data: rule, error, loading, retry } = useAsync(() => getNicknameRule(auth.user.id), [auth.user.id]);
  const [open, setOpen] = useState(false);
  const [value, setValue] = useState('');
  const [busy, setBusy] = useState(false);
  const [formError, setFormError] = useState(null);
  const [done, setDone] = useState(null);
  const current = auth.profile.nickname;
  // 046: 장인은 직접 못 바꾸고(운영자가 바꿈), 인증 대기 중에도 못 바꾼다. 닉네임 변경 예정이면 30일 제한 없이 바로 바꾼다
  const { influencer, nickname_state: state, nickname_reset_at: resetAt } = auth.profile;
  const yielding = state === 'yielding';
  const blocked = influencer
    ? '인증된 장인은 닉네임을 직접 바꿀 수 없습니다. 바꾸려면 [문의하기]로 운영자에게 알려 주세요.'
    : state === 'pending'
      ? '장인 인증 신청을 심사하는 동안에는 닉네임을 바꿀 수 없습니다. 신청을 취소하면 바꿀 수 있습니다.'
      : null;
  const locked = !!blocked || (!yielding && rule?.next && Date.parse(rule.next) > Date.now());

  const close = () => {
    setOpen(false);
    setFormError(null);
  };
  const save = async (e) => {
    e.preventDefault();
    const problem = nicknameProblem(value) ?? (value.trim() === current ? '지금 닉네임과 같습니다.' : null);
    if (problem) return setFormError(problem);
    setBusy(true);
    setFormError(null);
    try {
      const profile = await saveNickname(auth.user.id, value);
      auth.setProfile(profile);
      setOpen(false);
      setDone(`닉네임을 "${profile.nickname}"${josaOf(profile.nickname, '으로/로')} 바꿨습니다.`);
      retry();
    } catch (err) {
      setFormError(err.message); // 쓴 닉네임은 칸에 그대로
    }
    setBusy(false);
  };

  return (
    <section className="me-section" aria-labelledby="nickname-change">
      <SectionHead icon={PencilIcon} id="nickname-change">닉네임 바꾸기</SectionHead>
      {done && <p className="notice" role="status">{done}</p>}
      {loading && <Loading />}
      {error && <ErrorBox error={error} onRetry={retry} />}
      {rule && (
        <>
          <p className="lead">
            지금 닉네임: <strong>{current}</strong>. 닉네임은 {rule.days}일에 한 번 바꿀 수 있습니다.
            {!blocked && !yielding && locked && <> 다음에는 <strong>{fmtDateTime(rule.next)}</strong>부터 바꿀 수 있습니다.</>}
          </p>
          {blocked && <p className="hint">{blocked}</p>}
          {yielding && (
            <p className="warn" role="note">
              장인 인증을 받은 분과 같은 닉네임이라 {resetAt ? <><strong>{fmtDateTime(resetAt)}</strong>에</> : '곧'} 임시 닉네임으로 바뀝니다.
              그 전에 새 닉네임을 정해 주세요. 지금은 {rule.days}일 제한 없이 바로 바꿀 수 있습니다.
            </p>
          )}
          {!open && !locked && (
            <button type="button" className="btn btn-small" onClick={() => { setValue(current); setOpen(true); setDone(null); }}>
              닉네임 바꾸기
            </button>
          )}
          {open && (
            <form className="nick-form" onSubmit={save} onKeyDown={(e) => e.key === 'Escape' && !busy && close()}>
              <label htmlFor="new-nickname">새 닉네임</label>
              {/* eslint-disable-next-line jsx-a11y/no-autofocus -- [닉네임 바꾸기]를 눌러 연 칸이라 바로 쓰게 한다 */}
              <input id="new-nickname" value={value} onChange={(e) => setValue(e.target.value)} autoComplete="off" autoFocus />
              <CharCount value={value.trim()} max={NICKNAME_MAX} />
              <small className="hint">저장하면 {rule.days}일 동안 다시 바꿀 수 없습니다.</small>
              {formError && <p className="form-error" role="alert">{formError}</p>}
              <div className="note-form-actions">
                <button type="submit" className="btn btn-small" disabled={busy}>{busy ? '저장하는 중…' : '고친 내용 저장'}</button>
                <button type="button" className="btn btn-small" onClick={close} disabled={busy}>취소</button>
              </div>
            </form>
          )}
        </>
      )}
    </section>
  );
}

/**
 * 회원 탈퇴 / 비회원 기록 지우기 (같은 delete_my_account). 확인 문구 = 닉네임, 닉네임 없는 비회원은 "지우기" (020).
 * /welcome(닉네임 없는 비회원)에서도 쓴다.
 */
export function DeleteAccount({ auth }) {
  const navigate = useNavigate();
  const guest = isGuest(auth);
  const [open, setOpen] = useState(false);
  const [confirm, setConfirm] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const nickname = auth.profile?.nickname ?? null;
  const word = nickname ?? '지우기';
  const ready = confirm.trim() === word;

  const close = () => {
    setOpen(false);
    setConfirm('');
    setError(null);
  };
  const submit = async (e) => {
    e.preventDefault();
    if (!ready || busy) return;
    setBusy(true);
    setError(null);
    try {
      await deleteMyAccount(confirm.trim());
      const siteNotice = guest ? '비회원 기록을 지웠습니다. 이 기기에서 로그인 정보도 지웠습니다.' : '탈퇴했습니다. 계정과 내 기록을 지웠습니다. 그동안 고마웠습니다.';
      navigate('/', { replace: true, state: { siteNotice } });
    } catch (err) {
      setError(err.message);
      setBusy(false);
    }
  };

  return (
    <section className="me-section" aria-labelledby="delete-account">
      <SectionHead icon={TrashIcon} id="delete-account">{guest ? '비회원 기록 지우기' : '회원 탈퇴'}</SectionHead>
      {auth.isOperatorAccount ? (
        <p className="hint">운영자 계정은 탈퇴할 수 없습니다.</p>
      ) : (
        <>
          {guest && <p className="hint">같이 쓰는 기기라면 다 쓴 뒤 지워 주세요. 비회원은 로그아웃이 없습니다.</p>}
          <ul className="hint delete-account-list">
            <li><strong>지워집니다:</strong> 계정·닉네임, 보낸 제안, 공개되지 않은 빌드, 알림, 경험치·칭호, 탑신병자 커뮤니티 댓글·추천·신고, 문서 댓글, 다른 사람 댓글이 없는 내 글</li>
            <li><strong>작성자만 지우고 남습니다:</strong> 문서에 반영된 내용과 수정 기록, 공개된 빌드, 다른 사람 댓글이 달린 내 글(내용은 지우고 보이지 않게)</li>
            <li><strong>수만 남습니다:</strong> 내가 누른 추천·비추천은 누른 사람 표시만 지워지고 추천 수는 그대로 남습니다.</li>
            {!guest && auth.profile?.influencer && (
              <li><strong>인증된 장인이라면:</strong> 링크, 팔로우, 장인 표시, 한정판 칭호가 사라지고, 닉네임은 30일 동안 다른 사람이 쓸 수 없습니다.</li>
            )}
            {guest ? <li>되돌릴 수 없습니다.</li> : <li>카카오로 연결돼 있었으면 카카오 쪽 연결도 끊습니다. 되돌릴 수 없습니다.</li>}
          </ul>
          {!open ? (
            <button type="button" className="btn btn-small btn-danger" onClick={() => setOpen(true)}>{guest ? '비회원 기록 지우기' : '탈퇴'}</button>
          ) : (
            <form className="nick-form" onSubmit={submit} onKeyDown={(e) => e.key === 'Escape' && !busy && close()}>
              <label htmlFor="delete-confirm">
                {nickname ? (
                  <>확인을 위해 내 닉네임 <strong>{nickname}</strong>{josaOf(nickname, '을/를')} 그대로 입력해 주세요</>
                ) : (
                  <>확인을 위해 <strong>지우기</strong>를 그대로 입력해 주세요</>
                )}
              </label>
              {/* eslint-disable-next-line jsx-a11y/no-autofocus -- [탈퇴]를 눌러 연 확인 칸 */}
              <input id="delete-confirm" value={confirm} onChange={(e) => setConfirm(e.target.value)} autoComplete="off" autoFocus />
              {error && <p className="form-error" role="alert">{error}</p>}
              <div className="note-form-actions">
                <button type="submit" className="btn btn-small btn-danger" disabled={!ready || busy}>
                  {busy ? (guest ? '지우는 중…' : '탈퇴하는 중…') : guest ? '지우기 확정' : '탈퇴 확정'}
                </button>
                <button type="button" className="btn btn-small" onClick={close} disabled={busy}>취소</button>
              </div>
            </form>
          )}
        </>
      )}
    </section>
  );
}
