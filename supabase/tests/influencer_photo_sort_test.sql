-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것. (운영 DB 확인은 scripts/check_influencer_photo_sort_after.sql)
-- 078 장인 목록 정렬에 프로필 사진 유무: 사진 있는 장인 먼저(두 정렬 모두) → 그 안팎은 070 정렬 그대로(팔로워 → 최근 활동 → 닉네임 → id),
--   빈 경로는 제약으로 들어올 수 없음, 사진 삭제(null)면 뒤로, 검색해도 같은 규칙, 쪽 크기 1~7로 이어도 겹침·빠짐 없음(60명 > 50),
--   새 순서 = 옛 순서에서 사진 있는 장인만 순서대로 앞으로(웹 photoFirst와 같은 결과), 모양·권한·설명 그대로, 다른 함수·103/30/73·66·허용 목록·푸시 판정 그대로,
--   되돌리기 블록(078 파일 그대로)으로 070 본문이 되살아나고 078 본문(파일 그대로)을 다시 실행하면 같은 지문
\set ON_ERROR_STOP 1
\set QUIET 1
-- 장인 60명 (inf01~inf60): 3의 배수만 사진, 팔로워 수는 (번호×7) mod 11, 공개 빌드는 5의 배수만(최근 활동 차이)
insert into auth.users (id, email) select ('00000000-0000-0000-0000-0000000001' || lpad(i::text, 2, '0'))::uuid, 'i' || i || '@x.com' from generate_series(1, 60) i;
update public.profiles set nickname = 'inf' || right(id::text, 2), influencer = 'creator', influencer_at = now()
 where id::text like '00000000-0000-0000-0000-0000000001%';
update public.profiles set photo_path = id::text || '/a.jpg', photo_updated_at = now()
 where id::text like '00000000-0000-0000-0000-0000000001%' and right(id::text, 2)::int % 3 = 0;
insert into public.influencer_follows (follower_id, influencer_id)
select f.id, i.id from public.profiles i join public.profiles f on f.id::text like '00000000-0000-0000-0000-0000000001%' and f.id <> i.id
 where i.id::text like '00000000-0000-0000-0000-0000000001%' and right(f.id::text, 2)::int <= (right(i.id::text, 2)::int * 7) % 11;
begin;
alter table public.builds disable trigger builds_check_new;
create temp table src as select * from public.builds where counter_id = (select id from public.counters where counter_champion = 'Quinn') order by id limit 1;
insert into public.builds (counter_id, author_id, runes, summoner_spells, starting_items, core_items, max_skill, patch, status, updated_at)
select s.counter_id, p.id, s.runes, s.summoner_spells, s.starting_items, s.core_items, s.max_skill, s.patch, 'approved', now() - (right(p.id::text, 2)::int || ' hours')::interval
  from src s, public.profiles p where p.id::text like '00000000-0000-0000-0000-0000000001%' and right(p.id::text, 2)::int % 5 = 0;
set constraints all immediate;
alter table public.builds enable trigger builds_check_new;
commit;

create function pg_temp.dir(q text, s text, pg integer, sz integer) returns jsonb language sql stable as $$ select public.influencer_directory(q, s, pg, sz) $$;
-- 쪽 크기 sz로 끝까지 이은 순서 (id 목록)
create function pg_temp.walk(s text, sz integer, q text default null) returns text[] language sql stable as $$
  select coalesce(array_agg(e.x ->> 'id' order by pg.n, e.o), '{}')
    from generate_series(1, greatest(1, ceil((public.influencer_directory(q, s, 1, 1) ->> 'total')::numeric / sz)::integer)) pg(n)
   cross join lateral jsonb_array_elements(public.influencer_directory(q, s, pg.n, sz) -> 'items') with ordinality e(x, o) $$;
create function pg_temp.photo(pid text) returns boolean language sql stable as $$
  select photo_path is not null and btrim(photo_path) <> '' from public.profiles where id = pid::uuid $$;
create function pg_temp.fol(pid text) returns bigint language sql stable as $$
  select count(*) from public.influencer_follows where influencer_id = pid::uuid $$;
-- 사진 있는 것만 순서대로 앞으로 (웹 photoFirst와 같은 규칙)
create function pg_temp.photo_first(a text[]) returns text[] language sql stable as $$
  select coalesce(array_agg(x order by not pg_temp.photo(x), o), '{}') from unnest(a) with ordinality u(x, o) $$;
-- 사진 없는 장인 뒤에 나온 사진 있는 장인 수
create function pg_temp.late_photo(a text[]) returns bigint language sql stable as $$
  select count(*) from unnest(a) with ordinality u(x, o)
   where pg_temp.photo(x) and exists (select 1 from unnest(a) with ordinality v(y, p) where p < o and not pg_temp.photo(y)) $$;
create function pg_temp.fn_fp() returns text language sql stable as $$
  select count(*) || '/' || md5(string_agg(p.proname || '(' || oidvectortypes(p.proargtypes) || ')' || pg_get_function_result(p.oid) || p.provolatile::text
           || replace(p.prosrc, E'\r', '') || p.prosecdef::text || coalesce(array_to_string(p.proconfig, ','), '') || coalesce(array_to_string(p.proacl, ','), ''),
           '|' order by p.proname, oidvectortypes(p.proargtypes)))
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind in ('f', 'p') and p.proname <> 'influencer_directory' $$;
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
create function pg_temp.attrs() returns text language sql stable as $$
  select pg_get_function_arguments(oid) || '|' || pg_get_function_result(oid) || '|' || provolatile::text || '|' || prosecdef::text || '|' || array_to_string(proconfig, ',')
         || '|' || array_to_string(proacl, ',') || '|' || pg_get_userbyid(proowner) || '|' || obj_description(oid, 'pg_proc')
    from pg_proc where oid = 'public.influencer_directory(text, text, integer, integer)'::regprocedure $$;
create function pg_temp.body_fp() returns text language sql stable as $$
  select md5(replace(prosrc, E'\r', '')) from pg_proc where oid = 'public.influencer_directory(text, text, integer, integer)'::regprocedure $$;
grant execute on all functions in schema pg_temp to anon, authenticated;

select t.ok('078 본문(ef21f41e…), 모양 그대로: jsonb · stable · security definer · search_path · anon·authenticated 실행 · 070 설명',
  pg_temp.body_fp() = 'ef21f41e761c3785defccdf6a8bcbf42'
  and pg_temp.attrs() like 'p_query text DEFAULT NULL::text, p_sort text DEFAULT ''followers''::text, p_page integer DEFAULT 1, p_size integer DEFAULT 10|jsonb|s|true|search_path=""|%anon=X/postgres%authenticated=X/postgres|postgres|공개 장인 목록 (070)%'
  and (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'influencer_directory') = 1);
select t.ok('장인 60명(사진 20명) — 50명을 넘어 웹은 서버 쪽 나누기', (pg_temp.dir(null, null, 1, 1) ->> 'total')::int = 60
  and (select count(*) from unnest(pg_temp.walk('followers', 50)) x where pg_temp.photo(x)) = 20);
select pg_temp.walk('followers', 50) as f78, pg_temp.walk('recent', 50) as r78 \gset
select pg_temp.fn_fp() as fn0, pg_temp.counts() as cnt0, pg_temp.push_fp() as push0, pg_temp.attrs() as attrs0 \gset

-- ===== 1. 정렬 =====
select t.ok('팔로워 순: 사진 있는 장인 20명이 모두 앞', pg_temp.late_photo(:'f78') = 0
  and (select bool_and(pg_temp.photo(x)) from unnest((:'f78'::text[])[1:20]) x));
select t.ok('최신순: 사진 있는 장인이 모두 앞', pg_temp.late_photo(:'r78') = 0);
select t.ok('팔로워 순: 사진 있음·없음 묶음 안에서 팔로워 많은 순',
  not exists (select 1 from unnest(:'f78'::text[]) with ordinality u(x, o) join unnest(:'f78'::text[]) with ordinality v(y, p) on p = o + 1
               where pg_temp.photo(x) = pg_temp.photo(y) and pg_temp.fol(y) > pg_temp.fol(x)));
select t.ok('최신순: 묶음 안에서 최근 활동 순(활동 없는 장인은 묶음 끝)',
  not exists (select 1 from unnest(:'r78'::text[]) with ordinality u(x, o) join unnest(:'r78'::text[]) with ordinality v(y, p) on p = o + 1
               cross join lateral (select (e ->> 'last_activity_at')::timestamptz a from jsonb_array_elements(pg_temp.dir(null, 'recent', 1, 50) -> 'items' || pg_temp.dir(null, 'recent', 2, 50) -> 'items') e where e ->> 'id' = x) ax
               cross join lateral (select (e ->> 'last_activity_at')::timestamptz a from jsonb_array_elements(pg_temp.dir(null, 'recent', 1, 50) -> 'items' || pg_temp.dir(null, 'recent', 2, 50) -> 'items') e where e ->> 'id' = y) ay
               where pg_temp.photo(x) = pg_temp.photo(y) and ((ax.a is null and ay.a is not null) or ay.a > ax.a)));
select t.ok('같은 사진·팔로워·활동이면 닉네임 순 (팔로워 순 첫 묶음의 동점)',
  not exists (select 1 from unnest(:'f78'::text[]) with ordinality u(x, o) join unnest(:'f78'::text[]) with ordinality v(y, p) on p = o + 1
               join public.profiles px on px.id = x::uuid join public.profiles py on py.id = y::uuid
               where pg_temp.photo(x) = pg_temp.photo(y) and pg_temp.fol(x) = pg_temp.fol(y)
                 and not exists (select 1 from public.builds b where b.author_id in (px.id, py.id) and b.status = 'approved')
                 and py.nickname < px.nickname));
select t.ok('검색해도 같은 규칙: "inf0" (9명) 사진 먼저', pg_temp.late_photo(pg_temp.walk('followers', 50, 'inf0')) = 0
  and cardinality(pg_temp.walk('followers', 50, 'inf0')) = 9);

-- ===== 2. 쪽 넘김 =====
select t.ok('쪽 크기 1·2·3·7·10으로 이어도 50명씩과 같은 순서, 겹침·빠짐 없음 (두 정렬)', (
  select bool_and(pg_temp.walk(s, z) = case s when 'followers' then :'f78'::text[] else :'r78'::text[] end
                  and cardinality(pg_temp.walk(s, z)) = 60
                  and (select count(distinct x) from unnest(pg_temp.walk(s, z)) x) = 60)
    from (values ('followers'), ('recent')) a(s) cross join (values (1), (2), (3), (7), (10)) b(z)));

-- ===== 3. 사진 판정 =====
select t.fails('빈 경로는 들어올 수 없음 (062 profiles_photo_path_shape)',
  $$update public.profiles set photo_path = '', photo_updated_at = now() where id = '00000000-0000-0000-0000-000000000101'$$, 'profiles_photo_path_shape');
begin;
update public.profiles set photo_path = null, photo_updated_at = null where id = '00000000-0000-0000-0000-000000000103';
select t.ok('사진을 지우면(null) 사진 없는 묶음으로', not ('00000000-0000-0000-0000-000000000103' = any ((pg_temp.walk('followers', 50))[1:19]))
  and pg_temp.late_photo(pg_temp.walk('followers', 50)) = 0);
rollback;

-- ===== 4. 바꾸지 않은 것 =====
select t.ok('다른 함수 지문·104/31/73/69(079·080 포함)·허용 목록·푸시 판정 그대로 (' || pg_temp.counts() || ')',
  pg_temp.counts() like '104/31/73/69/%');  -- 읽기 함수 69 = 078 때 66 + 079 my_following_cards + 080 2개

-- ===== 5. 되돌리기 블록 (078 파일 그대로) → 070 =====
begin;
create or replace function public.influencer_directory(p_query text default null, p_sort text default 'followers', p_page integer default 1, p_size integer default 10)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  q text := btrim(coalesce(p_query, ''));
  srt text := case when p_sort = 'recent' then 'recent' else 'followers' end;
  pg integer := greatest(coalesce(p_page, 1), 1);
  sz integer := least(greatest(coalesce(p_size, 10), 1), 50);
  pat text;
  k text;
  kpat text;
begin
  if char_length(q) > 20 then
    raise exception '검색어는 20자 이하로 적어 주세요.' using errcode = '22023';
  end if;
  if q <> '' then
    pat := '%' || replace(replace(replace(lower(q), '\', '\\'), '%', '\%'), '_', '\_') || '%';
    k := public.nickname_key(q);
    if coalesce(k, '') <> '' then
      kpat := '%' || replace(replace(replace(k, '\', '\\'), '%', '\%'), '_', '\_') || '%';
    end if;
  end if;
  return (
    with m as (
      select p.id, p.nickname, p.influencer, p.photo_path,
             (select count(*) from public.influencer_follows f where f.influencer_id = p.id) as followers,
             b.n as builds, b.last_at
        from public.profiles p
        cross join lateral (
          select count(*) as n, max(x.updated_at) as last_at
            from public.builds x join public.counters c on c.id = x.counter_id
           where x.author_id = p.id and x.status = 'approved' and c.status = 'approved'
        ) b
       where p.influencer is not null and p.nickname is not null
         and (q = '' or lower(p.nickname) like pat escape '\' or (kpat is not null and p.nickname_key like kpat escape '\'))
    ), o as (
      select m.*, row_number() over (order by
               case when srt = 'followers' then m.followers end desc nulls last,
               m.last_at desc nulls last,
               m.followers desc,
               m.nickname, m.id) as rn
        from m
    )
    select jsonb_build_object(
      'total', (select count(*) from m),
      'page', pg, 'size', sz, 'sort', srt,
      'items', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', o.id, 'nickname', o.nickname, 'influencer', o.influencer, 'photo_path', o.photo_path,
                 'follower_count', o.followers, 'build_count', o.builds, 'last_activity_at', o.last_at)
               order by o.rn)
          from o where o.rn > (pg - 1) * sz and o.rn <= pg * sz
      ), '[]'::jsonb))
  );
end;
$$;
commit;
select t.ok('되돌리기: 070 본문(7955c630…), 모양·권한·설명 그대로, 다른 함수 그대로',
  pg_temp.body_fp() = '7955c630a2b304baf7628375ca3f3940' and pg_temp.attrs() = :'attrs0' and pg_temp.fn_fp() = :'fn0');
select pg_temp.walk('followers', 50) as f70, pg_temp.walk('recent', 50) as r70 \gset
select t.ok('070 순서는 사진을 보지 않음 (사진 있는 장인이 뒤에도 있음)', pg_temp.late_photo(:'f70') > 0);
select t.ok('078 순서 = 070 순서에서 사진 있는 장인만 순서대로 앞으로 (웹 photoFirst와 같은 결과, 두 정렬)',
  pg_temp.photo_first(:'f70') = :'f78'::text[] and pg_temp.photo_first(:'r70') = :'r78'::text[]);

-- ===== 6. 078 본문 다시 (파일 그대로) =====
begin;

do $chk$
begin
  if to_regprocedure('public.influencer_directory(text, text, integer, integer)') is null then
    raise exception '070이 아직 실행되지 않았습니다.';
  end if;
  if md5(replace((select prosrc from pg_proc where oid = 'public.influencer_directory(text, text, integer, integer)'::regprocedure), E'\r', ''))
     <> '7955c630a2b304baf7628375ca3f3940' then
    raise exception 'influencer_directory 본문이 070과 다릅니다(이미 078을 실행했거나 다른 변경이 있음). 실행을 멈춥니다. check_influencer_photo_sort_before.sql 1번을 알려 주세요.';
  end if;
end $chk$;

create or replace function public.influencer_directory(p_query text default null, p_sort text default 'followers', p_page integer default 1, p_size integer default 10)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  q text := btrim(coalesce(p_query, ''));
  srt text := case when p_sort = 'recent' then 'recent' else 'followers' end;
  pg integer := greatest(coalesce(p_page, 1), 1);
  sz integer := least(greatest(coalesce(p_size, 10), 1), 50);
  pat text;
  k text;
  kpat text;
begin
  if char_length(q) > 20 then
    raise exception '검색어는 20자 이하로 적어 주세요.' using errcode = '22023';
  end if;
  if q <> '' then
    pat := '%' || replace(replace(replace(lower(q), '\', '\\'), '%', '\%'), '_', '\_') || '%';
    k := public.nickname_key(q);
    if coalesce(k, '') <> '' then
      kpat := '%' || replace(replace(replace(k, '\', '\\'), '%', '\%'), '_', '\_') || '%';
    end if;
  end if;
  return (
    with m as (
      select p.id, p.nickname, p.influencer, p.photo_path,
             (select count(*) from public.influencer_follows f where f.influencer_id = p.id) as followers,
             b.n as builds, b.last_at
        from public.profiles p
        cross join lateral (
          select count(*) as n, max(x.updated_at) as last_at
            from public.builds x join public.counters c on c.id = x.counter_id
           where x.author_id = p.id and x.status = 'approved' and c.status = 'approved'
        ) b
       where p.influencer is not null and p.nickname is not null
         and (q = '' or lower(p.nickname) like pat escape '\' or (kpat is not null and p.nickname_key like kpat escape '\'))
    ), o as (
      select m.*, row_number() over (order by
               (m.photo_path is not null and btrim(m.photo_path) <> '') desc,  -- 078: 프로필 사진 있는 장인 먼저
               case when srt = 'followers' then m.followers end desc nulls last,
               m.last_at desc nulls last,
               m.followers desc,
               m.nickname, m.id) as rn
        from m
    )
    select jsonb_build_object(
      'total', (select count(*) from m),
      'page', pg, 'size', sz, 'sort', srt,
      'items', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', o.id, 'nickname', o.nickname, 'influencer', o.influencer, 'photo_path', o.photo_path,
                 'follower_count', o.followers, 'build_count', o.builds, 'last_activity_at', o.last_at)
               order by o.rn)
          from o where o.rn > (pg - 1) * sz and o.rn <= pg * sz
      ), '[]'::jsonb))
  );
end;
$$;
-- create or replace는 권한·설명·소유자를 그대로 둔다 (확인 스크립트 6번)

commit;
select t.ok('078 다시: 같은 지문·순서, 모양·다른 함수·수·푸시 판정 그대로',
  pg_temp.body_fp() = 'ef21f41e761c3785defccdf6a8bcbf42' and pg_temp.walk('followers', 50) = :'f78'::text[]
  and pg_temp.attrs() = :'attrs0' and pg_temp.fn_fp() = :'fn0' and pg_temp.counts() = :'cnt0' and pg_temp.push_fp() = :'push0');
select t.fails('078을 한 번 더 실행하면 멈춤 (078 파일의 실행 전 확인 그대로)', $q$do $chk$
begin
  if to_regprocedure('public.influencer_directory(text, text, integer, integer)') is null then
    raise exception '070이 아직 실행되지 않았습니다.';
  end if;
  if md5(replace((select prosrc from pg_proc where oid = 'public.influencer_directory(text, text, integer, integer)'::regprocedure), E'\r', ''))
     <> '7955c630a2b304baf7628375ca3f3940' then
    raise exception 'influencer_directory 본문이 070과 다릅니다(이미 078을 실행했거나 다른 변경이 있음). 실행을 멈춥니다. check_influencer_photo_sort_before.sql 1번을 알려 주세요.';
  end if;
end $chk$$q$, '070과 다릅니다');
