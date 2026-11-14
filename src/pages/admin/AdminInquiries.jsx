import { useState } from 'react';
import { WITHDRAWN_USER } from '../../lib/nickname';
import { Link } from 'react-router-dom';
import {
  INQUIRY_ANSWER_MAX, INQUIRY_CATEGORIES, answerInquiry, getStaffInquiries, setInquiryCategory,
} from '../../api/inquiries';
import { useAlreadyHandled } from '../../components/AlreadyHandled';
import { useAuth } from '../../lib/auth';
import { fmtDateTime } from '../../lib/format';
import { useAsync } from '../../lib/useAsync';
import { ErrorBox, Loading } from '../../components/Status';
import { RequireStaff } from '../../components/RequireOperator';
import { CharCount } from '../../components/BoardParts';
import SectionHead from '../../components/SectionHead';
import UserName from '../../components/UserName';
import { ClockIcon, MessageIcon } from '../../components/Icons';

/**
 * 운영진: 문의 목록과 답변 (/admin/inquiries, SPEC 6-19). 답변하면 보낸 사람에게 알림이 간다.
 * 운영자는 전부, 감독관은 "계정·탈퇴"를 뺀 나머지 (DB의 RLS가 정한다 — 화면은 안내만). 분류 옮기기는 운영자만.
 * 답변은 문의 하나에 하나, 먼저 답한 분이 있으면 "이미 다른 분이 처리했습니다" 안내 후 목록을 새로고침한다.
 */
export default function AdminInquiries() {
  return (
    <RequireStaff>
      <InquiryAdmin />
    </RequireStaff>
  );
}

function InquiryAdmin() {
  const { user, isOperator } = useAuth();
  const [done, setDone] = useState(null);
  const { data, error, loading, retry } = useAsync(() => getStaffInquiries(user.id), [user.id]);
  const finished = (message) => {
    setDone(message);
    retry();
  };
  return (
    <article>
      <nav className="crumbs"><Link to="/admin" className="op-link">← 운영자 페이지</Link></nav>
      <h1 className="doc-title page-title"><MessageIcon size={26} className="title-icon op" /> 문의</h1>
      {done && <p className="notice" role="status">{done}</p>}
      {!isOperator && <p className="hint">&ldquo;계정·탈퇴&rdquo; 문의는 운영자만 볼 수 있어 이 목록에 나오지 않습니다.</p>}
      {loading && <Loading />}
      {error && <ErrorBox error={error} onRetry={retry} />}
      {data && (
        <>
          <section className="section" aria-labelledby="inq-waiting">
            <SectionHead icon={ClockIcon} count={data.waiting.length} id="inq-waiting">답변 대기</SectionHead>
            {data.waiting.length === 0 && <p className="empty">답변을 기다리는 문의가 없습니다.</p>}
            {data.waiting.length > 0 && (
              <ul className="inquiry-list" aria-label="답변 대기 문의">
                {data.waiting.map((row) => <StaffInquiry key={row.id} row={row} onDone={finished} />)}
              </ul>
            )}
          </section>
          <section className="section" aria-labelledby="inq-answered">
            <SectionHead icon={MessageIcon} count={data.answered.length} id="inq-answered">답변 완료</SectionHead>
            {data.answered.length === 0 && <p className="empty">답변한 문의가 없습니다.</p>}
            {data.answered.length > 0 && (
              <ul className="inquiry-list" aria-label="답변 완료 문의">
                {data.answered.map((row) => <StaffInquiry key={row.id} row={row} onDone={finished} />)}
              </ul>
            )}
            <p className="hint">문의는 마지막 활동(보낸 날 또는 답변한 날)부터 180일이 지나면 저절로 지워집니다.</p>
          </section>
        </>
      )}
    </article>
  );
}

function StaffInquiry({ row, onDone }) {
  const { isOperator } = useAuth();
  const [mode, setMode] = useState(null); // 'answer' | 'move'
  const handled = useAlreadyHandled(onDone); // 다른 분이 먼저 답했으면 안내 + 새로고침
  const answered = row.answer != null;
  return (
    <li className="inquiry-row" aria-label={`${INQUIRY_CATEGORIES[row.category]} 문의`}>
      <div className="inquiry-head">
        <span className="proposal-type">{INQUIRY_CATEGORIES[row.category]}</span>
        <span>{row.user ? <UserName profile={row.user} /> : WITHDRAWN_USER}</span>
        <small className="hint">{fmtDateTime(row.created_at)}</small>
      </div>
      <p className="inquiry-body">{row.body}</p>
      {answered && (
        <div className="inquiry-answer">
          <p className="inquiry-answer-head"><strong>(운) 답변</strong> <small className="hint">{fmtDateTime(row.answered_at)}</small></p>
          <p className="inquiry-body">{row.answer}</p>
        </div>
      )}
      {mode === null && (
        <div className="row-actions">
          {!answered && <button type="button" className="btn btn-small btn-op" onClick={() => setMode('answer')}>답변 쓰기</button>}
          {isOperator && <button type="button" className="btn btn-small btn-op" onClick={() => setMode('move')}>분류 옮기기</button>}
        </div>
      )}
      {mode === 'answer' && (
        <AnswerForm
          id={`answer-${row.id}`}
          onSubmit={handled(async (text) => { await answerInquiry(row.id, text); onDone('답변을 보냈습니다. 보낸 사람에게 알림이 갑니다.'); })}
          onCancel={() => setMode(null)}
        />
      )}
      {mode === 'move' && (
        <MoveForm
          id={`move-${row.id}`}
          current={row.category}
          onSubmit={async (category) => { await setInquiryCategory(row.id, category); onDone(`분류를 "${INQUIRY_CATEGORIES[category]}"(으)로 옮겼습니다.`); }}
          onCancel={() => setMode(null)}
        />
      )}
    </li>
  );
}

/** 답변 쓰기: 답변 내용 필수 (2,000자까지) → [답변 보내기]. [취소]·Esc로 닫힌다 */
function AnswerForm({ id, onSubmit, onCancel }) {
  const [text, setText] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const len = text.trim().length;
  const ready = len > 0 && len <= INQUIRY_ANSWER_MAX;
  const submit = async (e) => {
    e.preventDefault();
    if (!ready || busy) return;
    setBusy(true);
    setError(null);
    try {
      await onSubmit(text.trim());
    } catch (err) {
      setError(err.message);
      setBusy(false);
    }
  };
  return (
    <form className="note-form" onSubmit={submit} onKeyDown={(e) => e.key === 'Escape' && !busy && onCancel()}>
      <label htmlFor={id}>답변 (보낸 사람에게 보입니다)</label>
      {/* eslint-disable-next-line jsx-a11y/no-autofocus -- 버튼을 눌러 연 입력창이라 바로 쓰게 한다 */}
      <textarea id={id} rows={5} value={text} onChange={(e) => setText(e.target.value)} autoFocus />
      <CharCount value={text} max={INQUIRY_ANSWER_MAX} />
      <div className="note-form-actions">
        <button type="submit" className="btn btn-small btn-op" disabled={!ready || busy}>{busy ? '보내는 중…' : '답변 보내기'}</button>
        <button type="button" className="btn btn-small" onClick={onCancel} disabled={busy}>취소</button>
      </div>
      {error && <p className="form-error" role="alert">{error}</p>}
    </form>
  );
}

/** 분류 옮기기 (운영자만): 예) 계정 문제가 "기타"로 와서 감독관에게 보일 때 "계정·탈퇴"로 */
function MoveForm({ id, current, onSubmit, onCancel }) {
  const [category, setCategory] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const submit = async (e) => {
    e.preventDefault();
    if (!category || busy) return;
    setBusy(true);
    setError(null);
    try {
      await onSubmit(category);
    } catch (err) {
      setError(err.message);
      setBusy(false);
    }
  };
  return (
    <form className="note-form" onSubmit={submit} onKeyDown={(e) => e.key === 'Escape' && !busy && onCancel()}>
      <label htmlFor={id}>옮길 분류</label>
      <select id={id} value={category} onChange={(e) => setCategory(e.target.value)}>
        <option value="">분류를 골라 주세요</option>
        {Object.entries(INQUIRY_CATEGORIES).filter(([key]) => key !== current).map(([key, label]) => <option key={key} value={key}>{label}</option>)}
      </select>
      <small className="hint">&ldquo;계정·탈퇴&rdquo;로 옮기면 감독관은 이 문의를 볼 수 없게 됩니다.</small>
      <div className="note-form-actions">
        <button type="submit" className="btn btn-small btn-op" disabled={!category || busy}>{busy ? '옮기는 중…' : '옮기기 확정'}</button>
        <button type="button" className="btn btn-small" onClick={onCancel} disabled={busy}>취소</button>
      </div>
      {error && <p className="form-error" role="alert">{error}</p>}
    </form>
  );
}
