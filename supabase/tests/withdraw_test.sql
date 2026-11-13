-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 055: 회원 탈퇴 정리 - 장인 + 팔로워 + 링크 + 한정판 칭호 + 대표 칭호 + 추천을 함께 가진 회원의 탈퇴를 처음부터 끝까지.
--      공통 안쪽 함수(탈퇴 버튼/카카오 연결 끊기/비회원 정리/대시보드 삭제), 장인 신청 기록과 처리 기록 익명화,
--      추천/비추천 익명 보관(수 유지, 남의 칭호/알림 그대로), 탈퇴 장인 닉네임 30일 예약(비슷한 닉네임 포함), influencer_daily 정리, 권한
\set ON_ERROR_STOP 1
\set QUIET 1
\set OP '00000000-0000-0000-0000-00000000000a'
\set W  '00000000-0000-0000-0000-0000000000a1'
\set B  '00000000-0000-0000-0000-0000000000a2'
\set V  '00000000-0000-0000-0000-0000000000a3'
\set C  '00000000-0000-0000-0000-0000000000a4'
\set X  '00000000-0000-0000-0000-0000000000a5'
\set N  '00000000-0000-0000-0000-0000000000a6'
\set K  '00000000-0000-0000-0000-0000000000a7'
\set D  '00000000-0000-0000-0000-0000000000a8'
\set G  '00000000-0000-0000-0000-0000000000a9'
insert into auth.users (id, email) values
  (:'OP', 'op@x.com'), (:'W', 'w@x.com'), (:'B', 'b@x.com'), (:'V', 'v@x.com'), (:'C', 'c@x.com'),
  (:'X', 'x@x.com'), (:'N', 'n@x.com'), (:'K', 'k@x.com'), (:'D', 'd@x.com');
insert into auth.users (id, is_anonymous) values (:'G', true);
insert into auth.identities (user_id, provider, provider_id) values (:'K', 'kakao', '7007'), (:'W', 'google', 'g-w');
update public.profiles set nickname = '영자', role = 'admin' where id = :'OP';
update public.profiles set nickname = '옛장인' where id = :'W';
update public.profiles set nickname = '작성자' where id = :'B';
update public.profiles set nickname = '보통' where id = :'V';
update public.profiles set nickname = '셋째' where id = :'C';
update public.profiles set nickname = '다른장인', influencer = 'creator', influencer_at = now() where id = :'X';
update public.profiles set nickname = '일반회원' where id = :'N';
update public.profiles set nickname = '카카오장인', influencer = 'pro', influencer_at = now() where id = :'K';
update public.profiles set nickname = '대시보드장인', influencer = 'pro', influencer_at = now() where id = :'D';
update public.profiles set nickname = '손님' where id = :'G';

create function pg_temp.as_user(u uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', u::text, false); $$;
grant execute on all functions in schema pg_temp to anon, authenticated;
create temp table ids (name text primary key, id bigint);
grant all on ids to anon, authenticated;

-- ===== 0. 준비: W(장인님) - 운영자가 닉네임을 바꾼 기록, 신청 기록, 링크 2개, 팔로워 2명, 팔로우 1, 한정판 대표 칭호, 추천 =====
-- 운영자가 W의 닉네임을 바꿈 (처리 기록: rename_member, 메모에 "옛장인 -> 장인님")
set role authenticated;
select pg_temp.as_user(:'OP');
select admin_set_nickname(:'W', '장인님', '옛장인 사칭 신고로 바꿈');
select admin_set_nickname(:'V', '보통이', '대조용 다른 회원');
reset role;
update public.profiles set influencer = 'pro', influencer_at = now() where id = :'W';
insert into influencer_applications (user_id, kind, nickname, old_nickname, channel_url, channel_key, status, expires_at, ended_at, review_note, reviewed_by)
values (:'W', 'pro', '장인님', '옛장인', 'https://youtube.com/@jangin', 'youtube.com/@jangin', 'approved', now(), now(), '채널 확인 장인님', :'OP');
insert into influencer_applications (user_id, kind, nickname, old_nickname, channel_url, channel_key, status, expires_at, ended_at, review_note, created_at)
values (:'W', 'creator', '예전희망', '옛장인', 'https://youtube.com/@old', 'youtube.com/@old', 'rejected', now(), now() - interval '10 days', '반려 메모 옛장인', now() - interval '20 days');
insert into ids select 'app_ok', max(id) from influencer_applications where user_id = :'W' and status = 'approved';
insert into ids select 'app_rej', max(id) from influencer_applications where user_id = :'W' and status = 'rejected';
insert into ext_links (owner_id, url, host) values (:'W', 'https://youtube.com/@jangin', 'youtube.com'), (:'W', 'https://chzzk.naver.com/jangin', 'chzzk.naver.com');
insert into ids select 'link1', id from ext_links where url = 'https://youtube.com/@jangin';
insert into ids select 'link2', id from ext_links where url = 'https://chzzk.naver.com/jangin';
insert into link_reports (link_id, reporter_id, reason) select id, :'V', 'spam' from ids where name = 'link1';
-- 처리 기록: 운영자가 W 신청에 메모를 남긴 것처럼 (approve 기록), 다른 회원(V) 대상 기록은 그대로여야 함
insert into moderation_log (actor_id, actor_nickname, actor_role, action, target_kind, target_id, target_nickname, note)
select :'OP', '영자', 'admin', 'approve_influencer', 'influencer_application', id::text, '장인님', '채널 확인' from ids where name = 'app_ok';
insert into title_catalog (key, name, how_to, kind, equippable, sort_order) values ('lim_w', '첫장인', '공모전', 'limited', true, 1100);
set role authenticated;
select pg_temp.as_user(:'OP');
select dismiss_link_reports((select id from ids where name = 'link1'), '문제 없음');
select remove_link((select id from ids where name = 'link2'), '장인님 링크 정리');
select grant_title(:'W', 'lim_w', '공모전 1등 장인님');
reset role;
update public.profiles set main_title = 'lim_w' where id = :'W';
-- 팔로우: V, C -> W / W -> X
set role authenticated;
select pg_temp.as_user(:'V'); select follow_influencer(:'W');
select pg_temp.as_user(:'C'); select follow_influencer(:'W');
select pg_temp.as_user(:'W'); select follow_influencer(:'X');
reset role;
-- 추천: B의 공개 빌드에 W, C가 추천 / B의 글에 W가 추천. 장군 칭호 기준을 1로 낮춰 B가 장군을 받게
update xp_rules set value = 1 where key = 'title_general';
update builds set author_id = :'B' where id = (select min(id) from builds);
insert into ids select 'build', min(id) from builds;
set role authenticated;
select pg_temp.as_user(:'B');
select create_post('B의 글', '본문');
reset role;
insert into ids select 'post', max(id) from posts where author_id = :'B';
set role authenticated;
select pg_temp.as_user(:'W'); select vote_build((select id from ids where name = 'build'), 1::smallint);
select pg_temp.as_user(:'C'); select vote_build((select id from ids where name = 'build'), 1::smallint);
select pg_temp.as_user(:'W'); select vote_post((select id from ids where name = 'post'));
reset role;

select t.ok('준비: W는 장인, 대표 칭호 lim_w, 팔로워 2, 팔로우 1, 링크 1(하나는 운영자가 지움)',
  (select influencer = 'pro' and main_title = 'lim_w' from profiles where id = :'W')
  and (select count(*) = 2 from influencer_follows where influencer_id = :'W')
  and (select count(*) = 1 from influencer_follows where follower_id = :'W')
  and (select count(*) = 1 from ext_links where owner_id = :'W'));
select t.ok('준비: 빌드 추천 2, 글 추천 1, B는 장군 칭호',
  (select up_count = 2 from builds where id = (select id from ids where name = 'build'))
  and (select up_count = 1 from posts where id = (select id from ids where name = 'post'))
  and exists (select 1 from user_titles where user_id = :'B' and title_key = 'general'));
select t.ok('준비: W가 대상인 처리 기록 5줄 (닉네임 바꾸기, 신청 승인, 링크 신고 기각, 링크 삭제, 칭호 지급)',
  (select count(*) = 5 from moderation_log where target_nickname = '장인님'));

create temp table b_notes as select count(*) as n from notifications where user_id = :'B';
create temp table b_titles as select title_key from user_titles where user_id = :'B';
create temp table x_followers as select count(*) as n from influencer_follows where influencer_id = :'X';

-- ===== 1. 권한 =====
set role authenticated;
select pg_temp.as_user(:'V');
select t.fails('예약 표 직접 읽기 불가', 'select * from nickname_holds', 'permission denied');
select t.fails('예약 표 직접 쓰기 불가', $$insert into nickname_holds (nickname_key, hold_until) values ('x', now())$$, 'permission denied');
select t.fails('공통 안쪽 함수 직접 못 부름', format('select withdraw_account_unchecked(%L)', :'V'), 'permission denied');
select t.fails('정리 함수 직접 못 부름', format('select withdraw_cleanup(%L)', :'V'), 'permission denied');
select t.fails('메모 지우기 함수 직접 못 부름', $$select moderation_note_scrub('user', 'x', 'x', 'x', '{}')$$, 'permission denied');
select pg_temp.as_user(:'OP');
select t.fails('운영자는 탈퇴 못 함', $$select delete_my_account('영자')$$, '운영자 계정은 탈퇴할 수 없습니다');
reset role;
set role anon;
select t.fails('비로그인: 예약 표 읽기 불가', 'select * from nickname_holds', 'permission denied');
reset role;
select t.ok('예약 표 RLS 켬, 정책 없음', (select relrowsecurity from pg_class where oid = 'public.nickname_holds'::regclass)
  and not exists (select 1 from pg_policies where tablename = 'nickname_holds'));
select t.fails('공통 안쪽 함수도 운영자는 거부', format('select withdraw_account_unchecked(%L)', :'OP'), '운영자 계정은 탈퇴할 수 없습니다');

-- ===== 2. W 탈퇴 (탈퇴 버튼 경로) =====
set role authenticated;
select pg_temp.as_user(:'W');
select t.fails('확인 문구가 다르면 거부', $$select delete_my_account('옛장인')$$, '내 닉네임을 그대로');
select t.ok('탈퇴: 카카오 없으면 null', delete_my_account('장인님') is null);
reset role;

select t.ok('계정/프로필 지워짐', not exists (select 1 from auth.users where id = :'W') and not exists (select 1 from profiles where id = :'W'));
-- 2-1. 장인 관련은 지워짐
select t.ok('링크/링크 신고 지워짐', not exists (select 1 from ext_links where owner_id = :'W')
  and not exists (select 1 from link_reports where link_id in (select id from ids where name like 'link%')));
select t.ok('W의 팔로워/W가 한 팔로우 지워짐, X의 팔로워 1 줄어듦',
  not exists (select 1 from influencer_follows where :'W' in (influencer_id, follower_id))
  and (select count(*) from influencer_follows where influencer_id = :'X') = (select n - 1 from x_followers));
select t.ok('칭호(한정판 포함) 지워짐', not exists (select 1 from user_titles where user_id = :'W'));
-- 2-2. 장인 신청 기록: 식별 정보 지우고 상태/유형/시각만
select t.ok('승인 신청: user_id 비움, 상태 withdrawn, 식별 칸 모두 비움',
  (select user_id is null and status = 'withdrawn' and kind = 'pro' and ended_at is not null and created_at is not null
          and nickname is null and old_nickname is null and nickname_reverted is null and channel_url is null and channel_key is null
          and opgg_url is null and official_email is null and riot_id is null and riot_key is null
          and review_note is null and revoke_note is null and reviewed_by is null
     from influencer_applications where id = (select id from ids where name = 'app_ok')));
select t.ok('반려 신청: 상태 rejected 그대로, 식별 칸 비움, 끝난 시각 그대로(1년 정리 기준)',
  (select user_id is null and status = 'rejected' and kind = 'creator' and nickname is null and channel_url is null and review_note is null
          and ended_at < now() - interval '9 days'
     from influencer_applications where id = (select id from ids where name = 'app_rej')));
update influencer_applications set nickname = '되살림', channel_url = 'https://a.com/x' where id = (select id from ids where name = 'app_rej');
select t.ok('user_id가 빈 줄에 식별 칸을 다시 넣어도 트리거가 비움',
  (select nickname is null and channel_url is null from influencer_applications where id = (select id from ids where name = 'app_rej')));
select t.fails('표 제약: user_id가 빈 줄을 식별 칸과 함께 넣을 수 없음',
  $q$insert into influencer_applications (user_id, kind, nickname, status, expires_at, ended_at, channel_url, channel_key)
     values (null, 'creator', '누군가', 'withdrawn', now(), now(), 'https://a.com/b', 'a.com/b')$q$,
  'influencer_applications_fields');
select t.fails('표 제약: 회원 신청은 닉네임이 있어야 함',
  format($q$insert into influencer_applications (user_id, kind, nickname, status, expires_at, ended_at, channel_url, channel_key)
            values (%L, 'creator', null, 'rejected', now(), now(), 'https://a.com/b', 'a.com/b')$q$, :'V'),
  'influencer_applications_nickname_kept');
-- 2-3. 처리 기록: 대상 비우고 "탈퇴한 이용자", 메모의 닉네임/링크 주소 지움, 처리한 사람은 그대로
select t.ok('W가 대상인 처리 기록 5줄 모두 익명 (target_id 비움, 처리한 사람/종류 그대로)',
  (select count(*) = 5 from moderation_log where target_nickname = '탈퇴한 이용자' and target_id is null
     and actor_nickname = '영자' and actor_id = :'OP')
  and not exists (select 1 from moderation_log where target_nickname in ('장인님', '옛장인')));
select t.ok('닉네임 바꾸기 메모: "옛 -> 새" 지우고 사유만, 사유 안의 옛 닉네임도 지움',
  (select note = '탈퇴한 이용자 사칭 신고로 바꿈' from moderation_log where action = 'rename_member' and target_nickname = '탈퇴한 이용자'));
select t.ok('링크 처리 메모: 링크 주소와 닉네임 지움',
  (select note = '문제 없음' from moderation_log where action = 'dismiss_reports' and target_kind = 'link')
  and (select note = '탈퇴한 이용자 링크 정리' from moderation_log where action = 'remove_link'));
select t.ok('칭호 지급 메모: 칭호 이름은 남고 닉네임만 지움',
  (select note = E'첫장인 \u00B7 공모전 1등 탈퇴한 이용자' from moderation_log where action = 'grant_title' and target_nickname = '탈퇴한 이용자'));
select t.ok('신청 승인 기록도 익명', (select note = '채널 확인' and target_id is null from moderation_log where action = 'approve_influencer'));
select t.ok('다른 회원(V)이 대상인 기록은 그대로',
  (select target_id = :'V' and target_nickname = '보통이' and note like E'보통 \u2192 보통이%' from moderation_log where action = 'rename_member' and target_id = :'V'));
-- 2-4. 추천/비추천: 익명으로 남고 수 유지, B의 칭호/알림 그대로
select t.ok('빌드 추천 수 2 그대로, W의 표는 user_id만 비움',
  (select up_count = 2 from builds where id = (select id from ids where name = 'build'))
  and (select count(*) = 1 from build_votes where build_id = (select id from ids where name = 'build') and user_id is null and value = 1));
select t.ok('글 추천 수 1 그대로, W의 추천은 user_id만 비움',
  (select up_count = 1 from posts where id = (select id from ids where name = 'post'))
  and (select count(*) = 1 from post_votes where post_id = (select id from ids where name = 'post') and user_id is null));
select t.ok('B의 칭호(장군 포함) 그대로, B에게 새 알림 없음',
  not exists (select title_key from b_titles except select title_key from user_titles where user_id = :'B')
  and (select count(*) from notifications where user_id = :'B') = (select n from b_notes));
select t.ok('추천 기록(build_vote_log)은 누른 사람만 비움', exists (select 1 from build_vote_log where voter_id is null and new_value = 1));
-- 2-5. 남은 회원의 추천은 그대로 동작
set role authenticated;
select pg_temp.as_user(:'C');
select t.ok('C 추천 취소 -> 1 (익명 표는 남음)', (vote_build((select id from ids where name = 'build'), null) ->> 'up')::int = 1);
select t.ok('C 다시 추천 -> 2', (vote_build((select id from ids where name = 'build'), 1::smallint) ->> 'up')::int = 2);
select t.ok('C는 내 표만 읽음 (익명 표 안 보임)', (select count(*) = 1 from build_votes) and (select bool_and(user_id = :'C') from build_votes));
select pg_temp.as_user(:'V');
select t.ok('V 글 추천 -> 2 (익명 추천 포함해 다시 셈)', (vote_post((select id from ids where name = 'post')) ->> 'up')::int = 2);
select t.ok('V 추천 취소 -> 1', (vote_post((select id from ids where name = 'post')) ->> 'up')::int = 1);
select t.ok('V는 내 글 추천만 읽음', not exists (select 1 from post_votes));
select pg_temp.as_user(:'OP');
select t.ok('운영자는 익명 표도 읽음', exists (select 1 from build_votes where user_id is null));
reset role;
select t.ok('B의 칭호/알림은 끝까지 그대로',
  not exists (select title_key from b_titles except select title_key from user_titles where user_id = :'B')
  and (select count(*) from notifications where user_id = :'B') = (select n from b_notes));

-- ===== 3. 탈퇴한 장인의 닉네임 30일 예약 =====
select t.ok('예약: 장인님 키 1줄, 약 30일 (원문 닉네임은 보관 안 함)',
  (select count(*) = 1 from nickname_holds where nickname_key = nickname_key('장인님')
     and hold_until between now() + interval '29 days' and now() + interval '31 days')
  and not exists (select 1 from nickname_holds where nickname_key = '장인님' and nickname_key <> nickname_key('장인님')));
set role authenticated;
select pg_temp.as_user(:'V');
select t.fails('다른 회원이 같은 닉네임 못 씀', $$update profiles set nickname = '장인님' where id = auth.uid()$$, '최근 탈퇴한 장인의 닉네임');
select t.fails('비슷한 닉네임(공백)도 못 씀', $$update profiles set nickname = '장 인님' where id = auth.uid()$$, '최근 탈퇴한 장인의 닉네임');
select pg_temp.as_user(:'C');
select t.fails('장인 신청 희망 닉네임으로도 못 씀',
  $$select apply_influencer('creator', '장인님', 'https://youtube.com/@cc', 'c@x.com')$$, '최근 탈퇴한 장인의 닉네임');
select t.ok('막힌 신청은 남지 않음', not exists (select 1 from influencer_applications where channel_url = 'https://youtube.com/@cc'));
select pg_temp.as_user(:'OP');
select t.fails('운영자의 닉네임 바꾸기로도 못 씀', format('select admin_set_nickname(%L, %L, %L)', :'V', '장인님', 'x'), '최근 탈퇴한 장인의 닉네임');
reset role;
select t.ok('임시 닉네임은 예약과 겹치지 않음', influencer_temp_nickname() like '탑신병자#%');

-- 일반 회원 탈퇴는 예약 안 함
set role authenticated;
select pg_temp.as_user(:'N');
select delete_my_account('일반회원');
reset role;
select t.ok('일반 회원 탈퇴: 예약 없음', not exists (select 1 from nickname_holds where nickname_key = nickname_key('일반회원')));
set role authenticated;
select pg_temp.as_user(:'C');
update profiles set nickname = '일반회원' where id = auth.uid();
reset role;
select t.ok('일반 회원 닉네임은 바로 쓸 수 있음', (select nickname = '일반회원' from profiles where id = :'C'));

-- ===== 4. 다른 탈퇴 경로도 같은 정리 =====
-- 카카오 연결 끊기 (카카오만 연결된 장인)
insert into moderation_log (actor_id, actor_nickname, actor_role, action, target_kind, target_id, target_nickname, note)
values (:'OP', '영자', 'admin', 'grant_influencer', 'user', :'K', '카카오장인', E'프로게이머 \u00B7 카카오장인 지정');
select t.ok('카카오만 연결 -> deleted', kakao_unlinked('7007') = 'deleted');
select t.ok('카카오 경로: 예약 + 처리 기록 익명', exists (select 1 from nickname_holds where nickname_key = nickname_key('카카오장인'))
  and (select target_id is null and target_nickname = '탈퇴한 이용자' and note = E'프로게이머 \u00B7 탈퇴한 이용자 지정'
         from moderation_log where action = 'grant_influencer'));
-- 대시보드에서 직접 지움 (auth.users 삭제)
delete from auth.users where id = :'D';
select t.ok('대시보드 삭제: 예약도 됨', exists (select 1 from nickname_holds where nickname_key = nickname_key('대시보드장인')));
-- 오래 안 쓴 비회원 정리
insert into moderation_log (actor_id, actor_nickname, actor_role, action, target_kind, target_id, target_nickname, note)
values (:'OP', '영자', 'admin', 'rename_member', 'user', :'G', '새손님', E'손님 \u2192 새손님 \u00B7 부적절');
update profiles set last_seen_at = now() - interval '31 days' where id = :'G';
select t.ok('비회원 정리 1명', cleanup_guest_accounts() = 1);
select t.ok('비회원 정리: 처리 기록 익명, 비회원은 예약 없음',
  (select target_id is null and target_nickname = '탈퇴한 이용자' and note = '부적절' from moderation_log where note = '부적절')
  and not exists (select 1 from nickname_holds where nickname_key = nickname_key('손님')));

-- ===== 5. 메모 지우기: 형식을 모르는 닉네임 바꾸기 메모는 통째로 지움 =====
select t.ok('형식이 다른 rename 메모는 비움', moderation_note_scrub('user', 'rename_member', '알 수 없는 형식', '새이름', '{}') is null);
select t.ok('한 글자 닉네임은 메모에서 바꾸지 않음', moderation_note_scrub('user', 'grant_title', '가나다', 'x', '{가}') = '가나다');

-- ===== 6. 30일 뒤: influencer_daily가 예약을 지우고 닉네임을 다시 쓸 수 있음 =====
update nickname_holds set hold_until = now() - interval '1 minute' where nickname_key = nickname_key('장인님');
select t.ok('하루 작업: 기간 지난 예약 1줄 정리', (influencer_daily() ->> 'nickname_holds_purged')::int = 1);
select t.ok('남은 예약 2줄 (카카오장인, 대시보드장인)', (select count(*) = 2 from nickname_holds));
set role authenticated;
select pg_temp.as_user(:'B');
update profiles set nickname = '장인님' where id = auth.uid();
reset role;
select t.ok('예약이 끝나면 쓸 수 있음', (select nickname = '장인님' from profiles where id = :'B'));

-- ===== 7. 정의 확인 =====
select t.ok('추천 표: user_id 빈칸 허용 + on delete set null, 한 사람 한 표 유일 제약',
  (select bool_and(is_nullable = 'YES') from information_schema.columns where table_name in ('build_votes', 'post_votes') and column_name = 'user_id')
  and (select count(*) = 2 from pg_constraint where conname in ('build_votes_user_id_fkey', 'post_votes_user_id_fkey') and confdeltype = 'n')
  and (select count(*) = 2 from pg_constraint where conname in ('build_votes_once', 'post_votes_once') and contype = 'u'));
select t.ok('프로필 삭제 트리거가 게시판 정리보다 먼저(이름 순)',
  (select array_agg(tgname order by tgname) from pg_trigger where tgrelid = 'public.profiles'::regclass and not tgisinternal and tgtype & 8 = 8)
  = array['profiles_anonymize_on_delete', 'profiles_board_delete', 'profiles_delete_unpublished_builds']::name[]);
select t.ok('세 탈퇴 함수가 공통 안쪽 함수를 부름',
  (select count(*) = 3 from pg_proc where pronamespace = 'public'::regnamespace
     and proname in ('delete_my_account', 'kakao_unlinked', 'cleanup_guest_accounts') and prosrc like '%withdraw_account_unchecked%'
     and prosrc not like '%delete from auth.users%'));
