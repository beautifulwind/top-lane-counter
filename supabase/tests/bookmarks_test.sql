-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 066: 빌드 저장(북마크) - 표/RLS/권한, 로그인·닉네임 필요(비회원 계정은 닉네임 있으면 가능), 공개 빌드만, 중복 없음,
--      한도 500, 본인 것만 보임, 숨김 빌드·숨김 상대법은 목록에서 빠지고(hidden 수) 다시 공개되면 돌아옴, 해제는 숨겨져도 가능,
--      빌드 삭제·탈퇴하면 함께 지워짐, 기존 빌드·투표·수정 기록·알림은 저장·해제로 바뀌지 않음
\set ON_ERROR_STOP 1
\set QUIET 1
\set OP '00000000-0000-0000-0000-00000000000a'
\set U  '00000000-0000-0000-0000-00000000000d'
\set V  '00000000-0000-0000-0000-00000000000c'
\set N  '00000000-0000-0000-0000-00000000000e'
\set G  '00000000-0000-0000-0000-0000000000a1'
\set doc '{"summary":"요약","level_notes":{"1":"a","2":"b","3":"c","6":"d"},"lane_cautions":""}'
insert into auth.users (id, email) values (:'OP', 'op@x.com'), (:'U', 'u@x.com'), (:'V', 'v@x.com'), (:'N', 'n@x.com');
insert into auth.users (id, is_anonymous) values (:'G', true);
update public.profiles set nickname = '영자', role = 'admin' where id = :'OP';
update public.profiles set nickname = '유저' where id = :'U';
update public.profiles set nickname = '브이', influencer = 'pro', influencer_at = now() where id = :'V';
update public.profiles set nickname = '손님' where id = :'G';
update public.xp_rules set value = 0 where key in ('wiki_create_interval', 'build_edit_interval');
create temp table ids (k text primary key, v bigint);
grant all on ids to authenticated, anon;
create function pg_temp.id(p text) returns bigint language sql stable as $$ select v from ids where k = p $$;
select format('create function pg_temp.doc() returns jsonb language sql immutable as %L', format('select %L::jsonb', :'doc')) as mkdoc \gset
:mkdoc;
-- 기존 데이터 지문 (빌드·투표·수정 기록·알림) — 저장·해제 전후로 같아야 한다
create function pg_temp.fp() returns text language sql stable as $$
  select (select count(*) || '/' || coalesce(max(id), 0) || '/' || coalesce(sum(up_count), 0) || '/' || md5(coalesce(string_agg(b::text, '|' order by b.id), '')) from public.builds b)
    || '#' || (select count(*) || '/' || md5(coalesce(string_agg(v::text, '|' order by v.build_id, v.user_id::text), '')) from public.build_votes v)
    || '#' || (select count(*) || '/' || coalesce(max(id), 0) || '/' || md5(coalesce(string_agg(r::text, '|' order by r.id), '')) from public.build_revisions r)
    || '#' || (select count(*) || '/' || coalesce(max(id), 0) || '/' || md5(coalesce(string_agg(n::text, '|' order by n.id), '')) from public.notifications n) $$;
grant execute on all functions in schema pg_temp to anon, authenticated;

-- ===== 1. 표 / RLS / 권한 =====
select t.ok('RLS 켬 + 정책은 본인 읽기 하나', (select relrowsecurity from pg_class where oid = 'public.build_bookmarks'::regclass)
  and (select count(*) from pg_policy where polrelid = 'public.build_bookmarks'::regclass) = 1
  and (select polcmd from pg_policy where polrelid = 'public.build_bookmarks'::regclass) = 'r');
select t.ok('로그인: 읽기만 (넣기·고치기·지우기는 함수로만)', has_table_privilege('authenticated', 'public.build_bookmarks', 'select')
  and not has_table_privilege('authenticated', 'public.build_bookmarks', 'insert')
  and not has_table_privilege('authenticated', 'public.build_bookmarks', 'update')
  and not has_table_privilege('authenticated', 'public.build_bookmarks', 'delete'));
select t.ok('비로그인: 표·함수 권한 없음', not exists (
    select 1 from unnest(array['select', 'insert', 'update', 'delete']) p where has_table_privilege('anon', 'public.build_bookmarks', p))
  and not has_function_privilege('anon', 'public.save_build(bigint)', 'execute')
  and not has_function_privilege('anon', 'public.unsave_build(bigint)', 'execute')
  and not has_function_privilege('anon', 'public.my_saved_builds()', 'execute'));
select t.ok('중복 방지 기본 키 + 프로필·빌드 지우면 함께 (cascade 2개)',
  (select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'public.build_bookmarks'::regclass and contype = 'p') = 'PRIMARY KEY (user_id, build_id)'
  and (select count(*) from pg_constraint where conrelid = 'public.build_bookmarks'::regclass and contype = 'f' and confdeltype = 'c') = 2);
select t.ok('한도 500', save_build_limit() = 500);

-- 빌드 준비: 상대법 2개(다리우스 ← 가렌 / 케넨 ← 티모), 빌드 3개
set role authenticated;
set request.jwt.claim.sub = :'U';
select create_matchup('Darius', 'Garen', t.build() || pg_temp.doc()) as m \gset
insert into ids values ('m1', (:'m'::jsonb ->> 'counter_id')::bigint), ('b1', (:'m'::jsonb ->> 'build_id')::bigint);
insert into ids values ('b2', create_build(pg_temp.id('m1'), t.build(array['6631','3047','3071']) || pg_temp.doc()));
set request.jwt.claim.sub = :'V';
select create_matchup('Kennen', 'Teemo', t.build() || pg_temp.doc()) as m2 \gset
insert into ids values ('m2', (:'m2'::jsonb ->> 'counter_id')::bigint), ('b3', (:'m2'::jsonb ->> 'build_id')::bigint);
reset role;
select pg_temp.fp() as fp0 \gset

-- ===== 2. 누가 저장할 수 있나 =====
set role anon;
select t.fails('비로그인 저장 불가', format('select save_build(%s)', pg_temp.id('b1')), 'permission denied');
select t.fails('비로그인 목록 불가', 'select my_saved_builds()', 'permission denied');
select t.fails('비로그인 표 못 읽음', 'select * from build_bookmarks', 'permission denied');
reset role;
set role authenticated;
set request.jwt.claim.sub = :'N';
select t.fails('닉네임 전 저장 불가', format('select save_build(%s)', pg_temp.id('b1')), '닉네임을 정한 뒤에 저장할 수 있습니다');
select t.ok('닉네임 전 목록은 빈 목록', my_saved_builds() = '{"total":0,"hidden":0,"limit":500,"items":[]}'::jsonb);
set request.jwt.claim.sub = :'G';
select t.ok('비회원 계정(닉네임 있음) 저장 가능 — 나만 보는 기능', (save_build(pg_temp.id('b1')) ->> 'saved')::boolean);
set request.jwt.claim.sub = :'U';
select t.fails('표에 직접 넣기 불가', format('insert into build_bookmarks (user_id, build_id) values (%L, %s)', :'U', pg_temp.id('b3')), 'permission denied');
select t.fails('없는 빌드 저장 불가', 'select save_build(999999)', '공개된 빌드만 저장할 수 있습니다');

-- ===== 3. 저장·중복·해제·목록 =====
select t.ok('저장 → count 1', save_build(pg_temp.id('b3')) = '{"saved":true,"count":1}'::jsonb);
select t.ok('내 빌드도 저장 가능 → count 2', save_build(pg_temp.id('b1')) = '{"saved":true,"count":2}'::jsonb);
select t.ok('같은 빌드 다시 저장 = 그대로 성공 (개수 안 늘어남)', save_build(pg_temp.id('b3')) = '{"saved":true,"count":2}'::jsonb);
select t.ok('표에는 내 줄 2개만 보임 (비회원의 저장은 안 보임)', (select count(*) from build_bookmarks) = 2
  and not exists (select 1 from build_bookmarks where user_id <> :'U'));
select t.ok('목록: 최근 저장순, 줄 내용(상대법·장인·추천 수)',
  (select jsonb_agg(e ->> 'id' order by ord) from jsonb_array_elements(my_saved_builds() -> 'items') with ordinality x(e, ord))
    = jsonb_build_array(pg_temp.id('b1')::text, pg_temp.id('b3')::text)
  and (select e from jsonb_array_elements(my_saved_builds() -> 'items') e where (e ->> 'id')::bigint = pg_temp.id('b3'))
      @> '{"target":"Kennen","mine":"Teemo","influencer":"pro","up":0}'::jsonb
  and (my_saved_builds() ->> 'total')::int = 2 and (my_saved_builds() ->> 'hidden')::int = 0);
select t.ok('해제 → count 1, 다시 해제해도 그대로', unsave_build(pg_temp.id('b1')) = '{"saved":false,"count":1}'::jsonb
  and unsave_build(pg_temp.id('b1')) = '{"saved":false,"count":1}'::jsonb);
set request.jwt.claim.sub = :'V';
select t.ok('다른 사람 목록에는 내 저장이 안 나옴', (my_saved_builds() ->> 'total')::int = 0 and (select count(*) from build_bookmarks) = 0);
reset role;
select t.ok('저장·해제는 기존 빌드·투표·수정 기록·알림을 바꾸지 않음', pg_temp.fp() = :'fp0');

-- ===== 4. 숨김 빌드·숨김 상대법 =====
set role authenticated;
set request.jwt.claim.sub = :'U';
select save_build(pg_temp.id('b2')) \gset
reset role;
update public.builds set status = 'hidden', hide_reason = '검사' where id = pg_temp.id('b2');
update public.counters set status = 'hidden' where id = pg_temp.id('m2');
set role authenticated;
set request.jwt.claim.sub = :'U';
select t.ok('숨긴 빌드·숨긴 상대법의 빌드는 목록에서 빠지고 hidden 2', (my_saved_builds() ->> 'total')::int = 2
  and (my_saved_builds() ->> 'hidden')::int = 2 and jsonb_array_length(my_saved_builds() -> 'items') = 0);
select t.fails('숨긴 빌드 새로 저장 불가', format('select save_build(%s)', pg_temp.id('b2')), '공개된 빌드만 저장할 수 있습니다');
reset role;
update public.counters set status = 'approved' where id = pg_temp.id('m2');
set role authenticated;
set request.jwt.claim.sub = :'U';
select t.ok('상대법이 다시 공개되면 돌아옴', (my_saved_builds() ->> 'hidden')::int = 1 and jsonb_array_length(my_saved_builds() -> 'items') = 1);
select t.ok('숨겨진 빌드의 저장도 해제 가능', (unsave_build(pg_temp.id('b2')) ->> 'count')::int = 1);
select t.ok('해제하면 hidden 0', (my_saved_builds() ->> 'hidden')::int = 0);
reset role;
update public.builds set status = 'approved' where id = pg_temp.id('b2');

-- ===== 5. 한도 500 =====
-- 같은 상대법에 공개 빌드 499개를 더 만든다 (검사용: 트리거를 끄고 복사본으로 — 등록 규칙 검사는 다른 검사 파일이 한다)
set session_replication_role = replica;
insert into public.builds (counter_id, author_id, runes, summoner_spells, starting_items, core_items, max_skill, patch, status, seq)
  select counter_id, author_id, runes, summoner_spells, starting_items, core_items, max_skill, patch, status, 1000 + g
    from public.builds, generate_series(1, 499) g where id = pg_temp.id('b1');
set session_replication_role = origin;
insert into public.build_bookmarks (user_id, build_id)
  select :'U', b.id from public.builds b where b.seq > 1000 order by b.id;
select t.ok('검사 준비: 저장 500개', (select count(*) from public.build_bookmarks where user_id = :'U') = 500);
set role authenticated;
set request.jwt.claim.sub = :'U';
select t.ok('500개면 이미 저장한 빌드는 그대로 성공', (save_build(pg_temp.id('b3')) ->> 'count')::int = 500);
select t.fails('501번째 저장 거부', format('select save_build(%s)', pg_temp.id('b2')), '저장은 500개까지 할 수 있습니다. 안 보는 빌드를 해제해 주세요.');
select t.ok('하나 해제하면 다시 저장 가능', (unsave_build(pg_temp.id('b3')) ->> 'count')::int = 499
  and (save_build(pg_temp.id('b2')) ->> 'count')::int = 500);
reset role;

-- ===== 6. 빌드 삭제·탈퇴하면 함께 지워짐 =====
select count(*) as before_b2 from public.build_bookmarks where build_id = pg_temp.id('b2') \gset
delete from public.build_votes where build_id = pg_temp.id('b2');
delete from public.builds where id = pg_temp.id('b2');
select t.ok('빌드를 지우면 그 빌드의 저장도 지워짐', :before_b2 = 1
  and not exists (select 1 from public.build_bookmarks where build_id = pg_temp.id('b2')));
select t.ok('비회원 계정 저장 남아 있음 (탈퇴 전)', exists (select 1 from public.build_bookmarks where user_id = :'G'));
delete from auth.users where id = :'G';
select t.ok('탈퇴(계정 삭제)하면 저장도 지워짐', not exists (select 1 from public.build_bookmarks where user_id = :'G'));
