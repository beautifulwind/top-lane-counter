-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 040: 글·댓글 지움 표시(작성자·운영진), 지운 것은 아무도 못 읽음, 운영자 조회, 1년 정리
\set ON_ERROR_STOP 1
\set QUIET 1
\set A '00000000-0000-0000-0000-00000000000a'
\set M '00000000-0000-0000-0000-00000000000b'
\set D '00000000-0000-0000-0000-00000000000d'
\set F '00000000-0000-0000-0000-00000000000f'
insert into auth.users (id, email) values (:'A', 'op@x.com'), (:'M', 'm@x.com'), (:'D', 'd@x.com'), (:'F', 'f@x.com');
update public.profiles set nickname = '영자', role = 'admin' where id = :'A';
update public.profiles set nickname = '감독', role = 'moderator' where id = :'M';
update public.profiles set nickname = '디' where id = :'D';
update public.profiles set nickname = '에프' where id = :'F';
update public.xp_rules set value = 0 where key in ('post_interval', 'comment_interval');
create function pg_temp.xp(u uuid) returns integer language sql as $$ select xp from public.profiles where id = u $$;
create function pg_temp.notes(u uuid, k text) returns integer language sql as $$
  select count(*)::integer from public.notifications where user_id = u and kind = k $$;
grant execute on all functions in schema pg_temp to anon, authenticated;
\set quinn '(select id from public.counters where counter_champion = \'Quinn\')'

-- ===== 1. 작성자 삭제: 댓글 =====
set role authenticated;
set request.jwt.claim.sub = :'D';
select create_post('디의 글', '본문') as p1 \gset
set request.jwt.claim.sub = :'F';
select create_comment(:p1, '에프 댓글 1') as c1 \gset
select create_comment(:p1, '에프 댓글 2') as c2 \gset
select create_doc_comment(:quinn, '에프 문서 댓글') as dc1 \gset
reset role;
select t.ok('준비: 댓글 2 · 문서 댓글 1, 경험치 3', (select comment_count = 2 from posts where id = :p1) and pg_temp.xp(:'F') = 3);
insert into reports (reporter_id, comment_id, reason) values (:'D', :c1, 'spam');
set role authenticated;
set request.jwt.claim.sub = :'D';
select t.fails('남의 댓글은 못 지움', format('select delete_my_comment(%s)', :c1), '내 댓글만 지울 수 있습니다');
set request.jwt.claim.sub = :'F';
select delete_my_comment(:c1);
select t.ok('지운 댓글은 작성자에게도 안 보임', not exists (select 1 from post_comments where id = :c1));
select t.fails('다시 지우기', format('select delete_my_comment(%s)', :c1), '댓글을 찾지 못했습니다');
select t.fails('지운 댓글 고치기', format('select edit_comment(%s, %L)', :c1, 'x'), '댓글을 찾지 못했습니다');
select t.fails('지운 댓글 고치기 시작', format($$select begin_edit('comment', %s)$$, :c1), '숨기거나 삭제된');
reset role;
select t.ok('행은 남고 지움 표시(작성자)', (select deleted_at is not null and delete_kind = 'author' and deleted_by = :'F' and body = '에프 댓글 1' from post_comments where id = :c1));
select t.ok('댓글 수 1, 경험치 회수(댓글 삭제)', (select comment_count = 1 from posts where id = :p1) and pg_temp.xp(:'F') = 2
  and exists (select 1 from xp_events where user_id = :'F' and source_key = 'comment:' || :c1 and change = 'revoke' and reason = '댓글 삭제'));
select t.ok('열린 신고는 기각 (작성자가 댓글을 지움)', (select status = 'dismissed' and handled_note = '작성자가 댓글을 지움' from reports where comment_id = :c1));
set role authenticated;
set request.jwt.claim.sub = :'A';
select t.ok('운영자에게도 안 보임', not exists (select 1 from post_comments where id = :c1));
select t.fails('운영자: 지운 댓글 숨기기 불가', format('select hide_comment(%s, %L)', :c1, '메모'), '삭제된 댓글');

-- 문서 댓글
set request.jwt.claim.sub = :'F';
select delete_my_doc_comment(:dc1);
select t.ok('지운 문서 댓글 안 보임', not exists (select 1 from doc_comments where id = :dc1));
select t.fails('지운 문서 댓글 고치기', format('select edit_doc_comment(%s, %L)', :dc1, 'x'), '댓글을 찾지 못했습니다');
set request.jwt.claim.sub = :'A';
select t.ok('운영자에게도 안 보임', not exists (select 1 from doc_comments where id = :dc1));
reset role;
select t.ok('문서 댓글 경험치 회수', pg_temp.xp(:'F') = 1 and (select delete_kind = 'author' from doc_comments where id = :dc1));

-- ===== 2. 운영진 삭제 =====
set role authenticated;
set request.jwt.claim.sub = :'D';
select t.fails('일반 회원은 운영진 삭제 불가', format('select staff_delete_comment(%s, %L)', :c2, '이유'), '');
set request.jwt.claim.sub = :'M';
select t.fails('메모 필수', format('select staff_delete_comment(%s, %L)', :c2, '  '), '삭제 이유를 적어 주세요');
reset role;
insert into reports (reporter_id, comment_id, reason) values (:'D', :c2, 'abuse');
set role authenticated;
set request.jwt.claim.sub = :'M';
select staff_delete_comment(:c2, '욕설');
reset role;
select t.ok('감독관: 일반 회원 댓글 삭제 → 지움 표시(운영진)·메모',
  (select delete_kind = 'staff' and delete_note = '욕설' and deleted_by = :'M' from post_comments where id = :c2));
select t.ok('신고는 처리됨(메모)', (select status = 'resolved' and handled_note = '욕설' and handled_by = :'M' from reports where comment_id = :c2));
select t.ok('작성자 알림(comment_deleted, 글 링크) + 처리 기록 delete',
  (select count(*) = 1 from notifications where user_id = :'F' and kind = 'comment_deleted' and post_id = :p1 and message like '%메모: 욕설')
  and exists (select 1 from moderation_log where action = 'delete' and target_kind = 'comment' and target_id = :c2::text and note = '욕설'));
select t.ok('운영진 삭제 알림은 푸시 묶음이 없음', public.push_group('comment_deleted') is null and public.push_group('post_deleted') is null);
set role authenticated;
set request.jwt.claim.sub = :'A';
select create_post('운영자 글', '본문') as pa \gset
set request.jwt.claim.sub = :'M';
select t.fails('감독관은 운영진 글을 못 지움', format('select staff_delete_post(%s, %L)', :pa, '이유'), '감독관이 처리할 수 없습니다');
select t.fails('이미 지운 댓글', format('select staff_delete_comment(%s, %L)', :c2, '이유'), '댓글을 찾지 못했습니다');

-- 글 운영진 삭제: 운영자 모드를 끄면 거부
set request.jwt.claim.sub = :'A';
select set_operator_mode(false);
select t.fails('운영자 모드 끔 → 거부', format('select staff_delete_post(%s, %L)', :p1, '이유'), '');
select set_operator_mode(true);
select vote_post(:p1);
select staff_delete_post(:p1, '규칙 위반');
reset role;
select t.ok('글 운영진 삭제: 지움 표시·추천 0', (select delete_kind = 'staff' and delete_note = '규칙 위반' and up_count = 0 from posts where id = :p1)
  and not exists (select 1 from post_votes where post_id = :p1));
select t.ok('작성자 알림(post_deleted, 링크 없음)', (select count(*) = 1 from notifications where user_id = :'D' and kind = 'post_deleted' and post_id is null));
select t.ok('글 경험치 회수', pg_temp.xp(:'D') = 0);

-- 문서 댓글 운영진 삭제
set role authenticated;
set request.jwt.claim.sub = :'F';
select create_doc_comment(:quinn, '에프 문서 댓글 2') as dc2 \gset
set request.jwt.claim.sub = :'M';
select staff_delete_doc_comment(:dc2, '도배');
reset role;
select t.ok('문서 댓글 운영진 삭제 + 알림(카운터 링크)', (select delete_kind = 'staff' from doc_comments where id = :dc2)
  and (select count(*) = 1 from notifications where user_id = :'F' and kind = 'doc_comment_deleted' and counter_id is not null));

-- ===== 3. 지운 글의 남은 댓글 =====
set role authenticated;
set request.jwt.claim.sub = :'D';
select create_post('디의 둘째 글', '본문') as p2 \gset
set request.jwt.claim.sub = :'F';
select create_comment(:p2, '남는 댓글') as c3 \gset
select xp from profiles where id = :'F' \gset f_
set request.jwt.claim.sub = :'D';
select delete_my_post(:p2);
set request.jwt.claim.sub = :'F';
select t.ok('지운 글의 남의 댓글: 쓴 사람에게도 안 보임', not exists (select 1 from post_comments where id = :c3));
select t.fails('지운 글의 댓글은 신고 불가', format('select report_comment(%s, %L)', :c3, 'spam'), '신고할 수 없는 댓글');
reset role;
select t.ok('그 댓글 경험치는 그대로', pg_temp.xp(:'F') = :f_xp and (select deleted_at is null from post_comments where id = :c3));

-- ===== 4. 운영자 조회 =====
set role authenticated;
set request.jwt.claim.sub = :'M';
select t.fails('감독관은 못 봄', format('select admin_deleted_writings(%L)', :'F'), '운영자만');
set request.jwt.claim.sub = :'A';
select admin_deleted_writings(:'F') as dw \gset
select admin_deleted_writings(:'D') as dw_d \gset
reset role;
select t.ok('에프: 지운 댓글 2(작성자·운영진)·문서 댓글 2, 내용·사유·지운 사람',
  jsonb_array_length(:'dw'::jsonb -> 'comments') = 2 and jsonb_array_length(:'dw'::jsonb -> 'doc_comments') = 2
  and jsonb_array_length(:'dw'::jsonb -> 'posts') = 0
  and (:'dw'::jsonb -> 'comments' -> 0 ->> 'delete_kind') = 'staff'  -- 최근에 지운 것부터
  and (:'dw'::jsonb -> 'comments' -> 0 ->> 'delete_note') = '욕설'
  and (:'dw'::jsonb -> 'comments' -> 0 -> 'deleted_by' ->> 'nickname') = '감독'
  and (:'dw'::jsonb -> 'comments' -> 1 ->> 'body') = '에프 댓글 1'
  and (:'dw'::jsonb ->> 'keep_days')::int = 365);
select t.ok('디: 지운 글 2 (내용 보관, 남은 댓글 수)',
  jsonb_array_length(:'dw_d'::jsonb -> 'posts') = 2
  and (:'dw_d'::jsonb -> 'posts' -> 0 ->> 'title') = '디의 둘째 글'
  and (:'dw_d'::jsonb -> 'posts' -> 0 ->> 'comment_count')::int = 1);
set role authenticated;
set request.jwt.claim.sub = :'A';
select t.ok('회원 정보: 활동 수에서 지운 것 빼고, 지운 개수 따로',
  (select (x ->> 'deleted_comments')::int = 4 and (x ->> 'comments')::int = 1 from (select admin_member_info(:'F') x) s)
  and (select (x ->> 'deleted_posts')::int = 2 and (x ->> 'posts')::int = 0 from (select admin_member_info(:'D') x) s));
reset role;

-- ===== 5. 1년 정리 =====
set role authenticated;
select t.fails('사람은 정리 함수를 못 부름', 'select purge_deleted_writings()', 'permission denied');
reset role;
update posts set deleted_at = now() - interval '366 days' where id = :p2;
update post_comments set deleted_at = now() - interval '366 days' where id = :c1;
update doc_comments set deleted_at = now() - interval '366 days' where id = :dc1;
delete from notifications where user_id = :'F';
select purge_deleted_writings() as purged \gset
select t.ok('정리: 1년 지난 글 1(그 아래 남의 댓글도)·댓글 1·문서 댓글 1',
  :'purged'::jsonb = '{"posts": 1, "comments": 1, "doc_comments": 1}'::jsonb
  and not exists (select 1 from posts where id = :p2) and not exists (select 1 from post_comments where id in (:c1, :c3))
  and not exists (select 1 from doc_comments where id = :dc1));
select t.ok('1년 안 된 것은 그대로', exists (select 1 from posts where id = :p1) and exists (select 1 from post_comments where id = :c2));
select t.ok('따라 지워진 댓글 경험치는 회수하되 알림 없음', pg_temp.xp(:'F') = :f_xp - 1
  and not exists (select 1 from notifications where user_id = :'F'));

-- ===== 6. 탈퇴: 지운 글도 내용을 비움 =====
set role authenticated;
set request.jwt.claim.sub = :'D';
select create_post('탈퇴 전 지운 글', '비밀 본문') as p3 \gset
set request.jwt.claim.sub = :'F';
select create_comment(:p3, '에프') ;
set request.jwt.claim.sub = :'D';
select delete_my_post(:p3);
reset role;
delete from auth.users where id = :'D';
select t.ok('탈퇴: 남의 댓글 달린 지운 글은 내용을 비우고 남음 (1년 뒤 정리)',
  (select author_id is null and title = '' and body = '' and deleted_at is not null from posts where id = :p3));
