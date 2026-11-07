// 알림 한 줄 만들기 (SPEC 6-17): 종류마다 아이콘·짧은 제목·둘째 줄·누르면 갈 곳.
// 제안·빌드 알림은 DB에 메모만 저장돼 있어 제목은 여기서 만든다. 게시판·레벨·칭호 알림은 DB 문장이 곧 제목.
import { TYPE_LABEL, fmtDateTime } from './format';
import { matchupTitle } from './josa';
import { TITLES } from './titles';

// 제안·빌드 알림: 제목, 메모 이름
const DECISION = {
  proposal_approved: { icon: 'check', title: '제안이 승인됐습니다', memo: '승인 메모' },
  proposal_rejected: { icon: 'ban', title: '제안이 거절됐습니다', memo: '거절 사유' },
  build_approved: { icon: 'check', title: '빌드가 공개됐습니다', memo: '승인 메모' },
  build_rejected: { icon: 'ban', title: '빌드가 거절됐습니다', memo: '거절 사유' },
  build_hidden: { icon: 'hidden', title: '운영진이 내 빌드를 숨겼습니다', memo: '숨긴 사유' },
  build_restored: { icon: 'shown', title: '숨겨졌던 내 빌드가 다시 공개됐습니다', memo: '메모' },
  revision_request: { icon: 'flag', title: '재검토 요청을 받았습니다', memo: '운영자 메모' },
  revision_cancelled: { icon: 'flag', title: '재검토 요청이 취소됐습니다', memo: '보낸 내용 그대로 승인 대기 중입니다. 메모' },
};
// 게시판·문서 댓글 알림: 아이콘 ("… 메모: …"는 메모를 둘째 줄로)
const BOARD_ICON = {
  post_comment: 'comment', doc_comment: 'comment',
  post_hidden: 'hidden', comment_hidden: 'hidden', doc_comment_hidden: 'hidden',
  post_restored: 'shown', comment_restored: 'shown', doc_comment_restored: 'shown',
};

/** 칭호 알림 문장("칭호 '장군'을 얻었습니다…")에서 칭호 키 */
const titleKeyIn = (message) => Object.keys(TITLES).find((k) => message?.includes(`'${TITLES[k]}'`)) ?? null;

/**
 * n = getNotifications()의 한 줄, name = 챔피언 id → 이름.
 * 돌려주는 값: { icon, title, subject(매치업 등, 없으면 null), detail(메모 등), to(없으면 null), titleKey(칭호 훈장) }
 */
export function describeNotification(n, name = (id) => id) {
  const matchup = (c) => (c ? matchupTitle(name(c.counter_champion), name(c.target_champion)) : null);
  const d = DECISION[n.kind];
  if (d) {
    const own = n.proposal_id ? n.proposal : n.build?.counter;
    const label = n.proposal_id ? (TYPE_LABEL[n.proposal?.type] ?? '제안') : '빌드';
    return {
      icon: d.icon,
      title: d.title,
      subject: own ? `[${label}] ${matchup(own)}` : null,
      detail: n.message ? `${d.memo}: ${n.message}` : null,
      to: n.proposal_id ? `/me/proposals/${n.proposal_id}` : n.build_id ? `/me/builds/${n.build_id}` : null,
    };
  }
  if (n.kind === 'level_up' || n.kind === 'level_down') return { icon: 'level', title: n.message, to: '/me' };
  if (n.kind === 'title_earned' || n.kind === 'title_revoked') {
    return { icon: 'medal', title: n.message, to: '/me', titleKey: titleKeyIn(n.message) };
  }
  if (n.kind === 'moderator_granted' || n.kind === 'moderator_revoked') {
    const [title, memo] = (n.message ?? '').split(' 메모: ');
    return { icon: 'flag', title, subject: null, detail: memo ? `메모: ${memo}` : null, to: n.kind === 'moderator_granted' ? '/admin' : null };
  }
  if (BOARD_ICON[n.kind]) {
    const [title, memo] = (n.message ?? '').split(' 메모: ');
    const docLink = n.counter?.status === 'approved'
      ? `/champion/${n.counter.target_champion}/counter/${n.counter.counter_champion}#comments` : null;
    const postLink = n.post_id && n.kind !== 'post_hidden' ? `/board/${n.post_id}` : null; // 숨긴 글은 열 수 없다
    return {
      icon: BOARD_ICON[n.kind],
      title,
      subject: n.counter ? matchup(n.counter) : null,
      detail: memo ? `메모: ${memo}` : null,
      to: n.kind.startsWith('doc_comment') ? docLink : postLink,
    };
  }
  return { icon: 'bell', title: n.message ?? '알림', to: null }; // 모르는 종류 (새 종류가 생겼을 때)
}

/** 알림 시각: 1분 안 "방금 전", 1시간 안 "N분 전", 하루 안 "N시간 전", 그보다 오래되면 날짜 */
export function noticeTime(ts, now = Date.now()) {
  const t = new Date(ts).getTime();
  const min = Math.floor((now - t) / 60000);
  if (min < 1) return '방금 전';
  if (min < 60) return `${min}분 전`;
  if (min < 60 * 24) return `${Math.floor(min / 60)}시간 전`;
  return fmtDateTime(ts).slice(0, 10);
}
