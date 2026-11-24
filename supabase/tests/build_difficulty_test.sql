-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것. (운영 DB 확인은 scripts/check_build_difficulty_after.sql)
-- 071 빌드 난이도 별점: 칸·제약(0.5~5.0, 0.5 단위, null 허용, 기존 빌드 null), set_build_difficulty 권한(로그인만·anon·public 없음),
--   작성자 본인만(숨긴 빌드도 본인은 됨, 남은 공개·숨김·없는 빌드 모두 같은 문장), 범위·단위 위반 거부(반올림 안 함), null로 비우기,
--   비로그인 거부, 068 활동 제한(첫 줄 검사), 표 직접 고치기 불가, 별점만 바꾸면 수정 시각·버전·수정 기록·알림·푸시 모두 그대로,
--   기존 읽기 함수 응답에 새 칸이 끼지 않음,
--   읽기 함수 build_difficulties(공개·비로그인·본인·운영자·감독관 범위 = builds 읽기 규칙 그대로, 숨김·대기·숨긴 상대법 빌드는 남에게 안 나옴,
--   비어 있는 별점은 키 없음, 빈 배열·null id, 200개 상한)
\set ON_ERROR_STOP 1
\set QUIET 1
\set OP '00000000-0000-0000-0000-00000000000a'
\set A  '00000000-0000-0000-0000-0000000000d1'
\set B  '00000000-0000-0000-0000-0000000000d2'
\set R  '00000000-0000-0000-0000-0000000000d3'
\set M  '00000000-0000-0000-0000-0000000000d4'
\set doc '{"summary":"요약","level_notes":{"1":"a","2":"b","3":"c","6":"d"},"lane_cautions":""}'
insert into auth.users (id, email) values (:'OP', 'op@x.com'), (:'A', 'a@x.com'), (:'B', 'b@x.com'), (:'R', 'r@x.com'), (:'M', 'm@x.com');
update public.profiles set nickname = '영자', role = 'admin' where id = :'OP';
update public.profiles set nickname = '에이' where id = :'A';
update public.profiles set nickname = '비이' where id = :'B';
update public.profiles set nickname = '제한맨' where id = :'R';
update public.profiles set nickname = '감독', role = 'moderator' where id = :'M';
update public.xp_rules set value = 0 where key in ('wiki_create_interval', 'build_edit_interval');
create temp table ids (k text primary key, v bigint);
grant all on ids to authenticated, anon;
create function pg_temp.id(p text) returns bigint language sql stable as $$ select v from ids where k = p $$;
select format('create function pg_temp.doc() returns jsonb language sql immutable as %L', format('select %L::jsonb', :'doc')) as mkdoc \gset
:mkdoc;
-- 별점 말고 바뀌면 안 되는 것: 빌드 줄(별점 칸 뺌) · 수정 기록 · 알림 · 푸시 호출
create function pg_temp.fp() returns text language sql volatile security definer as $$
  select (select md5(string_agg((to_jsonb(b) - 'difficulty')::text, '|' order by b.id)) from public.builds b)
    || '#' || (select count(*) || '·' || coalesce(max(id), 0) from public.build_revisions)
    || '#' || (select count(*) || '·' || coalesce(max(id), 0) from public.notifications)
    || '#' || (select count(*) from net.calls) $$;
create function pg_temp.dif(p bigint) returns numeric language sql volatile security definer as $$
  select difficulty from public.builds where id = p $$;
create function pg_temp.notes(p uuid) returns text language sql volatile security definer as $$
  select count(*) || ':' || coalesce(string_agg(message, '|' order by id), '') from public.notifications where user_id = p and kind = 'build_edited' $$;
grant execute on all functions in schema pg_temp to anon, authenticated;

-- ===== 1. 칸·제약 =====
select t.ok('칸 difficulty numeric(2,1), null 허용, 기본값 없음', (
  select data_type = 'numeric' and numeric_precision = 2 and numeric_scale = 1 and is_nullable = 'YES' and column_default is null
    from information_schema.columns where table_schema = 'public' and table_name = 'builds' and column_name = 'difficulty'));
select t.ok('기존 빌드는 모두 null (픽스처 빌드 2개)', (select count(*) from public.builds) >= 2
  and not exists (select 1 from public.builds where difficulty is not null));
select t.ok('제약 builds_difficulty_check 있음', exists (select 1 from pg_constraint where conname = 'builds_difficulty_check' and conrelid = 'public.builds'::regclass));
select t.fails('제약: 0.3 불가 (표에 직접)', $$update public.builds set difficulty = 0.3 where id = (select min(id) from public.builds)$$, 'builds_difficulty_check');
select t.fails('제약: 0.0 불가', $$update public.builds set difficulty = 0 where id = (select min(id) from public.builds)$$, 'builds_difficulty_check');
select t.fails('제약: 5.5 불가', $$update public.builds set difficulty = 5.5 where id = (select min(id) from public.builds)$$, 'builds_difficulty_check');
select t.fails('제약: 10 이상은 칸 크기에서 거부', $$update public.builds set difficulty = 10 where id = (select min(id) from public.builds)$$, 'numeric field overflow');

-- ===== 2. 함수 모양·권한 =====
select t.ok('함수: security definer, search_path "", volatile, jsonb', (
  select prosecdef and proconfig = array['search_path=""'] and provolatile = 'v' and prorettype = 'jsonb'::regtype
    from pg_proc where oid = 'public.set_build_difficulty(bigint, numeric)'::regprocedure));
select t.ok('권한: 로그인만 (anon·public 없음)', has_function_privilege('authenticated', 'public.set_build_difficulty(bigint, numeric)', 'execute')
  and not has_function_privilege('anon', 'public.set_build_difficulty(bigint, numeric)', 'execute')
  and not exists (select 1 from pg_proc, unnest(proacl) a where oid = 'public.set_build_difficulty(bigint, numeric)'::regprocedure and a::text like '=%'));
select t.ok('068 규칙: 선언부 첫 줄이 assert_can_write()', (select prosrc ~ '^\s*declare\s*\n\s*_can_write constant boolean := public\.assert_can_write\(\);'
  from pg_proc where oid = 'public.set_build_difficulty(bigint, numeric)'::regprocedure));
select t.ok('허용 목록(restriction_exemptions)에는 없음', not exists (select 1 from public.restriction_exemptions where name like 'set_build_difficulty%'));
select t.ok('같은 이름 함수는 하나뿐', (select count(*) from pg_proc where proname = 'set_build_difficulty') = 1);

-- ===== 3. 준비: A가 빌드 2개(하나는 운영자가 숨김), B가 빌드 1개, R이 빌드 1개 =====
set role authenticated;
set request.jwt.claim.sub = :'A';
select create_matchup('Darius', 'Garen', t.build() || pg_temp.doc()) as m \gset
insert into ids values ('m1', (:'m'::jsonb ->> 'counter_id')::bigint), ('bA', (:'m'::jsonb ->> 'build_id')::bigint);
insert into ids values ('bAh', create_build(pg_temp.id('m1'), t.build(array['6631','3047','3071']) || pg_temp.doc()));
set request.jwt.claim.sub = :'B';
insert into ids values ('bB', create_build(pg_temp.id('m1'), t.build(array['6631','3047','3075']) || pg_temp.doc()));
set request.jwt.claim.sub = :'R';
insert into ids values ('bR', create_build(pg_temp.id('m1'), t.build(array['6631','3047','3143']) || pg_temp.doc()));
set request.jwt.claim.sub = :'OP';
select hide_build(pg_temp.id('bAh'), '검사용 숨김');
reset role;
select t.ok('준비: 공개 빌드 3개 + 숨긴 빌드 1개, 모두 별점 없음', (select count(*) from public.builds where id in (pg_temp.id('bA'), pg_temp.id('bB'), pg_temp.id('bR')) and status = 'approved') = 3
  and (select status from public.builds where id = pg_temp.id('bAh')) = 'hidden'
  and (select count(*) from public.builds where difficulty is not null) = 0);
select pg_temp.fp() as fp0 \gset

-- ===== 4. 비로그인 =====
set role anon;
set request.jwt.claim.sub = '';
select t.fails('비로그인(anon): 실행 권한 없음', format($$select set_build_difficulty(%s, 3.0)$$, pg_temp.id('bA')), 'permission denied');
reset role;
set role authenticated;
set request.jwt.claim.sub = '';
select t.fails('로그인 역할이어도 사용자 없음: 로그인 필요', format($$select set_build_difficulty(%s, 3.0)$$, pg_temp.id('bA')), '로그인이 필요합니다');
reset role;
select t.ok('비로그인 시도는 아무것도 바꾸지 않음', pg_temp.fp() = :'fp0' and pg_temp.dif(pg_temp.id('bA')) is null);

-- ===== 5. 작성자 본인: 정하기·바꾸기·비우기, 숨긴 빌드도 됨 =====
set role authenticated;
set request.jwt.claim.sub = :'A';
select set_build_difficulty(pg_temp.id('bA'), 3.5) as r1 \gset
reset role;
select t.ok('본인: 3.5 저장, 돌려주는 값 { build_id, difficulty }', pg_temp.dif(pg_temp.id('bA')) = 3.5
  and :'r1'::jsonb = jsonb_build_object('build_id', pg_temp.id('bA'), 'difficulty', 3.5));
select t.ok('별점만 바꿈: 빌드의 다른 칸(수정 시각·버전 포함)·수정 기록·알림·푸시 그대로', pg_temp.fp() = :'fp0');
set role authenticated;
set request.jwt.claim.sub = :'A';
select set_build_difficulty(pg_temp.id('bA'), 0.5);
select t.ok('최솟값 0.5', pg_temp.dif(pg_temp.id('bA')) = 0.5);
select set_build_difficulty(pg_temp.id('bA'), 5);
select t.ok('최댓값 5 (= 5.0)', pg_temp.dif(pg_temp.id('bA')) = 5.0);
select set_build_difficulty(pg_temp.id('bA'), 4.50);
select t.ok('4.50도 4.5로 (같은 값)', pg_temp.dif(pg_temp.id('bA')) = 4.5);
select set_build_difficulty(pg_temp.id('bA'), 4.5) as same \gset
select t.ok('같은 값을 다시 보내도 성공', (:'same'::jsonb ->> 'difficulty')::numeric = 4.5);
select set_build_difficulty(pg_temp.id('bA'), null) as cleared \gset
select t.ok('null로 비우기', pg_temp.dif(pg_temp.id('bA')) is null and :'cleared'::jsonb = jsonb_build_object('build_id', pg_temp.id('bA'), 'difficulty', null));
select set_build_difficulty(pg_temp.id('bA'), 2.0);
select set_build_difficulty(pg_temp.id('bAh'), 1.5);
select t.ok('숨긴 빌드도 본인은 정할 수 있음', pg_temp.dif(pg_temp.id('bAh')) = 1.5);
reset role;
select t.ok('여러 번 바꿔도 별점 말고는 그대로 (수정 기록·알림·푸시 없음)', pg_temp.fp() = :'fp0');

-- ===== 6. 범위·단위 위반 (반올림하지 않고 거부, 값은 그대로) =====
set role authenticated;
set request.jwt.claim.sub = :'A';
select t.fails('0 불가', format($$select set_build_difficulty(%s, 0)$$, pg_temp.id('bA')), '0.5부터 5.0까지 0.5 단위');
select t.fails('0.3 불가 (0.5 단위 아님)', format($$select set_build_difficulty(%s, 0.3)$$, pg_temp.id('bA')), '0.5부터 5.0까지 0.5 단위');
select t.fails('0.25 불가 (반올림하지 않음)', format($$select set_build_difficulty(%s, 0.25)$$, pg_temp.id('bA')), '0.5부터 5.0까지 0.5 단위');
select t.fails('2.75 불가', format($$select set_build_difficulty(%s, 2.75)$$, pg_temp.id('bA')), '0.5부터 5.0까지 0.5 단위');
select t.fails('5.5 불가', format($$select set_build_difficulty(%s, 5.5)$$, pg_temp.id('bA')), '0.5부터 5.0까지 0.5 단위');
select t.fails('5.01 불가', format($$select set_build_difficulty(%s, 5.01)$$, pg_temp.id('bA')), '0.5부터 5.0까지 0.5 단위');
select t.fails('-1 불가', format($$select set_build_difficulty(%s, -1)$$, pg_temp.id('bA')), '0.5부터 5.0까지 0.5 단위');
select t.fails('100 불가', format($$select set_build_difficulty(%s, 100)$$, pg_temp.id('bA')), '0.5부터 5.0까지 0.5 단위');
reset role;
select t.ok('잘못된 값 뒤에도 2.0 그대로', pg_temp.dif(pg_temp.id('bA')) = 2.0);

-- ===== 7. 다른 사람: 공개·숨김·없는 빌드 모두 같은 문장 =====
select pg_temp.fp() || '#' || pg_temp.dif(pg_temp.id('bA')) || '#' || pg_temp.dif(pg_temp.id('bAh')) as fp1 \gset
set role authenticated;
set request.jwt.claim.sub = :'B';
select t.fails('남의 공개 빌드 불가', format($$select set_build_difficulty(%s, 3.0)$$, pg_temp.id('bA')), '내가 만든 빌드에만 난이도를 정할 수 있습니다');
select t.fails('남의 공개 빌드 비우기도 불가', format($$select set_build_difficulty(%s, null)$$, pg_temp.id('bA')), '내가 만든 빌드에만 난이도를 정할 수 있습니다');
select t.fails('남의 숨긴 빌드 불가 (같은 문장)', format($$select set_build_difficulty(%s, 3.0)$$, pg_temp.id('bAh')), '내가 만든 빌드에만 난이도를 정할 수 있습니다');
select t.fails('없는 빌드 (같은 문장)', $$select set_build_difficulty(999999, 3.0)$$, '내가 만든 빌드에만 난이도를 정할 수 있습니다');
select t.fails('빌드 id 없음 (같은 문장)', $$select set_build_difficulty(null, 3.0)$$, '내가 만든 빌드에만 난이도를 정할 수 있습니다');
select t.fails('작성자가 없는(탈퇴) 빌드 불가', $$select set_build_difficulty((select min(id) from public.builds), 3.0)$$, '내가 만든 빌드에만 난이도를 정할 수 있습니다');
set request.jwt.claim.sub = :'OP';
select t.fails('운영자도 남의 빌드는 불가', format($$select set_build_difficulty(%s, 3.0)$$, pg_temp.id('bA')), '내가 만든 빌드에만 난이도를 정할 수 있습니다');
-- 표를 직접 고치기·넣기 불가 (함수로만)
set request.jwt.claim.sub = :'A';
select t.fails('본인도 표를 직접 고칠 수 없음', format($$update public.builds set difficulty = 1.0 where id = %s$$, pg_temp.id('bA')), 'permission denied');
select t.fails('표에 직접 넣을 때 별점 칸 불가', format($$insert into public.builds (counter_id, author_id, runes, summoner_spells, starting_items, core_items, patch, status, difficulty)
  select counter_id, %L, runes, summoner_spells, starting_items, core_items, patch, 'pending', 1.0 from public.builds where id = %s$$, :'A', pg_temp.id('bA')), 'permission denied');
reset role;
select t.ok('거절된 시도는 아무것도 바꾸지 않음', pg_temp.fp() || '#' || pg_temp.dif(pg_temp.id('bA')) || '#' || pg_temp.dif(pg_temp.id('bAh')) = :'fp1');

-- ===== 8. 068 활동 제한: 첫 줄 검사 (입력 검사보다 먼저) =====
set role authenticated;
set request.jwt.claim.sub = :'OP';
select restrict_user(:'R', 7, '검사용 제한');
set request.jwt.claim.sub = :'R';
select t.fails('제한 중: 내 빌드도 불가 (제한 문장)', format($$select set_build_difficulty(%s, 3.0)$$, pg_temp.id('bR')), '활동이 제한된 상태입니다');
select t.fails('제한 중: 잘못된 값이어도 제한 문장이 먼저', format($$select set_build_difficulty(%s, 9.9)$$, pg_temp.id('bR')), '활동이 제한된 상태입니다');
select t.fails('제한 중: 비우기도 불가', format($$select set_build_difficulty(%s, null)$$, pg_temp.id('bR')), '활동이 제한된 상태입니다');
reset role;
select t.ok('제한 중 시도로 별점이 바뀌지 않음', pg_temp.dif(pg_temp.id('bR')) is null);
update public.user_restrictions set starts_at = now() - interval '8 days', ends_at = now() - interval '1 second' where user_id = :'R';  -- 시간이 흐른 셈
set role authenticated;
set request.jwt.claim.sub = :'R';
select set_build_difficulty(pg_temp.id('bR'), 4.0);
reset role;
select t.ok('기간이 지나면 다시 됨', pg_temp.dif(pg_temp.id('bR')) = 4.0);

-- ===== 9. 알림: 진짜 수정은 build_edited를 만들지만, 별점만 바꾸면 안 만든다 (10분 묶기 문장도 그대로) =====
set role authenticated;
set request.jwt.claim.sub = :'B';
select edit_build(pg_temp.id('bA'), (select version from public.builds where id = pg_temp.id('bA')), t.build() || pg_temp.doc() || '{"summary":"비이가 고침"}'::jsonb);
reset role;
select pg_temp.notes(:'A') as na \gset
select pg_temp.notes(:'OP') as nop \gset
select t.ok('대조: 남이 내용을 고치면 작성자·운영자에게 build_edited가 생긴다 (알림이 살아 있음)', :'na' like '1:%' and :'nop' like '1:%');
select (select count(*) from public.notifications) || '·' || (select count(*) from net.calls) || '·' || (select count(*) from public.build_revisions)
  || '·' || (select version || '·' || coalesce(updated_at::text, '') || '·' || coalesce(updated_by::text, '') || '·' || coalesce(edited_at::text, '') from public.builds where id = pg_temp.id('bA')) as before_rate \gset
set role authenticated;
set request.jwt.claim.sub = :'A';
select set_build_difficulty(pg_temp.id('bA'), 3.0);
select set_build_difficulty(pg_temp.id('bA'), 2.5);
select set_build_difficulty(pg_temp.id('bA'), null);
select set_build_difficulty(pg_temp.id('bA'), 1.0);
reset role;
select t.ok('별점만 4번 바꿈: 알림 수·푸시 호출·수정 기록·버전·수정 시각·수정한 사람 그대로',
  (select count(*) from public.notifications) || '·' || (select count(*) from net.calls) || '·' || (select count(*) from public.build_revisions)
  || '·' || (select version || '·' || coalesce(updated_at::text, '') || '·' || coalesce(updated_by::text, '') || '·' || coalesce(edited_at::text, '') from public.builds where id = pg_temp.id('bA'))
  = :'before_rate');
select t.ok('10분 안이어도 「(N번 수정)」 묶기 문장이 늘지 않음 (작성자·운영자 알림 그대로)', pg_temp.notes(:'A') = :'na' and pg_temp.notes(:'OP') = :'nop');

-- ===== 10. 기존 읽기 함수 응답 모양 그대로 (새 칸이 끼지 않음) =====
select t.ok('follow_build_card에 difficulty 없음', not (public.follow_build_card(pg_temp.id('bA')) ? 'difficulty'));
select t.ok('build_json(위키 스냅숏·서명)에 difficulty 없음', not ((select public.build_json(b) from public.builds b where id = pg_temp.id('bA')) ? 'difficulty'));
set role authenticated;
set request.jwt.claim.sub = :'A';
select save_build(pg_temp.id('bB')) ->> 'saved' as saved \gset
select t.ok('my_saved_builds 등 jsonb 함수는 칸을 골라 만든다 (내 저장 목록 줄에 difficulty 없음)',
  :'saved' = 'true' and jsonb_array_length(my_saved_builds() -> 'items') = 1
  and not ((my_saved_builds() -> 'items' -> 0) ? 'difficulty'));
select t.ok('influencer_builds의 카드에도 difficulty 없음 (follow_build_card 그대로)',
  not exists (select 1 from jsonb_array_elements(coalesce(influencer_builds(:'A', 1) -> 'items', '[]'::jsonb)) e where e ? 'difficulty'));
-- 표를 읽을 수 있는 사람에게는 칸이 읽힌다 (공개 빌드 = 누구나, 숨긴 빌드 = 본인·운영자)
select t.ok('본인: 공개·숨긴 내 빌드의 별점을 읽음', (select difficulty from public.builds where id = pg_temp.id('bA')) = 1.0
  and (select difficulty from public.builds where id = pg_temp.id('bAh')) = 1.5);
set request.jwt.claim.sub = :'B';
select t.ok('남: 공개 빌드 별점은 읽고, 숨긴 빌드는 줄 자체가 안 보임', (select difficulty from public.builds where id = pg_temp.id('bA')) = 1.0
  and not exists (select 1 from public.builds where id = pg_temp.id('bAh')));
reset role;
set role anon;
set request.jwt.claim.sub = '';
select t.ok('비로그인: 공개 빌드 별점 읽음', (select difficulty from public.builds where id = pg_temp.id('bA')) = 1.0);
reset role;

-- ===== 11. 읽기 함수 build_difficulties =====
select t.ok('읽기 함수: stable, security invoker(부른 사람 권한 = builds 읽기 규칙), search_path "", jsonb', (
  select provolatile = 's' and not prosecdef and proconfig = array['search_path=""'] and prorettype = 'jsonb'::regtype
    from pg_proc where oid = 'public.build_difficulties(bigint[])'::regprocedure));
select t.ok('권한: 비로그인·로그인 모두, public 없음', has_function_privilege('anon', 'public.build_difficulties(bigint[])', 'execute')
  and has_function_privilege('authenticated', 'public.build_difficulties(bigint[])', 'execute')
  and not exists (select 1 from pg_proc, unnest(proacl) a where oid = 'public.build_difficulties(bigint[])'::regprocedure and a::text like '=%'));
select t.ok('읽기 함수라 068 쓰기 함수 검사 대상이 아님 (쓰기 함수 101개·검사 30개 그대로)', (
  select count(*) filter (where p.proname = 'build_difficulties') = 0 and count(*) = 101
     and count(*) filter (where p.prosrc ~ '^\s*declare\s*\n\s*_can_write constant boolean := public\.assert_can_write\(\);'
                             or p.prosrc ~ '^\s*begin\s*\n\s*perform public\.assert_can_write\(\);') = 30
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f' and p.provolatile = 'v' and p.prorettype <> 'trigger'::regtype
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))));
-- 준비: A의 승인 대기 빌드(2.5), B의 숨긴 상대법 밑 빌드(3.0). 지금: bA 1.0 공개 · bAh 1.5 숨김 · bR 4.0 공개 · bB 공개(별점 없음)
set role authenticated;
set request.jwt.claim.sub = :'A';
insert into ids values ('bAp', create_build(pg_temp.id('m1'), t.build(array['6631','3047','3742']) || pg_temp.doc()));
select set_build_difficulty(pg_temp.id('bAp'), 2.5);
set request.jwt.claim.sub = :'B';
select create_matchup('Darius', 'Sett', t.build() || pg_temp.doc()) as m2 \gset
insert into ids values ('m2', (:'m2'::jsonb ->> 'counter_id')::bigint), ('bB2', (:'m2'::jsonb ->> 'build_id')::bigint);
select set_build_difficulty(pg_temp.id('bB2'), 3.0);
reset role;
update public.builds set status = 'pending', reviewed_by = null, reviewed_at = null where id = pg_temp.id('bAp');
update public.counters set status = 'hidden' where id = pg_temp.id('m2');
select t.ok('준비: 대기 빌드 1개 · 숨긴 상대법 밑 빌드 1개', (select status from public.builds where id = pg_temp.id('bAp')) = 'pending'
  and (select c.status from public.builds b join public.counters c on c.id = b.counter_id where b.id = pg_temp.id('bB2')) = 'hidden');
-- 부를 id 목록 (탈퇴한 작성자의 픽스처 빌드·없는 id·null 포함) / 같은 사람이 표를 직접 읽은 값
create function pg_temp.all_ids() returns bigint[] language sql stable as $$
  select array[pg_temp.id('bA'), pg_temp.id('bAh'), pg_temp.id('bAp'), pg_temp.id('bB'), pg_temp.id('bB2'), pg_temp.id('bR'),
               (select min(id) from public.builds), 999999, null] $$;
create function pg_temp.direct() returns jsonb language sql stable as $$
  select coalesce(jsonb_object_agg(id::text, difficulty), '{}'::jsonb) from public.builds where id = any (pg_temp.all_ids()) and difficulty is not null $$;
create function pg_temp.expect(variadic ks text[]) returns jsonb language sql stable as $$
  select coalesce(jsonb_object_agg(pg_temp.id(k)::text, (select difficulty from public.builds where id = pg_temp.id(k))), '{}'::jsonb) from unnest(ks) k $$;
grant execute on all functions in schema pg_temp to anon, authenticated;
select pg_temp.expect('bA', 'bR') as e_public, pg_temp.expect('bA', 'bAh', 'bAp', 'bR') as e_a, pg_temp.expect('bA', 'bR', 'bB2') as e_b,
       pg_temp.expect('bA', 'bAh', 'bAp', 'bB2', 'bR') as e_op, pg_temp.expect('bA', 'bAh', 'bR') as e_mod \gset
select t.ok('준비: 기대값 (공개 = 1.0·4.0, 운영자 = 5개)', :'e_public'::jsonb = jsonb_build_object(pg_temp.id('bA')::text, 1.0, pg_temp.id('bR')::text, 4.0)
  and (select count(*) from jsonb_object_keys(:'e_op'::jsonb)) = 5);

set role anon;
set request.jwt.claim.sub = '';
select t.ok('비로그인: 공개 빌드 별점만 (숨김·대기·숨긴 상대법·별점 없음·없는 id·null은 키 없음)', build_difficulties(pg_temp.all_ids()) = :'e_public'::jsonb);
select t.ok('비로그인: 표를 직접 읽은 값과 같음', build_difficulties(pg_temp.all_ids()) = pg_temp.direct());
select t.ok('값은 숫자 (1.0 → 1.0)', (build_difficulties(array[pg_temp.id('bA')]) -> pg_temp.id('bA')::text) = '1.0'::jsonb
  and jsonb_typeof(build_difficulties(array[pg_temp.id('bA')]) -> pg_temp.id('bA')::text) = 'number');
reset role;
set role authenticated;
set request.jwt.claim.sub = :'B';
select t.ok('남(B): 공개 빌드 + 내 빌드(숨긴 상대법 밑이어도)만, A의 숨김·대기 빌드 별점은 안 나옴', build_difficulties(pg_temp.all_ids()) = :'e_b'::jsonb
  and not (build_difficulties(pg_temp.all_ids()) ?| array[pg_temp.id('bAh')::text, pg_temp.id('bAp')::text]));
select t.ok('남(B): 숨김·대기 빌드 id만 넣어도 {}', build_difficulties(array[pg_temp.id('bAh'), pg_temp.id('bAp')]) = '{}'::jsonb);
select t.ok('남(B): 표를 직접 읽은 값과 같음', build_difficulties(pg_temp.all_ids()) = pg_temp.direct());
set request.jwt.claim.sub = :'A';
select t.ok('본인(A): 내 숨긴 빌드·대기 빌드 별점도 나옴', build_difficulties(pg_temp.all_ids()) = :'e_a'::jsonb);
select t.ok('본인(A): 남의 숨긴 상대법 밑 빌드는 안 나옴', not (build_difficulties(pg_temp.all_ids()) ? pg_temp.id('bB2')::text));
set request.jwt.claim.sub = :'OP';
select t.ok('운영자: 숨김·대기·숨긴 상대법 빌드까지 모두', build_difficulties(pg_temp.all_ids()) = :'e_op'::jsonb);
set request.jwt.claim.sub = :'M';
select t.ok('감독관: builds 읽기 규칙대로 (처리할 수 있는 작성자의 숨긴 빌드는 보임, 대기·숨긴 상대법 밑 빌드는 안 보임)',
  build_difficulties(pg_temp.all_ids()) = :'e_mod'::jsonb and build_difficulties(pg_temp.all_ids()) = pg_temp.direct());
reset role;
update public.profiles set operator_mode = false where id = :'OP';
set role authenticated;
set request.jwt.claim.sub = :'OP';
select t.ok('운영자 모드를 끄면 일반 회원과 같은 범위 (is_admin과 같음)', build_difficulties(pg_temp.all_ids()) = :'e_public'::jsonb);
reset role;
update public.profiles set operator_mode = true where id = :'OP';

-- 별점 없음·빈 입력·null·상한
set role anon;
set request.jwt.claim.sub = '';
select t.ok('비어 있는 별점은 키 없음 (bB 하나만 → {})', build_difficulties(array[pg_temp.id('bB')]) = '{}'::jsonb);
select t.ok('빈 배열 → {}', build_difficulties('{}'::bigint[]) = '{}'::jsonb);
select t.ok('null → {}', build_difficulties(null) = '{}'::jsonb);
select t.ok('null만 든 배열 → {}', build_difficulties(array[null, null]::bigint[]) = '{}'::jsonb);
select t.ok('null id는 무시하고 나머지는 읽음', build_difficulties(array[null, pg_temp.id('bA'), null]) = jsonb_build_object(pg_temp.id('bA')::text, 1.0));
select t.ok('같은 id가 여러 번 있어도 키 하나', build_difficulties(array[pg_temp.id('bA'), pg_temp.id('bA')]) = jsonb_build_object(pg_temp.id('bA')::text, 1.0));
select t.ok('200개는 됨', build_difficulties(array_append(array(select g::bigint from generate_series(1000001, 1000199) g), pg_temp.id('bA')))
  = jsonb_build_object(pg_temp.id('bA')::text, 1.0));
select t.ok('null은 개수에 안 셈 (200개 + null 5개)', build_difficulties(array(select g::bigint from generate_series(1000001, 1000200) g) || array[null, null, null, null, null]::bigint[]) = '{}'::jsonb);
select t.fails('201개는 오류', $$select build_difficulties(array(select g::bigint from generate_series(1, 201) g))$$, '한 번에 200개까지');
reset role;
