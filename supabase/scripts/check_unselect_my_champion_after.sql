-- =====================================================================
-- 081(unselect_my_champion) 실행 "뒤" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- SQL Editor에 통째로 붙여넣어 실행한다. 1~5번은 「정상 값」과 같아야 하고, 6~8번은 before 스크립트에 적어 둔 값과 비교한다.
-- =====================================================================
with
wf as (
  select p.oid, p.proname || '(' || oidvectortypes(p.proargtypes) || ')' as sig, p.prosrc
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f' and p.provolatile = 'v' and p.prorettype <> 'trigger'::regtype
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
fn as (select oid, prosrc from pg_proc where oid = to_regprocedure('public.unselect_my_champion(text)'))
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '있음: unselect_my_champion · 허용 목록 줄(이유)' as what,
    case when exists (select 1 from fn) then '있음' else '없음' end
      || ' · ' || coalesce((select reason from public.restriction_exemptions where kind = 'function' and name = 'unselect_my_champion(text)'), '없음') as now_value,
    '있음 · 내 챔피언 해제 (등록은 막음)' as ok_value, null as memo
  union all select 2, '권한: 로그인 실행 · 비로그인 실행 · public 실행 · 검사 없음(assert_can_write 없음) · security definer · search_path',
    (select has_function_privilege('authenticated', p.oid, 'execute')::text || ' · ' || has_function_privilege('anon', p.oid, 'execute')::text
            || ' · ' || exists (select 1 from unnest(p.proacl) a where a::text like '=%')::text
            || ' · ' || (p.prosrc not like '%assert_can_write%')::text || ' · ' || p.prosecdef::text || ' · ' || coalesce(array_to_string(p.proconfig, ','), '-')
       from pg_proc p where p.oid = (select oid from fn)),
    'true · false · false · true · true · search_path=""', null
  union all select 3, '쓰기 함수 수 (전체 / 첫 줄 검사 / 허용 목록)',
    (select count(*) from wf) || ' / '
      || (select count(*) from wf where wf.prosrc ~ '^\s*declare\s*\n\s*_can_write constant boolean := public\.assert_can_write\(\);'
                                     or wf.prosrc ~ '^\s*begin\s*\n\s*perform public\.assert_can_write\(\);')
      || ' / ' || (select count(*) from wf where exists (select 1 from public.restriction_exemptions e where e.kind = 'function' and e.name = wf.sig)),
    '105 / 31 / 74', null
  union all select 4, '빠뜨림: 첫 줄 검사도 허용 목록도 없는 쓰기 함수',
    coalesce((select string_agg(wf.sig, ', ') from wf
               where not (wf.prosrc ~ '^\s*declare\s*\n\s*_can_write constant boolean := public\.assert_can_write\(\);'
                          or wf.prosrc ~ '^\s*begin\s*\n\s*perform public\.assert_can_write\(\);')
                 and not exists (select 1 from public.restriction_exemptions e where e.kind = 'function' and e.name = wf.sig)), '없음'),
    '없음', null
  union all select 5, 'set_my_champion 본문 지문 (CR 뺌) - 081이 고치지 않음',
    (select md5(replace(prosrc, E'\r', '')) from pg_proc where oid = to_regprocedure('public.set_my_champion(text, boolean)')),
    '9c23c989dfc6c22ba2d81400570f9c8b', null
  union all select 6, '비교: 새 함수를 뺀 public 함수 수 / 지문 (CR 뺌)',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a where a.sig <> 'unselect_my_champion(text)'),
    'before 3번과 같음', null
  union all select 7, '비교: 허용 목록 줄 수 / 지문 · 트리거 · 정책',
    (select count(*) || ' / ' || left(md5(string_agg(kind || ':' || name || ':' || reason, ',' order by kind, name)), 12) from public.restriction_exemptions)
      || ' · ' || (select count(*) || ' / ' || left(md5(string_agg(tgrelid::regclass::text || pg_get_triggerdef(oid) || tgenabled::text, ',' order by tgrelid::regclass::text, tgname)), 12)
       from pg_trigger where not tgisinternal and tgrelid in (select oid from pg_class where relnamespace = 'public'::regnamespace))
      || ' · ' || (select count(*) || ' / ' || left(md5(string_agg(polrelid::regclass::text || polname || polcmd::text || coalesce(pg_get_expr(polqual, polrelid), '') || coalesce(pg_get_expr(polwithcheck, polrelid), ''), ',' order by polrelid::regclass::text, polname)), 12)
       from pg_policy where polrelid in (select oid from pg_class where relnamespace = 'public'::regnamespace)),
    'before 5번 줄 수 +1 · before 6번과 같음', '허용 목록 지문은 달라짐(새 줄)'
  union all select 8, '비교: 등록된 챔피언 줄 수 / 사람 수 / 지문',
    (select count(*) || ' / ' || count(distinct user_id) || ' / ' || left(coalesce(md5(string_agg(user_id::text || ':' || champion, ',' order by user_id, champion)), '-'), 12) from public.user_champions),
    'before 7번과 같음', '그 사이 사이트에서 등록·해제했으면 다를 수 있음'
) x
order by ord;
