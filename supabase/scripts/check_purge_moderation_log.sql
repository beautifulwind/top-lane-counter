-- =====================================================================
-- 035(처리 기록 1년 보관 삭제) 확인 조회 (읽기만 — 아무것도 바꾸지 않는다).
-- 035 실행 "전"과 "후"에, 그리고 pg_cron 일정을 등록한 "뒤"에 SQL Editor에 통째로 붙여넣어 실행한다.
-- 표 하나가 나온다. [지금 값]이 [실행 전 정상]·[실행 후 정상]과 맞는지 본다. 이 파일은 마지막이 조회문이다.
-- (pg_cron 일정 확인은 9~12번 줄이 같이 보여 준다. pg_cron이 꺼져 있으면 "cron 없음")
-- =====================================================================
with c as (
  select exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                 where n.nspname = 'public' and p.proname = 'purge_old_moderation_log') as has_fn
)
select ord as "순서", what as "항목", now_value as "지금 값", before_ok as "실행 전 정상", after_ok as "실행 후 정상"
from (
  select 1 as ord, '처리 기록 표 (030)' as what, (to_regclass('public.moderation_log') is not null)::text as now_value, 'true' as before_ok, 'true' as after_ok
  union all select 2, 'purge_old_moderation_log 함수', c.has_fn::text, 'false', 'true' from c
  union all select 3, '설정값 moderation_log_keep_days (일)',
    coalesce((select value::text from public.xp_rules where key = 'moderation_log_keep_days'), '없음'), '없음', '365'
  union all select 4, '사람(로그인·비로그인)이 삭제 함수를 부를 수 있나 (false여야 함)',
    case when c.has_fn then (select (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))::text
                             from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'purge_old_moderation_log')
         else '함수 없음' end, '함수 없음', 'false' from c
  union all select 5, '삭제 함수가 처리 기록만 지우나 (moderation_log 사용 · 설정값 사용)',
    case when c.has_fn then (select (prosrc like '%delete from public.moderation_log%' and prosrc like '%moderation_log_keep_days%')::text
                             from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'purge_old_moderation_log')
         else '함수 없음' end, '함수 없음', 'true' from c
  union all select 6, '처리 기록 전체 수 (실행 전후 같아야 함 — 035는 아무것도 지우지 않음)', (select count(*)::text from public.moderation_log), '-', '실행 전과 같음'
  union all select 7, '보관 기간이 이미 지난 기록 수 (지금 지워질 후보 · 일정이 돈 뒤에는 0)',
    (select count(*)::text from public.moderation_log
      where created_at < now() - make_interval(days => coalesce((select value::integer from public.xp_rules where key = 'moderation_log_keep_days'), 365))), '-', '일정 등록 전: 0 이상 · 첫 실행 뒤: 0'
  union all select 8, '가장 오래된 처리 기록 시각', coalesce((select min(created_at)::text from public.moderation_log), '기록 없음'), '-', '1년 안이어야 함 (일정이 돈 뒤)'
  union all select 9, 'pg_cron 일정 개수 (purge-old-moderation-log)',
    case when to_regclass('cron.job') is null then 'cron 없음'
         else (xpath('/row/c/text()', query_to_xml('select count(*) as c from cron.job where jobname = ''purge-old-moderation-log''', false, true, '')))[1]::text end,
    '0', '일정 등록 뒤: 1'
  union all select 10, 'pg_cron 일정 시각 (UTC 19:20 = 한국 새벽 4:20)',
    case when to_regclass('cron.job') is null then 'cron 없음'
         else coalesce((xpath('/row/c/text()', query_to_xml('select schedule as c from cron.job where jobname = ''purge-old-moderation-log''', false, true, '')))[1]::text, '등록 안 됨') end,
    '등록 안 됨', '20 19 * * *'
  union all select 11, 'pg_cron 일정이 켜져 있나 (active)',
    case when to_regclass('cron.job') is null then 'cron 없음'
         else coalesce((xpath('/row/c/text()', query_to_xml('select active::text as c from cron.job where jobname = ''purge-old-moderation-log''', false, true, '')))[1]::text, '등록 안 됨') end,
    '등록 안 됨', 'true'
  union all select 12, '다른 정리 일정과 시각이 겹치나 (0이어야 함)',
    case when to_regclass('cron.job') is null then 'cron 없음'
         else (xpath('/row/c/text()', query_to_xml('select count(*) as c from cron.job where jobname <> ''purge-old-moderation-log'' and schedule = ''20 19 * * *''', false, true, '')))[1]::text end,
    '0', '0'
  union all select 13, '기존 알림 수 (실행 전후 같아야 함)', (select count(*)::text from public.notifications), '-', '실행 전과 같음'
  union all select 14, '기존 문의 수 (실행 전후 같아야 함)', case when to_regclass('public.inquiries') is null then '표 없음' else (xpath('/row/c/text()', query_to_xml('select count(*) as c from public.inquiries', false, true, '')))[1]::text end, '-', '실행 전과 같음'
) x
order by ord;
