import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { NICKNAME_MAX, deleteMyAccount, getNicknameRule, nicknameProblem, saveNickname } from '../api/auth';
import { useAsync } from '../lib/useAsync';
import { fmtDateTime } from '../lib/format';
import { josaOf } from '../lib/josa';
import { CharCount } from './BoardParts';
import { ErrorBox, Loading } from './Status';

/** /me 아래쪽 "계정": 닉네임 바꾸기(30일에 한 번) · 회원 탈퇴 (SPEC 6-8) */
export default function AccountSettings({ auth }) {
  return (
    <>
      <NicknameChange auth={auth} />
      <DeleteAccount auth={auth} />
    </>
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
  const locked = rule?.next && Date.parse(rule.next) > Date.now();

  const close = () => {
    setOpen(false);
    setFormError(null);
  };
  const save = async (e) => {
    e.preventDefault();
    const problem = nicknameProblem(value) ?? (value.trim() === current ? '지금 닉네임과 같아요.' : null);
    if (problem) return setFormError(problem);
    setBusy(true);
    setFormError(null);
    try {
      const profile = await saveNickname(auth.user.id, value);
      auth.setProfile(profile);
      setOpen(false);
      setDone(`닉네임을 "${profile.nickname}"${josaOf(profile.nickname, '으로/로')} 바꿨어요.`);
      retry();
    } catch (err) {
      setFormError(err.message); // 쓴 닉네임은 칸에 그대로
    }
    setBusy(false);
  };

  return (
    <section className="me-section" aria-labelledby="nickname-change">
      <h2 id="nickname-change">닉네임 바꾸기</h2>
      {done && <p className="notice" role="status">{done}</p>}
      {loading && <Loading />}
      {error && <ErrorBox error={error} onRetry={retry} />}
      {rule && (
        <>
          <p className="lead">
            지금 닉네임: <strong>{current}</strong>. 닉네임은 {rule.days}일에 한 번 바꿀 수 있어요.
            {locked && <> 다음에는 <strong>{fmtDateTime(rule.next)}</strong>부터 바꿀 수 있어요.</>}
          </p>
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
              <small className="hint">저장하면 {rule.days}일 동안 다시 바꿀 수 없어요.</small>
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

function DeleteAccount({ auth }) {
  const navigate = useNavigate();
  const [open, setOpen] = useState(false);
  const [confirm, setConfirm] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const nickname = auth.profile.nickname;
  const ready = confirm.trim() === nickname;

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
      navigate('/', { replace: true, state: { siteNotice: '탈퇴했어요. 계정과 내 기록을 지웠어요. 그동안 고마웠어요.' } });
    } catch (err) {
      setError(err.message);
      setBusy(false);
    }
  };

  return (
    <section className="me-section" aria-labelledby="delete-account">
      <h2 id="delete-account">회원 탈퇴</h2>
      {auth.isOperator ? (
        <p className="hint">운영자 계정은 탈퇴할 수 없어요.</p>
      ) : (
        <>
          <ul className="hint delete-account-list">
            <li><strong>지워져요:</strong> 계정·닉네임, 보낸 제안, 공개되지 않은 빌드, 따봉·비추, 알림, 경험치·칭호, 게시판 댓글·추천·신고, 문서 댓글, 다른 사람 댓글이 없는 내 글</li>
            <li><strong>작성자만 지우고 남아요:</strong> 문서에 반영된 내용과 수정 기록, 공개된 빌드, 다른 사람 댓글이 달린 내 글(&ldquo;삭제된 글&rdquo;로)</li>
            <li>카카오로 연결돼 있었으면 카카오 쪽 연결도 끊어요. 되돌릴 수 없어요.</li>
          </ul>
          {!open ? (
            <button type="button" className="btn btn-small btn-danger" onClick={() => setOpen(true)}>탈퇴</button>
          ) : (
            <form className="nick-form" onSubmit={submit} onKeyDown={(e) => e.key === 'Escape' && !busy && close()}>
              <label htmlFor="delete-confirm">
                확인을 위해 내 닉네임 <strong>{nickname}</strong>{josaOf(nickname, '을/를')} 그대로 입력해 주세요
              </label>
              {/* eslint-disable-next-line jsx-a11y/no-autofocus -- [탈퇴]를 눌러 연 확인 칸 */}
              <input id="delete-confirm" value={confirm} onChange={(e) => setConfirm(e.target.value)} autoComplete="off" autoFocus />
              {error && <p className="form-error" role="alert">{error}</p>}
              <div className="note-form-actions">
                <button type="submit" className="btn btn-small btn-danger" disabled={!ready || busy}>
                  {busy ? '탈퇴하는 중…' : '탈퇴 확정'}
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
