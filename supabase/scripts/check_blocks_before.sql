-- =====================================================================
-- 061(사용자 차단) 실행 "전" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 061을 실행하기 전에 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~4번: [지금 값]이 [정상 값]과 모두 맞으면 061을 실행해도 된다. 하나라도 다르면 실행하지 말고 알려 주세요.
--   - 5~8번은 "적어 둘 값"이다. 061 실행 뒤 check_blocks_after.sql의 같은 이름 줄과 비교한다(같아야 한다).
--     (그 사이 사이트에서 누가 글·댓글을 쓰거나 팔로우하면 달라질 수 있다 - 사람이 적은 시간에 이어서 실행해 주세요.)
-- =====================================================================
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '060 실행됨 (빌드 댓글 표 build_comments가 없음)' as what,
    coalesce(to_regclass('public.build_comments')::text, '없음') as now_value, '없음' as ok_value, 'build_comments가 보이면 060부터 실행' as memo
  union all select 2, '차단 표 user_blocks가 아직 없음',
    coalesce(to_regclass('public.user_blocks')::text, '없음'), '없음', 'user_blocks가 보이면 061을 이미 실행한 것 - 다시 실행하지 말 것'
  union all select 3, '061이 만들 함수(my_blocked_ids·user_blocks_check·user_blocks_unfollow)가 이미 있는 수',
    (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in ('my_blocked_ids', 'user_blocks_check', 'user_blocks_unfollow')), '0', null
  union all select 4, '061이 바꿀 함수 모양 (board_page / notify_new_comment / new_follower_digest)',
    (select string_agg(p.oid::regprocedure::text, ' / ' order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in ('board_page', 'notify_new_comment', 'new_follower_digest')),
    'board_page(text,integer,integer) / new_follower_digest() / notify_new_comment(text,bigint,uuid,uuid,boolean)', null
  union all select 5, '적어 둘 값: 커뮤니티 글 수 (지우지 않은 것 / 공지)',
    (select count(*) filter (where deleted_at is null) || ' / ' || count(*) filter (where deleted_at is null and is_notice) from public.posts),
    '(이 값을 적어 둠)', '061 뒤 같아야 함 (차단한 사람이 없으니 글 목록 수도 같다)'
  union all select 6, '적어 둘 값: 알림 수 (전체 / post_comment / comment_reply / doc_comment / new_followers)',
    (select count(*) || ' / ' || count(*) filter (where kind = 'post_comment') || ' / ' || count(*) filter (where kind = 'comment_reply')
            || ' / ' || count(*) filter (where kind = 'doc_comment') || ' / ' || count(*) filter (where kind = 'new_followers')
       from public.notifications),
    '(이 값을 적어 둠)', '061 뒤 같아야 함 (061은 알림을 만들거나 지우지 않는다)'
  union all select 7, '적어 둘 값: 장인 팔로우 수',
    (select count(*)::text from public.influencer_follows), '(이 값을 적어 둠)', '061 뒤 같아야 함'
  union all select 8, '적어 둘 값: 회원 수 (프로필)',
    (select count(*)::text from public.profiles), '(이 값을 적어 둠)', '061 뒤 같아야 함'
) rows
order by ord;
