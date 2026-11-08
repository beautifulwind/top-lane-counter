import { useState } from 'react';
import { Link } from 'react-router-dom';
import {
  INQUIRY_CATEGORIES, INQUIRY_DAILY_MAX, INQUIRY_MAX, INQUIRY_MIN, createInquiry, deleteMyInquiry, getMyInquiries,
} from '../api/inquiries';
import { useAuth } from '../lib/auth';
import { fmtDateTime } from '../lib/format';
import { useAsync } from '../lib/useAsync';
import { ErrorBox, Loading } from '../components/Status';
import { RequireLogin } from '../components/RequireOperator';
import { CharCount, ConfirmInline } from '../components/BoardParts';
import SectionHead from '../components/SectionHead';
import { MessageIcon, SendIcon } from '../components/Icons';

/**
 * 문의하기 (/inquiries, SPEC 6-19): 로그인한 사람 누구나(비회원·닉네임 전 포함) 운영진에게 문의를 보내고, 내 문의와 답변을 본다.
 * 분류 + 내용만 (제목 없음). 하루 3건·글자 수는 DB가 막고, 화면은 안내만 한다. 답변이 달리면 알림(/notifications)이 온다.
 */
export default function Inquiries() {
  return (
    <RequireLogin>
      <InquiriesBody />
    </RequireLogin>
  );
}

function InquiriesBody() {
  const { user } = useAuth();
  const [done, setDone] = useState(null);
  const { data, error, loading, retry } = useAsync(() => getMyInquiries(user.id), [user.id]);
  return (
    <article>
      <h1 className="doc-title page-title"><MessageIcon size={26} className="title-icon" /> 문의하기</h1>
      <p className="lead">
        오류 신고, 건의, 계정·탈퇴, 그 밖의 문의를 운영진에게 보낼 수 있습니다. 답변은 이메일이 아니라 이 화면과 <Link to="/notifications">알림</Link>으로 알려 드립니다.
        하루에 {INQUIRY_DAILY_MAX}건까지 보낼 수 있습니다.
      </p>
      {done && <p className="notice" role="status">{done}</p>}
      <InquiryForm onSent={() => { setDone('문의를 보냈습니다. 답변이 달리면 알림으로 알려 드립니다.'); retry(); }} />
      <section className="section" aria-labelledby="my-inquiries">
        <SectionHead icon={SendIcon} count={data?.length} id="my-inquiries">내 문의</SectionHead>
        {loading && <Loading />}
        {error && <ErrorBox error={error} onRetry={retry} />}
        {data && data.length === 0 && <p className="empty">보낸 문의가 없습니다.</p>}
        {data && data.length > 0 && (
          <ul className="inquiry-list" aria-label="내 문의 목록">
            {data.map((row) => (
              <MyInquiry key={row.id} row={row} onDeleted={() => { setDone('문의를 지웠습니다.'); retry(); }} />
            ))}
          </ul>
        )}
        <p className="hint">문의와 답변은 마지막 활동(보낸 날 또는 답변한 날)부터 180일 동안 보관한 뒤 지웁니다. 직접 지울 수도 있습니다.</p>
      </section>
    </article>
  );
}

function InquiryForm({ onSent }) {
  const [category, setCategory] = useState('');
  const [body, setBody] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const len = body.trim().length;
  const ready = category !== '' && len >= INQUIRY_MIN && len <= INQUIRY_MAX;

  const submit = async (e) => {
    e.preventDefault();
    if (!ready || busy) return;
    setBusy(true);
    setError(null);
    try {
      await createInquiry(category, body);
      setCategory('');
      setBody('');
      onSent();
    } catch (err) {
      setError(err.message); // 쓴 내용은 그대로 둔다
    }
    setBusy(false);
  };

  return (
    <form className="doc-form form-card" onSubmit={submit}>
      <label htmlFor="inquiry-category">분류</label>
      <select id="inquiry-category" value={category} onChange={(e) => setCategory(e.target.value)}>
        <option value="">분류를 골라 주세요</option>
        {Object.entries(INQUIRY_CATEGORIES).map(([key, label]) => <option key={key} value={key}>{label}</option>)}
      </select>
      <label htmlFor="inquiry-body">내용</label>
      <textarea id="inquiry-body" rows={6} value={body} onChange={(e) => setBody(e.target.value)} />
      <CharCount value={body} max={INQUIRY_MAX} />
      <small className="hint">
        {INQUIRY_MIN}자 이상 적어 주세요. 비밀번호, 주민등록번호, 전화번호 같은 개인정보는 적지 말아 주세요.
        &ldquo;계정·탈퇴&rdquo; 문의는 운영자만 볼 수 있습니다.
      </small>
      {error && <p className="form-error" role="alert">{error}</p>}
      <div className="actions">
        <button type="submit" className="btn btn-primary" disabled={!ready || busy}>{busy ? '보내는 중…' : '문의 보내기'}</button>
      </div>
    </form>
  );
}

function MyInquiry({ row, onDeleted }) {
  const [deleting, setDeleting] = useState(false);
  const answered = row.answer != null;
  return (
    <li className="inquiry-row" aria-label={`${INQUIRY_CATEGORIES[row.category]} 문의`}>
      <div className="inquiry-head">
        <span className="proposal-type">{INQUIRY_CATEGORIES[row.category]}</span>
        <span className={answered ? 'inquiry-state answered' : 'inquiry-state'}>{answered ? '답변 완료' : '답변 대기'}</span>
        <small className="hint">{fmtDateTime(row.created_at)}</small>
      </div>
      <p className="inquiry-body">{row.body}</p>
      {answered && (
        <div className="inquiry-answer">
          <p className="inquiry-answer-head"><strong>(운) 답변</strong> <small className="hint">{fmtDateTime(row.answered_at)}</small></p>
          <p className="inquiry-body">{row.answer}</p>
        </div>
      )}
      {deleting ? (
        <ConfirmInline
          question="문의를 지우시겠습니까? 답변도 함께 사라집니다."
          confirmLabel="지우기"
          onConfirm={async () => { await deleteMyInquiry(row.id); onDeleted(); }}
          onCancel={() => setDeleting(false)}
        />
      ) : (
        <div className="row-actions">
          <button type="button" className="btn btn-small" onClick={() => setDeleting(true)}>지우기</button>
        </div>
      )}
    </li>
  );
}
