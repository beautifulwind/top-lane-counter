import { displayNickname } from '../lib/nickname';
import { useState } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { hideBuild, voteBuild } from '../api/builds';
import { canWrite, isGuest, useAuth } from '../lib/auth';
import GuestHint from './GuestHint';
import { patchMinor } from '../lib/buildContent';
import UserName from './UserName';
import NoteForm from './NoteForm';
import { ThumbIcon } from './Icons';

export function Icon({ entry, size = 32, round = false, fallback = '?' }) {
  if (!entry) {
    return (
      <span className="ico missing" style={{ width: size, height: size }} title="게임 데이터에 없음">
        {fallback}
      </span>
    );
  }
  const img = (name) => (
    <img
      src={entry.icon}
      alt={name}
      title={name}
      width={size}
      height={size}
      className={round ? 'ico round' : 'ico'}
      loading="lazy"
    />
  );
  // 서사 아이템 (028): 아이콘 아래 작은 "서사" 태그로 완성템과 구분 (읽는 이름은 "덤불 조끼 (서사)")
  if (entry.kind === 'epic') {
    return (
      <span className="ico-wrap">
        {img(`${entry.name} (서사)`)}
        <span className="epic-tag" aria-hidden="true">서사</span>
      </span>
    );
  }
  return img(entry.name);
}

/** 작성자 표시: 닉네임 / 작성자가 없으면 탈퇴한 유저 */
export function BuildAuthor({ build }) {
  if (build.author) return <UserName profile={build.author} />;
  return '(탈퇴한 유저)';
}

/**
 * 빌드 카드 (매치업 문서·등록 미리보기·운영자 화면 공용).
 * interactive: 추천/비추천 누르기 + 운영자 [빌드 숨기기] (매치업 문서에서만). 아니면 숫자만 보인다.
 * onHidden(message): 운영자가 숨긴 뒤 / lastOne: 이 매치업의 마지막 공개 빌드 (숨기기 잠금)
 */
export default function BuildCard({ build, items, runes, spells, latest, interactive = false, onHidden, lastOne = false }) {
  const r = build.runes;
  return (
    <article className="build" aria-label={`빌드: ${displayNickname(build.author, '(탈퇴한 유저)')}`}>
      <div className="build-head">
        <span className="build-author">
          <BuildAuthor build={build} />
        </span>
        {build.patch && (
          <span className="badge">{`패치 ${patchMinor(build.patch)}`}</span>
        )}
      </div>

      <div className="build-row">
        <span className="label">특성</span>
        <div className="icons">
          <Icon entry={runes.runes[r.keystone]} size={40} round />
          {r.primary.map((id, i) => <Icon key={i} entry={runes.runes[id]} size={28} round />)}
          <span className="sep" />
          <Icon entry={runes.paths[r.secondaryPath]} size={22} round />
          {r.secondary.map((id, i) => <Icon key={i} entry={runes.runes[id]} size={28} round />)}
          <span className="sep" />
          {r.shards.map((id, i) => <Icon key={i} entry={runes.shards[id]} size={20} round />)}
        </div>
      </div>

      <div className="build-row">
        <span className="label">주문</span>
        <div className="icons">
          {build.summoner_spells.map((id, i) => <Icon key={i} entry={spells[id]} />)}
        </div>
      </div>

      <div className="build-row">
        <span className="label">시작</span>
        <div className="icons">
          {build.starting_items.map((id, i) => <Icon key={i} entry={items[id]} />)}
        </div>
      </div>

      <div className="build-row">
        <span className="label">템트리</span>
        <div className="icons">
          {build.core_items.map((id, i) => (
            <span key={i} className="step">
              {i > 0 && <span className="arrow">›</span>}
              <Icon entry={items[id]} />
            </span>
          ))}
        </div>
      </div>

      <div className="build-row">
        <span className="label">스킬</span>
        <div className="skills">
          <span className="skill-group" aria-label={`선마: ${build.max_skill ?? '없음'}`}>
            <small className="muted">선마</small>
            <kbd className="skill-key">{build.max_skill ?? '?'}</kbd>
          </span>
        </div>
      </div>

      {interactive ? (
        <BuildActions build={build} onHidden={onHidden} lastOne={lastOne} />
      ) : (
        build.up !== undefined && (
          <div className="votes">
            <span className="vote-count" aria-label={`추천 ${build.up}`}><ThumbIcon /> {build.up}</span>
            <span className="vote-count" aria-label={`비추천 ${build.down}`}><ThumbIcon down /> {build.down}</span>
          </div>
        )
      )}
    </article>
  );
}

/** 추천/비추천 (로그인한 사람만, 한 사람 한 표, 같은 버튼 다시 누르면 취소, 내 빌드는 못 누름) + 운영자 숨기기 */
function BuildActions({ build, onHidden, lastOne }) {
  const auth = useAuth();
  const navigate = useNavigate();
  const location = useLocation();
  const [votes, setVotes] = useState({ up: build.up, down: build.down, mine: build.mine ?? null });
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const [hiding, setHiding] = useState(false);
  const [guestHint, setGuestHint] = useState(false);
  const signedIn = auth.status === 'signedIn';
  const own = signedIn && build.author_id === auth.user.id;
  const score = votes.up - votes.down;

  const vote = async (value) => {
    if (!signedIn) {
      navigate('/login', { state: { from: location.pathname + '#builds' } });
      return;
    }
    if (!canWrite(auth)) {
      navigate('/welcome', { state: { from: location.pathname + '#builds' } });
      return;
    }
    if (own || busy) return;
    if (isGuest(auth)) {
      setGuestHint(true); // 비회원은 추천·비추천 불가 (DB 트리거도 막는다)
      return;
    }
    setBusy(true);
    setError(null);
    try {
      const next = await voteBuild(build.id, votes.mine === value ? null : value);
      setVotes({ up: next.up, down: next.down, mine: next.mine ?? null });
    } catch (e) {
      setError(e.message);
    } finally {
      setBusy(false);
    }
  };

  const title = own ? '내 빌드에는 투표할 수 없습니다' : !signedIn ? '로그인하면 투표할 수 있습니다' : undefined;
  return (
    <>
      <div className="votes">
        <button
          type="button"
          className={votes.mine === 1 ? 'vote on' : 'vote'}
          aria-pressed={votes.mine === 1}
          aria-label={`추천 ${votes.up}`}
          onClick={() => vote(1)}
          disabled={own || busy}
          title={title}
        >
          <ThumbIcon /> {votes.up}
        </button>
        <button
          type="button"
          className={votes.mine === -1 ? 'vote on down' : 'vote'}
          aria-pressed={votes.mine === -1}
          aria-label={`비추천 ${votes.down}`}
          onClick={() => vote(-1)}
          disabled={own || busy}
          title={title}
        >
          <ThumbIcon down /> {votes.down}
        </button>
        {own && <span className="own-badge">내 빌드</span>}
        <span className={score > 0 ? 'score plus' : score < 0 ? 'score minus' : 'score'}>점수 {score > 0 ? `+${score}` : score}</span>
      </div>
      {error && <p className="form-error" role="alert">{error}</p>}
      {guestHint && <GuestHint what="추천·비추천을 누를" />}
      {auth.isOperator && (
        <div className="row-actions">
          <button type="button" className="btn btn-small btn-op" onClick={() => setHiding((v) => !v)} aria-expanded={hiding} disabled={lastOne}>
            빌드 숨기기
          </button>
          {lastOne && <small className="hint">마지막 공개 빌드라 숨길 수 없습니다. 다른 빌드를 먼저 승인하거나, 카운터를 숨겨 주세요.</small>}
        </div>
      )}
      {hiding && (
        <NoteForm
          id={`hide-build-${build.id}`}
          label="숨기는 사유 (필수, 작성자에게 보입니다)"
          hint="숨기면 다른 사람에게 이 빌드가 안 보입니다. 추천 수는 그대로 남고, 운영자 페이지에서 다시 공개할 수 있습니다."
          confirmLabel="숨기기 확정"
          busyLabel="숨기는 중…"
          onCancel={() => setHiding(false)}
          onSubmit={async (reason) => {
            await hideBuild(build.id, reason);
            onHidden?.(`빌드를 숨겼습니다. (${displayNickname(build.author)})`);
          }}
        />
      )}
    </>
  );
}
