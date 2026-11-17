-- =====================================================================
-- 061(사용자 차단) 실행 "뒤" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 061을 실행한 뒤 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~11번: [지금 값]이 [정상 값]과 모두 맞아야 한다. 하나라도 다르면 알려 주세요.
--   - 12~15번: 실행 전 check_blocks_before.sql의 5~8번에 적어 둔 값과 같아야 한다.
-- =====================================================================
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '차단 표 user_blocks 있음 + 줄 수' as what,
    coalesce(to_regclass('public.user_blocks')::text, '없음') || ' / ' || (select count(*) from public.user_blocks) as now_value,
    'user_blocks / 0' as ok_value, '061 직후 (아직 아무도 차단하지 않음)' as memo
  union all select 2, '기본 키 (blocker_id, blocked_id) + 자기 자신 차단 막기',
    (select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'public.user_blocks'::regclass and contype = 'p')
      || ' / ' || coalesce((select pg_get_constraintdef(oid) from pg_constraint where conname = 'user_blocks_not_self'), '없음'),
    'PRIMARY KEY (blocker_id, blocked_id) / CHECK ((blocker_id <> blocked_id))', null
  union all select 3, '두 칸 모두 프로필 참조 + 탈퇴하면 함께 지움 (cascade인 외래 키 수)',
    (select count(*)::text from pg_constraint where conrelid = 'public.user_blocks'::regclass and contype = 'f'
       and confrelid = 'public.profiles'::regclass and confdeltype = 'c'), '2', null
  union all select 4, 'RLS 켜짐 / 정책 수 (읽기·넣기·지우기)',
    (select relrowsecurity::text from pg_class where oid = 'public.user_blocks'::regclass)
      || ' / ' || (select count(*) from pg_policy where polrelid = 'public.user_blocks'::regclass),
    'true / 3', null
  union all select 5, '로그인한 사람 권한 (읽기 / 넣기 / 지우기 / 고치기)',
    has_table_privilege('authenticated', 'public.user_blocks', 'select')::text || ' / ' || has_table_privilege('authenticated', 'public.user_blocks', 'insert')::text
      || ' / ' || has_table_privilege('authenticated', 'public.user_blocks', 'delete')::text || ' / ' || has_table_privilege('authenticated', 'public.user_blocks', 'update')::text,
    'true / true / true / false', null
  union all select 6, '비로그인 권한 (읽기 / 넣기 / 지우기 / 고치기)',
    has_table_privilege('anon', 'public.user_blocks', 'select')::text || ' / ' || has_table_privilege('anon', 'public.user_blocks', 'insert')::text
      || ' / ' || has_table_privilege('anon', 'public.user_blocks', 'delete')::text || ' / ' || has_table_privilege('anon', 'public.user_blocks', 'update')::text,
    'false / false / false / false', null
  union all select 7, '트리거 (넣기 전 검사 / 넣은 뒤 팔로우 끊기)',
    (select count(*) filter (where tgname = 'user_blocks_check') || ' / ' || count(*) filter (where tgname = 'user_blocks_unfollow')
       from pg_trigger where not tgisinternal and tgrelid = 'public.user_blocks'::regclass),
    '1 / 1', null
  union all select 8, 'my_blocked_ids: 로그인 / 비로그인 실행 가능',
    has_function_privilege('authenticated', 'public.my_blocked_ids()', 'execute')::text || ' / ' || has_function_privilege('anon', 'public.my_blocked_ids()', 'execute')::text,
    'true / true', '비로그인은 빈 목록 (글 목록 함수가 부른다)'
  union all select 9, '트리거 함수는 아무도 직접 못 부름 (로그인 / 비로그인)',
    (has_function_privilege('authenticated', 'public.user_blocks_check()', 'execute') or has_function_privilege('authenticated', 'public.user_blocks_unfollow()', 'execute'))::text
      || ' / ' || (has_function_privilege('anon', 'public.user_blocks_check()', 'execute') or has_function_privilege('anon', 'public.user_blocks_unfollow()', 'execute'))::text,
    'false / false', null
  union all select 10, '바꾼 함수에 차단 거르기가 들어감 (board_page / new_follower_digest / notify_new_comment)',
    (select string_agg((p.prosrc like '%my_blocked_ids%' or p.prosrc like '%user_blocks%')::text, ' / ' order by p.proname)
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in ('board_page', 'new_follower_digest', 'notify_new_comment')),
    'true / true / true', null
  union all select 11, '새 함수·바꾼 함수가 search_path 고정 (빠진 수) + 새 함수는 정의자 권한 (빠진 수)',
    (select count(*) filter (where coalesce(array_to_string(p.proconfig, ','), '') not like '%search_path=%')
            || ' / ' || count(*) filter (where p.proname in ('my_blocked_ids', 'user_blocks_check', 'user_blocks_unfollow', 'notify_new_comment', 'new_follower_digest') and not p.prosecdef)
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in ('my_blocked_ids', 'user_blocks_check', 'user_blocks_unfollow', 'board_page', 'notify_new_comment', 'new_follower_digest')),
    '0 / 0', 'board_page는 원래대로 호출자 권한'
  union all select 12, '커뮤니티 글 수 (지우지 않은 것 / 공지)',
    (select count(*) filter (where deleted_at is null) || ' / ' || count(*) filter (where deleted_at is null and is_notice) from public.posts),
    '(실행 전 5번과 같음)', null
  union all select 13, '알림 수 (전체 / post_comment / comment_reply / doc_comment / new_followers)',
    (select count(*) || ' / ' || count(*) filter (where kind = 'post_comment') || ' / ' || count(*) filter (where kind = 'comment_reply')
            || ' / ' || count(*) filter (where kind = 'doc_comment') || ' / ' || count(*) filter (where kind = 'new_followers')
       from public.notifications),
    '(실행 전 6번과 같음)', null
  union all select 14, '장인 팔로우 수', (select count(*)::text from public.influencer_follows), '(실행 전 7번과 같음)', null
  union all select 15, '회원 수 (프로필)', (select count(*)::text from public.profiles), '(실행 전 8번과 같음)', null
) rows
order by ord;
