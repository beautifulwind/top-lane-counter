-- =====================================================================
-- 073(push_wanted: 웹 구독 또는 앱 기기 토큰) 실행 "뒤" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다). 운영 DB에서 언제 다시 실행해도 된다.
-- 073을 실행한 "직후" SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~9번: [지금 값]이 [정상 값]과 모두 맞아야 한다. 하나라도 다르면 알려 주세요.
--   - 10~19번: 실행 전 check_push_wanted_before.sql의 4~13번에 적어 둔 값과 비교한다(각 줄의 [정상 값]에 무엇과 같아야 하는지 적었다).
--   - 함수 본문 지문은 줄바꿈 CR을 뺀 값으로 계산한다(SQL Editor가 CRLF로 붙여 넣어도 같은 값 - c5333b1과 같은 방식).
--   - 이 조회는 push_wanted를 부르지 않는다. 토큰·endpoint 값 자체는 출력하지 않는다(개수·지문만).
-- =====================================================================
with
pw as (select to_regprocedure('public.push_wanted(uuid, text)') as oid),
-- 일반 사용자(로그인·비로그인)가 부를 수 있는 쓰기 함수 (068 빠뜨림 방지 검사와 같은 대상)
wf as (
  select p.oid, p.proname || '(' || oidvectortypes(p.proargtypes) || ')' as sig, p.prosrc,
         case
           when p.prosrc ~ '^\s*declare\s*\n\s*_can_write constant boolean := public\.assert_can_write\(\);'
             or p.prosrc ~ '^\s*begin\s*\n\s*perform public\.assert_can_write\(\);' then 'checked'
           when p.prosrc like '%assert_can_write%' then 'NOT_FIRST'
           when exists (select 1 from public.restriction_exemptions e
                         where e.kind = 'function' and e.name = p.proname || '(' || oidvectortypes(p.proargtypes) || ')') then 'exempt'
           else 'MISSING'
         end as state
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f' and p.provolatile = 'v' and p.prorettype <> 'trigger'::regtype
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))
),
-- 일반 사용자(로그인·비로그인)가 부를 수 있는 읽기 함수 - 실행 전 스크립트와 같은 식
rf as (
  select p.proname || '(' || oidvectortypes(p.proargtypes) || ')' as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f' and p.provolatile in ('s', 'i') and p.prorettype <> 'trigger'::regtype
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))
),
-- public의 모든 함수 (실행 전 스크립트와 같은 식)
allf as (
  select p.proname || '(' || oidvectortypes(p.proargtypes) || ')' as sig,
         p.proname || '(' || oidvectortypes(p.proargtypes) || ')' || pg_get_function_result(p.oid) || p.provolatile::text
           || replace(p.prosrc, E'\r', '') || p.prosecdef::text || coalesce(array_to_string(p.proconfig, ','), '')
           || coalesce(array_to_string(p.proacl, ','), '') as body
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind in ('f', 'p')
),
pt as (select unnest(array['public.notifications', 'public.push_subscriptions', 'public.push_settings', 'public.device_push_tokens']::regclass[]) as rel)
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, 'push_wanted 본문 지문 (줄바꿈 CR을 뺀 값)' as what,
    coalesce((select md5(replace(prosrc, E'\r', '')) from pg_proc where oid = (select oid from pw)), '함수 없음') as now_value,
    'e6f1723ae3a6b0126ece4b51488a067c' as ok_value, '파일 그대로 실행했으면 같음 (CRLF로 붙여 넣어도 같음)' as memo
  union all select 2, '바뀐 곳은 마지막 조건 하나뿐: 새 조건을 옛 조건으로 되바꾼 본문의 지문',
    coalesce((select md5(replace(replace(prosrc, E'\r', ''),
                E'  and (exists (select 1 from public.push_subscriptions where user_id = p_user)\n       or exists (select 1 from public.device_push_tokens where user_id = p_user));  -- 073: 웹 구독 또는 앱 기기 토큰',
                '  and exists (select 1 from public.push_subscriptions where user_id = p_user);'))
                from pg_proc where oid = (select oid from pw)), '함수 없음'),
    'bfb8e95016ca726a7dade1b76bb56fce', '067 본문 지문과 같음 = 종류별 묶음·운영자 모드·설정 판단은 한 글자도 안 바뀜'
  union all select 3, 'push_wanted 모양 (인자 · 반환 · volatile · security definer · search_path) · 같은 이름 함수 수',
    coalesce((select oid::regprocedure::text || ' · ' || pg_get_function_result(oid) || ' · ' || provolatile::text || ' · ' || prosecdef::text
                     || ' · ' || coalesce(array_to_string(proconfig, ','), '없음')
                from pg_proc where oid = (select oid from pw)), '함수 없음')
      || ' · ' || (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'push_wanted'),
    'push_wanted(uuid,text) · boolean · s · true · search_path="" · 1', null
  union all select 4, 'push_wanted 실행 권한 (비로그인 anon / 로그인 authenticated / public 기본 권한)',
    coalesce((select has_function_privilege('anon', oid, 'execute')::text || ' / ' || has_function_privilege('authenticated', oid, 'execute')::text
                     || ' / ' || exists (select 1 from unnest(proacl) a where a::text like '=%')::text
                from pg_proc where oid = (select oid from pw)), '함수 없음'),
    'false / false / false', '남의 알림 설정을 묻지 못하게 (037부터 그대로)'
  union all select 5, 'push_wanted 소유자가 device_push_tokens를 읽을 수 있음 (소유자 같음 / FORCE RLS / 소유자 select 권한)',
    coalesce((select ((select proowner from pg_proc where oid = (select oid from pw)) = c.relowner)::text
                     || ' / ' || c.relforcerowsecurity::text
                     || ' / ' || has_table_privilege((select proowner from pg_proc where oid = (select oid from pw)), c.oid, 'select')::text
                from pg_class c where c.oid = to_regclass('public.device_push_tokens')), '표 없음'),
    'true / false / true', 'security definer 함수는 소유자 권한으로 돈다. 표 소유자는 FORCE가 아니면 RLS를 거치지 않는다'
  union all select 6, '알림 트리거 그대로 (notifications_push가 부르는 함수 / 켜짐)',
    coalesce((select tgfoid::regprocedure::text || ' / ' || tgenabled::text from pg_trigger where tgname = 'notifications_push' and tgrelid = 'public.notifications'::regclass), '없음'),
    'push_on_notification() / O', null
  union all select 7, 'push_wanted를 부르는 함수 (본문에 push_wanted( 가 있는 함수)',
    coalesce((select string_agg(p.oid::regprocedure::text, ', ' order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
               where n.nspname = 'public' and p.prosrc like '%push_wanted(%' and p.proname <> 'push_wanted'), '없음'),
    'push_on_notification(), push_targets(bigint)', '트리거(부를지)와 Edge Function용 push_targets(웹 구독 목록) 두 곳'
  union all select 8, '쓰기 함수 수 (전체 / 첫 줄 검사 / 허용 목록)',
    (select count(*) from wf) || ' / ' || (select count(*) from wf where state = 'checked') || ' / ' || (select count(*) from wf where state = 'exempt'),
    '103 / 30 / 73', '073은 쓰기 함수를 더하거나 바꾸지 않는다'
  union all select 9, '빠뜨림 방지: 쓰기 함수 중 통과 못 한 것 (검사도 허용 목록도 없음 / 검사가 첫 줄이 아님)',
    coalesce((select string_agg(sig || ' ' || state, ', ' order by sig) from wf where state not in ('checked', 'exempt')), '없음'),
    '없음', '068 check_restrictions_after.sql 5번과 같은 규칙'
  -- ===== 실행 전 값과 비교 =====
  union all select 10, '비교: 쓰기 함수 수 (전체 / 첫 줄 검사 / 허용 목록)',
    (select count(*) from wf) || ' / ' || (select count(*) from wf where state = 'checked') || ' / ' || (select count(*) from wf where state = 'exempt'),
    '실행 전 4번과 같음', null
  union all select 11, '비교: 쓰기 함수의 이름·본문·보안·search_path·권한 지문',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a join wf on wf.sig = a.sig),
    '실행 전 5번과 같음', null
  union all select 12, '비교: push_wanted를 뺀 public의 모든 함수 수 / 지문',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a where a.sig <> 'push_wanted(uuid, text)'),
    '실행 전 6번과 같음', '다른 함수는 하나도 바뀌지 않았다'
  union all select 13, '비교: 웹 푸시 발송 함수 지문 (push_on_notification·push_targets·push_forget·push_group)',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a
      where split_part(a.sig, '(', 1) in ('push_on_notification', 'push_targets', 'push_forget', 'push_group')),
    '실행 전 7번과 같음', null
  union all select 14, '비교: push_wanted의 본문 밖 속성 (인자 · 반환 · volatile · security definer · search_path · 권한 · 소유자)',
    coalesce((select oid::regprocedure::text || ' · ' || pg_get_function_result(oid) || ' · ' || provolatile::text || ' · ' || prosecdef::text
                     || ' · ' || coalesce(array_to_string(proconfig, ','), '없음') || ' · ' || coalesce(array_to_string(proacl, ','), '기본')
                     || ' · ' || pg_get_userbyid(proowner)
                from pg_proc where oid = (select oid from pw)), '함수 없음'),
    '실행 전 8번과 같음', 'create or replace라 소유자·권한이 그대로 남는다'
  union all select 15, '비교: 표 4개의 칸·제약 지문',
    (select left(md5(string_agg(c.table_name || ':' || c.column_name || ':' || c.data_type || ':' || c.is_nullable || ':' || coalesce(c.column_default, ''), ',' order by c.table_name, c.ordinal_position)), 12)
       from information_schema.columns c where c.table_schema = 'public' and c.table_name in ('notifications', 'push_subscriptions', 'push_settings', 'device_push_tokens'))
      || ' · ' || (select count(*) || ' / ' || left(md5(string_agg(conrelid::regclass::text || ':' || conname || ':' || pg_get_constraintdef(oid), ',' order by conrelid::regclass::text, conname)), 12)
       from pg_constraint where conrelid in (select rel from pt)),
    '실행 전 9번과 같음', null
  union all select 16, '비교: 같은 4개 표의 트리거 · 정책 · 권한 · RLS',
    (select count(*) || ' / ' || left(md5(string_agg(tgrelid::regclass::text || pg_get_triggerdef(oid) || tgenabled::text, ',' order by tgrelid::regclass::text, tgname)), 12)
       from pg_trigger where tgrelid in (select rel from pt) and not tgisinternal)
      || ' · ' || (select count(*) || ' / ' || left(md5(string_agg(polrelid::regclass::text || polname || polcmd::text || coalesce(pg_get_expr(polqual, polrelid), '') || coalesce(pg_get_expr(polwithcheck, polrelid), ''), ',' order by polrelid::regclass::text, polname)), 12)
       from pg_policy where polrelid in (select rel from pt))
      || ' · ' || (select left(md5(string_agg(table_name || ':' || grantee || ':' || privilege_type, ',' order by table_name, grantee, privilege_type)), 12)
       from information_schema.role_table_grants where table_schema = 'public' and table_name in ('notifications', 'push_subscriptions', 'push_settings', 'device_push_tokens')
        and grantee in ('anon', 'authenticated', 'service_role'))
      || ' · ' || (select string_agg(relrowsecurity::text, ',' order by relname) from pg_class where oid in (select rel from pt)),
    '실행 전 10번과 같음', null
  union all select 17, '비교: 허용 목록(restriction_exemptions) 줄 수 / 지문',
    (select count(*) || ' / ' || left(md5(string_agg(kind || ':' || name || ':' || reason, ',' order by kind, name)), 12) from public.restriction_exemptions),
    '실행 전 11번과 같음', null
  union all select 18, '비교: 웹 푸시 기기 수 · 가장 큰 id · 지문 앞 12자리 / 앱 기기 토큰 수 · 가장 큰 id / 알림 종류 설정 줄 수',
    (select count(*) || ' · ' || coalesce(max(id), 0) || ' · ' || left(md5(coalesce(string_agg(s::text, '|' order by s.id), '')), 12) from public.push_subscriptions s)
      || ' / ' || (select count(*) || ' · ' || coalesce(max(id), 0) from public.device_push_tokens)
      || ' / ' || (select count(*) from public.push_settings),
    '실행 전 12번과 같음', '073은 데이터를 바꾸지 않는다 (그 사이 사이트 활동이 있으면 다를 수 있음)'
  union all select 19, '비교: 알림 전체 수 · 가장 큰 id / 읽기 함수 수 / 지문',
    (select count(*) || ' · ' || coalesce(max(id), 0) from public.notifications)
      || ' / ' || (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a join rf on rf.sig = a.sig),
    '실행 전 13번과 같음', '읽기 함수는 늘거나 바뀌지 않았다'
  union all select 20, '참고: 사람 수 (웹 구독만 / 앱 토큰만 / 둘 다) - 「앱 토큰만」인 사람이 이제 앱 푸시를 받는다',
    (select count(*) filter (where w and not a) || ' / ' || count(*) filter (where a and not w) || ' / ' || count(*) filter (where w and a)
       from (select pr.id,
                    exists (select 1 from public.push_subscriptions s where s.user_id = pr.id) as w,
                    exists (select 1 from public.device_push_tokens d where d.user_id = pr.id) as a
               from public.profiles pr) x),
    '(참고) 실행 전 14번과 같음', null
) x
order by ord;
