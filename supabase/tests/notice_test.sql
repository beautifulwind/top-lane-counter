-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 051: 공지 + 공지 알림 (표/RLS, 운영자만 공지 올리기, [알림 보내기] 끄기, 대기 줄 나눠 보내기, 두 번 안 감,
--      숨김/삭제/오래된 줄 버림, 탈퇴 계정 제외, 고쳐도 다시 안 감, 운영자 새 글 알림과 안 겹침, 목록 고정, 푸시 묶음, 읽음)
\set ON_ERROR_STOP 1
\set QUIET 1
\set OP  '00000000-0000-0000-0000-00000000000a'
\set MOD '00000000-0000-0000-0000-00000000000b'
\set U   '00000000-0000-0000-0000-00000000000d'
\set V   '00000000-0000-0000-0000-00000000000c'
\set GU  '00000000-0000-0000-0000-000000000010'
\set GN  '00000000-0000-0000-0000-000000000011'
insert into auth.users (id, email) values (:'OP', 'op@x.com'), (:'MOD', 'm@x.com'), (:'U', 'u@x.com'), (:'V', 'v@x.com');
insert into auth.users (id, email, is_anonymous) values (:'GU', null, true), (:'GN', null, true);
update public.profiles set nickname = '영자', role = 'admin' where id = :'OP';
update public.profiles set nickname = '감독', role = 'moderator' where id = :'MOD';
update public.profiles set nickname = '유저' where id = :'U';
update public.profiles set nickname = '브이' where id = :'V';
update public.profiles set nickname = '손님' where id = :'GU';
-- GN: 닉네임을 아직 정하지 않은 게스트
update public.xp_rules set value = 0 where key in ('post_interval', 'comment_interval');
delete from notifications;
delete from notice_notify_queue;
create temp table ids (k text primary key, v bigint);
grant all on ids to authenticated, anon;

-- ===== 1. 표 / RLS / 알림 종류 =====
select t.ok('대기 줄 RLS 켜짐 + 정책 없음', (select relrowsecurity from pg_class where oid = 'public.notice_notify_queue'::regclass)
  and not exists (select 1 from pg_policy where polrelid = 'public.notice_notify_queue'::regclass));
select t.ok('대기 줄 권한 없음 (anon/authenticated 읽기/넣기/고치기/지우기)', not exists (
  select 1 from unnest(array['anon', 'authenticated']) r, unnest(array['select', 'insert', 'update', 'delete']) p
   where has_table_privilege(r, 'public.notice_notify_queue', p)));
set role authenticated;
set request.jwt.claim.sub = :'U';
select t.fails('로그인 사용자 대기 줄 직접 읽기 거부', 'select * from notice_notify_queue', 'permission denied');
select t.fails('로그인 사용자 대기 줄 직접 넣기 거부', 'insert into notice_notify_queue (post_id) values (1)', 'permission denied');
select t.fails('공지 표시 직접 고치기 거부', 'update posts set is_notice = true', 'permission denied');
reset role;
set role anon;
select t.fails('비로그인 대기 줄 직접 읽기 거부', 'select * from notice_notify_queue', 'permission denied');
reset role;
select t.ok('알림 종류에 notice_posted (있던 종류 그대로)', (select pg_get_constraintdef(oid) like '%notice_posted%'
  and pg_get_constraintdef(oid) like '%followed_build_created%' and pg_get_constraintdef(oid) like '%link_removed%' from pg_constraint
  where conname = 'notifications_kind_check' and conrelid = 'public.notifications'::regclass));
select t.ok('설정값 늘지 않음 (63)', (select count(*) from xp_rules) = 63);

-- ===== 2. 함수 권한 =====
set role anon;
select t.fails('비로그인 공지 올리기 거부', 'select create_notice(''공지'', ''본문'')', 'permission denied');
select t.fails('비로그인 보내기 직접 호출 거부', 'select notice_notify_dispatch()', 'permission denied');
reset role;
set role authenticated;
set request.jwt.claim.sub = :'U';
select t.fails('로그인 사용자 보내기 직접 호출 거부', 'select notice_notify_dispatch()', 'permission denied');
select t.fails('일반 회원 공지 거부', 'select create_notice(''공지'', ''본문'')', '운영자만');
set request.jwt.claim.sub = :'MOD';
select t.fails('감독관 공지 거부', 'select create_notice(''공지'', ''본문'')', '운영자만');
set request.jwt.claim.sub = :'GU';
select t.fails('게스트 공지 거부', 'select create_notice(''공지'', ''본문'')', '운영자만');
set request.jwt.claim.sub = :'OP';
select set_operator_mode(false);
select t.fails('운영자 모드 꺼짐 거부', 'select create_notice(''공지'', ''본문'')', '운영자만');
select set_operator_mode(true);
select t.fails('제목 없는 공지 거부', 'select create_notice('' '', ''본문'')', '제목');
reset role;
select t.ok('거부된 공지는 글도 대기 줄도 없음', not exists (select 1 from posts) and not exists (select 1 from notice_notify_queue));

-- ===== 3. 공지 올리기 =====
set role authenticated;
set request.jwt.claim.sub = :'OP';
insert into ids values ('n1', create_notice('점검 안내', '오늘 밤 점검합니다.'));
insert into ids values ('n2', create_notice('알림 없는 공지', '조용히 올립니다.', '{}', false));
reset role;
select t.ok('공지 표시가 붙음', (select bool_and(is_notice) from posts where id in (select v from ids)));
select t.ok('[알림 보내기] 켬 = 대기 줄 한 줄 / 끔 = 없음', (select count(*) from notice_notify_queue) = 1
  and exists (select 1 from notice_notify_queue where post_id = (select v from ids where k = 'n1')));
select t.ok('올릴 때는 알림을 바로 만들지 않음 (대기 줄만)', not exists (select 1 from notifications where kind = 'notice_posted'));
select t.ok('운영자 본인이 쓴 공지라 운영자 새 글 알림(post_created)도 없음', not exists (select 1 from notifications where kind = 'post_created'));
set role authenticated;
set request.jwt.claim.sub = :'U';
insert into ids values ('p1', create_post('보통 글', '본문'));
reset role;
select t.ok('보통 글은 그대로 운영자 새 글 알림', (select count(*) from notifications where kind = 'post_created' and user_id = :'OP') = 1
  and not (select is_notice from posts where id = (select v from ids where k = 'p1')));

-- ===== 4. 나눠 보내기 =====
-- 대상: 공지를 쓴 OP를 뺀 가입자 전부 = MOD, U, V, GU, GN (5명)
select notice_notify_dispatch(4) as d1 \gset
select t.ok('1분에 4명까지: 4명 보내고 대기 줄에 이어서 표시', (:'d1'::jsonb ->> 'sent')::int = 4 and (:'d1'::jsonb ->> 'left')::int = 1
  and (select after_user is not null from notice_notify_queue));
select notice_notify_dispatch(4) as d2 \gset
select t.ok('다음 실행에서 나머지 1명, 대기 줄 끝', (:'d2'::jsonb ->> 'sent')::int = 1 and (:'d2'::jsonb ->> 'left')::int = 0);
select t.ok('가입자 모두(게스트·닉네임 없는 게스트·운영진 포함) 한 개씩, 쓴 운영자는 빼고',
  (select array_agg(user_id::text order by user_id::text) from notifications where kind = 'notice_posted')
    = (select array_agg(id::text order by id::text) from profiles where id <> :'OP'));
select t.ok('문장과 공지 연결', (select bool_and(message = '새 공지가 올라왔습니다. 「점검 안내」' and post_id = (select v from ids where k = 'n1'))
  from notifications where kind = 'notice_posted'));
select t.ok('알림 없는 공지(n2)는 알림 없음', not exists (select 1 from notifications where post_id = (select v from ids where k = 'n2')));
select t.ok('대기 줄이 없으면 아무것도 안 함', notice_notify_dispatch() ->> 'sent' = '0');

-- ===== 5. 같은 공지는 두 번 가지 않음 =====
insert into notice_notify_queue (post_id) values ((select v from ids where k = 'n1'));
select notice_notify_dispatch() as d3 \gset
select t.ok('대기 줄이 다시 생겨도 이미 받은 사람은 건너뜀', (:'d3'::jsonb ->> 'sent')::int = 0 and (:'d3'::jsonb ->> 'skipped_dup')::int = 5
  and (select count(*) from notifications where kind = 'notice_posted') = 5);
select t.fails('같은 사람에게 같은 공지 알림 두 번 넣기 거부 (부분 유일 인덱스)',
  format('insert into notifications (user_id, kind, message, post_id) values (%L, ''notice_posted'', ''x'', %s)', :'U', (select v from ids where k = 'n1')),
  'notifications_notice_once');
select t.fails('대기 줄도 공지마다 한 줄', format('insert into notice_notify_queue (post_id) values (%s), (%s)',
  (select v from ids where k = 'n1'), (select v from ids where k = 'n1')), 'notice_notify_queue_post');
set role authenticated;
set request.jwt.claim.sub = :'OP';
select edit_post((select v from ids where k = 'n1'), '점검 안내 (시간 변경)', '내일 밤 점검합니다.');
reset role;
select t.ok('공지를 고쳐도 대기 줄/알림 없음', not exists (select 1 from notice_notify_queue)
  and (select count(*) from notifications where kind = 'notice_posted') = 5);

-- ===== 6. 보내기 전에 숨김/삭제/오래됨 -> 버림, 탈퇴한 계정은 대상 아님 =====
set role authenticated;
set request.jwt.claim.sub = :'OP';
insert into ids values ('n3', create_notice('숨길 공지', '본문'));
select hide_post((select v from ids where k = 'n3'), '잘못 올림');
insert into ids values ('n4', create_notice('지울 공지', '본문'));
select delete_my_post((select v from ids where k = 'n4'));
insert into ids values ('n5', create_notice('늦은 공지', '본문'));
reset role;
update notice_notify_queue set created_at = now() - interval '2 days' where post_id = (select v from ids where k = 'n5');
select notice_notify_dispatch() as d4 \gset
select t.ok('숨긴/지운/시작 전에 하루 지난 공지는 보내지 않고 버림', (:'d4'::jsonb ->> 'dropped')::int = 3 and (:'d4'::jsonb ->> 'sent')::int = 0
  and not exists (select 1 from notice_notify_queue)
  and not exists (select 1 from notifications where post_id in (select v from ids where k in ('n3', 'n4', 'n5'))));
-- 이미 보내기 시작한 줄은 하루가 지나도 끝까지 보냄
set role authenticated;
set request.jwt.claim.sub = :'OP';
insert into ids values ('n6', create_notice('긴 공지', '본문'));
reset role;
select notice_notify_dispatch(2);
update notice_notify_queue set created_at = now() - interval '2 days';
-- 보내는 도중에 V 탈퇴 -> V는 대상에서 빠짐
set role authenticated;
set request.jwt.claim.sub = :'V';
select delete_my_account('브이');
reset role;
select notice_notify_dispatch();
select t.ok('시작한 공지는 끝까지 / 탈퇴한 계정에는 없음', not exists (select 1 from notice_notify_queue)
  and (select count(*) from notifications where post_id = (select v from ids where k = 'n6')) = (select count(*) from profiles where id <> :'OP')
  and not exists (select 1 from profiles where id = :'V'));

-- ===== 7. 목록: 공지 표시와 1쪽 고정 =====
set role anon;
select board_page() as bp \gset
select t.ok('줄마다 is_notice', (select bool_and(i ? 'is_notice') from jsonb_array_elements(:'bp'::jsonb -> 'rows') i)
  and exists (select 1 from jsonb_array_elements(:'bp'::jsonb -> 'rows') i where (i ->> 'is_notice')::boolean)
  and exists (select 1 from jsonb_array_elements(:'bp'::jsonb -> 'rows') i where not (i ->> 'is_notice')::boolean));
select t.ok('1쪽 고정 공지: 최근 순, 숨김/삭제 제외, 최대 3개',
  (select array_agg(i ->> 'title' order by n) from jsonb_array_elements(:'bp'::jsonb -> 'notices') with ordinality x(i, n))
    = array['긴 공지', '늦은 공지', '알림 없는 공지']);
select t.ok('2쪽/검색에는 고정 공지 없음', board_page(null, 2) -> 'notices' = '[]'::jsonb and board_page('점검') -> 'notices' = '[]'::jsonb);
reset role;
set role authenticated;
set request.jwt.claim.sub = :'OP';
select t.ok('운영진에게는 숨긴 공지도 보임', exists (select 1 from jsonb_array_elements(board_page() -> 'notices') i where i ->> 'title' = '숨길 공지'));
reset role;

-- ===== 8. 읽기 / 모두 읽음 (운영자 모드와 관계없이 보임) =====
set role authenticated;
set request.jwt.claim.sub = :'GU';
select t.ok('게스트 본인 공지 알림 읽기', (select count(*) from notifications where kind = 'notice_posted') = 2);
select t.ok('남의 알림은 안 보임', not exists (select 1 from notifications where user_id <> :'GU'));
reset role;
-- 운영자는 자기가 쓴 공지 알림을 받지 않으므로, 운영자 모드 검사용으로 한 줄 넣는다
insert into notifications (user_id, kind, message, post_id) values (:'OP', 'notice_posted', '새 공지가 올라왔습니다. 「검사」', (select v from ids where k = 'p1'));
set role authenticated;
set request.jwt.claim.sub = :'OP';
select set_operator_mode(false);
select t.ok('운영자 모드를 꺼도 공지 알림은 보임', (select count(*) from notifications where kind = 'notice_posted') = 1);
select mark_all_notifications_read((select max(id) from notifications));
select t.ok('모두 읽음에 함께 읽음 처리', not exists (select 1 from notifications where kind = 'notice_posted' and read_at is null));
select set_operator_mode(true);
reset role;
select t.ok('읽기 정책/모두 읽음의 운영진 목록에는 없음', (select pg_get_expr(polqual, polrelid) not like '%notice_posted%' from pg_policy
  where polname = 'notifications: 본인 읽기') and (select prosrc not like '%notice_posted%' from pg_proc where proname = 'mark_all_notifications_read'));

-- ===== 9. 푸시 묶음 notice (기본 켜짐, 따로 끄고 켬) =====
select t.ok('푸시 묶음 notice (있던 묶음 그대로)', push_group('notice_posted') = 'notice' and push_group('followed_build_created') = 'follow_builds'
  and push_group('link_removed') = 'my_results' and push_group('post_created') = 'staff_new');
set role authenticated;
set request.jwt.claim.sub = :'U';
insert into push_subscriptions (user_id, endpoint, p256dh, auth) values (auth.uid(), 'https://push.test/n-1', 'k', 'a');
reset role;
select t.ok('설정 줄이 없으면 켜짐', push_wanted(:'U', 'notice_posted'));
select t.ok('기기를 켜지 않은 사람은 안 감', not push_wanted(:'GU', 'notice_posted'));
set role authenticated;
set request.jwt.claim.sub = :'U';
insert into push_settings (user_id) values (auth.uid());
update push_settings set notice = false where user_id = auth.uid();
reset role;
select t.ok('본인이 notice를 끄면 안 감 (다른 묶음은 그대로)', not push_wanted(:'U', 'notice_posted') and push_wanted(:'U', 'link_removed')
  and push_wanted(:'U', 'followed_build_created'));
set role authenticated;
set request.jwt.claim.sub = :'GU';
update push_settings set notice = true where user_id = :'U';
reset role;
select t.ok('남의 푸시 설정은 못 고침', not (select notice from push_settings where user_id = :'U'));
-- 휴대폰 알림 요청: 새 공지 알림이 생길 때 켠 사람에게만
insert into vault.decrypted_secrets values ('push_function_url', 'https://fn.test/web-push'), ('push_webhook_secret', 's')
  on conflict (name) do nothing;
delete from net.calls;
set role authenticated;
set request.jwt.claim.sub = :'U';
update push_settings set notice = true where user_id = auth.uid();
set request.jwt.claim.sub = :'OP';
insert into ids values ('n7', create_notice('푸시 공지', '본문'));
reset role;
select notice_notify_dispatch();
select t.ok('공지 알림이 생길 때 푸시를 켠 사람(U)에게만 요청 한 번', (select count(*) from net.calls) = 1
  and (select (body ->> 'notification_id')::bigint from net.calls)
      = (select id from notifications where user_id = :'U' and post_id = (select v from ids where k = 'n7')));

-- ===== 10. 글이 지워지면 알림/대기 줄도 =====
delete from posts where id = (select v from ids where k = 'n7');
select t.ok('글을 완전히 지우면 그 공지 알림도 없음 (cascade)', not exists (select 1 from notifications where post_id = (select v from ids where k = 'n7')));
