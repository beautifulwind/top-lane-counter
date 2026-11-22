import { WITHDRAWN_USER, displayNickname } from '../lib/nickname';
import { useEffect, useRef, useState } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { voteBuild } from '../api/builds';
import { saveBuild, unsaveBuild } from '../api/bookmarks';
import { canWrite, isGuest, useAuth } from '../lib/auth';
import GuestHint from './GuestHint';
import VoteNotice, { useVoteNotice } from './VoteNotice';
import { GO_DELAY_MS, MSG, SAVE_MSG, voteErrorText } from '../lib/voteMessages';
import { patchMinor } from '../lib/buildContent';
import UserName from './UserName';
import SkillSequenceView from './SkillSequenceView';
import { BookmarkIcon, ThumbIcon } from './Icons';

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

/** 작성자 표시: 닉네임만(레벨·칭호 없이, 장인 표시는 보임 — 046) / 작성자가 없으면 탈퇴한 이용자 */
export function BuildAuthor({ build }) {
  if (build.author) return <UserName profile={build.author} plain linkTo={build.author_id} />;
  return WITHDRAWN_USER;
}

/**
 * 빌드 카드 (상대법 화면·등록 미리보기·운영자 화면 공용).
 * interactive: 추천/비추천 누르기 (상대법 화면에서만). 아니면 숫자만 보인다.
 * authorExtra: 작성자 닉네임 옆에 붙일 것 (050: 상대법 화면의 장인 [+] 팔로우 버튼)
 */
export default function BuildCard({ build, items, runes, spells, interactive = false, authorExtra = null, onVoted = null }) {
  const r = build.runes;
  return (
    <article className="build" aria-label={`빌드: ${displayNickname(build.author)}`}>
      <div className="build-head">
        <span className="build-author">
          <BuildAuthor build={build} />
          {authorExtra}
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
          <SkillSequenceView sequence={build.skill_sequence} />
        </div>
      </div>

      {interactive ? (
        <BuildActions build={build} onVoted={onVoted} />
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

/**
 * 추천/비추천 (로그인한 정식 회원만, 한 사람 한 표, 같은 버튼 다시 누르면 취소, 내 빌드는 못 누름). 운영자 [빌드 숨기기]는 ⋮ 메뉴 (Matchup).
 * SPEC 6-79: 눌러도 못 하는 경우에는 버튼을 끄지 않고(aria-disabled) 눌렀을 때 이유를 화면 글로 보여 준다.
 * 로그인·닉네임이 필요하면 안내를 먼저 보여 주고 잠깐(GO_DELAY_MS) 뒤에 그 화면으로 보낸다.
 * 066 [저장]: 같은 줄 비추천 버튼 오른쪽 책갈피. 누르면 저장, 다시 누르면 해제(나만 봄). 로그인·닉네임 안내는 추천과 같고, 비회원·내 빌드도 저장할 수 있다.
 */
function BuildActions({ build, onVoted }) {
  const auth = useAuth();
  const navigate = useNavigate();
  const location = useLocation();
  const [votes, setVotes] = useState({ up: build.up, down: build.down, mine: build.mine ?? null });
  const [busy, setBusy] = useState(false);
  const [saved, setSaved] = useState(!!build.saved);
  const [saving, setSaving] = useState(false);
  const [notice, showNotice, clearNotice] = useVoteNotice();
  const [announce, setAnnounce] = useState('');
  const [guestHint, setGuestHint] = useState(false);
  const going = useRef(null);
  useEffect(() => {
    return () => clearTimeout(going.current);
  }, []);
  const signedIn = auth.status === 'signedIn';
  const own = signedIn && build.author_id === auth.user.id;
  const closed = !!build.status && build.status !== 'approved'; // 공개 중이 아닌 빌드(서버가 거절) — 상대법 화면에는 원래 안 나온다
  const score = votes.up - votes.down;

  const goAfterNotice = (text, to) => {
    showNotice({ kind: 'info', text });
    if (going.current) return; // 이미 이동하는 중
    going.current = setTimeout(() => navigate(to, { state: { from: location.pathname + '#builds' } }), GO_DELAY_MS);
  };

  const vote = async (value) => {
    if (busy || going.current) return;
    if (!signedIn) return goAfterNotice(`${MSG.login} 로그인 화면으로 이동합니다.`, '/login');
    if (!canWrite(auth)) return goAfterNotice(`${MSG.nickname} 닉네임 정하기로 이동합니다.`, '/welcome');
    if (own) return showNotice({ kind: 'info', text: MSG.ownBuild });
    if (closed) return showNotice({ kind: 'info', text: MSG.notPublic });
    if (isGuest(auth)) {
      setGuestHint(true); // 비회원은 추천·비추천 불가 (DB 트리거도 막는다)
      return undefined;
    }
    setBusy(true);
    clearNotice();
    setGuestHint(false);
    try {
      const cancel = votes.mine === value;
      const next = await voteBuild(build.id, cancel ? null : value);
      setVotes({ up: next.up, down: next.down, mine: next.mine ?? null });
      setAnnounce(`${value === 1 ? '추천' : '비추천'}${cancel ? '을 취소했습니다' : '했습니다'}.`);
      onVoted?.(build.id, { up: next.up, down: next.down, mine: next.mine ?? null }); // 6-79: 빌드 탭·[더보기] 창의 추천 수도 같이
    } catch (e) {
      showNotice({ kind: 'error', text: voteErrorText(e) });
    } finally {
      setBusy(false);
    }
    return undefined;
  };

  const toggleSave = async () => {
    if (saving || going.current) return undefined;
    if (!signedIn) return goAfterNotice(`${SAVE_MSG.login} 로그인 화면으로 이동합니다.`, '/login');
    if (!canWrite(auth)) return goAfterNotice(`${SAVE_MSG.nickname} 닉네임 정하기로 이동합니다.`, '/welcome');
    if (closed && !saved) return showNotice({ kind: 'info', text: SAVE_MSG.notPublic });
    setSaving(true);
    clearNotice();
    try {
      const next = saved ? await unsaveBuild(build.id) : await saveBuild(build.id);
      setSaved(!!next?.saved);
      setAnnounce(next?.saved ? SAVE_MSG.saved : SAVE_MSG.unsaved);
      onVoted?.(build.id, { saved: !!next?.saved }); // 다른 빌드를 봤다가 돌아와도 그대로
    } catch (e) {
      showNotice({ kind: 'error', text: e.message });
    } finally {
      setSaving(false);
    }
    return undefined;
  };

  const unavailable = own || closed;
  const cls = (on, down) => ['vote', on && 'on', on && down && 'down', unavailable && 'is-disabled'].filter(Boolean).join(' ');
  return (
    <>
      <div className="votes">
        <button
          type="button"
          className={cls(votes.mine === 1, false)}
          aria-pressed={votes.mine === 1}
          aria-label={`추천 ${votes.up}`}
          aria-disabled={unavailable || undefined}
          onClick={() => vote(1)}
          disabled={busy}
        >
          <ThumbIcon /> {votes.up}
        </button>
        <button
          type="button"
          className={cls(votes.mine === -1, true)}
          aria-pressed={votes.mine === -1}
          aria-label={`비추천 ${votes.down}`}
          aria-disabled={unavailable || undefined}
          onClick={() => vote(-1)}
          disabled={busy}
        >
          <ThumbIcon down /> {votes.down}
        </button>
        <button
          type="button"
          className={saved ? 'vote bookmark on' : 'vote bookmark'}
          aria-pressed={saved}
          aria-label="빌드 저장"
          onClick={toggleSave}
          disabled={saving}
        >
          <BookmarkIcon filled={saved} /> <span className="bookmark-text" aria-hidden="true">{saved ? '저장됨' : '저장'}</span>
        </button>
        {own && <span className="own-badge">내 빌드</span>}
        <span className={score > 0 ? 'score plus' : score < 0 ? 'score minus' : 'score'}>점수 {score > 0 ? `+${score}` : score}</span>
      </div>
      <span className="sr-only" role="status">{announce}</span>
      <VoteNotice notice={notice} />
      {guestHint && <GuestHint what="추천·비추천을 누를" />}
    </>
  );
}
