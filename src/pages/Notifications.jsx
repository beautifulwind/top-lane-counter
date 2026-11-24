import { useState } from 'react';
import { Link, Navigate } from 'react-router-dom';
import { getChampionMap } from '../api/ddragon';
import { getNotifications, markAllNotificationsRead, markNotificationRead } from '../api/notifications';
import { getMyTitleBookOnce, hasTitleBookOnce } from '../api/rewards';
import { useAuth } from '../lib/auth';
import { useUnreadCount } from '../lib/unread';
import { describeNotification, noticeTime } from '../lib/notifications';
import { fmtDateTime } from '../lib/format';
import { useAsync } from '../lib/useAsync';
import { ErrorBox, Loading } from '../components/Status';
import TitleMedal, { titleColorClass, titleColorStyle } from '../components/TitleMedal';
import {
  AlertIcon, BanIcon, BellIcon, CheckCircleIcon, EyeIcon, EyeOffIcon, FlagIcon, LayersIcon, MessageIcon, TrendingUpIcon, UsersIcon,
} from '../components/Icons';

const ICONS = {
  check: CheckCircleIcon, ban: BanIcon, hidden: EyeOffIcon, shown: EyeIcon, flag: FlagIcon,
  comment: MessageIcon, level: TrendingUpIcon, bell: BellIcon, build: LayersIcon, // build: 050 팔로우한 장인의 새 빌드
  users: UsersIcon, // users: 052 장인 새 팔로워
  alert: AlertIcon, // alert: 069 운영자 경고
};

/**
 * 알림 (/notifications, SPEC 6-17, 6-90): 내 알림 전부 최신순 한 줄씩, 20개씩 [더 보기].
 * 열어도 읽음 처리하지 않는다. 알림 한 줄을 누르면 그 줄만 읽음 처리(이동은 막지 않음), 맨 위 [모두 읽음]은 빨간 점과 같은 기준(내 전체 안 읽은 알림 > 0)일 때만.
 * 읽으면 「새」 표시·색이 바로 꺼지고 ☰·[알림]의 빨간 점이 다시 센다. 로그인한 사람만 (비회원 포함, 닉네임 전도 볼 수 있음)
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
    // 도감은 같은 세션에서 한 번만 읽는다. 단, 안 읽은 칭호 알림(새로 받음·회수)이 있는데 도감이 예전에 읽은 것이면 그것만 새로 읽는다
    const cachedBook = hasTitleBookOnce(userId);
    const [champs, page, first] = await Promise.all([getChampionMap(), getNotifications(userId), getMyTitleBookOnce(userId).then((b) => b.items, () => [])]);
    const newTitle = page.rows.some((n) => !n.read_at && (n.kind === 'title_earned' || n.kind === 'title_revoked'));
    const book = cachedBook && newTitle ? await getMyTitleBookOnce(userId, { fresh: true }).then((b) => b.items, () => first) : first;
    return { champs, book, ...page };
  }, [userId]);
  // [더 보기]로 이어 붙인 알림 (처음 목록을 다시 불러오면 비운다)
  const [extra, setExtra] = useState({ base: null, rows: [], more: false });
  const [busy, setBusy] = useState(false);
  const [moreError, setMoreError] = useState(null);
  // 이 화면에서 읽음 처리한 알림 번호들 (불러온 목록의 read_at은 그대로 두고 겹쳐 본다)
  const [readIds, setReadIds] = useState(() => new Set());
  const [allUpto, setAllUpto] = useState(null); // [모두 읽음]으로 처리한 맨 위 번호
  const [markError, setMarkError] = useState(null);
  // [모두 읽음]은 헤더 빨간 점과 같은 값(내 전체 안 읽은 알림 수 > 0)으로 보인다 — 불러오지 않은 오래된 알림까지 센다
  const unreadCount = useUnreadCount(userId);

  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  const ext = extra.base === data ? extra : { base: data, rows: [], more: data.more };
  const rows = [...data.rows, ...ext.rows];
  if (rows.length === 0) return <p className="empty">아직 받은 알림이 없습니다.</p>;

  const name = (id) => data.champs[id]?.name ?? id;
  const isNew = (n) => !n.read_at && !readIds.has(n.id) && !(allUpto != null && n.id <= allUpto);
  /** 한 줄 읽음 처리: 색을 바로 끄고, 실패하면 되돌린다. 이동은 기다리지 않는다 (합쳐진 알림도 한 줄 = id 하나) */
  const readOne = (n) => {
    if (!isNew(n)) return;
    setReadIds((s) => new Set(s).add(n.id));
    markNotificationRead(n.id).catch(() => setReadIds((s) => { const x = new Set(s); x.delete(n.id); return x; }));
  };
  const readAll = async () => {
    setMarkError(null);
    try {
      await markAllNotificationsRead(data.rows[0].id);
      setAllUpto(data.rows[0].id);
    } catch (e) {
      setMarkError(e.message);
    }
  };
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
      {unreadCount > 0 && (
        <div className="actions end">
          <button type="button" className="btn btn-small" onClick={readAll}>모두 읽음</button>
        </div>
      )}
      {markError && <p className="form-error" role="alert">{markError}</p>}
      <ul className="noti-list" aria-label="알림 목록">
        {rows.map((n) => <NotificationRow key={n.id} n={n} fresh={isNew(n)} name={name} book={data.book} onRead={() => readOne(n)} />)}
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

function NotificationRow({ n, fresh, name, book, onRead }) {
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
      {d.to
        ? <Link to={d.to} className="noti-main" onClick={onRead}>{body}</Link>
        : fresh
          ? (
            // 가는 곳이 없는 알림도 안 읽은 것은 눌러서 읽음 처리 (키보드 Enter·Space)
            <div
              className="noti-main" role="button" tabIndex={0} onClick={onRead}
              onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); onRead(); } }}
            >
              {body}
            </div>
          )
          : <div className="noti-main">{body}</div>}
    </li>
  );
}
