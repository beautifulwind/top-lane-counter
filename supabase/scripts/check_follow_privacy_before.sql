-- =====================================================================
-- 063(팔로우 목록 공개 범위 줄이기) 실행 "전" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 063을 실행하기 전에 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~5번: [지금 값]이 [정상 값]과 모두 맞으면 063을 실행해도 된다. 하나라도 다르면 실행하지 말고 알려 주세요.
--   - 6~9번은 "적어 둘 값"이다. 063 실행 뒤 check_follow_privacy_after.sql의 같은 이름 줄과 비교한다(같아야 한다).
--     (그 사이 사이트에서 누가 팔로우·차단하면 달라질 수 있다 - 사람이 적은 시간에 이어서 실행해 주세요.)
-- =====================================================================
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '062 실행됨 (프로필 사진 칸 profiles.photo_path 있음)' as what,
    (exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'profiles' and column_name = 'photo_path'))::text as now_value,
    'true' as ok_value, 'false면 062부터 실행' as memo
  union all select 2, '061 실행됨 (차단 표 user_blocks 있음)',
    coalesce(to_regclass('public.user_blocks')::text, '없음'), 'user_blocks', '063이 차단 표를 읽는다'
  union all select 3, '063이 바꿀 함수 모양 (4개)',
    (select string_agg(p.oid::regprocedure::text, ' / ' order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in ('influencer_followers', 'influencer_followers_unchecked', 'my_following', 'my_following_unchecked')),
    'influencer_followers(uuid,integer) / influencer_followers_unchecked(uuid,integer) / my_following(integer) / my_following_unchecked(uuid,integer)', null
  union all select 4, '063 아직 안 함 (팔로워 목록 함수에 게스트 검사 / 응답에 팔로우한 때 있음)',
    (select (p.prosrc like '%is_guest%')::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'influencer_followers')
      || ' / ' || (select (p.prosrc like '%followed_at%')::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'influencer_followers_unchecked'),
    'false / true', '앞이 true면 063을 이미 실행한 것 - 다시 실행해도 결과는 같지만 알려 주세요'
  union all select 5, '실행 권한 (로그인: 팔로워 목록·내 팔로우 / 비로그인: 둘 중 하나라도 / 안쪽 함수: 누구든)',
    (has_function_privilege('authenticated', 'public.influencer_followers(uuid,integer)', 'execute')
       and has_function_privilege('authenticated', 'public.my_following(integer)', 'execute'))::text
      || ' / ' || (has_function_privilege('anon', 'public.influencer_followers(uuid,integer)', 'execute')
       or has_function_privilege('anon', 'public.my_following(integer)', 'execute'))::text
      || ' / ' || (has_function_privilege('authenticated', 'public.influencer_followers_unchecked(uuid,integer)', 'execute')
       or has_function_privilege('anon', 'public.influencer_followers_unchecked(uuid,integer)', 'execute')
       or has_function_privilege('authenticated', 'public.my_following_unchecked(uuid,integer)', 'execute')
       or has_function_privilege('anon', 'public.my_following_unchecked(uuid,integer)', 'execute'))::text,
    'true / false / false', '063 뒤에도 같아야 함'
  union all select 6, '적어 둘 값: 장인 팔로우 수',
    (select count(*)::text from public.influencer_follows), '(이 값을 적어 둠)', '063 뒤 같아야 함 (063은 데이터를 바꾸지 않는다)'
  union all select 7, '적어 둘 값: 차단 줄 수',
    (select count(*)::text from public.user_blocks), '(이 값을 적어 둠)', '063 뒤 같아야 함'
  union all select 8, '적어 둘 값: 장인 수 / 회원 수 (프로필)',
    (select count(*) filter (where influencer is not null) || ' / ' || count(*) from public.profiles), '(이 값을 적어 둠)', '063 뒤 같아야 함'
  union all select 9, '적어 둘 값: 장인 본인의 팔로워 목록에서 빠질 줄 수 (장인과 팔로워 사이에 차단이 있는 팔로우)',
    (select count(*)::text from public.influencer_follows f
      where exists (select 1 from public.user_blocks b
                     where (b.blocker_id = f.follower_id and b.blocked_id = f.influencer_id)
                        or (b.blocker_id = f.influencer_id and b.blocked_id = f.follower_id))),
    '(이 값을 적어 둠)', '063 뒤에도 같은 수 (줄은 지우지 않고 장인 본인이 보는 목록에서만 뺀다)'
) rows
order by ord;
