import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { setMainTitle } from '../api/rewards';
import { useAuth } from '../lib/auth';
import { levelProgress } from '../lib/levels';
import { fmtDate, fmtDateTime } from '../lib/format';
import { SparklesIcon } from './Icons';
import TitleMedal, { titleColorClass, titleColorStyle } from './TitleMedal';

/**
 * /me 레벨·칭호 (SPEC 6장): LevelBar = 프로필 카드 안의 큰 "Lv.N" + 다음 레벨까지 막대와 작은 숫자 "현재 / 목표",
 * MyTitles = 그 아래 칭호판(훈장) 카드.
 * 제목("Level")·"경험치" 글자는 없다 (2026-11-04).
 * rewards = getMyRewards() 결과. 레벨·칭호 알림은 알림 화면(/notifications)에서 본다 (027)
 * 지급·회수·레벨은 DB가 정한다. 여기서 바꾸는 건 대표 칭호뿐. 칭호판은 my_title_book() 도감 하나로 그린다 (053, SPEC 6-3).
 */
export function LevelBar({ rewards }) {
  const auth = useAuth();
  const p = levelProgress(rewards.xp ?? 0, rewards.levels, rewards.rules.level_step);
  // 상단 닉네임은 로그인할 때 불러온 값 → 여기서 새로 읽은 레벨·대표 칭호(회수되면 비워짐)로 맞춘다
  const { profile, setProfile } = auth;
  useEffect(() => {
    if (profile && (profile.level !== rewards.level || profile.xp !== rewards.xp || profile.main_title !== rewards.main_title)) {
      setProfile({ ...profile, level: rewards.level, xp: rewards.xp, main_title: rewards.main_title });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps -- 새로 불러왔을 때 한 번만
  }, [rewards]);

  return (
    <section className="me-level" aria-label="레벨">
      <p className="lv-big">Lv.{rewards.level}</p>
      <div className="me-level-bar">
        <div
          className="xp-bar" role="progressbar" aria-label={`Lv.${p.level + 1}까지`}
          aria-valuemin={p.from} aria-valuemax={p.to} aria-valuenow={p.xp}
        >
          <span style={{ width: `${p.percent}%` }} />
        </div>
        <p className="xp-nums"><span className="sr-only">경험치 </span>{p.xp.toLocaleString()} / {p.to.toLocaleString()}</p>
      </div>
    </section>
  );
}

/** 접었을 때 보이는 훈장 수 (5개씩 2줄) */
const COLLAPSED = 10;
const SECRET = '???';

/**
 * 칭호 칸 (프로필 카드 아래): 제목 "칭호" + 얻은 수 알약(활동 칭호만 센다) + 도감.
 * book = getMyTitleBook() 결과 (운영자 계정도 받는다 — 칭호가 없어 전부 흐리게 나온다)
 */
export default function MyTitles({ book }) {
  const auth = useAuth();
  const items = book.items;
  const activity = items.filter((t) => t.kind === 'activity');
  const special = items.filter((t) => t.kind !== 'activity');
  const total = activity.length;
  const ownedCount = activity.filter((t) => t.owned).length;
  return (
    <section className="me-section me-card" aria-labelledby="my-titles">
      <div className="sub-head">
        <h2 id="my-titles"><SparklesIcon size={18} className="title-icon" /> 칭호</h2>
        <span className="count-badge" aria-label={`칭호 ${total}개 중 ${ownedCount}개 얻음`}>{ownedCount} / {total}</span>
      </div>
      <TitleBoard activity={activity} special={special} current={auth.profile?.main_title ?? null} />
    </section>
  );
}

/** 훈장 한 칸의 지금 모습: 장인은 인증 여부(auth.profile.influencer)로, 나머지는 도감의 owned로 */
const isOwned = (t, profile) => (t.kind === 'influencer' ? !!profile?.influencer : t.owned);

/**
 * 칭호판: 활동 칭호 훈장을 가로 5개씩, 그 아래 "특별 칭호"(장인·한정판). 얻은 것은 칭호색, 못 얻은 것은 흐리게, 대표 칭호는 테두리 + "대표".
 * 접으면 훈장 2줄(10개)만, [더보기]/[접기].
 * 말풍선(이름·얻는 방법·기간·얻은 날짜): 마우스를 올리거나 Tab으로 오면 보기만, 누르면(탭) 고정되고 활동 칭호를 얻었으면 [대표로 설정]/[대표 해제].
 * 비밀 칭호를 못 얻었으면 "???"만. 닫기: 다시 누르기, 바깥 누르기, Esc.
 */
function TitleBoard({ activity, special, current }) {
  const auth = useAuth();
  const [pinned, setPinned] = useState(null);
  const [peek, setPeek] = useState(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const [pos, setPos] = useState(null);
  const [expanded, setExpanded] = useState(false);
  const boardRef = useRef(null);
  const popRef = useRef(null);

  const all = [...activity, ...special];
  const foldable = all.length > COLLAPSED;
  const open = expanded || !foldable;
  const shownActivity = open ? activity : activity.slice(0, COLLAPSED);
  const shownSpecial = open ? special : special.slice(0, Math.max(0, COLLAPSED - shownActivity.length));
  const visibleKeys = [...shownActivity, ...shownSpecial].map((t) => t.key);
  // 접혀서 안 보이는 훈장의 말풍선은 닫는다
  const pinnedKey = pinned && visibleKeys.includes(pinned) ? pinned : null;
  const peekKey = peek && visibleKeys.includes(peek) ? peek : null;
  const shown = pinnedKey ?? peekKey;
  const shownItem = shown ? all.find((t) => t.key === shown) : null;
  const limitedCount = special.filter((t) => t.kind === 'limited').length;

  // 고정된 말풍선: 바깥 누르기·Esc로 닫기
  useEffect(() => {
    if (!pinnedKey) return undefined;
    const onDown = (e) => { if (!boardRef.current?.contains(e.target)) setPinned(null); };
    const onKey = (e) => {
      if (e.key !== 'Escape') return;
      setPinned(null);
      setPeek(null);
      boardRef.current?.querySelector(`[data-title="${pinnedKey}"]`)?.focus();
    };
    document.addEventListener('pointerdown', onDown);
    document.addEventListener('keydown', onKey);
    return () => { document.removeEventListener('pointerdown', onDown); document.removeEventListener('keydown', onKey); };
  }, [pinnedKey]);

  // 말풍선 자리: 훈장 바로 아래, 칭호판 밖으로 나가지 않게 좌우를 맞춘다 (꼬리는 훈장 가운데)
  useLayoutEffect(() => {
    if (!shown || !boardRef.current || !popRef.current) { setPos(null); return; }
    const board = boardRef.current.getBoundingClientRect();
    const btn = boardRef.current.querySelector(`[data-title="${shown}"]`).getBoundingClientRect();
    const w = popRef.current.offsetWidth;
    const center = btn.left - board.left + btn.width / 2;
    const left = Math.max(0, Math.min(center - w / 2, board.width - w));
    setPos({ top: btn.bottom - board.top + 10, left, arrow: center - left });
  }, [shown, expanded]);

  const choose = async (key) => {
    setBusy(true);
    setError(null);
    try {
      const profile = await setMainTitle(auth.user.id, key);
      if (profile) auth.setProfile(profile);
    } catch (e) {
      setError(e.message);
    }
    setBusy(false);
  };

  const medalButton = (t) => {
    const owned = isOwned(t, auth.profile);
    const main = current === t.key;
    const hiddenSecret = t.secret && !owned;
    const ended = t.kind === 'limited' && !owned && t.period === 'ended';
    const name = hiddenSecret ? SECRET : t.name;
    const label = `${name}${owned ? '' : ' (아직 못 얻음)'}${ended ? ' (종료)' : ''}${main ? ' (대표 칭호)' : ''}`;
    return (
      <li key={t.key}>
        <button
          type="button" data-title={t.key} aria-label={label}
          className={['medal', titleColorClass(t), t.kind === 'limited' ? 'limited' : '', owned ? 'owned' : 'locked', main ? 'main' : ''].filter(Boolean).join(' ')}
          style={titleColorStyle(t)}
          aria-expanded={pinnedKey === t.key} aria-describedby={shown === t.key ? 'medal-pop' : undefined}
          onClick={() => { setError(null); if (pinnedKey === t.key) { setPinned(null); setPeek(null); } else setPinned(t.key); }}
          onMouseEnter={() => setPeek(t.key)} onMouseLeave={() => setPeek(null)}
          onFocus={() => setPeek(t.key)} onBlur={() => setPeek(null)}
        >
          <span className="medal-art"><TitleMedal item={t} secret={hiddenSecret} /></span>
          <span className="medal-name">{name}</span>
          {ended && <span className="medal-end" aria-hidden="true">종료</span>}
          {main && <span className="medal-main-tag" aria-hidden="true">대표</span>}
        </button>
      </li>
    );
  };

  const popOwned = shownItem && isOwned(shownItem, auth.profile);
  const popSecret = shownItem && shownItem.secret && !popOwned;
  const popDate = !shownItem ? null : shownItem.kind === 'influencer' ? (auth.profile?.influencer_at ?? shownItem.earned_at) : shownItem.earned_at;
  return (
    <div className="title-board" ref={boardRef}>
      <ul className="medal-grid" aria-label="칭호판">{shownActivity.map(medalButton)}</ul>
      {(shownSpecial.length > 0 || (limitedCount === 0 && open)) && <h3 className="medal-group">특별 칭호</h3>}
      {shownSpecial.length > 0 && <ul className="medal-grid" aria-label="특별 칭호">{shownSpecial.map(medalButton)}</ul>}
      {limitedCount === 0 && open && <p className="hint medal-soon">한정판 칭호는 준비 중입니다.</p>}
      {foldable && (
        <div className="actions center">
          <button type="button" className="btn btn-small" aria-expanded={expanded} onClick={() => setExpanded(!expanded)}>{expanded ? '접기' : '더보기'}</button>
        </div>
      )}
      {shownItem && (
        <div
          id="medal-pop" ref={popRef} role={pinnedKey ? 'group' : 'tooltip'} aria-label={pinnedKey ? `칭호 ${popSecret ? SECRET : shownItem.name}` : undefined}
          className={`medal-pop ${titleColorClass(shownItem)}`} style={pos ? { ...titleColorStyle(shownItem), top: pos.top, left: pos.left, '--arrow': `${pos.arrow}px` } : { ...titleColorStyle(shownItem), visibility: 'hidden' }}
        >
          <p className="medal-pop-name">{popSecret ? SECRET : shownItem.name}</p>
          {!popSecret && shownItem.description && <p className="medal-pop-desc">{shownItem.description}</p>}
          <p className="medal-pop-cond">{popSecret ? '얻는 방법은 비밀입니다.' : shownItem.how_to}</p>
          {shownItem.kind === 'limited' && (
            <p className="medal-pop-period">
              한정판 · {shownItem.period === 'ended' ? '종료' : shownItem.period === 'upcoming' ? '시작 전' : '진행 중'}
              {(shownItem.starts_at || shownItem.ends_at) && ` (${shownItem.starts_at ? fmtDate(shownItem.starts_at) : '처음'} ~ ${shownItem.ends_at ? fmtDate(shownItem.ends_at) : '계속'})`}
            </p>
          )}
          <p className="medal-pop-date">
            {popOwned ? `${fmtDateTime(popDate)} ${shownItem.kind === 'influencer' ? '인증' : '얻음'}`.trim() : '아직 못 얻음'}
          </p>
          {pinnedKey === shown && popOwned && shownItem.equippable && (
            current === shown
              ? <button type="button" className="btn btn-small" disabled={busy} onClick={() => choose(null)}>대표 해제</button>
              : <button type="button" className="btn btn-primary btn-small" disabled={busy} onClick={() => choose(shown)}>대표로 설정</button>
          )}
          {error && <p className="form-error" role="alert">{error}</p>}
        </div>
      )}
    </div>
  );
}
