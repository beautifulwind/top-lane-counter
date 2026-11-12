import { useState } from 'react';
import { Link } from 'react-router-dom';
import {
  approveInfluencer, extendInfluencer, getAllDoneApplications, getInfluencerApplications, rejectInfluencer,
} from '../../api/influencer';
import RequireOperator from '../../components/RequireOperator';
import { ErrorBox, Loading } from '../../components/Status';
import NoteForm from '../../components/NoteForm';
import CopyButton from '../../components/CopyButton';
import UserName from '../../components/UserName';
import { RenameMember, RevokeInfluencer } from '../../components/InfluencerAdmin';
import { SparklesIcon } from '../../components/Icons';
import { useAuth } from '../../lib/auth';
import { fmtDateTime } from '../../lib/format';
import { josaOf } from '../../lib/josa';
import { INFLUENCER_KINDS } from '../../lib/nickname';
import { OPERATOR_RIOT_ID, STATUS_LABEL, byEmail, confirmMail } from '../../lib/influencer';
import { useAsync } from '../../lib/useAsync';

const PAGE_SIZE = 20;
// 보기: 처리 전은 DB가 쪽을 나누고, 끝난 것은 한 번에 받아 상태별로 걸러 쪽을 나눈다
const VIEWS = [
  { key: 'pending', label: '처리 전' },
  { key: 'approved', label: '승인', match: (s) => s === 'approved' },
  { key: 'rejected', label: '반려', match: (s) => s === 'rejected' },
  { key: 'expired', label: '만료', match: (s) => s === 'expired' },
  { key: 'other', label: '취소·해제·탈퇴', match: (s) => ['cancelled', 'revoked', 'withdrawn'].includes(s) },
];

/**
 * 운영자: 장인 인증 심사 (046, SPEC 6-33 · /admin/influencers). 운영자 전용, 운영자 모드를 끄면 쓸 수 없다(DB도 거부).
 * (a) 크리에이터·프로게이머: 채널·공식 이메일 확인 → 확인 메일 문구 복사 → 회신을 보고 승인·반려
 * (b) 그랜드마스터 이상: 라이엇 닉네임#태그 복사 → 운영자 인증 계정의 받은 친구 요청(수락하지 않음)·op.gg 티어 확인 → 승인·반려
 */
export default function AdminInfluencers() {
  const auth = useAuth();
  if (auth.isOperatorAccount && !auth.isOperator) {
    return (
      <article>
        <h1 className="doc-title page-title"><SparklesIcon size={26} className="title-icon op" /> 장인 인증 심사</h1>
        <p className="empty">운영자 모드가 꺼져 있어 장인 인증을 심사할 수 없습니다. <Link to="/me/settings">계정 설정</Link>에서 운영자 모드를 켜 주세요.</p>
      </article>
    );
  }
  return (
    <RequireOperator>
      <Review />
    </RequireOperator>
  );
}

function Review() {
  const [view, setView] = useState('pending');
  const [page, setPage] = useState(1);
  const [done, setDone] = useState(null);
  const { data, error, loading, retry } = useAsync(async () => {
    if (view === 'pending') {
      const r = await getInfluencerApplications('pending', page, PAGE_SIZE);
      return { items: r?.items ?? [], total: r?.total ?? 0 };
    }
    const all = (await getAllDoneApplications()).filter((a) => VIEWS.find((v) => v.key === view).match(a.status));
    return { items: all.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE), total: all.length };
  }, [view, page]);
  const pages = data ? Math.max(1, Math.ceil(data.total / PAGE_SIZE)) : 1;
  const switchView = (v) => {
    setView(v);
    setPage(1);
    setDone(null);
  };
  const finished = (message) => {
    setDone(message);
    retry();
  };

  return (
    <article>
      <nav className="crumbs"><Link to="/admin" className="op-link">← 운영자 페이지</Link></nav>
      <h1 className="doc-title page-title"><SparklesIcon size={26} className="title-icon op" /> 장인 인증 심사</h1>
      <p className="hint">
        처리 전은 오래된 신청부터 보입니다. 14일 안에 처리하지 않으면 저절로 만료되고, [만료일 7일 늘리기]로 기다릴 수 있습니다.
        승인·반려 메모는 처리 기록에 남고, 반려 사유는 신청자에게 알림으로 갑니다. 공식 이메일·라이엇 닉네임은 처리가 끝나면 바로 지워집니다.
      </p>
      <div className="row-actions" role="group" aria-label="신청 보기">
        {VIEWS.map((v) => (
          <button key={v.key} type="button" className={`btn btn-small${view === v.key ? ' btn-op' : ''}`} aria-pressed={view === v.key} onClick={() => switchView(v.key)}>
            {v.label}
          </button>
        ))}
        {data && <span className="count-badge">{data.total}건</span>}
      </div>
      {done && <p className="notice" role="status">{done}</p>}
      {loading && <Loading />}
      {error && <ErrorBox error={error} onRetry={retry} />}
      {data && data.items.length === 0 && <p className="empty">{view === 'pending' ? '처리할 장인 신청이 없습니다.' : '해당하는 신청이 없습니다.'}</p>}
      {data && data.items.length > 0 && (
        <ul className="proposal-list" aria-label="장인 신청 목록">
          {data.items.map((a) => <ApplicationRow key={a.id} app={a} onDone={finished} />)}
        </ul>
      )}
      {pages > 1 && (
        <nav className="row-actions" aria-label="쪽 이동">
          <button type="button" className="btn btn-small" disabled={page <= 1} onClick={() => setPage(page - 1)}>이전</button>
          <span className="hint">{page} / {pages}쪽</span>
          <button type="button" className="btn btn-small" disabled={page >= pages} onClick={() => setPage(page + 1)}>다음</button>
        </nav>
      )}
    </article>
  );
}

/** 신청 한 줄: 신청자·유형·희망 닉네임 → 유형별 확인 도구 → [승인]·[반려]·[만료일 7일 늘리기] (끝난 것은 결과 + 해제·닉네임 바꾸기) */
function ApplicationRow({ app: a, onDone }) {
  const [mode, setMode] = useState(null); // 'approve' | 'reject'
  const [revert, setRevert] = useState(false);
  const [retryNow, setRetryNow] = useState(false);
  const [busy, setBusy] = useState(false);
  const [rowError, setRowError] = useState(null);
  const pending = a.status === 'pending';
  const kindLabel = a.kind_label ?? INFLUENCER_KINDS[a.kind] ?? a.kind;
  const staffOverlap = a.overlap && a.overlap.role !== 'user';

  const extend = async () => {
    setBusy(true);
    setRowError(null);
    try {
      const until = await extendInfluencer(a.id);
      onDone(`"${a.nickname}" 신청의 만료일을 ${fmtDateTime(until)}까지 늘렸습니다.`);
    } catch (e) {
      setRowError(e.message);
    }
    setBusy(false);
  };

  return (
    <li className="proposal-row" aria-label={`장인 신청: ${a.nickname}`}>
      <div className="proposal-main">
        <span className="proposal-type">{kindLabel}</span>{' '}
        <strong>{a.nickname}</strong>
        {!pending && <>{' '}<span className="op-badge">{STATUS_LABEL[a.status] ?? a.status}</span></>}
      </div>
      <div className="proposal-meta">
        <span>
          신청자:{' '}
          {a.user ? <Link to={`/admin/members/${a.user.id}`} className="op-link"><UserName profile={a.user} /></Link> : '탈퇴한 이용자'}
        </span>
        {a.old_nickname && a.old_nickname !== a.nickname && <span>신청 전 닉네임: {a.old_nickname}</span>}
        <span>신청: {fmtDateTime(a.created_at)}</span>
        {pending && <span>만료: {fmtDateTime(a.expires_at)}{a.extended_count > 0 && ` (${a.extended_count}번 늘림)`}</span>}
        {a.recent_rejections > 0 && <span>최근 180일 반려 {a.recent_rejections}번</span>}
      </div>

      {pending && a.overlap && (
        <p className="warn" role="note">
          같은(비슷한) 닉네임을 쓰는 회원: <Link to={`/admin/members/${a.overlap.id}`} className="op-link">{a.overlap.nickname}</Link>
          {staffOverlap
            ? ' — 운영진이 쓰는 닉네임이라 승인할 수 없습니다. 반려하거나 닉네임을 정리해 주세요.'
            : ' — 승인하면 이 회원에게 미리 알림이 가고, 3일 뒤 임시 닉네임으로 바뀝니다.'}
        </p>
      )}

      {byEmail(a.kind) ? <EmailCheck app={a} /> : <FriendCheck app={a} />}

      {!pending && (
        <p className="hint">
          {STATUS_LABEL[a.status] ?? a.status}
          {a.reviewer && ` · ${a.reviewer}`}
          {a.ended_at && ` · ${fmtDateTime(a.ended_at)}`}
          {a.review_note && ` — ${a.review_note}`}
          {a.retry_now && ' · 바로 다시 신청 허용'}
          {a.nickname_reverted && ` · 닉네임을 "${a.nickname_reverted}"${josaOf(a.nickname_reverted, '으로/로')} 되돌림`}
          {a.revoked_at && ` · 해제 ${fmtDateTime(a.revoked_at)}${a.revoke_note ? ` — ${a.revoke_note}` : ''}`}
        </p>
      )}

      {pending && mode === null && (
        <div className="row-actions">
          <button type="button" className="btn btn-small btn-op" disabled={busy || staffOverlap} onClick={() => setMode('approve')}>승인</button>
          <button type="button" className="btn btn-small btn-op" disabled={busy} onClick={() => setMode('reject')}>반려</button>
          <button type="button" className="btn btn-small btn-op" disabled={busy} onClick={extend}>만료일 7일 늘리기</button>
        </div>
      )}
      {rowError && <p className="form-error" role="alert">{rowError}</p>}
      {mode === 'approve' && (
        <NoteForm
          id={`approve-influencer-${a.id}`}
          label={`승인 메모 (필수, 기록용 — 예: ${byEmail(a.kind) ? '이메일 회신 확인' : '친구 요청 확인, op.gg 그랜드마스터'})`}
          confirmLabel="승인 확정"
          onCancel={() => setMode(null)}
          onSubmit={async (note) => {
            await approveInfluencer(a.id, note);
            onDone(`"${a.nickname}" 님을 장인으로 승인했습니다.`);
          }}
        />
      )}
      {mode === 'reject' && (
        <NoteForm
          id={`reject-influencer-${a.id}`}
          label="반려 사유 (필수, 신청자에게 알림으로 갑니다)"
          confirmLabel="반려 확정"
          onCancel={() => { setMode(null); setRevert(false); setRetryNow(false); }}
          onSubmit={async (note) => {
            await rejectInfluencer(a.id, note, { revertNickname: revert, retryNow });
            onDone(`"${a.nickname}" 신청을 반려했습니다.`);
          }}
        >
          <label className="check-row">
            <input type="checkbox" checked={revert} onChange={(e) => setRevert(e.target.checked)} />
            <span>닉네임도 되돌리기 <small className="hint">다른 회원과 겹치지 않아도 신청 전 닉네임으로 돌립니다 (겹치면 체크하지 않아도 되돌립니다).</small></span>
          </label>
          <label className="check-row">
            <input type="checkbox" checked={retryNow} onChange={(e) => setRetryNow(e.target.checked)} />
            <span>바로 다시 신청 허용 <small className="hint">7일 기다리지 않고, 180일 반려 횟수에도 세지 않습니다 (예: 링크를 잘못 적었을 때).</small></span>
          </label>
        </NoteForm>
      )}

      {a.status === 'approved' && a.user && (
        <div className="row-actions">
          <RevokeInfluencer member={a.user} onDone={onDone} />
          <RenameMember member={a.user} onDone={onDone} />
        </div>
      )}
    </li>
  );
}

/** (a) 채널 링크·공식 이메일 + 확인 메일 문구 복사 */
function EmailCheck({ app: a }) {
  const mail = confirmMail(a.nickname);
  return (
    <div className="inf-check" aria-label="이메일 확인">
      <p>
        채널: {a.channel_url ? <a href={a.channel_url} target="_blank" rel="noopener noreferrer nofollow" className="op-link">{a.channel_url}</a> : '—'}
      </p>
      {a.status === 'pending' && (
        <>
          <p>
            공식 이메일: {a.official_email ? <><strong>{a.official_email}</strong> <CopyButton text={a.official_email} what="공식 이메일" op /></> : '—'}
          </p>
          <ol className="hint">
            <li>채널 소개란·팀 공식 페이지에 공개된 이메일과 같은지 먼저 확인합니다.</li>
            <li>운영자 메일함에서 이 주소로 아래 확인 메일을 보냅니다.</li>
            <li>"본인입니다" 회신이 오면 승인(메모 "이메일 회신 확인"), 다르거나 공개되지 않은 이메일이면 반려합니다.</li>
          </ol>
          <p>제목: {mail.subject} <CopyButton text={mail.subject} what="확인 메일 제목" op /></p>
          <pre className="mail-preview">{mail.body}</pre>
          <CopyButton text={mail.body} what="확인 메일 본문" op />
        </>
      )}
    </div>
  );
}

/** (b) 라이엇 닉네임#태그 복사 + op.gg 링크 */
function FriendCheck({ app: a }) {
  return (
    <div className="inf-check" aria-label="친구 요청 확인">
      {a.status === 'pending' && (
        <p>
          라이엇 닉네임: {a.riot_id ? <><strong className="riot-id">{a.riot_id}</strong> <CopyButton text={a.riot_id} what="라이엇 닉네임" op /></> : '—'}
        </p>
      )}
      <p>
        op.gg: {a.opgg_url ? <a href={a.opgg_url} target="_blank" rel="noopener noreferrer nofollow" className="op-link">{a.opgg_url}</a> : '—'}
      </p>
      {a.status === 'pending' && (
        <ol className="hint">
          <li>운영자 인증 계정 <strong>{OPERATOR_RIOT_ID}</strong>의 받은 친구 요청에서 위 이름을 찾습니다. <strong>수락하지 않습니다.</strong></li>
          <li>op.gg에서 지금 티어가 그랜드마스터 이상인지 봅니다.</li>
          <li>둘 다 맞으면 승인(메모 "친구 요청 확인"), 요청이 없거나 이름·티어가 다르면 반려합니다.</li>
        </ol>
      )}
    </div>
  );
}
