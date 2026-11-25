-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것. (운영 DB 확인은 scripts/check_member_page_after.sql)
-- 075 일반 사용자 개인 페이지 member_page: 권한(비로그인·로그인 가능, public 회수), 읽기 함수(stable·definer·search_path·068 쓰기 함수 검사 대상 아님,
--   쓰기 함수 103/30/73 그대로, 읽기 함수 66), 열리는 기준(공개 빌드 5개 이상 = 승인 빌드 + 승인 상대법, 숨김·대기·거절·숨긴 상대법 제외,
--   설정값으로 바뀜), 닫히는 경우(모양 틀린 id·없는 사람·탈퇴·닉네임 없음·비회원·운영자·장인·정지 중 → 모두 null),
--   정지가 끝나거나 풀리면 다시 열림, 부른 사람과 관계없이 같은 응답, 돌려주는 칸(닉네임·사진·칭호·빌드뿐 - 이메일·가입일시·역할·레벨 없음),
--   칭호(숨긴 도감 칭호 제외, 비밀 칭호는 대표일 때만), 쪽 나누기·정렬, 데이터를 바꾸지 않음
\set ON_ERROR_STOP 1
\set QUIET 1
\set R  '00000000-0000-0000-0000-0000000000b1'
\set S  '00000000-0000-0000-0000-0000000000b2'
\set X  '00000000-0000-0000-0000-0000000000b3'
\set I  '00000000-0000-0000-0000-0000000000b4'
\set GU '00000000-0000-0000-0000-0000000000b5'
\set NN '00000000-0000-0000-0000-0000000000b6'
\set OP '00000000-0000-0000-0000-0000000000b7'
\set W  '00000000-0000-0000-0000-0000000000b8'
\set M  '00000000-0000-0000-0000-0000000000b9'
\set V  '00000000-0000-0000-0000-0000000000c1'
insert into auth.users (id, email) values (:'R', 'r@x.com'), (:'S', 's@x.com'), (:'X', 'x@x.com'), (:'I', 'i@x.com'), (:'GU', 'gu@x.com'),
  (:'NN', 'nn@x.com'), (:'OP', 'op@x.com'), (:'W', 'w@x.com'), (:'M', 'm@x.com'), (:'V', 'v@x.com');
update public.profiles set nickname = '루키' where id = :'R';
update public.profiles set nickname = '사파' where id = :'S';
update public.profiles set nickname = '정지중' where id = :'X';
update public.profiles set nickname = '장인님', influencer = 'creator', influencer_at = now() where id = :'I';
update public.profiles set nickname = '손님', is_guest = true where id = :'GU';
update public.profiles set nickname = null where id = :'NN';
update public.profiles set nickname = '운영', role = 'admin', level = 0, xp = 0, main_title = null where id = :'OP';
update public.profiles set nickname = '떠날사람' where id = :'W';
update public.profiles set nickname = '감독', role = 'moderator' where id = :'M';
update public.profiles set nickname = '구경꾼' where id = :'V';

-- 빌드 (검사 트리거를 잠깐 끄고 픽스처 빌드를 복사해 넣는다 - fixtures.sql과 같은 방식)
--   R : 공개 5 + 숨김 2 + 대기 1 + 거절 1 + 재검토 1 + 숨긴 상대법에 공개 1 + 대기 상대법에 공개 1 -> 공개 5 (열림)
--   S : 공개 4 + 숨김 3 + 대기 2 + 숨긴 상대법에 공개 2 -> 공개 4 (닫힘)
--   X·I·GU·NN·OP·W·M : 공개 5씩
begin;
alter table public.builds disable trigger builds_check_new;
insert into public.counters (target_champion, counter_champion, sort_order, status) values ('Darius', 'Teemo', 9, 'hidden'), ('Darius', 'Vayne', 10, 'pending');
create temp table src as select * from public.builds where counter_id = (select id from public.counters where counter_champion = 'Quinn') order by id limit 1;
create function pg_temp.mk(author uuid, st text, n integer, champ text default 'Quinn') returns void language sql as $$
  insert into public.builds (counter_id, author_id, runes, summoner_spells, starting_items, core_items, max_skill, patch, status,
                             hide_reason, hidden_at, reject_reason, revision_note)
  select (select id from public.counters where counter_champion = champ), author, s.runes, s.summoner_spells, s.starting_items, s.core_items,
         s.max_skill, s.patch, st,
         case when st = 'hidden' then '검사' end, case when st = 'hidden' then now() end,
         case when st = 'rejected' then '검사' end, case when st = 'revision_requested' then '검사' end
    from src s, generate_series(1, n) $$;
select pg_temp.mk(:'R', 'approved', 5), pg_temp.mk(:'R', 'hidden', 2), pg_temp.mk(:'R', 'pending', 1), pg_temp.mk(:'R', 'rejected', 1),
       pg_temp.mk(:'R', 'revision_requested', 1), pg_temp.mk(:'R', 'approved', 1, 'Teemo'), pg_temp.mk(:'R', 'approved', 1, 'Vayne');
select pg_temp.mk(:'S', 'approved', 4), pg_temp.mk(:'S', 'hidden', 3), pg_temp.mk(:'S', 'pending', 2), pg_temp.mk(:'S', 'approved', 2, 'Teemo');
select pg_temp.mk(u, 'approved', 5) from unnest(array[:'X', :'I', :'GU', :'NN', :'W', :'M']::uuid[]) u;
set constraints all immediate;
alter table public.builds enable trigger builds_check_new;
commit;
-- 운영자 빌드는 트리거가 운영자 경험치를 막으므로 따로 (공개 5)
begin;
alter table public.builds disable trigger builds_check_new;
select pg_temp.mk(:'OP', 'approved', 5);
set constraints all immediate;
alter table public.builds enable trigger builds_check_new;
commit;
-- 정렬 확인용: R의 공개 빌드 수정 시각을 1~5일 전으로
update public.builds b set updated_at = now() - (x.rn || ' days')::interval
  from (select id, row_number() over (order by id) as rn from public.builds where author_id = :'R' and status = 'approved'
          and counter_id = (select id from public.counters where counter_champion = 'Quinn')) x
 where b.id = x.id;
-- X: 지금 정지 중
insert into public.user_restrictions (user_id, reason, days, ends_at, created_by) values (:'X', '검사', 7, now() + interval '7 days', :'OP');

create function pg_temp.mp(u text, pg integer default 1) returns jsonb language sql stable as $$ select public.member_page(u, pg) $$;
create function pg_temp.fp() returns text language sql stable as $$
  select (select md5(string_agg(p::text, '|' order by p.id)) from public.profiles p)
    || '#' || (select md5(string_agg(b::text, '|' order by b.id)) from public.builds b)
    || '#' || (select md5(coalesce(string_agg(n::text, '|' order by n.id), '')) from public.notifications n)
    || '#' || (select md5(coalesce(string_agg(t::text, '|' order by t.user_id, t.title_key), '')) from public.user_titles t) $$;
grant execute on all functions in schema pg_temp to anon, authenticated;
select pg_temp.fp() as fp0 \gset

-- ===== 1. 권한 / 읽기 함수 =====
select t.ok('비로그인(anon)·로그인(authenticated) 둘 다 부를 수 있음',
  has_function_privilege('anon', 'public.member_page(text, integer)', 'execute')
  and has_function_privilege('authenticated', 'public.member_page(text, integer)', 'execute'));
select t.ok('public 기본 권한은 회수 (권한 목록에 "=X/" 없음)',
  (select not exists (select 1 from unnest(proacl) a where a::text like '=%') from pg_proc where oid = 'public.member_page(text, integer)'::regprocedure));
select t.ok('stable · security definer · search_path 빈 값 · jsonb',
  (select provolatile = 's' and prosecdef and proconfig = array['search_path=""'] and prorettype = 'jsonb'::regtype
     from pg_proc where oid = 'public.member_page(text, integer)'::regprocedure));
select t.ok('068 빠뜨림 방지 검사(volatile 쓰기 함수만)의 대상이 아니고, 허용 목록에도 없음',
  (select provolatile <> 'v' from pg_proc where oid = 'public.member_page(text, integer)'::regprocedure)
  and not exists (select 1 from public.restriction_exemptions where name like 'member_page%'));
select t.ok('068 쓰기 함수 수: 104 / 첫 줄 검사 31 / 허용 목록 73 (080 set_my_champion 포함)', (
  select count(*) = 104
     and count(*) filter (where p.prosrc ~ '^\s*declare\s*\n\s*_can_write constant boolean := public\.assert_can_write\(\);'
                             or p.prosrc ~ '^\s*begin\s*\n\s*perform public\.assert_can_write\(\);') = 31
     and count(*) filter (where exists (select 1 from public.restriction_exemptions e where e.kind = 'function'
                                         and e.name = p.proname || '(' || oidvectortypes(p.proargtypes) || ')')) = 73
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f' and p.provolatile = 'v' and p.prorettype <> 'trigger'::regtype
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))));
select t.ok('일반 사용자가 부를 수 있는 읽기 함수 69개 (074까지 65 + member_page + 079 my_following_cards + 080 2개)', (
  select count(*) = 69 and count(*) filter (where p.proname = 'member_page') = 1
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f' and p.provolatile in ('s', 'i') and p.prorettype <> 'trigger'::regtype
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))));
select t.ok('설정값 member_page_min_builds = 5', public.xp_rule('member_page_min_builds') = 5);

-- ===== 2. 열리는 기준 / 공개 빌드 수 =====
select pg_temp.mp(:'R') as r1 \gset
select t.ok('R: 공개 빌드 5개 → 열림, total 5 (숨김 2·대기 1·거절 1·재검토 1·숨긴 상대법 1·대기 상대법 1 제외)',
  :'r1'::jsonb is not null and (:'r1'::jsonb ->> 'total')::int = 5 and jsonb_array_length(:'r1'::jsonb -> 'items') = 5);
select t.ok('R: 목록의 빌드는 모두 승인 빌드 + 승인 상대법', not exists (
  select 1 from jsonb_array_elements(:'r1'::jsonb -> 'items') e
   join public.builds b on b.id = (e ->> 'id')::bigint join public.counters c on c.id = b.counter_id
   where b.status <> 'approved' or c.status <> 'approved' or b.author_id <> :'R'));
set role anon;
reset request.jwt.claim.sub;
select t.ok('R: 공개 빌드 수 = 비로그인이 builds 읽기 정책(RLS)으로 보는 R의 빌드 수', (:'r1'::jsonb ->> 'total')::int = (
  select count(*) from public.builds b where b.author_id = :'R'));
reset role;
select t.ok('R: 공개 빌드 수 = 장인 페이지(public_profile.build_count)와 같은 식', (:'r1'::jsonb ->> 'total')::int = (
  select count(*) from public.builds b join public.counters c on c.id = b.counter_id
   where b.author_id = :'R' and b.status = 'approved' and c.status = 'approved'));
select t.ok('S: 공개 4개(숨김 3·대기 2·숨긴 상대법 2는 세지 않음) → null', pg_temp.mp(:'S') is null);
-- 대기 상대법이 승인되면 R은 6개
update public.counters set status = 'approved' where counter_champion = 'Vayne';
select t.ok('상대법이 공개되면 그 빌드도 셈 (R 6)', (pg_temp.mp(:'R') ->> 'total')::int = 6);
update public.counters set status = 'pending' where counter_champion = 'Vayne';
-- S의 숨긴 빌드 하나가 다시 공개되면 5개 → 열림, 다시 숨기면 닫힘
update public.builds set status = 'approved', hide_reason = null, hidden_at = null
 where id = (select min(id) from public.builds where author_id = :'S' and status = 'hidden');
select t.ok('S: 숨긴 빌드가 다시 공개되어 5개 → 열림', (pg_temp.mp(:'S') ->> 'total')::int = 5);
update public.builds set status = 'hidden', hide_reason = '검사', hidden_at = now()
 where id = (select max(id) from public.builds where author_id = :'S' and status = 'approved'
               and counter_id = (select id from public.counters where counter_champion = 'Quinn'));
select t.ok('S: 다시 하나를 숨기면 4개 → null', pg_temp.mp(:'S') is null);
-- 기준 바꾸기
update public.xp_rules set value = 4 where key = 'member_page_min_builds';
select t.ok('기준을 4로 바꾸면 S도 열림', (pg_temp.mp(:'S') ->> 'total')::int = 4);
update public.xp_rules set value = 6 where key = 'member_page_min_builds';
select t.ok('기준을 6으로 바꾸면 R도 닫힘', pg_temp.mp(:'R') is null);
update public.xp_rules set value = 5 where key = 'member_page_min_builds';

-- ===== 3. 닫히는 경우 (모두 null - 없는 사람과 구별 불가) =====
select t.ok('모양이 틀린 id·null·빈 문자열 → null', pg_temp.mp(null) is null and pg_temp.mp('') is null and pg_temp.mp('abc') is null
  and pg_temp.mp(:'R' || 'x') is null and pg_temp.mp(''' or 1=1 --') is null);
select t.ok('없는 사람 → null', pg_temp.mp('00000000-0000-0000-0000-00000000ffff') is null);
select t.ok('대문자 id도 같은 사람', pg_temp.mp(upper(:'R')) = pg_temp.mp(:'R'));
select t.ok('지금 정지 중(공개 5) → null', pg_temp.mp(:'X') is null);
select t.ok('장인(공개 5) → null (장인 페이지 public_profile은 그대로 열림)', pg_temp.mp(:'I') is null and public.public_profile(:'I') is not null);
select t.ok('비회원(공개 5) → null', pg_temp.mp(:'GU') is null);
select t.ok('닉네임 없음(공개 5) → null', pg_temp.mp(:'NN') is null);
select t.ok('운영자(공개 5) → null', pg_temp.mp(:'OP') is null);
select t.ok('감독관은 일반 사용자처럼 열림 (역할은 돌려주지 않음)', (pg_temp.mp(:'M') ->> 'total')::int = 5
  and not (pg_temp.mp(:'M')::text ~ 'moderator'));
select t.ok('탈퇴 전: W 열림', (pg_temp.mp(:'W') ->> 'total')::int = 5);
delete from auth.users where id = :'W';
select t.ok('탈퇴 → null (프로필이 지워짐, 빌드는 작성자 없이 남음)', pg_temp.mp(:'W') is null
  and exists (select 1 from public.builds where author_id is null and status = 'approved'));
-- 정지가 풀리거나 끝나면 다시 열림
update public.user_restrictions set lifted_at = now(), lifted_by = :'OP', lift_note = '검사' where user_id = :'X';
select t.ok('정지를 풀면 다시 열림', (pg_temp.mp(:'X') ->> 'total')::int = 5);
insert into public.user_restrictions (user_id, reason, days, starts_at, ends_at, created_by)
values (:'X', '검사', 1, now() - interval '2 days', now() - interval '1 day', :'OP');
select t.ok('기간이 끝난 정지 기록만 있으면 열림', (pg_temp.mp(:'X') ->> 'total')::int = 5);
insert into public.user_restrictions (user_id, reason, days, ends_at, created_by) values (:'X', '검사', 3, now() + interval '3 days', :'OP');
select t.ok('다시 정지되면 닫힘', pg_temp.mp(:'X') is null);

-- ===== 4. 부른 사람과 관계없이 같은 응답 =====
set role anon;
reset request.jwt.claim.sub;
select public.member_page(:'R') as ra \gset
select t.ok('비로그인: R 열림, S·X 닫힘', (:'ra'::jsonb ->> 'total')::int = 5 and public.member_page(:'S') is null and public.member_page(:'X') is null);
reset role;
set role authenticated;
set request.jwt.claim.sub = :'V';
select public.member_page(:'R') as rv \gset
set request.jwt.claim.sub = :'R';
select public.member_page(:'R') as rr \gset
select t.ok('본인이 불러도 숨김·대기 빌드는 안 나오고, 정지된 사람은 닫힘', (public.member_page(:'R') ->> 'total')::int = 5);
set request.jwt.claim.sub = :'X';
select t.ok('정지된 본인이 불러도 null', public.member_page(:'X') is null);
set request.jwt.claim.sub = :'OP';
select public.member_page(:'R') as ro \gset
select t.ok('운영자가 불러도 S(4개)·X(정지)·I(장인)는 null', public.member_page(:'S') is null and public.member_page(:'X') is null and public.member_page(:'I') is null);
reset role;
reset request.jwt.claim.sub;
select t.ok('비로그인·로그인·본인·운영자 응답이 모두 같음', :'ra'::jsonb = :'rv'::jsonb and :'rv'::jsonb = :'rr'::jsonb and :'rr'::jsonb = :'ro'::jsonb
  and :'ra'::jsonb = pg_temp.mp(:'R'));

-- ===== 5. 돌려주는 칸 =====
select t.ok('맨 위 칸: member·total·page·size·items', (select array_agg(k order by k) from jsonb_object_keys(:'r1'::jsonb) k) = array['items', 'member', 'page', 'size', 'total']);
select t.ok('member 칸: id·nickname·photo_path·main_title·titles 5개뿐', (select array_agg(k order by k) from jsonb_object_keys(:'r1'::jsonb -> 'member') k)
  = array['id', 'main_title', 'nickname', 'photo_path', 'titles']);
select t.ok('닉네임·id 값', :'r1'::jsonb -> 'member' ->> 'nickname' = '루키' and :'r1'::jsonb -> 'member' ->> 'id' = :'R');
select t.ok('일반 사용자 사진은 비어 있음(장인만 올릴 수 있음)', :'r1'::jsonb -> 'member' -> 'photo_path' = 'null'::jsonb);
select t.ok('이메일·가입일시·역할·레벨·경험치·운영 정보·제한·닉네임 상태·장인·링크·팔로우가 없음', not exists (
  select 1 from jsonb_object_keys(:'r1'::jsonb -> 'member') k
   where k in ('email', 'created_at', 'role', 'level', 'xp', 'is_guest', 'operator_mode', 'last_seen_at', 'influencer', 'influencer_at',
               'nickname_state', 'nickname_reset_at', 'links', 'follower_count', 'restriction', 'warnings'))
  and :'r1'::jsonb::text !~ 'r@x\.com'
  and not exists (select 1 from jsonb_each(:'r1'::jsonb -> 'member') e, public.profiles p
                   where p.id = :'R' and e.value in (to_jsonb(p.created_at), to_jsonb(p.last_seen_at), to_jsonb(p.level), to_jsonb(p.role)))
  and :'r1'::jsonb::text !~ 'follower');
select t.ok('빌드 카드는 장인 페이지(influencer_builds)와 같은 follow_build_card 모양', not exists (
  select 1 from jsonb_array_elements(:'r1'::jsonb -> 'items') e where e <> public.follow_build_card((e ->> 'id')::bigint)));
select t.ok('카드의 작성자: id·nickname·influencer(null)만', (select array_agg(k order by k) from jsonb_object_keys(:'r1'::jsonb -> 'items' -> 0 -> 'author') k)
  = array['id', 'influencer', 'nickname'] and :'r1'::jsonb -> 'items' -> 0 -> 'author' -> 'influencer' = 'null'::jsonb);

-- ===== 6. 칭호 =====
-- (검사용 도감 줄: 비밀 활동 칭호·숨긴 한정판·공개 한정판. 이 절에서는 보상 다시 계산이 일어나지 않는다)
insert into public.title_catalog (key, name, how_to, kind, equippable, sort_order, secret) values ('act_secret', '비밀', '비밀', 'activity', true, 70, true);
insert into public.title_catalog (key, name, how_to, kind, sort_order, hidden) values ('lim_hidden', '숨김', '숨김', 'limited', 1002, true);
insert into public.title_catalog (key, name, how_to, kind, sort_order) values ('lim_open', '공개', '공개', 'limited', 1003);
insert into public.user_titles (user_id, title_key) values (:'R', 'act_secret'), (:'R', 'lim_hidden'), (:'R', 'lim_open'), (:'R', 'general')
  on conflict do nothing;
update public.profiles set main_title = 'general' where id = :'R';
select t.ok('대표 칭호와 칭호 목록: 숨긴 도감 칭호·대표가 아닌 비밀 칭호 제외, 활동 → 한정판 순',
  pg_temp.mp(:'R') -> 'member' ->> 'main_title' = 'general'
  and (pg_temp.mp(:'R') -> 'member' -> 'titles') = (
    select jsonb_agg(ut.title_key order by case tc.kind when 'activity' then 1 else 3 end, tc.sort_order)
      from public.user_titles ut join public.title_catalog tc on tc.key = ut.title_key
     where ut.user_id = :'R' and ut.title_key not in ('act_secret', 'lim_hidden'))
  and pg_temp.mp(:'R') -> 'member' -> 'titles' ? 'lim_open' and pg_temp.mp(:'R') -> 'member' -> 'titles' ? 'general'
  and not (pg_temp.mp(:'R') -> 'member' -> 'titles' ? 'act_secret') and not (pg_temp.mp(:'R') -> 'member' -> 'titles' ? 'lim_hidden'));
-- 비밀 칭호를 대표로 달면 보인다 (public_title_info와 같은 규칙)
update public.profiles set main_title = 'act_secret' where id = :'R';
select t.ok('비밀 칭호는 대표로 달았을 때만 목록에 나옴 (숨긴 칭호는 여전히 없음)',
  pg_temp.mp(:'R') -> 'member' -> 'titles' ? 'act_secret' and not (pg_temp.mp(:'R') -> 'member' -> 'titles' ? 'lim_hidden')
  and pg_temp.mp(:'R') -> 'member' ->> 'main_title' = 'act_secret');
select t.ok('대표 칭호가 없으면 null, 목록은 가진 칭호를 도감 순으로', pg_temp.mp(:'M') -> 'member' -> 'titles' = (
    select coalesce(jsonb_agg(ut.title_key order by tc.sort_order), '[]'::jsonb)
      from public.user_titles ut join public.title_catalog tc on tc.key = ut.title_key where ut.user_id = :'M')
  and pg_temp.mp(:'M') -> 'member' -> 'main_title' = 'null'::jsonb);
update public.profiles set main_title = null where id = :'R';

-- ===== 7. 쪽 나누기 / 정렬 =====
select t.ok('최근 수정순 (1일 전 → 5일 전)', (select bool_and(a.t >= b.t) from (
  select (e ->> 'updated_at')::timestamptz as t, o from jsonb_array_elements(pg_temp.mp(:'R') -> 'items') with ordinality x(e, o)) a
  join (select (e ->> 'updated_at')::timestamptz as t, o from jsonb_array_elements(pg_temp.mp(:'R') -> 'items') with ordinality x(e, o)) b on b.o = a.o + 1));
begin;
alter table public.builds disable trigger builds_check_new;
select pg_temp.mk(:'R', 'approved', 20);
set constraints all immediate;
alter table public.builds enable trigger builds_check_new;
commit;
select t.ok('25개: 1쪽 20개, 2쪽 5개, 3쪽 0개, total 25, size 20',
  jsonb_array_length(pg_temp.mp(:'R', 1) -> 'items') = 20 and jsonb_array_length(pg_temp.mp(:'R', 2) -> 'items') = 5
  and jsonb_array_length(pg_temp.mp(:'R', 3) -> 'items') = 0 and (pg_temp.mp(:'R', 3) ->> 'total')::int = 25
  and (pg_temp.mp(:'R', 1) ->> 'size')::int = 20 and (pg_temp.mp(:'R', 2) ->> 'page')::int = 2);
select t.ok('1·2쪽 겹침·빠짐 없음', (
  select count(distinct e ->> 'id') = 25 from (
    select jsonb_array_elements(pg_temp.mp(:'R', 1) -> 'items') e union all select jsonb_array_elements(pg_temp.mp(:'R', 2) -> 'items')) x));
select t.ok('쪽 0·음수·null → 1쪽', pg_temp.mp(:'R', 0) = pg_temp.mp(:'R', 1) and pg_temp.mp(:'R', -3) = pg_temp.mp(:'R', 1)
  and pg_temp.mp(:'R', null) = pg_temp.mp(:'R', 1) and (pg_temp.mp(:'R', null) ->> 'page')::int = 1);

-- ===== 8. 데이터를 바꾸지 않음 / 기존 함수 그대로 =====
select pg_temp.fp() as fp1 \gset
select public.member_page(:'R'), public.member_page(:'S'), public.member_page(:'X');
select t.ok('부르기만 해서는 프로필·빌드·알림·칭호가 바뀌지 않음', pg_temp.fp() = :'fp1');
select t.ok('장인 페이지 함수는 일반 사용자에게 여전히 null (public_profile·influencer_builds 그대로)',
  public.public_profile(:'R') is null and public.influencer_builds(:'R', 1) is null);
