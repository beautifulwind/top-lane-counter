-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 015: 자유게시판 — 쓰기 권한, 도배 간격, 고치기(수정됨), 지우기(삭제된 글로 남기기), 추천, 신고, 숨기기·다시 공개,
--      알림(댓글 합치기), 경험치(하루 상한·회수), 탑신병자, 목록·검색, 탈퇴
\set ON_ERROR_STOP 1
\set QUIET 1
\set A '00000000-0000-0000-0000-00000000000a'
\set B '00000000-0000-0000-0000-00000000000b'
\set D '00000000-0000-0000-0000-00000000000d'
\set E '00000000-0000-0000-0000-00000000000e'
\set F '00000000-0000-0000-0000-00000000000f'
insert into auth.users (id, email) values (:'A', 'op@x.com'), (:'B', 'b@x.com'), (:'D', 'd@x.com'), (:'E', 'e@x.com'), (:'F', 'f@x.com');
update public.profiles set nickname = '영자', role = 'admin' where id = :'A';
update public.profiles set nickname = '비' where id = :'B';
update public.profiles set nickname = '디' where id = :'D';
update public.profiles set nickname = '에프' where id = :'F';
-- E는 닉네임 없음
-- 간격 검사는 따로 하고, 나머지는 간격 0으로
update public.xp_rules set value = 0 where key in ('post_interval', 'comment_interval');
create temp table ids (k text primary key, v bigint);
grant all on ids to authenticated;

create function pg_temp.xp(u uuid) returns integer language sql as $$ select xp from public.profiles where id = u $$;
create function pg_temp.titles(u uuid) returns text[] language sql as $$
  select coalesce(array_agg(title_key order by title_key), '{}') from public.user_titles where user_id = u $$;
create function pg_temp.notes(u uuid, k text) returns integer language sql as $$
  select count(*)::integer from public.notifications where user_id = u and kind = k $$;
create function pg_temp.id(key text) returns bigint language sql as $$ select v from ids where k = key $$;
grant execute on all functions in schema pg_temp to anon, authenticated;

-- ===================================================================
-- 1. 쓰기 권한
-- ===================================================================
set request.jwt.claim.sub = '';
set role anon;
select t.ok('비로그인: 목록은 볼 수 있다', (public.board_page() ->> 'total')::int = 0);
select t.fails('비로그인: 글쓰기 함수 없음', $$ select public.create_post('제목', '본문') $$, 'permission denied');
reset role;

set role authenticated;
set request.jwt.claim.sub = :'E';
select t.fails('닉네임 없으면 못 씀', $$ select public.create_post('제목', '본문') $$, '닉네임을 정해야');
set request.jwt.claim.sub = :'B';
select t.fails('직접 insert 막힘', $$ insert into public.posts (author_id, title, body) values (auth.uid(), 'a', 'b') $$, 'permission denied');
select t.fails('빈 제목', $$ select public.create_post('   ', '본문') $$, '제목을 적어 주세요');
select t.fails('제목 101자', $$ select public.create_post(repeat('가', 101), '본문') $$, '제목은 100자 이하');
select t.fails('본문 10001자', $$ select public.create_post('제목', repeat('가', 10001)) $$, '본문은 10000자 이하');
select public.create_post('  첫 글  ', E'안녕하세요\n반가워요') as p1 \gset
insert into ids values ('p1', :p1);
select t.ok('글쓰기 → 앞뒤 공백 정리, 보이는 상태',
  (select title = '첫 글' and status = 'visible' and edited_at is null and author_id = auth.uid() from posts where id = :p1));
select t.fails('직접 update 막힘', $$ update public.posts set title = 'x' $$, 'permission denied');
select t.fails('직접 delete 막힘', $$ delete from public.posts $$, 'permission denied');
reset role;

select t.ok('경험치 +5, 탑신병자 (첫 글)', pg_temp.xp(:'B') = 5 and pg_temp.titles(:'B') = array['top_addict']);
select t.ok('내역: 게시판 글 지급 줄',
  (select count(*) = 1 from xp_events where user_id = :'B' and source_key = 'post:' || :p1 and type = 'post' and amount = 5 and change = 'grant'));

-- ===================================================================
-- 2. 고치기 (수정됨), 남의 글은 못 고침
-- ===================================================================
set role authenticated;
set request.jwt.claim.sub = :'B';
select public.edit_post(:p1, '첫 글', E'안녕하세요\n반가워요');
select t.ok('바뀐 게 없으면 수정됨 안 붙음', (select edited_at is null from posts where id = :p1));
select public.edit_post(:p1, '첫 글 (고침)', '본문 고침');
select t.ok('고치면 수정됨', (select edited_at is not null and title = '첫 글 (고침)' from posts where id = :p1));
set request.jwt.claim.sub = :'D';
select t.fails('남의 글 고치기', format('select public.edit_post(%s, %L, %L)', :p1, 'x', 'y'), '내 글만 고칠 수 있습니다');
select t.fails('남의 글 지우기', format('select public.delete_my_post(%s)', :p1), '내 글만 지울 수 있습니다');
reset role;
select t.ok('고쳐도 경험치 그대로', pg_temp.xp(:'B') = 5);

-- ===================================================================
-- 3. 댓글 + 알림 (내 글에 내 댓글은 알림 없음, 안 읽은 알림은 합친다)
-- ===================================================================
set role authenticated;
set request.jwt.claim.sub = :'B';
select public.create_comment(:p1, '내 글에 내 댓글') as c_self \gset
set request.jwt.claim.sub = :'D';
select t.fails('빈 댓글', format('select public.create_comment(%s, %L)', :p1, ' '), '댓글을 적어 주세요');
select t.fails('댓글 1001자', format('select public.create_comment(%s, repeat(%L, 1001))', :p1, '가'), '댓글은 1000자 이하');
select public.create_comment(:p1, '디의 댓글') as c1 \gset
insert into ids values ('c1', :c1);
reset role;
select t.ok('내 댓글은 알림 없음, 남의 댓글은 알림 1개',
  pg_temp.notes(:'B', 'post_comment') = 1
  and (select message = '내 글 「첫 글 (고침)」에 새 댓글이 달렸습니다.' and post_id = :p1 from notifications where user_id = :'B' and kind = 'post_comment'));
set role authenticated;
set request.jwt.claim.sub = :'F';
select public.create_comment(:p1, '에프의 댓글') as c2 \gset
insert into ids values ('c2', :c2);
reset role;
select t.ok('안 읽은 알림은 합친다: 새 댓글 2개',
  pg_temp.notes(:'B', 'post_comment') = 1
  and (select message = '내 글 「첫 글 (고침)」에 새 댓글 2개가 달렸습니다.' from notifications where user_id = :'B' and kind = 'post_comment'));
update notifications set read_at = now() where user_id = :'B';
set role authenticated;
set request.jwt.claim.sub = :'D';
select public.create_comment(:p1, '디의 두 번째') as c3 \gset
reset role;
select t.ok('읽은 뒤에는 새 알림', pg_temp.notes(:'B', 'post_comment') = 2);
select t.ok('댓글 수 = 보이는 댓글 4', (select comment_count = 4 from posts where id = :p1));
select t.ok('댓글 경험치 +1, 탑신병자 (첫 댓글)', pg_temp.xp(:'D') = 2 and pg_temp.titles(:'D') = array['top_addict']
  and pg_temp.xp(:'F') = 1 and pg_temp.titles(:'F') = array['top_addict']);

set role authenticated;
set request.jwt.claim.sub = :'D';
select public.edit_comment(:c3, '디의 두 번째 (고침)');
select t.ok('댓글 고치면 수정됨', (select edited_at is not null from post_comments where id = :c3));
set request.jwt.claim.sub = :'F';
select t.fails('남의 댓글 고치기', format('select public.edit_comment(%s, %L)', :c3, 'x'), '내 댓글만 고칠 수 있습니다');
select t.fails('남의 댓글 지우기', format('select public.delete_my_comment(%s)', :c3), '내 댓글만 지울 수 있습니다');
set request.jwt.claim.sub = :'D';
select public.delete_my_comment(:c3);
reset role;
select t.ok('댓글 지우면 경험치 회수 (이유: 댓글 삭제), 댓글 수 3',
  pg_temp.xp(:'D') = 1 and (select comment_count = 3 from posts where id = :p1)
  and (select count(*) = 1 from xp_events where user_id = :'D' and source_key = 'comment:' || :c3 and change = 'revoke' and reason = '댓글 삭제'));

-- ===================================================================
-- 4. 추천 (한 번, 다시 누르면 취소, 내 글은 안 됨)
-- ===================================================================
set role authenticated;
set request.jwt.claim.sub = :'B';
select t.fails('내 글 추천', format('select public.vote_post(%s)', :p1), '내 글은 추천할 수 없습니다');
set request.jwt.claim.sub = :'D';
select t.ok('추천', public.vote_post(:p1) = '{"up": 1, "mine": true}'::jsonb);
select t.ok('내 추천만 보인다', (select count(*) = 1 from post_votes));
set request.jwt.claim.sub = :'F';
select t.ok('두 번째 사람 추천', public.vote_post(:p1) = '{"up": 2, "mine": true}'::jsonb);
select t.ok('다시 누르면 취소', public.vote_post(:p1) = '{"up": 1, "mine": false}'::jsonb);
select t.fails('직접 추천 insert 막힘', format('insert into public.post_votes (post_id, user_id) values (%s, auth.uid())', :p1), 'permission denied');
reset role;
select t.ok('추천은 경험치 없음 (글 5 + 댓글 1)', pg_temp.xp(:'B') = 6);

-- ===================================================================
-- 5. 신고 → 운영자 숨기기 → 다시 공개
-- ===================================================================
set role authenticated;
set request.jwt.claim.sub = :'B';
select t.fails('내 글 신고', format('select public.report_post(%s, %L)', :p1, 'spam'), '내 글은 신고할 수 없습니다');
set request.jwt.claim.sub = :'D';
select t.fails('이유 없음', format('select public.report_post(%s, %L)', :p1, 'x'), '신고 이유를 골라');
select t.fails('기타는 내용 필수', format('select public.report_post(%s, %L, %L)', :p1, 'other', ' '), '기타 이유를 적어');
select public.report_post(:p1, 'spam');
select t.fails('같은 사람 같은 글 두 번', format('select public.report_post(%s, %L)', :p1, 'abuse'), '이미 신고한 글입니다');
select t.ok('신고는 일반 유저에게 안 보임', (select count(*) = 0 from reports));
set request.jwt.claim.sub = :'F';
select public.report_post(:p1, 'other', '홍보 링크');
select public.report_comment(:c1, 'abuse');
select t.fails('같은 댓글 두 번', format('select public.report_comment(%s, %L)', :c1, 'spam'), '이미 신고한 댓글입니다');
select t.fails('일반 유저는 숨기기 못 함', format('select public.hide_post(%s, %L)', :p1, '메모'), '운영자만');
set request.jwt.claim.sub = :'A';
select t.ok('운영자는 신고를 본다', (select count(*) = 3 from reports where status = 'open'));
select t.fails('숨기기 메모 필수', format('select public.hide_post(%s, %L)', :p1, ' '), '숨기는 이유를 적어');
select public.hide_post(:p1, '광고 글');
reset role;
select t.ok('숨기면 글 신고는 처리됨, 댓글 신고는 그대로',
  (select count(*) = 2 from reports where post_id = :p1 and status = 'resolved' and handled_note = '광고 글')
  and (select count(*) = 1 from reports where comment_id = :c1 and status = 'open'));
select t.ok('글쓴이에게 알림 (메모 포함)',
  (select message = '내 글 「첫 글 (고침)」을 운영진이 숨겼습니다. 메모: 광고 글' and post_id = :p1 from notifications where user_id = :'B' and kind = 'post_hidden'));
select t.ok('글 숨김 → 글 경험치 회수, 댓글 쓴 사람은 그대로',
  pg_temp.xp(:'B') = 1 and pg_temp.xp(:'D') = 1 and pg_temp.xp(:'F') = 1
  and (select reason = '글 숨김' from xp_events where user_id = :'B' and source_key = 'post:' || :p1 and change = 'revoke'));
select t.ok('탑신병자는 내 댓글이 남아 있어 유지', pg_temp.titles(:'B') = array['top_addict']);

set request.jwt.claim.sub = '';
set role anon;
select t.ok('비로그인: 숨긴 글·그 댓글 안 보임, 목록에도 없음',
  (select count(*) = 0 from posts) and (select count(*) = 0 from post_comments) and (public.board_page() ->> 'total')::int = 0);
reset role;
set role authenticated;
set request.jwt.claim.sub = :'B';
select t.ok('글쓴이도 숨긴 글은 안 보임', (select count(*) = 0 from posts));
select t.fails('숨긴 글 고치기', format('select public.edit_post(%s, %L, %L)', :p1, 'x', 'y'), '운영진이 숨긴 글은 고칠 수 없습니다');
set request.jwt.claim.sub = :'D';
select t.fails('숨긴 글에 댓글', format('select public.create_comment(%s, %L)', :p1, 'x'), '글을 찾지 못했습니다');
select t.fails('숨긴 글 추천', format('select public.vote_post(%s)', :p1), '추천할 수 없는 글');
set request.jwt.claim.sub = :'A';
select t.ok('운영자는 숨긴 글·댓글을 본다', (select count(*) = 1 from posts) and (select count(*) = 3 from post_comments)
  and (select hidden_note = '광고 글' from posts where id = :p1));
select t.fails('이미 숨긴 글', format('select public.hide_post(%s, %L)', :p1, '또'), '이미 숨긴 글');
select t.fails('다시 공개 메모 필수', format('select public.restore_post(%s, %L)', :p1, ''), '다시 공개 메모를 적어');
select public.restore_post(:p1, '오해였어요');
reset role;
select t.ok('다시 공개: 메모 비움, 경험치 다시 (같은 키 한 번분), 알림',
  (select status = 'visible' and hidden_note is null and hidden_at is null from posts where id = :p1)
  and pg_temp.xp(:'B') = 6
  and (select sum(amount) = 5 from xp_events where user_id = :'B' and source_key = 'post:' || :p1)
  and pg_temp.notes(:'B', 'post_restored') = 1);

-- 댓글 숨기기·다시 공개, 신고 기각
set role authenticated;
set request.jwt.claim.sub = :'A';
select public.hide_comment(:c1, '욕설');
reset role;
select t.ok('댓글 숨김: 경험치 회수, 댓글 수 2, 신고 처리됨, 알림',
  pg_temp.xp(:'D') = 0 and (select comment_count = 2 from posts where id = :p1)
  and (select status = 'resolved' from reports where comment_id = :c1)
  and (select message = '「첫 글 (고침)」에 쓴 내 댓글을 운영진이 숨겼습니다. 메모: 욕설' from notifications where user_id = :'D' and kind = 'comment_hidden'));
select t.ok('탑신병자 회수 (보이는 글·댓글·기여 없음)', pg_temp.titles(:'D') = '{}' and pg_temp.notes(:'D', 'title_revoked') = 1);
set request.jwt.claim.sub = '';
set role anon;
select t.ok('숨긴 댓글은 안 보임', (select count(*) = 2 from post_comments));
reset role;
set role authenticated;
set request.jwt.claim.sub = :'D';
select t.fails('숨긴 댓글 고치기', format('select public.edit_comment(%s, %L)', :c1, 'x'), '운영진이 숨긴 댓글');
set request.jwt.claim.sub = :'A';
select public.restore_comment(:c1, '다시 봤습니다');
reset role;
select t.ok('댓글 다시 공개: 경험치·칭호 돌아옴', pg_temp.xp(:'D') = 1 and pg_temp.titles(:'D') = array['top_addict']
  and pg_temp.notes(:'D', 'comment_restored') = 1);

set role authenticated;
set request.jwt.claim.sub = :'D';
select public.report_comment(:c2, 'abuse');
set request.jwt.claim.sub = :'B';
select public.report_comment(:c2, 'spam');
set request.jwt.claim.sub = :'A';
select t.fails('기각: 대상 하나', $$ select public.dismiss_reports(null, null) $$, '하나를 골라');
select t.ok('신고 기각 (2건)', public.dismiss_reports(null, :c2, '문제없음') = 2);
select t.fails('처리할 신고 없음', format('select public.dismiss_reports(null, %s)', :c2), '처리할 신고가 없습니다');
reset role;
select t.ok('기각해도 댓글·경험치 그대로', pg_temp.xp(:'F') = 1 and (select status = 'visible' from post_comments where id = :c2));
set role authenticated;
set request.jwt.claim.sub = :'D';
select t.fails('기각된 뒤에도 같은 사람은 다시 신고 못 함', format('select public.report_comment(%s, %L)', :c2, 'spam'), '이미 신고한 댓글');
reset role;

-- ===================================================================
-- 6. 글 지우기 (040): 지움 표시만 — 누구에게도 안 보이고, 달린 남의 댓글도 함께 안 보임 (경험치는 유지)
-- ===================================================================
set role authenticated;
set request.jwt.claim.sub = :'D';
select public.vote_post(:p1);  -- 취소 (위에서 누른 것)
select public.vote_post(:p1);
reset role;
insert into reports (reporter_id, post_id, reason) values (:'A', :p1, 'abuse');  -- 열린 신고 하나
set role authenticated;
set request.jwt.claim.sub = :'B';
select t.ok('지우기 → hard (옛 화면 호환 값)', public.delete_my_post(:p1) = 'hard');
reset role;
select t.ok('지운 글: 내용은 보관, 지움 표시(작성자), 추천 0, 댓글 행은 그대로',
  (select title <> '' and deleted_at is not null and delete_kind = 'author' and deleted_by = :'B' and up_count = 0 from posts where id = :p1)
  and (select count(*) = 3 from post_comments where post_id = :p1 and deleted_at is null));
set role authenticated;
set request.jwt.claim.sub = :'B';
select t.ok('작성자에게도 글·댓글이 안 보임',
  not exists (select 1 from posts where id = :p1) and not exists (select 1 from post_comments where post_id = :p1));
select t.fails('삭제된 글 다시 지우기', format('select public.delete_my_post(%s)', :p1), '이미 삭제된 글');
select t.fails('삭제된 글 고치기', format('select public.edit_post(%s, %L, %L)', :p1, 'x', 'y'), '삭제된 글입니다');
set request.jwt.claim.sub = :'D';
select t.fails('삭제된 글에 댓글', format('select public.create_comment(%s, %L)', :p1, 'x'), '삭제된 글에는 댓글을');
select t.fails('삭제된 글 추천', format('select public.vote_post(%s)', :p1), '추천할 수 없는 글');
select t.fails('삭제된 글 신고', format('select public.report_post(%s, %L)', :p1, 'spam'), '신고할 수 없는 글');
select t.fails('삭제된 글의 댓글 고치기', format('select public.edit_comment(%s, %L)', :c1, 'x'), '댓글을 찾지 못했습니다');
select t.fails('삭제된 글의 댓글 신고', format('select public.report_comment(%s, %L)', :c2, 'spam'), '신고할 수 없는 댓글');
set request.jwt.claim.sub = :'A';
select t.ok('운영자에게도 안 보임', not exists (select 1 from posts where id = :p1) and not exists (select 1 from post_comments where post_id = :p1));
reset role;
select t.ok('열린 신고는 기각 (작성자가 글을 지움)',
  (select count(*) = 0 from reports where post_id = :p1 and status = 'open')
  and (select count(*) = 1 from reports where post_id = :p1 and handled_note = '작성자가 글을 지움'));
select t.ok('글 경험치 회수 (글 삭제), 남의 댓글 경험치는 그대로',
  pg_temp.xp(:'B') = 1 and pg_temp.xp(:'D') = 1 and pg_temp.xp(:'F') = 1
  and (select reason = '글 삭제' from xp_events where user_id = :'B' and source_key = 'post:' || :p1 order by id desc limit 1));
select t.ok('목록·개수에 없음', (public.board_page() ->> 'total')::int = 0 and jsonb_array_length(public.board_page() -> 'rows') = 0);

set role authenticated;
set request.jwt.claim.sub = :'B';
select public.create_post('혼자 쓴 글', '본문') as p2 \gset
select public.create_comment(:p2, '내 댓글') as c_p2 \gset
select t.ok('지우기 → hard', public.delete_my_post(:p2) = 'hard');
reset role;
select t.ok('지운 글·댓글 행은 보관 (1년 뒤 정리)', (select count(*) = 1 from posts where id = :p2) and (select count(*) = 1 from post_comments where post_id = :p2));

-- ===================================================================
-- 7. 하루 상한 (글 5개 = 25, 댓글 10개 = 10) — 숨기면 다음 것이 들어온다
-- ===================================================================
set role authenticated;
set request.jwt.claim.sub = :'D';
select public.create_post('상한 ' || n, '본문') from generate_series(1, 6) n;
reset role;
select t.ok('글 6개 → 오늘은 25만', (select coalesce(sum(amount), 0) = 25 from xp_events where user_id = :'D' and type = 'post'));
insert into ids select 'cap1', id from posts where title = '상한 1';
insert into ids select 'cap6', id from posts where title = '상한 6';
set role authenticated;
set request.jwt.claim.sub = :'A';
select public.hide_post(pg_temp.id('cap1'), '테스트');
reset role;
select t.ok('하나 숨기면 6번째가 들어와 그대로 25',
  (select coalesce(sum(amount), 0) = 25 from xp_events where user_id = :'D' and type = 'post')
  and (select sum(amount) = 5 from xp_events where user_id = :'D' and source_key = 'post:' || pg_temp.id('cap6')));

set role authenticated;
set request.jwt.claim.sub = :'F';
select public.create_comment(pg_temp.id('cap6'), '댓글 ' || n) from generate_series(1, 12) n;
reset role;
select t.ok('댓글 12개 → 오늘은 10만', (select coalesce(sum(amount), 0) = 10 from xp_events where user_id = :'F' and type = 'comment'));
select t.ok('댓글 알림은 하나로 합쳐짐 (12개)',
  (select count(*) = 1 from notifications where user_id = :'D' and kind = 'post_comment' and read_at is null)
  and (select message like '%새 댓글 12개%' from notifications where user_id = :'D' and kind = 'post_comment' and read_at is null));

-- ===================================================================
-- 8. 도배 간격 (글 30초, 댓글 5초)
-- ===================================================================
update public.xp_rules set value = 30 where key = 'post_interval';
update public.xp_rules set value = 5 where key = 'comment_interval';
update public.board_last_write set post_at = now() - interval '10 seconds', comment_at = now() - interval '2 seconds' where user_id = :'F';
set role authenticated;
set request.jwt.claim.sub = :'F';
select t.fails('글 30초 안에 다시', $$ select public.create_post('도배', '도배') $$, '글은 30초에 한 번 쓸 수 있습니다. 20초 뒤에');
select t.fails('댓글 5초 안에 다시', format('select public.create_comment(%s, %L)', pg_temp.id('cap6'), 'x'), '댓글은 5초에 한 번 쓸 수 있습니다. 3초 뒤에');
reset role;
update public.board_last_write set post_at = now() - interval '31 seconds', comment_at = now() - interval '6 seconds' where user_id = :'F';
set role authenticated;
set request.jwt.claim.sub = :'F';
select public.create_post('간격 지남', '본문') as p_ok \gset
select t.ok('간격이 지나면 된다', :p_ok > 0);
select t.fails('바로 또 쓰면 막힘', $$ select public.create_post('또', '또') $$, '30초에 한 번');
reset role;
-- 글을 지워도 간격은 남는다
set role authenticated;
set request.jwt.claim.sub = :'F';
select public.delete_my_post(:p_ok);
select t.fails('지우고 바로 다시 써도 막힘', $$ select public.create_post('또', '또') $$, '30초에 한 번');
reset role;
update public.xp_rules set value = 0 where key in ('post_interval', 'comment_interval');

-- ===================================================================
-- 9. 목록·검색 (20개씩, 최신순, 제목·본문, % _ 는 글자 그대로)
-- ===================================================================
set role authenticated;
set request.jwt.claim.sub = :'B';
select public.create_post('목록 ' || n, case when n = 3 then '퀸 공략 100%' else '본문' end) from generate_series(1, 22) n;
reset role;
set request.jwt.claim.sub = '';
set role anon;
select t.ok('1쪽: 20개, 최신순', jsonb_array_length(public.board_page(null, 1) -> 'rows') = 20
  and public.board_page(null, 1) -> 'rows' -> 0 ->> 'title' = '목록 22');
select t.ok('전체 수 (숨긴 글 제외)', (public.board_page() ->> 'total')::int = 5 + 22);
select t.ok('2쪽', jsonb_array_length(public.board_page(null, 2) -> 'rows') = 7);
select t.ok('본문 검색', (public.board_page('퀸 공략') ->> 'total')::int = 1);
select t.ok('제목 검색', (public.board_page('목록 2') ->> 'total')::int = 4);  -- 2, 20, 21, 22
select t.ok('% 는 글자 그대로', (public.board_page('100%') ->> 'total')::int = 1 and (public.board_page('%') ->> 'total')::int = 1);
select t.ok('_ 는 글자 그대로', (public.board_page('_') ->> 'total')::int = 0);
select t.ok('작성자 정보', public.board_page(null, 1) -> 'rows' -> 0 -> 'author' ->> 'nickname' = '비');
reset role;

-- ===================================================================
-- 10. 탈퇴: 남의 댓글이 달린 글은 삭제된 글로, 나머지는 지움
-- ===================================================================
set role authenticated;
set request.jwt.claim.sub = :'B';
select public.create_post('탈퇴 전 글', '본문') as p_quit \gset
set request.jwt.claim.sub = :'F';
select public.create_comment(:p_quit, '남는 댓글');
reset role;
delete from auth.users where id = :'B';
select t.ok('탈퇴: 댓글 달린 글은 내용을 지우고 지움 표시 (작성자 비움, 안 보임)',
  (select author_id is null and deleted_at is not null and delete_kind = 'author' and title = '' and body = '' from posts where id = :p_quit));
select t.ok('탈퇴: 나머지 글은 지움', (select count(*) = 0 from posts where title like '목록 %'));
select t.ok('남은 댓글 경험치 그대로', (select count(*) = 1 from post_comments where post_id = :p_quit));

-- ===================================================================
-- 11. 운영자는 경험치 없음
-- ===================================================================
set role authenticated;
set request.jwt.claim.sub = :'A';
select public.create_post('공지', '운영자 글');
reset role;
select t.ok('운영자 글: 경험치·칭호 없음', pg_temp.xp(:'A') = 0 and pg_temp.titles(:'A') = '{}');
