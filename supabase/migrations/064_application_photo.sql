-- =====================================================================
-- 064: 장인 인증 신청서에서 프로필 사진 고르기 (2026-11-21, SPEC 6-76) - 062의 버킷 profile-photos를 그대로 쓴다
--
-- 1. 신청 표 influencer_applications에 photo_path / photo_updated_at (심사 중인 신청에만 값이 있다).
--    신청 표는 원래 본인·운영자(운영자 모드)만 읽으므로 신청 사진 경로는 다른 사람에게 드러나지 않는다.
--    profiles.photo_path(누구나 읽음, 장인만)에는 승인 전까지 넣지 않는다.
-- 2. 화면 흐름: 신청서에서 사진을 고르면 휴대폰 안에서 미리보기만 -> [신청 보내기]로 신청이 접수된 뒤 바로 올리고
--    set_application_photo(경로)로 신청에 붙인다. 심사 중에는 [내 신청] 카드에서 바꾸기·지우기(clear_application_photo).
--    - 올리기(Storage 규칙 + profile_photo_upload_problem): "인증된 장인" -> "인증된 장인 또는 심사 중 신청이 있는 회원"
--      내 폴더에만, 폴더에 파일 5개, 24시간에 사진 바꾸기 profile_photo_daily_max(10)번 - 장인 사진과 같은 기록으로 센다.
--    - 보기: 본인(원래 내 폴더는 본다) + 운영자 모드가 켜진 운영자(새 함수 profile_photo_reviewable). 감독관·다른 회원·비로그인은 못 본다.
--      공개 보기(profile_photo_visible)와 공개 프로필(public_profile)은 그대로 - 장인의 지금 사진만.
--    - 지우기: 심사 중 신청 사진은 지우기 규칙으로 못 지운다 (운영자가 깨진 사진을 보지 않게. 바꾸면 옛 파일은 대기열로).
-- 3. 승인: approve_influencer(신청, 메모, 운영자가 본 사진 경로, 사진 포함 여부) - 새로 더함.
--    운영자가 본 사진(없었으면 null)과 지금 신청 사진이 다르면 승인 거부("신청자가 사진을 바꿨습니다").
--    포함이면 파일 이동 없이 그 경로를 profiles.photo_path로 정한다. 빼면 파일은 대기열로, 승인 알림 끝에
--    「프로필 사진은 운영 원칙에 따라 등록하지 않았습니다.」 (새 알림 종류 없음 - web-push 다시 배포 필요 없음).
--    옛 approve_influencer(신청, 메모)는 남겨 두되, 신청 사진이 있으면 "새로고침" 안내로 거부한다(사진을 못 본 화면의 승인 막기).
-- 4. 신청이 끝나면(반려·만료·취소·탈퇴, 승인 때 뺀 사진) 사진 경로를 비우고 기존 대기열 profile_photo_trash로 보낸다
--    -> 매일 media-cleanup이 지운다. 사진을 바꿀 때 옛 파일도 대기열로.
--    정리 함수 profile_photo_cleanup_list/done은 심사 중 신청 사진을 지우지 않는다(062는 "장인 사진이 아닌 채 24시간"이면 지웠다).
-- 5. 내 장인 상태 my_influencer_status: application에 photo_path, 맨 위에 photo_ready(true - 064 실행 여부를 화면이 안다).
--    운영자 신청 목록 admin_influencer_applications: 줄마다 photo_path.
--
-- 새 버킷·새 표·새 알림 종류·새 설정값·새 pg_cron 없음. Edge Function(media-cleanup·web-push) 다시 배포 필요 없음
-- (media-cleanup은 같은 DB 함수 이름을 부른다).
-- 실행 전 supabase/scripts/check_application_photo_before.sql, 실행 뒤 check_application_photo_after.sql.
-- 063까지 실행한 DB에서 SQL Editor에 통째로 붙여넣어 "한 번" 실행한다. 지금 화면(신청 사진 전)과도 호환된다 - SQL을 먼저 실행한다.
--
-- >> 되돌리기 (rollback) - 문제가 생기면 SQL Editor에서 아래를 한 번에 실행한다(맨 앞 "-- "는 빼고). 063 상태로 돌아간다.
--    되돌릴 수 없는 것: 심사 중 신청에 붙은 사진 연결은 지워진다(파일은 장인 사진이 아니므로 24시간 뒤 매일 정리가 지운다).
--    이미 승인돼 장인 사진이 된 것은 그대로 남는다.
--     begin;
--     -- 1) Storage 보기 규칙을 062로 (함수를 쓰므로 먼저)
--     drop policy if exists "profile-photos 보기" on storage.objects;
--     create policy "profile-photos 보기" on storage.objects
--       for select to anon, authenticated
--       using (
--         bucket_id = 'profile-photos'
--         and (owner_id = (select auth.uid())::text or public.profile_photo_visible(name))
--       );
--     -- 2) 바꾼 함수를 063 상태(062·046·049 내용)로
--     create or replace function public.profile_photo_upload_problem()
--     returns text language plpgsql stable security definer set search_path = ''
--     as $$
--     declare
--       me uuid := (select auth.uid());
--       daily integer := public.xp_rule('profile_photo_daily_max');
--     begin
--       if me is null then
--         return '로그인해야 프로필 사진을 올릴 수 있습니다.';
--       end if;
--       if not exists (select 1 from public.profiles where id = me and influencer is not null and nickname is not null and not is_guest) then
--         return '인증된 장인만 프로필 사진을 올릴 수 있습니다.';
--       end if;
--       if (select count(*) from storage.objects o where o.bucket_id = 'profile-photos' and o.owner_id = me::text) >= 5 then
--         return '올려 두고 쓰지 않은 사진이 많습니다. 하루 뒤 다시 시도해 주세요.';
--       end if;
--       if (select count(*) from public.profile_photo_changes c where c.user_id = me and c.created_at > now() - interval '24 hours') >= daily then
--         return format('프로필 사진은 하루에 %s번까지 바꿀 수 있습니다. 내일 다시 해 주세요.', daily);
--       end if;
--       return null;
--     end;
--     $$;
--     create or replace function public.profile_photo_deletable(p_path text)
--     returns boolean language sql stable security definer set search_path = ''
--     as $$
--       select (select auth.uid()) is not null
--          and (storage.foldername(p_path))[1] = (select auth.uid())::text
--          and p_path is distinct from (select photo_path from public.profiles where id = (select auth.uid()));
--     $$;
--     create or replace function public.profile_photo_cleanup_list(p_limit integer default 100)
--     returns text[] language sql stable security definer set search_path = ''
--     as $$
--       select coalesce(array_agg(x.path), '{}') from (
--         select t.path from public.profile_photo_trash t
--         where not exists (select 1 from public.profiles p where p.photo_path = t.path)
--         union
--         select ob.name from storage.objects ob
--         where ob.bucket_id = 'profile-photos'
--           and ob.created_at < now() - make_interval(hours => public.xp_rule('media_orphan_hours'))
--           and not exists (select 1 from public.profiles p where p.photo_path = ob.name)
--         limit greatest(least(coalesce(p_limit, 100), 1000), 1)
--       ) x;
--     $$;
--     create or replace function public.profile_photo_cleanup_done(p_paths text[])
--     returns integer language plpgsql security definer set search_path = ''
--     as $$
--     declare
--       n integer;
--     begin
--       delete from public.profile_photo_trash t
--        where t.path = any(coalesce(p_paths, '{}'))
--          and not exists (select 1 from public.profiles p where p.photo_path = t.path);
--       get diagnostics n = row_count;
--       return n;
--     end;
--     $$;
--     create or replace function public.approve_influencer_unchecked(p_id bigint, p_note text)
--     returns void language plpgsql security definer set search_path = ''
--     as $$
--     declare
--       a public.influencer_applications;
--       u public.profiles;
--       note text := nullif(btrim(coalesce(p_note, '')), '');
--       grace integer := coalesce(public.xp_rule('influencer_nickname_grace_days'), 3);
--       h record;
--     begin
--       if note is null or char_length(note) > 500 then
--         raise exception '승인 메모를 적어 주세요. (500자 이하)' using errcode = '22023';
--       end if;
--       select * into a from public.influencer_applications where id = p_id for update;
--       if not found then
--         raise exception '신청을 찾지 못했습니다.' using errcode = 'P0002';
--       end if;
--       if a.status <> 'pending' or a.user_id is null then
--         raise exception '이미 처리된 신청입니다.' using errcode = 'TL409';
--       end if;
--       select * into u from public.profiles where id = a.user_id for update;
--       perform pg_advisory_xact_lock(hashtext('nickname_key:' || u.nickname_key));
--       if exists (select 1 from public.profiles o where o.nickname_key = u.nickname_key and o.id <> u.id
--                     and (o.role <> 'user' or o.influencer is not null or o.nickname_state is not null)) then
--         raise exception E'같은 닉네임을 운영진\u00B7장인\u00B7다른 신청자가 쓰고 있어 승인할 수 없습니다. 반려하거나 닉네임을 정리해 주세요.' using errcode = '23505';
--       end if;
--       -- 같은 닉네임을 쓰던 보통 회원: 닉네임 변경 예정 (유예 뒤 임시 닉네임) + 미리 알림
--       for h in select o.id from public.profiles o where o.nickname_key = u.nickname_key and o.id <> u.id for update loop
--         update public.profiles set nickname_state = 'yielding', nickname_reset_at = now() + make_interval(days => grace) where id = h.id;
--         perform public.notify(h.id, 'nickname_reset_soon',
--           format('운영 원칙에 따라 %s일 뒤 닉네임이 임시 닉네임으로 바뀝니다. 그 전에 새 닉네임을 정해 주세요.', grace), null, null);
--       end loop;
--       update public.profiles set influencer = a.kind, influencer_at = now(), nickname_state = null, nickname_reset_at = null where id = u.id;
--       update public.influencer_applications
--          set status = 'approved', ended_at = now(), reviewed_by = (select auth.uid()), review_note = note
--        where id = a.id;
--       perform public.notify(u.id, 'influencer_approved', '장인 인증이 완료됐습니다. 이제 닉네임 앞에 "장인" 표시가 붙습니다.', null, null);
--       perform public.log_moderation('approve_influencer', 'influencer_application', a.id::text, note, u.nickname);
--     end;
--     $$;
--     create or replace function public.my_influencer_status()
--     returns jsonb language plpgsql stable security definer set search_path = ''
--     as $$
--     declare
--       me uuid := (select auth.uid());
--       p public.profiles;
--     begin
--       if me is null then
--         raise exception '로그인해 주세요.' using errcode = '42501';
--       end if;
--       select * into p from public.profiles where id = me;
--       return jsonb_build_object(
--         'influencer', p.influencer, 'influencer_at', p.influencer_at,
--         'nickname_state', p.nickname_state, 'nickname_reset_at', p.nickname_reset_at,
--         'is_guest', coalesce(p.is_guest, false),
--         'next_apply_at', public.influencer_next_apply_at(me),
--         'application', (
--           select jsonb_build_object('id', a.id, 'kind', a.kind, 'nickname', a.nickname, 'old_nickname', a.old_nickname,
--                                     'channel_url', a.channel_url, 'official_email', a.official_email, 'riot_id', a.riot_id,
--                                     'opgg_url', a.opgg_url, 'status', a.status, 'created_at', a.created_at, 'expires_at', a.expires_at,
--                                     'ended_at', a.ended_at, 'review_note', a.review_note, 'retry_now', a.retry_now,
--                                     'nickname_reverted', a.nickname_reverted, 'revoked_at', a.revoked_at, 'revoke_note', a.revoke_note)
--             from public.influencer_applications a where a.user_id = me order by a.created_at desc, a.id desc limit 1));
--     end;
--     $$;
--     create or replace function public.admin_influencer_applications_unchecked(p_status text, p_page integer, p_size integer)
--     returns jsonb language plpgsql stable security definer set search_path = ''
--     as $$
--     declare
--       pg integer := greatest(coalesce(p_page, 1), 1);
--       sz integer := least(greatest(coalesce(p_size, 20), 1), 50);
--       st text := coalesce(p_status, 'pending');
--       win interval := make_interval(days => coalesce(public.xp_rule('influencer_reject_window_days'), 180));
--     begin
--       if st not in ('pending', 'done') then
--         raise exception '목록 종류를 다시 골라 주세요.' using errcode = '22023';
--       end if;
--       return jsonb_build_object(
--         'total', (select count(*) from public.influencer_applications a where (a.status = 'pending') = (st = 'pending')),
--         'page', pg, 'size', sz,
--         'items', coalesce((
--           select jsonb_agg(jsonb_build_object(
--                    'id', x.id, 'kind', x.kind, 'kind_label', public.influencer_kind_label(x.kind),
--                    'nickname', x.nickname, 'old_nickname', x.old_nickname,
--                    'channel_url', x.channel_url, 'official_email', x.official_email, 'riot_id', x.riot_id, 'opgg_url', x.opgg_url,
--                    'status', x.status, 'created_at', x.created_at, 'expires_at', x.expires_at, 'extended_count', x.extended_count,
--                    'ended_at', x.ended_at, 'review_note', x.review_note, 'retry_now', x.retry_now,
--                    'nickname_reverted', x.nickname_reverted, 'revoked_at', x.revoked_at, 'revoke_note', x.revoke_note,
--                    'direct', coalesce((to_jsonb(x) ->> 'direct')::boolean, false),
--                    'reviewer', (select r.nickname from public.profiles r where r.id = x.reviewed_by),
--                    'user', (select jsonb_build_object('id', u.id, 'nickname', u.nickname, 'role', u.role, 'level', u.level,
--                                                       'main_title', u.main_title, 'is_guest', u.is_guest, 'created_at', u.created_at,
--                                                       'influencer', u.influencer, 'nickname_state', u.nickname_state)
--                               from public.profiles u where u.id = x.user_id),
--                    'overlap', case when x.status = 'pending' then (
--                        select jsonb_build_object('id', o.id, 'nickname', o.nickname, 'role', o.role)
--                          from public.profiles o join public.profiles me on me.id = x.user_id
--                         where o.nickname_key = me.nickname_key and o.id <> me.id limit 1) end,
--                    'recent_rejections', (select count(*) from public.influencer_applications r
--                                           where r.user_id = x.user_id and r.status = 'rejected' and not r.retry_now and r.ended_at > now() - win))
--                  order by x.ord1, x.ord2 desc nulls last, x.id)
--           from (
--             select a.*,
--                    case when st = 'pending' then extract(epoch from a.created_at) end as ord1,
--                    case when st = 'done' then coalesce(a.revoked_at, a.ended_at) end as ord2
--               from public.influencer_applications a
--              where (a.status = 'pending') = (st = 'pending')
--              order by case when st = 'pending' then a.created_at end, coalesce(a.revoked_at, a.ended_at) desc nulls last, a.id
--              limit sz offset (pg - 1) * sz
--           ) x
--         ), '[]'::jsonb));
--     end;
--     $$;
--     -- 3) 트리거와 새 함수
--     drop trigger if exists influencer_applications_photo_changed on public.influencer_applications;
--     drop trigger if exists influencer_applications_photo_end on public.influencer_applications;
--     drop function if exists public.approve_influencer(bigint, text, text, boolean);
--     drop function if exists public.approve_influencer_unchecked(bigint, text, text, boolean);
--     drop function if exists public.set_application_photo(text);
--     drop function if exists public.clear_application_photo();
--     drop function if exists public.profile_photo_reviewable(text);
--     drop function if exists public.application_photo_after_change();
--     drop function if exists public.application_photo_clear_on_end();
--     -- 4) 신청 표 칸 (심사 중 신청의 사진 연결이 지워진다 - 파일은 매일 정리가 24시간 뒤 지운다)
--     alter table public.influencer_applications drop constraint if exists influencer_applications_photo_pending;
--     alter table public.influencer_applications drop constraint if exists influencer_applications_photo_pair;
--     alter table public.influencer_applications drop column if exists photo_path;
--     alter table public.influencer_applications drop column if exists photo_updated_at;
--     commit;
--
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 0. 안전장치: 063까지 실행한 DB에서 한 번만
-- ---------------------------------------------------------------------
do $guard$
begin
  if exists (select 1 from information_schema.columns
              where table_schema = 'public' and table_name = 'influencer_applications' and column_name = 'photo_path') then
    raise exception '064를 이미 실행했습니다 (influencer_applications.photo_path 칸이 있음). 다시 실행하지 마세요. 아무것도 바뀌지 않았습니다.' using errcode = 'P0001';
  end if;
  if to_regclass('public.profile_photo_trash') is null
     or not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                     where n.nspname = 'public' and p.proname = 'influencer_followers' and p.prosrc like '%is_guest%') then
    raise exception '063까지 실행한 DB에서만 실행합니다 (062, 063을 먼저). 아무것도 바뀌지 않았습니다.' using errcode = 'P0001';
  end if;
end;
$guard$;

-- ---------------------------------------------------------------------
-- 1. 신청 표 칸 (읽기는 원래 규칙 그대로 - 본인·운영자. 쓰기는 함수로만)
-- ---------------------------------------------------------------------
alter table public.influencer_applications
  add column photo_path text unique,
  add column photo_updated_at timestamptz,
  add constraint influencer_applications_photo_pair check ((photo_path is null) = (photo_updated_at is null)),
  add constraint influencer_applications_photo_pending check (
    photo_path is null or (status = 'pending' and user_id is not null and starts_with(photo_path, user_id::text || '/')));
comment on column public.influencer_applications.photo_path is
  '장인 인증 신청 때 고른 프로필 사진 경로 (064, 버킷 profile-photos). 심사 중에만, 본인·운영자만 본다. 승인되면 profiles.photo_path로';
comment on column public.influencer_applications.photo_updated_at is '신청 사진을 마지막으로 정한 때 (064)';

-- 신청이 끝나면(심사 중이 아니게 되거나 탈퇴로 user_id가 비면) 사진 칸을 비운다.
-- BEFORE 트리거는 이름 순으로 돈다 -> influencer_applications_clear_private(탈퇴면 withdrawn으로 바꿈) 다음에 돈다
create function public.application_photo_clear_on_end()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if new.photo_path is not null and (new.status <> 'pending' or new.user_id is null) then
    new.photo_path := null;
    new.photo_updated_at := null;
  end if;
  return new;
end;
$$;
create trigger influencer_applications_photo_end before update on public.influencer_applications
  for each row execute function public.application_photo_clear_on_end();

-- 옛 신청 사진을 대기열로 (바꿈·지움·신청 끝남). 승인으로 장인 사진이 된 경로는 넣지 않는다
create function public.application_photo_after_change()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if not exists (select 1 from public.profiles p where p.photo_path = old.photo_path) then
    insert into public.profile_photo_trash (path, reason)
    values (old.photo_path, case when new.photo_path is not null then 'replaced'
                                 when new.status = 'pending' and new.user_id is not null then 'cleared'
                                 else 'application_' || new.status end)
    on conflict (path) do nothing;
  end if;
  return null;
end;
$$;
create trigger influencer_applications_photo_changed after update on public.influencer_applications
  for each row when (old.photo_path is not null and old.photo_path is distinct from new.photo_path)
  execute function public.application_photo_after_change();

-- ---------------------------------------------------------------------
-- 2. Storage 규칙
-- ---------------------------------------------------------------------
-- 올릴 수 없는 이유 (062 + "심사 중 신청이 있는 회원"도 올릴 수 있음)
create or replace function public.profile_photo_upload_problem()
returns text language plpgsql stable security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  daily integer := public.xp_rule('profile_photo_daily_max');
begin
  if me is null then
    return '로그인해야 프로필 사진을 올릴 수 있습니다.';
  end if;
  if not exists (select 1 from public.profiles p where p.id = me and p.nickname is not null and not p.is_guest
                   and (p.influencer is not null
                        or exists (select 1 from public.influencer_applications a where a.user_id = me and a.status = 'pending'))) then
    return '인증된 장인이나 장인 인증을 신청한 회원만 프로필 사진을 올릴 수 있습니다.';
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

-- 운영자 심사용: 심사 중 신청의 사진이고 지금 운영자(운영자 모드)인가
create function public.profile_photo_reviewable(p_path text)
returns boolean language sql stable security definer set search_path = ''
as $$
  select public.is_admin()
     and exists (select 1 from public.influencer_applications a where a.photo_path = p_path and a.status = 'pending');
$$;

-- 내가 지울 수 있는 파일인가: 내 폴더 + 지금 내 사진이 아님 + 심사 중 신청 사진이 아님(064)
create or replace function public.profile_photo_deletable(p_path text)
returns boolean language sql stable security definer set search_path = ''
as $$
  select (select auth.uid()) is not null
     and (storage.foldername(p_path))[1] = (select auth.uid())::text
     and p_path is distinct from (select photo_path from public.profiles where id = (select auth.uid()))
     and not exists (select 1 from public.influencer_applications a where a.photo_path = p_path);
$$;

drop policy "profile-photos 보기" on storage.objects;
create policy "profile-photos 보기" on storage.objects
  for select to anon, authenticated
  using (
    bucket_id = 'profile-photos'
    and (owner_id = (select auth.uid())::text or public.profile_photo_visible(name) or public.profile_photo_reviewable(name))
  );

-- ---------------------------------------------------------------------
-- 3. 신청 사진 정하기·지우기 (심사 중인 본인)
-- ---------------------------------------------------------------------
create function public.set_application_photo(p_path text)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := public.board_writer();
  a public.influencer_applications%rowtype;
  o record;
  m text;
  sz bigint;
  daily integer := public.xp_rule('profile_photo_daily_max');
begin
  select * into a from public.influencer_applications where user_id = me and status = 'pending' for update;
  if not found then
    raise exception '심사 중인 장인 인증 신청이 없습니다.' using errcode = 'P0002';
  end if;
  if p_path is null or p_path !~ ('^' || me::text || '/[0-9A-Za-z_-]{1,64}\.(webp|jpg)$') then
    raise exception '사진을 다시 골라 주세요.' using errcode = '22023';
  end if;
  if p_path = a.photo_path then
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
  update public.influencer_applications set photo_path = p_path, photo_updated_at = now() where id = a.id;
  insert into public.profile_photo_changes (user_id) values (me);
  delete from public.profile_photo_trash where path = p_path;  -- 혹시 대기열에 있던 내 파일을 다시 쓰면 지우지 않는다
end;
$$;

create function public.clear_application_photo()
returns void language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
begin
  if me is null then
    raise exception '로그인이 필요합니다.' using errcode = '42501';
  end if;
  update public.influencer_applications set photo_path = null, photo_updated_at = null
   where user_id = me and status = 'pending' and photo_path is not null;
end;
$$;

-- ---------------------------------------------------------------------
-- 4. 승인 (사진 포함/제외, 운영자가 본 사진과 다르면 거부)
-- ---------------------------------------------------------------------
create function public.approve_influencer_unchecked(p_id bigint, p_note text, p_photo_path text, p_with_photo boolean)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  a public.influencer_applications;
  u public.profiles;
  note text := nullif(btrim(coalesce(p_note, '')), '');
  seen text := nullif(btrim(coalesce(p_photo_path, '')), '');
  grace integer := coalesce(public.xp_rule('influencer_nickname_grace_days'), 3);
  photo text;
  h record;
begin
  if note is null or char_length(note) > 500 then
    raise exception '승인 메모를 적어 주세요. (500자 이하)' using errcode = '22023';
  end if;
  select * into a from public.influencer_applications where id = p_id for update;
  if not found then
    raise exception '신청을 찾지 못했습니다.' using errcode = 'P0002';
  end if;
  if a.status <> 'pending' or a.user_id is null then
    raise exception '이미 처리된 신청입니다.' using errcode = 'TL409';
  end if;
  -- 064: 운영자가 본 사진과 지금 신청 사진이 다르면 거부 (그 사이 신청자가 바꾸거나 지움)
  if a.photo_path is distinct from seen then
    raise exception '신청자가 프로필 사진을 바꿨습니다. 새로고침한 뒤 사진을 다시 확인하고 승인해 주세요.' using errcode = 'TL409';
  end if;
  photo := case when coalesce(p_with_photo, false) then a.photo_path end;
  select * into u from public.profiles where id = a.user_id for update;
  perform pg_advisory_xact_lock(hashtext('nickname_key:' || u.nickname_key));
  if exists (select 1 from public.profiles o where o.nickname_key = u.nickname_key and o.id <> u.id
                and (o.role <> 'user' or o.influencer is not null or o.nickname_state is not null)) then
    raise exception E'같은 닉네임을 운영진\u00B7장인\u00B7다른 신청자가 쓰고 있어 승인할 수 없습니다. 반려하거나 닉네임을 정리해 주세요.' using errcode = '23505';
  end if;
  -- 같은 닉네임을 쓰던 보통 회원: 닉네임 변경 예정 (유예 뒤 임시 닉네임) + 미리 알림
  for h in select o.id from public.profiles o where o.nickname_key = u.nickname_key and o.id <> u.id for update loop
    update public.profiles set nickname_state = 'yielding', nickname_reset_at = now() + make_interval(days => grace) where id = h.id;
    perform public.notify(h.id, 'nickname_reset_soon',
      format('운영 원칙에 따라 %s일 뒤 닉네임이 임시 닉네임으로 바뀝니다. 그 전에 새 닉네임을 정해 주세요.', grace), null, null);
  end loop;
  -- 사진 포함이면 파일 이동 없이 그 경로가 장인 사진이 된다 (신청 쪽 칸은 아래 상태 변경 때 트리거가 비움)
  update public.profiles
     set influencer = a.kind, influencer_at = now(), nickname_state = null, nickname_reset_at = null,
         photo_path = photo, photo_updated_at = case when photo is not null then now() end
   where id = u.id;
  update public.influencer_applications
     set status = 'approved', ended_at = now(), reviewed_by = (select auth.uid()), review_note = note
   where id = a.id;  -- 뺀 사진은 트리거가 대기열로
  if photo is not null then
    delete from public.profile_photo_trash where path = photo;
  end if;
  perform public.notify(u.id, 'influencer_approved',
    '장인 인증이 완료됐습니다. 이제 닉네임 앞에 "장인" 표시가 붙습니다.'
      || case when photo is not null then ' 신청 때 고른 프로필 사진도 등록됐습니다.'
              when a.photo_path is not null then ' 프로필 사진은 운영 원칙에 따라 등록하지 않았습니다.'
              else '' end, null, null);
  perform public.log_moderation('approve_influencer', 'influencer_application', a.id::text,
    case when a.photo_path is not null and photo is null then concat_ws(E' \u00B7 ', note, '신청 사진 제외') else note end, u.nickname);
end;
$$;

create function public.approve_influencer(p_id bigint, p_note text, p_photo_path text, p_with_photo boolean)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  perform public.require_operator();
  perform public.approve_influencer_unchecked(p_id, p_note, p_photo_path, p_with_photo);
end;
$$;

-- 옛 승인(신청, 메모): 사진을 보지 못한 화면이므로 신청 사진이 있으면 거부, 없으면 그대로 승인
create or replace function public.approve_influencer_unchecked(p_id bigint, p_note text)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  if exists (select 1 from public.influencer_applications where id = p_id and status = 'pending' and photo_path is not null) then
    raise exception '신청 사진을 확인해야 승인할 수 있습니다. 화면을 새로고침해 주세요.' using errcode = 'TL409';
  end if;
  perform public.approve_influencer_unchecked(p_id, p_note, null, false);
end;
$$;

-- ---------------------------------------------------------------------
-- 5. 내 장인 상태 / 운영자 신청 목록에 사진 경로 (나머지는 046·049 그대로)
-- ---------------------------------------------------------------------
create or replace function public.my_influencer_status()
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  p public.profiles;
begin
  if me is null then
    raise exception '로그인해 주세요.' using errcode = '42501';
  end if;
  select * into p from public.profiles where id = me;
  return jsonb_build_object(
    'influencer', p.influencer, 'influencer_at', p.influencer_at,
    'nickname_state', p.nickname_state, 'nickname_reset_at', p.nickname_reset_at,
    'is_guest', coalesce(p.is_guest, false),
    'next_apply_at', public.influencer_next_apply_at(me),
    'photo_ready', true,  -- 064: 신청 사진을 받을 수 있는 DB
    'application', (
      select jsonb_build_object('id', a.id, 'kind', a.kind, 'nickname', a.nickname, 'old_nickname', a.old_nickname,
                                'channel_url', a.channel_url, 'official_email', a.official_email, 'riot_id', a.riot_id,
                                'opgg_url', a.opgg_url, 'status', a.status, 'created_at', a.created_at, 'expires_at', a.expires_at,
                                'ended_at', a.ended_at, 'review_note', a.review_note, 'retry_now', a.retry_now,
                                'nickname_reverted', a.nickname_reverted, 'revoked_at', a.revoked_at, 'revoke_note', a.revoke_note,
                                'photo_path', a.photo_path)  -- 064
        from public.influencer_applications a where a.user_id = me order by a.created_at desc, a.id desc limit 1));
end;
$$;

create or replace function public.admin_influencer_applications_unchecked(p_status text, p_page integer, p_size integer)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  pg integer := greatest(coalesce(p_page, 1), 1);
  sz integer := least(greatest(coalesce(p_size, 20), 1), 50);
  st text := coalesce(p_status, 'pending');
  win interval := make_interval(days => coalesce(public.xp_rule('influencer_reject_window_days'), 180));
begin
  if st not in ('pending', 'done') then
    raise exception '목록 종류를 다시 골라 주세요.' using errcode = '22023';
  end if;
  return jsonb_build_object(
    'total', (select count(*) from public.influencer_applications a where (a.status = 'pending') = (st = 'pending')),
    'page', pg, 'size', sz,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', x.id, 'kind', x.kind, 'kind_label', public.influencer_kind_label(x.kind),
               'nickname', x.nickname, 'old_nickname', x.old_nickname,
               'channel_url', x.channel_url, 'official_email', x.official_email, 'riot_id', x.riot_id, 'opgg_url', x.opgg_url,
               'status', x.status, 'created_at', x.created_at, 'expires_at', x.expires_at, 'extended_count', x.extended_count,
               'ended_at', x.ended_at, 'review_note', x.review_note, 'retry_now', x.retry_now,
               'nickname_reverted', x.nickname_reverted, 'revoked_at', x.revoked_at, 'revoke_note', x.revoke_note,
               'direct', coalesce((to_jsonb(x) ->> 'direct')::boolean, false),
               'photo_path', x.photo_path,  -- 064 (심사 중일 때만 값이 있다)
               'reviewer', (select r.nickname from public.profiles r where r.id = x.reviewed_by),
               'user', (select jsonb_build_object('id', u.id, 'nickname', u.nickname, 'role', u.role, 'level', u.level,
                                                  'main_title', u.main_title, 'is_guest', u.is_guest, 'created_at', u.created_at,
                                                  'influencer', u.influencer, 'nickname_state', u.nickname_state)
                          from public.profiles u where u.id = x.user_id),
               'overlap', case when x.status = 'pending' then (
                   select jsonb_build_object('id', o.id, 'nickname', o.nickname, 'role', o.role)
                     from public.profiles o join public.profiles me on me.id = x.user_id
                    where o.nickname_key = me.nickname_key and o.id <> me.id limit 1) end,
               'recent_rejections', (select count(*) from public.influencer_applications r
                                      where r.user_id = x.user_id and r.status = 'rejected' and not r.retry_now and r.ended_at > now() - win))
             order by x.ord1, x.ord2 desc nulls last, x.id)
      from (
        select a.*,
               case when st = 'pending' then extract(epoch from a.created_at) end as ord1,
               case when st = 'done' then coalesce(a.revoked_at, a.ended_at) end as ord2
          from public.influencer_applications a
         where (a.status = 'pending') = (st = 'pending')
         order by case when st = 'pending' then a.created_at end, coalesce(a.revoked_at, a.ended_at) desc nulls last, a.id
         limit sz offset (pg - 1) * sz
      ) x
    ), '[]'::jsonb));
end;
$$;

-- ---------------------------------------------------------------------
-- 6. 정리 (Edge Function media-cleanup이 service_role로 부른다) - 심사 중 신청 사진은 지우지 않는다
-- ---------------------------------------------------------------------
create or replace function public.profile_photo_cleanup_list(p_limit integer default 100)
returns text[] language sql stable security definer set search_path = ''
as $$
  select coalesce(array_agg(x.path), '{}') from (
    select t.path from public.profile_photo_trash t
    where not exists (select 1 from public.profiles p where p.photo_path = t.path)
      and not exists (select 1 from public.influencer_applications a where a.photo_path = t.path)
    union
    select ob.name from storage.objects ob
    where ob.bucket_id = 'profile-photos'
      and ob.created_at < now() - make_interval(hours => public.xp_rule('media_orphan_hours'))
      and not exists (select 1 from public.profiles p where p.photo_path = ob.name)
      and not exists (select 1 from public.influencer_applications a where a.photo_path = ob.name)
    limit greatest(least(coalesce(p_limit, 100), 1000), 1)
  ) x;
$$;

create or replace function public.profile_photo_cleanup_done(p_paths text[])
returns integer language plpgsql security definer set search_path = ''
as $$
declare
  n integer;
begin
  delete from public.profile_photo_trash t
   where t.path = any(coalesce(p_paths, '{}'))
     and not exists (select 1 from public.profiles p where p.photo_path = t.path)
     and not exists (select 1 from public.influencer_applications a where a.photo_path = t.path);
  get diagnostics n = row_count;
  return n;
end;
$$;

-- ---------------------------------------------------------------------
-- 7. 권한 (create or replace한 함수의 권한은 그대로 남는다)
-- ---------------------------------------------------------------------
revoke execute on function public.application_photo_clear_on_end() from public, anon, authenticated;
revoke execute on function public.application_photo_after_change() from public, anon, authenticated;
revoke execute on function public.profile_photo_reviewable(text) from public;
grant execute on function public.profile_photo_reviewable(text) to anon, authenticated;  -- Storage 보기 규칙이 부른다 (운영자가 아니면 false)
revoke execute on function public.set_application_photo(text) from public, anon;
grant execute on function public.set_application_photo(text) to authenticated;
revoke execute on function public.clear_application_photo() from public, anon;
grant execute on function public.clear_application_photo() to authenticated;
revoke execute on function public.approve_influencer_unchecked(bigint, text, text, boolean) from public, anon, authenticated;
revoke execute on function public.approve_influencer(bigint, text, text, boolean) from public, anon;
grant execute on function public.approve_influencer(bigint, text, text, boolean) to authenticated;  -- 운영자인지는 함수 안에서

commit;
