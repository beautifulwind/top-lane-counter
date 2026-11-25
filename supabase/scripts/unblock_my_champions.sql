-- =====================================================================
-- block_my_champions_until_open.sql로 건 「내 챔피언」 날짜 차단을 풀기 (SPEC 6-119). set_my_champion을 080 본문으로 되돌린다.
-- SQL Editor에 통째로 붙여넣어 실행한다. 함수 본문이 「차단본」이나 「080 본문」이 아니면 아무것도 바꾸지 않고 멈춘다(두 번 실행해도 괜찮다).
-- 맨 끝 표가 정상인 값: 080 본문과 같음 true · 날짜 조건 없음 true · 첫 줄 검사 true · 로그인 실행 true · 비로그인 실행 false.
-- 「등록된 것」은 지금까지 등록된 줄·사람 수(값은 상관없음). 이 스크립트는 등록 데이터를 건드리지 않는다.
-- =====================================================================
begin;

do $chk$
declare
  h text := (select md5(replace(prosrc, E'\r', '')) from pg_proc where oid = to_regprocedure('public.set_my_champion(text, boolean)'));
begin
  if h is null or h not in ('0c4a93d2cc5f0227ac8e9396cbbecf93', '9c23c989dfc6c22ba2d81400570f9c8b') then
    raise exception 'set_my_champion이 차단본도 080 본문도 아닙니다. 실행을 멈춥니다.';
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

select (md5(replace(prosrc, E'\r', '')) = '9c23c989dfc6c22ba2d81400570f9c8b') as "080 본문과 같음",
       (prosrc not like '%2026-12-25%') as "날짜 조건 없음",
       (prosrc ~ '^\s*declare\s*\n\s*_can_write constant boolean := public\.assert_can_write\(\);') as "첫 줄 검사",
       has_function_privilege('authenticated', oid, 'execute') as "로그인 실행",
       has_function_privilege('anon', oid, 'execute') as "비로그인 실행",
       (select count(*) || '줄 / ' || count(distinct user_id) || '명' from public.user_champions) as "등록된 것"
  from pg_proc where oid = 'public.set_my_champion(text, boolean)'::regprocedure;
