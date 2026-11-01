-- =====================================================================
-- 회원 등급 정리: 운영자 1명 (role = 'admin')
-- - 운영자는 1명이고 모든 권한을 가진다 (RLS의 is_admin() = "운영자인가")
-- - 운영자는 항상 Lv.0, 경험치·칭호가 쌓이지 않는다
-- - 다른 사람을 관리자로 지정하는 기능은 보류 → set_user_role() 삭제
--   (운영자 교체는 Supabase SQL Editor에서만 가능)
-- 002_auth.sql까지 실행한 DB에서, SQL Editor에 통째로 붙여넣어 "한 번" 실행한다.
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. 관리자 지정 기능 보류: 앱에서 role을 바꿀 수 있는 유일한 길을 없앤다
--    (profiles.role 칸은 2단계부터 클라이언트가 직접 못 바꾼다)
-- ---------------------------------------------------------------------
drop function if exists public.set_user_role(uuid, text);

comment on function public.is_admin() is '지금 로그인한 사람이 운영자(role = admin, 1명)인가';

-- ---------------------------------------------------------------------
-- 2. 운영자는 1명만
-- ---------------------------------------------------------------------
create unique index profiles_one_operator on public.profiles ((true)) where role = 'admin';

-- ---------------------------------------------------------------------
-- 3. 운영자는 항상 Lv.0 · 경험치 0 · 대표 칭호 없음
--    운영자에서 내려오면 Lv.1 · 경험치 0부터 다시 시작
-- ---------------------------------------------------------------------
create function public.operator_profile_rules()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if new.role = 'admin' then
    new.level := 0;
    new.xp := 0;
    new.main_title := null;
  elsif tg_op = 'UPDATE' and old.role = 'admin' then
    new.level := 1;
    new.xp := 0;
  end if;
  return new;
end;
$$;
create trigger profiles_operator_rules before insert or update on public.profiles
  for each row execute function public.operator_profile_rules();

-- 운영자가 되면 이미 가진 칭호를 지운다
create function public.operator_clear_titles()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  delete from public.user_titles where user_id = new.id;
  return null;
end;
$$;
create trigger profiles_operator_clear_titles after insert or update of role on public.profiles
  for each row when (new.role = 'admin') execute function public.operator_clear_titles();

-- 운영자 앞으로 들어오는 경험치 기록·칭호는 조용히 무시 (6단계 지급 함수가 신경 쓰지 않아도 됨)
create function public.skip_operator_rewards()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if exists (select 1 from public.profiles where id = new.user_id and role = 'admin') then
    return null;  -- 이 행은 넣지 않는다
  end if;
  return new;
end;
$$;
create trigger xp_events_skip_operator before insert or update on public.xp_events
  for each row execute function public.skip_operator_rewards();
create trigger user_titles_skip_operator before insert or update on public.user_titles
  for each row execute function public.skip_operator_rewards();

-- Lv.0은 운영자만, 일반 유저는 Lv.1 이상 (2단계의 "level >= 1" 제약을 바꾼다)
alter table public.profiles drop constraint profiles_level_check;

-- 지금 운영자에게 바로 적용 (트리거가 Lv.0 · 경험치 0 · 칭호 없음으로 바꾼다)
update public.profiles set role = role where role = 'admin';

alter table public.profiles add constraint profiles_level_by_role check (
  (role = 'admin' and level = 0 and xp = 0 and main_title is null)
  or (role <> 'admin' and level >= 1)
);

-- 트리거 전용 함수는 API로 직접 호출하지 못하게
revoke execute on function public.operator_profile_rules() from public, anon, authenticated;
revoke execute on function public.operator_clear_titles() from public, anon, authenticated;
revoke execute on function public.skip_operator_rewards() from public, anon, authenticated;

commit;

-- =====================================================================
-- (참고) 운영자를 다른 계정으로 바꿔야 할 때 — SQL Editor에서만, 아래 순서대로
--   update public.profiles set role = 'user'  where role = 'admin';
--   update public.profiles set role = 'admin' where id = (select id from auth.users where email = '새 운영자 이메일');
-- =====================================================================
