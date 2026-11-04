-- =====================================================================
-- 027: 알림 화면 /notifications (2026-11-04, SPEC 6-17)
-- 1. 사용자별 최신순 색인: 알림 화면이 내 알림을 번호(id) 큰 순으로 20개씩 이어서 읽는다
-- 2. mark_all_notifications_read(p_upto): 알림 화면을 열면 그 화면의 맨 위 알림 번호까지 내 안 읽은 알림을 한 번에 읽음 처리.
--    처리한 시각을 돌려준다 (화면이 "이번에 읽음 처리한 것"에 "새" 표시를 남기는 데 쓴다)
-- 3. 보관 기간: 만든 지 notification_keep_days(90)일 지난 알림은 purge_old_notifications()가 지운다.
--    pg_cron 일정은 이 파일 맨 아래 SQL을 따로 실행해 등록한다.
-- 표·알림 종류는 그대로. 예전 mark_notifications_read(p_ids)도 그대로 둔다.
-- 026_tone_hamnida.sql까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다. 여러 번 실행해도 결과는 같다.
-- =====================================================================

begin;

-- 1. 색인
create index if not exists notifications_user_recent_idx on public.notifications (user_id, id desc);

-- 2. 모두 읽음 처리 (본인 것만)
create or replace function public.mark_all_notifications_read(p_upto bigint)
returns timestamptz language plpgsql security definer set search_path = ''
as $$
declare
  t timestamptz := now();
begin
  if (select auth.uid()) is null then
    raise exception '로그인이 필요합니다.' using errcode = '42501';
  end if;
  update public.notifications
     set read_at = t
   where user_id = (select auth.uid()) and read_at is null and id <= p_upto;
  return t;
end;
$$;
revoke execute on function public.mark_all_notifications_read(bigint) from public, anon;
grant execute on function public.mark_all_notifications_read(bigint) to authenticated;

-- 3. 보관 기간 (숫자는 다른 설정처럼 xp_rules 한 곳에)
insert into public.xp_rules (key, value, note)
values ('notification_keep_days', 90, '알림 보관 기간(일): 만든 지 이만큼 지난 알림은 매일 지운다 (purge_old_notifications, pg_cron)')
on conflict (key) do nothing;

create or replace function public.purge_old_notifications()
returns integer language plpgsql security definer set search_path = ''
as $$
declare
  n integer;
begin
  delete from public.notifications
   where created_at < now() - make_interval(days => public.xp_rule('notification_keep_days'));
  get diagnostics n = row_count;
  return n;
end;
$$;
-- 사람은 못 부르고 pg_cron(postgres)만
revoke execute on function public.purge_old_notifications() from public, anon, authenticated;

comment on table public.notifications is
  '알림 — /notifications에서 보고, 화면을 열면 읽음 처리돼 ☰·[알림]의 빨간 점이 꺼진다. notification_keep_days(90)일 지나면 지운다';

commit;

-- 확인 (실행 뒤):
-- select (select count(*) from pg_indexes where indexname = 'notifications_user_recent_idx') as idx,          -- 1
--        (select value from public.xp_rules where key = 'notification_keep_days') as keep_days;                -- 90

-- ---------------------------------------------------------------------
-- pg_cron 일정 등록 (위를 실행한 뒤 따로 한 번): 매일 한국 시간 새벽 4시 (UTC 19시)
-- (Supabase 대시보드 Integrations → Cron이 켜져 있어야 한다. 같은 이름으로 다시 실행하면 일정이 바뀐다)
--
-- select cron.schedule('purge-old-notifications', '0 19 * * *', $$select public.purge_old_notifications()$$);
--
-- 확인: select jobname, schedule, command, active from cron.job where jobname = 'purge-old-notifications';
-- 끄기: select cron.unschedule('purge-old-notifications');
-- ---------------------------------------------------------------------
