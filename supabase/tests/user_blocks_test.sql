-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 061: 사용자 차단 - 표/RLS/권한, 자기 자신·운영자 차단 불가, 비로그인 불가, 고치기 불가, 남의 차단 안 보임,
--      글 목록·검색에서 빠짐(해제하면 돌아옴), 댓글·답글 알림 안 만듦·합친 수에서 뺌, 팔로우 끊기, 새 팔로워 수에서 뺌, 탈퇴하면 지워짐
\set ON_ERROR_STOP 1
\set QUIET 1
\set A '00000000-0000-0000-0000-00000000000a'
\set B '00000000-0000-0000-0000-00000000000b'
\set D '00000000-0000-0000-0000-00000000000d'
\set F '00000000-0000-0000-0000-00000000000f'
\set W '00000000-0000-0000-0000-000000000012'
\set G '00000000-0000-0000-0000-0000000000a1'
insert into auth.users (id, email) values (:'A', 'op@x.com'), (:'B', 'b@x.com'), (:'D', 'd@x.com'), (:'F', 'f@x.com'), (:'W', 'w@x.com');
insert into auth.users (id, is_anonymous) values (:'G', true);
update public.profiles set nickname = '영자', role = 'admin' where id = :'A';
update public.profiles set nickname = '비' where id = :'B';
update public.profiles set nickname = '디' where id = :'D';
update public.profiles set nickname = '에프' where id = :'F';
update public.profiles set nickname = 'Faker', influencer = 'pro', influencer_at = now() - interval '2 days' where id = :'W';
update public.profiles set nickname = '손님' where id = :'G';
update public.xp_rules set value = 0 where key in ('post_interval', 'comment_interval');

create function pg_temp.notes(u uuid, k text) returns integer language sql as $$
  select count(*)::integer from public.notifications where user_id = u and kind = k $$;
create function pg_temp.msg(u uuid, k text) returns text language sql as $$
  select message from public.notifications where user_id = u and kind = k order by id desc limit 1 $$;
create function pg_temp.titles(p jsonb) returns text language sql as $$
  select coalesce(string_agg(e ->> 'title', ',' order by (e ->> 'id')::bigint), '') from jsonb_array_elements(p -> 'rows') e $$;
grant execute on all functions in schema pg_temp to anon, authenticated;

-- ===================================================================
-- 1. 표 / RLS / 권한
-- ===================================================================
select t.ok('RLS 켜짐 + 정책 3개 (읽기·넣기·지우기)', (select relrowsecurity from pg_class where oid = 'public.user_blocks'::regclass)
  and (select count(*) from pg_policy where polrelid = 'public.user_blocks'::regclass) = 3
  and not exists (select 1 from pg_policy where polrelid = 'public.user_blocks'::regclass and polcmd not in ('r', 'a', 'd')));
select t.ok('로그인: 읽기·넣기·지우기만 (고치기 없음)', has_table_privilege('authenticated', 'public.user_blocks', 'select')
  and has_table_privilege('authenticated', 'public.user_blocks', 'insert') and has_table_privilege('authenticated', 'public.user_blocks', 'delete')
  and not has_table_privilege('authenticated', 'public.user_blocks', 'update'));
select t.ok('비로그인: 권한 없음', not exists (
  select 1 from unnest(array['select', 'insert', 'update', 'delete']) p where has_table_privilege('anon', 'public.user_blocks', p)));
select t.ok('트리거 함수는 아무도 못 부름', not has_function_privilege('authenticated', 'public.user_blocks_check()', 'execute')
  and not has_function_privilege('anon', 'public.user_blocks_unfollow()', 'execute'));
select t.ok('두 칸 모두 프로필 참조 + 지우면 함께 (cascade)', (select count(*) from pg_constraint
  where conrelid = 'public.user_blocks'::regclass and contype = 'f' and confrelid = 'public.profiles'::regclass and confdeltype = 'c') = 2);

set role anon;
select t.fails('비로그인 차단 불가', format('insert into user_blocks (blocker_id, blocked_id) values (%L, %L)', :'B', :'D'), 'permission denied');
select t.fails('비로그인 목록 못 읽음', 'select * from user_blocks', 'permission denied');
select t.ok('비로그인 my_blocked_ids = 빈 목록', my_blocked_ids() = '{}'::uuid[]);
reset role;

set role authenticated;
set request.jwt.claim.sub = :'B';
select t.fails('자기 자신 차단 불가', format('insert into user_blocks (blocker_id, blocked_id) values (%L, %L)', :'B', :'B'), 'user_blocks_not_self');
select t.fails('남의 이름으로 차단 불가', format('insert into user_blocks (blocker_id, blocked_id) values (%L, %L)', :'F', :'D'), 'row-level security');
select t.fails('운영자 계정 차단 불가', format('insert into user_blocks (blocker_id, blocked_id) values (%L, %L)', :'B', :'A'), '운영자 계정은 차단할 수 없습니다');
insert into user_blocks (blocker_id, blocked_id, created_at) values (:'B', :'D', now() - interval '9 days');
select t.ok('차단됨 + 시각은 DB 시각', (select created_at > now() - interval '1 minute' from user_blocks where blocker_id = :'B' and blocked_id = :'D'));
select t.fails('같은 사람 두 번 차단 불가 (기본 키)', format('insert into user_blocks (blocker_id, blocked_id) values (%L, %L)', :'B', :'D'), 'duplicate key');
select t.fails('고치기 거부', format('update user_blocks set blocked_id = %L where blocker_id = %L', :'F', :'B'), 'permission denied');
set request.jwt.claim.sub = :'F';
select t.ok('남의 차단 목록은 안 보임', (select count(*) from user_blocks) = 0 and my_blocked_ids() = '{}'::uuid[]);
delete from user_blocks where blocker_id = :'B';
reset role;
select t.ok('남의 차단은 못 지움', exists (select 1 from user_blocks where blocker_id = :'B' and blocked_id = :'D'));
set role authenticated;
set request.jwt.claim.sub = :'D';
select t.ok('차단당한 사람에게는 아무것도 안 보임', (select count(*) from user_blocks) = 0);
set request.jwt.claim.sub = :'G';
insert into user_blocks (blocker_id, blocked_id) values (:'G', :'D');
select t.ok('비회원(익명 로그인)도 차단 가능', my_blocked_ids() = array[:'D'::uuid]);
delete from user_blocks where blocked_id = :'D';
reset role;
select t.ok('차단 해제 = 본인 줄 지우기', not exists (select 1 from user_blocks where blocker_id = :'G'));

-- ===================================================================
-- 2. 커뮤니티 글 목록·검색: 차단한 사람의 글이 빠지고, 해제하면 돌아온다
-- ===================================================================
set role authenticated;
set request.jwt.claim.sub = :'D';
select create_post('디 글', '차단될 글') as pd \gset
set request.jwt.claim.sub = :'F';
select create_post('에프 글', '보이는 글') as pf \gset
set request.jwt.claim.sub = :'B';
select t.ok('차단한 사람 글 빠짐 (목록·전체 수)', pg_temp.titles(board_page(null, 1, 20)) = '에프 글'
  and (board_page(null, 1, 20) ->> 'total')::int = 1);
select t.ok('검색에서도 빠짐', (board_page('글', 1, 20) ->> 'total')::int = 1 and pg_temp.titles(board_page('글', 1, 20)) = '에프 글');
set request.jwt.claim.sub = :'D';
select t.ok('차단당한 사람에게는 그대로', pg_temp.titles(board_page(null, 1, 20)) = '디 글,에프 글');
set request.jwt.claim.sub = :'F';
select t.ok('다른 사람에게는 그대로', (board_page(null, 1, 20) ->> 'total')::int = 2);
reset role;
set role anon;
select t.ok('비로그인에게는 그대로', (board_page(null, 1, 20) ->> 'total')::int = 2);
reset role;
set role authenticated;
set request.jwt.claim.sub = :'B';
delete from user_blocks where blocked_id = :'D';
select t.ok('해제하면 다시 보임', pg_temp.titles(board_page(null, 1, 20)) = '디 글,에프 글');
insert into user_blocks (blocker_id, blocked_id) values (:'B', :'D');
reset role;

-- ===================================================================
-- 3. 알림: 받는 사람이 차단한 사람의 댓글·답글로는 만들지 않고, 합친 수에서도 뺀다
-- ===================================================================
delete from notifications;
set role authenticated;
set request.jwt.claim.sub = :'B';
select create_post('비 글', '본문') as pb \gset
select create_comment(:pb, '비 댓글') as cb \gset
set request.jwt.claim.sub = :'D';
select create_comment(:pb, '디 댓글 (차단됨)');
select create_comment(:pb, '디 답글 (차단됨)', '{}', :cb);
reset role;
select t.ok('차단한 사람의 댓글·답글 -> 알림 없음', pg_temp.notes(:'B', 'post_comment') = 0 and pg_temp.notes(:'B', 'comment_reply') = 0);
set role authenticated;
set request.jwt.claim.sub = :'F';
select create_comment(:pb, '에프 댓글');
set request.jwt.claim.sub = :'D';
select create_comment(:pb, '디 또 댓글');
set request.jwt.claim.sub = :'F';
select create_comment(:pb, '에프 또 댓글');
reset role;
select t.ok('다른 사람 댓글은 알림 + 합친 수에서 차단한 사람 것은 뺌 (2개)',
  pg_temp.notes(:'B', 'post_comment') = 1 and pg_temp.msg(:'B', 'post_comment') like '%새 댓글 2개%');
set role authenticated;
set request.jwt.claim.sub = :'F';
select create_comment(:pb, '에프 답글', '{}', :cb);
set request.jwt.claim.sub = :'D';
select create_comment(:pb, '디 또 답글', '{}', :cb);
set request.jwt.claim.sub = :'F';
select create_comment(:pb, '에프 또 답글', '{}', :cb);
reset role;
select t.ok('답글 알림도 차단한 사람 것은 빼고 셈 (2개)',
  pg_temp.notes(:'B', 'comment_reply') = 1 and pg_temp.msg(:'B', 'comment_reply') like '%새 답글 2개%');
-- 차단당한 사람은 그대로 알림을 받는다 (차단 사실이 드러나지 않게)
set role authenticated;
set request.jwt.claim.sub = :'D';
select create_post('디 두번째 글', '본문') as pd2 \gset
set request.jwt.claim.sub = :'B';
select create_comment(:pd2, '비가 디 글에 댓글');
reset role;
select t.ok('차단당한 사람은 차단한 사람의 댓글 알림을 그대로 받음', pg_temp.notes(:'D', 'post_comment') = 1);
-- 문서 댓글 답글
delete from notifications;
set role authenticated;
set request.jwt.claim.sub = :'B';
select create_doc_comment((select id from counters limit 1), '비 문서 댓글') as dc \gset
set request.jwt.claim.sub = :'D';
select create_doc_comment((select id from counters limit 1), '디 문서 답글', :dc);
reset role;
select t.ok('문서 댓글 답글도 차단한 사람 것은 알림 없음', pg_temp.notes(:'B', 'comment_reply') = 0);
set role authenticated;
set request.jwt.claim.sub = :'F';
select create_doc_comment((select id from counters limit 1), '에프 문서 답글', :dc);
reset role;
select t.ok('다른 사람 문서 답글은 알림', pg_temp.notes(:'B', 'comment_reply') = 1);

-- ===================================================================
-- 4. 장인 팔로우: 차단하면 내 팔로우가 끊기고, 장인이 차단한 팔로워는 새 팔로워 수에서 빠진다
-- ===================================================================
delete from notifications;
delete from public.follow_rate;
select follow_influencer_unchecked(:'B', :'W');
select follow_influencer_unchecked(:'D', :'W');
select follow_influencer_unchecked(:'F', :'W');
set role authenticated;
set request.jwt.claim.sub = :'B';
insert into user_blocks (blocker_id, blocked_id) values (:'B', :'W');
set request.jwt.claim.sub = :'W';
insert into user_blocks (blocker_id, blocked_id) values (:'W', :'D');
reset role;
select t.ok('장인을 차단하면 내 팔로우가 끊김', not exists (select 1 from influencer_follows where follower_id = :'B' and influencer_id = :'W'));
select t.ok('장인이 차단한 팔로워의 팔로우는 그대로 (차단 사실이 드러나지 않게)',
  exists (select 1 from influencer_follows where follower_id = :'D' and influencer_id = :'W'));
select new_follower_digest();
select t.ok('새 팔로워 수에서 차단한 팔로워는 뺌 (1명)', pg_temp.msg(:'W', 'new_followers') = '오늘 새 팔로워 1명이 생겼습니다.');

-- ===================================================================
-- 5. 탈퇴: 차단한 사람·차단당한 사람 누가 탈퇴해도 차단 줄이 지워진다
-- ===================================================================
select t.ok('탈퇴 전 차단 줄', (select count(*) from user_blocks where :'D' in (blocker_id, blocked_id)) = 2
  and (select count(*) from user_blocks where blocker_id = :'B') = 2);
set role authenticated;
set request.jwt.claim.sub = :'D';
select delete_my_account('디');
reset role;
select t.ok('차단당한 사람이 탈퇴 -> 그 줄 지워짐', not exists (select 1 from user_blocks where :'D' in (blocker_id, blocked_id)));
set role authenticated;
set request.jwt.claim.sub = :'B';
select delete_my_account('비');
reset role;
select t.ok('차단한 사람이 탈퇴 -> 그 사람의 차단 목록 지워짐', not exists (select 1 from user_blocks where blocker_id = :'B'));
select t.ok('남은 차단 없음', (select count(*) from user_blocks) = 0);
