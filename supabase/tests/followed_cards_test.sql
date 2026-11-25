-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것. (운영 DB 확인은 scripts/check_followed_cards_after.sql)
-- 079 내가 팔로우한 장인 카드 my_following_cards: 모양·권한(로그인만, 비로그인·public 불가), 비회원·sub 없음 거부, 나의 팔로우만(남의 팔로우 안 보임),
--   my_following과 같은 순서·쪽(20개씩, 겹침·빠짐 없음), 돌려주는 칸(사진·유형·팔로워·공개 빌드 수뿐 - 이메일·가입일시·팔로우한 때 없음),
--   빼는 장인(정지 중 - 풀리면 다시, 인증 해제·탈퇴는 팔로우 자체가 지워짐), 데이터를 바꾸지 않음,
--   다른 함수(my_following 포함)·쓰기 함수 103/30/73·읽기 함수 67·허용 목록·푸시 판정 그대로, 되돌리기 블록·다시 실행(079 파일 그대로)
\set ON_ERROR_STOP 1
\set QUIET 1
\set A  '00000000-0000-0000-0000-0000000003a1'
\set B  '00000000-0000-0000-0000-0000000003a2'
\set GU '00000000-0000-0000-0000-0000000003a3'
\set OP '00000000-0000-0000-0000-0000000003a4'
-- 팬 A·B, 비회원 GU, 운영자 OP, 장인 inf01~inf25 (3의 배수만 사진)
insert into auth.users (id, email) values (:'A', 'a@x.com'), (:'B', 'b@x.com'), (:'OP', 'op@x.com');
insert into auth.users (id, email, is_anonymous) values (:'GU', null, true);
update public.profiles set nickname = '팬에이' where id = :'A';
update public.profiles set nickname = '팬비' where id = :'B';
update public.profiles set nickname = '운영', role = 'admin' where id = :'OP';
insert into auth.users (id, email) select ('00000000-0000-0000-0000-0000000004' || lpad(i::text, 2, '0'))::uuid, 'k' || i || '@x.com' from generate_series(1, 25) i;
update public.profiles set nickname = 'inf' || right(id::text, 2), influencer = case when right(id::text, 2)::int % 2 = 0 then 'pro' else 'creator' end, influencer_at = now()
 where id::text like '00000000-0000-0000-0000-0000000004%';
update public.profiles set photo_path = id::text || '/a.jpg', photo_updated_at = now()
 where id::text like '00000000-0000-0000-0000-0000000004%' and right(id::text, 2)::int % 3 = 0;
-- A는 25명 모두 팔로우 (inf01이 가장 최근, 같은 시각 둘: inf24·inf25), B는 inf01·inf02·inf03만, GU는 inf01
insert into public.influencer_follows (follower_id, influencer_id, created_at)
select :'A', p.id, now() - (least(right(p.id::text, 2)::int, 24) || ' minutes')::interval from public.profiles p where p.id::text like '00000000-0000-0000-0000-0000000004%';
insert into public.influencer_follows (follower_id, influencer_id, created_at)
select :'B', p.id, now() - interval '1 day' from public.profiles p where p.id::text in ('00000000-0000-0000-0000-000000000401', '00000000-0000-0000-0000-000000000402', '00000000-0000-0000-0000-000000000403');
insert into public.influencer_follows (follower_id, influencer_id) values (:'GU', '00000000-0000-0000-0000-000000000401');
-- 공개 빌드: inf01에 공개 2 + 숨김 1, inf02에 공개 1
begin;
alter table public.builds disable trigger builds_check_new;
create temp table src as select * from public.builds where counter_id = (select id from public.counters where counter_champion = 'Quinn') order by id limit 1;
insert into public.builds (counter_id, author_id, runes, summoner_spells, starting_items, core_items, max_skill, patch, status, hide_reason, hidden_at)
select s.counter_id, a.author::uuid, s.runes, s.summoner_spells, s.starting_items, s.core_items, s.max_skill, s.patch, a.st,
       case when a.st = 'hidden' then '검사' end, case when a.st = 'hidden' then now() end
  from src s, (values ('00000000-0000-0000-0000-000000000401', 'approved'), ('00000000-0000-0000-0000-000000000401', 'approved'),
                      ('00000000-0000-0000-0000-000000000401', 'hidden'), ('00000000-0000-0000-0000-000000000402', 'approved')) a(author, st);
set constraints all immediate;
alter table public.builds enable trigger builds_check_new;
commit;

create function pg_temp.cards(u uuid, pg integer default 1) returns jsonb language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', u::text, true);
  return public.my_following_cards(pg);
end $$;
create function pg_temp.old(u uuid, pg integer default 1) returns jsonb language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', u::text, true);
  return public.my_following(pg);
end $$;
create function pg_temp.ids(j jsonb) returns text language sql immutable as $$
  select coalesce(string_agg(right(e ->> 'id', 2), ',' order by o), '') from jsonb_array_elements(j -> 'items') with ordinality x(e, o) $$;
create function pg_temp.all_ids(u uuid) returns text language plpgsql as $$
declare r text := ''; n integer := 1; j jsonb;
begin
  loop
    j := pg_temp.cards(u, n);
    exit when jsonb_array_length(j -> 'items') = 0;
    r := r || case when r = '' then '' else ',' end || pg_temp.ids(j);
    n := n + 1;
  end loop;
  return r;
end $$;
create function pg_temp.data_fp() returns text language sql stable as $$
  select (select md5(string_agg(p::text, '|' order by p.id)) from public.profiles p)
    || '#' || (select md5(string_agg(f::text, '|' order by f.follower_id, f.influencer_id)) from public.influencer_follows f)
    || '#' || (select md5(coalesce(string_agg(n::text, '|' order by n.id), '')) from public.notifications n) $$;
create function pg_temp.fn_fp() returns text language sql stable as $$
  select count(*) || '/' || md5(string_agg(p.proname || '(' || oidvectortypes(p.proargtypes) || ')' || pg_get_function_result(p.oid) || p.provolatile::text
           || replace(p.prosrc, E'\r', '') || p.prosecdef::text || coalesce(array_to_string(p.proconfig, ','), '') || coalesce(array_to_string(p.proacl, ','), ''),
           '|' order by p.proname, oidvectortypes(p.proargtypes)))
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind in ('f', 'p') and p.proname <> 'my_following_cards' $$;
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
grant execute on all functions in schema pg_temp to anon, authenticated;
select pg_temp.data_fp() as d0, pg_temp.fn_fp() as fn0, pg_temp.counts() as cnt0, pg_temp.push_fp() as push0 \gset

-- ===== 1. 모양·권한 =====
select t.ok('my_following_cards(integer) 하나 · jsonb · stable · security definer · search_path 빈 값 · 기본값 1 · 설명',
  (select count(*) = 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'my_following_cards')
  and (select provolatile = 's' and prosecdef and proconfig = array['search_path=""'] and prorettype = 'jsonb'::regtype
          and pg_get_function_arguments(oid) = 'p_page integer DEFAULT 1' and obj_description(oid, 'pg_proc') like '내가 팔로우한 장인 카드 (079)%'
         from pg_proc where oid = 'public.my_following_cards(integer)'::regprocedure));
select t.ok('권한: 로그인(authenticated)만 실행, 비로그인(anon)·public 불가 (my_following과 같음)',
  has_function_privilege('authenticated', 'public.my_following_cards(integer)', 'execute')
  and not has_function_privilege('anon', 'public.my_following_cards(integer)', 'execute')
  and (select not exists (select 1 from unnest(proacl) a where a::text like '=%') from pg_proc where oid = 'public.my_following_cards(integer)'::regprocedure));
select t.ok('읽기 함수라 068 쓰기 함수 검사 대상이 아니고 허용 목록에도 없음 · 쓰기 함수 105/31/74 · 읽기 함수 69 (66 + my_following_cards + 080 2개)',
  pg_temp.counts() like '105/31/74/69/%' and not exists (select 1 from public.restriction_exemptions where name like 'my_following_cards%'));
set role anon;
reset request.jwt.claim.sub;
select t.fails('비로그인: 실행 권한 없음', 'select public.my_following_cards()', 'permission denied');
reset role;
set role authenticated;
reset request.jwt.claim.sub;
select t.fails('로그인 표시(sub)가 없으면 거부', 'select public.my_following_cards()', '로그인해 주세요');
set request.jwt.claim.sub = :'GU';
select t.fails('비회원(게스트): my_following과 같은 문장으로 거부', 'select public.my_following_cards()', '비회원은 팔로우한 장인 목록을 볼 수 없습니다');
reset role;

-- ===== 2. 나의 팔로우만 · 순서 · 쪽 =====
select pg_temp.cards(:'A') as a1, pg_temp.cards(:'A', 2) as a2, pg_temp.cards(:'B') as b1, pg_temp.old(:'A') as o1, pg_temp.old(:'A', 2) as o2 \gset
select t.ok('A: total 25 · 1쪽 20 · 2쪽 5 · 3쪽 0 · size 20 · page 그대로',
  (:'a1'::jsonb ->> 'total')::int = 25 and jsonb_array_length(:'a1'::jsonb -> 'items') = 20 and jsonb_array_length(:'a2'::jsonb -> 'items') = 5
  and jsonb_array_length(pg_temp.cards(:'A', 3) -> 'items') = 0 and (:'a1'::jsonb ->> 'size')::int = 20 and (:'a2'::jsonb ->> 'page')::int = 2);
select t.ok('A: 최근 팔로우 순 (같은 시각이면 장인 id 순), 쪽을 이어도 겹침·빠짐 없음',
  pg_temp.all_ids(:'A') = '01,02,03,04,05,06,07,08,09,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25');
select t.ok('순서·쪽이 my_following과 같음 (1쪽·2쪽 id)', pg_temp.ids(:'a1') = pg_temp.ids(:'o1') and pg_temp.ids(:'a2') = pg_temp.ids(:'o2'));
select t.ok('B: 자기 팔로우 3명만 (A의 팔로우가 보이지 않음)', (:'b1'::jsonb ->> 'total')::int = 3 and pg_temp.ids(:'b1') = '01,02,03');
select t.ok('팔로우가 없는 운영자: total 0 · 빈 목록', pg_temp.cards(:'OP') = '{"page": 1, "size": 20, "items": [], "total": 0}'::jsonb);
select t.ok('쪽 번호 0·음수·null은 1쪽', pg_temp.ids(pg_temp.cards(:'A', 0)) = pg_temp.ids(:'a1') and pg_temp.ids(pg_temp.cards(:'A', -3)) = pg_temp.ids(:'a1')
  and pg_temp.ids(pg_temp.cards(:'A', null)) = pg_temp.ids(:'a1'));

-- ===== 3. 돌려주는 칸 =====
select t.ok('칸은 id·nickname·influencer·photo_path·follower_count·build_count뿐 (이메일·가입일시·역할·팔로우한 때 없음), 바깥은 total·page·size·items',
  (select string_agg(distinct k, ',' order by k) from jsonb_array_elements(:'a1'::jsonb -> 'items') e, jsonb_object_keys(e) k)
    = 'build_count,follower_count,id,influencer,nickname,photo_path'
  and (select string_agg(k, ',' order by k) from jsonb_object_keys(:'a1'::jsonb) k) = 'items,page,size,total');
select t.ok('값: 닉네임·유형(pro/creator)·사진 경로(3의 배수만, 나머지 null)가 profiles와 같음', not exists (
  select 1 from jsonb_array_elements((:'a1'::jsonb -> 'items') || (:'a2'::jsonb -> 'items')) e join public.profiles p on p.id = (e ->> 'id')::uuid
   where e ->> 'nickname' is distinct from p.nickname or e ->> 'influencer' is distinct from p.influencer or e ->> 'photo_path' is distinct from p.photo_path)
  and (select count(*) from jsonb_array_elements((:'a1'::jsonb -> 'items') || (:'a2'::jsonb -> 'items')) e where e ->> 'photo_path' is not null) = 8);
select t.ok('팔로워 수 = 장인 전체 팔로워 수 (inf01 3명: A·B·GU, inf05 1명), 공개 빌드 수 = 장인 페이지와 같은 식 (inf01 2 · 숨김 제외, inf02 1, 나머지 0)',
  (select (e ->> 'follower_count')::int from jsonb_array_elements(:'a1'::jsonb -> 'items') e where right(e ->> 'id', 2) = '01') = 3
  and (select (e ->> 'follower_count')::int from jsonb_array_elements(:'a1'::jsonb -> 'items') e where right(e ->> 'id', 2) = '05') = 1
  and not exists (select 1 from jsonb_array_elements((:'a1'::jsonb -> 'items') || (:'a2'::jsonb -> 'items')) e
                   where (e ->> 'build_count')::int <> (select count(*) from public.builds b join public.counters c on c.id = b.counter_id
                                                         where b.author_id = (e ->> 'id')::uuid and b.status = 'approved' and c.status = 'approved'))
  and (select (e ->> 'build_count')::int from jsonb_array_elements(:'a1'::jsonb -> 'items') e where right(e ->> 'id', 2) = '01') = 2);

-- ===== 4. 빼는 장인 =====
insert into public.user_restrictions (user_id, reason, days, ends_at, created_by) values ('00000000-0000-0000-0000-000000000402', '검사', 7, now() + interval '7 days', :'OP');
select t.ok('정지 중인 장인(inf02)은 목록·total에서 빠짐 (A 24명, B 2명), 쪽을 이어도 빠짐 없음',
  (pg_temp.cards(:'A') ->> 'total')::int = 24 and pg_temp.ids(pg_temp.cards(:'B')) = '01,03' and (pg_temp.cards(:'B') ->> 'total')::int = 2
  and pg_temp.all_ids(:'A') = '01,03,04,05,06,07,08,09,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25');
select t.ok('my_following은 그대로 정지 중인 장인도 보임 (기존 함수는 고치지 않음)', pg_temp.ids(pg_temp.old(:'B')) = '01,02,03');
update public.user_restrictions set lifted_at = now(), lifted_by = :'OP' where user_id = '00000000-0000-0000-0000-000000000402';
select t.ok('정지가 풀리면 다시 나옴 (팔로우가 남아 있으므로)', pg_temp.ids(pg_temp.cards(:'B')) = '01,02,03');
begin;
update public.profiles set influencer = null, influencer_at = null where id = '00000000-0000-0000-0000-000000000403';
select t.ok('장인 인증 해제(inf03): 팔로우가 지워져 목록·total에서 빠짐', pg_temp.ids(pg_temp.cards(:'B')) = '01,02' and (pg_temp.cards(:'A') ->> 'total')::int = 24);
rollback;
begin;
delete from auth.users where id = '00000000-0000-0000-0000-000000000401';
select t.ok('탈퇴한 장인(inf01): 팔로우가 함께 지워져 빠짐', pg_temp.ids(pg_temp.cards(:'B')) = '02,03');
rollback;
select t.ok('불러도 데이터는 그대로 (profiles·팔로우·알림)', pg_temp.data_fp() = :'d0'
  and pg_temp.counts() = :'cnt0');

-- ===== 5. 되돌리기 블록 (079 파일 그대로) → 078 =====
begin;
drop function public.my_following_cards(integer);
commit;
select t.ok('되돌리기: my_following_cards 없음 · 다른 함수 지문·쓰기 함수 수 그대로 · 읽기 함수 68(080 2개 포함) · 푸시 판정 그대로',
  to_regprocedure('public.my_following_cards(integer)') is null and pg_temp.fn_fp() = :'fn0'
  and pg_temp.counts() like '105/31/74/68/%' and pg_temp.push_fp() = :'push0');
select t.ok('되돌려도 my_following은 063 본문(e40ce0e5…)·권한 그대로',
  (select md5(replace(prosrc, E'\r', '')) = 'e40ce0e5918ea536f64c16340501eddf' and has_function_privilege('authenticated', oid, 'execute')
          and not has_function_privilege('anon', oid, 'execute') from pg_proc where oid = 'public.my_following(integer)'::regprocedure));

-- ===== 6. 079 본문 다시 (파일 그대로) =====
begin;

do $chk$
begin
  if to_regprocedure('public.my_following_cards(integer)') is not null then
    raise exception 'my_following_cards가 이미 있습니다(079를 이미 실행함). 실행을 멈춥니다.';
  end if;
  if to_regprocedure('public.my_following(integer)') is null or to_regprocedure('public.active_restriction_id(uuid)') is null then
    raise exception '063·068이 아직 실행되지 않았습니다.';
  end if;
end $chk$;

create function public.my_following_cards(p_page integer default 1)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  me uuid := (select auth.uid());
  pg integer := greatest(coalesce(p_page, 1), 1);
  sz constant integer := 20;
begin
  if me is null then
    raise exception '로그인해 주세요.' using errcode = '42501';
  end if;
  if public.is_guest(me) then
    raise exception '비회원은 팔로우한 장인 목록을 볼 수 없습니다. 마이페이지에서 구글·카카오를 연결해 주세요.' using errcode = '42501';
  end if;
  return (
    with f as (
      select x.influencer_id, x.created_at, p.nickname, p.influencer, p.photo_path
        from public.influencer_follows x
        join public.profiles p on p.id = x.influencer_id
       where x.follower_id = me
         and p.influencer is not null and p.nickname is not null
         and public.active_restriction_id(p.id) is null
    ), pagef as (
      select * from f order by f.created_at desc, f.influencer_id limit sz offset (pg - 1) * sz
    )
    select jsonb_build_object(
      'total', (select count(*) from f),
      'page', pg, 'size', sz,
      'items', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', g.influencer_id, 'nickname', g.nickname, 'influencer', g.influencer, 'photo_path', g.photo_path,
                 'follower_count', (select count(*) from public.influencer_follows h where h.influencer_id = g.influencer_id),
                 'build_count', (select count(*) from public.builds b join public.counters c on c.id = b.counter_id
                                  where b.author_id = g.influencer_id and b.status = 'approved' and c.status = 'approved'))
               order by g.created_at desc, g.influencer_id)
          from pagef g
      ), '[]'::jsonb))
  );
end;
$$;
comment on function public.my_following_cards(integer) is
  '내가 팔로우한 장인 카드 (079): my_following과 같은 순서·쪽(20). 사진·장인 유형·팔로워 수·공개 빌드 수. 인증 없음·닉네임 없음·정지 중인 장인 제외. 로그인·비회원 아님';
revoke execute on function public.my_following_cards(integer) from public, anon;
grant execute on function public.my_following_cards(integer) to authenticated;

commit;
select t.ok('079 다시: 같은 지문(0cfd5497…)·같은 결과, 다른 함수·수·푸시 판정 그대로',
  (select md5(replace(prosrc, E'\r', '')) from pg_proc where oid = 'public.my_following_cards(integer)'::regprocedure) = '0cfd5497d4e82573a44f87e34c020d9b'
  and pg_temp.cards(:'A') = :'a1'::jsonb and pg_temp.fn_fp() = :'fn0' and pg_temp.counts() = :'cnt0' and pg_temp.push_fp() = :'push0');
select t.fails('079를 한 번 더 실행하면 멈춤 (079 파일의 실행 전 확인 그대로)', $q$do $chk$
begin
  if to_regprocedure('public.my_following_cards(integer)') is not null then
    raise exception 'my_following_cards가 이미 있습니다(079를 이미 실행함). 실행을 멈춥니다.';
  end if;
  if to_regprocedure('public.my_following(integer)') is null or to_regprocedure('public.active_restriction_id(uuid)') is null then
    raise exception '063·068이 아직 실행되지 않았습니다.';
  end if;
end $chk$$q$, '이미 있습니다');
