-- =====================================================================
-- 054: 칭호 도감 3단계 - 한정판 대표 칭호 + 닉네임 옆 배지 (2026-11-13, SPEC 6-41)
--
-- 1. 한정판도 칭호마다 장착 가능(equippable = true)으로 정할 수 있다. 장인(influencer)은 계속 장착 불가.
--    표 제약 title_catalog_equip_activity_only(활동만) -> title_catalog_equip_kind(장인만 불가)로 바꾼다.
--    이번에 칭호를 새로 넣거나 equippable 값을 바꾸지 않는다(지금 한정판 줄은 모두 false 그대로).
-- 2. public_title_info(): 닉네임 옆 배지에 쓰는 칭호 공개 정보 [{ key, kind, name, icon, color }].
--    - 누구나(비로그인 포함) 부를 수 있다. 게시판/댓글/문서 댓글/빌드는 비로그인에게도 보이고, 지금도
--      profiles.main_title, user_titles는 비로그인이 읽을 수 있으며 배지가 그대로 나온다(schema.sql 권한, 015 board_page).
--      이 함수를 로그인 사용자에게만 열면 비로그인 화면에서 한정판 배지만 빠지게 된다.
--    - 활동 + 한정판만(장인은 따로 "장인" 표시가 있어 빠짐). 숨김(hidden) 칭호는 빠진다.
--    - 비밀(secret) 칭호는 지금 누군가 대표 칭호로 달고 있을 때만 들어간다. 대표로 단 회원이 닉네임 옆에
--      스스로 이름을 내보이는 것이므로 이름/그림/색은 공개해도 되고, 아무도 안 달았으면 이름이 새지 않는다.
--      소개/얻는 방법/기간은 어떤 칭호도 돌려주지 않는다(도감은 my_title_book() 그대로).
--    - 화면은 앱이 켜질 때 한 번 읽어서 재사용한다(모르는 키가 보이면 5분에 한 번까지 다시 읽음).
-- 3. 대표 칭호 트리거 check_main_title_equippable: 장착 가능 + 숨김이 아닌 칭호만(숨김 조건 추가).
--    가진 칭호인지는 예전처럼 외래 키 profiles_main_title_owned가 본다.
-- 4. 새 트리거 title_catalog_unequip: 운영자가 도감 표에서 어떤 칭호를 장착 불가(equippable = false)로 바꾸거나
--    숨기면(hidden = true) 그 칭호를 대표로 단 회원의 대표 칭호를 비운다(알림 없음).
--
-- 회수 때 대표 칭호 비우기는 이미 된다(바꾸지 않음): 활동 칭호는 sync_rewards, 한정판은 revoke_title이
-- user_titles 줄을 지우면 외래 키 profiles_main_title_owned(on delete set null (main_title))가 대표 칭호를 비운다.
--
-- 회원 칭호(user_titles)와 대표 칭호(profiles.main_title)는 하나도 바꾸지 않는다.
-- 새 알림 종류 없음, 새 설정값 없음, 처리 기록 종류 없음. pg_cron 없음. Edge Function 재배포 없음.
-- 실행 전 supabase/scripts/check_title_badge_before.sql, 실행 뒤 check_title_badge_after.sql.
--
-- >> 한정판을 장착 가능으로 바꾸는 예 (나중에 SQL Editor에서. 054 뒤에만 된다):
--     update public.title_catalog set equippable = true where key = '한정판 키' and kind = 'limited';
--
-- >> 되돌리기 (rollback) - 문제가 생기면 SQL Editor에서 아래를 한 번에 실행한다. 054가 만든 것만 지우고 053 상태로 돌아간다.
--    (주의: 한정판을 대표 칭호로 단 회원이 있으면 그 대표 칭호는 비워지고, 한정판의 equippable은 모두 false가 된다.
--     053의 표 제약이 한정판 장착을 허락하지 않기 때문이다. 회원이 가진 칭호 줄은 그대로.)
--     begin;
--     drop trigger if exists title_catalog_unequip on public.title_catalog;
--     drop function if exists public.title_catalog_unequip();
--     drop function if exists public.public_title_info();
--     update public.profiles p set main_title = null
--       from public.title_catalog c where c.key = p.main_title and c.kind <> 'activity';
--     update public.title_catalog set equippable = false where kind <> 'activity' and equippable;
--     alter table public.title_catalog drop constraint if exists title_catalog_equip_kind;
--     alter table public.title_catalog add constraint title_catalog_equip_activity_only check (kind = 'activity' or not equippable);
--     comment on column public.title_catalog.equippable is null;
--     create or replace function public.check_main_title_equippable()
--     returns trigger language plpgsql security definer set search_path = ''
--     as $f$
--     begin
--       if new.main_title is not null
--          and not exists (select 1 from public.title_catalog c where c.key = new.main_title and c.equippable) then
--         raise exception '이 칭호는 대표 칭호로 고를 수 없습니다.' using errcode = '23514';
--       end if;
--       return new;
--     end;
--     $f$;
--     commit;
-- =====================================================================

begin;

do $$
begin
  if to_regclass('public.title_catalog') is null then
    raise exception '053이 아직 실행되지 않았습니다. 053을 먼저 실행해 주세요.';
  end if;
  if to_regprocedure('public.public_title_info()') is not null then
    raise exception '054를 이미 실행했습니다.';
  end if;
  if not exists (select 1 from pg_constraint
                  where conname = 'title_catalog_equip_activity_only' and conrelid = 'public.title_catalog'::regclass) then
    raise exception '도감 표 제약 title_catalog_equip_activity_only가 없습니다. check_title_badge_before.sql을 확인해 주세요.';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 1. 장착 가능: 장인만 불가 (활동/한정판은 칭호마다 equippable로)
-- ---------------------------------------------------------------------
alter table public.title_catalog drop constraint title_catalog_equip_activity_only;
alter table public.title_catalog add constraint title_catalog_equip_kind check (kind <> 'influencer' or not equippable);
comment on column public.title_catalog.equippable is
  '대표 칭호로 고를 수 있나 (054: 활동/한정판은 칭호마다, 장인은 늘 false)';

-- ---------------------------------------------------------------------
-- 2. 닉네임 옆 배지용 공개 정보
-- ---------------------------------------------------------------------
create function public.public_title_info()
returns jsonb language sql stable security definer set search_path = ''
as $$
  select coalesce(jsonb_agg(
           jsonb_build_object('key', c.key, 'kind', c.kind, 'name', c.name, 'icon', c.icon, 'color', c.color)
           order by case c.kind when 'activity' then 1 else 3 end, c.sort_order, c.key),
         '[]'::jsonb)
  from public.title_catalog c
  where c.kind in ('activity', 'limited')
    and not c.hidden
    and (not c.secret or exists (select 1 from public.profiles p where p.main_title = c.key));
$$;
comment on function public.public_title_info() is
  '닉네임 옆 칭호 배지용 공개 정보 (054). 활동+한정판, 숨김 제외, 비밀 칭호는 누군가 대표로 달았을 때만. 소개/얻는 방법은 없음';

-- ---------------------------------------------------------------------
-- 3. 대표 칭호: 장착 가능 + 숨김 아님
-- ---------------------------------------------------------------------
create or replace function public.check_main_title_equippable()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if new.main_title is not null
     and not exists (select 1 from public.title_catalog c
                      where c.key = new.main_title and c.equippable and not c.hidden) then  -- 054: 숨김 칭호도 불가
    raise exception '이 칭호는 대표 칭호로 고를 수 없습니다.' using errcode = '23514';
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- 4. 장착 불가로 바꾸거나 숨기면 그 칭호를 단 대표 칭호를 비운다
-- ---------------------------------------------------------------------
create function public.title_catalog_unequip()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  update public.profiles set main_title = null where main_title = new.key;
  return null;
end;
$$;
create trigger title_catalog_unequip after update of equippable, hidden on public.title_catalog
  for each row when (not new.equippable or new.hidden)
  execute function public.title_catalog_unequip();

-- ---------------------------------------------------------------------
-- 5. 권한
-- ---------------------------------------------------------------------
revoke execute on function public.title_catalog_unequip() from public, anon, authenticated;
revoke execute on function public.public_title_info() from public;
grant execute on function public.public_title_info() to anon, authenticated;
-- check_main_title_equippable은 053에서 회수한 권한 그대로(create or replace는 권한을 바꾸지 않는다)

commit;
