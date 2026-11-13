-- =====================================================================
-- 055: 회원 탈퇴 정리 (2026-11-13, SPEC 6-42). 044는 탈퇴용으로 예약했던 번호지만 비워 두고 055로 만든다
--      (044라는 이름이면 새 DB에서 046~054보다 먼저 실행되어 장인/팔로우 표가 없어 멈춘다).
--
-- 탈퇴 경로는 모두 공통 안쪽 함수 withdraw_account_unchecked(회원) 하나를 거친다:
--   delete_my_account(회원 탈퇴/비회원 기록 지우기) / kakao_unlinked(카카오만 연결된 계정) / cleanup_guest_accounts(오래 안 쓴 비회원)
--   -> withdraw_account_unchecked: 운영자 불가, 카카오 ID 찾기, auth.users 삭제
--   -> 프로필 삭제 직전 트리거 profiles_anonymize_on_delete -> withdraw_cleanup(회원) (대시보드에서 지워도 같은 정리)
--   -> 그 밖의 기록은 지금까지의 on delete 규칙 (cascade/set null)
--
-- 바뀌는 것
-- 1. 장인 인증 신청(influencer_applications): 탈퇴하면(user_id가 비워지면) 희망/옛/되돌린 닉네임, 채널 URL/키, op.gg URL,
--    공식 이메일, 라이엇 ID/해시, 심사/해제 메모, 처리한 운영진을 지우고 유형/상태/시각만 남긴다(끝난 날부터 1년 뒤 삭제는 그대로).
--    nickname은 빈칸 허용으로, 표 제약 influencer_applications_fields에 "user_id가 비면 식별 칸도 모두 비어 있음"을 더한다.
-- 2. 처리 기록(moderation_log): 탈퇴한 회원이 대상인 줄(대상 회원 / 그 회원의 장인 신청 / 그 회원의 링크)은
--    target_id를 비우고 target_nickname을 "탈퇴한 이용자"로, 메모에서 "옛 \u2192 새" 닉네임, 링크 주소, 그 회원의 닉네임을 지운다.
--    처리한 사람/종류/시각은 그대로 1년 보관. target_id는 빈칸 허용으로.
-- 3. 탈퇴한 장인의 닉네임 예약: 새 표 nickname_holds(nickname_key만, RLS 켬/정책 없음/직접 접근 불가).
--    인증된 장인이 탈퇴하면 30일(xp_rules.influencer_nickname_hold_days) 동안 누구도 그 닉네임과 비슷한 닉네임(nickname_key가 같은)을 못 쓴다
--    (직접 바꾸기, 장인 신청 희망 닉네임, 운영자 닉네임 바꾸기, 임시 닉네임 모두). 일반 회원은 예약하지 않는다.
--    기간이 지난 줄은 기존 pg_cron influencer_daily가 지운다(돌려주는 값에 nickname_holds_purged 추가). 새 pg_cron 없음.
-- 4. 추천/비추천(build_votes, post_votes): 탈퇴해도 지우지 않고 user_id만 비운다(on delete set null) -> 빌드/글 추천 수 유지.
--    기본 키를 새 id로, "한 사람 한 표"는 유일 제약 (build_id|post_id, user_id)로 (빈칸끼리는 겹쳐도 됨).
--    추천 수 트리거 apply_build_vote는 user_id만 바뀌면 빌드를 건드리지 않아 작성자 경험치/칭호 다시 계산과 알림이 없다.
--    읽기 정책(내 표만, 운영자는 전부), vote_build/vote_post, 글 추천 수 다시 세기(count(*)), 비회원 막기 트리거는 그대로 동작한다.
-- 5. 한 번 정리: 이미 탈퇴한 회원의 장인 신청 기록(user_id가 빈 줄)과, 계정이 없는 대상의 처리 기록을 위 규칙대로 정리한다
--    (실행 결과 NOTICE에 줄 수가 나온다). 이미 지워진 추천/비추천은 되살릴 수 없다.
--
-- 그대로인 것: 처리 전 신고가 걸린 글/댓글과 숨김 기록(hide_log)은 지금처럼 탈퇴 때 바로 지운다. 재가입 막기용 식별값은 보관하지 않는다.
-- Edge Function 재배포 없음(delete-account/kakao-unlink가 부르는 함수 이름/인자 그대로). 새 알림 종류 없음. 새 pg_cron 없음.
-- 실행 전 supabase/scripts/check_withdraw_before.sql, 실행 뒤 check_withdraw_after.sql.
--
-- >> 되돌리기 (rollback) - 문제가 생기면 SQL Editor에서 아래를 한 번에 실행한다. 054 상태로 돌아간다.
--    되돌릴 수 없는 것: 이미 지운 신청 기록의 식별 칸과 처리 기록의 대상/메모(원래 값이 없다).
--    되돌리면 익명 추천/비추천 줄(user_id가 빈 줄)은 지운다 - 빌드/글의 추천 수는 바꾸지 않는다(수 트리거를 잠깐 끔).
--    탈퇴로 user_id가 빈 장인 신청 기록도 지운다(054 제약은 채널/op.gg가 빈 줄을 허락하지 않음). 닉네임 예약 표는 지운다.
--     begin;
--     drop trigger if exists profiles_anonymize_on_delete on public.profiles;
--     drop function if exists public.withdraw_on_profile_delete();
--     drop function if exists public.withdraw_cleanup(uuid);
--     drop function if exists public.moderation_note_scrub(text, text, text, text, text[]);
--     -- 추천/비추천: 익명 줄을 지우고(수는 그대로) 054의 기본 키/외래 키로
--     alter table public.build_votes disable trigger build_votes_count;
--     delete from public.build_votes where user_id is null;
--     alter table public.build_votes enable trigger build_votes_count;
--     alter table public.build_votes drop constraint build_votes_user_id_fkey;
--     alter table public.build_votes add constraint build_votes_user_id_fkey foreign key (user_id) references public.profiles (id) on delete cascade;
--     alter table public.build_votes alter column user_id set not null;
--     alter table public.build_votes drop constraint build_votes_once;
--     alter table public.build_votes drop constraint build_votes_pkey;
--     alter table public.build_votes drop column id;
--     alter table public.build_votes add constraint build_votes_pkey primary key (build_id, user_id);
--     delete from public.post_votes where user_id is null;
--     alter table public.post_votes drop constraint post_votes_user_id_fkey;
--     alter table public.post_votes add constraint post_votes_user_id_fkey foreign key (user_id) references public.profiles (id) on delete cascade;
--     alter table public.post_votes alter column user_id set not null;
--     alter table public.post_votes drop constraint post_votes_once;
--     alter table public.post_votes drop constraint post_votes_pkey;
--     alter table public.post_votes drop column id;
--     alter table public.post_votes add constraint post_votes_pkey primary key (post_id, user_id);
--     -- 처리 기록: 비운 target_id는 빈 글자로
--     update public.moderation_log set target_id = '' where target_id is null;
--     alter table public.moderation_log alter column target_id set not null;
--     -- 장인 신청: 탈퇴로 비운 줄을 지우고 054 제약으로
--     delete from public.influencer_applications where user_id is null;
--     alter table public.influencer_applications drop constraint influencer_applications_nickname_kept;
--     alter table public.influencer_applications drop constraint influencer_applications_fields;
--     alter table public.influencer_applications add constraint influencer_applications_fields check (
--       case
--         when direct then status <> 'pending' and channel_url is null and channel_key is null and official_email is null
--           and riot_id is null and riot_key is null and opgg_url is null
--         when kind in ('creator', 'pro') then channel_url is not null and channel_key is not null and riot_id is null and riot_key is null
--           and opgg_url is null and (status <> 'pending' or official_email is not null)
--         else official_email is null and channel_url is null and channel_key is null and opgg_url is not null
--           and (status <> 'pending' or (riot_id is not null and riot_key is not null))
--       end);
--     alter table public.influencer_applications alter column nickname set not null;
--     -- 함수: 054 때 정의로 (delete_my_account/kakao_unlinked/cleanup_guest_accounts는 다시 auth.users를 직접 지움)
--     create or replace function public.delete_my_account(p_confirm text)
--      RETURNS text
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $f$
--     declare
--       me uuid := (select auth.uid());
--       prof public.profiles%rowtype;
--       kakao text;
--       word text;
--     begin
--       if me is null then
--         raise exception '로그인해 주세요.' using errcode = '42501';
--       end if;
--       select * into prof from public.profiles where id = me for update;
--       if found and prof.role = 'admin' then
--         raise exception '운영자 계정은 탈퇴할 수 없습니다.' using errcode = '42501';
--       end if;
--       word := case when coalesce(prof.is_guest, false) then '지우기' else '탈퇴' end;
--       if btrim(coalesce(p_confirm, '')) is distinct from coalesce(prof.nickname, word) then
--         if prof.nickname is null then
--           raise exception '확인 칸에 "%"를 그대로 적어 주세요.', word using errcode = '22023';
--         end if;
--         raise exception '확인 칸에 내 닉네임을 그대로 적어 주세요.' using errcode = '22023';
--       end if;
--       select provider_id into kakao from auth.identities where user_id = me and provider = 'kakao' limit 1;
--       delete from auth.users where id = me;  -- 프로필과 그 밖의 기록은 on delete 규칙대로 (SPEC 개인정보 메모)
--       return kakao;
--     end;
--     $f$;
--     create or replace function public.kakao_unlinked(p_kakao_id text)
--      RETURNS text
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $f$
--     declare
--       uid uuid;
--       left_providers jsonb;
--     begin
--       select user_id into uid from auth.identities where provider = 'kakao' and provider_id = p_kakao_id;
--       if uid is null then
--         return 'not_found';  -- 이미 탈퇴했거나 연결을 뗀 사람 (우리 탈퇴 버튼이 카카오 연결 끊기를 부르면 이 알림이 다시 온다)
--       end if;
--       if exists (select 1 from auth.identities where user_id = uid and provider <> 'kakao') then
--         delete from auth.identities where user_id = uid and provider = 'kakao';
--         select coalesce(jsonb_agg(provider order by provider), '[]'::jsonb) into left_providers
--         from (select distinct provider from auth.identities where user_id = uid) x;
--         update auth.users
--         set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb)
--           || jsonb_build_object('providers', left_providers)
--           || case when raw_app_meta_data ->> 'provider' = 'kakao'
--                   then jsonb_build_object('provider', left_providers ->> 0) else '{}'::jsonb end
--         where id = uid;
--         return 'unlinked';
--       end if;
--       if exists (select 1 from public.profiles where id = uid and role = 'admin') then
--         return 'operator_kept';  -- 운영자 1명 규칙: 지우지 않고 기록만 (Edge Function 로그)
--       end if;
--       delete from auth.users where id = uid;
--       return 'deleted';
--     end;
--     $f$;
--     create or replace function public.cleanup_guest_accounts()
--      RETURNS integer
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $f$
--     declare
--       empty_days integer := public.xp_rule('guest_empty_days');
--       idle_days integer := public.xp_rule('guest_idle_days');
--       n integer;
--     begin
--       with gone as (
--         delete from auth.users u
--          using public.profiles p
--          where p.id = u.id and u.is_anonymous and p.is_guest and p.role <> 'admin'
--            and p.last_seen_at < now() - make_interval(days =>
--                  case when public.guest_has_records(p.id) then idle_days else empty_days end)
--         returning u.id
--       )
--       select count(*) into n from gone;
--       return n;
--     end;
--     $f$;
--     create or replace function public.check_nickname_key()
--      RETURNS trigger
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $f$
--     declare
--       k text := public.nickname_key(new.nickname);
--     begin
--       if new.nickname is null or (tg_op = 'UPDATE' and new.nickname is not distinct from old.nickname)
--          or coalesce(current_setting('tl.nickname_system', true), '') = 'on' then
--         return new;
--       end if;
--       perform pg_advisory_xact_lock(hashtext('nickname_key:' || k));
--       if exists (select 1 from public.profiles p where p.nickname_key = k and p.id <> new.id) then
--         raise exception '이미 사용 중인 닉네임입니다. 비슷한 닉네임도 쓸 수 없습니다.' using errcode = '23505';
--       end if;
--       return new;
--     end;
--     $f$;
--     create or replace function public.influencer_temp_nickname()
--      RETURNS text
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $f$
--     declare
--       cand text;
--     begin
--       loop
--         cand := '탑신병자#' || substr(md5(random()::text || clock_timestamp()::text), 1, 6);
--         exit when not exists (select 1 from public.profiles where nickname_key = public.nickname_key(cand));
--       end loop;
--       return cand;
--     end;
--     $f$;
--     create or replace function public.influencer_daily()
--      RETURNS jsonb
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $f$
--     declare
--       r record;
--       back text;
--       n_expired integer := 0;
--       n_warned integer := 0;
--       n_reset integer := 0;
--       n_purged integer := 0;
--       warn_days integer := coalesce(public.xp_rule('influencer_expiring_days'), 3);
--       left_days integer;
--     begin
--       -- 1) 만료: 기한이 지난 처리 전 신청
--       for r in select id, user_id, created_at, expires_at from public.influencer_applications
--                 where status = 'pending' and expires_at <= now() order by id loop
--         back := public.influencer_close(r.id, 'expired', null, false, false);
--         if r.user_id is not null then
--           insert into public.notifications (user_id, kind, message)
--           values (r.user_id, 'influencer_expired',
--                   format('%s일 안에 확인이 끝나지 않아 신청이 만료됐습니다. 다시 신청할 수 있습니다.',
--                          round(extract(epoch from (r.expires_at - r.created_at)) / 86400)::integer)
--                   || public.influencer_reverted_sentence(back));
--         end if;
--         n_expired := n_expired + 1;
--       end loop;
--
--       -- 2) 만료 전 알림: 남은 기간이 warn_days 이하, 아직 안 보낸 신청만 (한 신청에 한 번)
--       for r in select id, user_id, kind, expires_at from public.influencer_applications
--                 where status = 'pending' and expiring_notified_at is null and user_id is not null
--                   and expires_at <= now() + make_interval(days => warn_days) for update loop
--         left_days := greatest(ceil(extract(epoch from (r.expires_at - now())) / 86400)::integer, 1);
--         insert into public.notifications (user_id, kind, message)
--         values (r.user_id, 'influencer_expiring', case when r.kind = 'grandmaster'
--           then format('신청이 %s일 뒤 만료됩니다. 아직 친구 요청을 보내지 않았다면 {운영자 닉네임}으로 보내 주세요.', left_days)
--           else format('신청이 %s일 뒤 만료됩니다. 확인 메일에 아직 회신하지 않았다면 만료되기 전에 회신해 주세요.', left_days) end);
--         update public.influencer_applications set expiring_notified_at = now() where id = r.id;
--         n_warned := n_warned + 1;
--       end loop;
--
--       -- 3) 유예가 끝난 "닉네임 변경 예정" 회원 -> 임시 닉네임
--       for r in select id from public.profiles where nickname_state = 'yielding' and nickname_reset_at <= now() for update loop
--         perform public.system_set_nickname(r.id, public.influencer_temp_nickname(), null, null, 'reset');
--         insert into public.notifications (user_id, kind, message)
--         values (r.id, 'nickname_reset', '운영 원칙에 따라 닉네임이 임시 닉네임으로 바뀌었습니다. 새 닉네임을 정해 주세요.');
--         n_reset := n_reset + 1;
--       end loop;
--
--       -- 4) 끝난 지 influencer_keep_days(365)일 지난 신청 정리 (처리 전/승인 중인 것은 남김)
--       delete from public.influencer_applications
--        where status not in ('pending', 'approved')
--          and coalesce(revoked_at, ended_at) < now() - make_interval(days => coalesce(public.xp_rule('influencer_keep_days'), 365));
--       get diagnostics n_purged = row_count;
--
--       return jsonb_build_object('expired', n_expired, 'expiring_notified', n_warned, 'nickname_reset', n_reset, 'purged', n_purged);
--     end;
--     $f$;
--     create or replace function public.apply_build_vote()
--      RETURNS trigger
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $f$
--     begin
--       if tg_op in ('UPDATE', 'DELETE') then
--         update public.builds
--            set up_count   = up_count   - (old.value = 1)::int,
--                down_count = down_count - (old.value = -1)::int
--          where id = old.build_id;
--       end if;
--       if tg_op in ('INSERT', 'UPDATE') then
--         update public.builds
--            set up_count   = up_count   + (new.value = 1)::int,
--                down_count = down_count + (new.value = -1)::int
--          where id = new.build_id;
--       end if;
--       return null;
--     end;
--     $f$;
--     create or replace function public.influencer_applications_clear_private()
--      RETURNS trigger
--      LANGUAGE plpgsql
--      SECURITY DEFINER
--      SET search_path TO ''
--     AS $f$
--     begin
--       if old.user_id is not null and new.user_id is null and new.status in ('pending', 'approved') then
--         new.status := 'withdrawn';
--         new.ended_at := coalesce(new.ended_at, now());
--       end if;
--       if new.status <> 'pending' then
--         new.official_email := null;
--         new.riot_id := null;
--       end if;
--       if new.status not in ('pending', 'approved') then
--         new.riot_key := null;
--       end if;
--       return new;
--     end;
--     $f$;
--     drop function if exists public.withdraw_account_unchecked(uuid);
--     drop table if exists public.nickname_holds;
--     delete from public.xp_rules where key = 'influencer_nickname_hold_days';
--     commit;
-- =====================================================================

begin;

do $$
begin
  if to_regprocedure('public.public_title_info()') is null then
    raise exception '054가 아직 실행되지 않았습니다. 054를 먼저 실행해 주세요.';
  end if;
  if to_regclass('public.nickname_holds') is not null then
    raise exception '055를 이미 실행했습니다.';
  end if;
  if not (has_table_privilege('auth.users', 'DELETE') and has_table_privilege('auth.identities', 'SELECT')) then
    raise exception '이 역할에는 auth.users를 지울 권한이 없습니다. Supabase SQL Editor에서 실행해 주세요.';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 1. 설정값: 탈퇴한 장인의 닉네임 예약 기간 (일)
-- ---------------------------------------------------------------------
insert into public.xp_rules (key, value, note) values
  ('influencer_nickname_hold_days', 30, '탈퇴한 장인의 닉네임을 다른 사람이 못 쓰는 기간(일). 비슷한 닉네임도 막음. 지나면 influencer_daily가 지움 (055)');

-- ---------------------------------------------------------------------
-- 2. 탈퇴한 장인의 닉네임 예약 표 (닉네임 원문은 남기지 않고 비교 키 nickname_key만)
-- ---------------------------------------------------------------------
create table public.nickname_holds (
  nickname_key  text primary key,                 -- public.nickname_key(닉네임): 비슷한 닉네임(대소문자/공백/모양이 같은 글자)도 같은 키
  hold_until    timestamptz not null,             -- 이때까지 아무도 이 키의 닉네임을 못 씀
  created_at    timestamptz not null default now()
);
create index nickname_holds_until on public.nickname_holds (hold_until);
revoke all on public.nickname_holds from anon, authenticated;
alter table public.nickname_holds enable row level security;  -- 정책 없음: 클라이언트는 읽기/쓰기 모두 불가 (함수/트리거만)
comment on table public.nickname_holds is
  '탈퇴한 장인의 닉네임 예약 (055). nickname_key만 보관, 기간(influencer_nickname_hold_days, 30일)이 지나면 influencer_daily가 지움. 직접 읽기/쓰기 불가';

-- 닉네임 검사(046): 예약된 키면 누구도(시스템 경로 - 장인 신청/운영자 바꾸기/임시 닉네임 포함) 못 씀
create or replace function public.check_nickname_key()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  k text := public.nickname_key(new.nickname);
begin
  if new.nickname is null or (tg_op = 'UPDATE' and new.nickname is not distinct from old.nickname) then
    return new;
  end if;
  perform pg_advisory_xact_lock(hashtext('nickname_key:' || k));
  if exists (select 1 from public.nickname_holds h where h.nickname_key = k and h.hold_until > now()) then
    raise exception '최근 탈퇴한 장인의 닉네임이라 지금은 쓸 수 없습니다. 비슷한 닉네임도 쓸 수 없습니다.' using errcode = '23505';
  end if;
  if coalesce(current_setting('tl.nickname_system', true), '') = 'on' then
    return new;
  end if;
  if exists (select 1 from public.profiles p where p.nickname_key = k and p.id <> new.id) then
    raise exception '이미 사용 중인 닉네임입니다. 비슷한 닉네임도 쓸 수 없습니다.' using errcode = '23505';
  end if;
  return new;
end;
$$;

-- 임시 닉네임(046)도 예약된 키는 피한다
create or replace function public.influencer_temp_nickname()
returns text language plpgsql security definer set search_path = ''
as $$
declare
  cand text;
begin
  loop
    cand := '탑신병자#' || substr(md5(random()::text || clock_timestamp()::text), 1, 6);
    exit when not exists (select 1 from public.profiles where nickname_key = public.nickname_key(cand))
          and not exists (select 1 from public.nickname_holds where nickname_key = public.nickname_key(cand));
  end loop;
  return cand;
end;
$$;

-- 장인 하루 작업(046): 5) 기간이 지난 닉네임 예약 지우기를 더한다 (새 pg_cron 없음)
create or replace function public.influencer_daily()
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  r record;
  back text;
  n_expired integer := 0;
  n_warned integer := 0;
  n_reset integer := 0;
  n_purged integer := 0;
  n_holds integer := 0;
  warn_days integer := coalesce(public.xp_rule('influencer_expiring_days'), 3);
  left_days integer;
begin
  -- 1) 만료: 기한이 지난 처리 전 신청
  for r in select id, user_id, created_at, expires_at from public.influencer_applications
            where status = 'pending' and expires_at <= now() order by id loop
    back := public.influencer_close(r.id, 'expired', null, false, false);
    if r.user_id is not null then
      insert into public.notifications (user_id, kind, message)
      values (r.user_id, 'influencer_expired',
              format('%s일 안에 확인이 끝나지 않아 신청이 만료됐습니다. 다시 신청할 수 있습니다.',
                     round(extract(epoch from (r.expires_at - r.created_at)) / 86400)::integer)
              || public.influencer_reverted_sentence(back));
    end if;
    n_expired := n_expired + 1;
  end loop;

  -- 2) 만료 전 알림: 남은 기간이 warn_days 이하, 아직 안 보낸 신청만 (한 신청에 한 번)
  for r in select id, user_id, kind, expires_at from public.influencer_applications
            where status = 'pending' and expiring_notified_at is null and user_id is not null
              and expires_at <= now() + make_interval(days => warn_days) for update loop
    left_days := greatest(ceil(extract(epoch from (r.expires_at - now())) / 86400)::integer, 1);
    insert into public.notifications (user_id, kind, message)
    values (r.user_id, 'influencer_expiring', case when r.kind = 'grandmaster'
      then format('신청이 %s일 뒤 만료됩니다. 아직 친구 요청을 보내지 않았다면 {운영자 닉네임}으로 보내 주세요.', left_days)
      else format('신청이 %s일 뒤 만료됩니다. 확인 메일에 아직 회신하지 않았다면 만료되기 전에 회신해 주세요.', left_days) end);
    update public.influencer_applications set expiring_notified_at = now() where id = r.id;
    n_warned := n_warned + 1;
  end loop;

  -- 3) 유예가 끝난 "닉네임 변경 예정" 회원 -> 임시 닉네임
  for r in select id from public.profiles where nickname_state = 'yielding' and nickname_reset_at <= now() for update loop
    perform public.system_set_nickname(r.id, public.influencer_temp_nickname(), null, null, 'reset');
    insert into public.notifications (user_id, kind, message)
    values (r.id, 'nickname_reset', '운영 원칙에 따라 닉네임이 임시 닉네임으로 바뀌었습니다. 새 닉네임을 정해 주세요.');
    n_reset := n_reset + 1;
  end loop;

  -- 4) 끝난 지 influencer_keep_days(365)일 지난 신청 정리 (처리 전/승인 중인 것은 남김)
  delete from public.influencer_applications
   where status not in ('pending', 'approved')
     and coalesce(revoked_at, ended_at) < now() - make_interval(days => coalesce(public.xp_rule('influencer_keep_days'), 365));
  get diagnostics n_purged = row_count;

  -- 5) (055) 기간이 지난 탈퇴 장인 닉네임 예약 정리
  delete from public.nickname_holds where hold_until <= now();
  get diagnostics n_holds = row_count;

  return jsonb_build_object('expired', n_expired, 'expiring_notified', n_warned, 'nickname_reset', n_reset, 'purged', n_purged,
                            'nickname_holds_purged', n_holds);
end;
$$;

-- ---------------------------------------------------------------------
-- 3. 장인 인증 신청: 탈퇴하면 식별 정보를 지우고 상태/유형/시각만 남긴다
-- ---------------------------------------------------------------------
-- 지우는 칸: 희망 닉네임, 옛 닉네임, 되돌린 닉네임, 채널 URL/키, op.gg URL, 공식 이메일, 라이엇 ID/해시, 심사/해제 메모, 처리한 운영진
-- 남는 칸: id, 유형(kind), 상태(status), 직접 지정 여부(direct), 신청/기한/끝난/해제 시각, 늘린 횟수, 만료 전 알림 시각
alter table public.influencer_applications alter column nickname drop not null;
alter table public.influencer_applications drop constraint influencer_applications_fields;

create or replace function public.influencer_applications_clear_private()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if old.user_id is not null and new.user_id is null and new.status in ('pending', 'approved') then
    new.status := 'withdrawn';
    new.ended_at := coalesce(new.ended_at, now());
  end if;
  if new.user_id is null then  -- (055) 탈퇴: 식별 정보를 모두 지운다
    new.nickname := null;
    new.old_nickname := null;
    new.nickname_reverted := null;
    new.channel_url := null;
    new.channel_key := null;
    new.opgg_url := null;
    new.review_note := null;
    new.revoke_note := null;
    new.reviewed_by := null;
    new.retry_now := false;
  end if;
  if new.status <> 'pending' then
    new.official_email := null;
    new.riot_id := null;
  end if;
  if new.status not in ('pending', 'approved') then
    new.riot_key := null;
  end if;
  return new;
end;
$$;

-- 이미 탈퇴한 회원의 신청 기록 (user_id가 비어 있는 줄) 한 번 정리 - 위 트리거가 식별 칸을 비운다
do $$
declare
  n integer;
begin
  update public.influencer_applications
     set status = case when status in ('pending', 'approved') then 'withdrawn' else status end,
         ended_at = case when status in ('pending', 'approved') then coalesce(ended_at, now()) else ended_at end,
         nickname = null
   where user_id is null
     and (nickname is not null or old_nickname is not null or nickname_reverted is not null or channel_url is not null
          or channel_key is not null or opgg_url is not null or official_email is not null or riot_id is not null
          or riot_key is not null or review_note is not null or revoke_note is not null or reviewed_by is not null
          or status in ('pending', 'approved'));
  get diagnostics n = row_count;
  raise notice '055 한 번 정리: 이미 탈퇴한 회원의 장인 신청 기록 %줄', n;
end $$;

alter table public.influencer_applications add constraint influencer_applications_fields check (
  case
    when user_id is null then status <> 'pending' and nickname is null and old_nickname is null and nickname_reverted is null
      and channel_url is null and channel_key is null and official_email is null and riot_id is null and riot_key is null
      and opgg_url is null and review_note is null and revoke_note is null and reviewed_by is null
    when direct then status <> 'pending' and channel_url is null and channel_key is null and official_email is null
      and riot_id is null and riot_key is null and opgg_url is null
    when kind in ('creator', 'pro') then channel_url is not null and channel_key is not null and riot_id is null and riot_key is null
      and opgg_url is null and (status <> 'pending' or official_email is not null)
    else official_email is null and channel_url is null and channel_key is null and opgg_url is not null
      and (status <> 'pending' or (riot_id is not null and riot_key is not null))
  end);
alter table public.influencer_applications add constraint influencer_applications_nickname_kept
  check (user_id is null or nickname is not null);

-- ---------------------------------------------------------------------
-- 4. 운영진 처리 기록(moderation_log): 대상 회원이 탈퇴하면 대상 칸과 메모의 닉네임을 지운다
-- ---------------------------------------------------------------------
-- 처리한 사람(actor)/종류(action)/대상 종류(target_kind)/시각은 그대로 1년 보관 (035 purge_old_moderation_log)
alter table public.moderation_log alter column target_id drop not null;

-- 메모에서 대상 회원을 알 수 있는 부분을 지운다
--   - 회원 닉네임 바꾸기(rename_member) "옛 \u2192 새 \u00B7 사유": 앞의 "옛 \u2192 새 \u00B7 "를 지우고 사유만 (형식이 다르면 메모 전체를 지움)
--   - 링크(link) 처리 메모 맨 앞의 링크 주소 (장인 채널 주소라 누구인지 바로 알 수 있음)
--   - 남은 메모 안의 그 회원 닉네임(2자 이상)은 "탈퇴한 이용자"로
create function public.moderation_note_scrub(p_kind text, p_action text, p_note text, p_target_nickname text, p_names text[])
returns text language plpgsql immutable set search_path = ''
as $$
declare
  n text := p_note;
  head text;
  pos integer;
  nm text;
begin
  if n is null then
    return null;
  end if;
  if p_action = 'rename_member' then
    head := E' \u2192 ' || coalesce(p_target_nickname, '') || E' \u00B7 ';
    pos := case when p_target_nickname is null then 0 else strpos(n, head) end;
    n := case when pos > 0 then substr(n, pos + char_length(head)) else null end;
  end if;
  if p_kind = 'link' and n is not null then
    n := regexp_replace(n, '^https?://\S+(' || E' \u00B7 ' || ')?', '');
  end if;
  foreach nm in array coalesce(p_names, '{}'::text[]) loop
    if n is not null and char_length(nm) >= 2 then
      n := replace(n, nm, '탈퇴한 이용자');
    end if;
  end loop;
  return nullif(btrim(n), '');
end;
$$;

-- 이미 탈퇴한 회원이 대상인 기록 한 번 정리
--   - 회원(user): 대상 id의 계정이 없음
--   - 장인 신청(influencer_application): 그 신청의 user_id가 비어 있음
--   - 링크(link): 대상 닉네임을 지금 쓰는 회원도, 닉네임 변경 기록(남아 있는 회원)에 그 닉네임도 없음
do $$
declare
  n integer;
begin
  with gone as (
    select m.id from public.moderation_log m
     where m.target_nickname is distinct from '탈퇴한 이용자'
       and (   (m.target_kind = 'user' and m.target_id is not null
                and not exists (select 1 from public.profiles p where p.id::text = m.target_id))
            or (m.target_kind = 'influencer_application'
                and exists (select 1 from public.influencer_applications a where a.id::text = m.target_id and a.user_id is null))
            or (m.target_kind = 'link' and m.target_nickname is not null
                and not exists (select 1 from public.profiles p where p.nickname = m.target_nickname)
                and not exists (select 1 from public.nickname_changes c join public.profiles p on p.id = c.user_id
                                 where m.target_nickname in (c.old_nickname, c.new_nickname))))
  )
  update public.moderation_log m
     set note = public.moderation_note_scrub(m.target_kind, m.action, m.note, m.target_nickname, array[m.target_nickname]),
         target_id = null,
         target_nickname = '탈퇴한 이용자'
    from gone where gone.id = m.id;
  get diagnostics n = row_count;
  raise notice '055 한 번 정리: 이미 탈퇴한 회원이 대상인 처리 기록 %줄', n;
end $$;

-- ---------------------------------------------------------------------
-- 5. 추천/비추천: 탈퇴해도 지우지 않고 누른 사람 칸만 비운다 (수 유지)
-- ---------------------------------------------------------------------
-- 기본 키 (빌드/글, 사람) -> 새 id. 한 사람 한 표는 유일 제약으로 (비운 칸(NULL)끼리는 겹쳐도 됨 = 익명 표 여러 개)
-- 읽기 정책(user_id = 내 id)은 그대로: 비운 줄은 아무 회원과도 맞지 않아 운영자만 본다
alter table public.build_votes drop constraint build_votes_pkey;
alter table public.build_votes add column id bigint generated always as identity;
alter table public.build_votes add constraint build_votes_pkey primary key (id);
alter table public.build_votes add constraint build_votes_once unique (build_id, user_id);
alter table public.build_votes alter column user_id drop not null;
alter table public.build_votes drop constraint build_votes_user_id_fkey;
alter table public.build_votes add constraint build_votes_user_id_fkey
  foreign key (user_id) references public.profiles (id) on delete set null;

alter table public.post_votes drop constraint post_votes_pkey;
alter table public.post_votes add column id bigint generated always as identity;
alter table public.post_votes add constraint post_votes_pkey primary key (id);
alter table public.post_votes add constraint post_votes_once unique (post_id, user_id);
alter table public.post_votes alter column user_id drop not null;
alter table public.post_votes drop constraint post_votes_user_id_fkey;
alter table public.post_votes add constraint post_votes_user_id_fkey
  foreign key (user_id) references public.profiles (id) on delete set null;

-- 추천 수 트리거(008): 누른 사람 칸만 바뀌면(탈퇴로 비움) 빌드를 건드리지 않는다
--   -> 빌드 up_count가 그대로라 작성자 경험치/칭호 다시 계산(builds_rewards)도 돌지 않고 알림도 없다
create or replace function public.apply_build_vote()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and new.build_id = old.build_id and new.value = old.value then
    return null;  -- (055) 탈퇴로 user_id만 비워짐: 수는 그대로
  end if;
  if tg_op in ('UPDATE', 'DELETE') then
    update public.builds
       set up_count   = up_count   - (old.value = 1)::int,
           down_count = down_count - (old.value = -1)::int
     where id = old.build_id;
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    update public.builds
       set up_count   = up_count   + (new.value = 1)::int,
           down_count = down_count + (new.value = -1)::int
     where id = new.build_id;
  end if;
  return null;
end;
$$;

-- ---------------------------------------------------------------------
-- 6. 탈퇴 정리 함수 + 공통 안쪽 탈퇴 함수
-- ---------------------------------------------------------------------
-- withdraw_cleanup(회원): 프로필이 지워지기 직전에 트리거가 부른다 (어느 길로 지우든 - 탈퇴/카카오/비회원 정리/대시보드 삭제)
--   1) 인증된 장인이면 닉네임 키를 30일 예약
--   2) 처리 기록에서 이 회원이 대상인 줄: target_id 비움, target_nickname "탈퇴한 이용자", 메모의 닉네임/링크 주소 지움
--   (장인 신청 기록은 on delete set null 때 신청 표 트리거가, 추천/비추천은 on delete set null이 처리)
create function public.withdraw_cleanup(p_user uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  prof public.profiles%rowtype;
  names text[];
begin
  select * into prof from public.profiles where id = p_user;
  if not found then
    return;
  end if;

  if prof.influencer is not null and prof.nickname_key is not null then
    insert into public.nickname_holds (nickname_key, hold_until)
    values (prof.nickname_key, now() + make_interval(days => coalesce(public.xp_rule('influencer_nickname_hold_days'), 30)))
    on conflict (nickname_key) do update set hold_until = greatest(public.nickname_holds.hold_until, excluded.hold_until);
  end if;

  -- 이 회원이 썼던 닉네임 (지금 + 변경 기록 + 장인 신청의 희망/옛/되돌린 닉네임)
  select coalesce(array_agg(distinct x.n), '{}') into names
    from (select prof.nickname as n
          union all select c.old_nickname from public.nickname_changes c where c.user_id = p_user
          union all select c.new_nickname from public.nickname_changes c where c.user_id = p_user
          union all select a.nickname from public.influencer_applications a where a.user_id = p_user
          union all select a.old_nickname from public.influencer_applications a where a.user_id = p_user
          union all select a.nickname_reverted from public.influencer_applications a where a.user_id = p_user) x
   where x.n is not null;

  update public.moderation_log m
     set note = public.moderation_note_scrub(m.target_kind, m.action, m.note, m.target_nickname, names),
         target_id = null,
         target_nickname = '탈퇴한 이용자'
   where (m.target_kind = 'user' and m.target_id = p_user::text)
      or (m.target_kind = 'influencer_application'
          and m.target_id in (select a.id::text from public.influencer_applications a where a.user_id = p_user))
      or (m.target_kind = 'link'
          and (m.target_id in (select l.id::text from public.ext_links l where l.owner_id = p_user)
               or m.target_nickname = any (names)));
end;
$$;
comment on function public.withdraw_cleanup(uuid) is
  '탈퇴 정리 (055): 장인 닉네임 예약 + 처리 기록의 대상 회원 지우기. 프로필 삭제 트리거(profiles_anonymize_on_delete)만 부른다';

create function public.withdraw_on_profile_delete()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  perform public.withdraw_cleanup(old.id);
  return old;
end;
$$;
-- 이름 순서로 profiles_board_delete/profiles_delete_unpublished_builds보다 먼저 돈다 (BEFORE DELETE 트리거는 이름 순)
create trigger profiles_anonymize_on_delete before delete on public.profiles
  for each row execute function public.withdraw_on_profile_delete();

-- 공통 안쪽 탈퇴 함수: delete_my_account / kakao_unlinked / cleanup_guest_accounts가 부른다. 아무도 직접 못 부름
-- 돌려주는 값: 연결돼 있던 카카오 ID (없으면 null)
create function public.withdraw_account_unchecked(p_user uuid)
returns text language plpgsql security definer set search_path = ''
as $$
declare
  r text;
  kakao text;
begin
  select role into r from public.profiles where id = p_user for update;
  if r = 'admin' then
    raise exception '운영자 계정은 탈퇴할 수 없습니다.' using errcode = '42501';
  end if;
  select provider_id into kakao from auth.identities where user_id = p_user and provider = 'kakao' limit 1;
  delete from auth.users where id = p_user;  -- 정리는 profiles_anonymize_on_delete 트리거 + on delete 규칙
  return kakao;
end;
$$;
comment on function public.withdraw_account_unchecked(uuid) is
  '공통 안쪽 탈퇴 함수 (055). delete_my_account/kakao_unlinked/cleanup_guest_accounts만 부름. 운영자 불가. 카카오 ID를 돌려줌';

create or replace function public.delete_my_account(p_confirm text)
returns text language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  prof public.profiles%rowtype;
  word text;
begin
  if me is null then
    raise exception '로그인해 주세요.' using errcode = '42501';
  end if;
  select * into prof from public.profiles where id = me for update;
  if found and prof.role = 'admin' then
    raise exception '운영자 계정은 탈퇴할 수 없습니다.' using errcode = '42501';
  end if;
  word := case when coalesce(prof.is_guest, false) then '지우기' else '탈퇴' end;
  if btrim(coalesce(p_confirm, '')) is distinct from coalesce(prof.nickname, word) then
    if prof.nickname is null then
      raise exception '확인 칸에 "%"를 그대로 적어 주세요.', word using errcode = '22023';
    end if;
    raise exception '확인 칸에 내 닉네임을 그대로 적어 주세요.' using errcode = '22023';
  end if;
  return public.withdraw_account_unchecked(me);
end;
$$;

create or replace function public.kakao_unlinked(p_kakao_id text)
returns text language plpgsql security definer set search_path = ''
as $$
declare
  uid uuid;
  left_providers jsonb;
begin
  select user_id into uid from auth.identities where provider = 'kakao' and provider_id = p_kakao_id;
  if uid is null then
    return 'not_found';  -- 이미 탈퇴했거나 연결을 뗀 사람 (우리 탈퇴 버튼이 카카오 연결 끊기를 부르면 이 알림이 다시 온다)
  end if;
  if exists (select 1 from auth.identities where user_id = uid and provider <> 'kakao') then
    delete from auth.identities where user_id = uid and provider = 'kakao';
    select coalesce(jsonb_agg(provider order by provider), '[]'::jsonb) into left_providers
    from (select distinct provider from auth.identities where user_id = uid) x;
    update auth.users
    set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb)
      || jsonb_build_object('providers', left_providers)
      || case when raw_app_meta_data ->> 'provider' = 'kakao'
              then jsonb_build_object('provider', left_providers ->> 0) else '{}'::jsonb end
    where id = uid;
    return 'unlinked';
  end if;
  if exists (select 1 from public.profiles where id = uid and role = 'admin') then
    return 'operator_kept';  -- 운영자 1명 규칙: 지우지 않고 기록만 (Edge Function 로그)
  end if;
  perform public.withdraw_account_unchecked(uid);
  return 'deleted';
end;
$$;

create or replace function public.cleanup_guest_accounts()
returns integer language plpgsql security definer set search_path = ''
as $$
declare
  empty_days integer := public.xp_rule('guest_empty_days');
  idle_days integer := public.xp_rule('guest_idle_days');
  r record;
  n integer := 0;
begin
  for r in
    select p.id from public.profiles p join auth.users u on u.id = p.id
     where u.is_anonymous and p.is_guest and p.role <> 'admin'
       and p.last_seen_at < now() - make_interval(days =>
             case when public.guest_has_records(p.id) then idle_days else empty_days end)
     order by p.id
  loop
    perform public.withdraw_account_unchecked(r.id);
    n := n + 1;
  end loop;
  return n;
end;
$$;

-- ---------------------------------------------------------------------
-- 7. 함수 권한 (새 함수는 아무도 직접 못 부름. 바꾼 함수의 권한은 create or replace라 그대로)
-- ---------------------------------------------------------------------
revoke execute on function public.moderation_note_scrub(text, text, text, text, text[]) from public, anon, authenticated;
revoke execute on function public.withdraw_cleanup(uuid) from public, anon, authenticated;
revoke execute on function public.withdraw_on_profile_delete() from public, anon, authenticated;
revoke execute on function public.withdraw_account_unchecked(uuid) from public, anon, authenticated;

commit;
