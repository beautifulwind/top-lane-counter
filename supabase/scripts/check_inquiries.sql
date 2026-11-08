-- =====================================================================
-- 032(문의하기) 확인 조회 (읽기만 — 아무것도 바꾸지 않는다).
-- 032 실행 "전"과 "후"에 한 번씩 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다.
-- [지금 값]이 [실행 전 정상]·[실행 후 정상]과 맞는지 본다. (pg_cron 일정은 맨 아래 따로)
-- =====================================================================
with c as (
  select
    to_regclass('public.inquiries') is not null as has_table,
    exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'create_inquiry') as has_fn
), f as (
  select p.oid, p.proname, p.prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname in ('create_inquiry', 'answer_inquiry', 'set_inquiry_category', 'delete_my_inquiry')
)
select ord as "순서", what as "항목", now_value as "지금 값", before_ok as "실행 전 정상", after_ok as "실행 후 정상"
from (
  select 1 as ord, '031 실행됨 (032의 전제: proposal_reviewing 표)' as what, (to_regclass('public.proposal_reviewing') is not null)::text as now_value, 'true' as before_ok, 'true' as after_ok
  union all select 2, 'inquiries 표', c.has_table::text, 'false', 'true' from c
  union all select 3, '표의 행 보안(RLS) 켜짐 (inquiries · inquiry_quota)',
    case when c.has_table then (select string_agg(relrowsecurity::text, ' · ' order by relname) from pg_class k join pg_namespace n on n.oid = k.relnamespace where n.nspname = 'public' and k.relname in ('inquiries', 'inquiry_quota')) else '표 없음' end, '표 없음', 'true · true' from c
  union all select 4, '일반 사용자·비로그인이 표에 쓸 수 있나 (모두 false여야 함)',
    case when c.has_table then (
      has_table_privilege('authenticated', 'public.inquiries', 'insert,update,delete')
      or has_table_privilege('anon', 'public.inquiries', 'select,insert,update,delete')
      or has_table_privilege('authenticated', 'public.inquiry_quota', 'select,insert,update,delete')
      or has_table_privilege('anon', 'public.inquiry_quota', 'select,insert,update,delete'))::text else '표 없음' end, '표 없음', 'false' from c
  union all select 5, '읽기 정책 (inquiries 1개 / inquiry_quota 0개 — 하루 개수 표는 함수로만)',
    case when c.has_table then (select count(*) filter (where tablename = 'inquiries')::text || ' / ' || count(*) filter (where tablename = 'inquiry_quota')::text from pg_policies where schemaname = 'public' and tablename in ('inquiries', 'inquiry_quota')) else '표 없음' end, '표 없음', '1 / 0' from c
  union all select 6, '읽기 정책이 감독관의 계정·탈퇴(account) 제외를 하나',
    case when c.has_table then coalesce((select (qual like '%is_moderator%' and qual like '%account%' and qual like '%is_admin%' and qual like '%user_id%')::text from pg_policies where schemaname = 'public' and tablename = 'inquiries'), '정책 없음') else '표 없음' end, '표 없음', 'true' from c
  union all select 7, '문의 함수 4개 (create·answer·set_category·delete_my)', (select count(*)::text from f), '0', '4'
  union all select 8, '비로그인이 네 함수를 부를 수 있나 (false여야 함)',
    case when c.has_fn then (select bool_or(has_function_privilege('anon', f.oid, 'execute'))::text from f) else '함수 없음' end, '함수 없음', 'false' from c
  union all select 9, '로그인한 사람이 네 함수를 부를 수 있나 (true — 권한은 함수 안에서 DB가 검사)',
    case when c.has_fn then (select bool_and(has_function_privilege('authenticated', f.oid, 'execute'))::text from f) else '함수 없음' end, '함수 없음', 'true' from c
  union all select 10, '답변 함수가 운영진 검사(require_staff)·계정·탈퇴 제한을 하나',
    case when c.has_fn then (select (prosrc like '%require_staff%' and prosrc like '%account%' and prosrc like '%is_moderator%')::text from f where proname = 'answer_inquiry') else '함수 없음' end, '함수 없음', 'true' from c
  union all select 11, '분류 옮기기 함수가 운영자 검사(require_operator)를 하나',
    case when c.has_fn then (select (prosrc like '%require_operator%')::text from f where proname = 'set_inquiry_category') else '함수 없음' end, '함수 없음', 'true' from c
  union all select 12, '보관 삭제·분류 이름 함수를 일반 사용자가 부를 수 있나 (false여야 함)',
    coalesce((select bool_or(has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('purge_old_inquiries', 'inquiry_category_label')), '함수 없음'), '함수 없음', 'false'
  union all select 13, '알림 종류에 inquiry_answered 포함',
    (select (pg_get_constraintdef(oid) like '%inquiry_answered%')::text from pg_constraint where conname = 'notifications_kind_check' and conrelid = 'public.notifications'::regclass), 'false', 'true'
  union all select 14, '처리 기록 종류에 answer_inquiry·move_inquiry·inquiry 포함',
    (select bool_and(pg_get_constraintdef(oid) like any (array['%answer_inquiry%', '%inquiry%']))::text from pg_constraint where conrelid = 'public.moderation_log'::regclass and conname in ('moderation_log_action_check', 'moderation_log_target_kind_check')), 'false', 'true'
  union all select 15, '설정값 (하루 개수 · 최소 · 최대 · 답변 최대 · 보관일)',
    coalesce((select string_agg(value::text, ' · ' order by case key when 'inquiry_daily_max' then 1 when 'inquiry_min' then 2 when 'inquiry_max' then 3 when 'inquiry_answer_max' then 4 else 5 end) from public.xp_rules where key like 'inquiry\_%'), '없음'), '없음', '3 · 5 · 1000 · 2000 · 180'
  union all select 16, '지금 문의 수 (읽기: 이 화면은 운영자 권한이라 전체가 보임)',
    case when c.has_table then (xpath('/row/c/text()', query_to_xml('select count(*) as c from public.inquiries', false, true, '')))[1]::text else '표 없음' end, '표 없음', '0 (처음 실행 직후)' from c
  union all select 17, '기존 알림 수 (실행 전후 같아야 함)', (select count(*)::text from public.notifications), '-', '실행 전과 같음'
  union all select 18, '기존 처리 기록 수 (실행 전후 같아야 함)', (select count(*)::text from public.moderation_log), '-', '실행 전과 같음'
) x
order by ord;

-- ---------------------------------------------------------------------
-- pg_cron 일정 확인 (등록한 뒤). 아래 한 줄만 따로 실행: 1줄이 나오고 active = true면 정상
-- select jobname, schedule, command, active from cron.job where jobname = 'purge-old-inquiries';
-- 실행 기록: select status, start_time from cron.job_run_details where command like '%purge_old_inquiries%' order by start_time desc limit 5;
-- ---------------------------------------------------------------------
