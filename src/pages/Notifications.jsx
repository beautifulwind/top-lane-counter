import { useEffect, useState } from 'react';
import { Link, Navigate } from 'react-router-dom';
import { getChampionMap } from '../api/ddragon';
import { getNotifications, markAllNotificationsRead } from '../api/notifications';
import { getMyTitleBook } from '../api/rewards';
import { useAuth } from '../lib/auth';
import { describeNotification, noticeTime } from '../lib/notifications';
import { fmtDateTime } from '../lib/format';
import { useAsync } from '../lib/useAsync';
import { ErrorBox, Loading } from '../components/Status';
import TitleMedal, { titleColorClass, titleColorStyle } from '../components/TitleMedal';
import {
  BanIcon, BellIcon, CheckCircleIcon, EyeIcon, EyeOffIcon, FlagIcon, LayersIcon, MessageIcon, TrendingUpIcon, UsersIcon,
} from '../components/Icons';

const ICONS = {
  check: CheckCircleIcon, ban: BanIcon, hidden: EyeOffIcon, shown: EyeIcon, flag: FlagIcon,
  comment: MessageIcon, level: TrendingUpIcon, bell: BellIcon, build: LayersIcon, // build: 050 팔로우한 장인의 새 빌드
  users: UsersIcon, // users: 052 장인 새 팔로워
};

/**
 * 알림 (/notifications, SPEC 6-17): 내 알림 전부 최신순 한 줄씩, 20개씩 [더 보기].
 * 열면 이 화면 맨 위 알림까지 안 읽은 알림을 한 번에 읽음 처리 → ☰·[알림]의 빨간 점이 꺼진다.
 * "새" 표시는 이번 방문 동안 남는다 (안 읽었던 것 + 이번에 읽음 처리한 것). 로그인한 사람만 (비회원 포함, 닉네임 전도 볼 수 있음)
 */
export default function Notifications() {
  const auth = useAuth();
  if (auth.status === 'loading') return <Loading />;
  if (auth.status === 'signedOut') return <Navigate to="/login" replace state={{ from: '/notifications' }} />;
  return (
    <article className="notifications-page">
      <h1 className="doc-title page-title"><BellIcon size={26} className="title-icon" /> 알림</h1>
      <NotificationList userId={auth.user.id} />
    </article>
  );
}

function NotificationList({ userId }) {
  const { data, error, loading, retry } = useAsync(async () => {
    // 칭호 알림의 훈장은 도감(한정판 포함)에서 — 못 읽어도 알림은 보인다(예전 6개 훈장으로)
    const [champs, page, book] = await Promise.all([getChampionMap(), getNotifications(userId), getMyTitleBook().then((b) => b.items, () => [])]);
    return { champs, book, ...page };
  }, [userId]);
  // [더 보기]로 이어 붙인 알림 (처음 목록을 다시 불러오면 비운다)
  const [extra, setExtra] = useState({ base: null, rows: [], more: false });
  const [busy, setBusy] = useState(false);
  const [moreError, setMoreError] = useState(null);
  const [markedAt, setMarkedAt] = useState(null);

  useEffect(() => {
    if (!data) return;
    // 화면에 보였다 = 확인했다 → 맨 위 알림까지 모두 읽음 (실패하면 다음에 다시)
    if (data.rows.some((n) => !n.read_at)) markAllNotificationsRead(data.rows[0].id).then(setMarkedAt, () => {});
  }, [data]);

  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  const ext = extra.base === data ? extra : { base: data, rows: [], more: data.more };
  const rows = [...data.rows, ...ext.rows];
  if (rows.length === 0) return <p className="empty">아직 받은 알림이 없습니다.</p>;

  const name = (id) => data.champs[id]?.name ?? id;
  const isNew = (n) => !n.read_at || (markedAt && new Date(n.read_at).getTime() >= new Date(markedAt).getTime());
  const loadMore = async () => {
    setBusy(true);
    setMoreError(null);
    try {
      const page = await getNotifications(userId, rows[rows.length - 1].id);
      setExtra({ base: data, rows: [...ext.rows, ...page.rows], more: page.more });
    } catch (e) {
      setMoreError(e.message);
    }
    setBusy(false);
  };

  return (
    <>
      <ul className="noti-list" aria-label="알림 목록">
        {rows.map((n) => <NotificationRow key={n.id} n={n} fresh={isNew(n)} name={name} book={data.book} />)}
      </ul>
      {ext.more && (
        <div className="actions center">
          <button type="button" className="btn" onClick={loadMore} disabled={busy}>{busy ? '불러오는 중…' : '더 보기'}</button>
        </div>
      )}
      {moreError && <p className="form-error" role="alert">{moreError}</p>}
      <p className="hint noti-keep">알림은 90일 동안 보관됩니다.</p>
    </>
  );
}

function NotificationRow({ n, fresh, name, book }) {
  const d = describeNotification(n, name, book);
  const Icon = ICONS[d.icon];
  const body = (
    <>
      <span
        className={`noti-icon ${d.icon}${d.titleKey ? ` title-color ${titleColorClass(d.titleItem)}` : ''}`}
        style={d.icon === 'medal' ? titleColorStyle(d.titleItem) : undefined} aria-hidden="true"
      >
        {d.icon === 'medal' ? <TitleMedal item={d.titleItem} box={[26, 29]} /> : <Icon size={20} />}
      </span>
      <span className="noti-body">
        <span className="noti-title">
          {fresh && <span className="new-badge">새</span>}
          {d.title}
        </span>
        {d.subject && <span className="noti-subject">{d.subject}</span>}
        {d.detail && <span className="noti-detail">{d.detail}</span>}
      </span>
      <time className="noti-time" dateTime={n.created_at} title={fmtDateTime(n.created_at)}>{noticeTime(n.created_at)}</time>
    </>
  );
  return (
    <li className={`noti-row${fresh ? ' new' : ''}`}>
      {d.to ? <Link to={d.to} className="noti-main">{body}</Link> : <div className="noti-main">{body}</div>}
    </li>
  );
}
