-- =====================================================================
-- 080(내 챔피언 user_champions · champion_catalog · set_my_champion · my_champions · my_champion_builds) 실행 "전" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1번이 「없음 · 없음 · 없음 · 없음 · 없음」이면 실행해도 된다. 2~9번은 적어 둔다(080 뒤 check_my_champions_after.sql과 비교).
--   - 이메일·토큰·닉네임 값은 출력하지 않는다(개수·지문만). 함수 본문 지문은 줄바꿈 CR을 뺀 값.
--   - 사이트 활동이 있으면 개수가 달라질 수 있다 - 이어서 바로 실행해 주세요.
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
)
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '있음: user_champions 표 · champion_catalog 표 · set_my_champion · my_champions · my_champion_builds' as what,
    case when to_regclass('public.user_champions') is null then '없음' else '있음' end
      || ' · ' || case when to_regclass('public.champion_catalog') is null then '없음' else '있음' end
      || ' · ' || case when to_regprocedure('public.set_my_champion(text, boolean)') is null then '없음' else '있음' end
      || ' · ' || case when to_regprocedure('public.my_champions()') is null then '없음' else '있음' end
      || ' · ' || case when to_regprocedure('public.my_champion_builds(text, integer)') is null then '없음' else '있음' end as now_value,
    '없음 · 없음 · 없음 · 없음 · 없음' as ok_value, '하나라도 「있음」이면 이미 실행함 (080은 맨 앞 확인에서 멈춘다)' as memo
  union all select 2, '적어 둘 값: 쓰기 함수 수 (전체 / 첫 줄에 assert_can_write 검사 / 허용 목록)',
    (select count(*) from wf) || ' / '
      || (select count(*) from wf where wf.prosrc ~ '^\s*declare\s*\n\s*_can_write constant boolean := public\.assert_can_write\(\);'
                                     or wf.prosrc ~ '^\s*begin\s*\n\s*perform public\.assert_can_write\(\);')
      || ' / ' || (select count(*) from wf where exists (select 1 from public.restriction_exemptions e where e.kind = 'function' and e.name = wf.sig)),
    '103 / 30 / 73', '080 뒤에는 104 / 31 / 73'
  union all select 3, '적어 둘 값: 쓰기 함수 지문 (CR 뺌)',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a join wf on wf.sig = a.sig),
    '(이 값을 적어 둠)', null
  union all select 4, '적어 둘 값: 읽기 함수 수 / 지문 (CR 뺌)',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a join rf on rf.sig = a.sig),
    '(이 값을 적어 둠)', '079까지 실행했으면 67개 (080 뒤 69개)'
  union all select 5, '적어 둘 값: public의 모든 함수 수 / 지문 (CR 뺌)',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a),
    '(이 값을 적어 둠)', null
  union all select 6, '적어 둘 값: 푸시 판정 지문 - 모든 사람 × 모든 알림 종류의 push_wanted · 종류별 push_group',
    (select count(*) || ' / ' || md5(string_agg(p.id::text || ':' || k.k || ':' || public.push_wanted(p.id, k.k)::text, ',' order by p.id, k.k))
       from public.profiles p cross join kinds k)
      || ' · ' || (select count(*) || ' / ' || md5(string_agg(k || ':' || coalesce(public.push_group(k), '-'), ',' order by k)) from kinds),
    '(이 값을 적어 둠)', null
  union all select 7, '적어 둘 값: 허용 목록(restriction_exemptions) 줄 수 / 지문 · xp_rules 줄 수 / 지문',
    (select count(*) || ' / ' || left(md5(string_agg(kind || ':' || name || ':' || reason, ',' order by kind, name)), 12) from public.restriction_exemptions)
      || ' · ' || (select count(*) || ' / ' || left(md5(string_agg(key || ':' || value || ':' || note, ',' order by key)), 12) from public.xp_rules),
    '(이 값을 적어 둠)', null
  union all select 8, '적어 둘 값: public 트리거 수 / 지문 · 정책 수 / 지문',
    (select count(*) || ' / ' || left(md5(string_agg(tgrelid::regclass::text || pg_get_triggerdef(oid) || tgenabled::text, ',' order by tgrelid::regclass::text, tgname)), 12)
       from pg_trigger where not tgisinternal and tgrelid in (select oid from pg_class where relnamespace = 'public'::regnamespace))
      || ' · ' || (select count(*) || ' / ' || left(md5(string_agg(polrelid::regclass::text || polname || polcmd::text || coalesce(pg_get_expr(polqual, polrelid), '') || coalesce(pg_get_expr(polwithcheck, polrelid), ''), ',' order by polrelid::regclass::text, polname)), 12)
       from pg_policy where polrelid in (select oid from pg_class where relnamespace = 'public'::regnamespace)),
    '(이 값을 적어 둠)', null
  union all select 9, '적어 둘 값: 공개 빌드 수 (빌드 approved + 상대법 approved) / 회원 수',
    (select count(*) from public.builds b join public.counters c on c.id = b.counter_id where b.status = 'approved' and c.status = 'approved')
      || ' / ' || (select count(*) from public.profiles),
    '(이 값을 적어 둠)', '080은 데이터를 바꾸지 않음'
) x
order by ord;
