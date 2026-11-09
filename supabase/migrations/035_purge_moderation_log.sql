-- =====================================================================
-- 035: 운영진 처리 기록(moderation_log) 1년 보관 후 자동 삭제 (2026-11-09, SPEC 6-22)
--
-- 1. 설정값 moderation_log_keep_days = 365 (xp_rules 한 곳, 다른 보관 기간과 같은 방식)
-- 2. purge_old_moderation_log(): 처리한 날(created_at)부터 보관 기간이 지난 기록을 지우고 지운 개수를 돌려준다.
--    사람은 못 부르고 pg_cron만 (purge_old_notifications·purge_old_inquiries와 같음). 지정·해제 기록도 같은 기준.
-- 3. 개인정보처리방침 4번에 "처리한 날부터 1년" 반영 (화면 문구, 이 파일과 함께 배포).
--
-- 하위 호환: 있던 표·함수는 바꾸지 않고 더하기만 한다. 실행 직후에는 아무것도 지워지지 않는다
-- (pg_cron 일정을 등록해야 매일 돈다). 순서: 이 파일 실행 → supabase/scripts/check_purge_moderation_log.sql로 확인 → 일정 등록.
-- 034까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- =====================================================================

begin;

insert into public.xp_rules (key, value, note) values
  ('moderation_log_keep_days', 365, '운영진 처리 기록 보관 기간(일) — 처리한 날부터 이만큼(1년) 지나면 매일 지운다 (purge_old_moderation_log, pg_cron)')
on conflict (key) do nothing;

create function public.purge_old_moderation_log()
returns integer language plpgsql security definer set search_path = ''
as $$
declare
  n integer;
begin
  delete from public.moderation_log
   where created_at < now() - make_interval(days => public.xp_rule('moderation_log_keep_days'));
  get diagnostics n = row_count;
  return n;
end;
$$;
comment on function public.purge_old_moderation_log() is
  '보관 기간(moderation_log_keep_days, 365일)이 지난 처리 기록 삭제. 사람은 못 부르고 pg_cron만';

-- 사람은 못 부르고 pg_cron(postgres)만
revoke execute on function public.purge_old_moderation_log() from public, anon, authenticated;

comment on table public.moderation_log is
  '운영자·감독관의 처리 기록 (030). 숨김·다시 공개·신고 기각·새 카운터 승인/반려·감독관 지정/해제 등. 운영자만 읽고 아무도 직접 못 씀. 처리자 탈퇴 후에도 남지만 moderation_log_keep_days(365)일이 지나면 지움 (035)';

commit;

-- 확인 (실행 뒤): supabase/scripts/check_purge_moderation_log.sql

-- ---------------------------------------------------------------------
-- pg_cron 일정 등록 (위를 실행한 뒤 따로 한 번): 매일 한국 시간 새벽 4시 20분 (UTC 19시 20분)
-- 겹치지 않게: 알림 4:00(19:00) · 문의 4:10(19:10) · 처리 기록 4:20(19:20) · 비회원 정리 4:30(19:30) · 사진 정리 4:40(19:40)
-- (같은 이름으로 다시 실행하면 일정이 바뀐다)
--
-- select cron.schedule('purge-old-moderation-log', '20 19 * * *', $$select public.purge_old_moderation_log()$$);
--
-- 확인: select jobname, schedule, command, active from cron.job where jobname = 'purge-old-moderation-log';
-- 실행 기록: select status, start_time from cron.job_run_details where command like '%purge_old_moderation_log%' order by start_time desc limit 5;
-- 끄기: select cron.unschedule('purge-old-moderation-log');
-- ---------------------------------------------------------------------
