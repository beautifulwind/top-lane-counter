-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 021: 신고 사유 'hate' · 숨김 기록(hide_log) · 운영자 hide_counts
\set ON_ERROR_STOP 1
\set QUIET 1
\set A '00000000-0000-0000-0000-00000000000a'
\set B '00000000-0000-0000-0000-00000000000b'
\set C '00000000-0000-0000-0000-00000000000c'
insert into auth.users (id, email) values (:'A', 'op@x.com'), (:'B', 'b@x.com'), (:'C', 'c@x.com');
update public.profiles set nickname = '영자', role = 'admin' where id = :'A';
update public.profiles set nickname = '쓴이' where id = :'B';
update public.profiles set nickname = '본이' where id = :'C';
update public.xp_rules set value = 0 where key in ('post_interval', 'comment_interval');
create temp table ids (k text primary key, v bigint);
grant all on ids to authenticated;
insert into ids select 'quinn', id from counters where counter_champion = 'Quinn';

set role authenticated;
set request.jwt.claim.sub = :'B';
select public.create_post('글1', '본문');
insert into ids select 'p1', max(id) from posts;
select public.create_post('글2', '본문');
insert into ids select 'p2', max(id) from posts;
select public.create_comment((select v from ids where k = 'p1'), '댓글');
insert into ids select 'c1', max(id) from post_comments;
select public.create_doc_comment((select v from ids where k = 'quinn'), '문서 댓글');
insert into ids select 'd1', max(id) from doc_comments;

-- ===== 1. 신고 사유 hate =====
set request.jwt.claim.sub = :'C';
select public.report_post((select v from ids where k = 'p1'), 'hate');
select public.report_comment((select v from ids where k = 'c1'), 'hate', '고인 비하');
select public.report_doc_comment((select v from ids where k = 'd1'), 'hate');
reset role;
select t.ok('글·댓글·문서 댓글 모두 hate 신고', (select count(*) = 3 from reports where reason = 'hate'));
set role authenticated;
set request.jwt.claim.sub = :'C';
select t.fails('모르는 사유는 막힘', format($$select public.report_post(%s, 'racism')$$, (select v from ids where k = 'p2')), '신고 이유를 골라 주세요');
select public.report_post((select v from ids where k = 'p2'), 'privacy');
set request.jwt.claim.sub = :'A';
select public.report_post((select v from ids where k = 'p2'), 'abuse');
reset role;
select t.ok('기존 사유 abuse·privacy도 그대로', (select count(*) = 2 from reports where post_id = (select v from ids where k = 'p2')));
select t.fails('표에 직접 넣어도 사유 검사', format($$insert into reports (reporter_id, post_id, reason) values ('%s', 1, 'racism')$$, :'C'), 'reports_reason_check');
set role authenticated;

-- ===== 2. 숨김 기록 =====
set request.jwt.claim.sub = :'C';
select t.fails('운영자가 아니면 hide_counts 불가', format($$select public.hide_counts(array['%s']::uuid[])$$, :'B'), '운영자만');
select t.fails('숨김 기록은 아무도 직접 못 읽음', 'select * from hide_log', 'permission denied');

set request.jwt.claim.sub = :'A';
select t.ok('처음엔 0회', (select (public.hide_counts(array[:'B', :'C']::uuid[]) -> 'counts' ->> :'B')::int = 0));
select t.ok('기간은 xp_rules (90일)', (select (public.hide_counts(array[:'B']::uuid[]) ->> 'days')::int = 90));
select public.hide_post((select v from ids where k = 'p1'), '혐오 표현');
select public.hide_comment((select v from ids where k = 'c1'), '고인 비하');
select public.hide_doc_comment((select v from ids where k = 'd1'), '혐오');
select t.ok('글·댓글·문서 댓글 숨김 = 3회', (select (public.hide_counts(array[:'B']::uuid[]) -> 'counts' ->> :'B')::int = 3));
select t.ok('숨겨지지 않은 사람은 0회', (select (public.hide_counts(array[:'C']::uuid[]) -> 'counts' ->> :'C')::int = 0));

select public.restore_comment((select v from ids where k = 'c1'), '잘못 숨김');
select t.ok('다시 공개하면 빠짐 (2회)', (select (public.hide_counts(array[:'B']::uuid[]) -> 'counts' ->> :'B')::int = 2));
select public.hide_comment((select v from ids where k = 'c1'), '다시 숨김');
select t.ok('또 숨기면 다시 셈 (3회)', (select (public.hide_counts(array[:'B']::uuid[]) -> 'counts' ->> :'B')::int = 3));

-- 작성자가 숨겨진 글을 지워도 기록은 남는다
set request.jwt.claim.sub = :'B';
select public.delete_my_post((select v from ids where k = 'p1'));
set request.jwt.claim.sub = :'A';
select t.ok('숨겨진 글을 지워도 횟수 그대로', (select (public.hide_counts(array[:'B']::uuid[]) -> 'counts' ->> :'B')::int = 3));

-- 기간이 지나면 빠짐
reset role;
update hide_log set hidden_at = now() - interval '91 days' where kind = 'post';
set role authenticated;
set request.jwt.claim.sub = :'A';
select t.ok('90일이 지난 숨김은 안 셈 (2회)', (select (public.hide_counts(array[:'B']::uuid[]) -> 'counts' ->> :'B')::int = 2));

-- 탈퇴하면 기록도 지워짐
reset role;
delete from auth.users where id = :'B';
select t.ok('탈퇴하면 숨김 기록도 삭제', not exists (select 1 from hide_log where author_id = :'B'));
