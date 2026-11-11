-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 036: 운영자 회원 현황·검색·정보 (운영자 전용, 민감 정보 없음) + 감독관 재검토 요청
\set ON_ERROR_STOP 1
\set QUIET 1
\set OP  '00000000-0000-0000-0000-00000000000a'
\set MOD '00000000-0000-0000-0000-00000000000b'
\set U   '00000000-0000-0000-0000-00000000000d'
\set G   '00000000-0000-0000-0000-00000000000e'
\set K   '00000000-0000-0000-0000-00000000000f'
\set GU  '00000000-0000-0000-0000-000000000010'
\set doc '{"summary":"요약","level_notes":{"1":"a","2":"b","3":"c","6":"d","9":"e","11":"f"},"lane_cautions":""}'
insert into auth.users (id, email) values (:'OP', 'op@x.com'), (:'MOD', 'm@x.com'), (:'U', 'secret-u@x.com'), (:'G', 'g@x.com'), (:'K', 'k@x.com');
insert into auth.users (id, email, is_anonymous) values (:'GU', null, true);
insert into auth.identities (user_id, provider, provider_id) values
  (:'U', 'google', 'SECRET-GOOGLE-ID'), (:'U', 'kakao', 'SECRET-KAKAO-ID'), (:'G', 'google', 'g-1'), (:'K', 'kakao', 'k-1'),
  (:'OP', 'google', 'op-1'), (:'MOD', 'google', 'mod-1');
update public.profiles set nickname = '영자', role = 'admin' where id = :'OP';
update public.profiles set nickname = '감독', role = 'moderator' where id = :'MOD';
update public.profiles set nickname = '유저_하나' where id = :'U';
update public.profiles set nickname = '구글러' where id = :'G';
update public.profiles set nickname = '카카오러' where id = :'K';
update public.profiles set created_at = now() - interval '30 days' where id in (:'G', :'MOD');

-- ===== 1. 권한: 운영자만 =====
set role anon;
select t.fails('비로그인: 통계 불가', 'select admin_member_stats()', 'permission denied');
select t.fails('비로그인: 검색 불가', $$select admin_search_members('유저')$$, 'permission denied');
select t.fails('비로그인: 회원 정보 불가', format('select admin_member_info(%L)', :'U'), 'permission denied');
reset role;
set role authenticated;
set request.jwt.claim.sub = :'U';
select t.fails('일반 회원: 통계 불가', 'select admin_member_stats()', '운영자만');
select t.fails('일반 회원: 검색 불가', $$select admin_search_members('유저')$$, '운영자만');
select t.fails('일반 회원: 회원 정보 불가', format('select admin_member_info(%L)', :'G'), '운영자만');
select t.fails('일반 회원: 본인 정보도 이 함수로는 불가', format('select admin_member_info(%L)', :'U'), '운영자만');
set request.jwt.claim.sub = :'MOD';
select t.fails('감독관: 통계 불가', 'select admin_member_stats()', '운영자만');
select t.fails('감독관: 검색 불가', $$select admin_search_members('유저')$$, '운영자만');
select t.fails('감독관: 회원 정보 불가', format('select admin_member_info(%L)', :'U'), '운영자만');
reset role;

-- ===== 2. 통계 =====
set role authenticated;
set request.jwt.claim.sub = :'OP';
select admin_member_stats() as st \gset
reset role;
select t.ok('총 가입자 = 프로필 수', (:'st'::jsonb ->> 'total')::int = (select count(*) from profiles));
select t.ok('정식 회원 5 + 비회원 1', (:'st'::jsonb ->> 'members')::int = 5 and (:'st'::jsonb ->> 'guests')::int = 1);
select t.ok('구글 4(운영자·감독·유저·구글러), 카카오 2(유저·카카오러), 둘 다 1', (:'st'::jsonb ->> 'google')::int = 4
  and (:'st'::jsonb ->> 'kakao')::int = 2 and (:'st'::jsonb ->> 'both')::int = 1);
select t.ok('최근 7일 신규: 30일 전 가입 2명 제외', (:'st'::jsonb ->> 'new_7d')::int = 4 and (:'st'::jsonb ->> 'new_7d_members')::int = 3);
select t.ok('통계에는 숫자만 (이메일 없음)', (select bool_and(jsonb_typeof(v) = 'number') from jsonb_each(:'st'::jsonb) e(k, v)));

-- ===== 3. 검색 =====
set role authenticated;
set request.jwt.claim.sub = :'OP';
select t.ok('부분 일치', jsonb_array_length(admin_search_members('러')) = 2);
select t.ok('대소문자 무시·앞뒤 공백 무시', admin_search_members('  유저  ') -> 0 ->> 'nickname' = '유저_하나');
select t.ok('_ 는 글자 그대로 (와일드카드 아님)', jsonb_array_length(admin_search_members('_')) = 1);
select t.ok('% 도 글자 그대로', jsonb_array_length(admin_search_members('%')) = 0);
select t.ok('없는 닉네임은 빈 목록', admin_search_members('없는사람') = '[]'::jsonb);
select t.fails('빈 검색어 불가', $$select admin_search_members('   ')$$, '찾을 닉네임');
select t.fails('NULL 검색어 불가', 'select admin_search_members(null)', '찾을 닉네임');
select t.fails('21자 이상 불가', format('select admin_search_members(%L)', repeat('가', 21)), '20자까지');
reset role;
-- 결과 수 상한 10
insert into auth.users (id) select gen_random_uuid() from generate_series(1, 14);
update public.profiles set nickname = '대량' || substr(id::text, 1, 6) where nickname is null;
set role authenticated;
set request.jwt.claim.sub = :'OP';
select t.ok('결과는 최대 10명', jsonb_array_length(admin_search_members('대량')) = 10);
select t.ok('결과에는 이메일·로그인 ID 같은 칸이 없음',
  (select bool_and(k in ('id', 'nickname', 'role', 'level', 'main_title', 'is_guest', 'created_at'))
     from jsonb_array_elements(admin_search_members('러')) r, jsonb_object_keys(r) k));
reset role;

-- ===== 4. 회원 정보 =====
-- 유저의 활동: 제안 2, 글 2(하나는 삭제), 댓글 1(게시판) + 문서 댓글 1, 빌드는 제안 승인으로 1
set role authenticated;
set request.jwt.claim.sub = :'U';
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Garen', auth.uid(), :'doc', t.build()) returning id as p1 \gset
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Teemo', auth.uid(), :'doc', t.build()) returning id as p2 \gset
reset role;
insert into posts (author_id, title, body) values (:'U', '글1', '본문'), (:'U', '글2', '본문');
update posts set deleted_at = now(), delete_kind = 'author', deleted_by = :'U' where title = '글2';
insert into post_comments (post_id, author_id, body) values ((select id from posts where title = '글1'), :'U', '댓글');
insert into doc_comments (counter_id, author_id, body) values ((select id from counters where counter_champion = 'Quinn'), :'U', '문서 댓글');
set role authenticated;
set request.jwt.claim.sub = :'OP';
select admin_member_info(:'U') as mi \gset
reset role;
select t.ok('기본 정보', (:'mi'::jsonb ->> 'nickname') = '유저_하나' and (:'mi'::jsonb ->> 'role') = 'user'
  and (:'mi'::jsonb ->> 'level')::int = 1 and (:'mi'::jsonb ->> 'is_guest')::boolean = false);
select t.ok('가입일', (:'mi'::jsonb ->> 'created_at')::timestamptz = (select created_at from profiles where id = :'U'));
select t.ok('가입 방식: 구글·카카오 (이름만)', (:'mi'::jsonb -> 'providers') = '["google", "kakao"]'::jsonb);
select t.ok('칭호: 얻은 칭호(글·제안으로 자동 지급된 것)', jsonb_array_length(:'mi'::jsonb -> 'titles') >= 1
  and (:'mi'::jsonb -> 'titles') = (select jsonb_agg(title_key order by title_key) from user_titles where user_id = :'U'));
select t.ok('활동 수: 제안 2·글 1(삭제 제외)·빌드 0·댓글 2', (:'mi'::jsonb ->> 'proposals')::int = 2 and (:'mi'::jsonb ->> 'posts')::int = 1
  and (:'mi'::jsonb ->> 'builds')::int = 0 and (:'mi'::jsonb ->> 'comments')::int = 2);
select t.ok('응답에 이메일·로그인 ID가 없음', :'mi' not like '%secret-u@x.com%' and :'mi' not like '%SECRET%' and :'mi' not like '%@%');
select t.ok('응답 칸은 정해진 것뿐', (select bool_and(k in ('id', 'nickname', 'role', 'level', 'main_title', 'is_guest', 'created_at',
  'providers', 'titles', 'proposals', 'posts', 'builds', 'comments', 'deleted_posts', 'deleted_comments')) from jsonb_object_keys(:'mi'::jsonb) k));
select t.ok('지운 글 1·지운 댓글 0 (040)', (:'mi'::jsonb ->> 'deleted_posts')::int = 1 and (:'mi'::jsonb ->> 'deleted_comments')::int = 0);
set role authenticated;
set request.jwt.claim.sub = :'OP';
select t.ok('비회원 정보: 가입 방식 없음, 비회원 표시', (admin_member_info(:'GU') ->> 'is_guest')::boolean and admin_member_info(:'GU') -> 'providers' = '[]'::jsonb);
select t.fails('없는 회원', format('select admin_member_info(%L)', gen_random_uuid()), '회원을 찾지 못했습니다');
-- 운영자 모드를 끄면 일반 회원과 같다
select set_operator_mode(false);
select t.fails('모드 끔: 통계 불가', 'select admin_member_stats()', '운영자만');
select t.fails('모드 끔: 검색 불가', $$select admin_search_members('유저')$$, '운영자만');
select t.fails('모드 끔: 회원 정보 불가', format('select admin_member_info(%L)', :'U'), '운영자만');
select set_operator_mode(true);
select t.ok('모드 켜면 다시 가능', jsonb_array_length(admin_search_members('유저')) = 1);
reset role;

-- ===== 5. 감독관의 재검토 요청 =====
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Vayne', :'MOD', :'doc', t.build()) returning id as p_self \gset
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Ornn', :'OP', :'doc', t.build()) returning id as p_op \gset
insert into edit_proposals (type, counter_id, target_champion, counter_champion, proposer_id, content)
values ('doc_edit', (select id from counters where counter_champion = 'Quinn'), 'Darius', 'Quinn', :'U', :'doc') returning id as p_doc \gset
select count(*) as logs_before from moderation_log \gset
set role authenticated;
set request.jwt.claim.sub = :'MOD';
select t.fails('본인 제안은 재검토 요청 불가', format('select request_proposal_revision(%s, %L, t.pv(%s))', :p_self, '메모', :p_self), '처리할 수 없는 제안');
select t.fails('운영진 제안은 불가', format('select request_proposal_revision(%s, %L, t.pv(%s))', :p_op, '메모', :p_op), '처리할 수 없는 제안');
select t.fails('문서 수정 제안은 불가', format('select request_proposal_revision(%s, %L, t.pv(%s))', :p_doc, '메모', :p_doc), '처리할 수 없는 제안');
select t.fails('메모 필수', format('select request_proposal_revision(%s, %L, t.pv(%s))', :p1, ' ', :p1), '재검토 요청 메모');
select t.fails('제안자가 방금 고친 버전과 다르면 불가', format('select request_proposal_revision(%s, %L, 999)', :p1, '메모'), '제안자가 방금 고쳤습니다');
select request_proposal_revision(:p1, '9레벨을 고쳐 주세요', t.pv(:p1));
select t.fails('이미 재검토를 요청한 제안', format('select request_proposal_revision(%s, %L, t.pv(%s))', :p1, '또', :p1), '이미 다른 분이 처리했습니다');
select t.fails('요청 취소는 운영자만', format('select cancel_proposal_revision(%s, %L)', :p1, '취소'), '운영자만');
reset role;
select t.ok('상태: 재검토 요청됨, 메모 저장', (select status = 'revision_requested' and revision_note = '9레벨을 고쳐 주세요' from edit_proposals where id = :p1));
select t.ok('처리자는 제안 칸에 남지 않음 (기록에만)', (select revision_requested_by is null and revision_requested_at is not null from edit_proposals where id = :p1));
select t.ok('처리 기록: 감독관, request_revision, 메모', exists (select 1 from moderation_log
  where action = 'request_revision' and target_kind = 'proposal' and target_id = :p1::text and actor_id = :'MOD' and actor_role = 'moderator' and note = '9레벨을 고쳐 주세요'));
select t.ok('제안자 알림 (종류·문장 그대로)', exists (select 1 from notifications where user_id = :'U' and kind = 'revision_request' and proposal_id = :p1 and message = '9레벨을 고쳐 주세요'));
select t.ok('처리 기록은 이 한 줄만 늘어남', (select count(*) from moderation_log) = :logs_before + 1);
set role authenticated;
set request.jwt.claim.sub = :'MOD';
select t.ok('감독관은 재검토 중인 제안을 읽지 못함', not exists (select 1 from edit_proposals where id = :p1));
select t.fails('재검토 중인 제안은 반려도 불가 (감독관 범위 밖)', format('select reject_proposal(%s, %L, t.pv(%s))', :p1, '거절', :p1), '이미 다른 분이 처리했습니다');
reset role;

-- 제안자가 고쳐서 다시 내면 대기로 돌아오고, 감독관이 반려 (기존 동작)
select t.ok('검토 잠금: 재검토 요청하면 표시가 지워짐 (트리거)', not exists (select 1 from proposal_reviewing where proposal_id = :p1));
set role authenticated;
set request.jwt.claim.sub = :'MOD';
select start_proposal_review(:p2);
reset role;
select t.ok('검토 잠금: 감독관 표시가 남음', exists (select 1 from proposal_reviewing where proposal_id = :p2 and user_id = :'MOD'));
set role authenticated;
set request.jwt.claim.sub = :'MOD';
select request_proposal_revision(:p2, '출처를 적어 주세요', t.pv(:p2));
reset role;
select t.ok('검토 잠금: 감독관 본인의 재검토 요청 뒤에도 표시가 지워짐', not exists (select 1 from proposal_reviewing where proposal_id = :p2));

-- 운영자: 재검토 요청은 그대로 되고 처리자가 남는다, 재검토 취소도 그대로
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Kayle', :'U', :'doc', t.build()) returning id as p3 \gset
set role authenticated;
set request.jwt.claim.sub = :'OP';
select request_proposal_revision(:p3, '운영자 요청', t.pv(:p3));
select cancel_proposal_revision(:p2, '감독관 요청을 운영자가 취소');
reset role;
select t.ok('운영자: 처리자가 그대로 남음', (select revision_requested_by = :'OP' from edit_proposals where id = :p3));
select t.ok('운영자: 처리 기록도 남음', exists (select 1 from moderation_log where action = 'request_revision' and target_id = :p3::text and actor_id = :'OP'));
select t.ok('운영자가 감독관의 요청을 취소하면 대기로 복귀', (select status = 'pending' and revision_requested_by is null from edit_proposals where id = :p2));

-- 기존 감독관 동작 그대로: 승인·반려
set role authenticated;
set request.jwt.claim.sub = :'MOD';
select reject_proposal(:p2, '근거 부족', t.pv(:p2));
reset role;
select t.ok('감독관 반려: 상태·제안자 알림·처리 기록 그대로', (select status = 'rejected' and reviewed_by is null from edit_proposals where id = :p2)
  and exists (select 1 from notifications where user_id = :'U' and kind = 'proposal_rejected' and proposal_id = :p2)
  and exists (select 1 from moderation_log where action = 'reject_proposal' and target_id = :p2::text and actor_id = :'MOD'));

-- 일반 회원은 여전히 못 함
set role authenticated;
set request.jwt.claim.sub = :'G';
select t.fails('일반 회원: 재검토 요청 불가', format('select request_proposal_revision(%s, %L, t.pv(%s))', :p3, '메모', :p3), '운영자만');
reset role;
set role anon;
select t.fails('비로그인: 재검토 요청 불가', format('select request_proposal_revision(%s, %L, 1)', :p3, '메모'), 'permission denied');
reset role;
