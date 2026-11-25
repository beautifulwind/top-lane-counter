-- =====================================================================
-- !! 더 실행하지 않는다: 2026-11-25에 기능을 바로 열기로 바꿨다(SPEC 6-119). 풀기는 unblock_my_champions.sql. 아래는 기록용.
-- (선택) 「내 챔피언」 새 등록을 2026-12-25(한국 0시) 전에는 DB에서도 막기 (SPEC 6-118). 번호 있는 마이그레이션이 아니다.
-- set_my_champion 본문에 날짜 조건 하나만 더한다. 이름·인자·반환·권한·설명, 첫 줄 assert_can_write()는 그대로. 해제는 막지 않는다.
-- 날짜가 지나면 아무것도 하지 않아도 열린다. 날짜는 src/lib/legal.js MY_CHAMPIONS_EDITION과 같아야 한다(화면 테스트가 확인).
-- 080을 실행한 DB에서 SQL Editor에 통째로 붙여넣어 실행한다. 080 본문이 아닌 함수가 있으면 멈춘다(두 번 실행해도 멈춤).
-- 맨 끝 표: 「조건 있음」 true, 「첫 줄 검사」 true, 「로그인 실행」 true, 「비로그인 실행」 false 이면 정상. 「이미 등록된 것」은 지금까지 등록된 줄·사람 수.
--
-- >> 되돌리기: 아래를 맨 앞 "-- " 를 빼고 실행하면 080 본문으로 돌아간다.
-- begin;
-- create or replace function public.set_my_champion(p_champion text, p_selected boolean)
-- returns jsonb language plpgsql security definer set search_path = ''
-- as $$
-- declare
--   _can_write constant boolean := public.assert_can_write();
--   me uuid := (select auth.uid());
--   lim constant integer := 10;
--   n integer;
-- begin
--   if me is null then
--     raise exception '로그인해 주세요.' using errcode = '42501';
--   end if;
--   if p_selected is null then
--     raise exception '선택할지 해제할지 알려 주세요.' using errcode = '22023';
--   end if;
--   if coalesce(p_champion, '') !~ '^[A-Za-z]{1,30}$' then
--     raise exception '없는 챔피언입니다. 다시 골라 주세요.' using errcode = '22023';
--   end if;
--   -- 같은 사람이 동시에 여러 번 눌러도 10개를 넘지 않게 그 사람 줄을 잠근다
--   perform 1 from public.profiles where id = me for update;
--   if not p_selected then
--     delete from public.user_champions where user_id = me and champion = p_champion;
--   elsif not exists (select 1 from public.user_champions where user_id = me and champion = p_champion) then
--     if not exists (select 1 from public.champion_catalog where champion_id = p_champion)
--        and not exists (select 1 from public.counters where counter_champion = p_champion and status = 'approved') then
--       raise exception '없는 챔피언입니다. 다시 골라 주세요.' using errcode = '22023';
--     end if;
--     select count(*) into n from public.user_champions where user_id = me;
--     if n >= lim then
--       raise exception '최대 10개까지 선택할 수 있습니다. 하나를 해제한 뒤 선택해 주세요.' using errcode = 'TL413';
--     end if;
--     insert into public.user_champions (user_id, champion) values (me, p_champion);
--   end if;
--   select count(*) into n from public.user_champions where user_id = me;
--   return jsonb_build_object('champion', p_champion, 'selected', p_selected, 'count', n, 'limit', lim);
-- end;
-- $$;
-- commit;
-- =====================================================================
begin;

do $chk$
begin
  if (select md5(replace(prosrc, E'\r', '')) from pg_proc where oid = to_regprocedure('public.set_my_champion(text, boolean)')) is distinct from '9c23c989dfc6c22ba2d81400570f9c8b' then
    raise exception 'set_my_champion이 080 본문이 아닙니다(080 전이거나 이미 바꿈). 실행을 멈춥니다.';
  end if;
end $chk$;

create or replace function public.set_my_champion(p_champion text, p_selected boolean)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  _can_write constant boolean := public.assert_can_write();
  me uuid := (select auth.uid());
  lim constant integer := 10;
  n integer;
begin
  if me is null then
    raise exception '로그인해 주세요.' using errcode = '42501';
  end if;
  if p_selected is null then
    raise exception '선택할지 해제할지 알려 주세요.' using errcode = '22023';
  end if;
  -- 방침 2026-12-25판 시행 전에는 새 등록을 받지 않는다 (서버 시각, 한국 0시부터 열림). 해제는 된다
  if p_selected and (now() at time zone 'Asia/Seoul')::date < date '2026-12-25' then
    raise exception '내 챔피언 기능은 준비 중입니다. 2026-12-25부터 쓸 수 있습니다.' using errcode = '22023';
  end if;
  if coalesce(p_champion, '') !~ '^[A-Za-z]{1,30}$' then
    raise exception '없는 챔피언입니다. 다시 골라 주세요.' using errcode = '22023';
  end if;
  -- 같은 사람이 동시에 여러 번 눌러도 10개를 넘지 않게 그 사람 줄을 잠근다
  perform 1 from public.profiles where id = me for update;
  if not p_selected then
    delete from public.user_champions where user_id = me and champion = p_champion;
  elsif not exists (select 1 from public.user_champions where user_id = me and champion = p_champion) then
    if not exists (select 1 from public.champion_catalog where champion_id = p_champion)
       and not exists (select 1 from public.counters where counter_champion = p_champion and status = 'approved') then
      raise exception '없는 챔피언입니다. 다시 골라 주세요.' using errcode = '22023';
    end if;
    select count(*) into n from public.user_champions where user_id = me;
    if n >= lim then
      raise exception '최대 10개까지 선택할 수 있습니다. 하나를 해제한 뒤 선택해 주세요.' using errcode = 'TL413';
    end if;
    insert into public.user_champions (user_id, champion) values (me, p_champion);
  end if;
  select count(*) into n from public.user_champions where user_id = me;
  return jsonb_build_object('champion', p_champion, 'selected', p_selected, 'count', n, 'limit', lim);
end;
$$;

commit;

select (prosrc like '%date ''2026-12-25''%') as "조건 있음",
       (prosrc ~ '^\s*declare\s*\n\s*_can_write constant boolean := public\.assert_can_write\(\);') as "첫 줄 검사",
       has_function_privilege('authenticated', oid, 'execute') as "로그인 실행",
       has_function_privilege('anon', oid, 'execute') as "비로그인 실행",
       (select count(*) || '줄 / ' || count(distinct user_id) || '명' from public.user_champions) as "이미 등록된 것"
  from pg_proc where oid = 'public.set_my_champion(text, boolean)'::regprocedure;
