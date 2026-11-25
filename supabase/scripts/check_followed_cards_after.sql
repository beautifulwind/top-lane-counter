-- =====================================================================
-- 079(내가 팔로우한 장인 카드 my_following_cards) 실행 "뒤" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1·2·4·5·14번은 [정상 값]과 같아야 한다(4번 N은 사람 수). 3번은 전 2번, 6~13번 「비교」는 전 3~10번과 같아야 한다.
--   - 4번은 팔로우한 회원마다 이 조회 안에서만 그 사람으로 새 함수를 불러(request.jwt.claim.sub, 조회가 끝나면 사라짐) 기대값과 개수만 비교한다.
--   - 이메일·토큰·닉네임 값은 출력하지 않는다(개수·지문만). 함수 본문 지문은 줄바꿈 CR을 뺀 값.
--   - 사이트 활동(팔로우 등)이 있으면 개수가 달라질 수 있다 - 이어서 바로 실행해 주세요.
-- =====================================================================
with
wf as (
  select p.oid, p.proname || '(' || oidvectortypes(p.proargtypes) || ')' as sig, p.prosrc
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f' and p.provolatile = 'v' and p.prorettype <> 'trigger'::regtype
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))
),
rf as (
  select p.proname || '(' || oidvectortypes(p.proargtypes) || ')' as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f' and p.provolatile in ('s', 'i') and p.prorettype <> 'trigger'::regtype
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))
),
allf as (
  select p.proname || '(' || oidvectortypes(p.proargtypes) || ')' as sig,
         p.proname || '(' || oidvectortypes(p.proargtypes) || ')' || pg_get_function_result(p.oid) || p.provolatile::text
           || replace(p.prosrc, E'\r', '') || p.prosecdef::text || coalesce(array_to_string(p.proconfig, ','), '')
           || coalesce(array_to_string(p.proacl, ','), '') as body
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind in ('f', 'p')
),
kinds as (
  select (regexp_matches(pg_get_constraintdef(oid), '''([a-z_]+)''', 'g'))[1] as k
    from pg_constraint where conname = 'notifications_kind_check' and conrelid = 'public.notifications'::regclass
  union select 'no_such_kind'
),
-- 팔로우 줄과 그 장인이 새 함수에 나올 조건(인증 있음 · 닉네임 있음 · 정지 중 아님)
fl as (
  select x.follower_id, x.influencer_id, x.created_at,
         (p.influencer is not null and p.nickname is not null
          and not exists (select 1 from public.user_restrictions r where r.user_id = p.id and r.lifted_at is null and r.ends_at > now())) as shown
    from public.influencer_follows x join public.profiles p on p.id = x.influencer_id
),
per as (
  select u.id as uid,
         (select count(*) from fl where fl.follower_id = u.id and fl.shown) as want_total,
         (select coalesce(string_agg(fl.influencer_id::text, ',' order by fl.created_at desc, fl.influencer_id), '')
            from (select * from fl where fl.follower_id = u.id and fl.shown order by fl.created_at desc, fl.influencer_id limit 20) fl) as want_ids,
         r.res
    from public.profiles u
    cross join lateral (select set_config('request.jwt.claim.sub', u.id::text, true) as s) s
    cross join lateral (select public.my_following_cards(1) as res where s.s is not null) r
   where not u.is_guest and exists (select 1 from public.influencer_follows x where x.follower_id = u.id)
)
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, 'my_following_cards 있음 · 모양 (인자 · 반환 · stable · security definer · search_path)' as what,
    coalesce((select '있음 · ' || pg_get_function_arguments(oid) || ' · ' || pg_get_function_result(oid) || ' · ' || provolatile::text || ' · ' || prosecdef::text
            || ' · ' || coalesce(array_to_string(proconfig, ','), '없음')
       from pg_proc where oid = to_regprocedure('public.my_following_cards(integer)')), '없음') as now_value,
    '있음 · p_page integer DEFAULT 1 · jsonb · s · true · search_path=""' as ok_value, null as memo
  union all select 2, '실행 권한: 로그인(authenticated) / 비로그인(anon) / public',
    (select has_function_privilege('authenticated', oid, 'execute')::text || ' / ' || has_function_privilege('anon', oid, 'execute')::text
            || ' / ' || exists (select 1 from unnest(proacl) a where a::text like '=%')::text
       from pg_proc where oid = to_regprocedure('public.my_following_cards(integer)')),
    'true / false / false', '비로그인은 부를 수 없음'
  union all select 3, '팔로우 줄 수 / 팔로우한 사람 수 / 빠지는 팔로우 줄 수',
    (select count(*) from fl) || ' / ' || (select count(distinct follower_id) from fl) || ' / ' || (select count(*) from fl where not shown),
    '(전 2번과 같음)', '데이터를 바꾸지 않음'
  union all select 4, '팔로우한 정식 회원마다 불러 본 결과: 확인한 사람 수 / total이 다른 사람 수 / 1쪽 장인 목록·순서가 다른 사람 수',
    (select count(*) || ' / ' || count(*) filter (where (res ->> 'total')::bigint <> want_total)
            || ' / ' || count(*) filter (where coalesce((select string_agg(e ->> 'id', ',' order by o) from jsonb_array_elements(res -> 'items') with ordinality e(e, o)), '') <> want_ids)
       from per),
    'N / 0 / 0', '자기 팔로우만, 최근 팔로우 순, 빠질 장인 제외 (값은 사람 수만 출력)'
  union all select 5, '돌려준 칸 이름 (모든 줄의 칸 이름 모음)',
    coalesce((select string_agg(distinct k, ',' order by k) from per, jsonb_array_elements(res -> 'items') e, jsonb_object_keys(e) k), '(줄 없음)'),
    'build_count,follower_count,id,influencer,nickname,photo_path', '이메일·가입일시·운영 정보 칸 없음'
  union all select 6, '비교: 쓰기 함수 수 (전체 / 첫 줄에 assert_can_write 검사 / 허용 목록)',
    (select count(*) from wf) || ' / '
      || (select count(*) from wf where wf.prosrc ~ '^\s*declare\s*\n\s*_can_write constant boolean := public\.assert_can_write\(\);'
                                     or wf.prosrc ~ '^\s*begin\s*\n\s*perform public\.assert_can_write\(\);')
      || ' / ' || (select count(*) from wf where exists (select 1 from public.restriction_exemptions e where e.kind = 'function' and e.name = wf.sig)),
    '(전 3번과 같음)', null
  union all select 7, '비교: 쓰기 함수 지문 (CR 뺌)',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a join wf on wf.sig = a.sig),
    '(전 4번과 같음)', null
  union all select 8, '비교: my_following_cards를 뺀 읽기 함수 수 / 지문 (CR 뺌)',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a join rf on rf.sig = a.sig where a.sig <> 'my_following_cards(integer)'),
    '(전 5번과 같음)', null
  union all select 9, '비교: my_following_cards를 뺀 public의 모든 함수 수 / 지문 (CR 뺌)',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a where a.sig <> 'my_following_cards(integer)'),
    '(전 6번과 같음)', null
  union all select 10, '비교: my_following 지문 · 속성 (인자 · 반환 · stable · security definer · 권한)',
    (select left(md5(replace(prosrc, E'\r', '')), 12) || ' · ' || pg_get_function_arguments(oid) || ' · ' || pg_get_function_result(oid) || ' · ' || provolatile::text
            || ' · ' || prosecdef::text || ' · ' || coalesce(array_to_string(proacl, ','), '기본')
       from pg_proc where oid = to_regprocedure('public.my_following(integer)')),
    '(전 7번과 같음)', null
  union all select 11, '비교: 푸시 판정 지문 - 모든 사람 × 모든 알림 종류의 push_wanted · 종류별 push_group',
    (select count(*) || ' / ' || md5(string_agg(p.id::text || ':' || k.k || ':' || public.push_wanted(p.id, k.k)::text, ',' order by p.id, k.k))
       from public.profiles p cross join kinds k)
      || ' · ' || (select count(*) || ' / ' || md5(string_agg(k || ':' || coalesce(public.push_group(k), '-'), ',' order by k)) from kinds),
    '(전 8번과 같음)', null
  union all select 12, '비교: 허용 목록(restriction_exemptions) 줄 수 / 지문 · xp_rules 줄 수 / 지문',
    (select count(*) || ' / ' || left(md5(string_agg(kind || ':' || name || ':' || reason, ',' order by kind, name)), 12) from public.restriction_exemptions)
      || ' · ' || (select count(*) || ' / ' || left(md5(string_agg(key || ':' || value || ':' || note, ',' order by key)), 12) from public.xp_rules),
    '(전 9번과 같음)', null
  union all select 13, '비교: public 트리거 수 / 지문 · 정책 수 / 지문',
    (select count(*) || ' / ' || left(md5(string_agg(tgrelid::regclass::text || pg_get_triggerdef(oid) || tgenabled::text, ',' order by tgrelid::regclass::text, tgname)), 12)
       from pg_trigger where not tgisinternal and tgrelid in (select oid from pg_class where relnamespace = 'public'::regnamespace))
      || ' · ' || (select count(*) || ' / ' || left(md5(string_agg(polrelid::regclass::text || polname || polcmd::text || coalesce(pg_get_expr(polqual, polrelid), '') || coalesce(pg_get_expr(polwithcheck, polrelid), ''), ',' order by polrelid::regclass::text, polname)), 12)
       from pg_policy where polrelid in (select oid from pg_class where relnamespace = 'public'::regnamespace)),
    '(전 10번과 같음)', null
  union all select 14, '읽기 함수 전체 수',
    (select count(*) from rf)::text,
    '67', '66 + my_following_cards'
) x
order by ord;
