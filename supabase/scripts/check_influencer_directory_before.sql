-- =====================================================================
-- 070(공개 장인 목록 influencer_directory) 실행 "전" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 070을 실행하기 전에 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~2번: [지금 값]이 [정상 값]과 맞으면 070을 실행해도 된다. 다르면 실행하지 말고 알려 주세요.
--   - 3~7번은 "적어 둘 값"이다. 070 실행 뒤 check_influencer_directory_after.sql의 같은 이름 줄과 같아야 한다(070은 함수 하나만 더한다).
--   - 100번부터는 장인 한 명씩 search_influencers가 돌려주는 팔로워 수·빌드 수다(팔로워 많은 순). 실행 뒤 표의 100번부터와 같아야 한다.
--     (그 사이 누가 팔로우하거나 빌드를 올리면 달라질 수 있다 - 사람이 적은 시간에 이어서 실행해 주세요.)
--   - 함수 본문 지문은 줄바꿈 CR을 뺀 값으로 계산한다(SQL Editor가 CRLF로 붙여 넣어도 같은 값 - c5333b1과 같은 방식).
-- =====================================================================
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '069 실행됨 (표 user_warnings / 함수 search_influencers·nickname_key / profiles.photo_path 칸)' as what,
    coalesce(to_regclass('public.user_warnings')::text, '없음')
      || ' / ' || coalesce(to_regprocedure('public.search_influencers(text, integer)')::text, '없음')
      || ' · ' || coalesce(to_regprocedure('public.nickname_key(text)')::text, '없음')
      || ' / ' || (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'profiles' and column_name = 'photo_path') as now_value,
    'user_warnings / search_influencers(text,integer) · nickname_key(text) / 1' as ok_value, '없음이 있으면 앞 번호부터 실행' as memo
  union all select 2, '070 아직 안 함 (influencer_directory 함수 수)',
    (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'influencer_directory')::text,
    '0', '1이면 070을 이미 실행한 것 - 다시 실행하지 말고 알려 주세요'
  union all select 3, '적어 둘 값: 장인 수 (장인 전체 / 그중 닉네임 있음 / 장인인데 닉네임 없음)',
    (select count(*) || ' / ' || count(*) filter (where nickname is not null) || ' / ' || count(*) filter (where nickname is null)
       from public.profiles where influencer is not null),
    '(이 값을 적어 둠)', '셋째 값은 0이 정상(닉네임 없는 장인은 목록·검색에 안 나온다)'
  union all select 4, '적어 둘 값: 일반 사용자가 부를 수 있는 쓰기 함수 수 (volatile, 트리거 아님 - 068 빠뜨림 방지 검사 대상)',
    (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.prokind = 'f' and p.provolatile = 'v' and p.prorettype <> 'trigger'::regtype
        and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute')))::text,
    '(이 값을 적어 둠)', '070은 읽기 함수(stable)라 늘지 않는다'
  union all select 5, '적어 둘 값: 기존 장인 관련 공개 함수 4개 (본문·보안·search_path 지문, 본문 줄바꿈 CR은 빼고)',
    (select count(*) || ' / ' || md5(string_agg(p.proname || '(' || oidvectortypes(p.proargtypes) || ')' || replace(p.prosrc, E'\r', '') || p.prosecdef::text || coalesce(array_to_string(p.proconfig, ','), ''), '|' order by p.proname, oidvectortypes(p.proargtypes)))
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in ('search_influencers', 'influencer_builds', 'influencer_follower_count', 'nickname_key')),
    '(이 값을 적어 둠)', '옛 앱이 쓰는 함수 - 070은 고치지 않는다'
  union all select 6, '적어 둘 값: 위 4개 함수의 실행 권한 (비로그인·로그인 부를 수 있는 것)',
    (select string_agg(p.proname || ':' || has_function_privilege('anon', p.oid, 'execute')::text || '·' || has_function_privilege('authenticated', p.oid, 'execute')::text, ', ' order by p.proname)
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in ('search_influencers', 'influencer_builds', 'influencer_follower_count', 'nickname_key')),
    '(이 값을 적어 둠)', null
  union all select 7, '적어 둘 값: 프로필 / 빌드 / 팔로우 (각 줄 수 · 내용 지문 앞 12자리, 프로필은 마지막 접속 시각 빼고)',
    (select count(*) || '·' || left(md5(coalesce(string_agg((to_jsonb(p) - 'last_seen_at')::text, '|' order by p.id), '')), 12) from public.profiles p)
      || ' / ' || (select count(*) || '·' || left(md5(coalesce(string_agg(b::text, '|' order by b.id), '')), 12) from public.builds b)
      || ' / ' || (select count(*) || '·' || left(md5(coalesce(string_agg(f::text, '|' order by f.follower_id::text, f.influencer_id::text), '')), 12) from public.influencer_follows f),
    '(이 값을 적어 둠)', '그 사이 사이트 활동이 있으면 달라질 수 있음'
  -- 100번부터: 장인 한 명씩 (search_influencers 결과 그대로 - 자기 닉네임으로 찾으면 정확히 맞는 사람이 맨 앞에 온다)
  union all
  select 100 + row_number() over (order by (s ->> 'follower_count')::int desc, p.nickname, p.id)::int,
    '장인: ' || p.nickname || ' (' || p.influencer || ')',
    '팔로워 ' || coalesce(s ->> 'follower_count', '?') || ' · 빌드 ' || coalesce(s ->> 'build_count', '?'),
    '(이 값을 적어 둠)', case when s is null then 'search_influencers에서 못 찾음 - 알려 주세요' end
    from public.profiles p
    left join lateral (select e as s from jsonb_array_elements(public.search_influencers(left(p.nickname, 20)) -> 'items') e where e ->> 'id' = p.id::text) x on true
   where p.influencer is not null and p.nickname is not null
) x
order by ord;
