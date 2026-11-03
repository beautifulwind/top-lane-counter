-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 020: 비회원(익명 로그인) — 표시, 할 수 있는 것·없는 것, 정식 계정 전환, 기록 지우기, 오래 안 쓴 비회원 정리
\set ON_ERROR_STOP 1
\set QUIET 1
\set A '00000000-0000-0000-0000-00000000000a'
\set B '00000000-0000-0000-0000-00000000000b'
\set G '00000000-0000-0000-0000-0000000000a1'
\set H '00000000-0000-0000-0000-0000000000a2'
\set I '00000000-0000-0000-0000-0000000000a3'
\set J '00000000-0000-0000-0000-0000000000a4'
insert into auth.users (id, email) values (:'A', 'op@x.com'), (:'B', 'b@x.com');
insert into auth.users (id, is_anonymous) values (:'G', true), (:'H', true), (:'I', true), (:'J', true);
update public.profiles set nickname = '영자', role = 'admin' where id = :'A';
update public.profiles set nickname = '회원비' where id = :'B';
update public.profiles set nickname = '손님지' where id = :'G';
update public.xp_rules set value = 0 where key in ('post_interval', 'comment_interval');
create temp table ids (k text primary key, v bigint);
grant all on ids to authenticated;
insert into ids select 'quinn', id from counters where counter_champion = 'Quinn';
insert into ids select 'build', min(id) from builds where status = 'approved';

-- ===== 1. 표시 =====
select t.ok('가입할 때 비회원 표시', (select bool_and(is_guest) from profiles where id in (:'G', :'H', :'I', :'J')));
select t.ok('회원은 비회원 아님', (select not is_guest from profiles where id = :'B'));
set role anon;
set request.jwt.claim.sub = '';
select t.ok('비로그인도 비회원 표시를 읽음', (select is_guest from profiles where id = :'G'));
set role authenticated;
set request.jwt.claim.sub = :'G';
select t.fails('본인도 비회원 표시를 못 바꿈', $$update profiles set is_guest = false where id = auth.uid()$$, 'permission denied');

-- ===== 2. 할 수 있는 것: 글·댓글·문서 댓글·제안 =====
select public.create_post('비회원 글', '안녕하세요');
insert into ids select 'post', max(id) from posts;
select public.create_comment((select v from ids where k = 'post'), '비회원 댓글');
select public.create_doc_comment((select v from ids where k = 'quinn'), '비회원 문서 댓글');
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Garen', auth.uid(),
        '{"summary":"s","level_notes":{"1":"a","2":"b","3":"c","6":"d"},"lane_cautions":""}', t.build());
select t.ok('비회원도 글·댓글·문서 댓글·제안',
  exists (select 1 from posts where author_id = auth.uid()) and exists (select 1 from post_comments where author_id = auth.uid())
  and exists (select 1 from doc_comments where author_id = auth.uid()) and exists (select 1 from edit_proposals where proposer_id = auth.uid()));
select t.ok('비회원도 경험치가 쌓임', (select xp > 0 from profiles where id = auth.uid()));

-- ===== 3. 못 하는 것: 따봉/비추, 추천, 신고 =====
select t.fails('따봉 불가', format('select public.vote_build(%s, 1::smallint)', (select v from ids where k = 'build')), '비회원은 따봉·비추를 누를 수 없어요');
select t.fails('비추 불가', format('select public.vote_build(%s, (-1)::smallint)', (select v from ids where k = 'build')), '비회원은 따봉·비추를');
set request.jwt.claim.sub = :'B';
select public.create_post('회원 글', '본문');
insert into ids select 'bpost', max(id) from posts where author_id = auth.uid();
set request.jwt.claim.sub = :'G';
select t.fails('노가리방 추천 불가', format('select public.vote_post(%s)', (select v from ids where k = 'bpost')), '비회원은 추천할 수 없어요');
select t.fails('신고 불가', format($$select public.report_post(%s, 'spam')$$, (select v from ids where k = 'bpost')), '비회원은 신고할 수 없어요');

-- 회원은 비회원 글을 추천할 수 있다
set request.jwt.claim.sub = :'B';
select public.vote_post((select v from ids where k = 'post'));
select t.ok('회원은 비회원 글 추천 가능', (select up_count = 1 from posts where id = (select v from ids where k = 'post')));

-- ===== 4. 정식 계정 전환: 같은 계정 그대로 =====
reset role;
update auth.users set is_anonymous = false where id = :'G';
select t.ok('연결하면 비회원 표시가 꺼지고 기록·닉네임은 그대로',
  (select not is_guest and nickname = '손님지' and xp > 0 from profiles where id = :'G')
  and exists (select 1 from posts where author_id = :'G'));
set role authenticated;
set request.jwt.claim.sub = :'G';
select public.vote_post((select v from ids where k = 'bpost'));
select t.ok('전환한 뒤에는 추천 가능', (select up_count = 1 from posts where id = (select v from ids where k = 'bpost')));

-- ===== 5. 비회원 기록 지우기 (닉네임 없는 비회원은 "지우기") =====
set request.jwt.claim.sub = :'H';
select t.fails('확인 문구가 다르면 안 지움', $$select public.delete_my_account('탈퇴')$$, '확인 칸에 "지우기"를');
select public.delete_my_account('지우기');
reset role;
select t.ok('비회원 기록 지우기: 계정·프로필 없음', not exists (select 1 from auth.users where id = :'H') and not exists (select 1 from profiles where id = :'H'));

-- ===== 6. 오래 안 쓴 비회원 정리 =====
set role authenticated;
set request.jwt.claim.sub = :'J';
update profiles set nickname = '기록있음' where id = auth.uid();
select public.create_post('J 글', '본문');
reset role;
-- I: 기록 없음 31일 전 / J: 기록 있음 31일 전 / 회원 B·운영자 A: 아주 오래 전
update profiles set last_seen_at = now() - interval '31 days' where id in (:'I', :'J');
update profiles set last_seen_at = now() - interval '400 days' where id in (:'A', :'B');
select t.ok('정리: 기록 없는 비회원만 (30일)', public.cleanup_guest_accounts() = 1);
select t.ok('정리 뒤: I 없음, J·회원·운영자 그대로',
  not exists (select 1 from auth.users where id = :'I')
  and (select count(*) = 3 from auth.users where id in (:'J', :'A', :'B')));
update profiles set last_seen_at = now() - interval '91 days' where id = :'J';
select t.ok('정리: 기록 있는 비회원은 90일', public.cleanup_guest_accounts() = 1);
select t.ok('정리 뒤: J 없음', not exists (select 1 from auth.users where id = :'J'));
select t.ok('정리된 비회원 글은 탈퇴와 같은 규칙 (남의 댓글 없는 글은 삭제)', not exists (select 1 from posts where title = 'J 글'));
set role authenticated;
set request.jwt.claim.sub = :'B';
select t.fails('일반 유저는 정리 함수를 못 부름', 'select public.cleanup_guest_accounts()', 'permission denied');

-- ===== 7. 접속 시각 =====
reset role;
update profiles set last_seen_at = now() - interval '2 days' where id = :'B';
set role authenticated;
select public.touch_last_seen();
select t.ok('touch_last_seen: 지금으로', (select last_seen_at > now() - interval '1 minute' from profiles where id = :'B'));
