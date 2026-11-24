-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것. (운영 DB 확인은 scripts/check_influencer_directory_after.sql)
-- 070 공개 장인 목록 influencer_directory: 권한(비로그인·로그인 가능, public 회수), 읽기 함수(stable·search_path·068 쓰기 함수 검사 대상 아님),
--   대상(장인만·닉네임 있음·탈퇴하면 빠짐), 개수가 search_influencers와 같음, 숨긴·대기 빌드와 숨긴 상대법의 빌드는 개수·최근 활동 모두에서 빠짐,
--   정렬 두 가지와 동률 처리, 쪽 나누기(겹침·빠짐 없음), 입력 보정(정렬·쪽·크기 1~50), 검색(대소문자·%·_ 글자 그대로·20자), 돌려주는 칸 7개,
--   기존 함수(search_influencers) 그대로, 데이터를 바꾸지 않음
\set ON_ERROR_STOP 1
\set QUIET 1
\set A  '00000000-0000-0000-0000-0000000000a1'
\set B  '00000000-0000-0000-0000-0000000000a2'
\set C  '00000000-0000-0000-0000-0000000000a3'
\set D  '00000000-0000-0000-0000-0000000000a4'
\set E  '00000000-0000-0000-0000-0000000000a5'
\set G  '00000000-0000-0000-0000-0000000000a6'
\set N  '00000000-0000-0000-0000-0000000000a7'
\set F1 '00000000-0000-0000-0000-0000000000f1'
\set F2 '00000000-0000-0000-0000-0000000000f2'
\set F3 '00000000-0000-0000-0000-0000000000f3'
insert into auth.users (id, email) values (:'A', 'a@x.com'), (:'B', 'b@x.com'), (:'C', 'c@x.com'), (:'D', 'd@x.com'), (:'E', 'e@x.com'),
  (:'G', 'g@x.com'), (:'N', 'n@x.com'), (:'F1', 'f1@x.com'), (:'F2', 'f2@x.com'), (:'F3', 'f3@x.com');
update public.profiles set nickname = 'Alpha', influencer = 'pro', influencer_at = now() where id = :'A';
update public.profiles set nickname = 'Bravo', influencer = 'creator', influencer_at = now() where id = :'B';
update public.profiles set nickname = 'Charlie', influencer = 'grandmaster', influencer_at = now() where id = :'C';
update public.profiles set nickname = '델타', influencer = 'creator', influencer_at = now() where id = :'D';
update public.profiles set nickname = 'Echo', influencer = 'creator', influencer_at = now() where id = :'E';
update public.profiles set nickname = 'Golf', influencer = 'pro', influencer_at = now() where id = :'G';
update public.profiles set nickname = 'Alpine' where id = :'N';  -- 장인 아님 (검색어 alp에 걸리지만 빠져야 함)
update public.profiles set nickname = '팬' || right(id::text, 1) where id in (:'F1', :'F2', :'F3');

-- 팔로워: A·B·E 3명, C 1명, D·G 0명
insert into public.influencer_follows (follower_id, influencer_id) values
  (:'F1', :'A'), (:'F2', :'A'), (:'F3', :'A'),
  (:'F1', :'B'), (:'F2', :'B'), (:'F3', :'B'),
  (:'F1', :'E'), (:'F2', :'E'), (:'F3', :'E'),
  (:'F1', :'C');

-- 빌드 (검사 트리거를 잠깐 끄고 픽스처 빌드를 복사해 넣는다 - fixtures.sql과 같은 방식)
--   A: 공개 1개(3일 전) + 숨김 1개(방금) + 대기 1개(방금) -> 개수 1, 최근 활동 3일 전
--   B: 공개 2개(1일 전, 5일 전) -> 개수 2, 1일 전
--   C: 공개 1개(1시간 전)
--   E: 숨긴 상대법에만 빌드(방금, 빌드 자체는 approved) -> 개수 0, null
--   D·G: 빌드 없음
begin;
alter table public.builds disable trigger builds_check_new;
insert into public.counters (target_champion, counter_champion, sort_order, status) values ('Darius', 'Teemo', 9, 'hidden');
create temp table src as select * from public.builds where counter_id = (select id from public.counters where counter_champion = 'Quinn') order by id limit 1;
insert into public.builds (counter_id, author_id, runes, summoner_spells, starting_items, core_items, max_skill, patch, status, updated_at, hide_reason, hidden_at)
select coalesce(v.cid, s.counter_id), v.author, s.runes, s.summoner_spells, s.starting_items, s.core_items, s.max_skill, s.patch, v.st, v.at,
       case when v.st = 'hidden' then '검사' end, case when v.st = 'hidden' then now() end
  from src s, (values
    (:'A'::uuid, 'approved', now() - interval '3 days', null::bigint),
    (:'A'::uuid, 'hidden',   now(),                     null),
    (:'A'::uuid, 'pending',  now(),                     null),
    (:'B'::uuid, 'approved', now() - interval '1 day',  null),
    (:'B'::uuid, 'approved', now() - interval '5 days', null),
    (:'C'::uuid, 'approved', now() - interval '1 hour', null),
    (:'E'::uuid, 'approved', now(), (select id from public.counters where counter_champion = 'Teemo'))
  ) as v (author, st, at, cid);
set constraints all immediate;
alter table public.builds enable trigger builds_check_new;
commit;
-- 위 넣기에서 트리거가 updated_at을 바꿨을 수 있으니 시각을 다시 맞춘다 (status 그대로)
update public.builds set updated_at = case
    when author_id = :'A' and status = 'approved' then now() - interval '3 days'
    when author_id = :'B' and updated_at > now() - interval '2 days' then now() - interval '1 day'
    when author_id = :'B' then now() - interval '5 days'
    when author_id = :'C' then now() - interval '1 hour'
    else now() end
 where author_id in (:'A', :'B', :'C', :'E');

create function pg_temp.dir(q text default null, s text default null, pg integer default 1, sz integer default 50) returns jsonb
  language sql stable as $$ select public.influencer_directory(q, s, pg, sz) $$;
create function pg_temp.names(j jsonb) returns text language sql immutable as $$
  select coalesce(string_agg(e ->> 'nickname', ',' order by o), '') from jsonb_array_elements(j -> 'items') with ordinality as x(e, o) $$;
create function pg_temp.item(j jsonb, nick text) returns jsonb language sql immutable as $$
  select e from jsonb_array_elements(j -> 'items') e where e ->> 'nickname' = nick $$;
create function pg_temp.fp() returns text language sql stable as $$
  select (select md5(string_agg(p::text, '|' order by p.id)) from public.profiles p)
    || '#' || (select md5(string_agg(b::text, '|' order by b.id)) from public.builds b)
    || '#' || (select md5(string_agg(f::text, '|' order by f.follower_id::text, f.influencer_id::text)) from public.influencer_follows f) $$;
grant execute on all functions in schema pg_temp to anon, authenticated;
select pg_temp.fp() as fp0 \gset

-- ===== 1. 권한 / 읽기 함수 =====
select t.ok('비로그인(anon)·로그인(authenticated) 둘 다 부를 수 있음',
  has_function_privilege('anon', 'public.influencer_directory(text, text, integer, integer)', 'execute')
  and has_function_privilege('authenticated', 'public.influencer_directory(text, text, integer, integer)', 'execute'));
select t.ok('public 기본 권한은 회수 (권한 목록에 "=X/" 없음)',
  (select not exists (select 1 from unnest(proacl) a where a::text like '=%') from pg_proc where oid = 'public.influencer_directory(text, text, integer, integer)'::regprocedure));
select t.ok('stable · security definer · search_path 빈 값',
  (select provolatile = 's' and prosecdef and proconfig = array['search_path=""'] from pg_proc where oid = 'public.influencer_directory(text, text, integer, integer)'::regprocedure));
select t.ok('068 빠뜨림 방지 검사(volatile 쓰기 함수만)의 대상이 아니고, 허용 목록에도 없음',
  (select provolatile <> 'v' from pg_proc where oid = 'public.influencer_directory(text, text, integer, integer)'::regprocedure)
  and not exists (select 1 from public.restriction_exemptions where name like 'influencer_directory%'));
set role anon;
reset request.jwt.claim.sub;
select t.ok('비로그인 호출: 장인 6명', (public.influencer_directory(null, null, 1, 10) ->> 'total')::int = 6);
reset role;
set role authenticated;
set request.jwt.claim.sub = :'F1';
select t.ok('로그인 호출: 장인 6명', (public.influencer_directory(null, null, 1, 10) ->> 'total')::int = 6);
reset role;
reset request.jwt.claim.sub;

-- ===== 2. 대상 / 돌려주는 칸 =====
select pg_temp.dir() as all_f \gset
select t.ok('장인만 (일반 회원 Alpine·팬 없음)', pg_temp.names(:'all_f') !~ '(Alpine|팬)');
select t.ok('돌려주는 칸은 7개뿐 (이메일·역할·경험치 등 없음)', not exists (
  select 1 from jsonb_array_elements(:'all_f'::jsonb -> 'items') e, jsonb_object_keys(e) k
   where k not in ('id', 'nickname', 'influencer', 'photo_path', 'follower_count', 'build_count', 'last_activity_at'))
  and (select count(*) from jsonb_object_keys(pg_temp.item(:'all_f', 'Alpha'))) = 7);
select t.ok('맨 위 칸: total·page·size·sort·items', (select array_agg(k order by k) from jsonb_object_keys(:'all_f'::jsonb) k) = array['items', 'page', 'size', 'sort', 'total']);
select t.ok('장인 유형·사진 칸 그대로', pg_temp.item(:'all_f', 'Charlie') ->> 'influencer' = 'grandmaster'
  and pg_temp.item(:'all_f', 'Charlie') ? 'photo_path');

-- ===== 3. 개수 / 숨긴 빌드 =====
select t.ok('팔로워 수: A 3, C 1, D 0', (pg_temp.item(:'all_f', 'Alpha') ->> 'follower_count')::int = 3
  and (pg_temp.item(:'all_f', 'Charlie') ->> 'follower_count')::int = 1 and (pg_temp.item(:'all_f', '델타') ->> 'follower_count')::int = 0);
select t.ok('빌드 수: A 1(숨김·대기 빠짐), B 2, E 0(숨긴 상대법 빠짐), D 0',
  (pg_temp.item(:'all_f', 'Alpha') ->> 'build_count')::int = 1 and (pg_temp.item(:'all_f', 'Bravo') ->> 'build_count')::int = 2
  and (pg_temp.item(:'all_f', 'Echo') ->> 'build_count')::int = 0 and (pg_temp.item(:'all_f', '델타') ->> 'build_count')::int = 0);
select t.ok('최근 활동: A는 공개 빌드의 3일 전 (방금 고친 숨김·대기 빌드는 안 드러남)',
  (pg_temp.item(:'all_f', 'Alpha') ->> 'last_activity_at')::timestamptz
    = (select updated_at from public.builds where author_id = :'A' and status = 'approved'));
select t.ok('최근 활동: 공개 빌드가 없으면 null (E 숨긴 상대법뿐, D 빌드 없음)',
  pg_temp.item(:'all_f', 'Echo') -> 'last_activity_at' = 'null'::jsonb and pg_temp.item(:'all_f', '델타') -> 'last_activity_at' = 'null'::jsonb);
select t.ok('최근 활동: B는 두 공개 빌드 중 최근(1일 전)',
  (pg_temp.item(:'all_f', 'Bravo') ->> 'last_activity_at')::timestamptz
    = (select max(updated_at) from public.builds where author_id = :'B' and status = 'approved'));
select t.ok('팔로워 수·빌드 수가 장인마다 search_influencers와 같음', not exists (
  select 1 from jsonb_array_elements(:'all_f'::jsonb -> 'items') d
   cross join lateral (select s from jsonb_array_elements(public.search_influencers(d ->> 'nickname') -> 'items') s where s ->> 'id' = d ->> 'id') x
   where (x.s ->> 'follower_count') is distinct from (d ->> 'follower_count') or (x.s ->> 'build_count') is distinct from (d ->> 'build_count'))
  and (select count(*) from jsonb_array_elements(:'all_f'::jsonb -> 'items') d
        where exists (select 1 from jsonb_array_elements(public.search_influencers(d ->> 'nickname') -> 'items') s where s ->> 'id' = d ->> 'id')) = 6);

-- ===== 4. 정렬 =====
select t.ok('팔로워 많은 순(기본): 3명끼리는 최근 활동 순(B 1일 > A 3일 > E 없음), 다음 C, 0명끼리는 닉네임 순 [' || pg_temp.names(:'all_f') || ']',
  pg_temp.names(:'all_f') = 'Bravo,Alpha,Echo,Charlie,Golf,델타' and :'all_f'::jsonb ->> 'sort' = 'followers');
select t.ok('최신순: C(1시간) > B > A, 활동 없는 사람은 맨 뒤에서 팔로워 순(E 3) → 닉네임 순 [' || pg_temp.names(pg_temp.dir(null, 'recent')) || ']',
  pg_temp.names(pg_temp.dir(null, 'recent')) = 'Charlie,Bravo,Alpha,Echo,Golf,델타' and pg_temp.dir(null, 'recent') ->> 'sort' = 'recent');
select t.ok('모르는 정렬·null·빈 값은 팔로워 많은 순', pg_temp.names(pg_temp.dir(null, 'xyz')) = pg_temp.names(:'all_f')
  and pg_temp.dir(null, 'xyz') ->> 'sort' = 'followers' and pg_temp.dir(null, '') ->> 'sort' = 'followers'
  and public.influencer_directory() ->> 'sort' = 'followers');
select t.ok('대소문자가 다른 RECENT는 모르는 값 (팔로워 순)', pg_temp.dir(null, 'RECENT') ->> 'sort' = 'followers');

-- ===== 5. 쪽 나누기 =====
select t.ok('크기 2로 1~3쪽을 이으면 한 번에 본 순서와 같음 (겹침·빠짐 없음, 두 정렬 모두)',
  pg_temp.names(pg_temp.dir(null, null, 1, 2)) || ',' || pg_temp.names(pg_temp.dir(null, null, 2, 2)) || ',' || pg_temp.names(pg_temp.dir(null, null, 3, 2)) = pg_temp.names(:'all_f')
  and pg_temp.names(pg_temp.dir(null, 'recent', 1, 2)) || ',' || pg_temp.names(pg_temp.dir(null, 'recent', 2, 2)) || ',' || pg_temp.names(pg_temp.dir(null, 'recent', 3, 2))
      = pg_temp.names(pg_temp.dir(null, 'recent')));
select t.ok('크기 4: 1쪽 4명, 2쪽 2명, 3쪽 0명, total은 늘 6', jsonb_array_length(pg_temp.dir(null, null, 1, 4) -> 'items') = 4
  and jsonb_array_length(pg_temp.dir(null, null, 2, 4) -> 'items') = 2 and jsonb_array_length(pg_temp.dir(null, null, 3, 4) -> 'items') = 0
  and (pg_temp.dir(null, null, 3, 4) ->> 'total')::int = 6);
select t.ok('쪽 0·음수·null은 1쪽', pg_temp.names(pg_temp.dir(null, null, 0, 2)) = 'Bravo,Alpha' and pg_temp.dir(null, null, -3, 2) ->> 'page' = '1'
  and public.influencer_directory(null, null, null, 2) ->> 'page' = '1');
select t.ok('크기: 기본 10, 999 → 50, 0·음수 → 1, null → 10',
  public.influencer_directory() ->> 'size' = '10' and pg_temp.dir(null, null, 1, 999) ->> 'size' = '50'
  and pg_temp.dir(null, null, 1, 0) ->> 'size' = '1' and jsonb_array_length(pg_temp.dir(null, null, 1, -5) -> 'items') = 1
  and public.influencer_directory(null, null, 1, null) ->> 'size' = '10');

-- ===== 6. 검색 =====
select t.ok('부분 일치·대소문자 무시: ALP → Alpha만 (장인 아닌 Alpine 없음)', pg_temp.names(pg_temp.dir('ALP')) = 'Alpha'
  and (pg_temp.dir('ALP') ->> 'total')::int = 1);
select t.ok('가운데 글자로도: rav → Bravo, 한글: 델 → 델타', pg_temp.names(pg_temp.dir('rav')) = 'Bravo' and pg_temp.names(pg_temp.dir('델')) = '델타');
select t.ok('검색해도 정렬은 그대로: "o" 팔로워 순 / 최신순', pg_temp.names(pg_temp.dir('o')) = 'Bravo,Echo,Golf'
  and pg_temp.names(pg_temp.dir('o', 'recent')) = 'Bravo,Echo,Golf');
select t.ok('%, _ 는 글자 그대로 (아무거나 아님)', (pg_temp.dir('%') ->> 'total')::int = 0 and (pg_temp.dir('_') ->> 'total')::int = 0
  and (pg_temp.dir('a%') ->> 'total')::int = 0);
select t.ok('빈 칸·공백뿐이면 전체', (pg_temp.dir('   ') ->> 'total')::int = 6 and (pg_temp.dir('') ->> 'total')::int = 6);
select t.ok('검색어 앞뒤 빈칸은 뺌', pg_temp.names(pg_temp.dir('  alpha  ')) = 'Alpha');
select t.ok('20자까지는 됨', (pg_temp.dir(repeat('가', 20)) ->> 'total')::int = 0);
select t.fails('21자는 거부 (search_influencers와 같은 문장)', format('select public.influencer_directory(%L)', repeat('가', 21)), '20자 이하');
select t.ok('없는 닉네임 → total 0, items 빈 배열', (pg_temp.dir('zzz') ->> 'total')::int = 0 and pg_temp.dir('zzz') -> 'items' = '[]'::jsonb);

-- ===== 7. 장인 해제·탈퇴 =====
begin;
update public.profiles set influencer = null, influencer_at = null where id = :'G';
select t.ok('장인 인증이 풀리면 목록에서 빠짐', (pg_temp.dir() ->> 'total')::int = 5 and pg_temp.names(pg_temp.dir()) !~ 'Golf');
rollback;
begin;
delete from auth.users where id = :'C';
select t.ok('탈퇴하면 빠짐 (프로필이 지워짐)', (pg_temp.dir() ->> 'total')::int = 5 and pg_temp.names(pg_temp.dir()) !~ 'Charlie');
rollback;

-- ===== 8. 바꾸지 않은 것 =====
select t.ok('부르기만 해서는 데이터가 그대로 (프로필·빌드·팔로우 지문)', pg_temp.fp() = :'fp0');
select t.ok('search_influencers는 그대로: 빈 검색어 거부, 20개씩, 인자·반환형',
  to_regprocedure('public.search_influencers(text, integer)') is not null
  and (select prorettype = 'jsonb'::regtype from pg_proc where oid = 'public.search_influencers(text, integer)'::regprocedure)
  and public.search_influencers('a') ->> 'size' = '20');
select t.fails('search_influencers 빈 검색어는 여전히 거부', 'select public.search_influencers(''  '')', '한 글자 이상');
select t.ok('같은 이름의 다른 버전(오버로드) 없음', (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'influencer_directory') = 1);
