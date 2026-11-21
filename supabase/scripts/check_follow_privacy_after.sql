-- =====================================================================
-- 063(팔로우 목록 공개 범위 줄이기) 실행 "뒤" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 063을 실행한 뒤 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~7번: [지금 값]이 [정상 값]과 모두 맞아야 한다. 하나라도 다르면 알려 주세요.
--   - 8~11번: 실행 전 check_follow_privacy_before.sql의 6~9번에 적어 둔 값과 같아야 한다.
-- =====================================================================
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '함수 모양 그대로 (4개)' as what,
    (select string_agg(p.oid::regprocedure::text, ' / ' order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in ('influencer_followers', 'influencer_followers_unchecked', 'my_following', 'my_following_unchecked')) as now_value,
    'influencer_followers(uuid,integer) / influencer_followers_unchecked(uuid,integer) / my_following(integer) / my_following_unchecked(uuid,integer)' as ok_value,
    null as memo
  union all select 2, '팔로워 목록 바깥 함수: 게스트 거부 / 본인 아니면 운영자만 (is_admin)',
    (select (p.prosrc like '%is_guest(me)%')::text || ' / ' || (p.prosrc like '%p_user is distinct from me and not public.is_admin()%')::text
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'influencer_followers'),
    'true / true', null
  union all select 3, '내 팔로우 바깥 함수: 게스트 거부',
    (select (p.prosrc like '%is_guest(me)%')::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'my_following'),
    'true', null
  union all select 4, '응답에 팔로우한 때(followed_at) 없음 (팔로워 목록 / 내 팔로우)',
    (select string_agg((p.prosrc not like '%followed_at%')::text, ' / ' order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in ('influencer_followers_unchecked', 'my_following_unchecked')),
    'true / true', '순서는 서버 안에서만 created_at으로'
  union all select 5, '팔로워 목록에 차단 거르기 (user_blocks)',
    (select (p.prosrc like '%public.user_blocks%')::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'influencer_followers_unchecked'),
    'true', null
  union all select 6, '실행 권한 (로그인: 팔로워 목록·내 팔로우 / 비로그인: 둘 중 하나라도 / 안쪽 함수: 누구든)',
    (has_function_privilege('authenticated', 'public.influencer_followers(uuid,integer)', 'execute')
       and has_function_privilege('authenticated', 'public.my_following(integer)', 'execute'))::text
      || ' / ' || (has_function_privilege('anon', 'public.influencer_followers(uuid,integer)', 'execute')
       or has_function_privilege('anon', 'public.my_following(integer)', 'execute'))::text
      || ' / ' || (has_function_privilege('authenticated', 'public.influencer_followers_unchecked(uuid,integer)', 'execute')
       or has_function_privilege('anon', 'public.influencer_followers_unchecked(uuid,integer)', 'execute')
       or has_function_privilege('authenticated', 'public.my_following_unchecked(uuid,integer)', 'execute')
       or has_function_privilege('anon', 'public.my_following_unchecked(uuid,integer)', 'execute'))::text,
    'true / false / false', '실행 전 5번과 같음'
  union all select 7, '4개 모두 정의자 권한 (빠진 수) / search_path 고정 (빠진 수)',
    (select count(*) filter (where not p.prosecdef) || ' / ' || count(*) filter (where coalesce(array_to_string(p.proconfig, ','), '') not like '%search_path=%')
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in ('influencer_followers', 'influencer_followers_unchecked', 'my_following', 'my_following_unchecked')),
    '0 / 0', null
  union all select 8, '장인 팔로우 수', (select count(*)::text from public.influencer_follows), '(실행 전 6번과 같음)', null
  union all select 9, '차단 줄 수', (select count(*)::text from public.user_blocks), '(실행 전 7번과 같음)', null
  union all select 10, '장인 수 / 회원 수 (프로필)',
    (select count(*) filter (where influencer is not null) || ' / ' || count(*) from public.profiles), '(실행 전 8번과 같음)', null
  union all select 11, '팔로워 목록에서 빠질 줄 수 (장인과 팔로워 사이에 차단이 있는 팔로우)',
    (select count(*)::text from public.influencer_follows f
      where exists (select 1 from public.user_blocks b
                     where (b.blocker_id = f.follower_id and b.blocked_id = f.influencer_id)
                        or (b.blocker_id = f.influencer_id and b.blocked_id = f.follower_id))),
    '(실행 전 9번과 같음)', '줄은 그대로, 목록에서만 빠진다'
) rows
order by ord;
