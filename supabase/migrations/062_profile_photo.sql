-- =====================================================================
-- 062: 장인 프로필 사진 (2026-11-21, SPEC 6-71) - 추가만 하는 변경. App Store 심사 가이드 1.2(UGC) 대응: 신고 + 운영자 삭제
--
-- 1. 비공개 버킷 profile-photos (파일당 1MB, webp·jpeg). 경로 = 사용자id/임의이름.webp(또는 .jpg). 올릴 때마다 새 이름(덮어쓰기 없음)
--    -> 사진을 바꾸면 주소가 바뀌어서 옛 사진이 캐시로 보이지 않는다.
--    화면이 올리기 전에 가운데를 정사각형으로 잘라 512x512로 줄이고 다시 저장한다(촬영 위치 같은 사진 정보가 빠짐).
--    - 올리기: 인증된 장인 본인만, 내 폴더에만, 폴더에 파일 5개까지, 24시간에 사진 바꾸기 profile_photo_daily_max(10)번까지
--    - 보기: 누구나(비로그인 포함) - 단, 장인의 "지금 사진"일 때만. 내 폴더 파일은 나도 본다.
--      바꾸거나 지우거나 운영자가 지우거나 인증이 끝나면 그 순간부터 옛 파일은 아무도(본인 빼고) 못 본다.
--    - 지우기: 본인 폴더의 파일 중 "지금 사진이 아닌 것"만 (바꾼 직후 화면이 옛 파일을 바로 지운다). 고치기(update)는 없음.
-- 2. profiles에 photo_path / photo_updated_at (누구나 읽음, 직접 못 고침 - 아래 함수로만).
--    set_profile_photo(경로) / clear_profile_photo(): 장인 본인. remove_profile_photo(사람, 사유): 운영자만(감독관 불가),
--    장인에게 profile_photo_removed 알림(링크 삭제와 같이 알림함 + 휴대폰 알림 my_results), 처리 기록 remove_profile_photo.
-- 3. 사진이 바뀌거나 지워지면(본인·운영자·인증 해제·탈퇴) 옛 경로를 profile_photo_trash에 넣는다.
--    Edge Function media-cleanup(다시 배포 필요)이 매일 이 대기열 + 올리고 24시간 동안 안 쓴 파일을 Storage API로 지운다.
--    장인 인증이 끝나면(해제 등 influencer가 비워지는 모든 길) 사진을 바로 비운다.
-- 4. 신고 profile_photo_reports: 정식 회원, 남의 사진만, 같은 사진은 한 번. 사유 obscene·hate·impersonation·spam·other(내용 필수).
--    처리 전 신고가 처음 생기면 운영자에게 report_received "(프로필 사진)". 운영자 목록 admin_profile_photo_reports, 기각 dismiss_profile_photo_reports.
--    사진이 바뀌거나 지워지면 그 사진의 처리 전 신고는 저절로 닫힌다(운영자가 지우면 "처리됨", 그 밖은 "기각").
-- 5. public_profile 응답에 photo_path.
-- 사용자 차단(061)과는 따로 움직인다: 차단한 장인의 페이지는 지금처럼 안내만 보여서 사진도 안 보인다. 운영자 화면은 차단과 상관없다.
--
-- 새 pg_cron 일정 없음 (기존 media-cleanup 일정이 두 버킷을 같이 정리). Edge Function media-cleanup·web-push 다시 배포 필요.
-- 실행 전 supabase/scripts/check_profile_photo_before.sql, 실행 뒤 check_profile_photo_after.sql.
-- 061까지 실행한 DB에서 SQL Editor에 통째로 붙여넣어 "한 번" 실행한다. 지금 화면(사진 기능 전)과도 호환된다 - SQL을 먼저 실행한다.
--
-- >> 되돌리기 (rollback) - 문제가 생기면 SQL Editor에서 아래를 한 번에 실행한다(맨 앞 "-- "는 빼고). 061 상태로 돌아간다.
--    되돌릴 수 없는 것: 프로필 사진 연결·신고 기록, 사진 삭제 알림·처리 기록 줄은 지워진다.
--    버킷 profile-photos와 그 안의 파일은 SQL로 지울 수 없어서 남는다 -> 대시보드 Storage에서 버킷을 비우고(Empty) 삭제(Delete)한다.
--    (화면은 사진 칸이 없으면 사진 없이 예전처럼 보인다)
--     begin;
--     -- 1) Storage 규칙 (함수를 쓰므로 먼저)
--     drop policy if exists "profile-photos 올리기" on storage.objects;
--     drop policy if exists "profile-photos 보기" on storage.objects;
--     drop policy if exists "profile-photos 지우기" on storage.objects;
--     -- 2) 트리거
--     drop trigger if exists profiles_photo_on_influencer_end on public.profiles;
--     drop trigger if exists profiles_photo_changed on public.profiles;
--     drop trigger if exists profiles_photo_on_delete on public.profiles;
--     drop trigger if exists profile_photo_reports_notify on public.profile_photo_reports;
--     -- 3) 새 함수
--     drop function if exists public.set_profile_photo(text);
--     drop function if exists public.clear_profile_photo();
--     drop function if exists public.remove_profile_photo(uuid, text);
--     drop function if exists public.report_profile_photo(uuid, text, text);
--     drop function if exists public.admin_profile_photo_reports(integer, integer);
--     drop function if exists public.dismiss_profile_photo_reports(uuid, text);
--     drop function if exists public.profile_photo_upload_problem();
--     drop function if exists public.profile_photo_visible(text);
--     drop function if exists public.profile_photo_deletable(text);
--     drop function if exists public.profile_photo_cleanup_list(integer);
--     drop function if exists public.profile_photo_cleanup_done(text[]);
--     drop function if exists public.profile_photo_clear_on_influencer_end();
--     drop function if exists public.profile_photo_after_change();
--     drop function if exists public.profile_photo_on_profile_delete();
--     drop function if exists public.notify_staff_new_photo_report();
--     -- 4) 새 표와 프로필 칸
--     drop table if exists public.profile_photo_reports;
--     drop table if exists public.profile_photo_trash;
--     drop table if exists public.profile_photo_changes;
--     alter table public.profiles drop constraint if exists profiles_photo_pair;
--     alter table public.profiles drop constraint if exists profiles_photo_path_shape;
--     alter table public.profiles drop constraint if exists profiles_photo_influencer;
--     alter table public.profiles drop column if exists photo_path;
--     alter table public.profiles drop column if exists photo_updated_at;
--     delete from public.xp_rules where key = 'profile_photo_daily_max';
--     -- 5) 062가 만든 알림·처리 기록 줄을 지우고 허용 목록을 061 상태로
--     delete from public.notifications where kind = 'profile_photo_removed';
--     delete from public.moderation_log where action = 'remove_profile_photo';
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
--       'followed_build_created', 'notice_posted', 'new_followers', 'comment_reply']));
--     alter table public.moderation_log drop constraint moderation_log_action_check;
--     alter table public.moderation_log add constraint moderation_log_action_check check (action = any (array[
--       'hide', 'restore', 'dismiss_reports', 'approve_proposal', 'reject_proposal', 'grant_moderator', 'revoke_moderator',
--       'answer_inquiry', 'move_inquiry', 'edit_proposal', 'request_revision', 'delete', 'revert', 'resolve_report', 'dismiss_report',
--       'approve_influencer', 'reject_influencer', 'extend_influencer', 'revoke_influencer', 'rename_member',
--       'remove_link', 'add_link_domain', 'remove_link_domain', 'grant_influencer', 'grant_title', 'revoke_title']));
--     -- 6) 바꾼 함수를 061 내용으로
--     CREATE OR REPLACE FUNCTION public.push_group(p_kind text)
--      RETURNS text
--      LANGUAGE sql
--      IMMUTABLE
--      SET search_path TO ''
--     AS $function$
--       select case
--         when p_kind in ('proposal_submitted', 'build_submitted', 'inquiry_received', 'matchup_created', 'build_created', 'post_created',
--                         'error_reported', 'report_received', 'influencer_applied') then 'staff_new'
--         when p_kind in ('proposal_approved', 'proposal_rejected', 'build_approved', 'build_rejected',
--                         'revision_request', 'counter_restored', 'build_restored',
--                         'influencer_received', 'influencer_expiring', 'influencer_approved', 'influencer_rejected',
--                         'influencer_expired', 'influencer_revoked', 'nickname_reset_soon', 'nickname_reset', 'link_removed') then 'my_results'
--         when p_kind in ('followed_build_created') then 'follow_builds'
--         when p_kind in ('notice_posted') then 'notice'
--         when p_kind in ('new_followers') then 'new_followers'
--       end;
--     $function$;
--     CREATE OR REPLACE FUNCTION public.public_profile(p_user text)
--      RETURNS jsonb
--      LANGUAGE plpgsql
--      STABLE SECURITY DEFINER
--      SET search_path TO ''
--     AS $function$
--     declare
--       uid uuid;
--       p public.profiles%rowtype;
--     begin
--       if p_user is null or p_user !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
--         return null;
--       end if;
--       uid := p_user::uuid;
--       select * into p from public.profiles where id = uid and influencer is not null and nickname is not null;
--       if not found then
--         return null;
--       end if;
--       return jsonb_build_object(
--         'id', p.id,
--         'nickname', p.nickname,
--         'influencer', p.influencer,
--         'links', coalesce((select jsonb_agg(public.ext_link_json(l.id) order by l.sort)
--                              from public.ext_links l where l.owner_id = p.id and l.build_id is null and public.ext_link_visible(l.id)), '[]'::jsonb),
--         'build_count', (select count(*) from public.builds b join public.counters c on c.id = b.counter_id
--                          where b.author_id = p.id and b.status = 'approved' and c.status = 'approved'),
--         'builds', coalesce((select jsonb_agg(x.j order by x.created_at desc, x.id desc) from (
--                     select b.id, b.created_at, jsonb_build_object(
--                              'id', b.id, 'counter_id', b.counter_id, 'seq', b.seq, 'name', b.name, 'patch', b.patch,
--                              'target_champion', c.target_champion, 'counter_champion', c.counter_champion,
--                              'created_at', b.created_at,
--                              'link', (select public.ext_link_json(l.id) from public.ext_links l
--                                        where l.build_id = b.id and public.ext_link_visible(l.id))) as j
--                       from public.builds b join public.counters c on c.id = b.counter_id
--                      where b.author_id = p.id and b.status = 'approved' and c.status = 'approved'
--                      order by b.created_at desc, b.id desc
--                      limit 10) x), '[]'::jsonb));
--     end;
--     $function$;
--     commit;
--
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 0. 안전장치: 061까지 실행한 DB에서 한 번만
-- ---------------------------------------------------------------------
do $guard$
begin
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'profiles' and column_name = 'photo_path') then
    raise exception '062를 이미 실행했습니다 (profiles.photo_path 칸이 있음). 다시 실행하지 마세요. 아무것도 바뀌지 않았습니다.' using errcode = 'P0001';
  end if;
  if to_regclass('public.user_blocks') is null or to_regclass('public.storage_trash') is null
     or to_regprocedure('public.public_profile(text)') is null then
    raise exception '061까지 실행한 DB에서만 실행합니다. 아무것도 바뀌지 않았습니다.' using errcode = 'P0001';
  end if;
end;
$guard$;

-- ---------------------------------------------------------------------
-- 1. 숫자와 버킷
-- ---------------------------------------------------------------------
insert into public.xp_rules (key, value, note) values
  ('profile_photo_daily_max', 10, '장인 프로필 사진: 24시간 안에 사진을 바꿀 수 있는 횟수 (062)');

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('profile-photos', 'profile-photos', false, 1048576, array['image/webp', 'image/jpeg'])
on conflict (id) do update
  set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

-- ---------------------------------------------------------------------
-- 2. 프로필 칸 (누구나 읽음 - profiles 읽기 규칙 그대로. 사용자가 고칠 수 있는 칸은 그대로 nickname·main_title뿐)
-- ---------------------------------------------------------------------
alter table public.profiles
  add column photo_path text unique,
  add column photo_updated_at timestamptz,
  add constraint profiles_photo_pair check ((photo_path is null) = (photo_updated_at is null)),
  add constraint profiles_photo_path_shape check (photo_path is null or starts_with(photo_path, id::text || '/')),
  add constraint profiles_photo_influencer check (photo_path is null or influencer is not null);
comment on column public.profiles.photo_path is '장인 프로필 사진 경로 (062, 버킷 profile-photos). null = 사진 없음. 함수로만 바뀐다';
comment on column public.profiles.photo_updated_at is '장인 프로필 사진을 마지막으로 정한 때 (062)';

-- 사진 바꾸기 기록 (하루 횟수 세기용. 아무도 직접 못 읽음, 이틀 지난 줄은 다음에 바꿀 때 지운다)
create table public.profile_photo_changes (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now()
);
create index profile_photo_changes_user_idx on public.profile_photo_changes (user_id, created_at);
comment on table public.profile_photo_changes is '장인 프로필 사진을 바꾼 기록 (062, 하루 횟수 제한용). 아무도 직접 못 읽음';
revoke all on public.profile_photo_changes from anon, authenticated;
alter table public.profile_photo_changes enable row level security;

-- 지울 파일 대기열 (board-media의 storage_trash와 따로 - Edge Function이 버킷별로 지운다)
create table public.profile_photo_trash (
  path      text primary key,
  reason    text not null,
  queued_at timestamptz not null default now()
);
comment on table public.profile_photo_trash is '지울 Storage 파일 (profile-photos, 062). Edge Function media-cleanup이 지우고 줄을 뺀다. 아무도 직접 못 읽음';
revoke all on public.profile_photo_trash from anon, authenticated;
alter table public.profile_photo_trash enable row level security;

-- ---------------------------------------------------------------------
-- 3. 신고 표
-- ---------------------------------------------------------------------
create table public.profile_photo_reports (
  id            bigint generated always as identity primary key,
  owner_id      uuid not null references public.profiles (id) on delete cascade,
  photo_path    text not null,
  reporter_id   uuid not null references public.profiles (id) on delete cascade,
  reason        text not null check (reason in ('obscene', 'hate', 'impersonation', 'spam', 'other')),
  detail        text check (detail is null or char_length(detail) <= 500),
  status        text not null default 'open' check (status in ('open', 'resolved', 'dismissed')),
  handled_by    uuid references public.profiles (id) on delete set null,
  handled_at    timestamptz,
  handled_note  text,
  created_at    timestamptz not null default now(),
  check (reason <> 'other' or coalesce(btrim(detail), '') <> '')
);
create unique index profile_photo_reports_once on public.profile_photo_reports (reporter_id, photo_path);
create index profile_photo_reports_open on public.profile_photo_reports (photo_path, created_at) where status = 'open';
create index profile_photo_reports_owner on public.profile_photo_reports (owner_id);
comment on table public.profile_photo_reports is '장인 프로필 사진 신고 (062). 운영자만 함수로 본다. 사진이 바뀌면 처리 전 신고는 저절로 닫힌다';
revoke all on public.profile_photo_reports from anon, authenticated;
alter table public.profile_photo_reports enable row level security;

-- 새 신고 -> 운영자에게만 report_received (그 사진에 처리 전 신고가 처음 생길 때만, 신고자 본인 제외)
create function public.notify_staff_new_photo_report()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if new.status <> 'open' then
    return null;
  end if;
  perform pg_advisory_xact_lock(hashtext('report_received:profile_photo:' || new.photo_path));
  if exists (select 1 from public.profile_photo_reports r where r.status = 'open' and r.id <> new.id and r.photo_path = new.photo_path) then
    return null;
  end if;
  insert into public.notifications (user_id, kind, message)
  select u.id, 'report_received', '새 신고가 들어왔습니다. (프로필 사진)'
    from public.profiles u
   where u.role = 'admin' and u.id is distinct from new.reporter_id;
  return null;
end;
$$;
create trigger profile_photo_reports_notify after insert on public.profile_photo_reports
  for each row execute function public.notify_staff_new_photo_report();

-- ---------------------------------------------------------------------
-- 4. 사진이 바뀔 때 (트리거)
-- ---------------------------------------------------------------------
-- 장인 인증이 끝나면(influencer가 비워지는 모든 길) 사진도 같이 비운다 (profiles_photo_influencer 검사보다 먼저)
create function public.profile_photo_clear_on_influencer_end()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if new.influencer is null and new.photo_path is not null then
    new.photo_path := null;
    new.photo_updated_at := null;
  end if;
  return new;
end;
$$;
create trigger profiles_photo_on_influencer_end before update of influencer on public.profiles
  for each row execute function public.profile_photo_clear_on_influencer_end();

-- 옛 경로를 지울 파일 대기열에 넣고, 그 사진의 처리 전 신고를 닫는다 (운영자 삭제는 함수가 먼저 "처리됨"으로 닫는다)
create function public.profile_photo_after_change()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.profile_photo_trash (path, reason)
  values (old.photo_path, case when new.photo_path is null then 'cleared' else 'replaced' end)
  on conflict (path) do nothing;
  update public.profile_photo_reports
     set status = 'dismissed', handled_at = now(), handled_note = '사진이 바뀌거나 지워져 저절로 닫힘'
   where photo_path = old.photo_path and status = 'open';
  return null;
end;
$$;
create trigger profiles_photo_changed after update on public.profiles  -- "of photo_path"를 쓰면 인증 해제(트리거가 비움) 때 안 불린다
  for each row when (old.photo_path is not null and old.photo_path is distinct from new.photo_path)
  execute function public.profile_photo_after_change();

-- 탈퇴(프로필이 지워짐) -> 사진 파일도 대기열에 (신고 줄은 cascade로 지워진다)
create function public.profile_photo_on_profile_delete()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.profile_photo_trash (path, reason) values (old.photo_path, 'withdrawn')
  on conflict (path) do nothing;
  return old;
end;
$$;
create trigger profiles_photo_on_delete before delete on public.profiles
  for each row when (old.photo_path is not null)
  execute function public.profile_photo_on_profile_delete();

-- ---------------------------------------------------------------------
-- 5. Storage 규칙
-- ---------------------------------------------------------------------
-- 올릴 수 없는 이유 (올릴 수 있으면 null). Storage 규칙과 화면이 같이 쓴다
create function public.profile_photo_upload_problem()
returns text language plpgsql stable security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  daily integer := public.xp_rule('profile_photo_daily_max');
begin
  if me is null then
    return '로그인해야 프로필 사진을 올릴 수 있습니다.';
  end if;
  if not exists (select 1 from public.profiles where id = me and influencer is not null and nickname is not null and not is_guest) then
    return '인증된 장인만 프로필 사진을 올릴 수 있습니다.';
  end if;
  if (select count(*) from storage.objects o where o.bucket_id = 'profile-photos' and o.owner_id = me::text) >= 5 then
    return '올려 두고 쓰지 않은 사진이 많습니다. 하루 뒤 다시 시도해 주세요.';
  end if;
  if (select count(*) from public.profile_photo_changes c where c.user_id = me and c.created_at > now() - interval '24 hours') >= daily then
    return format('프로필 사진은 하루에 %s번까지 바꿀 수 있습니다. 내일 다시 해 주세요.', daily);
  end if;
  return null;
end;
$$;

-- 지금 어떤 장인의 프로필 사진인가 (누구나 볼 수 있는 파일)
create function public.profile_photo_visible(p_path text)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.profiles where photo_path = p_path and influencer is not null);
$$;

-- 내가 지울 수 있는 파일인가: 내 폴더 + 지금 내 사진이 아님
create function public.profile_photo_deletable(p_path text)
returns boolean language sql stable security definer set search_path = ''
as $$
  select (select auth.uid()) is not null
     and (storage.foldername(p_path))[1] = (select auth.uid())::text
     and p_path is distinct from (select photo_path from public.profiles where id = (select auth.uid()));
$$;

create policy "profile-photos 올리기" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = (select auth.uid())::text
    and public.profile_photo_upload_problem() is null
  );
create policy "profile-photos 보기" on storage.objects
  for select to anon, authenticated
  using (
    bucket_id = 'profile-photos'
    and (owner_id = (select auth.uid())::text or public.profile_photo_visible(name))
  );
create policy "profile-photos 지우기" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'profile-photos'
    and owner_id = (select auth.uid())::text
    and public.profile_photo_deletable(name)
  );

-- ---------------------------------------------------------------------
-- 6. 사진 정하기·지우기 (장인 본인)
-- ---------------------------------------------------------------------
create function public.set_profile_photo(p_path text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := public.board_writer();
  p public.profiles%rowtype;
  o record;
  m text;
  sz bigint;
  daily integer := public.xp_rule('profile_photo_daily_max');
begin
  select * into p from public.profiles where id = me for update;
  if p.influencer is null or p.is_guest then
    raise exception '인증된 장인만 프로필 사진을 올릴 수 있습니다.' using errcode = '42501';
  end if;
  if p_path is null or p_path !~ ('^' || me::text || '/[0-9A-Za-z_-]{1,64}\.(webp|jpg)$') then
    raise exception '사진을 다시 골라 주세요.' using errcode = '22023';
  end if;
  if p_path = p.photo_path then
    return;  -- 이미 이 사진
  end if;
  select ob.owner_id, ob.metadata into o from storage.objects ob where ob.bucket_id = 'profile-photos' and ob.name = p_path;
  if not found or o.owner_id is distinct from me::text then
    raise exception '올린 사진을 찾지 못했습니다. 사진을 다시 골라 주세요.' using errcode = '23514';
  end if;
  m := o.metadata ->> 'mimetype';
  sz := coalesce((o.metadata ->> 'size')::bigint, 0);
  if m is null or m not in ('image/webp', 'image/jpeg') or sz <= 0 or sz > 1048576 then
    raise exception '사진 형식이나 크기가 맞지 않습니다. 다른 사진을 골라 주세요.' using errcode = '23514';
  end if;
  delete from public.profile_photo_changes where user_id = me and created_at < now() - interval '2 days';
  if (select count(*) from public.profile_photo_changes where user_id = me and created_at > now() - interval '24 hours') >= daily then
    raise exception '프로필 사진은 하루에 %번까지 바꿀 수 있습니다. 내일 다시 해 주세요.', daily using errcode = '54000';
  end if;
  update public.profiles set photo_path = p_path, photo_updated_at = now() where id = me;
  insert into public.profile_photo_changes (user_id) values (me);
  delete from public.profile_photo_trash where path = p_path;  -- 혹시 대기열에 있던 내 파일을 다시 쓰면 지우지 않는다
end;
$$;

create function public.clear_profile_photo()
returns void language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
begin
  if me is null then
    raise exception '로그인이 필요합니다.' using errcode = '42501';
  end if;
  update public.profiles set photo_path = null, photo_updated_at = null where id = me and photo_path is not null;
end;
$$;

-- ---------------------------------------------------------------------
-- 7. 신고 (정식 회원)
-- ---------------------------------------------------------------------
create function public.report_profile_photo(p_user uuid, p_reason text, p_detail text default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := public.board_writer();
  d text := nullif(btrim(coalesce(p_detail, '')), '');
  path text;
begin
  if public.is_guest(me) then
    raise exception '비회원은 신고할 수 없습니다. 구글/카카오를 연결하면 할 수 있습니다.' using errcode = '42501';
  end if;
  if p_reason is null or p_reason not in ('obscene', 'hate', 'impersonation', 'spam', 'other') then
    raise exception '신고 이유를 골라 주세요.' using errcode = '23514';
  end if;
  if p_reason = 'other' and d is null then
    raise exception '기타 이유를 적어 주세요.' using errcode = '23514';
  end if;
  if char_length(d) > 500 then
    raise exception '신고 내용은 500자 이하로 적어 주세요.' using errcode = '23514';
  end if;
  if p_user = me then
    raise exception '내 사진은 신고할 수 없습니다.' using errcode = '23514';
  end if;
  select photo_path into path from public.profiles where id = p_user and influencer is not null;
  if path is null then
    raise exception '신고할 수 없는 사진입니다. 이미 바뀌었거나 지워졌을 수 있습니다.' using errcode = 'P0002';
  end if;
  insert into public.profile_photo_reports (owner_id, photo_path, reporter_id, reason, detail) values (p_user, path, me, p_reason, d);
exception when unique_violation then
  raise exception '이미 신고한 사진입니다.' using errcode = '23505';
end;
$$;

-- ---------------------------------------------------------------------
-- 8. 운영자 (운영자 모드가 켜진 운영자만 - 감독관 불가)
-- ---------------------------------------------------------------------
-- 처리 전 신고 목록 (사진별로 묶음, 오래된 신고 먼저): { total, page, size, photos: [{ owner, photo_path, reports: [...] }] }
create function public.admin_profile_photo_reports(p_page integer default 1, p_size integer default 20)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  sz integer := least(greatest(coalesce(p_size, 20), 1), 100);
  pg integer := greatest(coalesce(p_page, 1), 1);
begin
  perform public.require_operator();
  return jsonb_build_object(
    'total', (select count(distinct r.photo_path) from public.profile_photo_reports r where r.status = 'open'),
    'page', pg, 'size', sz,
    'photos', coalesce((select jsonb_agg(x.j order by x.first_at, x.photo_path) from (
      select g.photo_path, g.first_at, jsonb_build_object(
               'photo_path', g.photo_path,
               'current', o.photo_path is not distinct from g.photo_path,
               'owner', jsonb_build_object('id', o.id, 'nickname', o.nickname, 'influencer', o.influencer, 'nickname_state', o.nickname_state),
               'reports', (select jsonb_agg(jsonb_build_object(
                                    'id', r.id, 'reason', r.reason, 'detail', r.detail, 'created_at', r.created_at,
                                    'reporter', jsonb_build_object('id', u.id, 'nickname', u.nickname, 'influencer', u.influencer,
                                                                   'nickname_state', u.nickname_state, 'role', u.role))
                                  order by r.created_at)
                             from public.profile_photo_reports r left join public.profiles u on u.id = r.reporter_id
                            where r.photo_path = g.photo_path and r.status = 'open')) as j
        from (select r.photo_path, min(r.owner_id::text)::uuid as owner_id, min(r.created_at) as first_at
                from public.profile_photo_reports r where r.status = 'open'
               group by r.photo_path order by min(r.created_at), r.photo_path limit sz offset (pg - 1) * sz) g
        join public.profiles o on o.id = g.owner_id) x), '[]'::jsonb));
end;
$$;

-- 그 장인의 지금 사진에 대한 처리 전 신고를 기각 (사진은 그대로). 돌려주는 값: 닫은 신고 수
create function public.dismiss_profile_photo_reports(p_user uuid, p_note text default null)
returns integer language plpgsql security definer set search_path = ''
as $$
declare
  note text := nullif(btrim(coalesce(p_note, '')), '');
  p public.profiles%rowtype;
  n integer;
begin
  perform public.require_operator();
  if char_length(note) > 500 then
    raise exception '메모는 500자 이하로 적어 주세요.' using errcode = '22023';
  end if;
  select * into p from public.profiles where id = p_user;
  if not found or p.photo_path is null then
    raise exception '처리할 신고가 없습니다. 사진이 이미 바뀌었거나 지워졌을 수 있습니다.' using errcode = 'P0002';
  end if;
  update public.profile_photo_reports set status = 'dismissed', handled_by = (select auth.uid()), handled_at = now(), handled_note = note
   where photo_path = p.photo_path and status = 'open';
  get diagnostics n = row_count;
  if n = 0 then
    raise exception '처리할 신고가 없습니다.' using errcode = 'P0002';
  end if;
  perform public.log_moderation('dismiss_reports', 'user', p.id::text, concat_ws(' · ', '프로필 사진', note), p.nickname);
  return n;
end;
$$;

-- 프로필 사진 삭제 (사유 필수). 장인에게 알림, 처리 전 신고는 "처리됨", 처리 기록. 파일은 대기열 -> media-cleanup
create function public.remove_profile_photo(p_user uuid, p_note text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  note text := nullif(btrim(coalesce(p_note, '')), '');
  p public.profiles%rowtype;
  n_reports integer;
begin
  perform public.require_operator();
  if note is null or char_length(note) > 500 then
    raise exception '삭제 사유를 적어 주세요. (500자 이하)' using errcode = '22023';
  end if;
  select * into p from public.profiles where id = p_user for update;
  if not found or p.photo_path is null then
    raise exception '지울 프로필 사진이 없습니다. 이미 바뀌었거나 지워졌을 수 있습니다.' using errcode = 'P0002';
  end if;
  update public.profile_photo_reports set status = 'resolved', handled_by = (select auth.uid()), handled_at = now(), handled_note = note
   where photo_path = p.photo_path and status = 'open';
  get diagnostics n_reports = row_count;
  update public.profiles set photo_path = null, photo_updated_at = null where id = p.id;
  perform public.notify(p.id, 'profile_photo_removed',
    format('프로필 사진이 운영 원칙에 따라 삭제됐습니다. 사유: %s', note), null, null);
  perform public.log_moderation('remove_profile_photo', 'user', p.id::text,
    concat_ws(' · ', case when n_reports > 0 then format('처리 전 신고 %s건', n_reports) end, note), p.nickname);
end;
$$;

-- ---------------------------------------------------------------------
-- 9. 정리 (Edge Function media-cleanup이 service_role로 부른다)
-- ---------------------------------------------------------------------
-- 지울 경로: 대기열 + 어느 장인의 사진도 아닌 채 media_orphan_hours(24시간)가 지난 파일
create function public.profile_photo_cleanup_list(p_limit integer default 100)
returns text[] language sql stable security definer set search_path = ''
as $$
  select coalesce(array_agg(x.path), '{}') from (
    select t.path from public.profile_photo_trash t
    where not exists (select 1 from public.profiles p where p.photo_path = t.path)
    union
    select ob.name from storage.objects ob
    where ob.bucket_id = 'profile-photos'
      and ob.created_at < now() - make_interval(hours => public.xp_rule('media_orphan_hours'))
      and not exists (select 1 from public.profiles p where p.photo_path = ob.name)
    limit greatest(least(coalesce(p_limit, 100), 1000), 1)
  ) x;
$$;

-- 지운 경로를 대기열에서 뺀다 (그 사이 다시 쓰인 경로는 남겨 둔다)
create function public.profile_photo_cleanup_done(p_paths text[])
returns integer language plpgsql security definer set search_path = ''
as $$
declare
  n integer;
begin
  delete from public.profile_photo_trash t
   where t.path = any(coalesce(p_paths, '{}'))
     and not exists (select 1 from public.profiles p where p.photo_path = t.path);
  get diagnostics n = row_count;
  return n;
end;
$$;

-- ---------------------------------------------------------------------
-- 10. 공개 프로필에 사진 경로 (나머지는 047 그대로)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.public_profile(p_user text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  uid uuid;
  p public.profiles%rowtype;
begin
  if p_user is null or p_user !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return null;
  end if;
  uid := p_user::uuid;
  select * into p from public.profiles where id = uid and influencer is not null and nickname is not null;
  if not found then
    return null;
  end if;
  return jsonb_build_object(
    'id', p.id,
    'nickname', p.nickname,
    'influencer', p.influencer,
    'photo_path', p.photo_path,  -- 062
    'links', coalesce((select jsonb_agg(public.ext_link_json(l.id) order by l.sort)
                         from public.ext_links l where l.owner_id = p.id and l.build_id is null and public.ext_link_visible(l.id)), '[]'::jsonb),
    'build_count', (select count(*) from public.builds b join public.counters c on c.id = b.counter_id
                     where b.author_id = p.id and b.status = 'approved' and c.status = 'approved'),
    'builds', coalesce((select jsonb_agg(x.j order by x.created_at desc, x.id desc) from (
                select b.id, b.created_at, jsonb_build_object(
                         'id', b.id, 'counter_id', b.counter_id, 'seq', b.seq, 'name', b.name, 'patch', b.patch,
                         'target_champion', c.target_champion, 'counter_champion', c.counter_champion,
                         'created_at', b.created_at,
                         'link', (select public.ext_link_json(l.id) from public.ext_links l
                                   where l.build_id = b.id and public.ext_link_visible(l.id))) as j
                  from public.builds b join public.counters c on c.id = b.counter_id
                 where b.author_id = p.id and b.status = 'approved' and c.status = 'approved'
                 order by b.created_at desc, b.id desc
                 limit 10) x), '[]'::jsonb));
end;
$function$;

-- ---------------------------------------------------------------------
-- 11. 알림 종류·휴대폰 알림 묶음·처리 기록 종류
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
  'followed_build_created', 'notice_posted', 'new_followers', 'comment_reply',
  'profile_photo_removed']));  -- 062

alter table public.moderation_log drop constraint moderation_log_action_check;
alter table public.moderation_log add constraint moderation_log_action_check check (action = any (array[
  'hide', 'restore', 'dismiss_reports', 'approve_proposal', 'reject_proposal', 'grant_moderator', 'revoke_moderator',
  'answer_inquiry', 'move_inquiry', 'edit_proposal', 'request_revision', 'delete', 'revert', 'resolve_report', 'dismiss_report',
  'approve_influencer', 'reject_influencer', 'extend_influencer', 'revoke_influencer', 'rename_member',
  'remove_link', 'add_link_domain', 'remove_link_domain', 'grant_influencer', 'grant_title', 'revoke_title',
  'remove_profile_photo']));  -- 062

CREATE OR REPLACE FUNCTION public.push_group(p_kind text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select case
    when p_kind in ('proposal_submitted', 'build_submitted', 'inquiry_received', 'matchup_created', 'build_created', 'post_created',
                    'error_reported', 'report_received', 'influencer_applied') then 'staff_new'
    when p_kind in ('proposal_approved', 'proposal_rejected', 'build_approved', 'build_rejected',
                    'revision_request', 'counter_restored', 'build_restored',
                    'influencer_received', 'influencer_expiring', 'influencer_approved', 'influencer_rejected',
                    'influencer_expired', 'influencer_revoked', 'nickname_reset_soon', 'nickname_reset', 'link_removed',
                    'profile_photo_removed') then 'my_results'  -- 062: 링크 삭제와 같은 묶음
    when p_kind in ('followed_build_created') then 'follow_builds'
    when p_kind in ('notice_posted') then 'notice'
    when p_kind in ('new_followers') then 'new_followers'
  end;
$function$;

-- ---------------------------------------------------------------------
-- 12. 권한
-- ---------------------------------------------------------------------
revoke execute on function public.notify_staff_new_photo_report() from public, anon, authenticated;
revoke execute on function public.profile_photo_clear_on_influencer_end() from public, anon, authenticated;
revoke execute on function public.profile_photo_after_change() from public, anon, authenticated;
revoke execute on function public.profile_photo_on_profile_delete() from public, anon, authenticated;
revoke execute on function public.profile_photo_upload_problem() from public, anon;
grant execute on function public.profile_photo_upload_problem() to authenticated;
revoke execute on function public.profile_photo_visible(text) from public;
grant execute on function public.profile_photo_visible(text) to anon, authenticated;
revoke execute on function public.profile_photo_deletable(text) from public, anon;
grant execute on function public.profile_photo_deletable(text) to authenticated;
revoke execute on function public.set_profile_photo(text) from public, anon;
grant execute on function public.set_profile_photo(text) to authenticated;
revoke execute on function public.clear_profile_photo() from public, anon;
grant execute on function public.clear_profile_photo() to authenticated;
revoke execute on function public.report_profile_photo(uuid, text, text) from public, anon;
grant execute on function public.report_profile_photo(uuid, text, text) to authenticated;
revoke execute on function public.admin_profile_photo_reports(integer, integer) from public, anon;
grant execute on function public.admin_profile_photo_reports(integer, integer) to authenticated;  -- 운영자인지는 함수 안에서
revoke execute on function public.dismiss_profile_photo_reports(uuid, text) from public, anon;
grant execute on function public.dismiss_profile_photo_reports(uuid, text) to authenticated;
revoke execute on function public.remove_profile_photo(uuid, text) from public, anon;
grant execute on function public.remove_profile_photo(uuid, text) to authenticated;
revoke execute on function public.profile_photo_cleanup_list(integer) from public, anon, authenticated;
revoke execute on function public.profile_photo_cleanup_done(text[]) from public, anon, authenticated;
grant execute on function public.profile_photo_cleanup_list(integer) to service_role;
grant execute on function public.profile_photo_cleanup_done(text[]) to service_role;

commit;
