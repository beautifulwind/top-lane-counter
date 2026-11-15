-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 058: 탑신병자 커뮤니티 답글 + 빌드 댓글·답글
--   2단계 제한(함수·표), 부모 확인, 비회원 금지, 읽기 정책, 알림(답글·글·빌드 주인, 나에게 없음, 합치기), 고치기·지우기,
--   부모가 지워져도 답글 유지, 신고·숨기기·다시 공개·운영진 삭제·기각, 감독관 목록, 개수, 경험치, 탈퇴 껍데기, 1년 정리, 운영자 조회
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

-- 퀸 상대법의 공개 빌드 하나를 B가 처음 만든 빌드로 (알림 받는 사람)
select id as qbuild, counter_id as quinn from builds where status = 'approved' order by id limit 1 \gset
select id as qbuild2 from builds where status = 'approved' and id <> :qbuild order by id limit 1 \gset
update builds set author_id = :'B', name = '정석' where id = :qbuild;

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
-- 3. 비회원: 빌드 댓글도 함수·표 모두 막힘 (탑신병자 커뮤니티 댓글은 guest_test)
-- ===================================================================
set request.jwt.claim.sub = :'G';
select t.fails('비회원 빌드 댓글 불가', format($$select create_build_comment(%s, 'x')$$, :qbuild), '비회원은 댓글을 달 수 없습니다');
reset role;
select t.fails('비회원 빌드 댓글 불가 (표 트리거)', format($$insert into build_comments (build_id, author_id, body) values (%s, %L, 'x')$$, :qbuild, :'G'),
  '비회원은 댓글을 달 수 없습니다');

-- ===================================================================
-- 4. 빌드 댓글·답글: 쓰기, 알림, 개수, 읽기
-- ===================================================================
set role authenticated;
set request.jwt.claim.sub = :'D';
select create_build_comment(:qbuild, '  D 빌드 댓글  ') as b1 \gset
reset role;
select t.ok('빌드 댓글 저장 (앞뒤 공백 정리)', (select body = 'D 빌드 댓글' and author_id = :'D' from build_comments where id = :b1));
select t.ok('빌드 주인에게 build_comment 알림 (빌드·상대법 id, 빌드 이름)',
  pg_temp.notes(:'B', 'build_comment') = 1
  and (select build_id = :qbuild and counter_id = :quinn from notifications where user_id = :'B' and kind = 'build_comment')
  and pg_temp.msg(:'B', 'build_comment') like '%정석%');
set role authenticated;
set request.jwt.claim.sub = :'F';
select create_build_comment(:qbuild, 'F 답글', :b1) as br1 \gset
reset role;
select t.ok('빌드 답글: 부모 작성자 D에게 comment_reply (빌드 id)',
  (select build_id = :qbuild and counter_id = :quinn and post_id is null from notifications where user_id = :'D' and kind = 'comment_reply' and build_id is not null));
select t.ok('빌드 주인 알림은 합쳐짐 (2개)', pg_temp.notes(:'B', 'build_comment') = 1 and pg_temp.msg(:'B', 'build_comment') like '%새 댓글 2개%');
set role authenticated;
set request.jwt.claim.sub = :'B';
select create_build_comment(:qbuild, 'B 자기 빌드에 댓글') as b2 \gset
reset role;
select t.ok('내 빌드에 내 댓글: 알림 없음', pg_temp.msg(:'B', 'build_comment') like '%새 댓글 2개%');
select t.ok('빌드 댓글 수 3', (select comment_count = 3 from builds where id = :qbuild));
set role authenticated;
set request.jwt.claim.sub = :'F';
select t.fails('빌드 3단계 불가', format($$select create_build_comment(%s, 'x', %s)$$, :qbuild, :br1), '답글에는 답글을 달 수 없습니다');
select t.fails('다른 빌드의 댓글에 답글 불가', format($$select create_build_comment(%s, 'x', %s)$$, :qbuild2, :b1), '답글을 달 댓글을 찾지 못했습니다');
select t.fails('빈 댓글 불가', format($$select create_build_comment(%s, '   ')$$, :qbuild), '댓글을 적어 주세요');
select t.fails('1000자 넘으면 불가', format($$select create_build_comment(%s, %L)$$, :qbuild, repeat('가', 1001)), '1000자 이하');
select t.fails('표에 직접 쓰기 권한 없음', format($$insert into build_comments (build_id, author_id, body) values (%s, auth.uid(), 'x')$$, :qbuild), 'permission denied');
reset role;
select t.fails('빌드 3단계 불가 (표 트리거)', format($$insert into build_comments (build_id, author_id, body, parent_id) values (%s, %L, 'x', %s)$$, :qbuild, :'F', :br1),
  '답글에는 답글을 달 수 없습니다');
update xp_rules set value = 5 where key = 'comment_interval';
set role authenticated;
set request.jwt.claim.sub = :'F';
select t.fails('도배 간격 (comment_interval 공유)', format($$select create_build_comment(%s, 'x')$$, :qbuild), '초에 한 번');
reset role;
update xp_rules set value = 0 where key = 'comment_interval';
set role anon;
set request.jwt.claim.sub = '';
select t.ok('비로그인도 빌드 댓글을 읽음', (select count(*) from build_comments where build_id = :qbuild) = 3);
select t.fails('비로그인은 쓸 수 없음', format($$select create_build_comment(%s, 'x')$$, :qbuild), 'permission denied');

-- 숨긴 빌드: 댓글은 운영자만, 새 댓글 불가
set role authenticated;
set request.jwt.claim.sub = :'A';
select hide_build(:qbuild2, '테스트 숨김');
set request.jwt.claim.sub = :'F';
select t.fails('숨긴 빌드에 댓글 불가', format($$select create_build_comment(%s, 'x')$$, :qbuild2), '빌드를 찾지 못했습니다');
reset role;
insert into build_comments (build_id, author_id, body) values (:qbuild2, :'F', '숨긴 빌드의 댓글') returning id as qb2c \gset
set role authenticated;
set request.jwt.claim.sub = :'D';
select t.ok('숨긴 빌드의 댓글은 일반 회원에게 안 보임', not exists (select 1 from build_comments where build_id = :qbuild2));
set request.jwt.claim.sub = :'A';
select t.ok('운영자는 숨긴 빌드의 댓글도 봄', exists (select 1 from build_comments where build_id = :qbuild2));

-- ===================================================================
-- 5. 고치기·지우기
-- ===================================================================
set request.jwt.claim.sub = :'D';
select begin_edit('build_comment', :b1) is not null as ok \gset
select t.ok('고치기 열기 (유예)', :'ok'::boolean);
select edit_build_comment(:b1, 'D 고친 댓글');
reset role;
select t.ok('고치면 수정됨 표시', (select body = 'D 고친 댓글' and edited_at is not null from build_comments where id = :b1));
set role authenticated;
set request.jwt.claim.sub = :'F';
select t.fails('남의 댓글 고치기 불가', format($$select edit_build_comment(%s, 'x')$$, :b1), '내 댓글만 고칠 수 있습니다');
select t.fails('남의 댓글 지우기 불가', format($$select delete_my_build_comment(%s)$$, :b1), '내 댓글만 지울 수 있습니다');
reset role;
update build_comments set created_at = now() - interval '11 minutes', edit_grace_until = null where id = :b1;
set role authenticated;
set request.jwt.claim.sub = :'D';
select t.fails('10분 지나면 고치기 불가', format($$select edit_build_comment(%s, 'y')$$, :b1), '고칠 수 있는 시간이 지났습니다');

-- ===================================================================
-- 6. 신고 · 기각 · 숨기기 · 다시 공개 · 운영진 삭제 (감독관 포함)
-- ===================================================================
set request.jwt.claim.sub = :'F';
select report_build_comment(:b1, 'spam');
select t.fails('같은 댓글 두 번 신고 불가', format($$select report_build_comment(%s, 'spam')$$, :b1), '이미 신고한 댓글입니다');
set request.jwt.claim.sub = :'D';
select t.fails('내 댓글 신고 불가', format($$select report_build_comment(%s, 'spam')$$, :b1), '내 댓글은 신고할 수 없습니다');
reset role;
select t.ok('새 신고 알림 (빌드 댓글, 상대법 링크)',
  (select count(*) from notifications where kind = 'report_received' and message like '%빌드 댓글%' and counter_id = :quinn) >= 1);
set role authenticated;
set request.jwt.claim.sub = :'M';
select t.ok('감독관 신고 목록에 빌드 댓글 (빌드·상대법 포함, 신고자 없음)',
  (select bool_or((x ->> 'build_comment_id')::bigint = :b1 and x -> 'build_comment' -> 'build' -> 'counter' ->> 'counter_champion' = 'Quinn'
                  and x -> 'reporter' = 'null'::jsonb)
     from jsonb_array_elements(open_reports_for_moderator()) x));
select dismiss_reports(null, null, '문제 없음', null, :b1) as n \gset
select t.ok('신고 기각 (빌드 댓글)', :n = 1);
reset role;
select t.ok('기각 처리 기록', exists (select 1 from moderation_log where action = 'dismiss_reports' and target_kind = 'build_comment' and target_id = :b1::text));
set role authenticated;
set request.jwt.claim.sub = :'M';
select hide_build_comment(:b1, '욕설');
reset role;
select t.ok('숨기기: 작성자 알림·숨김 기록·개수에서 빠짐',
  pg_temp.notes(:'D', 'build_comment_hidden') = 1
  and exists (select 1 from hide_log where kind = 'build_comment' and target_id = :b1 and unhidden_at is null)
  and (select comment_count = 2 from builds where id = :qbuild));
set role authenticated;
set request.jwt.claim.sub = :'F';
select t.ok('숨긴 댓글은 일반 회원에게 안 보임 (답글은 보임)', not exists (select 1 from build_comments where id = :b1) and exists (select 1 from build_comments where id = :br1));
set request.jwt.claim.sub = :'M';
select restore_build_comment(:b1, '오해');
reset role;
select t.ok('다시 공개: 알림·숨김 기록 닫힘', pg_temp.notes(:'D', 'build_comment_restored') = 1
  and not exists (select 1 from hide_log where kind = 'build_comment' and target_id = :b1 and unhidden_at is null));
set role authenticated;
set request.jwt.claim.sub = :'A';
select create_build_comment(:qbuild, '운영자 댓글') as ba \gset
set request.jwt.claim.sub = :'M';
select t.fails('감독관은 운영진 댓글을 못 숨김', format($$select hide_build_comment(%s, 'x')$$, :ba), '감독관이 처리할 수 없습니다');
select t.fails('감독관은 숨긴 빌드의 댓글을 처리 못 함',
  format($$select hide_build_comment(%s, 'x')$$, :qb2c), '숨긴 빌드의 댓글은 운영자만');
select staff_delete_build_comment(:br1, '도배');
reset role;
select t.ok('운영진 삭제: 지움 표시·작성자 알림·처리 기록',
  (select delete_kind = 'staff' and delete_note = '도배' from build_comments where id = :br1)
  and pg_temp.notes(:'F', 'build_comment_deleted') = 1
  and exists (select 1 from moderation_log where action = 'delete' and target_kind = 'build_comment'));

-- ===================================================================
-- 7. 경험치 (댓글 +1, 하루 상한 합산) · 탑신병자 · 운영자 조회
-- ===================================================================
select t.ok('빌드 댓글도 댓글 경험치 (키 build_comment:)',
  exists (select 1 from xp_should_have(:'D') where source_key = 'build_comment:' || :b1 and kind = 'build_comment'));
select t.ok('지운 빌드 댓글은 경험치 없음', not exists (select 1 from xp_should_have(:'F') where source_key = 'build_comment:' || :br1));
select t.ok('탑신병자 기준에 빌드 댓글', has_visible_writing(:'D'));
set role authenticated;
set request.jwt.claim.sub = :'A';
select t.ok('회원 정보: 댓글 수에 빌드 댓글 포함', (select (admin_member_info(:'F') ->> 'deleted_comments')::int >= 1));
select t.ok('지운 글·댓글 조회에 빌드 댓글', (select jsonb_array_length(admin_deleted_writings(:'F') -> 'build_comments') = 1));

-- ===================================================================
-- 8. 탈퇴: 남의 답글이 달린 내 댓글은 내용·작성자를 비운 껍데기, 나머지 내 댓글은 삭제
-- ===================================================================
set request.jwt.claim.sub = :'D';
select create_build_comment(:qbuild, 'D 혼자 댓글') as b3 \gset
select create_comment(:p2, 'D 혼자 글 댓글') as c3 \gset
set request.jwt.claim.sub = :'F';
select create_build_comment(:qbuild, 'F가 D에게', :b1) as br2 \gset
reset role;
delete from auth.users where id = :'D';
select t.ok('탈퇴: 남의 답글 달린 빌드 댓글은 껍데기 (내용·작성자 비움, 지움)',
  (select author_id is null and body = '' and deleted_at is not null from build_comments where id = :b1)
  and exists (select 1 from build_comments where id = :br2));
select t.ok('탈퇴: 남의 답글 달린 글 댓글(지운 것)도 껍데기, 답글 유지',
  (select author_id is null and body = '' from post_comments where id = :c1) and exists (select 1 from post_comments where id = :r1));
select t.ok('탈퇴: 답글 없는 내 댓글·내 답글은 삭제',
  not exists (select 1 from build_comments where id = :b3) and not exists (select 1 from post_comments where id in (:c3, :r3)));
select t.ok('탈퇴: 껍데기의 신고도 지움', not exists (select 1 from reports where build_comment_id = :b1));

-- ===================================================================
-- 9. 1년 정리: 남은 답글이 있는 부모는 남기고, 답글이 모두 정리되면 함께
-- ===================================================================
update build_comments set deleted_at = now() - interval '400 days' where id = :b1;
select purge_deleted_writings() as purged \gset
select t.ok('1년 정리: 살아 있는 답글이 있는 부모 껍데기는 남김', exists (select 1 from build_comments where id = :b1));
update build_comments set deleted_at = now() - interval '400 days', delete_kind = 'author' where parent_id = :b1;
select purge_deleted_writings() as purged \gset
select t.ok('1년 정리: 답글도 모두 정리 대상이면 부모와 함께 지움', not exists (select 1 from build_comments where id = :b1 or parent_id = :b1)
  and (:'purged'::jsonb ->> 'build_comments')::int >= 1);

-- ===================================================================
-- 10. 빌드 완전 삭제 → 댓글·알림도 함께 / 권한
-- ===================================================================
delete from builds where id = :qbuild2;
select t.ok('빌드가 지워지면 그 댓글도', not exists (select 1 from build_comments where build_id = :qbuild2));
select t.ok('내부 도우미는 아무도 못 부름',
  not has_function_privilege('authenticated', 'public.notify_new_comment(text, bigint, uuid, uuid, boolean)', 'execute')
  and not has_function_privilege('anon', 'public.build_comment_for_update(bigint)', 'execute')
  and not has_function_privilege('authenticated', 'public.require_moderate_open_build(bigint)', 'execute'));
select t.ok('화면 함수는 로그인한 사람만',
  has_function_privilege('authenticated', 'public.create_build_comment(bigint, text, bigint)', 'execute')
  and not has_function_privilege('anon', 'public.create_build_comment(bigint, text, bigint)', 'execute')
  and has_function_privilege('authenticated', 'public.create_comment(bigint, text, text[], bigint)', 'execute')
  and not has_function_privilege('anon', 'public.dismiss_reports(bigint, bigint, text, bigint, bigint)', 'execute'));
select t.ok('새 알림 종류는 휴대폰 알림 없음 (기존 댓글 알림과 같음)',
  push_group('build_comment') is null and push_group('comment_reply') is null and push_group('build_comment_hidden') is null);
