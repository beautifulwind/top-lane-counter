-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 045: 게시판 신고(글·댓글·문서 댓글) → 운영진 알림 report_received
--      (처음 생긴 처리 전 신고만 · 신고자 본인 제외 · 감독관은 처리할 수 있는 대상만 · 운영자 모드 · 푸시 묶음 · 예외)
\set ON_ERROR_STOP 1
\set QUIET 1
\set OP  '00000000-0000-0000-0000-00000000000a'
\set MOD '00000000-0000-0000-0000-00000000000b'
\set U   '00000000-0000-0000-0000-00000000000d'
\set V   '00000000-0000-0000-0000-00000000000c'
\set W   '00000000-0000-0000-0000-00000000000f'
\set X   '00000000-0000-0000-0000-000000000011'
\set GU  '00000000-0000-0000-0000-000000000010'
insert into auth.users (id, email) values (:'OP', 'op@x.com'), (:'MOD', 'm@x.com'), (:'U', 'u@x.com'), (:'V', 'v@x.com'), (:'W', 'w@x.com'), (:'X', 'x@x.com');
insert into auth.users (id, email, is_anonymous) values (:'GU', null, true);
update public.profiles set nickname = '영자', role = 'admin' where id = :'OP';
update public.profiles set nickname = '감독', role = 'moderator' where id = :'MOD';
update public.profiles set nickname = '유저' where id = :'U';
update public.profiles set nickname = '브이' where id = :'V';
update public.profiles set nickname = '더블유' where id = :'W';
update public.profiles set nickname = '엑스' where id = :'X';
update public.profiles set nickname = '손님' where id = :'GU';
create temp table ids (k text primary key, v bigint);
grant all on ids to authenticated, anon;
create function pg_temp.id(p text) returns bigint language sql stable as $$ select v from ids where k = p $$;
insert into ids select 'quinn', id from counters where counter_champion = 'Quinn' limit 1;

-- ===== 0. 준비: 유저 글·댓글·문서 댓글, 운영자 글, 감독관 글 =====
set role authenticated;
set request.jwt.claim.sub = :'U';
insert into ids values ('p_u', public.create_post('유저 글', '본문입니다 본문입니다'));
insert into ids values ('c_u', public.create_comment(pg_temp.id('p_u'), '유저 댓글'));
reset role;
delete from board_last_write;
set role authenticated;
set request.jwt.claim.sub = :'U';
insert into ids values ('d_u', public.create_doc_comment(pg_temp.id('quinn'), '유저 문서 댓글'));
set request.jwt.claim.sub = :'OP';
insert into ids values ('p_op', public.create_post('운영자 글', '본문입니다 본문입니다'));
set request.jwt.claim.sub = :'MOD';
insert into ids values ('p_mod', public.create_post('감독관 글', '본문입니다 본문입니다'));
reset role;
delete from notifications;
select t.ok('준비 끝 (알림 0)', (select count(*) from notifications) = 0);

-- ===== 1. 글 신고: 운영자·감독관에게 한 줄, 신고자 본인은 제외 =====
set role authenticated;
set request.jwt.claim.sub = :'V';
select report_post(pg_temp.id('p_u'), 'abuse');
reset role;
select t.ok('글 신고: 운영자·감독관에게 report_received (문장·글 번호)',
  (select count(*) from notifications where kind = 'report_received' and user_id in (:'OP', :'MOD')
     and message = '새 신고가 들어왔습니다. (글)' and post_id = pg_temp.id('p_u') and counter_id is null) = 2);
select t.ok('받는 사람은 운영진뿐 (신고자·글쓴이·다른 회원에게 안 감)',
  not exists (select 1 from notifications where kind = 'report_received' and user_id not in (:'OP', :'MOD')));

-- ===== 2. 같은 대상에 처리 전 신고가 이미 있으면 알림 없음 =====
set role authenticated;
set request.jwt.claim.sub = :'W';
select report_post(pg_temp.id('p_u'), 'spam');
reset role;
select t.ok('같은 글 둘째 신고: 알림 안 늘어남', (select count(*) from notifications where kind = 'report_received') = 2);

-- ===== 3. 댓글·문서 댓글 신고 =====
set role authenticated;
set request.jwt.claim.sub = :'V';
select report_comment(pg_temp.id('c_u'), 'abuse');
select report_doc_comment(pg_temp.id('d_u'), 'spam');
reset role;
select t.ok('댓글 신고: 문장 「(댓글)」, 그 댓글이 달린 글 번호',
  (select count(*) from notifications where kind = 'report_received' and message = '새 신고가 들어왔습니다. (댓글)' and post_id = pg_temp.id('p_u')) = 2);
select t.ok('문서 댓글 신고: 문장 「(문서 댓글)」, 상대법 번호',
  (select count(*) from notifications where kind = 'report_received' and message = '새 신고가 들어왔습니다. (문서 댓글)'
     and counter_id = pg_temp.id('quinn') and post_id is null) = 2);

-- ===== 4. 예외: 자기 글·거부된 신고는 알림 없음 =====
set role authenticated;
set request.jwt.claim.sub = :'U';
select t.fails('내 글 신고 불가', format('select report_post(%s, %L)', pg_temp.id('p_u'), 'abuse'), '내 글은 신고할 수 없습니다');
select t.fails('내 댓글 신고 불가', format('select report_comment(%s, %L)', pg_temp.id('c_u'), 'abuse'), '내 댓글은 신고할 수 없습니다');
select t.fails('내 문서 댓글 신고 불가', format('select report_doc_comment(%s, %L)', pg_temp.id('d_u'), 'abuse'), '내 댓글은 신고할 수 없습니다');
set request.jwt.claim.sub = :'V';
select t.fails('같은 사람이 같은 글을 다시 신고 불가', format('select report_post(%s, %L)', pg_temp.id('p_u'), 'abuse'), '이미 신고한 글');
set request.jwt.claim.sub = :'GU';
select t.fails('비회원 신고 불가', format('select report_post(%s, %L)', pg_temp.id('p_u'), 'abuse'), '');
reset role;
select t.ok('거부된 신고는 알림을 만들지 않음 (그대로 6건: 글 2·댓글 2·문서 댓글 2)', (select count(*) from notifications where kind = 'report_received') = 6);

-- ===== 5. 처리된 뒤 다른 사람이 다시 신고하면 새 "처음"으로 보고 다시 보냄 =====
set role authenticated;
set request.jwt.claim.sub = :'OP';
select dismiss_reports(pg_temp.id('p_u'), null, '문제 없음');
reset role;
select t.ok('기각 뒤 그 글의 처리 전 신고 0건', not exists (select 1 from reports where post_id = pg_temp.id('p_u') and status = 'open'));
set role authenticated;
set request.jwt.claim.sub = :'X';
select report_post(pg_temp.id('p_u'), 'privacy');
reset role;
select t.ok('기각된 글에 다른 사람이 새로 신고: 다시 알림 (글 알림 2 → 4)',
  (select count(*) from notifications where kind = 'report_received' and message = '새 신고가 들어왔습니다. (글)') = 4);
set role authenticated;
set request.jwt.claim.sub = :'OP';
select hide_post(pg_temp.id('p_u'), '광고');
set request.jwt.claim.sub = :'W';
select t.fails('숨긴 글은 신고 불가', format('select report_post(%s, %L)', pg_temp.id('p_u'), 'abuse'), '신고할 수 없는 글');
reset role;

-- ===== 6. 운영진이 쓴 글 · 운영진이 낸 신고 =====
delete from notifications;
set role authenticated;
set request.jwt.claim.sub = :'V';
select report_post(pg_temp.id('p_op'), 'abuse');
select report_post(pg_temp.id('p_mod'), 'abuse');
reset role;
select t.ok('운영자 글 신고: 운영자에게만 (감독관은 처리할 수 없어 안 감)',
  (select array_agg(user_id) from notifications where kind = 'report_received' and post_id = pg_temp.id('p_op')) = array[:'OP'::uuid]);
select t.ok('감독관 글 신고: 운영자에게만 (본인 글이라 감독관 제외)',
  (select array_agg(user_id) from notifications where kind = 'report_received' and post_id = pg_temp.id('p_mod')) = array[:'OP'::uuid]);
delete from notifications;
set role authenticated;
set request.jwt.claim.sub = :'MOD';
select report_post(pg_temp.id('p_op'), 'spam');
reset role;
select t.ok('이미 처리 전 신고가 있는 글에 운영진이 또 신고: 알림 없음', not exists (select 1 from notifications where kind = 'report_received'));

-- 새 대상: 유저 글 둘째. 감독관이 신고 → 운영자에게만 / 운영자가 신고 → 감독관에게만
set role authenticated;
set request.jwt.claim.sub = :'U';
insert into ids values ('p_u2', public.create_post('유저 글 둘', '본문입니다 본문입니다'));
reset role;
delete from board_last_write;
set role authenticated;
set request.jwt.claim.sub = :'U';
insert into ids values ('p_u3', public.create_post('유저 글 셋', '본문입니다 본문입니다'));
reset role;
set role authenticated;
set request.jwt.claim.sub = :'MOD';
select report_post(pg_temp.id('p_u2'), 'spam');
set request.jwt.claim.sub = :'OP';
select report_post(pg_temp.id('p_u3'), 'spam');
reset role;
select t.ok('감독관이 낸 신고: 운영자에게만',
  (select array_agg(user_id) from notifications where kind = 'report_received' and post_id = pg_temp.id('p_u2')) = array[:'OP'::uuid]);
select t.ok('운영자가 낸 신고: 운영자 본인에게는 안 가고 감독관에게만',
  (select array_agg(user_id) from notifications where kind = 'report_received' and post_id = pg_temp.id('p_u3')) = array[:'MOD'::uuid]);

-- ===== 7. 운영자 모드 · 모두 읽음 · 푸시 묶음 =====
delete from notifications;
delete from reports where post_id = pg_temp.id('p_u2');
set role authenticated;
set request.jwt.claim.sub = :'V';
select report_post(pg_temp.id('p_u2'), 'abuse');
set request.jwt.claim.sub = :'OP';
select t.ok('운영자: 신고 알림이 보임', (select count(*) from notifications where kind = 'report_received') = 1);
select set_operator_mode(false);
select t.ok('운영자 모드 끔: 신고 알림이 안 보임', (select count(*) from notifications where kind = 'report_received') = 0);
select mark_all_notifications_read(9999999);
select set_operator_mode(true);
select t.ok('운영자 모드 끔 동안 [모두 읽음]은 신고 알림을 건드리지 않음',
  (select count(*) from notifications where kind = 'report_received' and read_at is null) = 1);
set request.jwt.claim.sub = :'MOD';
select t.ok('감독관: 신고 알림이 보임', (select count(*) from notifications where kind = 'report_received') = 1);
reset role;
select t.ok('푸시 묶음: 새 신고 = 운영진 알림, 있던 묶음은 그대로',
  push_group('report_received') = 'staff_new' and push_group('error_reported') = 'staff_new'
  and push_group('post_created') = 'staff_new' and push_group('proposal_approved') = 'my_results' and push_group('error_report_handled') is null);
select t.ok('트리거 함수는 로그인 사용자가 직접 못 부름',
  not has_function_privilege('authenticated', 'public.notify_staff_new_report()', 'execute')
  and not has_function_privilege('anon', 'public.notify_staff_new_report()', 'execute'));

select '045 report_received 검사 끝' as done;
