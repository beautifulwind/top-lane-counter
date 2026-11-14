-- =====================================================================
-- 057: 경험치 설정 메모(xp_rules.note)의 옛 이름 "자유게시판" -> "탑신병자 커뮤니티" (SPEC 6-52)
--
-- 바뀌는 것: xp_rules.note 11줄 안의 글자 "자유게시판"만 "탑신병자 커뮤니티"로 바꾼다. 문구의 다른 부분은 그대로.
--   바뀌는 줄(key): post, post_daily_cap, comment, comment_daily_cap, post_interval, comment_interval,
--                   post_edit_minutes, comment_edit_minutes, media_post_max, media_post_gif_max, media_comment_max
--   value(숫자) 칸, 다른 key의 메모, 다른 표는 건드리지 않는다. 함수/표 구조/알림 문장/pg_cron 변경 없음. Edge Function 재배포 없음.
--   조사: 11줄 모두 "자유게시판" 바로 뒤가 띄어쓰기라 조사(은/는, 이/가, 을/를 등)가 어색해지는 줄은 없다.
--   여러 번 실행해도 결과는 같다(두 번째부터는 0줄). 실행 뒤 NOTICE에 바꾼 줄 수가 나온다(11줄이어야 함).
-- 실행 전 supabase/scripts/check_board_name_before.sql, 실행 뒤 check_board_name_after.sql.
-- 다른 표/설명에 남은 "자유게시판"은 supabase/scripts/check_board_name_find.sql로 찾는다(읽기만, 이 파일은 고치지 않음).
--
-- >> 되돌리기 (rollback) - 문제가 생기면 SQL Editor에서 아래를 한 번에 실행한다. 056 상태의 문구로 돌아간다.
--    같은 11줄에서 "탑신병자 커뮤니티"를 "자유게시판"으로 되돌릴 뿐이라 다른 글자는 바뀌지 않는다.
--    (check_board_name_before.sql 실행 전에 그 줄에 "탑신병자 커뮤니티"가 이미 있었다면 이 되돌리기는 그 글자도 바꾼다 - 그때는 아래 원래 문구로 직접 되돌릴 것)
--     begin;
--     update public.xp_rules set note = replace(note, '탑신병자 커뮤니티', '자유게시판')
--      where key in ('post', 'post_daily_cap', 'comment', 'comment_daily_cap', 'post_interval', 'comment_interval',
--                    'post_edit_minutes', 'comment_edit_minutes', 'media_post_max', 'media_post_gif_max', 'media_comment_max')
--        and note like '%탑신병자 커뮤니티%';
--     commit;
--
--    원래 문구 목록 (014~024 마이그레이션을 따라가 계산한 값. 실제 DB 값은 check_board_name_before.sql의 11~21번 줄에 그대로 나오니 그 결과를 적어 두면 가장 정확하다)
--      post                 자유게시판 글
--      post_daily_cap       자유게시판 글 하루 상한
--      comment              자유게시판 댓글 + 문서 댓글 (합쳐서 하루 상한)
--      comment_daily_cap    댓글 경험치 하루 상한 (자유게시판 댓글 + 문서 댓글 합계)
--      post_interval        자유게시판 글 최소 간격 (초, 도배 방지)
--      comment_interval     댓글 최소 간격 (초, 자유게시판 댓글·문서 댓글 공유, 도배 방지)
--      post_edit_minutes    자유게시판 글을 고칠 수 있는 시간 (쓴 뒤 분)
--      comment_edit_minutes 자유게시판 댓글·문서 댓글을 고칠 수 있는 시간 (쓴 뒤 분)
--      media_post_max       자유게시판 글 하나에 붙일 수 있는 사진·GIF 수
--      media_post_gif_max   자유게시판 글 하나에 붙일 수 있는 GIF 수
--      media_comment_max    자유게시판 댓글 하나에 붙일 수 있는 사진·GIF 수
-- =====================================================================

begin;

do $$
declare
  n integer;
begin
  update public.xp_rules
     set note = replace(note, '자유게시판', '탑신병자 커뮤니티')
   where key in ('post', 'post_daily_cap', 'comment', 'comment_daily_cap', 'post_interval', 'comment_interval',
                 'post_edit_minutes', 'comment_edit_minutes', 'media_post_max', 'media_post_gif_max', 'media_comment_max')
     and note like '%자유게시판%';
  get diagnostics n = row_count;
  raise notice '057: xp_rules 메모 %줄 바꿈 (처음 실행이면 11줄이어야 함)', n;
end $$;

commit;
