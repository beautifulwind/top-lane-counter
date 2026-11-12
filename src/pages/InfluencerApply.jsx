import { useState } from 'react';
import { Link } from 'react-router-dom';
import { applyInfluencer, cancelInfluencer, getMyInfluencerStatus } from '../api/influencer';
import { NICKNAME_MAX, getProfile, nicknameProblem } from '../api/auth';
import { RequireLogin } from '../components/RequireOperator';
import { ErrorBox, Loading } from '../components/Status';
import { CharCount, ConfirmInline } from '../components/BoardParts';
import CopyButton from '../components/CopyButton';
import { InfluencerName } from '../components/UserName';
import SectionHead from '../components/SectionHead';
import { SparklesIcon, SendIcon } from '../components/Icons';
import { isGuest, useAuth } from '../lib/auth';
import { fmtDateTime } from '../lib/format';
import { josaOf } from '../lib/josa';
import { INFLUENCER_KINDS } from '../lib/nickname';
import { KIND_CHOICES, OPERATOR_RIOT_ID, STATUS_LABEL, applicationProblem, byEmail, operatorIdLabel } from '../lib/influencer';
import { useAsync } from '../lib/useAsync';

/**
 * 장인 인증 신청 (046, SPEC 6-33 · /me/influencer): 유형 고르기 → 유형별 칸과 안내 → 보내기.
 * 내 신청 상태(접수 → 확인 중 → 승인·반려·만료)와 [신청 취소], 반려 사유와 다시 신청할 수 있는 때.
 * 신청하면 닉네임이 희망 닉네임으로 바뀌므로(인증 대기) 보낸 뒤·취소한 뒤 내 프로필을 다시 읽는다.
 */
export default function InfluencerApply() {
  return (
    <RequireLogin>
      <ApplyPage />
    </RequireLogin>
  );
}

function ApplyPage() {
  const auth = useAuth();
  const [done, setDone] = useState(null);
  const { data, error, loading, retry } = useAsync(() => getMyInfluencerStatus(), [auth.user.id]);
  const after = async (message) => {
    setDone(message);
    try {
      auth.setProfile(await getProfile(auth.user.id));
    } catch { /* 닉네임 표시는 다음에 다시 읽을 때 맞춰진다 */ }
    retry();
  };

  const app = data?.application ?? null;
  const next = data?.next_apply_at ?? null;
  const waiting = next && Date.parse(next) > Date.now();
  const yielding = data?.nickname_state === 'yielding';
  const canApply = data && !data.is_guest && !auth.isOperatorAccount && !data.influencer && app?.status !== 'pending' && !waiting && !yielding;

  return (
    <article>
      <h1 className="doc-title page-title"><SparklesIcon size={26} className="title-icon" /> 장인 인증</h1>
      <p className="lead">
        장인은 인증된 크리에이터·그랜드마스터 이상·프로게이머입니다. 인증되면 닉네임 앞에 진홍 <span className="inf-tag">장인</span> 표시가 붙고,
        처음 만든 빌드에 "장인 빌드" 라벨이 붙습니다. 빌드는 장인이 만든 것도 다른 분들이 위키처럼 고칠 수 있습니다.
      </p>
      {done && <p className="notice" role="status">{done}</p>}
      {loading && !data && <Loading />}
      {error && <ErrorBox error={error} onRetry={retry} />}
      {data && (
        <>
          {(data.is_guest || isGuest(auth)) && (
            <p className="warn" role="note">
              장인 인증은 구글·카카오로 로그인한 회원만 신청할 수 있습니다. <Link to="/me#upgrade">구글·카카오 연결하기</Link>
            </p>
          )}
          {auth.isOperatorAccount && <p className="hint">운영자 계정은 장인 인증을 신청할 수 없습니다.</p>}
          {data.influencer && <Certified status={data} profile={auth.profile} />}
          {app && app.status !== 'approved' && <StatusCard app={app} next={next} onDone={after} />}
          {yielding && !data.influencer && (
            <p className="warn" role="note">
              지금 닉네임은 장인 인증을 받은 분과 같아 바뀔 예정입니다. 먼저 <Link to="/me/settings">계정 설정</Link>에서 새 닉네임을 정한 뒤 신청해 주세요.
            </p>
          )}
          {canApply && <ApplyForm current={auth.profile?.nickname ?? ''} onDone={after} />}
        </>
      )}
    </article>
  );
}

/** 이미 장인: 유형·인증일, 닉네임은 운영자에게 */
function Certified({ status, profile }) {
  return (
    <section className="section" aria-labelledby="inf-certified">
      <SectionHead icon={SparklesIcon} id="inf-certified">인증된 장인입니다</SectionHead>
      <p><InfluencerName profile={profile} /></p>
      <ul className="log-list">
        <li>유형 {INFLUENCER_KINDS[status.influencer] ?? status.influencer}</li>
        {status.influencer_at && <li>인증일 {fmtDateTime(status.influencer_at)}</li>}
      </ul>
      <p className="hint">장인은 닉네임을 직접 바꿀 수 없습니다. 바꾸려면 <Link to="/inquiries">문의하기</Link>로 운영자에게 알려 주세요.</p>
    </section>
  );
}

const STEPS = ['접수', '확인 중', '결과'];

/** 마지막 신청: 단계(접수 → 확인 중 → 결과) + 상태별 안내 + [신청 취소] */
function StatusCard({ app, next, onDone }) {
  const [cancelling, setCancelling] = useState(false);
  const pending = app.status === 'pending';
  const at = pending ? 1 : 2;
  const cancel = async () => {
    const back = await cancelInfluencer(app.id);
    setCancelling(false);
    onDone(back ? `신청을 취소했습니다. 닉네임을 "${back}"${josaOf(back, '으로/로')} 되돌렸습니다.` : '신청을 취소했습니다.');
  };

  return (
    <section className="section" aria-labelledby="inf-status">
      <SectionHead icon={SendIcon} id="inf-status">내 신청</SectionHead>
      <ol className="inf-steps" aria-label="진행 단계">
        {STEPS.map((s, i) => (
          <li key={s} className={i < at ? 'done' : i === at ? 'now' : ''} aria-current={i === at ? 'step' : undefined}>
            {i === 2 && !pending ? STATUS_LABEL[app.status] ?? s : s}
          </li>
        ))}
      </ol>
      <ul className="log-list" aria-label="신청 내용">
        <li>상태 <strong>{STATUS_LABEL[app.status] ?? app.status}</strong></li>
        <li>유형 {INFLUENCER_KINDS[app.kind] ?? app.kind} · 희망 닉네임 {app.nickname}</li>
        <li>신청 {fmtDateTime(app.created_at)}{pending && <> · 만료 {fmtDateTime(app.expires_at)}</>}{app.ended_at && <> · 끝남 {fmtDateTime(app.ended_at)}</>}</li>
        {app.channel_url && <li>채널 {app.channel_url}</li>}
        {app.official_email && <li>공식 이메일 {app.official_email}</li>}
        {app.riot_id && <li>라이엇 닉네임 {app.riot_id}</li>}
      </ul>

      {pending && (
        <>
          {byEmail(app.kind) ? <EmailGuide email={app.official_email} /> : <FriendGuide />}
          {cancelling ? (
            <ConfirmInline
              question="신청을 취소하시겠습니까? 다른 분과 같은 닉네임이면 원래 닉네임으로 돌아갑니다."
              confirmLabel="신청 취소"
              onConfirm={cancel}
              onCancel={() => setCancelling(false)}
            />
          ) : (
            <div className="row-actions">
              <button type="button" className="btn btn-small" onClick={() => setCancelling(true)}>신청 취소</button>
            </div>
          )}
        </>
      )}
      {app.status === 'rejected' && (
        <p className="warn" role="note">
          반려됐습니다. 사유: {app.review_note}
          <br />
          {next && Date.parse(next) > Date.now() ? <><strong>{fmtDateTime(next)}</strong>부터 다시 신청할 수 있습니다.</> : '지금 다시 신청할 수 있습니다.'}
          {app.nickname_reverted && <><br />닉네임을 "{app.nickname_reverted}"{josaOf(app.nickname_reverted, '으로/로')} 되돌렸습니다.</>}
        </p>
      )}
      {app.status === 'expired' && (
        <p className="hint">기간 안에 확인이 끝나지 않아 만료됐습니다. 다시 신청할 수 있습니다.{app.nickname_reverted && ` 닉네임은 "${app.nickname_reverted}"${josaOf(app.nickname_reverted, '으로/로')} 되돌렸습니다.`}</p>
      )}
      {app.status === 'cancelled' && <p className="hint">취소한 신청입니다. 다시 신청할 수 있습니다.</p>}
      {app.status === 'revoked' && <p className="warn" role="note">장인 인증이 해제됐습니다.{app.revoke_note && ` 사유: ${app.revoke_note}`}</p>}
    </section>
  );
}

/** (a) 크리에이터·프로게이머: 이메일 회신 안내 (이유 → 진행 → 안심) */
function EmailGuide({ email = null }) {
  return (
    <div className="inf-guide" aria-label="이메일 회신 안내">
      <h3>이메일로 확인하는 이유</h3>
      <p>채널 소개란이나 팀 공식 페이지에 공개된 이메일은 그 채널의 주인만 받아 볼 수 있습니다. 그 주소로 보낸 메일에 회신이 오면 채널 주인이 맞다는 뜻입니다.</p>
      <h3>이렇게 해 주세요</h3>
      <ol>
        <li>채널·방송 링크와, 그 채널(또는 팀 공식 페이지)에 공개된 공식 이메일을 적어 보냅니다.</li>
        <li>운영자가 {email ? <strong>{email}</strong> : '그 이메일'}로 「탑신병자 가입자 본인 확인 이메일입니다」라는 제목의 메일을 보냅니다. 스팸함도 확인해 주세요.</li>
        <li>14일 안에 그 메일에 "본인입니다"라고 회신해 주세요. 운영자가 확인하면 결과를 알림으로 알려 드립니다.</li>
      </ol>
      <h3>안심하셔도 됩니다</h3>
      <ul>
        <li>비밀번호·인증 코드·화면 캡처는 묻지 않습니다.</li>
        <li>공식 이메일은 확인에만 쓰고 심사가 끝나면 바로 지웁니다.</li>
      </ul>
    </div>
  );
}

/** (b) 그랜드마스터 이상: 친구 요청 안내 (이유 → 3단계 + 운영자 계정 복사 → 안심) */
function FriendGuide() {
  return (
    <div className="inf-guide" aria-label="친구 요청 안내">
      <h3>친구 요청을 보내는 이유</h3>
      <p>라이엇 닉네임#태그는 누구나 적을 수 있지만, 친구 요청은 그 계정에 로그인한 본인만 보낼 수 있습니다. 적어 주신 계정에서 요청이 오면 계정 주인이 맞다는 뜻입니다.</p>
      <h3>이렇게 해 주세요</h3>
      <ol>
        <li>라이엇 닉네임#태그와 op.gg 링크를 적어 신청서를 보냅니다.</li>
        <li>
          14일 안에 롤 클라이언트에서 아래 운영자 인증 계정에 친구 요청을 보냅니다.
          <br />
          친구 요청을 보낼 운영자 인증 계정: <strong className="riot-id">{OPERATOR_RIOT_ID}</strong>{' '}
          <CopyButton text={OPERATOR_RIOT_ID} what="운영자 라이엇 닉네임" />
        </li>
        <li>운영자가 요청을 보낸 이름이 신청서와 같은지, op.gg 티어가 그랜드마스터 이상인지 확인하고 결과를 알림으로 알려 드립니다.</li>
      </ol>
      <h3>안심하셔도 됩니다</h3>
      <ul>
        <li>운영자는 친구 요청을 <strong>수락하지 않습니다</strong>. 보낸 이름만 확인합니다.</li>
        <li>비밀번호·인증 코드·화면 캡처는 묻지 않습니다.</li>
        <li>라이엇 닉네임#태그는 심사가 끝나면 바로 지웁니다. (같은 계정의 중복 신청을 막는 암호화 값만 인증이 유지되는 동안 보관합니다)</li>
      </ul>
    </div>
  );
}

const EMPTY = { kind: '', channelUrl: '', email: '', riotId: '', opggUrl: '' };

/** 신청서: 유형 → 희망 닉네임 → 유형별 칸 + 안내 → [신청 보내기] */
function ApplyForm({ current, onDone }) {
  const [v, setV] = useState({ ...EMPTY, nickname: current });
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState(null);
  const set = (k) => (e) => setV({ ...v, [k]: e.target.value });

  const submit = async (e) => {
    e.preventDefault();
    const p = nicknameProblem(v.nickname) ?? applicationProblem(v);
    if (p) return setProblem(p);
    setBusy(true);
    setProblem(null);
    try {
      await applyInfluencer(v);
      await onDone(byEmail(v.kind)
        ? '신청을 보냈습니다. 적어 주신 공식 이메일로 확인 메일이 갑니다. 14일 안에 "본인입니다"라고 회신해 주세요.'
        : `신청을 보냈습니다. 14일 안에 운영자 인증 계정에 친구 요청을 보내 주세요. ${operatorIdLabel()}`);
    } catch (err) {
      setProblem(err.message);
      setBusy(false);
    }
  };

  return (
    <section className="section" aria-labelledby="inf-apply">
      <SectionHead icon={SendIcon} id="inf-apply">신청하기</SectionHead>
      <form className="inf-form" onSubmit={submit} noValidate>
        <fieldset>
          <legend>유형</legend>
          {KIND_CHOICES.map((c) => (
            <label key={c.kind} className="check-row">
              <input type="radio" name="inf-kind" value={c.kind} checked={v.kind === c.kind} onChange={set('kind')} />
              <span>{c.label}<small className="hint">{c.hint}</small></span>
            </label>
          ))}
        </fieldset>

        <label htmlFor="inf-nickname">희망 닉네임</label>
        <input id="inf-nickname" value={v.nickname} onChange={set('nickname')} autoComplete="off" />
        <CharCount value={v.nickname.trim()} max={NICKNAME_MAX} />
        <small className="hint">
          신청하면 지금 닉네임이 이 닉네임으로 바뀌고 "인증 대기" 표시가 붙습니다. 심사 중에는 닉네임을 바꿀 수 없습니다(신청을 취소하면 됩니다).
          반려·만료됐을 때 다른 분과 같은 닉네임이면 원래 닉네임으로 돌아갑니다.
        </small>

        {byEmail(v.kind) && (
          <>
            <label htmlFor="inf-channel">채널·방송 링크</label>
            <input id="inf-channel" type="url" inputMode="url" placeholder="https://" value={v.channelUrl} onChange={set('channelUrl')} autoComplete="off" />
            <label htmlFor="inf-email">공식 이메일</label>
            <input id="inf-email" type="email" inputMode="email" value={v.email} onChange={set('email')} autoComplete="off" />
            <small className="hint">채널 소개란이나 팀 공식 페이지에 공개된 이메일만 됩니다. 개인 이메일은 확인할 수 없습니다.</small>
            <EmailGuide />
          </>
        )}
        {v.kind === 'grandmaster' && (
          <>
            <label htmlFor="inf-riot">라이엇 닉네임#태그</label>
            <input id="inf-riot" placeholder="닉네임#KR1" value={v.riotId} onChange={set('riotId')} autoComplete="off" />
            <label htmlFor="inf-opgg">op.gg 링크</label>
            <input id="inf-opgg" type="url" inputMode="url" placeholder="https://op.gg/" value={v.opggUrl} onChange={set('opggUrl')} autoComplete="off" />
            <FriendGuide />
          </>
        )}

        <p className="hint">이미 다른 분이 신청한 닉네임·채널·라이엇 닉네임이면 신청할 수 없습니다. 본인의 것이라면 <Link to="/inquiries">문의하기</Link>로 알려 주세요.</p>
        {problem && <p className="form-error" role="alert">{problem}</p>}
        <div className="actions">
          <button type="submit" className="btn btn-primary" disabled={busy || !v.kind}>{busy ? '보내는 중…' : '신청 보내기'}</button>
        </div>
      </form>
    </section>
  );
}
