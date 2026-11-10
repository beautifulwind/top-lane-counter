-- =====================================================================
-- 037(웹 푸시) 확인 조회 (읽기만 — 아무것도 바꾸지 않는다. 비밀 값의 내용은 보여 주지 않고 "있는지"만 본다).
-- 037 실행 "전", 실행 "후", Vault·Edge Function 설정(SPEC 11-11) "뒤"에 한 번씩 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다.
-- [지금 값]이 [실행 전 정상]·[실행 후 정상]과 맞는지 본다. 14·15번은 SPEC 11-11의 Vault 등록을 마치면 true가 된다.
--
-- 사이트에서 눈으로 확인할 것 (037 실행 + 설정 + 새 코드 push 뒤): SPEC 6-24 "직접 확인할 것"
-- 보내진 기록을 보려면 (Edge Function 응답, 최근 5개):
--   select id, status_code, left(content::text, 120) as content, created from net._http_response order by id desc limit 5;
-- =====================================================================
with fn as (
  select p.oid, p.proname, p.prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('admin_member_stats', 'push_group', 'push_wanted', 'push_on_notification', 'push_targets', 'push_forget', 'push_subscriptions_limit')
), pol as (
  select tablename, cmd, qual, with_check from pg_policies where schemaname = 'public' and tablename in ('push_subscriptions', 'push_settings')
), subs as (select to_regclass('public.push_subscriptions') as t), sets as (select to_regclass('public.push_settings') as t)
select ord as "순서", what as "항목", now_value as "지금 값", before_ok as "실행 전 정상", after_ok as "실행 후 정상"
from (
  select 1 as ord, '036 실행됨 (037의 전제)' as what,
    (exists (select 1 from fn where proname = 'admin_member_stats'))::text as now_value, 'true' as before_ok, 'true' as after_ok
  union all select 2, '기기 알림 주소 표 push_subscriptions · RLS 켜짐',
    coalesce((select 'true · ' || relrowsecurity::text from pg_class where oid = (select t from subs)), '표 없음'), '표 없음', 'true · true'
  union all select 3, 'push_subscriptions 정책: 본인만 읽기·넣기·지우기 (고치기 정책 없음)',
    case when (select t from subs) is null then '표 없음' else (
      (select count(*) from pol where tablename = 'push_subscriptions') = 3
      and (select bool_and(coalesce(qual, with_check) like '%auth.uid()%') from pol where tablename = 'push_subscriptions')
      and not exists (select 1 from pol where tablename = 'push_subscriptions' and cmd = 'UPDATE'))::text end, '표 없음', 'true'
  union all select 4, 'push_subscriptions 로그인 사용자 권한: 읽기 / 넣기 / 지우기 / 고치기',
    case when (select t from subs) is null then '표 없음' else
      has_table_privilege('authenticated', 'public.push_subscriptions', 'select')::text || ' / ' ||
      has_table_privilege('authenticated', 'public.push_subscriptions', 'insert')::text || ' / ' ||
      has_table_privilege('authenticated', 'public.push_subscriptions', 'delete')::text || ' / ' ||
      has_table_privilege('authenticated', 'public.push_subscriptions', 'update')::text end, '표 없음', 'true / true / true / false'
  union all select 5, '비로그인(anon)은 두 표 모두 못 읽음',
    case when (select t from subs) is null or (select t from sets) is null then '표 없음' else
      (not has_table_privilege('anon', 'public.push_subscriptions', 'select') and not has_table_privilege('anon', 'public.push_settings', 'select'))::text end,
    '표 없음', 'true'
  union all select 6, '알림 종류 설정 표 push_settings · RLS 켜짐',
    coalesce((select 'true · ' || relrowsecurity::text from pg_class where oid = (select t from sets)), '표 없음'), '표 없음', 'true · true'
  union all select 7, 'push_settings 정책: 본인만 읽기·넣기·고치기',
    case when (select t from sets) is null then '표 없음' else (
      (select count(*) from pol where tablename = 'push_settings') = 3
      and (select bool_and(coalesce(qual, with_check) like '%auth.uid()%') from pol where tablename = 'push_settings'))::text end, '표 없음', 'true'
  union all select 8, '탈퇴하면 함께 지움 (두 표 모두 profiles on delete cascade)',
    (select count(*)::text from pg_constraint where contype = 'f' and confdeltype = 'c' and confrelid = 'public.profiles'::regclass
       and conrelid in (select t from subs union all select t from sets where t is not null)), '0', '2'
  union all select 9, '알림이 생기면 푸시 트리거 notifications_push',
    (exists (select 1 from pg_trigger where tgname = 'notifications_push' and tgrelid = 'public.notifications'::regclass))::text, 'false', 'true'
  union all select 10, '푸시 종류: 운영진 3종 + 내 제안 결과 7종 (그 밖은 안 보냄)',
    -- 실행 전에는 함수가 없어 이름을 직접 쓰면 오류가 나므로 글자로 된 조회(query_to_xml)로 부른다
    case when exists (select 1 from fn where proname = 'push_group') then
      (xpath('/row/v/text()', query_to_xml($q$
        select count(*) filter (where public.push_group(k) = 'staff_new')::text || ' + ' || count(*) filter (where public.push_group(k) = 'my_results')::text
               || ' (level_up: ' || coalesce(public.push_group('level_up'), '안 보냄') || ')' as v
          from unnest(array['proposal_submitted', 'build_submitted', 'inquiry_received', 'proposal_approved', 'proposal_rejected',
                            'build_approved', 'build_rejected', 'revision_request', 'counter_restored', 'build_restored']) k
      $q$, false, true, '')))[1]::text
    else '함수 없음' end, '함수 없음', '3 + 7 (level_up: 안 보냄)'
  union all select 11, '보낼 대상 판단: 운영자 모드를 함께 보나 (끄면 운영진 알림 안 감)',
    coalesce((select (prosrc like '%operator_mode%' and prosrc like '%moderator%')::text from fn where proname = 'push_wanted'), '함수 없음'), '함수 없음', 'true'
  union all select 12, 'Edge Function용 push_targets·push_forget: 로그인 사용자 실행(false) / service_role 실행(true)',
    coalesce((select bool_or(has_function_privilege('authenticated', oid, 'execute'))::text || ' / ' || bool_and(has_function_privilege('service_role', oid, 'execute'))::text
                from fn where proname in ('push_targets', 'push_forget') having count(*) = 2), '함수 없음'), '함수 없음', 'false / true'
  union all select 13, 'pg_net 켜짐 (net.http_post — 11-10에서 켬)',
    (exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'net' and p.proname = 'http_post'))::text, 'true', 'true'
  union all select 14, 'Vault: push_function_url 등록됨 (값은 안 보여 줌)',
    (exists (select 1 from vault.secrets where name = 'push_function_url'))::text, 'false', 'false → 설정 뒤 true'
  union all select 15, 'Vault: push_webhook_secret 등록됨 (값은 안 보여 줌)',
    (exists (select 1 from vault.secrets where name = 'push_webhook_secret'))::text, 'false', 'false → 설정 뒤 true'
  union all select 16, '참고: 알림을 켠 기기 수 / 종류 설정을 바꾼 사람 수',
    case when (select t from subs) is null or (select t from sets) is null then '표 없음' else
      (xpath('/row/c/text()', query_to_xml('select count(*) as c from public.push_subscriptions', false, true, '')))[1]::text || ' / ' ||
      (xpath('/row/c/text()', query_to_xml('select count(*) as c from public.push_settings', false, true, '')))[1]::text end,
    '표 없음', '0 / 0 (켜면 늘어남)'
) r
order by ord;
