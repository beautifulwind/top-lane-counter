-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것. (운영 DB 확인은 scripts/check_unselect_my_champion_after.sql)
-- 081 unselect_my_champion: 모양·권한(비로그인 불가), 허용 목록(검사 없음) · 쓰기 함수 105/31/74 · 읽기 69,
--   set_my_champion 본문 그대로(080 지문), 해제(본인 것만, 없는 것 해제는 성공, 형식 거부, 비회원 가능),
--   활동 제한 중: 해제는 되고 등록(set_my_champion)·set_my_champion 해제는 전처럼 TL423,
--   다른 사람 데이터 영향 없음, 되돌리기 블록으로 080 상태(104/31/73, 다른 함수 지문 그대로), 다시 실행하면 멈춤
\set ON_ERROR_STOP 1
\set QUIET 1
\set A  '00000000-0000-0000-0000-0000000006a1'
\set B  '00000000-0000-0000-0000-0000000006a2'
\set GU '00000000-0000-0000-0000-0000000006a3'
\set OP '00000000-0000-0000-0000-0000000006a4'
\set R  '00000000-0000-0000-0000-0000000006a5'
insert into auth.users (id, email) values (:'A', 'a@x.com'), (:'B', 'b@x.com'), (:'OP', 'op@x.com'), (:'R', 'r@x.com');
insert into auth.users (id, email, is_anonymous) values (:'GU', null, true);
update public.profiles set nickname = '해제에이' where id = :'A';
update public.profiles set nickname = '해제비' where id = :'B';
update public.profiles set nickname = '운영', role = 'admin' where id = :'OP';
update public.profiles set nickname = '제한중' where id = :'R';
insert into public.user_champions (user_id, champion) values
  (:'A', 'Ahri'), (:'A', 'Quinn'), (:'A', 'Zed'), (:'B', 'Ahri'), (:'B', 'Quinn'), (:'GU', 'Garen'), (:'R', 'Ahri'), (:'R', 'Quinn');

create function pg_temp.counts() returns text language sql stable as $$
  with f as (select p.oid, p.prosrc, p.provolatile, p.proname || '(' || oidvectortypes(p.proargtypes) || ')' as sig
               from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.prokind = 'f' and p.prorettype <> 'trigger'::regtype
                and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute')))
  select (select count(*) from f where provolatile = 'v')
    || '/' || (select count(*) from f where provolatile = 'v' and (prosrc ~ '^\s*declare\s*\n\s*_can_write constant boolean := public\.assert_can_write\(\);'
                                                             or prosrc ~ '^\s*begin\s*\n\s*perform public\.assert_can_write\(\);'))
    || '/' || (select count(*) from f where provolatile = 'v' and exists (select 1 from public.restriction_exemptions e where e.kind = 'function' and e.name = f.sig))
    || '/' || (select count(*) from f where provolatile in ('s', 'i')) $$;
-- 새 함수를 뺀 모든 함수 지문
create function pg_temp.fn_fp() returns text language sql stable as $$
  select count(*) || '/' || md5(string_agg(p.proname || '(' || oidvectortypes(p.proargtypes) || ')' || pg_get_function_result(p.oid) || p.provolatile::text
           || replace(p.prosrc, E'\r', '') || p.prosecdef::text || coalesce(array_to_string(p.proconfig, ','), '') || coalesce(array_to_string(p.proacl, ','), ''),
           '|' order by p.proname, oidvectortypes(p.proargtypes)))
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind in ('f', 'p') and p.proname <> 'unselect_my_champion' $$;
create function pg_temp.others(u uuid) returns text language sql stable as $$
  select coalesce(string_agg(user_id::text || ':' || champion, ',' order by user_id, champion), '') from public.user_champions where user_id <> u $$;
create function pg_temp.mine(u uuid) returns text language sql stable as $$
  select coalesce(string_agg(champion, ',' order by champion), '') from public.user_champions where user_id = u $$;
create function pg_temp.un(u uuid, c text) returns text language plpgsql as $$
declare r jsonb;
begin
  perform set_config('request.jwt.claim.sub', u::text, true);
  r := public.unselect_my_champion(c);
  return r::text;
exception when others then
  return sqlstate || ':' || sqlerrm;
end $$;
create function pg_temp.set(u uuid, c text, sel boolean) returns text language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', u::text, true);
  perform public.set_my_champion(c, sel);
  return 'ok';
exception when others then
  return sqlstate || ':' || sqlerrm;
end $$;

-- ===== 1. 모양·권한·허용 목록·함수 수 =====
select t.ok('unselect_my_champion(text): jsonb · volatile · security definer · search_path 빈 값 · 같은 이름 하나',
  (select provolatile = 'v' and prosecdef and proconfig = array['search_path=""'] and prorettype = 'jsonb'::regtype
          and pg_get_function_arguments(oid) = 'p_champion text'
     from pg_proc where oid = 'public.unselect_my_champion(text)'::regprocedure)
  and (select count(*) from pg_proc where proname = 'unselect_my_champion') = 1);
select t.ok('권한: 로그인만 실행, 비로그인·public 불가',
  has_function_privilege('authenticated', 'public.unselect_my_champion(text)', 'execute')
  and not has_function_privilege('anon', 'public.unselect_my_champion(text)', 'execute')
  and not exists (select 1 from pg_proc p, unnest(p.proacl) a where p.oid = 'public.unselect_my_champion(text)'::regprocedure and a::text like '=%'));
select t.ok('허용 목록에 이유와 함께 1줄, 본문에 assert_can_write 없음',
  (select reason from public.restriction_exemptions where kind = 'function' and name = 'unselect_my_champion(text)') = '내 챔피언 해제 (등록은 막음)'
  and (select prosrc not like '%assert_can_write%' from pg_proc where oid = 'public.unselect_my_champion(text)'::regprocedure));
select t.ok('함수 수: 쓰기 105 / 첫 줄 검사 31 / 허용 목록 74 / 읽기 69 (' || pg_temp.counts() || ')', pg_temp.counts() = '105/31/74/69');
select t.ok('set_my_champion 본문은 080 그대로 (지문 9c23c989…) · 첫 줄 검사 그대로 · 허용 목록에 없음',
  (select md5(replace(prosrc, E'\r', '')) from pg_proc where oid = 'public.set_my_champion(text, boolean)'::regprocedure) = '9c23c989dfc6c22ba2d81400570f9c8b'
  and not exists (select 1 from public.restriction_exemptions where name = 'set_my_champion(text, boolean)'));
select pg_temp.fn_fp() as fn0, (select count(*) || ':' || md5(string_agg(kind || name || reason, ',' order by kind, name)) from public.restriction_exemptions where name <> 'unselect_my_champion(text)') as ex0 \gset

set role anon;
reset request.jwt.claim.sub;
select t.fails('비로그인: 실행 권한 없음', $$select public.unselect_my_champion('Ahri')$$, 'permission denied');
reset role;

-- ===== 2. 해제 =====
set role authenticated;
reset request.jwt.claim.sub;
select t.fails('로그인 표시(sub)가 없으면 거부', $$select public.unselect_my_champion('Ahri')$$, '로그인해 주세요');
reset role;
select pg_temp.others(:'A') as oa0 \gset
set role authenticated;
select pg_temp.un(:'A', 'Ahri') as r1 \gset
reset role;
select t.ok('해제: 본인 줄만 지우고 { champion, selected:false, count, limit } 를 돌려줌',
  :'r1'::jsonb = '{"champion": "Ahri", "selected": false, "count": 2, "limit": 10}'::jsonb and pg_temp.mine(:'A') = 'Quinn,Zed');
select t.ok('다른 사람(B의 Ahri 포함) 등록은 그대로', pg_temp.others(:'A') = :'oa0');
set role authenticated;
select pg_temp.un(:'A', 'Ahri') as r2, pg_temp.un(:'A', 'Teemo') as r3, pg_temp.un(:'A', 'Not a champ') as r4, pg_temp.un(:'A', null) as r5 \gset
reset role;
select t.ok('이미 해제했거나 등록하지 않은 챔피언 해제는 그대로 성공 (count 2)',
  (:'r2'::jsonb ->> 'count')::int = 2 and (:'r3'::jsonb ->> 'count')::int = 2 and pg_temp.mine(:'A') = 'Quinn,Zed');
select t.ok('형식이 틀리거나 비면 22023 「없는 챔피언입니다」', :'r4' like '22023:없는 챔피언입니다%' and :'r5' like '22023:없는 챔피언입니다%');
set role authenticated;
select pg_temp.un(:'GU', 'Garen') as r6 \gset
reset role;
select t.ok('비회원(게스트)도 해제 가능', (:'r6'::jsonb ->> 'count')::int = 0 and pg_temp.mine(:'GU') = '');
set role authenticated;
set request.jwt.claim.sub = :'A';
select t.fails('표에 직접 지우기는 여전히 불가', $$delete from public.user_champions where champion = 'Quinn'$$, 'permission denied');
reset role;

-- ===== 3. 활동 제한 중 =====
insert into public.user_restrictions (user_id, reason, days, ends_at, created_by) values (:'R', '검사', 7, now() + interval '7 days', :'OP');
select pg_temp.others(:'R') as or0 \gset
set role authenticated;
select pg_temp.set(:'R', 'Garen', true) as s1, pg_temp.set(:'R', 'Quinn', false) as s2 \gset
reset role;
select t.ok('제한 중: set_my_champion 등록·해제는 전처럼 TL423, 데이터 그대로',
  :'s1' like 'TL423:활동이 제한된 상태입니다.%' and :'s2' like 'TL423:%' and pg_temp.mine(:'R') = 'Ahri,Quinn');
set role authenticated;
select pg_temp.un(:'R', 'Quinn') as s3 \gset
reset role;
select t.ok('제한 중: unselect_my_champion 해제는 됨', (:'s3'::jsonb ->> 'count')::int = 1 and pg_temp.mine(:'R') = 'Ahri');
select t.ok('제한 중 해제도 다른 사람 데이터는 그대로', pg_temp.others(:'R') = :'or0');
set role authenticated;
select pg_temp.set(:'R', 'Quinn', true) as s4 \gset
reset role;
select t.ok('제한 중: 해제 뒤 다시 등록은 여전히 TL423', :'s4' like 'TL423:%' and pg_temp.mine(:'R') = 'Ahri');
update public.user_restrictions set lifted_at = now(), lifted_by = :'OP' where user_id = :'R';
set role authenticated;
select pg_temp.set(:'R', 'Quinn', true) as s5 \gset
reset role;
select t.ok('제한이 풀리면 등록 다시 됨', :'s5' = 'ok' and pg_temp.mine(:'R') = 'Ahri,Quinn');

-- ===== 4. 되돌리기 블록 (081 파일 그대로) → 080 상태 =====
select pg_temp.mine(:'A') || '|' || pg_temp.others(:'A') as data0 \gset
begin;
drop function public.unselect_my_champion(text);
delete from public.restriction_exemptions where kind = 'function' and name = 'unselect_my_champion(text)';
select t.ok('되돌리기: 함수·허용 목록 줄 없음 · 쓰기 104/31/73 · 읽기 69 · 다른 함수 지문·허용 목록 그대로 · 등록 데이터 그대로 (' || pg_temp.counts() || ')',
  to_regprocedure('public.unselect_my_champion(text)') is null and pg_temp.counts() = '104/31/73/69' and pg_temp.fn_fp() = :'fn0'
  and (select count(*) || ':' || md5(string_agg(kind || name || reason, ',' order by kind, name)) from public.restriction_exemptions) = :'ex0'
  and pg_temp.mine(:'A') || '|' || pg_temp.others(:'A') = :'data0');
rollback;
select t.fails('081을 한 번 더 실행하면 멈춤 (081 파일의 실행 전 확인 그대로)', $q$do $chk$
begin
  if to_regprocedure('public.set_my_champion(text, boolean)') is null or to_regclass('public.user_champions') is null then
    raise exception '080(내 챔피언)을 먼저 실행해야 합니다. 실행을 멈춥니다.';
  end if;
  if to_regprocedure('public.unselect_my_champion(text)') is not null
     or exists (select 1 from public.restriction_exemptions where kind = 'function' and name = 'unselect_my_champion(text)') then
    raise exception 'unselect_my_champion이 이미 있습니다(081을 이미 실행함). 실행을 멈춥니다.';
  end if;
end $chk$$q$, '이미 있습니다');
