-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 016: 문서 댓글 (쓰기·고치기·지우기·신고·숨기기, 카운터 숨김·삭제, 첫 제안자 알림, 경험치 상한 합산, 탑신병자)
--      + 고치기 시간 제한 (글 60분, 댓글 10분, 마감 전에 열면 5분 유예, 지우기는 언제든)
\set ON_ERROR_STOP 1
\set QUIET 1
\set A '00000000-0000-0000-0000-00000000000a'
\set B '00000000-0000-0000-0000-00000000000b'
\set D '00000000-0000-0000-0000-00000000000d'
\set F '00000000-0000-0000-0000-00000000000f'
insert into auth.users (id, email) values (:'A', 'op@x.com'), (:'B', 'b@x.com'), (:'D', 'd@x.com'), (:'F', 'f@x.com');
update public.profiles set nickname = '영자', role = 'admin' where id = :'A';
update public.profiles set nickname = '비' where id = :'B';
update public.profiles set nickname = '디' where id = :'D';
update public.profiles set nickname = '에프' where id = :'F';
update public.xp_rules set value = 0 where key in ('post_interval', 'comment_interval');
\set doc '{"summary":"가렌 요약","level_notes":{"1":"a","2":"b","3":"c","6":"d"},"lane_cautions":""}'

create function pg_temp.xp(u uuid) returns integer language sql as $$ select xp from public.profiles where id = u $$;
create function pg_temp.titles(u uuid) returns text[] language sql as $$
  select coalesce(array_agg(title_key order by title_key), '{}') from public.user_titles where user_id = u $$;
create function pg_temp.notes(u uuid, k text) returns integer language sql as $$
  select count(*)::integer from public.notifications where user_id = u and kind = k $$;
grant execute on all functions in schema pg_temp to anon, authenticated;

-- B가 제안해서 승인된 가렌 카운터 (첫 제안자 = B)
set role authenticated;
set request.jwt.claim.sub = :'B';
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Garen', auth.uid(), :'doc', t.build());
reset role;
select id as garen_p from edit_proposals where counter_champion = 'Garen' \gset
set role authenticated;
set request.jwt.claim.sub = :'A';
select approve_proposal(:garen_p, '좋습니다', null, null, 1) as garen \gset
reset role;
select id as quinn from counters where counter_champion = 'Quinn' \gset
select xp as b0 from profiles where id = :'B' \gset

-- ===================================================================
-- 1. 쓰기 · 알림 (첫 제안자에게, 합치기) · 경험치
-- ===================================================================
set request.jwt.claim.sub = '';
set role anon;
select t.fails('비로그인: 못 씀', format('select public.create_doc_comment(%s, %L)', :garen, 'x'), 'permission denied');
reset role;
set role authenticated;
set request.jwt.claim.sub = :'D';
select t.fails('직접 insert 막힘', format('insert into public.doc_comments (counter_id, author_id, body) values (%s, auth.uid(), %L)', :garen, 'x'), 'permission denied');
select t.fails('빈 댓글', format('select public.create_doc_comment(%s, %L)', :garen, ' '), '댓글을 적어 주세요');
select public.create_doc_comment(:garen, '가렌 문서 좋네요') as d1 \gset
reset role;
select t.ok('첫 제안자에게 알림 (문서 연결)',
  (select message = '내가 제안한 카운터 문서에 새 댓글이 달렸습니다.' and counter_id = :garen
   from notifications where user_id = :'B' and kind = 'doc_comment'));
select t.ok('문서 댓글 +1, 탑신병자', pg_temp.xp(:'D') = 1 and pg_temp.titles(:'D') = array['top_addict']);
select t.ok('내역: 문서 댓글 (매치업 이름, ref = 카운터:댓글)',
  (select type = 'doc_comment' and target_champion = 'Darius' and counter_champion = 'Garen' and ref_id = :garen || ':' || :d1
   from xp_events where user_id = :'D' and source_key = 'doc_comment:' || :d1));

set role authenticated;
set request.jwt.claim.sub = :'F';
select public.create_doc_comment(:garen, '저도요') as d2 \gset
set request.jwt.claim.sub = :'B';
select public.create_doc_comment(:garen, '제안자 본인 댓글') as d_own \gset
reset role;
select t.ok('알림 합침 (새 댓글 2개), 제안자 본인 댓글은 알림 없음',
  pg_temp.notes(:'B', 'doc_comment') = 1
  and (select message = '내가 제안한 카운터 문서에 새 댓글 2개가 달렸습니다.' from notifications where user_id = :'B' and kind = 'doc_comment'));

set role authenticated;
set request.jwt.claim.sub = :'D';
select public.create_doc_comment(:quinn, '초기 데이터 문서') as d_q \gset
reset role;
select t.ok('제안자 없는 카운터는 알림 없음', (select count(*) = 0 from notifications where counter_id = :quinn));

set request.jwt.claim.sub = '';
set role anon;
select t.ok('비로그인도 읽기', (select count(*) = 4 from doc_comments));
reset role;

-- 도배 간격은 게시판 댓글과 공유
update public.xp_rules set value = 5 where key = 'comment_interval';
update public.board_last_write set comment_at = now() where user_id = :'F';
set role authenticated;
set request.jwt.claim.sub = :'F';
select t.fails('게시판 댓글 간격 공유', format('select public.create_doc_comment(%s, %L)', :garen, 'x'), '댓글은 5초에 한 번');
reset role;
update public.xp_rules set value = 0 where key = 'comment_interval';

-- ===================================================================
-- 2. 하루 상한: 게시판 댓글 + 문서 댓글 합쳐서 10
-- ===================================================================
set role authenticated;
set request.jwt.claim.sub = :'F';
select public.create_post('에프 글', '본문') as fp \gset
select public.create_comment(:fp, '게시판 ' || n) from generate_series(1, 6) n;
select public.create_doc_comment(:garen, '문서 ' || n) from generate_series(1, 6) n;
reset role;
select t.ok('댓글 13개 → 상한 10 (합산)',
  (select coalesce(sum(amount), 0) = 10 from xp_events where user_id = :'F' and type in ('comment', 'doc_comment')));

-- ===================================================================
-- 3. 고치기·지우기·신고·숨기기
-- ===================================================================
set role authenticated;
set request.jwt.claim.sub = :'F';
select t.fails('남의 문서 댓글 고치기', format('select public.edit_doc_comment(%s, %L)', :d1, 'x'), '내 댓글만 고칠 수 있습니다');
select t.fails('남의 문서 댓글 지우기', format('select public.delete_my_doc_comment(%s)', :d1), '내 댓글만 지울 수 있습니다');
select public.report_doc_comment(:d1, 'abuse');
select t.fails('같은 댓글 두 번 신고', format('select public.report_doc_comment(%s, %L)', :d1, 'spam'), '이미 신고한 댓글');
set request.jwt.claim.sub = :'D';
select t.fails('내 댓글 신고', format('select public.report_doc_comment(%s, %L)', :d1, 'spam'), '내 댓글은 신고할 수 없습니다');
select public.edit_doc_comment(:d1, '가렌 문서 좋네요 (고침)');
select t.ok('고치면 수정됨', (select edited_at is not null from doc_comments where id = :d1));
set request.jwt.claim.sub = :'F';
select t.fails('일반 유저 숨기기', format('select public.hide_doc_comment(%s, %L)', :d1, 'x'), '운영자만');
set request.jwt.claim.sub = :'A';
select t.fails('숨기기 메모 필수', format('select public.hide_doc_comment(%s, %L)', :d1, ''), '숨기는 이유를 적어');
select public.hide_doc_comment(:d1, '욕설');
reset role;
select t.ok('숨김: 신고 처리됨, 알림, 경험치 회수 (댓글 숨김), 탑신병자 회수',
  (select status = 'resolved' from reports where doc_comment_id = :d1)
  and (select message = '문서에 쓴 내 댓글을 운영진이 숨겼습니다. 메모: 욕설' and counter_id = :garen from notifications where user_id = :'D' and kind = 'doc_comment_hidden')
  and (select reason = '댓글 숨김' from xp_events where user_id = :'D' and source_key = 'doc_comment:' || :d1 and change = 'revoke')
  and pg_temp.xp(:'D') = 1 and pg_temp.titles(:'D') = array['top_addict']);  -- 퀸 문서 댓글이 남아 있음
set request.jwt.claim.sub = '';
set role anon;
select t.ok('숨긴 댓글은 안 보임', (select count(*) = 0 from doc_comments where id = :d1));
reset role;
set role authenticated;
set request.jwt.claim.sub = :'D';
select t.fails('숨긴 댓글 고치기', format('select public.edit_doc_comment(%s, %L)', :d1, 'x'), '숨긴 댓글·문서는 고칠 수 없습니다');
set request.jwt.claim.sub = :'A';
select public.restore_doc_comment(:d1, '다시 봄');
reset role;
select t.ok('다시 공개: 경험치·알림', pg_temp.xp(:'D') = 2 and pg_temp.notes(:'D', 'doc_comment_restored') = 1);

set role authenticated;
set request.jwt.claim.sub = :'D';
select public.report_doc_comment(:d2, 'spam');
set request.jwt.claim.sub = :'A';
select t.ok('문서 댓글 신고 기각', public.dismiss_reports(null, null, '괜찮음', :d2) = 1);
select t.ok('운영자는 문서 댓글 신고를 본다', (select count(*) = 2 from reports where doc_comment_id is not null));
reset role;

set role authenticated;
set request.jwt.claim.sub = :'D';
select public.delete_my_doc_comment(:d_q);
reset role;
select t.ok('지우면 회수 (댓글 삭제)',
  (select reason = '댓글 삭제' from xp_events where user_id = :'D' and source_key = 'doc_comment:' || :d_q and change = 'revoke'));

-- ===================================================================
-- 4. 카운터 숨김 → 댓글도 운영자만, 새 댓글·고치기·신고 막힘, 경험치 유지 / 완전 삭제 → 같이 지움, 회수
-- ===================================================================
set role authenticated;
set request.jwt.claim.sub = :'A';
select hide_counter(:garen, '확인 필요');
reset role;
select t.ok('카운터 숨김: 댓글 경험치 유지', pg_temp.xp(:'D') = 1 and pg_temp.titles(:'D') = array['top_addict']);
set request.jwt.claim.sub = '';
set role anon;
select t.ok('숨긴 카운터의 댓글은 안 보임', (select count(*) = 0 from doc_comments where counter_id = :garen));
reset role;
set role authenticated;
set request.jwt.claim.sub = :'D';
select t.fails('숨긴 카운터에 댓글', format('select public.create_doc_comment(%s, %L)', :garen, 'x'), '댓글을 달 수 없는 문서');
select t.fails('숨긴 카운터의 댓글 고치기', format('select public.edit_doc_comment(%s, %L)', :d1, 'x'), '숨긴 댓글·문서는 고칠 수 없습니다');
set request.jwt.claim.sub = :'F';
select t.fails('숨긴 카운터의 댓글 신고', format('select public.report_doc_comment(%s, %L)', :d1, 'spam'), '신고할 수 없는 댓글');
set request.jwt.claim.sub = :'A';
select t.ok('운영자는 본다', (select count(*) > 0 from doc_comments where counter_id = :garen));
select delete_counter(:garen, 'Garen', '중복');
reset role;
select t.ok('완전 삭제: 댓글도 지움, 삭제 기록에 댓글 수',
  (select count(*) = 0 from doc_comments where counter_id = :garen)
  and (select comments_count = 9 from counter_deletions where counter_id = :garen));
select t.ok('완전 삭제: 댓글 경험치 회수 (카운터 삭제), 탑신병자 회수',
  pg_temp.xp(:'D') = 0 and pg_temp.titles(:'D') = '{}'
  and (select reason = '카운터 삭제' from xp_events where user_id = :'D' and source_key = 'doc_comment:' || :d1 order by id desc limit 1));
select t.ok('합산 상한: 지워진 문서 댓글 자리에 게시판 댓글이 들어옴 (에프 6개 = 6)',
  (select coalesce(sum(amount), 0) = 6 from xp_events where user_id = :'F' and type in ('comment', 'doc_comment')));

-- ===================================================================
-- 5. 고치기 시간 제한
-- ===================================================================
set role authenticated;
set request.jwt.claim.sub = :'D';
select public.create_post('시간 글', '본문') as tp \gset
select public.create_comment(:tp, '시간 댓글') as tc \gset
select public.create_doc_comment(:quinn, '시간 문서 댓글') as tdc \gset
reset role;

-- 글: 59분 → 고칠 수 있음 / 61분 → 못 고침, 지우기는 됨
update posts set created_at = now() - interval '59 minutes' where id = :tp;
set role authenticated;
set request.jwt.claim.sub = :'D';
select public.edit_post(:tp, '시간 글 (고침)', '본문');
reset role;
update posts set created_at = now() - interval '61 minutes', edit_grace_until = null where id = :tp;
set role authenticated;
set request.jwt.claim.sub = :'D';
select t.fails('글: 1시간 지나면 못 고침', format('select public.edit_post(%s, %L, %L)', :tp, 'x', 'y'), '고칠 수 있는 시간이 지났습니다');
select t.fails('글: 마감 뒤에 열면 유예 없음', format('select public.begin_edit(%L, %s)', 'post', :tp), '고칠 수 있는 시간이 지났습니다');
reset role;

-- 댓글: 9분에 열면 5분 유예 → 12분에 저장 가능, 유예가 끝나면 못 고침
update post_comments set created_at = now() - interval '9 minutes' where id = :tc;
set role authenticated;
set request.jwt.claim.sub = :'D';
select t.ok('마감 전에 열기 → 저장 마감 = 지금 + 5분 (마감보다 늦음)',
  public.begin_edit('comment', :tc) between now() + interval '4 minutes 59 seconds' and now() + interval '5 minutes 1 second');
reset role;
update post_comments set created_at = now() - interval '12 minutes' where id = :tc;
set role authenticated;
set request.jwt.claim.sub = :'D';
select public.edit_comment(:tc, '유예 중에 고침');
select t.ok('유예 중이면 저장됨', (select body = '유예 중에 고침' from post_comments where id = :tc));
select t.ok('유예 중에 다시 열어도 유예는 늘지 않음 (마감이 지남)',
  public.begin_edit('comment', :tc) = (select edit_grace_until from post_comments where id = :tc));
reset role;
update post_comments set edit_grace_until = now() - interval '1 second' where id = :tc;
set role authenticated;
set request.jwt.claim.sub = :'D';
select t.fails('유예가 끝나면 못 고침', format('select public.edit_comment(%s, %L)', :tc, 'x'), '고칠 수 있는 시간이 지났습니다');
select public.delete_my_comment(:tc);
select t.ok('시간이 지나도 지우기는 됨', (select count(*) = 0 from post_comments where id = :tc));
reset role;

-- 문서 댓글: 11분 → 못 고침, 남의 것 열기 막힘
update doc_comments set created_at = now() - interval '11 minutes' where id = :tdc;
set role authenticated;
set request.jwt.claim.sub = :'D';
select t.fails('문서 댓글: 10분 지나면 못 고침', format('select public.edit_doc_comment(%s, %L)', :tdc, 'x'), '고칠 수 있는 시간이 지났습니다');
set request.jwt.claim.sub = :'F';
select t.fails('남의 것은 열 수 없음', format('select public.begin_edit(%L, %s)', 'doc_comment', :tdc), '내 글·댓글만');
set request.jwt.claim.sub = :'D';
select public.delete_my_doc_comment(:tdc);
reset role;

-- 숫자는 xp_rules로 바꾼다
update public.xp_rules set value = 30 where key = 'comment_edit_minutes';
update doc_comments set created_at = now() where false;
set role authenticated;
set request.jwt.claim.sub = :'D';
select public.create_doc_comment(:quinn, '규칙 바꾸기') as rdc \gset
reset role;
update doc_comments set created_at = now() - interval '20 minutes' where id = :rdc;
set role authenticated;
set request.jwt.claim.sub = :'D';
select public.edit_doc_comment(:rdc, '30분으로 늘려서 고침');
select t.ok('comment_edit_minutes를 30으로 바꾸면 20분 뒤에도 고침', (select body = '30분으로 늘려서 고침' from doc_comments where id = :rdc));
reset role;

-- ===================================================================
-- 6. 탈퇴하면 문서 댓글도 지움
-- ===================================================================
delete from auth.users where id = :'D';
select t.ok('탈퇴: 문서 댓글 지움', (select count(*) = 0 from doc_comments where id = :rdc));
