-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 058: 탑신병자 커뮤니티 답글 (빌드 댓글은 060에서 없앰 - 없어진 것 확인)
--   2단계 제한(함수·표), 부모 확인, 알림(답글·글 주인, 나에게 없음, 합치기), 부모가 지워져도 답글 유지, 경험치, 탈퇴 껍데기, 1년 정리, 권한
--   (문서 댓글 답글은 doc_replies_test, 비회원은 guest_test)
\set ON_ERROR_STOP 1
\set QUIET 1
\set A '00000000-0000-0000-0000-00000000000a'
\set B '00000000-0000-0000-0000-00000000000b'
\set D '00000000-0000-0000-0000-00000000000d'
\set F '00000000-0000-0000-0000-00000000000f'
\set M '00000000-0000-0000-0000-0000000000e1'
\set G '00000000-0000-0000-0000-0000000000a1'
insert into auth.users (id, email) values (:'A', 'op@x.com'), (:'B', 'b@x.com'), (:'D', 'd@x.com'), (:'F', 'f@x.com'), (:'M', 'm@x.com');
insert into auth.users (id, is_anonymous) values (:'G', true);
update public.profiles set nickname = '영자', role = 'admin' where id = :'A';
update public.profiles set nickname = '비' where id = :'B';
update public.profiles set nickname = '디' where id = :'D';
update public.profiles set nickname = '에프' where id = :'F';
update public.profiles set nickname = '감독', role = 'moderator' where id = :'M';
update public.profiles set nickname = '손님' where id = :'G';
update public.xp_rules set value = 0 where key in ('post_interval', 'comment_interval');

create function pg_temp.notes(u uuid, k text) returns integer language sql as $$
  select count(*)::integer from public.notifications where user_id = u and kind = k $$;
create function pg_temp.msg(u uuid, k text) returns text language sql as $$
  select message from public.notifications where user_id = u and kind = k order by id desc limit 1 $$;
grant execute on all functions in schema pg_temp to anon, authenticated;

-- ===================================================================
-- 1. 탑신병자 커뮤니티 답글: 2단계까지, 부모 확인, 알림
-- ===================================================================
set role authenticated;
set request.jwt.claim.sub = :'B';
select create_post('B 글', '본문') as p1 \gset
select create_post('B 다른 글', '본문') as p2 \gset
set request.jwt.claim.sub = :'D';
select create_comment(:p1, 'D 댓글') as c1 \gset
reset role;
select t.ok('글 주인에게 새 댓글 알림 (기존 그대로)', pg_temp.notes(:'B', 'post_comment') = 1);
set role authenticated;
set request.jwt.claim.sub = :'F';
select create_comment(:p1, 'F 답글', '{}', :c1) as r1 \gset
reset role;
select t.ok('답글 저장 (parent_id)', (select parent_id = :c1 from post_comments where id = :r1));
select t.ok('답글: 부모 작성자 D에게 comment_reply (글 id 포함)',
  pg_temp.notes(:'D', 'comment_reply') = 1 and (select post_id = :p1 from notifications where user_id = :'D' and kind = 'comment_reply'));
select t.ok('답글: 글 주인 B는 새 댓글 알림이 합쳐짐 (2개)', pg_temp.notes(:'B', 'post_comment') = 1 and pg_temp.msg(:'B', 'post_comment') like '%새 댓글 2개%');
set role authenticated;
set request.jwt.claim.sub = :'B';
select create_comment(:p1, 'B 답글', '{}', :c1) as r2 \gset
reset role;
select t.ok('같은 글에 또 답글: D의 답글 알림이 합쳐짐', pg_temp.notes(:'D', 'comment_reply') = 1 and pg_temp.msg(:'D', 'comment_reply') like '%새 답글 2개%');
select t.ok('글 주인이 쓴 답글: 글 주인 본인에게 알림 없음', pg_temp.msg(:'B', 'post_comment') like '%새 댓글 2개%');
set role authenticated;
set request.jwt.claim.sub = :'D';
select create_comment(:p1, 'D 자기 댓글에 답글', '{}', :c1) as r3 \gset
reset role;
select t.ok('내 댓글에 내가 답글: 나에게 알림 없음', pg_temp.msg(:'D', 'comment_reply') like '%새 답글 2개%');
update notifications set read_at = now() where user_id in (:'B', :'D');
-- 글 주인이 쓴 댓글에 남이 답글 → 글 주인은 답글 알림 하나만
set role authenticated;
set request.jwt.claim.sub = :'B';
select create_comment(:p1, 'B 댓글') as cb \gset
set request.jwt.claim.sub = :'F';
select create_comment(:p1, 'F가 B에게', '{}', :cb);
reset role;
select t.ok('글 주인 = 부모 작성자: 답글 알림 하나만 (새 댓글 알림 없음)',
  (select count(*) from notifications where user_id = :'B' and read_at is null) = 1
  and (select kind from notifications where user_id = :'B' and read_at is null) = 'comment_reply');

set role authenticated;
set request.jwt.claim.sub = :'F';
select t.fails('3단계 불가 (함수)', format($$select create_comment(%s, 'x', '{}', %s)$$, :p1, :r1), '답글에는 답글을 달 수 없습니다');
select t.fails('다른 글의 댓글에 답글 불가', format($$select create_comment(%s, 'x', '{}', %s)$$, :p2, :c1), '답글을 달 댓글을 찾지 못했습니다');
select t.fails('표에 직접 쓰기 권한 없음', format($$insert into post_comments (post_id, author_id, body, parent_id) values (%s, auth.uid(), 'x', %s)$$, :p1, :r1), 'permission denied');
reset role;
select t.fails('3단계 불가 (표 트리거)', format($$insert into post_comments (post_id, author_id, body, parent_id) values (%s, %L, 'x', %s)$$, :p1, :'F', :r1),
  '답글에는 답글을 달 수 없습니다');
select t.fails('다른 글의 댓글을 부모로 (복합 외래 키)', format($$insert into post_comments (post_id, author_id, body, parent_id) values (%s, %L, 'x', %s)$$, :p2, :'F', :c1),
  'post_comments_parent_fkey');
select t.fails('답글이 달린 댓글을 답글로 바꾸기 불가', format($$update post_comments set parent_id = %s where id = %s$$, :cb, :c1),
  '답글에는 답글을 달 수 없습니다');
select t.ok('글 댓글 수 = 답글 포함', (select comment_count = 6 from posts where id = :p1));

-- ===================================================================
-- 2. 부모를 지워도 답글은 남는다 / 지운·숨긴 부모에는 답글 불가
-- ===================================================================
set role authenticated;
set request.jwt.claim.sub = :'D';
select delete_my_comment(:c1);
set request.jwt.claim.sub = :'F';
select t.ok('부모 지움: 부모는 안 보이고 답글은 보임 (화면이 "삭제된 댓글입니다"로)',
  not exists (select 1 from post_comments where id = :c1) and exists (select 1 from post_comments where id = :r1 and parent_id = :c1));
select t.fails('지운 댓글에 답글 불가', format($$select create_comment(%s, 'x', '{}', %s)$$, :p1, :c1), '답글을 달 댓글을 찾지 못했습니다');
set role anon;
set request.jwt.claim.sub = '';
select t.ok('비로그인도 답글을 읽음', exists (select 1 from post_comments where id = :r1));
set role authenticated;
set request.jwt.claim.sub = :'A';
select hide_comment(:cb, '숨김');
set request.jwt.claim.sub = :'D';
select t.fails('숨긴 댓글에 답글 불가', format($$select create_comment(%s, 'x', '{}', %s)$$, :p1, :cb), '답글을 달 댓글을 찾지 못했습니다');
set request.jwt.claim.sub = :'A';
select restore_comment(:cb, '다시');

-- ===================================================================
-- 3. 060: 058의 빌드 댓글은 없앴다 (표·칸·함수·종류), 답글 알림 종류는 그대로
-- ===================================================================
reset role;
select t.ok('060: 빌드 댓글 표·빌드 댓글 수 칸·신고 칸 없음',
  to_regclass('public.build_comments') is null
  and not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'builds' and column_name = 'comment_count')
  and not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'reports' and column_name = 'build_comment_id'));
select t.ok('060: 빌드 댓글 함수 없음, 신고 기각은 인자 4개',
  to_regprocedure('public.create_build_comment(bigint, text, bigint)') is null and to_regprocedure('public.build_open(bigint)') is null
  and to_regprocedure('public.dismiss_reports(bigint, bigint, text, bigint, bigint)') is null
  and to_regprocedure('public.dismiss_reports(bigint, bigint, text, bigint)') is not null);
select t.ok('060: 함수 본문에 빌드 댓글이 남지 않음',
  not exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace and (prosrc ilike '%build_comment%' or prosrc ilike '%build_open%')));
select t.fails('060: 빌드 댓글 알림 종류 없음', format($$insert into notifications (user_id, kind, message) values (%L, 'build_comment', 'x')$$, :'B'),
  'notifications_kind_check');
select t.fails('060: 숨김 기록 종류에 빌드 댓글 없음', format($$insert into hide_log (author_id, kind, target_id) values (%L, 'build_comment', 1)$$, :'B'),
  'hide_log_kind_check');
insert into notifications (user_id, kind, message) values (:'B', 'comment_reply', '답글 알림 종류는 그대로');
select t.ok('답글 알림 종류 comment_reply는 그대로', pg_temp.notes(:'B', 'comment_reply') >= 1);

-- ===================================================================
-- 4. 경험치 (답글도 댓글 +1) · 탑신병자
-- ===================================================================
select t.ok('답글도 댓글 경험치 (키 comment:)', exists (select 1 from xp_should_have(:'F') where source_key = 'comment:' || :r1 and kind = 'comment'));
select t.ok('탑신병자 기준에 댓글', has_visible_writing(:'F'));

-- ===================================================================
-- 5. 탈퇴: 남의 답글이 달린 내 댓글은 내용·작성자를 비운 껍데기, 나머지 내 댓글은 삭제
-- ===================================================================
set role authenticated;
set request.jwt.claim.sub = :'D';
select create_comment(:p2, 'D 혼자 글 댓글') as c3 \gset
set request.jwt.claim.sub = :'F';
select report_comment(:c3, 'spam');
reset role;
delete from auth.users where id = :'D';
select t.ok('탈퇴: 남의 답글 달린 글 댓글(지운 것)도 껍데기, 답글 유지',
  (select author_id is null and body = '' from post_comments where id = :c1) and exists (select 1 from post_comments where id = :r1));
select t.ok('탈퇴: 답글 없는 내 댓글·내 답글은 삭제 (그 신고도)',
  not exists (select 1 from post_comments where id in (:c3, :r3)) and not exists (select 1 from reports where comment_id = :c3));

-- ===================================================================
-- 6. 1년 정리: 남은 답글이 있는 부모는 남기고, 답글이 모두 정리되면 함께 (결과에 빌드 댓글 없음)
-- ===================================================================
update post_comments set deleted_at = now() - interval '400 days' where id = :c1;
select purge_deleted_writings() as purged \gset
select t.ok('1년 정리: 살아 있는 답글이 있는 부모 껍데기는 남김', exists (select 1 from post_comments where id = :c1));
update post_comments set deleted_at = now() - interval '400 days', delete_kind = 'author' where parent_id = :c1;
select purge_deleted_writings() as purged \gset
select t.ok('1년 정리: 답글도 모두 정리 대상이면 부모와 함께 지움 (결과 키는 글·댓글·문서 댓글)',
  not exists (select 1 from post_comments where id = :c1 or parent_id = :c1)
  and (:'purged'::jsonb ->> 'comments')::int >= 1 and not (:'purged'::jsonb ? 'build_comments'));

-- ===================================================================
-- 7. 권한
-- ===================================================================
select t.ok('내부 도우미는 아무도 못 부름',
  not has_function_privilege('authenticated', 'public.notify_new_comment(text, bigint, uuid, uuid, boolean)', 'execute')
  and not has_function_privilege('authenticated', 'public.check_comment_depth()', 'execute'));
select t.ok('화면 함수는 로그인한 사람만',
  has_function_privilege('authenticated', 'public.create_comment(bigint, text, text[], bigint)', 'execute')
  and not has_function_privilege('anon', 'public.create_comment(bigint, text, text[], bigint)', 'execute')
  and has_function_privilege('authenticated', 'public.dismiss_reports(bigint, bigint, text, bigint)', 'execute')
  and not has_function_privilege('anon', 'public.dismiss_reports(bigint, bigint, text, bigint)', 'execute'));
select t.ok('답글 알림은 휴대폰 알림 없음 (기존 댓글 알림과 같음)', push_group('comment_reply') is null and push_group('post_comment') is null);
