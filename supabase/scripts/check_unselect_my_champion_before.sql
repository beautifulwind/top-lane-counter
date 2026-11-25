-- =====================================================================
-- 081(unselect_my_champion) 실행 "전" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다.
--   - 1번이 「있음 · 없음 · 없음」, 2번이 「104 / 31 / 73」이면 실행해도 된다. 3~7번은 적어 둔다(081 뒤 after 스크립트와 비교).
--   - 이메일·토큰·닉네임 값은 출력하지 않는다(개수·지문만). 함수 본문 지문은 줄바꿈 CR을 뺀 값.
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
)
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '있음: set_my_champion(080) · unselect_my_champion · 허용 목록의 unselect_my_champion 줄' as what,
    case when to_regprocedure('public.set_my_champion(text, boolean)') is null then '없음' else '있음' end
      || ' · ' || case when to_regprocedure('public.unselect_my_champion(text)') is null then '없음' else '있음' end
      || ' · ' || case when exists (select 1 from public.restriction_exemptions where kind = 'function' and name = 'unselect_my_champion(text)') then '있음' else '없음' end as now_value,
    '있음 · 없음 · 없음' as ok_value, '첫 칸이 「없음」이면 080 먼저, 뒤 두 칸이 「있음」이면 이미 실행함' as memo
  union all select 2, '쓰기 함수 수 (전체 / 첫 줄 검사 / 허용 목록)',
    (select count(*) from wf) || ' / '
      || (select count(*) from wf where wf.prosrc ~ '^\s*declare\s*\n\s*_can_write constant boolean := public\.assert_can_write\(\);'
                                     or wf.prosrc ~ '^\s*begin\s*\n\s*perform public\.assert_can_write\(\);')
      || ' / ' || (select count(*) from wf where exists (select 1 from public.restriction_exemptions e where e.kind = 'function' and e.name = wf.sig)),
    '104 / 31 / 73', '081 뒤에는 105 / 31 / 74'
  union all select 3, '적어 둘 값: public의 모든 함수 수 / 지문 (CR 뺌)',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a),
    '(이 값을 적어 둠)', 'after 3번(새 함수를 뺀 지문)과 같아야 함'
  union all select 4, 'set_my_champion 본문 지문 (CR 뺌)',
    (select md5(replace(prosrc, E'\r', '')) from pg_proc where oid = to_regprocedure('public.set_my_champion(text, boolean)')),
    '9c23c989dfc6c22ba2d81400570f9c8b', '080 본문 (12-25 날짜 차단을 풀었으면 이 값)'
  union all select 5, '적어 둘 값: 허용 목록 줄 수 / 지문',
    (select count(*) || ' / ' || left(md5(string_agg(kind || ':' || name || ':' || reason, ',' order by kind, name)), 12) from public.restriction_exemptions),
    '(이 값을 적어 둠)', '081 뒤 줄 수 +1'
  union all select 6, '적어 둘 값: public 트리거 수 / 지문 · 정책 수 / 지문',
    (select count(*) || ' / ' || left(md5(string_agg(tgrelid::regclass::text || pg_get_triggerdef(oid) || tgenabled::text, ',' order by tgrelid::regclass::text, tgname)), 12)
       from pg_trigger where not tgisinternal and tgrelid in (select oid from pg_class where relnamespace = 'public'::regnamespace))
      || ' · ' || (select count(*) || ' / ' || left(md5(string_agg(polrelid::regclass::text || polname || polcmd::text || coalesce(pg_get_expr(polqual, polrelid), '') || coalesce(pg_get_expr(polwithcheck, polrelid), ''), ',' order by polrelid::regclass::text, polname)), 12)
       from pg_policy where polrelid in (select oid from pg_class where relnamespace = 'public'::regnamespace)),
    '(이 값을 적어 둠)', null
  union all select 7, '적어 둘 값: 등록된 챔피언 줄 수 / 사람 수 / 지문',
    (select count(*) || ' / ' || count(distinct user_id) || ' / ' || left(coalesce(md5(string_agg(user_id::text || ':' || champion, ',' order by user_id, champion)), '-'), 12) from public.user_champions),
    '(이 값을 적어 둠)', '081은 데이터를 바꾸지 않음 (사이트에서 등록·해제하면 달라질 수 있음)'
) x
order by ord;
