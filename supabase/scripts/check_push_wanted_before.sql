-- =====================================================================
-- 073(push_wanted: 웹 구독 또는 앱 기기 토큰) 실행 "전" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 073을 실행하기 전에 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~3번: [지금 값]이 [정상 값]과 맞으면 073을 실행해도 된다. 다르면 실행하지 말고 알려 주세요.
--   - 4~14번은 "적어 둘 값"이다. 073 실행 뒤 check_push_wanted_after.sql의 「비교」 줄과 비교한다
--     (073은 push_wanted 본문의 마지막 조건 하나만 바꾼다 - 다른 함수·표·트리거·정책·권한·데이터는 그대로여야 한다).
--   - 함수 본문 지문은 줄바꿈 CR을 뺀 값으로 계산한다(SQL Editor가 CRLF로 붙여 넣어도 같은 값 - c5333b1과 같은 방식).
--   - 토큰·endpoint 같은 값 자체는 출력하지 않는다(개수·지문만).
--   - 사이트 활동(알림·웹/앱 푸시 켜기·끄기)이 있으면 12~13번은 달라질 수 있다 - 사람이 적은 시간에 이어서 실행해 주세요.
-- =====================================================================
with
pw as (select to_regprocedure('public.push_wanted(uuid, text)') as oid),
-- 일반 사용자(로그인·비로그인)가 부를 수 있는 쓰기 함수 (068 빠뜨림 방지 검사와 같은 대상: volatile, 트리거 아님)
wf as (
  select p.oid, p.proname || '(' || oidvectortypes(p.proargtypes) || ')' as sig, p.prosrc
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f' and p.provolatile = 'v' and p.prorettype <> 'trigger'::regtype
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))
),
-- 일반 사용자(로그인·비로그인)가 부를 수 있는 읽기 함수 (stable·immutable, 트리거 아님)
rf as (
  select p.proname || '(' || oidvectortypes(p.proargtypes) || ')' as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f' and p.provolatile in ('s', 'i') and p.prorettype <> 'trigger'::regtype
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))
),
-- public의 모든 함수 (쓰기·읽기·트리거·내부 함수 전부) - 이름·인자·반환·본문·보안·search_path·권한
allf as (
  select p.proname || '(' || oidvectortypes(p.proargtypes) || ')' as sig,
         p.proname || '(' || oidvectortypes(p.proargtypes) || ')' || pg_get_function_result(p.oid) || p.provolatile::text
           || replace(p.prosrc, E'\r', '') || p.prosecdef::text || coalesce(array_to_string(p.proconfig, ','), '')
           || coalesce(array_to_string(p.proacl, ','), '') as body
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind in ('f', 'p')
),
-- 푸시와 관계있는 표 4개
pt as (select unnest(array['public.notifications', 'public.push_subscriptions', 'public.push_settings', 'public.device_push_tokens']::regclass[]) as rel)
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '072까지 실행됨 (표 device_push_tokens / 함수 register_device_push_token)' as what,
    coalesce(to_regclass('public.device_push_tokens')::text, '없음')
      || ' / ' || coalesce(to_regprocedure('public.register_device_push_token(text, text, text)')::text, '없음') as now_value,
    'device_push_tokens / register_device_push_token(text,text,text)' as ok_value, '없음이 있으면 072부터 실행' as memo
  union all select 2, 'push_wanted 본문 (067 본문 / 073 이미 실행 / 다름)',
    coalesce((select case md5(replace(prosrc, E'\r', ''))
                       when 'bfb8e95016ca726a7dade1b76bb56fce' then '067 본문'
                       when 'e6f1723ae3a6b0126ece4b51488a067c' then '073 이미 실행'
                       else '다름 ' || md5(replace(prosrc, E'\r', '')) end
                from pg_proc where oid = (select oid from pw)), '함수 없음'),
    '067 본문', '「073 이미 실행」이면 다시 실행하지 마세요. 「다름」이면 실행하지 말고 알려 주세요'
  union all select 3, 'push_wanted 소유자가 device_push_tokens를 읽을 수 있음 (소유자 같음 / FORCE RLS / 소유자 select 권한)',
    coalesce((select ((select proowner from pg_proc where oid = (select oid from pw)) = c.relowner)::text
                     || ' / ' || c.relforcerowsecurity::text
                     || ' / ' || has_table_privilege((select proowner from pg_proc where oid = (select oid from pw)), c.oid, 'select')::text
                from pg_class c where c.oid = to_regclass('public.device_push_tokens')), '표 없음'),
    'true / false / true', 'security definer 함수는 소유자 권한으로 돈다. 표 소유자는 FORCE가 아니면 RLS를 거치지 않는다'
  union all select 4, '적어 둘 값: 쓰기 함수 수 (전체 / 첫 줄에 assert_can_write 검사 / 허용 목록)',
    (select count(*) from wf) || ' / '
      || (select count(*) from wf where wf.prosrc ~ '^\s*declare\s*\n\s*_can_write constant boolean := public\.assert_can_write\(\);'
                                     or wf.prosrc ~ '^\s*begin\s*\n\s*perform public\.assert_can_write\(\);')
      || ' / ' || (select count(*) from wf where exists (select 1 from public.restriction_exemptions e where e.kind = 'function' and e.name = wf.sig)),
    '103 / 30 / 73 (예상)', '073 뒤에도 103 / 30 / 73이어야 한다. 예상과 다르면 그대로 적어 두고 알려 주세요'
  union all select 5, '적어 둘 값: 쓰기 함수의 이름·본문·보안·search_path·권한 지문 (CR 뺌)',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a join wf on wf.sig = a.sig),
    '(이 값을 적어 둠)', '실행 뒤: 같은 수·같은 지문 (push_wanted는 쓰기 함수가 아님)'
  union all select 6, '적어 둘 값: push_wanted를 뺀 public의 모든 함수 수 / 지문 (CR 뺌)',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a where a.sig <> 'push_wanted(uuid, text)'),
    '(이 값을 적어 둠)', '실행 뒤: 같은 수·같은 지문'
  union all select 7, '적어 둘 값: 웹 푸시 발송 함수 지문 (push_on_notification·push_targets·push_forget·push_group - push_wanted 뺌)',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a
      where split_part(a.sig, '(', 1) in ('push_on_notification', 'push_targets', 'push_forget', 'push_group')),
    '(이 값을 적어 둠)', '073은 발송 쪽 다른 함수를 고치지 않는다'
  union all select 8, '적어 둘 값: push_wanted의 본문 밖 속성 (인자 · 반환 · volatile · security definer · search_path · 권한 · 소유자)',
    coalesce((select oid::regprocedure::text || ' · ' || pg_get_function_result(oid) || ' · ' || provolatile::text || ' · ' || prosecdef::text
                     || ' · ' || coalesce(array_to_string(proconfig, ','), '없음') || ' · ' || coalesce(array_to_string(proacl, ','), '기본')
                     || ' · ' || pg_get_userbyid(proowner)
                from pg_proc where oid = (select oid from pw)), '함수 없음'),
    '(이 값을 적어 둠)', '실행 뒤: 본문만 바뀌고 이 줄은 같아야 한다'
  union all select 9, '적어 둘 값: 표 notifications·push_subscriptions·push_settings·device_push_tokens의 칸·제약 지문',
    (select left(md5(string_agg(c.table_name || ':' || c.column_name || ':' || c.data_type || ':' || c.is_nullable || ':' || coalesce(c.column_default, ''), ',' order by c.table_name, c.ordinal_position)), 12)
       from information_schema.columns c where c.table_schema = 'public' and c.table_name in ('notifications', 'push_subscriptions', 'push_settings', 'device_push_tokens'))
      || ' · ' || (select count(*) || ' / ' || left(md5(string_agg(conrelid::regclass::text || ':' || conname || ':' || pg_get_constraintdef(oid), ',' order by conrelid::regclass::text, conname)), 12)
       from pg_constraint where conrelid in (select rel from pt)),
    '(이 값을 적어 둠)', null
  union all select 10, '적어 둘 값: 같은 4개 표의 트리거 수 / 지문 · 정책 수 / 지문 · 비로그인·로그인·service_role 권한 지문 · RLS',
    (select count(*) || ' / ' || left(md5(string_agg(tgrelid::regclass::text || pg_get_triggerdef(oid) || tgenabled::text, ',' order by tgrelid::regclass::text, tgname)), 12)
       from pg_trigger where tgrelid in (select rel from pt) and not tgisinternal)
      || ' · ' || (select count(*) || ' / ' || left(md5(string_agg(polrelid::regclass::text || polname || polcmd::text || coalesce(pg_get_expr(polqual, polrelid), '') || coalesce(pg_get_expr(polwithcheck, polrelid), ''), ',' order by polrelid::regclass::text, polname)), 12)
       from pg_policy where polrelid in (select rel from pt))
      || ' · ' || (select left(md5(string_agg(table_name || ':' || grantee || ':' || privilege_type, ',' order by table_name, grantee, privilege_type)), 12)
       from information_schema.role_table_grants where table_schema = 'public' and table_name in ('notifications', 'push_subscriptions', 'push_settings', 'device_push_tokens')
        and grantee in ('anon', 'authenticated', 'service_role'))
      || ' · ' || (select string_agg(relrowsecurity::text, ',' order by relname) from pg_class where oid in (select rel from pt)),
    '(이 값을 적어 둠)', '073은 표를 건드리지 않는다'
  union all select 11, '적어 둘 값: 허용 목록(restriction_exemptions) 줄 수 / 지문',
    (select count(*) || ' / ' || left(md5(string_agg(kind || ':' || name || ':' || reason, ',' order by kind, name)), 12) from public.restriction_exemptions),
    '(이 값을 적어 둠)', '073은 허용 목록을 바꾸지 않는다'
  union all select 12, '적어 둘 값: 웹 푸시 기기 수 · 가장 큰 id · 지문 앞 12자리 / 앱 기기 토큰 수 · 가장 큰 id / 알림 종류 설정 줄 수 (값 자체는 출력하지 않음)',
    (select count(*) || ' · ' || coalesce(max(id), 0) || ' · ' || left(md5(coalesce(string_agg(s::text, '|' order by s.id), '')), 12) from public.push_subscriptions s)
      || ' / ' || (select count(*) || ' · ' || coalesce(max(id), 0) from public.device_push_tokens)
      || ' / ' || (select count(*) from public.push_settings),
    '(이 값을 적어 둠)', '그 사이 누가 웹·앱 알림을 켜고 끄면 달라질 수 있음'
  union all select 13, '적어 둘 값: 알림 전체 수 · 가장 큰 id / 일반 사용자가 부를 수 있는 읽기 함수 수 / 지문',
    (select count(*) || ' · ' || coalesce(max(id), 0) from public.notifications)
      || ' / ' || (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a join rf on rf.sig = a.sig),
    '(이 값을 적어 둠)', '073은 읽기 함수를 더하지 않는다 (알림 수는 사이트 활동으로 달라질 수 있음)'
  union all select 14, '참고: 사람 수 (웹 구독만 / 앱 토큰만 / 둘 다) - 073 뒤 새로 푸시 대상이 되는 것은 「앱 토큰만」',
    (select count(*) filter (where w and not a) || ' / ' || count(*) filter (where a and not w) || ' / ' || count(*) filter (where w and a)
       from (select pr.id,
                    exists (select 1 from public.push_subscriptions s where s.user_id = pr.id) as w,
                    exists (select 1 from public.device_push_tokens d where d.user_id = pr.id) as a
               from public.profiles pr) x),
    '(참고)', '「앱 토큰만」인 사람은 지금 앱 푸시를 못 받고 있다'
) x
order by ord;
