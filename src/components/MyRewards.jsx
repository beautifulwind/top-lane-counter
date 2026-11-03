import { useEffect, useState } from 'react';
import { setMainTitle } from '../api/rewards';
import { useAuth } from '../lib/auth';
import { levelProgress } from '../lib/levels';
import { TITLES, titleCondition, titleName } from '../lib/titles';
import { fmtDateTime } from '../lib/format';
import { matchupShort } from '../lib/josa';

export const REWARD_KINDS = ['level_up', 'level_down', 'title_earned', 'title_revoked'];
const KIND_LABEL = { new_counter: '새 카운터 승인', doc_edit: '문서 수정 승인', build: '빌드 승인', vote: '따봉 받음', post: '노가리방 글', comment: '노가리방 댓글', doc_comment: '문서 댓글' };
const PAGE = 30;

/**
 * /me 레벨·경험치·칭호 (SPEC 6장). rewards = getMyRewards() 결과, unread = 이번에 처음 보는 알림, champs = 챔피언 이름
 * 지급·회수·레벨은 DB가 정한다. 여기서 바꾸는 건 대표 칭호뿐.
 */
export default function MyRewards({ rewards, unread, champs }) {
  const auth = useAuth();
  const name = (id) => champs[id]?.name ?? id;
  const p = levelProgress(rewards.xp ?? 0, rewards.levels, rewards.rules.level_step);
  const notices = unread.filter((n) => REWARD_KINDS.includes(n.kind));
  const [shown, setShown] = useState(PAGE);
  // 상단 닉네임은 로그인할 때 불러온 값 → 여기서 새로 읽은 레벨·대표 칭호(회수되면 비워짐)로 맞춘다
  const { profile, setProfile } = auth;
  useEffect(() => {
    if (profile && (profile.level !== rewards.level || profile.xp !== rewards.xp || profile.main_title !== rewards.main_title)) {
      setProfile({ ...profile, level: rewards.level, xp: rewards.xp, main_title: rewards.main_title });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps -- 새로 불러왔을 때 한 번만
  }, [rewards]);

  return (
    <section className="me-section" aria-labelledby="my-level">
      <h2 id="my-level">레벨·경험치</h2>
      {notices.map((n) => (
        <p key={n.id} className="notice" role="status"><span className="new-badge">새 알림</span>{n.message}</p>
      ))}
      <p className="xp-summary">
        <strong>Lv.{rewards.level}</strong> · 경험치 {(rewards.xp ?? 0).toLocaleString()}
      </p>
      <div
        className="xp-bar" role="progressbar" aria-label={`Lv.${p.level + 1}까지`}
        aria-valuemin={p.from} aria-valuemax={p.to} aria-valuenow={p.xp}
      >
        <span style={{ width: `${p.percent}%` }} />
      </div>
      <p className="hint">다음 레벨(Lv.{p.level + 1})까지 {p.toNext.toLocaleString()} 남았어요. ({p.from.toLocaleString()} → {p.to.toLocaleString()})</p>

      <h3>칭호</h3>
      <MainTitlePicker owned={rewards.titles} current={auth.profile?.main_title ?? null} rules={rewards.rules} />

      <h3>경험치 내역</h3>
      {rewards.events.length === 0 ? (
        <p className="empty">아직 받은 경험치가 없어요. 제안·빌드가 승인되거나, 내 빌드가 따봉을 받거나, 노가리방 글·댓글·문서 댓글을 쓰면 경험치를 받아요.</p>
      ) : (
        <>
          <ul className="xp-list" aria-label="경험치 내역">
            {rewards.events.slice(0, shown).map((e) => (
              <li key={e.id} className={e.amount < 0 ? 'xp-row minus' : 'xp-row'}>
                <span className="xp-what">
                  {KIND_LABEL[e.type] ?? e.type}
                  {e.counter_champion && <> · {matchupShort(name(e.counter_champion), name(e.target_champion))}</>}
                  {e.reason && <small> ({e.reason})</small>}
                </span>
                <span className="xp-amount">{e.amount > 0 ? `+${e.amount}` : `−${-e.amount}`}</span>
                <small className="xp-when">{fmtDateTime(e.created_at)}</small>
              </li>
            ))}
          </ul>
          {rewards.events.length > shown && (
            <button type="button" className="btn btn-small" onClick={() => setShown(shown + PAGE)}>더 보기</button>
          )}
        </>
      )}
    </section>
  );
}

/** 칭호 6개: 가진 것은 대표 칭호로 고를 수 있고, 없는 것은 조건을 보여 준다 */
function MainTitlePicker({ owned, current, rules }) {
  const auth = useAuth();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const has = (key) => owned.find((t) => t.title_key === key);

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

  return (
    <fieldset className="title-picker" disabled={busy}>
      <legend>대표 칭호 (닉네임 앞에 보여요)</legend>
      <label className="title-row">
        <input type="radio" name="main-title" checked={current === null} onChange={() => choose(null)} />
        <span>없음</span>
      </label>
      {Object.keys(TITLES).map((key) => {
        const mine = has(key);
        return (
          <label key={key} className={mine ? 'title-row' : 'title-row locked'}>
            <input type="radio" name="main-title" checked={current === key} disabled={!mine} onChange={() => choose(key)} />
            <span>
              <strong>{titleName(key)}</strong>
              <small> — {titleCondition(key, rules)}{mine ? ` · ${fmtDateTime(mine.earned_at)} 얻음` : ' (아직 없음)'}</small>
            </span>
          </label>
        );
      })}
      {error && <p className="form-error" role="alert">{error}</p>}
    </fieldset>
  );
}
