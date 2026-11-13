-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 050: 장인 팔로우 (표/RLS, 권한 - 게스트 허용/비로그인 거부, 자기 자신/장인 아닌 회원 거부, 호출 횟수 제한,
--      팔로워 목록 열람 제한, 검색/공개 빌드, 모아 보기, [+] 상태, 알림 대상/묶기/나눠 보내기, 푸시 묶음,
--      해제 시 삭제, 탈퇴/게스트 정리 시 삭제, 운영자 장인 목록)
\set ON_ERROR_STOP 1
\set QUIET 1
\set OP  '00000000-0000-0000-0000-00000000000a'
\set MOD '00000000-0000-0000-0000-00000000000b'
\set U   '00000000-0000-0000-0000-00000000000d'
\set V   '00000000-0000-0000-0000-00000000000c'
\set W   '00000000-0000-0000-0000-00000000000f'
\set X   '00000000-0000-0000-0000-000000000012'
\set Z   '00000000-0000-0000-0000-000000000013'
\set GU  '00000000-0000-0000-0000-000000000010'
\set GN  '00000000-0000-0000-0000-000000000011'
\set doc '{"summary":"요약","level_notes":{"1":"a","2":"b","3":"c","6":"d"},"lane_cautions":""}'
insert into auth.users (id, email) values (:'OP', 'op@x.com'), (:'MOD', 'm@x.com'), (:'U', 'u@x.com'), (:'V', 'v@x.com'),
  (:'W', 'w@x.com'), (:'X', 'x@x.com'), (:'Z', 'z@x.com');
insert into auth.users (id, email, is_anonymous) values (:'GU', null, true), (:'GN', null, true);
update public.profiles set nickname = '영자', role = 'admin' where id = :'OP';
update public.profiles set nickname = '감독', role = 'moderator' where id = :'MOD';
update public.profiles set nickname = '유저' where id = :'U';
update public.profiles set nickname = 'Fakeman' where id = :'V';
update public.profiles set nickname = 'Faker', influencer = 'pro', influencer_at = now() - interval '2 days' where id = :'W';
update public.profiles set nickname = '쵸비' where id = :'X';
update public.profiles set nickname = '제트', influencer = 'creator', influencer_at = now() - interval '1 day' where id = :'Z';
update public.profiles set nickname = '손님' where id = :'GU';
-- GN: 닉네임을 아직 정하지 않은 게스트
update public.xp_rules set value = 0 where key in ('approval_on', 'wiki_create_interval', 'build_edit_interval');
delete from notifications;
delete from moderation_log;
create temp table ids (k text primary key, v bigint);
grant all on ids to authenticated, anon;
-- X는 운영자가 직접 지정 (049 - admin_influencer_list의 direct 확인용)
set role authenticated;
set request.jwt.claim.sub = :'OP';
select grant_influencer(:'X', 'creator', '직접 확인');
reset role;
delete from notifications;

-- ===== 1. 표 / RLS (로그인/비로그인 모두 직접 읽기/쓰기 불가) =====
select t.ok('새 표 3개 RLS 켜짐', (select bool_and(relrowsecurity) from pg_class
  where oid in ('public.influencer_follows'::regclass, 'public.follow_rate'::regclass, 'public.follow_notify_queue'::regclass)));
select t.ok('새 표 권한 없음 (anon/authenticated 읽기/넣기/고치기/지우기)', not exists (
  select 1 from unnest(array['public.influencer_follows', 'public.follow_rate', 'public.follow_notify_queue']) tb,
                unnest(array['anon', 'authenticated']) r, unnest(array['select', 'insert', 'update', 'delete']) p
   where has_table_privilege(r, tb, p)));
set role authenticated;
set request.jwt.claim.sub = :'U';
select t.fails('로그인 사용자 표 직접 읽기 거부', 'select * from influencer_follows', 'permission denied');
select t.fails('로그인 사용자 표 직접 넣기 거부', format('insert into influencer_follows (follower_id, influencer_id) values (%L, %L)', :'U', :'W'), 'permission denied');
select t.fails('호출 횟수 표 직접 고치기 거부', 'update follow_rate set n = 0', 'permission denied');
select t.fails('대기 줄 직접 읽기 거부', 'select * from follow_notify_queue', 'permission denied');
reset role;
set role anon;
select t.fails('비로그인 표 직접 읽기 거부', 'select * from influencer_follows', 'permission denied');
reset role;
select t.ok('알림 종류에 followed_build_created', (select pg_get_constraintdef(oid) like '%followed_build_created%' from pg_constraint
  where conname = 'notifications_kind_check' and conrelid = 'public.notifications'::regclass));
select t.ok('있던 알림 종류 그대로 (link_removed/report_received/influencer_applied)', (select pg_get_constraintdef(oid) like '%link_removed%'
  and pg_get_constraintdef(oid) like '%report_received%' and pg_get_constraintdef(oid) like '%influencer_applied%' from pg_constraint
  where conname = 'notifications_kind_check' and conrelid = 'public.notifications'::regclass));
select t.ok('설정값 늘지 않음 (050은 xp_rules에 더하지 않음)', not exists (select 1 from xp_rules where note like '%(050)%'));

-- ===== 2. 함수 권한 =====
set role anon;
reset request.jwt.claim.sub;
select t.fails('비로그인 팔로우 거부', format('select follow_influencer(%L)', :'W'), 'permission denied');
select t.fails('비로그인 팔로우 취소 거부', format('select unfollow_influencer(%L)', :'W'), 'permission denied');
select t.fails('비로그인 팔로워 목록 거부', format('select influencer_followers(%L)', :'W'), 'permission denied');
select t.fails('비로그인 내 팔로우 목록 거부', 'select my_following()', 'permission denied');
select t.fails('비로그인 모아 보기 거부', 'select followed_builds()', 'permission denied');
select t.fails('비로그인 [+] 상태 거부', format('select follow_status(array[%L]::uuid[])', :'W'), 'permission denied');
select t.fails('비로그인 운영자 장인 목록 거부', 'select admin_influencer_list()', 'permission denied');
select t.ok('비로그인 장인 검색 가능', (search_influencers('fak') ->> 'total')::int = 1);
select t.ok('비로그인 장인 공개 빌드 가능', influencer_builds(:'W') is not null);
select t.ok('비로그인 팔로워 수 가능', influencer_follower_count(:'W') = 0);
reset role;
set role authenticated;
set request.jwt.claim.sub = :'U';
select t.fails('안쪽 함수 follow_influencer_unchecked 직접 못 부름', format('select follow_influencer_unchecked(%L, %L)', :'U', :'W'), 'permission denied');
select t.fails('안쪽 함수 unfollow_influencer_unchecked 직접 못 부름', format('select unfollow_influencer_unchecked(%L, %L)', :'U', :'W'), 'permission denied');
select t.fails('안쪽 함수 influencer_followers_unchecked 직접 못 부름', format('select influencer_followers_unchecked(%L, 1)', :'W'), 'permission denied');
select t.fails('안쪽 함수 my_following_unchecked 직접 못 부름', format('select my_following_unchecked(%L, 1)', :'U'), 'permission denied');
select t.fails('안쪽 함수 followed_builds_unchecked 직접 못 부름', format('select followed_builds_unchecked(%L, 1)', :'U'), 'permission denied');
select t.fails('안쪽 함수 follow_status_unchecked 직접 못 부름', format('select follow_status_unchecked(%L, null)', :'U'), 'permission denied');
select t.fails('안쪽 함수 admin_influencer_list_unchecked 직접 못 부름', 'select admin_influencer_list_unchecked(1, 20)', 'permission denied');
select t.fails('알림 나눠 보내기 직접 못 부름', 'select follow_notify_dispatch()', 'permission denied');
select t.fails('도우미 follow_build_card 직접 못 부름', 'select follow_build_card(1)', 'permission denied');
select t.fails('도우미 follow_throttle 직접 못 부름', format('select follow_throttle(%L)', :'U'), 'permission denied');
reset role;
select t.ok('비로그인이 부를 수 있는 050 함수는 검색/공개 빌드/팔로워 수 3개뿐', (
  select array_agg(p.proname::text order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute')
     and p.proname in ('search_influencers', 'influencer_builds', 'influencer_follower_count', 'follow_influencer', 'unfollow_influencer',
                       'influencer_followers', 'my_following', 'followed_builds', 'follow_status', 'admin_influencer_list',
                       'follow_notify_dispatch', 'follow_build_card', 'follow_throttle', 'follow_queue_on_build', 'follows_on_influencer_end')
      or (n.nspname = 'public' and p.proname like '%follow%unchecked' and has_function_privilege('anon', p.oid, 'execute'))
) = array['influencer_builds', 'influencer_follower_count', 'search_influencers']);
select t.ok('로그인 사용자가 부를 수 있는 050 함수 목록', (
  select array_agg(p.proname::text order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and has_function_privilege('authenticated', p.oid, 'execute')
     and (p.proname in ('search_influencers', 'influencer_builds', 'influencer_follower_count', 'follow_influencer', 'unfollow_influencer',
                       'influencer_followers', 'my_following', 'followed_builds', 'follow_status', 'admin_influencer_list',
                       'follow_notify_dispatch', 'follow_build_card', 'follow_throttle', 'follow_queue_on_build', 'follows_on_influencer_end')
          or p.proname like '%follow%unchecked' or p.proname = 'admin_influencer_list_unchecked')
) = array['admin_influencer_list', 'follow_influencer', 'follow_status', 'followed_builds', 'influencer_builds', 'influencer_follower_count',
          'influencer_followers', 'my_following', 'search_influencers', 'unfollow_influencer']);

-- ===== 3. 팔로우 규칙 =====
set role authenticated;
set request.jwt.claim.sub = :'U';
select t.ok('정식 회원 팔로우', follow_influencer(:'W') = '{"following": true, "follower_count": 1}'::jsonb);
select t.ok('이미 팔로우 중이면 그대로 (오류 아님, 수 그대로)', (follow_influencer(:'W') ->> 'follower_count')::int = 1);
select t.fails('장인 아닌 회원 거부', format('select follow_influencer(%L)', :'V'), '인증된 장인만 팔로우할 수 있습니다');
select t.fails('운영자(장인 아님) 거부', format('select follow_influencer(%L)', :'OP'), '인증된 장인만 팔로우할 수 있습니다');
select t.fails('없는 회원 거부', 'select follow_influencer(''00000000-0000-0000-0000-0000000000ff'')', '인증된 장인만 팔로우할 수 있습니다');
select t.fails('null 거부', 'select follow_influencer(null)', '인증된 장인만 팔로우할 수 있습니다');
select follow_influencer(:'X');
set request.jwt.claim.sub = :'W';
select t.fails('자기 자신 거부', format('select follow_influencer(%L)', :'W'), '나 자신은 팔로우할 수 없습니다');
select t.ok('장인도 다른 장인을 팔로우', (follow_influencer(:'X') ->> 'following')::boolean);
set request.jwt.claim.sub = :'GU';
select t.ok('게스트(비회원) 팔로우 허용', (follow_influencer(:'W') ->> 'follower_count')::int = 2);
set request.jwt.claim.sub = :'GN';
select t.ok('닉네임 없는 게스트도 팔로우 허용', (follow_influencer(:'W') ->> 'follower_count')::int = 3);
set request.jwt.claim.sub = :'OP';
select t.ok('운영자도 팔로우 (로그인한 모든 사용자)', (follow_influencer(:'W') ->> 'follower_count')::int = 4);
reset role;
select t.ok('자기 자신 팔로우는 표 검사로도 막힘', exists (select 1 from pg_constraint where conname = 'influencer_follows_not_self'));
select t.fails('표 검사: 자기 자신 줄 거부', format('insert into influencer_follows (follower_id, influencer_id) values (%L, %L)', :'W', :'W'), 'influencer_follows_not_self');

set role authenticated;
set request.jwt.claim.sub = :'U';
select t.ok('[+] 상태: 팔로우 중 true / 아님 false / 장인 아님 false', follow_status(array[:'W', :'Z', :'V']::uuid[])
  = jsonb_build_object(:'W', true, :'Z', false, :'V', false));
select t.ok('[+] 상태: 빈 목록/null은 {}', follow_status('{}'::uuid[]) = '{}'::jsonb and follow_status(null) = '{}'::jsonb);
select t.ok('[+] 상태: 같은 id 여러 번이어도 한 칸', follow_status(array[:'W', :'W']::uuid[]) = jsonb_build_object(:'W', true));
select t.fails('[+] 상태: 101명 거부', 'select follow_status(array(select gen_random_uuid() from generate_series(1, 101)))', '100명까지');
select t.ok('팔로우 취소', unfollow_influencer(:'X') = jsonb_build_object('following', false, 'follower_count', 1));
select t.ok('팔로우 안 한 장인 취소도 오류 아님', (unfollow_influencer(:'Z') ->> 'follower_count')::int = 0);
select t.ok('내 팔로우 목록 (W만)', (select (j ->> 'total')::int = 1 and j -> 'items' -> 0 ->> 'id' = :'W' and j -> 'items' -> 0 ->> 'nickname' = 'Faker'
  and (j -> 'items' -> 0 ->> 'follower_count')::int = 4 and j -> 'items' -> 0 ? 'followed_at' from (select my_following() as j) s));
reset role;

-- ===== 4. 호출 횟수 제한 (1분에 30번) =====
delete from follow_rate;
set role authenticated;
set request.jwt.claim.sub = :'U';
do $$ begin
  for i in 1 .. 15 loop
    perform public.follow_influencer('00000000-0000-0000-0000-000000000013');
    perform public.unfollow_influencer('00000000-0000-0000-0000-000000000013');
  end loop;
end $$;
select t.fails('31번째 호출 거부', format('select follow_influencer(%L)', :'Z'), '너무 자주 눌렀습니다');
select t.fails('취소도 함께 셈', format('select unfollow_influencer(%L)', :'Z'), '너무 자주 눌렀습니다');
set request.jwt.claim.sub = :'GU';
select t.ok('다른 사람은 그대로 가능', (follow_status(array[:'W']::uuid[]) ->> :'W')::boolean and (follow_influencer(:'W') ->> 'following')::boolean);
reset role;
update follow_rate set window_start = now() - interval '61 seconds' where user_id = :'U';
set role authenticated;
set request.jwt.claim.sub = :'U';
select t.ok('1분이 지나면 다시 가능', (follow_influencer(:'W') ->> 'following')::boolean);
reset role;
delete from follow_rate;

-- ===== 5. 팔로워 목록 (로그인한 사용자만, 20개씩) =====
insert into auth.users (id, email) select ('00000000-0000-0000-0000-0000000001' || lpad(i::text, 2, '0'))::uuid, 'f' || i || '@x.com'
  from generate_series(1, 22) i;
update profiles set nickname = '팔로워' || lpad(right(id::text, 2), 2, '0') where id::text like '00000000-0000-0000-0000-0000000001%';
insert into influencer_follows (follower_id, influencer_id, created_at)
  select id, :'W', now() - interval '1 hour' - (right(id::text, 2)::int * interval '1 minute')
    from profiles where id::text like '00000000-0000-0000-0000-0000000001%';
set role authenticated;
set request.jwt.claim.sub = :'GU';
select influencer_followers(:'W') as fl \gset
select t.ok('게스트도 팔로워 목록 열람', (:'fl'::jsonb ->> 'total')::int = 26 and (:'fl'::jsonb ->> 'follower_count')::int = 26);
select t.ok('20개씩', jsonb_array_length(:'fl'::jsonb -> 'items') = 20 and (:'fl'::jsonb ->> 'size')::int = 20);
select t.ok('2쪽은 나머지 6개', jsonb_array_length(influencer_followers(:'W', 2) -> 'items') = 6);
select t.ok('최근 팔로우 순 (맨 위는 방금 팔로우한 사람)', (:'fl'::jsonb -> 'items' -> 25) is null
  and (:'fl'::jsonb -> 'items' -> 0 ->> 'followed_at')::timestamptz > now() - interval '30 minutes');
select t.ok('팔로워 한 줄: 닉네임/팔로우한 날 (역할/레벨/이메일 없음)', (select bool_and(i ? 'nickname' and i ? 'followed_at'
  and not (i ? 'role') and not (i ? 'level') and not (i ? 'email') and not (i ? 'main_title')) from jsonb_array_elements(:'fl'::jsonb -> 'items') i));
select t.ok('닉네임 없는 게스트는 nickname null', exists (select 1 from jsonb_array_elements(:'fl'::jsonb -> 'items') i
  where i ->> 'id' = :'GN' and i -> 'nickname' = 'null'::jsonb));
select t.fails('장인 아닌 회원의 팔로워 목록', format('select influencer_followers(%L)', :'V'), '인증된 장인을 찾지 못했습니다');
set request.jwt.claim.sub = :'U';
select t.ok('정식 회원도 열람', (influencer_followers(:'W') ->> 'total')::int = 26);
reset role;
set role anon;
select t.ok('비로그인은 수만 (26)', influencer_follower_count(:'W') = 26);
select t.ok('팔로워 수: 장인 아님/없는 id/모양 틀림은 null', influencer_follower_count(:'V') is null
  and influencer_follower_count('00000000-0000-0000-0000-0000000000ff') is null and influencer_follower_count('abc') is null
  and influencer_follower_count(null) is null);
reset role;

-- ===== 6. 장인 검색 (비로그인 가능, 인증된 장인만, 부분 일치) =====
set role anon;
select search_influencers('fak') as s \gset
select t.ok('부분 일치 + 대소문자 무시, 장인 아닌 Fakeman 제외', (:'s'::jsonb ->> 'total')::int = 1 and :'s'::jsonb -> 'items' -> 0 ->> 'nickname' = 'Faker');
select t.ok('검색 결과: id/닉네임/유형/팔로워 수/빌드 수만 (이메일/라이엇/역할 없음)', (select bool_and(
  (select array_agg(k order by k) from jsonb_object_keys(i) k) = array['build_count', 'follower_count', 'id', 'influencer', 'nickname'])
  from jsonb_array_elements(:'s'::jsonb -> 'items') i) and (:'s'::jsonb -> 'items' -> 0 ->> 'follower_count')::int = 26);
select t.ok('한 글자 검색', (search_influencers('쵸') ->> 'total')::int = 1);
select t.ok('비슷한 글자 열쇠로도 찾음 (FAKER, F a k e r)', (search_influencers('FAKER') ->> 'total')::int = 1 and (search_influencers('F a k e r') ->> 'total')::int = 1);
select t.ok('%, _ 는 글자 그대로 (아무거나 아님)', (search_influencers('%') ->> 'total')::int = 0 and (search_influencers('_') ->> 'total')::int = 0);
select t.ok('장인 아닌 회원 닉네임으로는 안 나옴', (search_influencers('유저') ->> 'total')::int = 0 and (search_influencers('영자') ->> 'total')::int = 0);
select t.fails('빈 검색어 거부', 'select search_influencers(''  '')', '한 글자 이상');
select t.fails('null 거부', 'select search_influencers(null)', '한 글자 이상');
select t.fails('21자 거부', format('select search_influencers(%L)', repeat('가', 21)), '20자 이하');
reset role;
-- 25명 장인 -> 20개씩
insert into auth.users (id, email) select ('00000000-0000-0000-0000-0000000002' || lpad(i::text, 2, '0'))::uuid, 'i' || i || '@x.com'
  from generate_series(1, 25) i;
update profiles set nickname = '검색장' || lpad(right(id::text, 2), 2, '0'), influencer = 'creator', influencer_at = now()
 where id::text like '00000000-0000-0000-0000-0000000002%';
set role anon;
select t.ok('검색 20개씩 / 2쪽 5개', (search_influencers('검색장') ->> 'total')::int = 25
  and jsonb_array_length(search_influencers('검색장') -> 'items') = 20 and jsonb_array_length(search_influencers('검색장', 2) -> 'items') = 5);
select t.ok('같은 닉네임이 맨 위', search_influencers('검색장07') -> 'items' -> 0 ->> 'nickname' = '검색장07');
reset role;
update profiles set influencer = null, influencer_at = null where id::text like '00000000-0000-0000-0000-0000000002%';

-- ===== 7. 장인의 공개 빌드 (비로그인 가능, 숨김/삭제 제외, 최근 수정순) =====
set role authenticated;
set request.jwt.claim.sub = :'W';
select create_matchup('Darius', 'Garen', t.build() || :'doc'::jsonb || '{"name":"첫 빌드"}'::jsonb) as m \gset
insert into ids values ('c1', (:'m'::jsonb ->> 'counter_id')::bigint), ('w1', (:'m'::jsonb ->> 'build_id')::bigint);
insert into ids values ('w2', create_build((select v from ids where k = 'c1'), t.build(array['3071','3047','3053']) || :'doc'::jsonb));
reset role;
select t.ok('새 빌드 2개 -> 대기 줄 2줄 (아직 알림 없음)', (select count(*) from follow_notify_queue where influencer_id = :'W') = 2
  and not exists (select 1 from notifications where kind = 'followed_build_created'));
-- 오래된 수정 시각으로 만들어 순서 확인
update builds set updated_at = now() - interval '1 day' where id = (select v from ids where k = 'w2');
set role anon;
select influencer_builds(:'W') as ib \gset
select t.ok('공개 빌드 2개, 최근 수정순', (:'ib'::jsonb ->> 'total')::int = 2
  and (:'ib'::jsonb -> 'items' -> 0 ->> 'id')::bigint = (select v from ids where k = 'w1')
  and (:'ib'::jsonb -> 'items' -> 1 ->> 'id')::bigint = (select v from ids where k = 'w2'));
select t.ok('카드: 상대법 이름/빌드 이름/패치/작성자/수정 시각', (select i ->> 'target_champion' = 'Darius' and i ->> 'counter_champion' = 'Garen'
  and i ->> 'name' = '첫 빌드' and i ->> 'patch' = '16.21.1' and i -> 'author' ->> 'nickname' = 'Faker' and i -> 'author' ->> 'influencer' = 'pro'
  and i ? 'updated_at' and i ? 'core_items' and i ? 'runes' and i ? 'editor_count' from jsonb_array_elements(:'ib'::jsonb -> 'items') i limit 1));
select t.ok('카드 작성자: id/닉네임/유형만 (역할/이메일 없음)', (select bool_and(
  (select array_agg(k order by k) from jsonb_object_keys(i -> 'author') k) = array['id', 'influencer', 'nickname'])
  from jsonb_array_elements(:'ib'::jsonb -> 'items') i));
select t.ok('장인 정보: id/닉네임/유형 + 팔로워 수', (select array_agg(k order by k) from jsonb_object_keys(:'ib'::jsonb -> 'influencer') k)
  = array['id', 'influencer', 'nickname'] and (:'ib'::jsonb ->> 'follower_count')::int = 26);
select t.ok('장인 아님/없는 id/모양 틀림은 null', influencer_builds(:'V') is null and influencer_builds('00000000-0000-0000-0000-0000000000ff') is null
  and influencer_builds('x') is null and influencer_builds(null) is null);
reset role;
update builds set status = 'hidden', hide_reason = '검사', hidden_at = now() where id = (select v from ids where k = 'w2');
set role anon;
select t.ok('숨긴 빌드 제외', (influencer_builds(:'W') ->> 'total')::int = 1 and jsonb_array_length(influencer_builds(:'W') -> 'items') = 1);
reset role;

-- ===== 8. 알림 (대기 줄 -> 나눠 보내기) =====
select follow_notify_dispatch() as d \gset
select t.ok('보내기 전에 숨겨진 빌드는 버림 (1 보냄 단위 = 팔로워 26명, 1줄 버림)', (:'d'::jsonb ->> 'dropped')::int = 1
  and (:'d'::jsonb ->> 'new')::int = 26 and (:'d'::jsonb ->> 'left')::int = 0);
select t.ok('팔로워 모두에게 1개씩 (U/게스트/운영자/팔로워 22명)', (select count(*) from notifications where kind = 'followed_build_created') = 26
  and (select count(distinct user_id) from notifications where kind = 'followed_build_created') = 26);
select t.ok('장인 본인 / 팔로우 안 한 회원은 받지 않음', not exists (select 1 from notifications where kind = 'followed_build_created'
  and user_id in (:'W', :'V', :'MOD', :'X', :'Z')));
select t.ok('알림 내용: 문장/상대법/빌드', (select message = '팔로우한 장인 Faker의 새 빌드가 올라왔습니다.' and build_id = (select v from ids where k = 'w1')
  and counter_id = (select v from ids where k = 'c1') and read_at is null from notifications where kind = 'followed_build_created' and user_id = :'U'));
select t.ok('숨긴 빌드 알림 없음', not exists (select 1 from notifications where build_id = (select v from ids where k = 'w2') and kind = 'followed_build_created'));
select t.ok('대기 줄 비어 있음', not exists (select 1 from follow_notify_queue));

-- 같은 장인이 3시간 안에 또 만들면 묶는다 (새 알림 없이 "N개"로 고침, 다시 안 읽음)
update notifications set read_at = now() where user_id = :'U' and kind = 'followed_build_created';
set role authenticated;
set request.jwt.claim.sub = :'W';
insert into ids values ('w3', create_build((select v from ids where k = 'c1'), t.build(array['3153','3047','3053']) || :'doc'::jsonb));
reset role;
select follow_notify_dispatch() as d \gset
select t.ok('3시간 안: 새 알림 0, 묶음 26', (:'d'::jsonb ->> 'new')::int = 0 and (:'d'::jsonb ->> 'merged')::int = 26);
select t.ok('묶인 알림: 한 사람에 1개, "2개", 새 빌드로, 다시 안 읽음', (select count(*) = 1 and bool_and(message = '팔로우한 장인 Faker의 새 빌드가 2개 올라왔습니다.')
  and bool_and(build_id = (select v from ids where k = 'w3')) and bool_and(read_at is null)
  from notifications where kind = 'followed_build_created' and user_id = :'U'));
-- 3시간이 지나면 새 알림
update influencer_follows set last_notified_at = now() - interval '3 hours 1 minute' where influencer_id = :'W';
set role authenticated;
set request.jwt.claim.sub = :'W';
insert into ids values ('w4', create_build((select v from ids where k = 'c1'), t.build(array['3124','3047','3053']) || :'doc'::jsonb));
reset role;
select follow_notify_dispatch() as d \gset
select t.ok('3시간 지나면 새 알림 26', (:'d'::jsonb ->> 'new')::int = 26 and (:'d'::jsonb ->> 'merged')::int = 0
  and (select count(*) from notifications where kind = 'followed_build_created' and user_id = :'U') = 2);
-- 알림 줄이 지워졌으면(90일 정리 등) 3시간 안이어도 새 알림
delete from notifications where user_id = :'GU' and kind = 'followed_build_created';
set role authenticated;
set request.jwt.claim.sub = :'W';
insert into ids values ('w5', create_build((select v from ids where k = 'c1'), t.build(array['3036','3047','3053']) || :'doc'::jsonb));
reset role;
select follow_notify_dispatch() as d \gset
select t.ok('지워진 알림이면 새로 (게스트 1명 새 알림, 나머지 25 묶음)', (:'d'::jsonb ->> 'new')::int = 1 and (:'d'::jsonb ->> 'merged')::int = 25);

-- 수정 / 숨김 / 다시 공개는 알림 없음
set role authenticated;
set request.jwt.claim.sub = :'W';
select edit_build((select v from ids where k = 'w1'), t.bv((select v from ids where k = 'w1')), t.build(array['6631','3047','3071']) || :'doc'::jsonb);
set request.jwt.claim.sub = :'U';
select edit_build((select v from ids where k = 'w4'), t.bv((select v from ids where k = 'w4')), t.build(array['3124','3047','3071']) || :'doc'::jsonb);
reset role;
update builds set status = 'hidden', hide_reason = '검사', hidden_at = now() where id = (select v from ids where k = 'w3');
update builds set status = 'approved', hide_reason = null, hidden_at = null where id = (select v from ids where k = 'w3');
select t.ok('수정/숨김/다시 공개는 대기 줄 없음', not exists (select 1 from follow_notify_queue));
set role anon;
select t.ok('수정한 빌드가 맨 위 (최근 수정순)', (influencer_builds(:'W') -> 'items' -> 0 ->> 'id')::bigint = (select v from ids where k = 'w4'));
reset role;

-- 장인 아닌 회원 / 팔로워 없는 장인의 새 빌드는 대기 줄 없음
set role authenticated;
set request.jwt.claim.sub = :'V';
select create_build((select v from ids where k = 'c1'), t.build(array['3071','3053','3065']) || :'doc'::jsonb);
set request.jwt.claim.sub = :'Z';
select create_build((select v from ids where k = 'c1'), t.build(array['3071','3053','3075']) || :'doc'::jsonb);
reset role;
select t.ok('장인 아닌 작성자 / 팔로워 없는 장인은 대기 줄 없음', not exists (select 1 from follow_notify_queue));

-- 새 상대법의 첫 빌드도 새 빌드
set role authenticated;
set request.jwt.claim.sub = :'W';
select create_matchup('Darius', 'Teemo', t.build() || :'doc'::jsonb) as m2 \gset
reset role;
select t.ok('새 상대법의 첫 빌드도 대기 줄', exists (select 1 from follow_notify_queue where build_id = (:'m2'::jsonb ->> 'build_id')::bigint));

-- 나눠 보내기: 한 번에 p_limit명, 남으면 다음 실행에서 이어서
update influencer_follows set last_notified_at = null, notification_id = null where influencer_id = :'W';
delete from notifications where kind = 'followed_build_created';
select follow_notify_dispatch(10) as d \gset
select t.ok('1차: 10명만, 대기 줄 남음(이어서 보낼 자리 기록)', (:'d'::jsonb ->> 'new')::int = 10 and (:'d'::jsonb ->> 'left')::int = 1
  and (select after_follower is not null from follow_notify_queue));
select follow_notify_dispatch(10) as d \gset
select t.ok('2차: 다음 10명', (:'d'::jsonb ->> 'new')::int = 10 and (:'d'::jsonb ->> 'left')::int = 1);
select follow_notify_dispatch(10) as d \gset
select t.ok('3차: 나머지 6명, 대기 줄 끝', (:'d'::jsonb ->> 'new')::int = 6 and (:'d'::jsonb ->> 'left')::int = 0);
select t.ok('겹치지 않고 26명 모두 1개씩', (select count(*) from notifications where kind = 'followed_build_created') = 26
  and (select count(distinct user_id) from notifications where kind = 'followed_build_created') = 26);

-- 하루 넘게 남은 대기 줄은 버림
set role authenticated;
set request.jwt.claim.sub = :'W';
select create_matchup('Darius', 'Nasus', t.build() || :'doc'::jsonb) as m3 \gset
reset role;
update follow_notify_queue set created_at = now() - interval '25 hours';
delete from notifications where kind = 'followed_build_created';
select follow_notify_dispatch() as d \gset
select t.ok('하루 넘은 대기 줄은 보내지 않고 버림', (:'d'::jsonb ->> 'dropped')::int = 1 and (:'d'::jsonb ->> 'new')::int = 0
  and not exists (select 1 from notifications where kind = 'followed_build_created'));

-- 승인 제도를 켠 길: 승인 대기 -> 처음 공개될 때 (숨김 -> 다시 공개는 아님)
alter table builds disable trigger builds_check_new;
insert into builds (counter_id, author_id, runes, summoner_spells, starting_items, core_items, max_skill, patch, status)
select (select v from ids where k = 'c1'), :'W', runes, summoner_spells, starting_items, array['3071','3053','3748'], max_skill, patch, 'pending'
  from builds where id = (select v from ids where k = 'w1')
returning id as pb \gset
alter table builds enable trigger builds_check_new;
select t.ok('승인 대기 빌드는 대기 줄 없음', not exists (select 1 from follow_notify_queue));
update builds set status = 'approved', reviewed_at = now() where id = :pb;
select t.ok('승인 대기 -> 공개되면 대기 줄', exists (select 1 from follow_notify_queue where build_id = :pb));
delete from follow_notify_queue;

-- 운영자 모드를 꺼도 보이고, 모두 읽음에 함께 읽음 처리 (운영진 알림 목록에 넣지 않음)
select follow_notify_dispatch();
set role authenticated;
set request.jwt.claim.sub = :'W';
select create_matchup('Darius', 'Fiora', t.build() || :'doc'::jsonb);
reset role;
update influencer_follows set last_notified_at = null where influencer_id = :'W';
select follow_notify_dispatch();
set role authenticated;
set request.jwt.claim.sub = :'OP';
select set_operator_mode(false);
select t.ok('운영자 모드 꺼도 본인 알림으로 보임', exists (select 1 from notifications where kind = 'followed_build_created'));
select mark_all_notifications_read((select max(id) from notifications));
select t.ok('모두 읽음에 함께 읽음 처리', not exists (select 1 from notifications where kind = 'followed_build_created' and read_at is null));
select set_operator_mode(true);
set request.jwt.claim.sub = :'U';
select t.ok('정식 회원 본인 알림 읽기', exists (select 1 from notifications where kind = 'followed_build_created'));
set request.jwt.claim.sub = :'GU';
select t.ok('게스트 본인 알림 읽기', exists (select 1 from notifications where kind = 'followed_build_created'));
select t.ok('남의 알림은 안 보임', not exists (select 1 from notifications where user_id <> :'GU'));
reset role;
select t.ok('읽기 정책/모두 읽음의 운영진 목록에는 없음', (select pg_get_expr(polqual, polrelid) not like '%followed_build_created%' from pg_policy
  where polname = 'notifications: 본인 읽기') and (select prosrc not like '%followed_build_created%' from pg_proc where proname = 'mark_all_notifications_read'));

-- 푸시 묶음 follow_builds (기존 묶음과 따로, 설정에서 끄고 켬)
select t.ok('푸시 묶음 follow_builds', push_group('followed_build_created') = 'follow_builds'
  and push_group('link_removed') = 'my_results' and push_group('influencer_applied') = 'staff_new');
set role authenticated;
set request.jwt.claim.sub = :'U';
insert into push_subscriptions (user_id, endpoint, p256dh, auth) values (auth.uid(), 'https://push.test/f-1', 'k', 'a');
reset role;
select t.ok('설정 줄이 없으면 켜짐', push_wanted(:'U', 'followed_build_created'));
set role authenticated;
set request.jwt.claim.sub = :'U';
insert into push_settings (user_id) values (auth.uid());
update push_settings set follow_builds = false where user_id = auth.uid();
reset role;
select t.ok('본인이 follow_builds를 끄면 안 감 (다른 묶음은 그대로)', not push_wanted(:'U', 'followed_build_created') and push_wanted(:'U', 'link_removed'));
set role authenticated;
set request.jwt.claim.sub = :'U';
update push_settings set my_results = false, follow_builds = true where user_id = auth.uid();
reset role;
select t.ok('my_results를 꺼도 follow_builds는 따로', push_wanted(:'U', 'followed_build_created') and not push_wanted(:'U', 'link_removed'));
set role authenticated;
set request.jwt.claim.sub = :'GU';
update push_settings set follow_builds = false where user_id = :'U';
reset role;
select t.ok('남의 푸시 설정은 못 고침', (select follow_builds from push_settings where user_id = :'U'));

-- ===== 9. 모아 보기 / 내 팔로우 =====
set role authenticated;
set request.jwt.claim.sub = :'U';
select followed_builds() as fb \gset
select t.ok('모아 보기: 팔로우한 장인 W의 공개 빌드만 (숨김 제외, 장인 아닌 V/팔로우 안 한 Z 제외)', (:'fb'::jsonb ->> 'total')::int
  = (select count(*) from builds b join counters c on c.id = b.counter_id where b.author_id = :'W' and b.status = 'approved' and c.status = 'approved')
  and (select bool_and(i -> 'author' ->> 'id' = :'W') from jsonb_array_elements(:'fb'::jsonb -> 'items') i)
  and not exists (select 1 from jsonb_array_elements(:'fb'::jsonb -> 'items') i where (i ->> 'id')::bigint = (select v from ids where k = 'w2')));
select t.ok('모아 보기: 최근 수정순', (select bool_and(a >= b) from (
  select (i ->> 'updated_at')::timestamptz as a, lead((i ->> 'updated_at')::timestamptz) over (order by n) as b
    from jsonb_array_elements(:'fb'::jsonb -> 'items') with ordinality x(i, n)) s where b is not null));
set request.jwt.claim.sub = :'V';
select t.ok('팔로우 안 한 사람은 빈 목록', followed_builds() = '{"page": 1, "size": 20, "items": [], "total": 0}'::jsonb
  and (my_following() ->> 'total')::int = 0);
reset role;
-- 20개씩: W 공개 빌드를 25개 넘게 만든다 (검사용으로 같은 내용을 복사, 새 빌드 알림 대기 줄은 비움)
alter table builds disable trigger builds_check_new;
insert into builds (counter_id, author_id, runes, summoner_spells, starting_items, core_items, max_skill, patch, status, summary, level_notes, lane_cautions, wiki)
select counter_id, author_id, runes, summoner_spells, starting_items, core_items, max_skill, patch, 'approved', summary, level_notes, lane_cautions, true
  from builds, generate_series(1, 25) where id = (select v from ids where k = 'w1');
alter table builds enable trigger builds_check_new;
delete from follow_notify_queue;
set role authenticated;
set request.jwt.claim.sub = :'U';
select t.ok('모아 보기 20개씩 / 2쪽은 나머지', jsonb_array_length(followed_builds() -> 'items') = 20 and (followed_builds() ->> 'size')::int = 20
  and jsonb_array_length(followed_builds(2) -> 'items') = (followed_builds() ->> 'total')::int - 20);
reset role;
set role anon;
select t.ok('장인 공개 빌드 20개씩', jsonb_array_length(influencer_builds(:'W') -> 'items') = 20
  and jsonb_array_length(influencer_builds(:'W', 2) -> 'items') = (influencer_builds(:'W') ->> 'total')::int - 20);
reset role;

-- ===== 10. 운영자 전용 장인 목록 =====
set role authenticated;
set request.jwt.claim.sub = :'OP';
select admin_influencer_list() as al \gset
select t.ok('장인 목록: W/X/Z 3명, 최근 인증 순', (:'al'::jsonb ->> 'total')::int = 3
  and (select array_agg(i ->> 'nickname' order by n) from jsonb_array_elements(:'al'::jsonb -> 'items') with ordinality x(i, n)) = array['쵸비', '제트', 'Faker']);
select t.ok('직접 지정 여부 / 유형 이름 / 인증일 / 팔로워 수', (select bool_and(case i ->> 'nickname'
    when '쵸비' then (i ->> 'direct')::boolean and i ->> 'kind_label' = '크리에이터'
    when 'Faker' then not (i ->> 'direct')::boolean and (i ->> 'follower_count')::int = 26 and i ->> 'kind_label' = '프로게이머'
    else not (i ->> 'direct')::boolean end and i ? 'influencer_at')
  from jsonb_array_elements(:'al'::jsonb -> 'items') i));
select t.ok('쪽 크기 (1명씩 2쪽)', jsonb_array_length(admin_influencer_list(2, 1) -> 'items') = 1 and admin_influencer_list(2, 1) -> 'items' -> 0 ->> 'nickname' = '제트');
select set_operator_mode(false);
select t.fails('운영자 모드 꺼짐 거부', 'select admin_influencer_list()', '운영자만');
select set_operator_mode(true);
set request.jwt.claim.sub = :'MOD';
select t.fails('감독관 거부', 'select admin_influencer_list()', '운영자만');
set request.jwt.claim.sub = :'U';
select t.fails('일반 회원 거부', 'select admin_influencer_list()', '운영자만');
set request.jwt.claim.sub = :'GU';
select t.fails('게스트 거부', 'select admin_influencer_list()', '운영자만');
reset role;

-- ===== 11. 인증 해제 -> 그 장인 팔로우 바로 삭제 =====
set role authenticated;
set request.jwt.claim.sub = :'U';
select follow_influencer(:'X');
set request.jwt.claim.sub = :'W';
select create_matchup('Darius', 'Jax', t.build() || :'doc'::jsonb);
reset role;
select t.ok('해제 전: W 팔로워 26, 대기 줄 1', (select count(*) from influencer_follows where influencer_id = :'W') = 26
  and exists (select 1 from follow_notify_queue where influencer_id = :'W'));
set role authenticated;
set request.jwt.claim.sub = :'OP';
select revoke_influencer(:'W', '검사 해제');
reset role;
select t.ok('해제하면 W 팔로우 기록 0, 대기 줄도 0', not exists (select 1 from influencer_follows where influencer_id = :'W')
  and not exists (select 1 from follow_notify_queue where influencer_id = :'W'));
select t.ok('다른 장인 팔로우는 그대로 (U -> X, W -> X)', exists (select 1 from influencer_follows where follower_id = :'U' and influencer_id = :'X')
  and exists (select 1 from influencer_follows where follower_id = :'W' and influencer_id = :'X'));
set role anon;
select t.ok('해제된 W: 검색/공개 빌드/팔로워 수에서 빠짐', (search_influencers('Faker') ->> 'total')::int = 0 and influencer_builds(:'W') is null
  and influencer_follower_count(:'W') is null);
reset role;
set role authenticated;
set request.jwt.claim.sub = :'U';
select t.fails('해제된 W는 팔로우 불가', format('select follow_influencer(%L)', :'W'), '인증된 장인만');
select t.ok('[+] 상태도 false', (follow_status(array[:'W']::uuid[]) ->> :'W')::boolean = false);
set request.jwt.claim.sub = :'OP';
select grant_influencer(:'W', 'pro', '다시 지정');
reset role;
select t.ok('다시 지정돼도 팔로우는 돌아오지 않음', not exists (select 1 from influencer_follows where influencer_id = :'W'));
set role authenticated;
set request.jwt.claim.sub = :'OP';
select admin_set_nickname(:'X', '쵸비2', '검사');
reset role;
select t.ok('닉네임을 바꿔도 X 팔로우 그대로', (select count(*) from influencer_follows where influencer_id = :'X') = 2);

-- ===== 12. 탈퇴 / 게스트 정리 / 비회원 기록 지우기 -> 그 사람의 팔로우 기록 없음 =====
set role authenticated;
set request.jwt.claim.sub = :'GU';
select follow_influencer(:'X');
select follow_influencer(:'Z');
set request.jwt.claim.sub = :'GN';
select follow_influencer(:'X');
set request.jwt.claim.sub = :'V';
select follow_influencer(:'X');
reset role;
-- 팔로우 호출 기록도 남아 있는지 (지워지는지 확인용)
select t.ok('준비: U/V/GU/GN 팔로우 기록과 호출 기록 있음', (select count(distinct follower_id) from influencer_follows where follower_id in (:'U', :'V', :'GU', :'GN')) = 4
  and (select count(*) from follow_rate where user_id in (:'U', :'V', :'GU', :'GN')) = 4);
set role authenticated;
set request.jwt.claim.sub = :'U';
select delete_my_account('유저');
reset role;
select t.ok('탈퇴하면 그 사람의 팔로우/호출 기록 없음', not exists (select 1 from influencer_follows where follower_id = :'U')
  and not exists (select 1 from follow_rate where user_id = :'U'));
set role authenticated;
set request.jwt.claim.sub = :'GN';
select delete_my_account('지우기');
reset role;
select t.ok('비회원 기록 지우기도 팔로우 기록 없음', not exists (select 1 from influencer_follows where follower_id = :'GN'));
update profiles set last_seen_at = now() - interval '400 days' where id = :'GU';
select t.ok('게스트 정리 대상', cleanup_guest_accounts() >= 1);
select t.ok('게스트 정리(cleanup-guests)도 팔로우/호출 기록 없음', not exists (select 1 from influencer_follows where follower_id = :'GU')
  and not exists (select 1 from follow_rate where user_id = :'GU'));
-- 장인이 탈퇴하면 그 장인을 팔로우한 기록도 없음
set role authenticated;
set request.jwt.claim.sub = :'Z';
select create_build((select v from ids where k = 'c1'), t.build(array['3071','3053','3083']) || :'doc'::jsonb);
reset role;
insert into influencer_follows (follower_id, influencer_id) values (:'V', :'Z');
set role authenticated;
set request.jwt.claim.sub = :'Z';
select create_build((select v from ids where k = 'c1'), t.build(array['3071','3053','3143']) || :'doc'::jsonb);
select delete_my_account('제트');
reset role;
select t.ok('장인이 탈퇴하면 그 장인을 팔로우한 기록과 대기 줄도 없음', not exists (select 1 from influencer_follows where influencer_id = :'Z')
  and not exists (select 1 from follow_notify_queue where influencer_id = :'Z'));
select t.ok('남은 팔로우: V -> X, W -> X', (select array_agg(follower_id::text || '>' || influencer_id::text order by follower_id::text) from influencer_follows
  where follower_id::text not like '00000000-0000-0000-0000-0000000001%') = array[:'V' || '>' || :'X', :'W' || '>' || :'X']);
