import { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { setMainTitle } from '../api/rewards';
import { useAuth } from '../lib/auth';
import { levelProgress } from '../lib/levels';
import { TITLES, titleCondition, titleName } from '../lib/titles';
import { fmtDateTime } from '../lib/format';
import { MedalIcon } from './Icons';

/**
 * /me 레벨·칭호 (SPEC 6장): 큰 "Lv.N", 다음 레벨까지 막대와 작은 숫자 "현재 / 목표", 칭호판(훈장).
 * 제목("Level")·"경험치" 글자는 없다 (2026-11-04).
 * rewards = getMyRewards() 결과. 레벨·칭호 알림은 알림 화면(/notifications)에서 본다 (027)
 * 지급·회수·레벨은 DB가 정한다. 여기서 바꾸는 건 대표 칭호뿐.
 */
export default function MyRewards({ rewards }) {
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
    <section className="me-section me-level" aria-label="레벨">
      <p className="lv-big">Lv.{rewards.level}</p>
      <div
        className="xp-bar" role="progressbar" aria-label={`Lv.${p.level + 1}까지`}
        aria-valuemin={p.from} aria-valuemax={p.to} aria-valuenow={p.xp}
      >
        <span style={{ width: `${p.percent}%` }} />
      </div>
      <p className="xp-nums"><span className="sr-only">경험치 </span>{p.xp.toLocaleString()} / {p.to.toLocaleString()}</p>

      <h3>칭호</h3>
      <TitleBoard owned={rewards.titles} current={auth.profile?.main_title ?? null} rules={rewards.rules} />
    </section>
  );
}

/**
 * 칭호판: 모든 칭호를 훈장으로 가로 5개씩 (TITLES 순서). 얻은 것은 칭호색, 못 얻은 것은 회색, 대표 칭호는 테두리 + "대표".
 * 말풍선(이름·조건·얻은 날짜): 마우스를 올리거나 Tab으로 오면 보기만, 누르면(탭) 고정되고 얻은 칭호면 [대표로 설정]/[대표 해제].
 * 닫기: 다시 누르기, 바깥 누르기, Esc.
 */
function TitleBoard({ owned, current, rules }) {
  const auth = useAuth();
  const [pinned, setPinned] = useState(null);
  const [peek, setPeek] = useState(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const [pos, setPos] = useState(null);
  const boardRef = useRef(null);
  const popRef = useRef(null);
  const shown = pinned ?? peek;

  const rowOf = (key) => owned.find((t) => t.title_key === key);

  // 고정된 말풍선: 바깥 누르기·Esc로 닫기
  useEffect(() => {
    if (!pinned) return undefined;
    const onDown = (e) => { if (!boardRef.current?.contains(e.target)) setPinned(null); };
    const onKey = (e) => {
      if (e.key !== 'Escape') return;
      const key = pinned;
      setPinned(null);
      setPeek(null);
      boardRef.current?.querySelector(`[data-title="${key}"]`)?.focus();
    };
    document.addEventListener('pointerdown', onDown);
    document.addEventListener('keydown', onKey);
    return () => { document.removeEventListener('pointerdown', onDown); document.removeEventListener('keydown', onKey); };
  }, [pinned]);

  // 말풍선 자리: 훈장 바로 아래, 칭호판 밖으로 나가지 않게 좌우를 맞춘다 (꼬리는 훈장 가운데)
  useLayoutEffect(() => {
    if (!shown || !boardRef.current || !popRef.current) { setPos(null); return; }
    const board = boardRef.current.getBoundingClientRect();
    const btn = boardRef.current.querySelector(`[data-title="${shown}"]`).getBoundingClientRect();
    const w = popRef.current.offsetWidth;
    const center = btn.left - board.left + btn.width / 2;
    const left = Math.max(0, Math.min(center - w / 2, board.width - w));
    setPos({ top: btn.bottom - board.top + 10, left, arrow: center - left });
  }, [shown]);

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

  const shownRow = shown && rowOf(shown);
  return (
    <div className="title-board" ref={boardRef}>
      <ul className="medal-grid" aria-label="칭호판">
        {Object.keys(TITLES).map((key) => {
          const row = rowOf(key);
          const main = current === key;
          const label = `${titleName(key)}${row ? '' : ' (아직 못 얻음)'}${main ? ' (대표 칭호)' : ''}`;
          return (
            <li key={key}>
              <button
                type="button" data-title={key} aria-label={label}
                className={`medal ${key} ${row ? 'owned' : 'locked'}${main ? ' main' : ''}`}
                aria-expanded={pinned === key} aria-describedby={shown === key ? 'medal-pop' : undefined}
                onClick={() => { setError(null); if (pinned === key) { setPinned(null); setPeek(null); } else setPinned(key); }}
                onMouseEnter={() => setPeek(key)} onMouseLeave={() => setPeek(null)}
                onFocus={() => setPeek(key)} onBlur={() => setPeek(null)}
              >
                <MedalIcon titleKey={key} />
                <span className="medal-name">{titleName(key)}</span>
                {main && <span className="medal-main-tag" aria-hidden="true">대표</span>}
              </button>
            </li>
          );
        })}
      </ul>
      {shown && (
        <div
          id="medal-pop" ref={popRef} role={pinned ? 'group' : 'tooltip'} aria-label={pinned ? `칭호 ${titleName(shown)}` : undefined}
          className={`medal-pop ${shown}`} style={pos ? { top: pos.top, left: pos.left, '--arrow': `${pos.arrow}px` } : { visibility: 'hidden' }}
        >
          <p className="medal-pop-name">{titleName(shown)}</p>
          <p className="medal-pop-cond">{titleCondition(shown, rules)}</p>
          <p className="medal-pop-date">{shownRow ? `${fmtDateTime(shownRow.earned_at)} 얻음` : '아직 못 얻음'}</p>
          {pinned === shown && shownRow && (
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
