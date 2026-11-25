-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것. (운영 DB 확인은 scripts/check_my_champions_after.sql)
-- 080 내 챔피언: 표·함수 모양과 권한(비로그인 불가, 표 직접 쓰기 불가), 등록·해제(중복 안전, 없는 챔피언 거절, 10개 한도 - 11개째 TL413),
--   비회원 가능·비로그인 거부·활동 제한 거부(TL423), 다른 사람의 등록이 보이지 않음(함수·표 모두),
--   빌드 모음: 공개 빌드만(숨김·대기·거절·숨긴 상대법 제외), 챔피언 하나로 좁히기, /builds 추천순(장인 → 추천 → 최신 → id),
--   쪽 나누기 20개(겹침·빠짐 없음), 차단한 사람 제외(blocked 개수), 탈퇴한 작성자 null, 칸 이름(이메일·운영 정보 없음),
--   탈퇴·비회원 정리 때 cascade로 지워짐, 읽어도 데이터 그대로,
--   쓰기 함수 104/31/73 · 읽기 함수 69 · 허용 목록·푸시 판정·다른 함수 지문 그대로(되돌리기 블록으로 079 상태 확인), 다시 실행하면 멈춤
\set ON_ERROR_STOP 1
\set QUIET 1
\set A   '00000000-0000-0000-0000-0000000005a1'
\set B   '00000000-0000-0000-0000-0000000005a2'
\set GU  '00000000-0000-0000-0000-0000000005a3'
\set OP  '00000000-0000-0000-0000-0000000005a4'
\set INF '00000000-0000-0000-0000-0000000005a5'
\set X   '00000000-0000-0000-0000-0000000005a6'
\set BL  '00000000-0000-0000-0000-0000000005a7'
\set R   '00000000-0000-0000-0000-0000000005a8'
-- 081(unselect_my_champion)은 이 파일이 아니라 unselect_my_champion_test.sql이 본다. 080만의 상태를 보려고 081 되돌리기 블록을 먼저 실행한다.
begin;
drop function public.unselect_my_champion(text);
delete from public.restriction_exemptions where kind = 'function' and name = 'unselect_my_champion(text)';
commit;
insert into auth.users (id, email) values (:'A', 'a@x.com'), (:'B', 'b@x.com'), (:'OP', 'op@x.com'), (:'INF', 'inf@x.com'),
  (:'X', 'x@x.com'), (:'BL', 'bl@x.com'), (:'R', 'r@x.com');
insert into auth.users (id, email, is_anonymous) values (:'GU', null, true);
update public.profiles set nickname = '팬에이' where id = :'A';
update public.profiles set nickname = '팬비' where id = :'B';
update public.profiles set nickname = '운영', role = 'admin' where id = :'OP';
update public.profiles set nickname = '장인', influencer = 'pro', influencer_at = now(), photo_path = id::text || '/a.jpg', photo_updated_at = now() where id = :'INF';
update public.profiles set nickname = '일반' where id = :'X';
update public.profiles set nickname = '차단될' where id = :'BL';
update public.profiles set nickname = '제한맨' where id = :'R';
insert into public.user_blocks (blocker_id, blocked_id) values (:'A', :'BL');

-- 빌드: 아리(Ahri) 상대법 2개(공개) + 숨긴 상대법 1개, 퀸(Quinn, fixtures: 다리우스 상대 탈퇴자 빌드 2개) + 가렌 상대 1개
--   아리: 공개 25개(장인 3 · 일반 20 · 차단될 2), 숨김 1 · 대기 1 · 거절 1, 숨긴 상대법 밑 공개 1
begin;
alter table public.builds disable trigger builds_check_new;
insert into public.counters (target_champion, counter_champion, sort_order, status) values
  ('Darius', 'Ahri', 1, 'approved'), ('Zed', 'Ahri', 1, 'approved'), ('Teemo', 'Ahri', 1, 'hidden'), ('Garen', 'Quinn', 1, 'approved'),
  ('Garen', 'Zzznew', 1, 'approved');
create temp table src as select * from public.builds where counter_id = (select id from public.counters where counter_champion = 'Quinn' and target_champion = 'Darius') order by id limit 1;
create temp table plan (n int, tgt text, mine text, author uuid, st text, up int, made timestamptz);
insert into plan
select i, case when i % 2 = 0 then 'Darius' else 'Zed' end, 'Ahri',
       case when i in (5, 12, 20) then :'INF'::uuid when i in (7, 8) then :'BL'::uuid else :'X'::uuid end,
       'approved', (i * 7) % 5, timestamptz '2026-11-01' + ((i % 6) || ' hours')::interval
  from generate_series(1, 25) i;
insert into plan values
  (101, 'Darius', 'Ahri', :'X', 'hidden', 99, now()), (102, 'Darius', 'Ahri', :'X', 'pending', 0, now()),
  (103, 'Zed', 'Ahri', :'X', 'rejected', 0, now()), (104, 'Teemo', 'Ahri', :'X', 'approved', 99, now()),
  (105, 'Garen', 'Quinn', :'X', 'approved', 3, now());
insert into public.builds (counter_id, author_id, runes, summoner_spells, starting_items, core_items, max_skill, patch, status, hide_reason, hidden_at,
                           reviewed_by, reviewed_at, reject_reason, up_count, created_at)
select c.id, p.author, s.runes, s.summoner_spells, s.starting_items, s.core_items, s.max_skill, s.patch, p.st,
       case when p.st = 'hidden' then '검사' end, case when p.st = 'hidden' then now() end,
       case when p.st = 'rejected' then :'OP'::uuid end, case when p.st = 'rejected' then now() end, case when p.st = 'rejected' then '검사' end,
       p.up, p.made
  from plan p join public.counters c on c.target_champion = p.tgt and c.counter_champion = p.mine, src s
 order by p.n;
set constraints all immediate;
alter table public.builds enable trigger builds_check_new;
commit;
-- up_count·created_at이 그대로 들어갔는지 (트리거가 덮어쓰지 않았는지)
select t.ok('검사 데이터: 아리 공개 빌드 25개 + 퀸 공개 3개, 추천 수·만든 때가 계획대로',
  (select count(*) from public.builds b join public.counters c on c.id = b.counter_id where c.counter_champion = 'Ahri' and b.status = 'approved' and c.status = 'approved') = 25
  and (select count(*) from public.builds b join public.counters c on c.id = b.counter_id where c.counter_champion = 'Quinn' and b.status = 'approved') = 3
  and (select count(distinct up_count) from public.builds b join public.counters c on c.id = b.counter_id where c.counter_champion = 'Ahri') > 3);

create function pg_temp.setc(u uuid, c text, sel boolean default true) returns jsonb language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', u::text, true);
  return public.set_my_champion(c, sel);
end $$;
create function pg_temp.err(u uuid, c text, sel boolean default true) returns text language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', u::text, true);
  perform public.set_my_champion(c, sel);
  return 'ok';
exception when others then
  return sqlstate || ':' || sqlerrm;
end $$;
create function pg_temp.mine(u uuid) returns text language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', u::text, true);
  return (select string_agg(x, ',' order by o) from jsonb_array_elements_text(public.my_champions() -> 'items') with ordinality e(x, o));
end $$;
create function pg_temp.blds(u uuid, c text default null, pg integer default 1) returns jsonb language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', u::text, true);
  return public.my_champion_builds(c, pg);
end $$;
create function pg_temp.ids(j jsonb) returns text language sql immutable as $$
  select coalesce(string_agg(e ->> 'id', ',' order by o), '') from jsonb_array_elements(j -> 'items') with ordinality x(e, o) $$;
create function pg_temp.all_ids(u uuid, c text default null) returns text language plpgsql as $$
declare r text := ''; n integer := 1; j jsonb;
begin
  loop
    j := pg_temp.blds(u, c, n);
    exit when jsonb_array_length(j -> 'items') = 0;
    r := r || case when r = '' then '' else ',' end || pg_temp.ids(j);
    n := n + 1;
  end loop;
  return r;
end $$;
-- 기대 순서: 공개(빌드·상대법 approved) · 내 챔피언 · 차단 제외, 장인 → 추천 → 최신 → id
create function pg_temp.want(u uuid, c text default null) returns text language sql stable as $$
  select coalesce(string_agg(b.id::text, ',' order by (a.influencer is not null) desc, b.up_count desc, b.created_at desc, b.id desc), '')
    from public.builds b join public.counters cc on cc.id = b.counter_id left join public.profiles a on a.id = b.author_id
   where b.status = 'approved' and cc.status = 'approved'
     and cc.counter_champion in (select champion from public.user_champions where user_id = u and (c is null or champion = c))
     and not exists (select 1 from public.user_blocks k where k.blocker_id = u and k.blocked_id = b.author_id) $$;
create function pg_temp.data_fp() returns text language sql stable as $$
  select (select md5(coalesce(string_agg(u::text, '|' order by u.user_id, u.champion), '')) from public.user_champions u)
    || '#' || (select md5(string_agg(b::text, '|' order by b.id)) from public.builds b)
    || '#' || (select md5(string_agg(p::text, '|' order by p.id)) from public.profiles p)
    || '#' || (select md5(coalesce(string_agg(n::text, '|' order by n.id), '')) from public.notifications n) $$;
create function pg_temp.fn_fp() returns text language sql stable as $$
  select count(*) || '/' || md5(string_agg(p.proname || '(' || oidvectortypes(p.proargtypes) || ')' || pg_get_function_result(p.oid) || p.provolatile::text
           || replace(p.prosrc, E'\r', '') || p.prosecdef::text || coalesce(array_to_string(p.proconfig, ','), '') || coalesce(array_to_string(p.proacl, ','), ''),
           '|' order by p.proname, oidvectortypes(p.proargtypes)))
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind in ('f', 'p') and p.proname not in ('set_my_champion', 'my_champions', 'my_champion_builds') $$;
create function pg_temp.counts() returns text language sql stable as $$
  with f as (select p.oid, p.prosrc, p.provolatile, p.proname || '(' || oidvectortypes(p.proargtypes) || ')' as sig
               from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.prokind = 'f' and p.prorettype <> 'trigger'::regtype
                and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute')))
  select (select count(*) from f where provolatile = 'v')
    || '/' || (select count(*) from f where provolatile = 'v' and (prosrc ~ '^\s*declare\s*\n\s*_can_write constant boolean := public\.assert_can_write\(\);'
                                                             or prosrc ~ '^\s*begin\s*\n\s*perform public\.assert_can_write\(\);'))
    || '/' || (select count(*) from f where provolatile = 'v' and exists (select 1 from public.restriction_exemptions e where e.kind = 'function' and e.name = f.sig))
    || '/' || (select count(*) from f where provolatile in ('s', 'i'))
    || '/' || (select md5(string_agg(kind || ':' || name || ':' || reason, ',' order by kind, name)) from public.restriction_exemptions) $$;
create function pg_temp.push_fp() returns text language sql stable as $$
  with kinds as (
    select (regexp_matches(pg_get_constraintdef(oid), '''([a-z_]+)''', 'g'))[1] as k
      from pg_constraint where conname = 'notifications_kind_check' and conrelid = 'public.notifications'::regclass
    union select 'no_such_kind')
  select md5(string_agg(p.id::text || ':' || k.k || ':' || public.push_wanted(p.id, k.k)::text || ':' || coalesce(public.push_group(k.k), '-'), ',' order by p.id, k.k))
    from public.profiles p cross join kinds k $$;
create function pg_temp.trig_pol_fp() returns text language sql stable as $$
  select (select count(*) || '/' || md5(string_agg(tgrelid::regclass::text || pg_get_triggerdef(oid) || tgenabled::text, ',' order by tgrelid::regclass::text, tgname))
            from pg_trigger where not tgisinternal and tgrelid in (select oid from pg_class where relnamespace = 'public'::regnamespace))
    || '#' || (select count(*) || '/' || md5(string_agg(polrelid::regclass::text || polname || polcmd::text || coalesce(pg_get_expr(polqual, polrelid), '') || coalesce(pg_get_expr(polwithcheck, polrelid), ''), ',' order by polrelid::regclass::text, polname))
            from pg_policy where polrelid in (select oid from pg_class where relnamespace = 'public'::regnamespace) and polrelid::regclass::text <> 'user_champions') $$;
grant execute on all functions in schema pg_temp to anon, authenticated;
select pg_temp.fn_fp() as fn0, pg_temp.counts() as cnt0, pg_temp.push_fp() as push0, pg_temp.trig_pol_fp() as tp0 \gset

-- ===== 1. 모양·권한 =====
select t.ok('set_my_champion(text, boolean): jsonb · volatile · security definer · search_path 빈 값 · 인자 이름 · 설명',
  (select provolatile = 'v' and prosecdef and proconfig = array['search_path=""'] and prorettype = 'jsonb'::regtype
          and pg_get_function_arguments(oid) = 'p_champion text, p_selected boolean' and obj_description(oid, 'pg_proc') like '내 챔피언 등록·해제 (080)%'
     from pg_proc where oid = 'public.set_my_champion(text, boolean)'::regprocedure));
select t.ok('my_champions(): jsonb · stable · security definer · search_path 빈 값',
  (select provolatile = 's' and prosecdef and proconfig = array['search_path=""'] and prorettype = 'jsonb'::regtype and pg_get_function_arguments(oid) = ''
     from pg_proc where oid = 'public.my_champions()'::regprocedure));
select t.ok('my_champion_builds(text, integer): jsonb · stable · security definer · 기본값 null·1',
  (select provolatile = 's' and prosecdef and proconfig = array['search_path=""'] and prorettype = 'jsonb'::regtype
          and pg_get_function_arguments(oid) = 'p_champion text DEFAULT NULL::text, p_page integer DEFAULT 1'
     from pg_proc where oid = 'public.my_champion_builds(text, integer)'::regprocedure));
select t.ok('같은 이름의 다른 함수 없음 (세 함수 각각 하나)', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname in ('set_my_champion', 'my_champions', 'my_champion_builds')) = 3);
select t.ok('세 함수 모두 로그인(authenticated)만 실행, 비로그인(anon)·public 불가', (
  select bool_and(has_function_privilege('authenticated', o, 'execute') and not has_function_privilege('anon', o, 'execute')
                  and not exists (select 1 from pg_proc p, unnest(p.proacl) a where p.oid = o and a::text like '=%'))
    from unnest(array['public.set_my_champion(text, boolean)'::regprocedure, 'public.my_champions()'::regprocedure,
                      'public.my_champion_builds(text, integer)'::regprocedure]) o));
select t.ok('user_champions: RLS 켬 · 기본 키 (user_id, champion) · user_id → profiles on delete cascade',
  (select relrowsecurity from pg_class where oid = 'public.user_champions'::regclass)
  and (select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'public.user_champions'::regclass and contype = 'p') = 'PRIMARY KEY (user_id, champion)'
  and (select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'public.user_champions'::regclass and contype = 'f')
      = 'FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE');
select t.ok('user_champions 권한: 로그인은 읽기만(본인 줄 정책 하나), 넣기·고치기·지우기 불가, 비로그인 아무것도 없음',
  has_table_privilege('authenticated', 'public.user_champions', 'select')
  and not has_table_privilege('authenticated', 'public.user_champions', 'insert') and not has_table_privilege('authenticated', 'public.user_champions', 'update')
  and not has_table_privilege('authenticated', 'public.user_champions', 'delete')
  and not has_table_privilege('anon', 'public.user_champions', 'select') and not has_table_privilege('anon', 'public.user_champions', 'insert')
  and (select count(*) = 1 and bool_and(polcmd = 'r') from pg_policy where polrelid = 'public.user_champions'::regclass));
select t.ok('champion_catalog: RLS 켬, 정책 없음, 로그인·비로그인 권한 없음, 챔피언 173개(아리·퀸·오공 포함)',
  (select relrowsecurity from pg_class where oid = 'public.champion_catalog'::regclass)
  and not exists (select 1 from pg_policy where polrelid = 'public.champion_catalog'::regclass)
  and not has_table_privilege('authenticated', 'public.champion_catalog', 'select') and not has_table_privilege('anon', 'public.champion_catalog', 'select')
  and (select count(*) from public.champion_catalog) = 173
  and (select count(*) from public.champion_catalog where champion_id in ('Ahri', 'Quinn', 'MonkeyKing', 'Darius')) = 4);
select t.ok('함수 수: 쓰기 104 / 첫 줄 검사 31 / 허용 목록 73 / 읽기 69, set_my_champion은 검사 쪽이고 허용 목록에 없음 (' || pg_temp.counts() || ')',
  pg_temp.counts() like '104/31/73/69/%'
  and (select prosrc ~ '^\s*declare\s*\n\s*_can_write constant boolean := public\.assert_can_write\(\);' from pg_proc where oid = 'public.set_my_champion(text, boolean)'::regprocedure)
  and not exists (select 1 from public.restriction_exemptions where name like '%champion%'));
set role anon;
reset request.jwt.claim.sub;
select t.fails('비로그인: set_my_champion 실행 권한 없음', $$select public.set_my_champion('Ahri', true)$$, 'permission denied');
select t.fails('비로그인: my_champions 실행 권한 없음', 'select public.my_champions()', 'permission denied');
select t.fails('비로그인: my_champion_builds 실행 권한 없음', 'select public.my_champion_builds()', 'permission denied');
select t.fails('비로그인: 표도 못 읽음', 'select * from public.user_champions', 'permission denied');
reset role;
set role authenticated;
reset request.jwt.claim.sub;
select t.fails('로그인 표시(sub)가 없으면 등록 거부', $$select public.set_my_champion('Ahri', true)$$, '로그인해 주세요');
select t.fails('로그인 표시(sub)가 없으면 목록 거부', 'select public.my_champions()', '로그인해 주세요');
select t.fails('로그인 표시(sub)가 없으면 빌드 모음 거부', 'select public.my_champion_builds()', '로그인해 주세요');
set request.jwt.claim.sub = :'A';
select t.fails('로그인해도 표에 직접 넣기 불가', $$insert into public.user_champions (user_id, champion) values ('00000000-0000-0000-0000-0000000005a1', 'Ahri')$$, 'permission denied');
reset role;

-- ===== 2. 등록·해제 =====
set role authenticated;
select t.ok('처음 등록: selected true · count 1 · limit 10', pg_temp.setc(:'A', 'Ahri') = '{"count": 1, "limit": 10, "champion": "Ahri", "selected": true}'::jsonb);
reset role;
select created_at as ahri_at from public.user_champions where user_id = :'A' and champion = 'Ahri' \gset
set role authenticated;
select t.ok('이미 등록한 챔피언을 또 등록: 오류 없이 같은 결과 (개수·등록 시각 그대로)',
  pg_temp.setc(:'A', 'Ahri') = '{"count": 1, "limit": 10, "champion": "Ahri", "selected": true}'::jsonb);
reset role;
select t.ok('중복 등록 뒤에도 줄 하나 · 시각 그대로', (select count(*) = 1 and min(created_at) = :'ahri_at'::timestamptz from public.user_champions where user_id = :'A'));
set role authenticated;
select t.ok('없는 챔피언(Foo)은 22023 「없는 챔피언입니다」', pg_temp.err(:'A', 'Foo') = '22023:없는 챔피언입니다. 다시 골라 주세요.');
select t.ok('형식이 틀린 값(빈 값·숫자·한글·null·31자)도 거부', pg_temp.err(:'A', '') like '22023:%' and pg_temp.err(:'A', 'Ahri1') like '22023:%'
  and pg_temp.err(:'A', '아리') like '22023:%' and pg_temp.err(:'A', null) like '22023:%' and pg_temp.err(:'A', repeat('a', 31)) like '22023:%');
select t.ok('대소문자가 다른 id(ahri)도 없는 챔피언', pg_temp.err(:'A', 'ahri') like '22023:%');
select t.ok('선택 여부 null 거부', pg_temp.err(:'A', 'Ahri', null) like '22023:%');
select t.ok('목록에 없어도 공개 상대법의 내 챔피언 쪽에 쓰인 id(Zzznew)는 받음', (pg_temp.setc(:'A', 'Zzznew') ->> 'count')::int = 2);
select t.ok('등록하지 않은 챔피언 해제: 오류 없이 그대로', pg_temp.setc(:'A', 'Garen', false) = '{"count": 2, "limit": 10, "champion": "Garen", "selected": false}'::jsonb);
select t.ok('해제', (pg_temp.setc(:'A', 'Zzznew', false) ->> 'count')::int = 1 and pg_temp.mine(:'A') = 'Ahri');
-- 10개까지
select pg_temp.setc(:'A', c) from unnest(array['Quinn', 'Darius', 'Garen', 'Zed', 'Teemo', 'Jax', 'Fiora', 'Riven', 'Irelia']) c;
select t.ok('10개 등록 (최근 등록순)', pg_temp.mine(:'A') = 'Irelia,Riven,Fiora,Jax,Teemo,Zed,Garen,Darius,Quinn,Ahri');
select t.ok('11개째는 TL413 「최대 10개까지 선택할 수 있습니다. 하나를 해제한 뒤 선택해 주세요.」',
  pg_temp.err(:'A', 'Yasuo') = 'TL413:최대 10개까지 선택할 수 있습니다. 하나를 해제한 뒤 선택해 주세요.');
select t.ok('10개일 때도 이미 등록한 챔피언을 또 누르면 오류 없음 (한도에 걸리지 않음)', (pg_temp.setc(:'A', 'Jax') ->> 'count')::int = 10);
select t.ok('10개일 때 없는 챔피언은 한도보다 「없는 챔피언」이 먼저', pg_temp.err(:'A', 'Foo') like '22023:%');
select t.ok('하나 해제하면 다시 선택 가능, 새로 고른 것이 맨 앞', (pg_temp.setc(:'A', 'Irelia', false) ->> 'count')::int = 9
  and (pg_temp.setc(:'A', 'Yasuo') ->> 'count')::int = 10 and pg_temp.mine(:'A') like 'Yasuo,Riven,%');
reset role;
select t.ok('한도는 서버가 지킴: A의 줄 10개', (select count(*) from public.user_champions where user_id = :'A') = 10);
set role authenticated;
select t.ok('비회원(게스트)도 등록·목록·빌드 모음 가능', (pg_temp.setc(:'GU', 'Quinn') ->> 'count')::int = 1 and pg_temp.mine(:'GU') = 'Quinn'
  and (pg_temp.blds(:'GU') ->> 'total')::int = 3);
select t.ok('닉네임 없는 회원도 등록 가능 (운영자 계정도 자기 것만)', (pg_temp.setc(:'OP', 'Ahri') ->> 'count')::int = 1);
reset role;
insert into public.user_restrictions (user_id, reason, days, ends_at, created_by) values (:'R', '검사', 7, now() + interval '7 days', :'OP');
insert into public.user_champions (user_id, champion) values (:'R', 'Quinn');
set role authenticated;
select t.ok('활동 제한 중: 등록·해제 모두 TL423 (첫 줄 검사)', pg_temp.err(:'R', 'Ahri') like 'TL423:활동이 제한된 상태입니다.%'
  and pg_temp.err(:'R', 'Quinn', false) like 'TL423:%' and pg_temp.err(:'R', null, null) like 'TL423:%');
select t.ok('활동 제한 중에도 읽기는 됨', pg_temp.mine(:'R') = 'Quinn' and (pg_temp.blds(:'R') ->> 'total')::int = 3);
reset role;

-- ===== 3. 다른 사람의 등록이 보이지 않음 =====
set role authenticated;
select t.ok('B: 등록 없음 → 빈 목록 · 빌드 0개 (A의 등록이 섞이지 않음)', pg_temp.mine(:'B') is null
  and pg_temp.blds(:'B') = '{"page": 1, "size": 20, "items": [], "total": 0, "blocked": 0}'::jsonb);
set request.jwt.claim.sub = :'B';
select t.ok('B: my_champions 그대로 부르면 { limit 10, items [] }', public.my_champions() = '{"limit": 10, "items": []}'::jsonb);
select t.ok('B가 표를 직접 읽어도 0줄 (본인 줄만)', (select count(*) from public.user_champions) = 0);
set request.jwt.claim.sub = :'A';
select t.ok('A가 표를 직접 읽으면 자기 10줄만', (select count(*) from public.user_champions) = 10
  and not exists (select 1 from public.user_champions where user_id <> :'A'::uuid));
select t.ok('B가 A의 챔피언으로 좁혀도(Yasuo·Ahri) 빈 목록', pg_temp.blds(:'B', 'Ahri') ->> 'total' = '0');
select t.ok('함수 인자에 다른 사람 id를 받는 자리가 없음', (select pg_get_function_arguments(oid) from pg_proc where oid = 'public.my_champions()'::regprocedure) = ''
  and (select pg_get_function_arguments(oid) not like '%uuid%' from pg_proc where oid = 'public.my_champion_builds(text, integer)'::regprocedure));
reset role;
select t.ok('user_champions를 읽는 함수는 080의 세 함수뿐 (다른 경로 없음)', (
  select string_agg(p.proname, ',' order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosrc like '%user_champions%') = 'my_champion_builds,my_champions,set_my_champion'
  and not exists (select 1 from pg_views where definition like '%user_champions%'));

-- ===== 4. 빌드 모음 =====
set role authenticated;
select t.ok('B: 아리 등록', (pg_temp.setc(:'B', 'Ahri') ->> 'count')::int = 1);
select pg_temp.blds(:'B') as b1, pg_temp.blds(:'B', null, 2) as b2, pg_temp.blds(:'A') as a1 \gset
select t.ok('B(아리만): 공개 25개, 1쪽 20 · 2쪽 5 · 3쪽 0, size 20, page 그대로, 차단 0',
  (:'b1'::jsonb ->> 'total')::int = 25 and jsonb_array_length(:'b1'::jsonb -> 'items') = 20 and jsonb_array_length(:'b2'::jsonb -> 'items') = 5
  and jsonb_array_length(pg_temp.blds(:'B', null, 3) -> 'items') = 0 and (:'b1'::jsonb ->> 'size')::int = 20 and (:'b2'::jsonb ->> 'page')::int = 2
  and (:'b1'::jsonb ->> 'blocked')::int = 0);
select t.ok('숨김·대기·거절 빌드, 숨긴 상대법 밑 빌드는 나오지 않음', not exists (
  select 1 from public.builds b join public.counters c on c.id = b.counter_id
   where (b.status <> 'approved' or c.status <> 'approved') and b.id::text = any (string_to_array(pg_temp.all_ids(:'B'), ','))));
select t.ok('순서: /builds 추천순과 같음 (장인 → 추천 → 최신 → id), 쪽을 이어도 겹침·빠짐 없음',
  pg_temp.all_ids(:'B') = pg_temp.want(:'B') and pg_temp.ids(:'b1') || ',' || pg_temp.ids(:'b2') = pg_temp.want(:'B'));
select t.ok('장인 빌드 3개가 맨 앞 (추천이 적어도)', (select bool_and(e -> 'author' ->> 'influencer' = 'pro')
  from jsonb_array_elements(:'b1'::jsonb -> 'items') with ordinality x(e, o) where o <= 3)
  and (select bool_and(e -> 'author' ->> 'influencer' is null) from jsonb_array_elements(:'b1'::jsonb -> 'items') with ordinality x(e, o) where o > 3));
select t.ok('A: 차단한 사람(BL) 빌드 2개 빼고 total, blocked = 2', (:'a1'::jsonb ->> 'blocked')::int = 2
  and (:'a1'::jsonb ->> 'total')::int = 23 + 3 and pg_temp.all_ids(:'A') = pg_temp.want(:'A')
  and position((select string_agg(id::text, ',') from public.builds where author_id = :'BL') in pg_temp.all_ids(:'A')) = 0);
select t.ok('챔피언 하나로 좁히기: 퀸 3개(탈퇴자 2 + 가렌 상대 1), 아리 23개', (pg_temp.blds(:'A', 'Quinn') ->> 'total')::int = 3
  and pg_temp.all_ids(:'A', 'Quinn') = pg_temp.want(:'A', 'Quinn') and (pg_temp.blds(:'A', 'Ahri') ->> 'total')::int = 23
  and (select bool_and(e ->> 'mine' = 'Quinn') from jsonb_array_elements(pg_temp.blds(:'A', 'Quinn') -> 'items') e));
select t.ok('등록하지 않은 챔피언으로 좁히면 빈 목록 (B는 퀸 미등록)', (pg_temp.blds(:'B', 'Quinn') ->> 'total')::int = 0
  and jsonb_array_length(pg_temp.blds(:'B', 'Quinn') -> 'items') = 0);
select t.ok('쪽 번호 0·음수·null은 1쪽', pg_temp.ids(pg_temp.blds(:'B', null, 0)) = pg_temp.ids(:'b1') and pg_temp.ids(pg_temp.blds(:'B', null, -2)) = pg_temp.ids(:'b1')
  and pg_temp.ids(pg_temp.blds(:'B', null, null)) = pg_temp.ids(:'b1'));
select t.ok('칸: id·name·seq·max_skill·up·created_at·author_id·author·target·mine뿐, 바깥은 total·blocked·page·size·items',
  (select string_agg(distinct k, ',' order by k) from jsonb_array_elements(:'a1'::jsonb -> 'items') e, jsonb_object_keys(e) k)
    = 'author,author_id,created_at,id,max_skill,mine,name,seq,target,up'
  and (select string_agg(k, ',' order by k) from jsonb_object_keys(:'a1'::jsonb) k) = 'blocked,items,page,size,total');
select t.ok('author 칸은 influencer·nickname·photo_path뿐 (이메일·역할·레벨 없음), 값은 profiles와 같음',
  (select string_agg(distinct k, ',' order by k) from jsonb_array_elements(:'a1'::jsonb -> 'items') e, jsonb_object_keys(e -> 'author') k
    where jsonb_typeof(e -> 'author') = 'object') = 'influencer,nickname,photo_path'
  and not exists (select 1 from jsonb_array_elements(:'a1'::jsonb -> 'items') e join public.profiles p on p.id = (e ->> 'author_id')::uuid
                   where e -> 'author' ->> 'nickname' is distinct from p.nickname or e -> 'author' ->> 'photo_path' is distinct from p.photo_path)
  and position('@' in pg_temp.blds(:'A', null, 1)::text || pg_temp.blds(:'A', null, 2)::text) = 0);
select t.ok('탈퇴한 작성자(fixtures 퀸 빌드): author_id·author 모두 null', (select count(*) from jsonb_array_elements(pg_temp.blds(:'A', 'Quinn') -> 'items') e
  where e -> 'author' = 'null'::jsonb and e -> 'author_id' = 'null'::jsonb) = 2);
select t.ok('값: 추천 수 up = up_count, target·mine = 상대법', not exists (
  select 1 from jsonb_array_elements((:'b1'::jsonb -> 'items') || (:'b2'::jsonb -> 'items')) e join public.builds b on b.id = (e ->> 'id')::bigint
    join public.counters c on c.id = b.counter_id
   where (e ->> 'up')::int <> b.up_count or e ->> 'target' <> c.target_champion or e ->> 'mine' <> c.counter_champion));
reset role;
update public.builds set status = 'hidden', hide_reason = '검사', hidden_at = now() where id = split_part(pg_temp.ids(:'b1'::jsonb), ',', 1)::bigint;
set role authenticated;
select t.ok('공개 빌드를 숨기면 바로 빠지고 total 24', (pg_temp.blds(:'B') ->> 'total')::int = 24 and pg_temp.all_ids(:'B') = pg_temp.want(:'B'));
reset role;
update public.builds set status = 'approved', hide_reason = null, hidden_at = null where id = split_part(pg_temp.ids(:'b1'::jsonb), ',', 1)::bigint;

-- ===== 5. 탈퇴·비회원 정리: cascade =====
select pg_temp.data_fp() as d0 \gset
set role authenticated;
select pg_temp.mine(:'A'), pg_temp.blds(:'A'), pg_temp.blds(:'B', 'Ahri', 2);
reset role;
select t.ok('불러도 데이터는 그대로 (등록·빌드·profiles·알림)', pg_temp.data_fp() = :'d0');
begin;
delete from auth.users where id = :'A';
select t.ok('회원 탈퇴(auth.users 삭제 → profiles 삭제): A의 등록 10줄이 함께 지워지고 다른 사람 것은 그대로',
  not exists (select 1 from public.user_champions where user_id = :'A') and (select count(*) from public.user_champions where user_id = :'B') = 1);
rollback;
begin;
update public.profiles set last_seen_at = now() - interval '400 days' where id = :'GU';
select public.cleanup_guest_accounts() as gone \gset
select t.ok('비회원 정리(cleanup_guest_accounts, 본문 그대로): 등록이 함께 지워짐', :'gone'::int >= 1 and not exists (select 1 from public.user_champions where user_id = :'GU'));
rollback;

-- ===== 6. 되돌리기 블록 (080 파일 그대로) → 079 상태 확인 뒤 다시 080으로 (트랜잭션 되돌림) =====
begin;
drop function public.my_champion_builds(text, integer);
drop function public.my_champions();
drop function public.set_my_champion(text, boolean);
drop table public.user_champions;
drop table public.champion_catalog;
select t.ok('되돌리기: 세 함수·두 표 없음 · 다른 함수 지문 그대로 · 쓰기 103/30/73 · 읽기 67 · 허용 목록·푸시 판정·트리거·정책 그대로',
  to_regclass('public.user_champions') is null and to_regclass('public.champion_catalog') is null
  and to_regprocedure('public.set_my_champion(text, boolean)') is null and to_regprocedure('public.my_champions()') is null
  and to_regprocedure('public.my_champion_builds(text, integer)') is null
  and pg_temp.fn_fp() = :'fn0' and pg_temp.counts() like '103/30/73/67/%' and split_part(pg_temp.counts(), '/', 5) = split_part(:'cnt0', '/', 5)
  and pg_temp.push_fp() = :'push0' and pg_temp.trig_pol_fp() = :'tp0');
rollback;
select t.ok('080 다시 (되돌림 취소): 지문·수 그대로', pg_temp.fn_fp() = :'fn0' and pg_temp.counts() = :'cnt0' and pg_temp.push_fp() = :'push0');
select t.fails('080을 한 번 더 실행하면 멈춤 (080 파일의 실행 전 확인 그대로)', $q$do $chk$
begin
  if to_regclass('public.user_champions') is not null or to_regclass('public.champion_catalog') is not null
     or to_regprocedure('public.set_my_champion(text, boolean)') is not null then
    raise exception '내 챔피언 표·함수가 이미 있습니다(080을 이미 실행함). 실행을 멈춥니다.';
  end if;
  if to_regprocedure('public.assert_can_write()') is null or to_regclass('public.user_blocks') is null then
    raise exception '061·068이 아직 실행되지 않았습니다.';
  end if;
end $chk$$q$, '이미 있습니다');
