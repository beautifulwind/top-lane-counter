-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 063: 팔로우 목록 공개 범위 - 팔로워 목록은 장인 본인·운영자(운영자 모드 켜짐)만, 게스트 거부, 남의 장인·감독관·운영자 모드 끈 운영자 거부,
--      장인 본인이 볼 때만 장인과 팔로워 사이 차단(어느 쪽이든)을 목록·total에서 뺌(운영자는 전부, 공개 팔로워 수는 그대로),
--      응답에 followed_at 없음(순서는 그대로),
--      내 팔로우 목록은 나만·게스트 거부·followed_at 없음, 함수 모양·권한 그대로
\set ON_ERROR_STOP 1
\set QUIET 1
\set OP  '00000000-0000-0000-0000-00000000000a'
\set MOD '00000000-0000-0000-0000-00000000000b'
\set U   '00000000-0000-0000-0000-00000000000d'
\set V   '00000000-0000-0000-0000-00000000000c'
\set W   '00000000-0000-0000-0000-00000000000f'
\set Z   '00000000-0000-0000-0000-000000000013'
\set G   '00000000-0000-0000-0000-000000000010'
\set F1  '00000000-0000-0000-0000-000000000201'
\set F2  '00000000-0000-0000-0000-000000000202'
\set F3  '00000000-0000-0000-0000-000000000203'
\set F4  '00000000-0000-0000-0000-000000000204'
insert into auth.users (id, email) values (:'OP', 'op@x.com'), (:'MOD', 'm@x.com'), (:'U', 'u@x.com'), (:'V', 'v@x.com'),
  (:'W', 'w@x.com'), (:'Z', 'z@x.com'), (:'F1', 'f1@x.com'), (:'F2', 'f2@x.com'), (:'F3', 'f3@x.com'), (:'F4', 'f4@x.com');
insert into auth.users (id, email, is_anonymous) values (:'G', null, true);
update public.profiles set nickname = '영자', role = 'admin' where id = :'OP';
update public.profiles set nickname = '감독', role = 'moderator' where id = :'MOD';
update public.profiles set nickname = '유저' where id = :'U';
update public.profiles set nickname = '보통' where id = :'V';
update public.profiles set nickname = 'Faker', influencer = 'pro', influencer_at = now() - interval '2 days' where id = :'W';
update public.profiles set nickname = '제트', influencer = 'creator', influencer_at = now() - interval '1 day' where id = :'Z';
update public.profiles set nickname = '팬하나' where id = :'F1';
update public.profiles set nickname = '팬둘' where id = :'F2';
update public.profiles set nickname = '팬셋' where id = :'F3';
update public.profiles set nickname = '팬넷' where id = :'F4';
-- G: 닉네임을 정하지 않은 게스트
-- W의 팔로워 7명 (최근 순: F1, F2, F3, F4, G, U, Z). U는 Z도 팔로우
insert into influencer_follows (follower_id, influencer_id, created_at) values
  (:'F1', :'W', now() - interval '1 hour'), (:'F2', :'W', now() - interval '2 hours'), (:'F3', :'W', now() - interval '3 hours'),
  (:'F4', :'W', now() - interval '4 hours'), (:'G', :'W', now() - interval '5 hours'), (:'U', :'W', now() - interval '6 hours'),
  (:'Z', :'W', now() - interval '7 hours'), (:'U', :'Z', now() - interval '30 minutes');
-- 차단: W가 F2를 차단(팔로우는 남음) / F3이 W를 차단(트리거가 팔로우를 끊는다 → 아래에서 F3이 차단한 채로 다시 팔로우) / U가 F4를 차단(W와 무관)
insert into user_blocks (blocker_id, blocked_id) values (:'W', :'F2'), (:'F3', :'W'), (:'U', :'F4');
select t.ok('준비: F3이 W를 차단하면 F3의 W 팔로우가 끊김 (061)', not exists (select 1 from influencer_follows where follower_id = :'F3' and influencer_id = :'W'));
set role authenticated;
set request.jwt.claim.sub = :'F3';
select t.ok('준비: F3이 차단한 채로 W를 다시 팔로우할 수 있음', (follow_influencer(:'W') ->> 'following')::boolean);
reset role;
update influencer_follows set created_at = now() - interval '3 hours' where follower_id = :'F3' and influencer_id = :'W';
delete from follow_rate;
select t.ok('준비: W 팔로우 7줄 (차단과 상관없이 표에는 남음)', (select count(*) from influencer_follows where influencer_id = :'W') = 7);

-- ===== 1. 함수 모양·권한 그대로 =====
select t.ok('함수 모양 그대로 (팔로워 목록은 장인 id를 받고, 내 팔로우는 쪽 번호만 - 남의 것을 물을 인자가 없다)',
  (select string_agg(p.oid::regprocedure::text, ',' order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in ('influencer_followers', 'my_following'))
  = 'influencer_followers(uuid,integer),my_following(integer)');
select t.ok('권한 그대로: 로그인만 실행 / 비로그인 불가 / 안쪽 함수 아무도 못 부름',
  has_function_privilege('authenticated', 'public.influencer_followers(uuid,integer)', 'execute')
  and has_function_privilege('authenticated', 'public.my_following(integer)', 'execute')
  and not has_function_privilege('anon', 'public.influencer_followers(uuid,integer)', 'execute')
  and not has_function_privilege('anon', 'public.my_following(integer)', 'execute')
  and not has_function_privilege('authenticated', 'public.influencer_followers_unchecked(uuid,integer)', 'execute')
  and not has_function_privilege('authenticated', 'public.my_following_unchecked(uuid,integer)', 'execute'));
set role anon;
reset request.jwt.claim.sub;
select t.fails('비로그인 팔로워 목록 거부', format('select influencer_followers(%L)', :'W'), 'permission denied');
select t.fails('비로그인 내 팔로우 거부', 'select my_following()', 'permission denied');
select t.ok('공개 팔로워 수는 그대로 전체 (차단 포함 7)', influencer_follower_count(:'W') = 7
  and (influencer_builds(:'W') ->> 'follower_count')::int = 7);
reset role;

-- ===== 2. 누가 볼 수 있나 =====
set role authenticated;
set request.jwt.claim.sub = :'G';
select t.fails('게스트: 남의 팔로워 목록 거부', format('select influencer_followers(%L)', :'W'), '비회원은 팔로워 목록을 볼 수 없습니다');
select t.fails('게스트: 자기 id를 넣어도 거부', format('select influencer_followers(%L)', :'G'), '비회원은 팔로워 목록을 볼 수 없습니다');
select t.fails('게스트: 내 팔로우 목록 거부', 'select my_following()', '비회원은 팔로우한 장인 목록을 볼 수 없습니다');
set request.jwt.claim.sub = :'U';
select t.fails('정식 회원: 남의 장인 팔로워 목록 거부', format('select influencer_followers(%L)', :'W'), '팔로워 목록은 장인 본인만 볼 수 있습니다');
select t.fails('정식 회원: 장인 아닌 회원 id도 같은 거부 (장인인지 드러나지 않음)', format('select influencer_followers(%L)', :'V'), '장인 본인만');
select t.fails('정식 회원: 빈 id 거부', 'select influencer_followers(null)', '장인 본인만');
set request.jwt.claim.sub = :'Z';
select t.fails('다른 장인: 남의 장인 팔로워 목록 거부', format('select influencer_followers(%L)', :'W'), '장인 본인만');
select t.ok('다른 장인: 내 목록은 봄 (U 1명)', (select (j ->> 'total')::int = 1 and j -> 'items' -> 0 ->> 'id' = :'U'
  from (select influencer_followers(:'Z') as j) s));
set request.jwt.claim.sub = :'MOD';
select t.fails('감독관도 남의 팔로워 목록 거부', format('select influencer_followers(%L)', :'W'), '장인 본인만');
set request.jwt.claim.sub = :'V';
select t.fails('장인이 아닌 회원이 자기 id: 장인을 찾지 못함', format('select influencer_followers(%L)', :'V'), '인증된 장인을 찾지 못했습니다');

-- ===== 3. 장인 본인: 차단 거르기 + 날짜 없음 + 순서 =====
set request.jwt.claim.sub = :'W';
select influencer_followers(:'W') as fl \gset
select t.ok('본인: total·follower_count = 5 (W가 차단한 F2, W를 차단한 F3 빠짐 - U가 차단한 F4는 그대로)',
  (:'fl'::jsonb ->> 'total')::int = 5 and (:'fl'::jsonb ->> 'follower_count')::int = 5 and jsonb_array_length(:'fl'::jsonb -> 'items') = 5);
select t.ok('본인: 최근 팔로우 순 그대로 F1, F4, G, U, Z (순서만 서버가 정함)',
  (select string_agg(i ->> 'id', ',' order by n) from jsonb_array_elements(:'fl'::jsonb -> 'items') with ordinality x(i, n))
  = concat_ws(',', :'F1', :'F4', :'G', :'U', :'Z'));
select t.ok('응답 칸: id·nickname·influencer·nickname_state만 (followed_at·created_at·역할·레벨 없음)',
  (select bool_and((select array_agg(k order by k) from jsonb_object_keys(i) k) = array['id', 'influencer', 'nickname', 'nickname_state'])
     from jsonb_array_elements(:'fl'::jsonb -> 'items') i)
  and position('followed_at' in :'fl') = 0 and position('created_at' in :'fl') = 0);
select t.ok('응답 겉 칸: follower_count·total·page·size·items만',
  (select array_agg(k order by k) from jsonb_object_keys(:'fl'::jsonb) k) = array['follower_count', 'items', 'page', 'size', 'total']);
select t.ok('장인 팔로워는 장인 표시, 닉네임 없는 게스트는 nickname null', exists (select 1 from jsonb_array_elements(:'fl'::jsonb -> 'items') i
  where i ->> 'id' = :'Z' and i ->> 'influencer' = 'creator') and exists (select 1 from jsonb_array_elements(:'fl'::jsonb -> 'items') i
  where i ->> 'id' = :'G' and i -> 'nickname' = 'null'::jsonb));
reset role;
delete from user_blocks where blocker_id = :'W' and blocked_id = :'F2';
set role authenticated;
set request.jwt.claim.sub = :'W';
select t.ok('차단을 풀면 다시 목록에 (6, F2가 F1 다음)', (select (j ->> 'total')::int = 6 and j -> 'items' -> 1 ->> 'id' = :'F2'
  from (select influencer_followers(:'W') as j) s));
reset role;
insert into user_blocks (blocker_id, blocked_id) values (:'W', :'F2');

-- 20개씩 + 차단은 쪽 나누기 전에 뺀다 (2쪽이 비거나 겹치지 않게)
insert into auth.users (id, email) select ('00000000-0000-0000-0000-0000000003' || lpad(i::text, 2, '0'))::uuid, 'p' || i || '@x.com'
  from generate_series(1, 20) i;
insert into influencer_follows (follower_id, influencer_id, created_at)
  select id, :'W', now() - interval '10 minutes' - (right(id::text, 2)::int * interval '1 second')
    from profiles where id::text like '00000000-0000-0000-0000-0000000003%';
insert into user_blocks (blocker_id, blocked_id) values (:'W', '00000000-0000-0000-0000-000000000301');
set role authenticated;
set request.jwt.claim.sub = :'W';
select t.ok('쪽 나누기: 팔로우 27줄 - 차단 3명(F2·F3·새 1명) = 24명 = 1쪽 20 + 2쪽 4, 겹침·차단한 사람 없음', (select (a ->> 'total')::int = 24
  and jsonb_array_length(a -> 'items') = 20 and jsonb_array_length(b -> 'items') = 4
  and (select count(distinct i ->> 'id') from (select jsonb_array_elements(a -> 'items') i union all select jsonb_array_elements(b -> 'items')) s) = 24
  and position('00000000-0000-0000-0000-000000000301' in (a::text || b::text)) = 0
  and position(:'F2' in (a::text || b::text)) = 0 and position(:'F3' in (a::text || b::text)) = 0
  from (select influencer_followers(:'W') as a, influencer_followers(:'W', 2) as b) s));
reset role;

-- ===== 4. 운영자 =====
-- 운영자도 F1을 차단해 둔다 (운영자 자신의 차단도 운영자의 열람에는 영향 없음)
insert into user_blocks (blocker_id, blocked_id) values (:'OP', :'F1');
set role authenticated;
set request.jwt.claim.sub = :'OP';
select influencer_followers(:'W') as ol \gset
select t.ok('운영자: 남의 장인 목록은 차단과 상관없이 전부 (27 = 팔로우 줄 전체, F2·F3·새 1명·운영자가 차단한 F1 포함)',
  (:'ol'::jsonb ->> 'total')::int = 27 and (:'ol'::jsonb ->> 'follower_count')::int = 27
  and position('00000000-0000-0000-0000-000000000301' in :'ol') > 0);  -- W가 차단한 새 1명도 1쪽에 보임 (F1·F2·F3은 2쪽 - 아래 검사)
select t.ok('운영자: 순서 그대로 - 1쪽 맨 위는 새 20명 중 가장 최근(…301), 2쪽 7명 F1, F2, F3, F4, G, U, Z, 겹침 없음',
  :'ol'::jsonb -> 'items' -> 0 ->> 'id' = '00000000-0000-0000-0000-000000000301'
  and (select string_agg(i ->> 'id', ',' order by n) from jsonb_array_elements(influencer_followers(:'W', 2) -> 'items') with ordinality x(i, n))
      = concat_ws(',', :'F1', :'F2', :'F3', :'F4', :'G', :'U', :'Z')
  and (select count(distinct i ->> 'id') from (select jsonb_array_elements(:'ol'::jsonb -> 'items') i
       union all select jsonb_array_elements(influencer_followers(:'W', 2) -> 'items')) s) = 27);
select t.ok('운영자에게도 날짜 없음 (칸 id·nickname·influencer·nickname_state만)',
  (select bool_and((select array_agg(k order by k) from jsonb_object_keys(i) k) = array['id', 'influencer', 'nickname', 'nickname_state'])
     from jsonb_array_elements(:'ol'::jsonb -> 'items') i)
  and position('followed_at' in :'ol') = 0 and position('created_at' in :'ol') = 0);
set request.jwt.claim.sub = :'W';
select t.ok('같은 때 장인 본인은 여전히 차단 관계를 뺀 24 (운영자의 F1 차단은 무관)', (influencer_followers(:'W') ->> 'total')::int = 24
  and position(:'F1' in influencer_followers(:'W')::text) > 0);
set request.jwt.claim.sub = :'OP';
select t.fails('운영자: 장인 아닌 회원은 장인을 찾지 못함', format('select influencer_followers(%L)', :'V'), '인증된 장인을 찾지 못했습니다');
reset role;
update profiles set operator_mode = false where id = :'OP';
set role authenticated;
set request.jwt.claim.sub = :'OP';
select t.fails('운영자 모드를 끄면 일반 회원과 같음 (거부)', format('select influencer_followers(%L)', :'W'), '장인 본인만');
reset role;
update profiles set operator_mode = true where id = :'OP';
-- 운영자 자신이 장인이면 자기 목록은 장인 본인 규칙 (운영자가 차단한 F1 제외)
update profiles set influencer = 'pro', influencer_at = now() where id = :'OP';
insert into influencer_follows (follower_id, influencer_id, created_at) values (:'F1', :'OP', now() - interval '1 hour'), (:'F2', :'OP', now() - interval '2 hours');
set role authenticated;
set request.jwt.claim.sub = :'OP';
select t.ok('운영자가 장인일 때 자기 목록: 자기가 차단한 F1은 빠짐 (F2만)', (select (j ->> 'total')::int = 1 and j -> 'items' -> 0 ->> 'id' = :'F2'
  from (select influencer_followers(:'OP') as j) s));
reset role;
update profiles set influencer = null, influencer_at = null where id = :'OP';

-- ===== 5. 내가 팔로우한 장인 =====
set role authenticated;
set request.jwt.claim.sub = :'U';
select my_following() as mf \gset
select t.ok('내 팔로우: 나만 (U → Z, W 최근 순)', (:'mf'::jsonb ->> 'total')::int = 2
  and (select string_agg(i ->> 'id', ',' order by n) from jsonb_array_elements(:'mf'::jsonb -> 'items') with ordinality x(i, n)) = concat_ws(',', :'Z', :'W'));
select t.ok('내 팔로우 칸: id·nickname·influencer·follower_count만 (followed_at 없음)',
  (select bool_and((select array_agg(k order by k) from jsonb_object_keys(i) k) = array['follower_count', 'id', 'influencer', 'nickname'])
     from jsonb_array_elements(:'mf'::jsonb -> 'items') i)
  and position('followed_at' in :'mf') = 0 and position('created_at' in :'mf') = 0);
select t.ok('내 팔로우의 팔로워 수는 공개 수 그대로 (W는 차단 포함 전체)', (select (i ->> 'follower_count')::int
  from jsonb_array_elements(:'mf'::jsonb -> 'items') i where i ->> 'id' = :'W') = (select influencer_follower_count(:'W')));
set request.jwt.claim.sub = :'F3';
select t.ok('W를 차단한 F3도 자기 팔로우 목록은 봄', (my_following() ->> 'total')::int = 1);
set request.jwt.claim.sub = :'OP';
select t.ok('운영자도 내 팔로우는 자기 것만 (0)', (my_following() ->> 'total')::int = 0);
reset role;
