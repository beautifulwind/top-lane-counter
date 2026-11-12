-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 042: 회원 목록·회원 정보(운영자 전용) + 자유게시판 새 글 알림(운영자만, 본인 제외, 운영자 모드, 푸시 묶음)
\set ON_ERROR_STOP 1
\set QUIET 1
\set OP  '00000000-0000-0000-0000-00000000000a'
\set MOD '00000000-0000-0000-0000-00000000000b'
\set U   '00000000-0000-0000-0000-00000000000d'
\set V   '00000000-0000-0000-0000-00000000000c'
\set GU  '00000000-0000-0000-0000-000000000010'
\set GONE '00000000-0000-0000-0000-0000000000ee'
insert into auth.users (id, email) values (:'OP', 'op@x.com'), (:'MOD', 'm@x.com'), (:'U', 'secret-u@x.com'), (:'V', 'v@x.com');
insert into auth.users (id, email, is_anonymous) values (:'GU', null, true);
insert into auth.identities (user_id, provider, provider_id) values (:'U', 'google', 'SECRET-GOOGLE-ID'), (:'V', 'kakao', 'k-1');
update public.profiles set nickname = '영자', role = 'admin' where id = :'OP';
update public.profiles set nickname = '감독', role = 'moderator' where id = :'MOD';
update public.profiles set nickname = '유저_하나' where id = :'U';
update public.profiles set nickname = '브이' where id = :'V';
update public.profiles set nickname = '손님' where id = :'GU';
update public.profiles set created_at = now() - interval '5 days' where id = :'OP';
update public.profiles set created_at = now() - interval '4 days' where id = :'MOD';
update public.profiles set created_at = now() - interval '3 days' where id = :'U';
update public.profiles set created_at = now() - interval '2 days' where id = :'V';
update public.profiles set created_at = now() - interval '1 day' where id = :'GU';
create temp table ids (k text primary key, v bigint);
grant all on ids to authenticated, anon;

-- ===== 1. 권한: 운영자만 (감독관·일반 회원·비로그인 불가) =====
set role anon;
select t.fails('비로그인: 목록 불가', 'select admin_member_list()', 'permission denied');
select t.fails('비로그인: 정보 불가', format('select admin_member_detail(%L)', :'U'), 'permission denied');
reset role;
set role authenticated;
set request.jwt.claim.sub = :'U';
select t.fails('일반 회원: 목록 불가', 'select admin_member_list()', '운영자만');
select t.fails('일반 회원: 정보 불가', format('select admin_member_detail(%L)', :'V'), '운영자만');
select t.fails('일반 회원: 본인 정보도 이 함수로는 불가', format('select admin_member_detail(%L)', :'U'), '운영자만');
select t.fails('일반 회원: 감독관 지정 불가', format('select set_moderator(%L, true, %L)', :'V', '메모'), '운영자만');
set request.jwt.claim.sub = :'MOD';
select t.fails('감독관: 목록 불가', 'select admin_member_list()', '운영자만');
select t.fails('감독관: 정보 불가', format('select admin_member_detail(%L)', :'U'), '운영자만');
select t.fails('감독관: 지운 글·댓글 조회 불가', format('select admin_deleted_writings(%L)', :'U'), '운영자만');
select t.fails('감독관: 감독관 지정 불가', format('select set_moderator(%L, true, %L)', :'V', '메모'), '운영자만');
select t.fails('감독관: 감독관 해제 불가', format('select set_moderator(%L, false, %L)', :'MOD', '메모'), '운영자만');
select t.fails('감독관: 안쪽 함수(목록)를 직접 못 부름', $$select admin_member_list_unchecked(null, null, 1, 20)$$, 'permission denied');
select t.fails('감독관: 안쪽 함수(정보)를 직접 못 부름', format('select admin_member_detail_unchecked(%L, 30)', :'U'), 'permission denied');
reset role;

-- 운영자 모드를 끄면 운영자도 거부
set role authenticated;
set request.jwt.claim.sub = :'OP';
select set_operator_mode(false);
select t.fails('운영자 모드 끔: 목록 불가', 'select admin_member_list()', '운영자만');
select t.fails('운영자 모드 끔: 정보 불가', format('select admin_member_detail(%L)', :'U'), '운영자만');
select t.fails('운영자 모드 끔: 지운 글·댓글 조회 불가', format('select admin_deleted_writings(%L)', :'U'), '운영자만');
select set_operator_mode(true);
reset role;

-- ===== 2. 회원 목록 =====
set role authenticated;
set request.jwt.claim.sub = :'OP';
select admin_member_list() as l \gset
select t.ok('총 5명, 첫 쪽 크기 20', (:'l'::jsonb ->> 'total')::int = 5 and (:'l'::jsonb ->> 'size')::int = 20 and (:'l'::jsonb ->> 'page')::int = 1);
select t.ok('최근 가입 순 (손님 → 브이 → 유저 → 감독 → 영자)',
  (select array_agg(m ->> 'nickname' order by o) from jsonb_array_elements(:'l'::jsonb -> 'members') with ordinality x(m, o)) = array['손님', '브이', '유저_하나', '감독', '영자']);
select t.ok('손님도 나오고 is_guest로 구분', (select (m ->> 'is_guest')::boolean from jsonb_array_elements(:'l'::jsonb -> 'members') m where m ->> 'nickname' = '손님'));
select t.ok('목록에는 이메일·로그인 ID 같은 칸이 없음',
  (select bool_and(k in ('id', 'nickname', 'role', 'level', 'main_title', 'is_guest', 'created_at', 'influencer', 'nickname_state'))  -- 046: 장인 유형·닉네임 상태
     from jsonb_array_elements(:'l'::jsonb -> 'members') r, jsonb_object_keys(r) k));
select t.ok('목록 전체에 이메일·로그인 ID 글자가 없음', :'l' !~ '(secret-u@x|SECRET-GOOGLE-ID|k-1)');
select t.ok('닉네임 검색 (부분 일치·대소문자·공백 무시)', jsonb_array_length(admin_member_list('  유저  ') -> 'members') = 1);
select t.ok('_ 는 글자 그대로', (admin_member_list('_') ->> 'total')::int = 1);
select t.ok('% 는 글자 그대로', (admin_member_list('%') ->> 'total')::int = 0);
select t.ok('역할 거르기: 감독관 1명', (admin_member_list(null, 'moderator') ->> 'total')::int = 1
  and admin_member_list(null, 'moderator') -> 'members' -> 0 ->> 'nickname' = '감독');
select t.ok('검색 + 역할', (admin_member_list('유저', 'moderator') ->> 'total')::int = 0);
select t.ok('쪽 나누기: 크기 2, 둘째 쪽은 셋째·넷째', (select array_agg(m ->> 'nickname' order by o)
  from jsonb_array_elements(admin_member_list(null, null, 2, 2) -> 'members') with ordinality x(m, o)) = array['유저_하나', '감독']
  and (admin_member_list(null, null, 2, 2) ->> 'total')::int = 5);
select t.ok('쪽 크기는 50까지', (admin_member_list(null, null, 1, 999) ->> 'size')::int = 50);
select t.ok('끝을 넘은 쪽은 빈 목록', admin_member_list(null, null, 9, 20) -> 'members' = '[]'::jsonb);
select t.fails('21자 이상 검색어 불가', format('select admin_member_list(%L)', repeat('가', 21)), '20자까지');
select t.fails('모르는 역할 불가', $$select admin_member_list(null, 'owner')$$, '역할');
reset role;

-- ===== 3. 활동 만들기 =====
-- 유저: 글 3(하나는 운영진이 숨김, 하나는 지움), 댓글 2(게시판 1 + 지운 글 밑 1)
set role authenticated;
set request.jwt.claim.sub = :'U';
insert into ids select 'p1', create_post('유저의 첫 글', '본문 하나');
reset role; delete from board_last_write;
set role authenticated; set request.jwt.claim.sub = :'U';
insert into ids select 'p2', create_post('유저의 숨길 글', '본문 둘');
reset role; delete from board_last_write;
set role authenticated; set request.jwt.claim.sub = :'U';
insert into ids select 'p3', create_post('유저의 지울 글', '비밀 본문');
reset role;

-- ===== 4. 새 글 알림 (위 글쓰기에서 생김) =====
select t.ok('새 글마다 운영자에게 post_created 알림 1줄, 글 연결', (select count(*) from notifications
  where user_id = :'OP' and kind = 'post_created' and post_id in (select v from ids where k in ('p1', 'p2', 'p3'))) = 3);
select t.ok('알림 문장', (select message from notifications where user_id = :'OP' and kind = 'post_created' and post_id = (select v from ids where k = 'p1'))
  = '새 글이 올라왔습니다. 「유저의 첫 글」');
select t.ok('운영자 외에는 안 감 (감독관·글쓴이·다른 회원)', not exists (select 1 from notifications where kind = 'post_created' and user_id <> :'OP'));
select t.ok('푸시 묶음: 새 글 = 운영진 알림', push_group('post_created') = 'staff_new');

-- 글쓴이 본인(운영자) 제외, 댓글은 알림 없음
set role authenticated;
set request.jwt.claim.sub = :'OP';
insert into ids select 'pa', create_post('운영자 글', '본문');
reset role;
select t.ok('운영자가 쓴 글은 운영자에게 알림 없음', not exists (select 1 from notifications where kind = 'post_created' and post_id = (select v from ids where k = 'pa')));
set role authenticated;
set request.jwt.claim.sub = :'V';
select create_comment((select v from ids where k = 'p1'), '브이의 댓글') as vc \gset
reset role;
select t.ok('댓글은 post_created 알림을 만들지 않음', (select count(*) from notifications where kind = 'post_created') = 3);

-- 운영자 모드: 끄면 목록·개수에서 가려지고 [모두 읽음]도 건드리지 않고 푸시도 안 감
insert into push_subscriptions (user_id, endpoint, p256dh, auth) values (:'OP', 'https://push.example/op', 'k', 'a');
select t.ok('운영자 모드 켬: 푸시 대상', push_wanted(:'OP', 'post_created'));
select max(id) as mx from notifications \gset
set role authenticated;
set request.jwt.claim.sub = :'OP';
select t.ok('운영자 모드 켬: 새 글 알림이 보임', (select count(*) from notifications where kind = 'post_created') = 3);
select set_operator_mode(false);
select t.ok('운영자 모드 끔: 새 글 알림이 목록에서 빠짐', (select count(*) from notifications where kind = 'post_created') = 0);
select mark_all_notifications_read(:mx) is not null as marked \gset
select set_operator_mode(true);
reset role;
select t.ok('운영자 모드 끔: [모두 읽음]이 새 글 알림을 안 건드림', (select count(*) from notifications where kind = 'post_created' and read_at is null) = 3);
update profiles set operator_mode = false where id = :'OP';
select t.ok('운영자 모드 끔: 푸시 안 감', not push_wanted(:'OP', 'post_created'));
update profiles set operator_mode = true where id = :'OP';
-- 설정에서 운영진 알림을 끄면 푸시 안 감
insert into push_settings (user_id, staff_new) values (:'OP', false);
select t.ok('운영진 알림 설정을 끄면 푸시 안 감', not push_wanted(:'OP', 'post_created'));
delete from push_settings;
-- 푸시 내용: push_targets에 post_id
select t.ok('push_targets: post_id 포함, 옛 칸도 그대로',
  (select (r -> 'notification' ->> 'post_id')::bigint = (select v from ids where k = 'p1')
      and r -> 'notification' ? 'proposal_id' and r -> 'notification' ? 'build_id' and r -> 'notification' ? 'counter_id'
      and jsonb_array_length(r -> 'subscriptions') = 1
    from (select push_targets((select id from notifications where kind = 'post_created' and post_id = (select v from ids where k = 'p1'))) as r) x));
-- 글이 숨김 상태로 들어오면 알림 없음 (트리거 조건)
insert into posts (author_id, title, body, status) values (:'U', '숨김으로 들어옴', '본문', 'hidden');
select t.ok('숨김 상태로 들어온 글은 알림 없음', (select count(*) from notifications where kind = 'post_created') = 3);
delete from posts where title = '숨김으로 들어옴';

-- ===== 5. 숨김·지움·댓글·고친 빌드·처리 이력 =====
set role authenticated;
set request.jwt.claim.sub = :'MOD';
select hide_post((select v from ids where k = 'p2'), '광고');
reset role;
reset role;
delete from board_last_write;
set role authenticated;
set request.jwt.claim.sub = :'U';
select create_comment((select v from ids where k = 'p1'), '유저의 댓글') as uc \gset
reset role;
delete from board_last_write;
set role authenticated;
set request.jwt.claim.sub = :'U';
select create_comment((select v from ids where k = 'p3'), '지울 글 밑 댓글') as uc3 \gset
select delete_my_post((select v from ids where k = 'p3'));
reset role;
-- 고친 빌드: V가 U의 빌드를 고침 (기록 표를 직접 채움 — 빌드 수정 흐름은 wiki_builds_test가 검사)
insert into build_editors (build_id, user_id, edits) select b.id, :'U', 3 from builds b limit 1;
-- 처리 이력: 유저 글 숨김(위) + 감독관 지정·해제 기록
set role authenticated;
set request.jwt.claim.sub = :'OP';
select set_moderator(:'U', true, '잠깐 맡김');
select set_moderator(:'U', false, '끝');
reset role;
-- 탈퇴한 처리자: 기록은 남고 프로필은 없음
insert into moderation_log (actor_id, actor_nickname, actor_role, action, target_kind, target_id, note)
values (:'GONE', '옛감독관', 'moderator', 'hide', 'post', (select v::text from ids where k = 'p1'), '예전 처리');

set role authenticated;
set request.jwt.claim.sub = :'OP';
select admin_member_detail(:'U') as d \gset
reset role;
select t.ok('기본 정보: 닉네임·역할·가입일', :'d'::jsonb -> 'info' ->> 'nickname' = '유저_하나' and :'d'::jsonb -> 'info' ->> 'role' = 'user' and :'d'::jsonb -> 'info' ? 'created_at');
select t.ok('기본 정보: 경험치·레벨·상대법 수', (:'d'::jsonb -> 'info' ->> 'xp')::int = (select xp from profiles where id = :'U')
  and :'d'::jsonb -> 'info' ? 'level' and (:'d'::jsonb -> 'info' ->> 'matchups')::int = 0);
select t.ok('활동 수: 글 2(지운 것 뺌)·댓글 2·지운 글 1', (:'d'::jsonb -> 'info' ->> 'posts')::int = 2
  and (:'d'::jsonb -> 'info' ->> 'comments')::int = 2 and (:'d'::jsonb -> 'info' ->> 'deleted_posts')::int = 1);
select t.ok('쓴 글: 지운 글 빼고 숨긴 글은 상태와 함께', (select array_agg(p ->> 'title' order by p ->> 'title') from jsonb_array_elements(:'d'::jsonb -> 'posts') p)
  = array['유저의 숨길 글', '유저의 첫 글']
  and (select p ->> 'status' from jsonb_array_elements(:'d'::jsonb -> 'posts') p where p ->> 'title' = '유저의 숨길 글') = 'hidden');
select t.ok('쓴 글: 지운 글의 제목·내용이 어디에도 없음', :'d' !~ '(지울 글|비밀 본문|지울 글 밑 댓글)');
select t.ok('쓴 댓글: 지운 글 밑 댓글은 빠짐', (select count(*) from jsonb_array_elements(:'d'::jsonb -> 'comments')) = 1
  and :'d'::jsonb -> 'comments' -> 0 ->> 'excerpt' = '유저의 댓글' and :'d'::jsonb -> 'comments' -> 0 ->> 'kind' = 'post');
select t.ok('고친 빌드: 상대법 이름·고친 횟수', (select count(*) from jsonb_array_elements(:'d'::jsonb -> 'edited_builds')) = 1
  and :'d'::jsonb -> 'edited_builds' -> 0 ->> 'counter_champion' = 'Quinn' and (:'d'::jsonb -> 'edited_builds' -> 0 ->> 'edits')::int = 3);
select t.ok('처리 이력: 글 숨김 + 감독관 지정·해제', (select array_agg(m ->> 'action' order by m ->> 'action') from jsonb_array_elements(:'d'::jsonb -> 'moderation') m)
  = array['grant_moderator', 'hide', 'hide', 'revoke_moderator']);
select t.ok('처리 이력: 처리자가 탈퇴했으면 "탈퇴한 이용자", 옛 닉네임은 안 나감',
  (select (m ->> 'actor_nickname') = '탈퇴한 이용자' and (m ->> 'actor_withdrawn')::boolean from jsonb_array_elements(:'d'::jsonb -> 'moderation') m where m ->> 'note' = '예전 처리')
  and :'d' not like '%옛감독관%');
select t.ok('처리 이력: 탈퇴하지 않은 처리자는 닉네임 그대로', (select bool_and(not (m ->> 'actor_withdrawn')::boolean) from jsonb_array_elements(:'d'::jsonb -> 'moderation') m where m ->> 'note' <> '예전 처리'));
select t.ok('이메일·로그인 ID 글자가 없음', :'d' !~ '(secret-u@x|SECRET-GOOGLE-ID)');
select t.ok('정보에 지운 글 내용을 넣지 않음 (admin_deleted_writings로만)', not (:'d'::jsonb ? 'deleted'));

-- 개수 제한
set role authenticated;
set request.jwt.claim.sub = :'OP';
select t.ok('개수는 1~100으로 맞춤', jsonb_array_length(admin_member_detail(:'U', 1) -> 'posts') = 1
  and jsonb_array_length(admin_member_detail(:'U', 0) -> 'posts') = 1 and jsonb_array_length(admin_member_detail(:'U', 100000) -> 'posts') = 2);
select t.fails('없는 회원', format('select admin_member_detail(%L)', :'GONE'), '찾지 못했습니다');
-- 운영자는 지운 글·댓글을 admin_deleted_writings로 읽는다 (기존 기능)
select t.ok('운영자: 지운 글 내용 조회', (select (admin_deleted_writings(:'U') -> 'posts' -> 0 ->> 'body') = '비밀 본문'));
reset role;

-- ===== 6. 옛 알림·옛 화면 호환 =====
select t.ok('알림 종류 제약에 예전 종류가 모두 남음', (select count(*) from unnest(array['revision_request', 'proposal_submitted', 'build_submitted', 'inquiry_received',
  'matchup_created', 'build_created', 'post_deleted', 'comment_deleted', 'doc_comment_deleted', 'counter_restored', 'moderator_granted']) k
  where pg_get_constraintdef((select oid from pg_constraint where conname = 'notifications_kind_check')) like '%''' || k || '''%') = 11);
select t.ok('예전 푸시 묶음 그대로', push_group('build_created') = 'staff_new' and push_group('build_restored') = 'my_results' and push_group('level_up') is null);
