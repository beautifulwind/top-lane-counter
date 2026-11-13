-- =====================================================================
-- 052: 장인 새 팔로워 알림 - 하루 한 번 묶음 (2026-11-13, SPEC 6-38)
--
-- 1. 알림 new_followers (새 종류, 푸시 묶음 new_followers - 푸시 설정 "새 팔로워", 기본 꺼짐)
--    - pg_cron 'new-follower-digest'가 하루에 한 번(한국 시간 낮 12시 = UTC 03:00) new_follower_digest()를 부른다.
--      그날 새 팔로워가 생긴 장인에게만 알림 한 개: "오늘 새 팔로워 N명이 생겼습니다." 새 팔로워가 없으면 알림 없음.
--    - 누가 팔로우했는지는 알림에 적지 않는다(숫자만). 화면에서 누르면 내 장인 페이지의 팔로워 목록(/me/followers -> /u/내 id).
--    - 알림함에만 쌓이고 휴대폰 알림은 기본 꺼짐(push_settings.new_followers = false). 켠 사람에게만 간다.
-- 2. N을 세는 규칙
--    - 지난 25시간 안에 팔로우했고 "지금도 팔로우 중"인 사람만 센다(influencer_follows에 남아 있는 줄).
--      그래서 하루가 지나기 전에 취소한 사람은 세지 않는다. 25시간 = 하루 + 크론이 조금 늦게 도는 여유.
--    - 한 번 센 (장인, 팔로워) 짝은 30일 동안 기록(new_follower_counted)해 두고 다시 세지 않는다.
--      같은 사람이 팔로우했다 취소했다를 되풀이해도, 창이 겹쳐도, 크론이 두 번 돌아도 N과 알림이 늘지 않는다.
--      (30일이 지나면 기록은 지워진다 - 그 뒤 다시 팔로우하면 새 팔로워로 센다.)
--    - 같은 날 크론이 또 돌면 이미 센 사람은 빠지므로 새로 생긴 사람이 없으면 알림이 생기지 않는다.
-- 3. 받지 않는 사람
--    - 인증이 해제된 장인: profiles.influencer가 비면 대상에서 빠진다(050 트리거가 팔로우도 지움). 052 트리거가 센 기록도 지운다.
--    - 탈퇴/정리된 계정: 프로필이 지워지면 팔로우와 센 기록이 함께 지워진다(on delete cascade) - 대상에 없다.
-- 4. 새 표 new_follower_counted (RLS 켬, 정책 없음, anon/authenticated 권한 회수 = 직접 읽기/쓰기 불가).
--    읽기 정책/모두 읽음 처리는 고치지 않는다: 받는 사람 본인의 알림이라 운영자 모드와 관계없이 보이고 모두 읽음에 함께 처리된다.
--
-- 새 설정값 없음(63 그대로). 처리 기록 종류 없음. pg_cron 일정 1개(아래 등록 SQL).
-- Edge Function web-push 재배포 필요(새 팔로워 알림을 제목 "새 팔로워" + 문장, 누르면 /me/followers로 보내도록 고쳤다).
--   재배포 전에도 푸시를 켠 사람에게는 간다(제목 "탑신병자" + 알림 문장, 누르면 알림 목록).
--
-- >> pg_cron 일정 등록 (실행 뒤 따로 한 번). 시간은 UTC 기준: 03:00 UTC = 한국 시간 낮 12:00 (한국은 서머타임 없음)
--     select cron.schedule('new-follower-digest', '0 3 * * *', $$select public.new_follower_digest()$$);
--
-- >> 되돌리기 (rollback) - 문제가 생기면 SQL Editor에서 아래를 한 번에 실행한다. 052가 만든 것만 지우고 051 상태로 돌아간다.
--    (이미 보낸 new_followers 알림과 센 기록도 지워진다. 팔로우 기록과 푸시 설정의 다른 칸은 그대로.)
--     begin;
--     do $r$ begin
--       if to_regclass('cron.job') is not null then
--         perform cron.unschedule(jobid) from cron.job where jobname = 'new-follower-digest';
--       end if;
--     end $r$;
--     drop trigger if exists new_follower_counted_on_influencer_end on public.profiles;
--     drop function if exists public.new_follower_counted_on_influencer_end();
--     drop function if exists public.new_follower_digest();
--     drop table if exists public.new_follower_counted;
--     drop index if exists public.influencer_follows_created;
--     delete from public.notifications where kind = 'new_followers';
--     alter table public.notifications drop constraint notifications_kind_check;
--     alter table public.notifications add constraint notifications_kind_check check (kind = any (array[
--       'revision_request', 'revision_cancelled', 'proposal_approved', 'proposal_rejected', 'build_approved', 'build_rejected',
--       'build_hidden', 'build_restored', 'level_up', 'level_down', 'title_earned', 'title_revoked',
--       'post_comment', 'post_hidden', 'post_restored', 'comment_hidden', 'comment_restored',
--       'doc_comment', 'doc_comment_hidden', 'doc_comment_restored', 'moderator_granted', 'moderator_revoked',
--       'inquiry_answered', 'proposal_submitted', 'build_submitted', 'inquiry_received', 'counter_restored',
--       'matchup_created', 'build_created', 'post_deleted', 'comment_deleted', 'doc_comment_deleted', 'post_created',
--       'error_reported', 'error_report_handled', 'report_received',
--       'influencer_applied', 'influencer_received', 'influencer_expiring', 'influencer_approved', 'influencer_rejected',
--       'influencer_expired', 'influencer_revoked', 'nickname_reset_soon', 'nickname_reset', 'link_removed',
--       'followed_build_created', 'notice_posted']));
--     create or replace function public.push_group(p_kind text)
--     returns text language sql immutable set search_path = ''
--     as $f$
--       select case
--         when p_kind in ('proposal_submitted', 'build_submitted', 'inquiry_received', 'matchup_created', 'build_created', 'post_created',
--                         'error_reported', 'report_received', 'influencer_applied') then 'staff_new'
--         when p_kind in ('proposal_approved', 'proposal_rejected', 'build_approved', 'build_rejected',
--                         'revision_request', 'counter_restored', 'build_restored',
--                         'influencer_received', 'influencer_expiring', 'influencer_approved', 'influencer_rejected',
--                         'influencer_expired', 'influencer_revoked', 'nickname_reset_soon', 'nickname_reset', 'link_removed') then 'my_results'
--         when p_kind in ('followed_build_created') then 'follow_builds'
--         when p_kind in ('notice_posted') then 'notice'
--       end;
--     $f$;
--     comment on function public.push_group(text) is
--       '푸시로 보내는 알림 종류의 묶음: staff_new(운영진) / my_results(내 결과) / follow_builds(팔로우한 장인의 새 빌드, 050) / notice(공지, 051) / null(푸시 안 함)';
--     create or replace function public.push_wanted(p_user uuid, p_kind text)
--     returns boolean language sql stable security definer set search_path = ''
--     as $f$
--       select case public.push_group(p_kind)
--         when 'staff_new' then
--           exists (select 1 from public.profiles p
--                    where p.id = p_user and (p.role = 'moderator' or (p.role = 'admin' and p.operator_mode)))
--           and coalesce((select s.staff_new from public.push_settings s where s.user_id = p_user), true)
--         when 'my_results' then
--           coalesce((select s.my_results from public.push_settings s where s.user_id = p_user), true)
--         when 'follow_builds' then
--           coalesce((select s.follow_builds from public.push_settings s where s.user_id = p_user), true)
--         when 'notice' then
--           coalesce((select s.notice from public.push_settings s where s.user_id = p_user), true)
--         else false
--       end
--       and exists (select 1 from public.push_subscriptions where user_id = p_user);
--     $f$;
--     alter table public.push_settings drop column new_followers;
--     commit;
--   되돌린 뒤 다시 052를 실행해도 된다(처음부터 다시 만든다).
--
-- 하위 호환: 있던 표/함수의 이름/인자/반환은 그대로. 새 표 1개/새 함수 2개/트리거 1개/인덱스 1개/알림 종류 1개/푸시 설정 칸 1개만 더한다.
-- 순서: check_new_followers_before.sql -> 이 파일 실행 -> check_new_followers_after.sql -> pg_cron 일정 등록
--       -> check_new_followers_after.sql 마지막 줄 확인.
-- 051까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- =====================================================================

begin;

do $$
begin
  if not exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'posts' and column_name = 'is_notice') then
    raise exception '051이 아직 실행되지 않았습니다. 051을 먼저 실행해 주세요.';
  end if;
  if to_regclass('public.new_follower_counted') is not null then
    raise exception '052를 이미 실행했습니다.';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 1. 표: 한 번 센 (장인, 팔로워) 짝 (30일 보관). 직접 읽기/쓰기 불가
-- ---------------------------------------------------------------------
create table public.new_follower_counted (
  influencer_id  uuid not null references public.profiles (id) on delete cascade,
  follower_id    uuid not null references public.profiles (id) on delete cascade,
  counted_at     timestamptz not null default now(),
  primary key (influencer_id, follower_id)
);
create index new_follower_counted_at on public.new_follower_counted (counted_at);
comment on table public.new_follower_counted is
  '새 팔로워 알림에서 이미 센 (장인, 팔로워) 짝 (052). 30일 뒤 지움. 팔로우/취소를 되풀이해도 다시 세지 않게. 직접 읽기/쓰기 불가';
alter table public.new_follower_counted enable row level security;
revoke all on public.new_follower_counted from anon, authenticated;

-- 하루 한 번 "지난 25시간 안의 팔로우"만 훑는다
create index influencer_follows_created on public.influencer_follows (created_at);

-- ---------------------------------------------------------------------
-- 2. 알림 종류 / 푸시 묶음 / 푸시 설정 칸 (기본 꺼짐)
-- ---------------------------------------------------------------------
alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check check (kind = any (array[
  'revision_request', 'revision_cancelled', 'proposal_approved', 'proposal_rejected', 'build_approved', 'build_rejected',
  'build_hidden', 'build_restored', 'level_up', 'level_down', 'title_earned', 'title_revoked',
  'post_comment', 'post_hidden', 'post_restored', 'comment_hidden', 'comment_restored',
  'doc_comment', 'doc_comment_hidden', 'doc_comment_restored', 'moderator_granted', 'moderator_revoked',
  'inquiry_answered', 'proposal_submitted', 'build_submitted', 'inquiry_received', 'counter_restored',
  'matchup_created', 'build_created', 'post_deleted', 'comment_deleted', 'doc_comment_deleted', 'post_created',
  'error_reported', 'error_report_handled', 'report_received',
  'influencer_applied', 'influencer_received', 'influencer_expiring', 'influencer_approved', 'influencer_rejected',
  'influencer_expired', 'influencer_revoked', 'nickname_reset_soon', 'nickname_reset', 'link_removed',
  'followed_build_created', 'notice_posted',
  'new_followers'  -- 052
]));

alter table public.push_settings add column new_followers boolean not null default false;
comment on column public.push_settings.new_followers is '장인 새 팔로워 휴대폰 알림 (052). 기본 꺼짐';
grant update (new_followers) on public.push_settings to authenticated;  -- 본인 줄만 (RLS 그대로)

create or replace function public.push_group(p_kind text)
returns text language sql immutable set search_path = ''
as $$
  select case
    when p_kind in ('proposal_submitted', 'build_submitted', 'inquiry_received', 'matchup_created', 'build_created', 'post_created',
                    'error_reported', 'report_received', 'influencer_applied') then 'staff_new'
    when p_kind in ('proposal_approved', 'proposal_rejected', 'build_approved', 'build_rejected',
                    'revision_request', 'counter_restored', 'build_restored',
                    'influencer_received', 'influencer_expiring', 'influencer_approved', 'influencer_rejected',
                    'influencer_expired', 'influencer_revoked', 'nickname_reset_soon', 'nickname_reset', 'link_removed') then 'my_results'
    when p_kind in ('followed_build_created') then 'follow_builds'
    when p_kind in ('notice_posted') then 'notice'
    when p_kind in ('new_followers') then 'new_followers'
  end;
$$;
comment on function public.push_group(text) is
  '푸시로 보내는 알림 종류의 묶음: staff_new(운영진) / my_results(내 결과) / follow_builds(팔로우한 장인의 새 빌드, 050) / notice(공지, 051) / new_followers(장인 새 팔로워, 052 - 기본 꺼짐) / null(푸시 안 함)';

create or replace function public.push_wanted(p_user uuid, p_kind text)
returns boolean language sql stable security definer set search_path = ''
as $$
  select case public.push_group(p_kind)
    when 'staff_new' then
      exists (select 1 from public.profiles p
               where p.id = p_user and (p.role = 'moderator' or (p.role = 'admin' and p.operator_mode)))
      and coalesce((select s.staff_new from public.push_settings s where s.user_id = p_user), true)
    when 'my_results' then
      coalesce((select s.my_results from public.push_settings s where s.user_id = p_user), true)
    when 'follow_builds' then
      coalesce((select s.follow_builds from public.push_settings s where s.user_id = p_user), true)
    when 'notice' then
      coalesce((select s.notice from public.push_settings s where s.user_id = p_user), true)
    when 'new_followers' then
      coalesce((select s.new_followers from public.push_settings s where s.user_id = p_user), false)  -- 설정 줄이 없으면 꺼짐
    else false
  end
  and exists (select 1 from public.push_subscriptions where user_id = p_user);
$$;

-- ---------------------------------------------------------------------
-- 3. 하루 묶음 (pg_cron new-follower-digest, 하루 한 번)
--    돌려주는 값: { notified: 알림을 받은 장인 수, counted: 이번에 센 팔로워 수, pruned: 30일 지나 지운 기록 수 }
-- ---------------------------------------------------------------------
create function public.new_follower_digest()
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  win constant interval := interval '25 hours';
  keep constant interval := interval '30 days';
  n_notified integer := 0;
  n_counted integer := 0;
  n_pruned integer := 0;
begin
  -- 두 번 겹쳐 돌지 않게
  if not pg_try_advisory_xact_lock(hashtext('new_follower_digest')) then
    return jsonb_build_object('notified', 0, 'counted', 0, 'pruned', 0, 'skipped', true);
  end if;
  delete from public.new_follower_counted where counted_at < now() - keep;
  get diagnostics n_pruned = row_count;
  with fresh as (
    -- 지금도 팔로우 중 + 지난 25시간 안에 팔로우 + 받는 사람이 지금 인증된 장인
    select f.influencer_id, f.follower_id
      from public.influencer_follows f
      join public.profiles a on a.id = f.influencer_id and a.influencer is not null
     where f.created_at > now() - win
       and f.follower_id <> f.influencer_id
  ), mark as (
    -- 이미 센 짝은 on conflict로 빠진다 = 새로 센 사람만 남는다
    insert into public.new_follower_counted (influencer_id, follower_id)
    select influencer_id, follower_id from fresh
    on conflict (influencer_id, follower_id) do nothing
    returning influencer_id
  ), ins as (
    insert into public.notifications (user_id, kind, message)
    select m.influencer_id, 'new_followers', format('오늘 새 팔로워 %s명이 생겼습니다.', count(*))
      from mark m
     group by m.influencer_id
    returning 1
  )
  select (select count(*) from mark), (select count(*) from ins) into n_counted, n_notified;
  return jsonb_build_object('notified', n_notified, 'counted', n_counted, 'pruned', n_pruned);
end;
$$;

-- ---------------------------------------------------------------------
-- 4. 장인 인증이 끝나면 센 기록도 지운다 (050 follows_on_influencer_end와 같은 때. 탈퇴/게스트 정리는 cascade)
-- ---------------------------------------------------------------------
create function public.new_follower_counted_on_influencer_end()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  delete from public.new_follower_counted where influencer_id = new.id;
  return null;
end;
$$;
create trigger new_follower_counted_on_influencer_end
  after update of influencer on public.profiles
  for each row when (old.influencer is not null and new.influencer is null)
  execute function public.new_follower_counted_on_influencer_end();

-- ---------------------------------------------------------------------
-- 5. 권한: 아무도 직접 못 부름 (pg_cron만). push_group/push_wanted는 create or replace라 있던 권한 그대로
-- ---------------------------------------------------------------------
revoke execute on function public.new_follower_digest() from public, anon, authenticated;
revoke execute on function public.new_follower_counted_on_influencer_end() from public, anon, authenticated;

commit;

-- 확인 (실행 뒤): supabase/scripts/check_new_followers_after.sql
-- pg_cron 일정 등록 (실행 뒤 따로 한 번, 03:00 UTC = 한국 시간 낮 12:00):
--   select cron.schedule('new-follower-digest', '0 3 * * *', $$select public.new_follower_digest()$$);
