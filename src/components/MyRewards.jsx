import { useEffect, useState } from 'react';
import { setMainTitle } from '../api/rewards';
import { useAuth } from '../lib/auth';
import { levelProgress } from '../lib/levels';
import { TITLES, titleCondition, titleName } from '../lib/titles';
import { fmtDateTime } from '../lib/format';
import { TitleBadge } from './UserName';

export const REWARD_KINDS = ['level_up', 'level_down', 'title_earned', 'title_revoked'];

/**
 * /me Level (SPEC 6장): 레벨·경험치 막대와 내가 가진 칭호 (022: 경험치 내역 칸은 없앰, 없는 칭호는 안 보임).
 * rewards = getMyRewards() 결과, unread = 이번에 처음 보는 알림
 * 지급·회수·레벨은 DB가 정한다. 여기서 바꾸는 건 대표 칭호뿐.
 */
export default function MyRewards({ rewards, unread }) {
  const auth = useAuth();
  const p = levelProgress(rewards.xp ?? 0, rewards.levels, rewards.rules.level_step);
  const notices = unread.filter((n) => REWARD_KINDS.includes(n.kind));
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
      <h2 id="my-level">Level</h2>
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
    </section>
  );
}

/** 내가 가진 칭호만 (TITLES 순서). 하나를 대표 칭호로 고른다 (없음도 가능) */
function MainTitlePicker({ owned, current, rules }) {
  const auth = useAuth();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const mine = Object.keys(TITLES)
    .map((key) => ({ key, row: owned.find((t) => t.title_key === key) }))
    .filter((t) => t.row);

  if (mine.length === 0) {
    return <p className="empty">아직 가진 칭호가 없어요. 처음으로 기여가 승인되거나 자유게시판에 글·댓글을 쓰면 칭호 '탑신병자'를 받아요.</p>;
  }

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
      {mine.map(({ key, row }) => (
        <label key={key} className="title-row">
          <input type="radio" name="main-title" checked={current === key} onChange={() => choose(key)} aria-label={titleName(key)} />
          <span>
            <TitleBadge titleKey={key} />
            <small> — {titleCondition(key, rules)} · {fmtDateTime(row.earned_at)} 얻음</small>
          </span>
        </label>
      ))}
      {error && <p className="form-error" role="alert">{error}</p>}
    </fieldset>
  );
}
