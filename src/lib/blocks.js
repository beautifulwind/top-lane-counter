// 사용자 차단 (061, SPEC 6-67): ⋮ 메뉴의 [이 사용자 차단] 항목과 화면 문구.
// 차단하면 내 화면에서만 그 사람의 글·댓글·답글·빌드가 숨겨지고(새로고침 없이), 그 사람이 일으킨 새 알림이 오지 않는다.
// 차단당한 사람에게는 아무것도 알리지 않는다. 운영자 계정은 차단할 수 없다(DB도 막는다).
import { isBlocked } from './auth';

export const BLOCK_LABEL = '이 사용자 차단';
export const BLOCK_CONFIRM = '이 사용자의 글과 댓글이 내 화면에서 숨겨집니다. 설정에서 언제든 해제할 수 있습니다.';
export const BLOCKED_DONE = '차단했습니다. 마이페이지 > 계정 설정 > 차단한 사용자에서 언제든 해제할 수 있습니다.';
export const BLOCKED_POST = '차단한 사용자의 글입니다.';
export const BLOCKED_COMMENT = '차단한 사용자의 댓글입니다.';
export const BLOCKED_PROFILE = '차단한 사용자입니다.';
export const SETTINGS_PATH = '/me/settings';

/** [이 사용자 차단]을 보여 줄 사람인가: 작성자가 있고(탈퇴 아님), 내가 아니고, 운영자 계정이 아니고, 아직 차단하지 않았다 */
export const canOfferBlock = (auth, authorId, author) =>
  authorId != null && authorId !== auth.user?.id && author?.role !== 'admin' && !isBlocked(auth, authorId);

/**
 * ⋮ 메뉴 항목 (없으면 null — MoreMenu가 빈 항목을 거른다).
 * 로그인 전이면 확인 없이 로그인 화면으로(onLogin), 로그인했으면 메뉴 안에서 한 번 더 묻고 차단 → onDone(안내 문구 또는 오류 문구)
 */
export function blockMenuItem(auth, authorId, author, { onLogin, onDone }) {
  if (!canOfferBlock(auth, authorId, author)) return null;
  if (auth.status !== 'signedIn') return { label: BLOCK_LABEL, onSelect: onLogin };
  return {
    label: BLOCK_LABEL,
    confirm: BLOCK_CONFIRM,
    onSelect: async () => {
      try {
        await auth.block(authorId, author ?? null);
        onDone?.(BLOCKED_DONE);
      } catch (e) {
        onDone?.(e.message);
      }
    },
  };
}
