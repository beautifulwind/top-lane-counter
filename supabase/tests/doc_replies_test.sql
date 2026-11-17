-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 059: 문서 댓글 답글 (2단계)
--   2단계 제한(함수·표), 부모 확인, 비회원(최상위는 가능, 답글은 함수·표 둘 다 막음), 알림(부모 작성자·첫 제안자, 나에게 없음, 합치기,
--   빌드 답글 알림과 섞이지 않음), 부모가 지워져도 답글 유지, 신고·숨기기·다시 공개·운영진 삭제, 경험치(하루 상한 합산), 탈퇴 껍데기, 1년 정리, 권한
\set ON_ERROR_STOP 1
\set QUIET 1
\set A '00000000-0000-0000-0000-00000000000a'
\set B '00000000-0000-0000-0000-00000000000b'
\set D '00000000-0000-0000-0000-00000000000d'
\set F '00000000-0000-0000-0000-00000000000f'
\set G '00000000-0000-0000-0000-0000000000a1'
insert into auth.users (id, email) values (:'A', 'op@x.com'), (:'B', 'b@x.com'), (:'D', 'd@x.com'), (:'F', 'f@x.com');
insert into auth.users (id, is_anonymous) values (:'G', true);
update public.profiles set nickname = '영자', role = 'admin' where id = :'A';
update public.profiles set nickname = '비' where id = :'B';
update public.profiles set nickname = '디' where id = :'D';
update public.profiles set nickname = '에프' where id = :'F';
update public.profiles set nickname = '손님' where id = :'G';
update public.xp_rules set value = 0 where key in ('post_interval', 'comment_interval');
\set doc '{"summary":"가렌 요약","level_notes":{"1":"a","2":"b","3":"c","6":"d"},"lane_cautions":""}'

create function pg_temp.notes(u uuid, k text) returns integer language sql as $$
  select count(*)::integer from public.notifications where user_id = u and kind = k $$;
create function pg_temp.msg(u uuid, k text) returns text language sql as $$
  select message from public.notifications where user_id = u and kind = k order by id desc limit 1 $$;
grant execute on all functions in schema pg_temp to anon, authenticated;

-- B가 제안해서 승인된 가렌 상대법 (첫 제안자 = B)
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
select id as gbuild from builds where counter_id = :garen and status = 'approved' order by id limit 1 \gset

-- ===================================================================
-- 1. 답글 달기 · 알림 (부모 작성자 comment_reply, 첫 제안자 doc_comment)
-- ===================================================================
set role authenticated;
set request.jwt.claim.sub = :'D';
select create_doc_comment(:garen, 'D 댓글') as d1 \gset
reset role;
select t.ok('최상위 댓글: 첫 제안자 알림 (기존 문장 그대로)',
  pg_temp.notes(:'B', 'doc_comment') = 1 and pg_temp.msg(:'B', 'doc_comment') = '내가 제안한 상대법 문서에 새 댓글이 달렸습니다.');
set role authenticated;
set request.jwt.claim.sub = :'F';
select create_doc_comment(:garen, 'F 답글', :d1) as r1 \gset
reset role;
select t.ok('답글 저장 (parent_id)', (select parent_id = :d1 from doc_comments where id = :r1));
select t.ok('답글: 부모 작성자 D에게 comment_reply (상대법 id만)',
  (select count(*) = 1 and bool_and(counter_id = :garen and post_id is null and build_id is null
                                     and message = '상대법 문서에 쓴 내 댓글에 새 답글이 달렸습니다.')
     from notifications where user_id = :'D' and kind = 'comment_reply'));
select t.ok('답글: 첫 제안자 B의 새 댓글 알림이 합쳐짐 (2개)',
  pg_temp.notes(:'B', 'doc_comment') = 1 and pg_temp.msg(:'B', 'doc_comment') like '%새 댓글 2개%');
set role authenticated;
set request.jwt.claim.sub = :'B';
select create_doc_comment(:garen, 'B 답글', :d1) as r2 \gset
reset role;
select t.ok('또 답글: D의 답글 알림이 합쳐짐 (2개)',
  pg_temp.notes(:'D', 'comment_reply') = 1 and pg_temp.msg(:'D', 'comment_reply') = '상대법 문서에 쓴 내 댓글에 새 답글 2개가 달렸습니다.');
select t.ok('첫 제안자가 쓴 답글: 본인에게 알림 없음', pg_temp.msg(:'B', 'doc_comment') like '%새 댓글 2개%');
set role authenticated;
set request.jwt.claim.sub = :'D';
select create_doc_comment(:garen, 'D 자기 댓글에 답글', :d1) as r3 \gset
reset role;
select t.ok('내 댓글에 내가 답글: 나에게 알림 없음', pg_temp.msg(:'D', 'comment_reply') like '%새 답글 2개%');
update notifications set read_at = now() where user_id in (:'B', :'D');

-- 첫 제안자가 쓴 댓글에 남이 답글 → 답글 알림 하나만
set role authenticated;
set request.jwt.claim.sub = :'B';
select create_doc_comment(:garen, 'B 댓글') as db \gset
set request.jwt.claim.sub = :'F';
select create_doc_comment(:garen, 'F가 B에게', :db);
reset role;
select t.ok('첫 제안자 = 부모 작성자: 답글 알림 하나만 (새 댓글 알림 없음)',
  (select count(*) from notifications where user_id = :'B' and read_at is null) = 1
  and (select kind from notifications where user_id = :'B' and read_at is null) = 'comment_reply');

-- 같은 상대법의 빌드 댓글 답글 알림(058, build_id 있음 - 060 전에 남았던 모양)과는 합치지 않는다
insert into notifications (user_id, kind, message, build_id, counter_id)
values (:'D', 'comment_reply', '빌드 댓글 답글 (058 모양)', :gbuild, :garen);
set role authenticated;
set request.jwt.claim.sub = :'F';
select create_doc_comment(:garen, 'F 문서 답글', :d1);
reset role;
select t.ok('빌드 답글 알림과 문서 답글 알림은 따로',
  (select count(*) from notifications where user_id = :'D' and kind = 'comment_reply' and read_at is null) = 2
  and exists (select 1 from notifications where user_id = :'D' and kind = 'comment_reply' and read_at is null and build_id = :gbuild)
  and exists (select 1 from notifications where user_id = :'D' and kind = 'comment_reply' and read_at is null and build_id is null
                and message = '상대법 문서에 쓴 내 댓글에 새 답글이 달렸습니다.'));

-- ===================================================================
-- 2. 2단계 제한 · 부모 확인 (함수 + 표)
-- ===================================================================
set role authenticated;
set request.jwt.claim.sub = :'F';
select t.fails('3단계 불가 (함수)', format($$select create_doc_comment(%s, 'x', %s)$$, :garen, :r1), '답글에는 답글을 달 수 없습니다');
select t.fails('다른 문서의 댓글에 답글 불가', format($$select create_doc_comment(%s, 'x', %s)$$, :quinn, :d1), '답글을 달 댓글을 찾지 못했습니다');
select t.fails('없는 댓글에 답글 불가', format($$select create_doc_comment(%s, 'x', %s)$$, :garen, 999999), '답글을 달 댓글을 찾지 못했습니다');
select t.fails('표에 직접 쓰기 권한 없음',
  format($$insert into doc_comments (counter_id, author_id, body, parent_id) values (%s, auth.uid(), 'x', %s)$$, :garen, :d1), 'permission denied');
reset role;
select t.fails('3단계 불가 (표 트리거)',
  format($$insert into doc_comments (counter_id, author_id, body, parent_id) values (%s, %L, 'x', %s)$$, :garen, :'F', :r1), '답글에는 답글을 달 수 없습니다');
select t.fails('답글이 달린 댓글을 답글로 바꾸기 불가 (표 트리거)',
  format($$update doc_comments set parent_id = %s where id = %s$$, :db, :d1), '답글에는 답글을 달 수 없습니다');
select t.fails('다른 문서의 부모 불가 (복합 외래 키)',
  format($$insert into doc_comments (counter_id, author_id, body, parent_id) values (%s, %L, 'x', %s)$$, :quinn, :'F', :d1), 'doc_comments_parent_fkey');

-- ===================================================================
-- 3. 비회원: 최상위 문서 댓글은 가능, 답글은 함수·표 둘 다 막음
-- ===================================================================
set role authenticated;
set request.jwt.claim.sub = :'G';
select create_doc_comment(:garen, '손님 댓글') as g1 \gset
select t.fails('비회원 답글 불가 (함수)', format($$select create_doc_comment(%s, 'x', %s)$$, :garen, :d1), '비회원은 답글을 달 수 없습니다');
reset role;
select t.ok('비회원 최상위 댓글은 그대로 됨', exists (select 1 from doc_comments where id = :g1 and parent_id is null));
select t.fails('비회원 답글 불가 (표 트리거)',
  format($$insert into doc_comments (counter_id, author_id, body, parent_id) values (%s, %L, 'x', %s)$$, :garen, :'G', :d1), '비회원은 답글을 달 수 없습니다');
set role authenticated;
set request.jwt.claim.sub = :'F';
select create_doc_comment(:garen, '손님에게 답글', :g1) as rg \gset
reset role;
select t.ok('비회원의 댓글에 회원이 답글은 됨 (비회원에게 답글 알림)', pg_temp.notes(:'G', 'comment_reply') = 1);

-- ===================================================================
-- 4. 지운·숨긴 부모: 답글은 남고, 새 답글은 못 닮
-- ===================================================================
set role authenticated;
set request.jwt.claim.sub = :'D';
select create_doc_comment(:garen, 'D 두 번째') as d2 \gset
set request.jwt.claim.sub = :'F';
select create_doc_comment(:garen, 'F가 D 두 번째에', :d2) as r4 \gset
set request.jwt.claim.sub = :'D';
select delete_my_doc_comment(:d2);
set request.jwt.claim.sub = :'F';
select t.ok('부모를 지워도 답글은 보임 (부모는 안 보임)', exists (select 1 from doc_comments where id = :r4) and not exists (select 1 from doc_comments where id = :d2));
select t.fails('지운 댓글에 답글 불가', format($$select create_doc_comment(%s, 'x', %s)$$, :garen, :d2), '답글을 달 댓글을 찾지 못했습니다');
set request.jwt.claim.sub = :'A';
select hide_doc_comment(:db, '테스트');
set request.jwt.claim.sub = :'F';
select t.fails('숨긴 댓글에 답글 불가', format($$select create_doc_comment(%s, 'x', %s)$$, :garen, :db), '답글을 달 댓글을 찾지 못했습니다');
set request.jwt.claim.sub = :'A';
select restore_doc_comment(:db, '다시');

-- ===================================================================
-- 5. 답글도 같은 문서 댓글: 고치기 · 신고 · 숨기기 · 다시 공개 · 운영진 삭제
-- ===================================================================
set request.jwt.claim.sub = :'F';
select edit_doc_comment(:r1, 'F 답글 고침');
set request.jwt.claim.sub = :'D';
select report_doc_comment(:r1, 'spam');
reset role;
select t.ok('답글 고치기·신고', (select body = 'F 답글 고침' and edited_at is not null from doc_comments where id = :r1)
  and exists (select 1 from reports where doc_comment_id = :r1 and status = 'open'));
set role authenticated;
set request.jwt.claim.sub = :'A';
select hide_doc_comment(:r1, '욕설');
reset role;
select t.ok('답글 숨기기: 작성자 알림·숨김 기록·신고 처리',
  pg_temp.notes(:'F', 'doc_comment_hidden') = 1
  and exists (select 1 from hide_log where kind = 'doc_comment' and target_id = :r1 and unhidden_at is null)
  and not exists (select 1 from reports where doc_comment_id = :r1 and status = 'open'));
set role authenticated;
set request.jwt.claim.sub = :'A';
select restore_doc_comment(:r1, '오해');
select staff_delete_doc_comment(:r3, '도배');
reset role;
select t.ok('답글 다시 공개·운영진 삭제',
  pg_temp.notes(:'F', 'doc_comment_restored') = 1
  and (select delete_kind = 'staff' from doc_comments where id = :r3) and pg_temp.notes(:'D', 'doc_comment_deleted') = 1);

-- ===================================================================
-- 6. 경험치: 답글도 문서 댓글 +1, 하루 상한 10을 함께 씀
-- ===================================================================
select t.ok('답글도 문서 댓글 경험치 (키 doc_comment:)',
  exists (select 1 from xp_should_have(:'F') where source_key = 'doc_comment:' || :r1 and kind = 'doc_comment'));
select t.ok('지운 답글은 경험치 없음', not exists (select 1 from xp_should_have(:'D') where source_key = 'doc_comment:' || :r3));
set role authenticated;
set request.jwt.claim.sub = :'F';
select create_doc_comment(:garen, '도배 ' || i, :d1) from generate_series(1, 12) i;
reset role;
select t.ok('하루 상한: 댓글·답글 합쳐 10까지',
  (select count(*) from xp_should_have(:'F') where kind in ('comment', 'doc_comment', 'build_comment')
     and (at at time zone 'Asia/Seoul')::date = (now() at time zone 'Asia/Seoul')::date) = 10);

-- ===================================================================
-- 7. 탈퇴: 남의 답글이 달린 내 문서 댓글은 껍데기, 나머지 내 문서 댓글·답글은 삭제
-- ===================================================================
set role authenticated;
set request.jwt.claim.sub = :'D';
select create_doc_comment(:garen, 'D 혼자 댓글') as d3 \gset
select create_doc_comment(:garen, 'D가 B에게', :db) as rd \gset
set request.jwt.claim.sub = :'F';
select report_doc_comment(:d1, 'spam');
reset role;
delete from auth.users where id = :'D';
select t.ok('탈퇴: 남의 답글 달린 문서 댓글은 껍데기 (내용·작성자 비움, 지움), 답글 유지',
  (select author_id is null and body = '' and deleted_at is not null and delete_kind = 'author' from doc_comments where id = :d1)
  and exists (select 1 from doc_comments where id = :r1));
select t.ok('탈퇴: 지운 부모(답글 있음)도 껍데기', (select author_id is null and body = '' from doc_comments where id = :d2) and exists (select 1 from doc_comments where id = :r4));
select t.ok('탈퇴: 답글 없는 내 댓글·내 답글은 삭제', not exists (select 1 from doc_comments where id in (:d3, :rd)));
select t.ok('탈퇴: 껍데기의 신고도 지움', not exists (select 1 from reports where doc_comment_id = :d1));
set role authenticated;
set request.jwt.claim.sub = :'F';
select t.ok('껍데기는 아무에게도 안 보임 (화면은 "삭제된 댓글입니다")', not exists (select 1 from doc_comments where id = :d1));
select t.fails('껍데기에 답글 불가', format($$select create_doc_comment(%s, 'x', %s)$$, :garen, :d1), '답글을 달 댓글을 찾지 못했습니다');
reset role;
select t.fails('지우지 않은 댓글은 작성자가 있어야 함', format($$update doc_comments set author_id = null where id = %s$$, :r1), 'doc_comments_author_or_deleted');

-- ===================================================================
-- 8. 1년 정리: 남은 답글이 있는 부모는 남기고, 답글이 모두 정리되면 함께
-- ===================================================================
update doc_comments set deleted_at = now() - interval '400 days' where id = :d1;
select purge_deleted_writings() as purged \gset
select t.ok('1년 정리: 살아 있는 답글이 있는 부모 껍데기는 남김', exists (select 1 from doc_comments where id = :d1));
update doc_comments set deleted_at = now() - interval '400 days', delete_kind = 'author' where parent_id = :d1;
select purge_deleted_writings() as purged \gset
select t.ok('1년 정리: 답글도 모두 정리 대상이면 부모와 함께 지움',
  not exists (select 1 from doc_comments where id = :d1 or parent_id = :d1) and (:'purged'::jsonb ->> 'doc_comments')::int >= 1);

-- ===================================================================
-- 9. 권한
-- ===================================================================
select t.ok('create_doc_comment: 로그인한 사람만, 옛 모양(인자 2개)은 없음',
  has_function_privilege('authenticated', 'public.create_doc_comment(bigint, text, bigint)', 'execute')
  and not has_function_privilege('anon', 'public.create_doc_comment(bigint, text, bigint)', 'execute')
  and to_regprocedure('public.create_doc_comment(bigint, text)') is null);
select t.ok('비회원 답글 막기 함수는 아무도 못 부름',
  not has_function_privilege('authenticated', 'public.block_guest_reply()', 'execute')
  and not has_function_privilege('anon', 'public.block_guest_reply()', 'execute'));
select t.ok('답글 알림은 휴대폰 알림 없음', push_group('comment_reply') is null and push_group('doc_comment') is null);
