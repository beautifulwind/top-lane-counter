-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 052: 장인 새 팔로워 알림 - 하루 묶음 (표/RLS, 권한, 지금도 팔로우 중인 사람만, 취소한 사람 제외, 팔로우/취소 반복,
--      두 번 돌아도 안 늘어남, 25시간 창, 30일 기록 정리, 인증 해제/탈퇴 제외, 이름 없음, 푸시 기본 꺼짐, 읽음)
\set ON_ERROR_STOP 1
\set QUIET 1
\set OP  '00000000-0000-0000-0000-00000000000a'
\set U   '00000000-0000-0000-0000-00000000000d'
\set V   '00000000-0000-0000-0000-00000000000c'
\set W   '00000000-0000-0000-0000-00000000000f'
\set X   '00000000-0000-0000-0000-000000000012'
\set Z   '00000000-0000-0000-0000-000000000013'
\set GU  '00000000-0000-0000-0000-000000000010'
insert into auth.users (id, email) values (:'OP', 'op@x.com'), (:'U', 'u@x.com'), (:'V', 'v@x.com'), (:'W', 'w@x.com'),
  (:'X', 'x@x.com'), (:'Z', 'z@x.com');
insert into auth.users (id, email, is_anonymous) values (:'GU', null, true);
update public.profiles set nickname = '영자', role = 'admin' where id = :'OP';
update public.profiles set nickname = '유저' where id = :'U';
update public.profiles set nickname = '브이' where id = :'V';
update public.profiles set nickname = 'Faker', influencer = 'pro', influencer_at = now() - interval '2 days' where id = :'W';
update public.profiles set nickname = '쵸비' where id = :'X';
update public.profiles set nickname = '제트', influencer = 'creator', influencer_at = now() - interval '1 day' where id = :'Z';
update public.profiles set nickname = '손님' where id = :'GU';
delete from notifications;
-- 팔로우/취소 호출 횟수(1분 30번)는 이 검사와 관계없으므로 매번 비운다
create function pg_temp.fol(p_me uuid, p_user uuid, p_on boolean) returns void language plpgsql as $$
begin
  delete from public.follow_rate;
  perform set_config('request.jwt.claim.sub', p_me::text, true);
  if p_on then perform public.follow_influencer_unchecked(p_me, p_user);
  else perform public.unfollow_influencer_unchecked(p_me, p_user); end if;
end $$;
create function pg_temp.msgs(p_user uuid) returns text[] language sql as $$
  select coalesce(array_agg(message order by id), '{}') from public.notifications where user_id = p_user and kind = 'new_followers'
$$;

-- ===== 1. 표 / RLS / 권한 / 알림 종류 =====
select t.ok('센 기록 표 RLS 켜짐 + 정책 없음', (select relrowsecurity from pg_class where oid = 'public.new_follower_counted'::regclass)
  and not exists (select 1 from pg_policy where polrelid = 'public.new_follower_counted'::regclass));
select t.ok('센 기록 표 권한 없음 (anon/authenticated 읽기/넣기/고치기/지우기)', not exists (
  select 1 from unnest(array['anon', 'authenticated']) r, unnest(array['select', 'insert', 'update', 'delete']) p
   where has_table_privilege(r, 'public.new_follower_counted', p)));
set role authenticated;
set request.jwt.claim.sub = :'W';
select t.fails('장인 본인도 센 기록 직접 읽기 거부', 'select * from new_follower_counted', 'permission denied');
select t.fails('로그인 사용자 하루 묶음 직접 호출 거부', 'select new_follower_digest()', 'permission denied');
reset role;
set role anon;
select t.fails('비로그인 하루 묶음 직접 호출 거부', 'select new_follower_digest()', 'permission denied');
reset role;
select t.ok('트리거 함수도 아무도 못 부름', not has_function_privilege('authenticated', 'public.new_follower_counted_on_influencer_end()', 'execute')
  and not has_function_privilege('anon', 'public.new_follower_counted_on_influencer_end()', 'execute'));
select t.ok('알림 종류에 new_followers (있던 종류 그대로)', (select pg_get_constraintdef(oid) like '%new_followers%'
  and pg_get_constraintdef(oid) like '%notice_posted%' and pg_get_constraintdef(oid) like '%followed_build_created%' from pg_constraint
  where conname = 'notifications_kind_check' and conrelid = 'public.notifications'::regclass));
select t.ok('설정값 늘지 않음 (052는 xp_rules에 더하지 않음)', not exists (select 1 from xp_rules where note like '%(052)%'));

-- ===== 2. 하루 묶음: 지금도 팔로우 중인 사람만, 숫자만 =====
select pg_temp.fol(:'U', :'W', true);
select pg_temp.fol(:'V', :'W', true);
select pg_temp.fol(:'GU', :'W', true);
select pg_temp.fol(:'GU', :'W', false);   -- 하루가 지나기 전에 취소
select pg_temp.fol(:'X', :'W', true);
select pg_temp.fol(:'X', :'W', false);
select pg_temp.fol(:'X', :'W', true);     -- 같은 날 팔로우/취소/다시 팔로우 = 1명
select t.ok('팔로우할 때는 알림을 바로 만들지 않음', not exists (select 1 from notifications where kind = 'new_followers'));
select new_follower_digest() as d1 \gset
select t.ok('새 팔로워가 생긴 장인(W)에게만 한 개, 취소한 GU는 빼고 3명', pg_temp.msgs(:'W') = array['오늘 새 팔로워 3명이 생겼습니다.']
  and pg_temp.msgs(:'Z') = '{}' and (:'d1'::jsonb ->> 'notified')::int = 1 and (:'d1'::jsonb ->> 'counted')::int = 3);
select t.ok('알림에 팔로워 이름/연결 없음 (숫자만)', (select bool_and(message not like '%유저%' and message not like '%브이%' and message not like '%쵸비%'
  and post_id is null and build_id is null and counter_id is null and proposal_id is null) from notifications where kind = 'new_followers'));
select t.ok('새 팔로워가 없는 장인/장인 아닌 회원은 알림 없음', not exists (select 1 from notifications where kind = 'new_followers' and user_id <> :'W'));

-- ===== 3. 다시 돌아도 / 팔로우·취소를 되풀이해도 늘지 않음 =====
select new_follower_digest() as d2 \gset
select t.ok('같은 날 다시 돌면 새로 센 사람이 없어 알림 없음', pg_temp.msgs(:'W') = array['오늘 새 팔로워 3명이 생겼습니다.']
  and (:'d2'::jsonb ->> 'notified')::int = 0);
select pg_temp.fol(:'U', :'W', false);
select pg_temp.fol(:'U', :'W', true);
select pg_temp.fol(:'V', :'W', false);
select pg_temp.fol(:'V', :'W', true);
select pg_temp.fol(:'V', :'W', false);
select pg_temp.fol(:'V', :'W', true);
select new_follower_digest();
select t.ok('이미 센 사람이 취소/다시 팔로우를 되풀이해도 알림이 늘지 않음', cardinality(pg_temp.msgs(:'W')) = 1);
-- 다음 날: GU가 다시 팔로우 (어제는 취소해서 세지 않았으므로 새 팔로워), Z에게도 새 팔로워
select pg_temp.fol(:'GU', :'W', true);
select pg_temp.fol(:'U', :'Z', true);
select new_follower_digest();
select t.ok('다음 날 새로 생긴 사람만 셈 (W 1명, Z 1명)', pg_temp.msgs(:'W') = array['오늘 새 팔로워 3명이 생겼습니다.', '오늘 새 팔로워 1명이 생겼습니다.']
  and pg_temp.msgs(:'Z') = array['오늘 새 팔로워 1명이 생겼습니다.']);

-- ===== 4. 25시간 창 / 30일 기록 정리 =====
select pg_temp.fol(:'OP', :'W', true);
update influencer_follows set created_at = now() - interval '26 hours' where follower_id = :'OP' and influencer_id = :'W';
select new_follower_digest();
select t.ok('25시간보다 오래된 팔로우는 세지 않음 (052 실행 전에 쌓인 팔로우가 한꺼번에 오지 않게)', cardinality(pg_temp.msgs(:'W')) = 2);
update new_follower_counted set counted_at = now() - interval '31 days' where follower_id = :'X' and influencer_id = :'W';
update influencer_follows set created_at = now() - interval '31 days' where follower_id = :'X' and influencer_id = :'W';
select new_follower_digest() as d3 \gset
select t.ok('30일 지난 기록은 지움', (:'d3'::jsonb ->> 'pruned')::int = 1
  and not exists (select 1 from new_follower_counted where follower_id = :'X' and influencer_id = :'W'));
select pg_temp.fol(:'X', :'W', false);
select pg_temp.fol(:'X', :'W', true);
select new_follower_digest();
select t.ok('기록이 지워진 뒤 다시 팔로우하면 새 팔로워로 셈', (pg_temp.msgs(:'W'))[3] = '오늘 새 팔로워 1명이 생겼습니다.');

-- ===== 5. 인증 해제 / 탈퇴 =====
select pg_temp.fol(:'V', :'Z', true);
set role authenticated;
set request.jwt.claim.sub = :'OP';
select revoke_influencer(:'Z', '검사 해제');
reset role;
select t.ok('인증이 해제되면 센 기록도 바로 지움', not exists (select 1 from new_follower_counted where influencer_id = :'Z'));
select new_follower_digest();
select t.ok('인증이 해제된 장인에게는 알림 없음', cardinality(pg_temp.msgs(:'Z')) = 1);
-- 장인이 아닌데 팔로우 줄이 남아 있는 경우(직접 넣음)에도 보내지 않음
insert into influencer_follows (follower_id, influencer_id) values (:'U', :'Z');
select new_follower_digest();
select t.ok('장인 표시가 없으면 팔로우 줄이 있어도 보내지 않음', cardinality(pg_temp.msgs(:'Z')) = 1);
select pg_temp.fol(:'GU', :'W', false);
select pg_temp.fol(:'U', :'W', false);
update influencer_follows set created_at = now() - interval '2 days' where influencer_id = :'W';
select pg_temp.fol(:'GU', :'W', true);
update new_follower_counted set counted_at = now() - interval '31 days' where follower_id = :'GU';
set role authenticated;
set request.jwt.claim.sub = :'GU';
select delete_my_account('손님');
reset role;
select t.ok('탈퇴하면 그 사람의 센 기록도 없음 (cascade)', not exists (select 1 from new_follower_counted where follower_id = :'GU'));
select new_follower_digest();
select t.ok('탈퇴한 팔로워는 세지 않음', cardinality(pg_temp.msgs(:'W')) = 3);
set role authenticated;
set request.jwt.claim.sub = :'W';
select delete_my_account('Faker');
reset role;
select t.ok('장인이 탈퇴하면 알림/센 기록 모두 없음', not exists (select 1 from notifications where user_id = :'W')
  and not exists (select 1 from new_follower_counted where influencer_id = :'W'));

-- ===== 6. 읽기 / 모두 읽음 =====
update profiles set influencer = 'pro', influencer_at = now() where id = :'X';
select pg_temp.fol(:'U', :'X', true);
select new_follower_digest();
set role authenticated;
set request.jwt.claim.sub = :'X';
select t.ok('장인 본인 알림 읽기', (select count(*) from notifications where kind = 'new_followers') = 1);
select mark_all_notifications_read((select max(id) from notifications));
select t.ok('모두 읽음에 함께 읽음 처리', not exists (select 1 from notifications where kind = 'new_followers' and read_at is null));
set request.jwt.claim.sub = :'U';
select t.ok('남의 새 팔로워 알림은 안 보임', not exists (select 1 from notifications where kind = 'new_followers'));
reset role;
select t.ok('읽기 정책/모두 읽음의 운영진 목록에는 없음', (select pg_get_expr(polqual, polrelid) not like '%new_followers%' from pg_policy
  where polname = 'notifications: 본인 읽기') and (select prosrc not like '%new_followers%' from pg_proc where proname = 'mark_all_notifications_read'));

-- ===== 7. 푸시 묶음 new_followers (기본 꺼짐, 켠 사람에게만) =====
select t.ok('푸시 묶음 new_followers (있던 묶음 그대로)', push_group('new_followers') = 'new_followers' and push_group('notice_posted') = 'notice'
  and push_group('followed_build_created') = 'follow_builds' and push_group('link_removed') = 'my_results');
set role authenticated;
set request.jwt.claim.sub = :'X';
insert into push_subscriptions (user_id, endpoint, p256dh, auth) values (auth.uid(), 'https://push.test/nf-1', 'k', 'a');
reset role;
select t.ok('설정 줄이 없으면 꺼짐 (다른 묶음은 켜짐)', not push_wanted(:'X', 'new_followers') and push_wanted(:'X', 'notice_posted'));
set role authenticated;
set request.jwt.claim.sub = :'X';
insert into push_settings (user_id) values (auth.uid());
reset role;
select t.ok('설정 줄의 기본값도 꺼짐', not (select new_followers from push_settings where user_id = :'X') and not push_wanted(:'X', 'new_followers'));
set role authenticated;
set request.jwt.claim.sub = :'X';
update push_settings set new_followers = true where user_id = auth.uid();
reset role;
select t.ok('본인이 켜면 감', push_wanted(:'X', 'new_followers'));
set role authenticated;
set request.jwt.claim.sub = :'U';
update push_settings set new_followers = false where user_id = :'X';
reset role;
select t.ok('남의 푸시 설정은 못 고침', (select new_followers from push_settings where user_id = :'X'));
insert into vault.decrypted_secrets values ('push_function_url', 'https://fn.test/web-push'), ('push_webhook_secret', 's')
  on conflict (name) do nothing;
delete from net.calls;
select pg_temp.fol(:'V', :'X', true);
select new_follower_digest();
select t.ok('켠 장인에게 휴대폰 알림 요청 한 번', (select count(*) from net.calls) = 1
  and (select (body ->> 'notification_id')::bigint from net.calls) = (select max(id) from notifications where user_id = :'X' and kind = 'new_followers'));
