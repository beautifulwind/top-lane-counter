-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 017: 닉네임 변경(30일에 한 번) · 회원 탈퇴 · 카카오 연결 끊기 · DB 오류 문구(조사·"다시 보내기")
\set ON_ERROR_STOP 1
\set QUIET 1
\set A '00000000-0000-0000-0000-00000000000a'
\set B '00000000-0000-0000-0000-00000000000b'
\set C '00000000-0000-0000-0000-00000000000c'
\set D '00000000-0000-0000-0000-00000000000d'
\set E '00000000-0000-0000-0000-00000000000e'
insert into auth.users (id, email, raw_app_meta_data) values
  (:'A', 'op@x.com', '{"provider":"kakao","providers":["google","kakao"]}'),
  (:'B', 'b@x.com', '{"provider":"kakao","providers":["google","kakao"]}'),
  (:'C', 'c@x.com', '{"provider":"kakao","providers":["kakao"]}'),
  (:'D', 'd@x.com', '{"provider":"google","providers":["google"]}'),
  (:'E', 'e@x.com', '{"provider":"kakao","providers":["kakao"]}');
insert into auth.identities (user_id, provider, provider_id) values
  (:'A', 'google', 'g-a'), (:'A', 'kakao', '1001'),
  (:'B', 'google', 'g-b'), (:'B', 'kakao', '2002'),
  (:'C', 'kakao', '3003'),
  (:'D', 'google', 'g-d'),
  (:'E', 'kakao', '5005');
update public.profiles set nickname = '영자', role = 'admin' where id = :'A';
update public.profiles set nickname = '비' where id = :'B';
update public.profiles set nickname = '씨' where id = :'C';
update public.profiles set nickname = '디' where id = :'D';
update public.xp_rules set value = 0 where key in ('post_interval', 'comment_interval');

-- ===================================================================
-- 1. 닉네임 변경: 처음 정하기는 변경 아님, 그다음 30일에 한 번, 기록은 본인·운영자만
-- ===================================================================
select t.ok('처음 정한 닉네임은 변경 기록 없음', (select count(*) = 0 from nickname_changes));
set role authenticated;
set request.jwt.claim.sub = :'D';
update public.profiles set nickname = '디디' where id = auth.uid();
select t.ok('첫 변경은 바로 됨 + 기록', (select nickname = '디디' from profiles where id = auth.uid())
  and (select old_nickname = '디' and new_nickname = '디디' from nickname_changes where user_id = auth.uid()));
select t.fails('30일 안에 다시 바꾸기', $$update public.profiles set nickname = '디디디' where id = auth.uid()$$, '닉네임은 30일에 한 번 바꿀 수 있어요');
select t.fails('대소문자만 바꿔도 변경', $$update public.profiles set nickname = 'DD' where id = auth.uid()$$, '30일에 한 번');
update public.profiles set main_title = null where id = auth.uid();
select t.ok('닉네임 그대로면 다른 칸은 고칠 수 있음', true);
select t.fails('바꾼 시각은 직접 못 고침', $$update public.nickname_changes set changed_at = now() - interval '40 days'$$, 'permission denied');
set request.jwt.claim.sub = :'B';
select t.ok('남의 변경 기록은 안 보임', (select count(*) = 0 from nickname_changes));
reset role;
set request.jwt.claim.sub = '';
set role anon;
select t.fails('비로그인은 기록 못 봄', 'select * from public.nickname_changes', 'permission denied');
reset role;
set role authenticated;
set request.jwt.claim.sub = :'A';
select t.ok('운영자는 기록을 봄', (select count(*) = 1 from nickname_changes));
reset role;
update nickname_changes set changed_at = now() - interval '30 days 1 minute' where user_id = :'D';
set role authenticated;
set request.jwt.claim.sub = :'D';
select t.fails('겹치는 닉네임은 그대로 막힘', $$update public.profiles set nickname = '비' where id = auth.uid()$$, 'duplicate key');
update public.profiles set nickname = '디삼' where id = auth.uid();
select t.ok('30일이 지나면 다시 바꿀 수 있음', (select nickname = '디삼' from profiles where id = auth.uid())
  and (select count(*) = 2 from nickname_changes where user_id = auth.uid()));
reset role;
update public.xp_rules set value = 0 where key = 'nickname_change_days';
set role authenticated;
set request.jwt.claim.sub = :'D';
update public.profiles set nickname = '디사' where id = auth.uid();
select t.ok('간격은 xp_rules로 바꾼다 (0일 = 제한 없음)', (select nickname = '디사' from profiles where id = auth.uid()));
reset role;
update public.xp_rules set value = 30 where key = 'nickname_change_days';

-- ===================================================================
-- 2. 회원 탈퇴
-- ===================================================================
set role authenticated;
set request.jwt.claim.sub = :'B';
select public.create_post('비의 글', '본문') as bp \gset
reset role;
set request.jwt.claim.sub = '';
set role anon;
select t.fails('비로그인은 탈퇴 함수를 못 부름', $$select public.delete_my_account('x')$$, 'permission denied');
reset role;
set role authenticated;
set request.jwt.claim.sub = :'A';
select t.fails('운영자는 탈퇴 불가', $$select public.delete_my_account('영자')$$, '운영자 계정은 탈퇴할 수 없어요');
set request.jwt.claim.sub = :'B';
select t.fails('닉네임이 다르면 탈퇴 안 됨', $$select public.delete_my_account('비비')$$, '내 닉네임을 그대로');
select t.ok('탈퇴: 카카오 ID를 돌려줌', public.delete_my_account(' 비 ') = '2002');
reset role;
select t.ok('탈퇴: 계정·로그인 방식·프로필·글이 지워짐',
  not exists (select 1 from auth.users where id = :'B')
  and not exists (select 1 from auth.identities where user_id = :'B')
  and not exists (select 1 from profiles where id = :'B')
  and not exists (select 1 from posts where id = :bp));

-- 닉네임을 아직 안 정한 사람은 "탈퇴"로 확인, 카카오가 없으면 null
insert into auth.users (id, email) values ('00000000-0000-0000-0000-0000000000f1', 'new@x.com');
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000f1';
select t.fails('닉네임 없으면 "탈퇴"를 적어야', $$select public.delete_my_account('')$$, '"탈퇴"를 그대로');
select t.ok('닉네임 없는 계정 탈퇴, 카카오 없으면 null', public.delete_my_account('탈퇴') is null);
reset role;

-- ===================================================================
-- 3. 카카오 연결 끊기 알림 (service_role만)
-- ===================================================================
set role authenticated;
set request.jwt.claim.sub = :'C';
select t.fails('로그인한 사람도 못 부름', $$select public.kakao_unlinked('3003')$$, 'permission denied');
reset role;
set role service_role;
select t.ok('모르는 카카오 ID', public.kakao_unlinked('9999') = 'not_found');
select t.ok('카카오만 연결 → 탈퇴 처리', public.kakao_unlinked('3003') = 'deleted');
select t.ok('운영자 계정은 지우지 않음 (구글도 있으면 카카오만 뗌)', public.kakao_unlinked('1001') = 'unlinked');
reset role;
select t.ok('탈퇴 처리: 계정·프로필 없음', not exists (select 1 from auth.users where id = :'C') and not exists (select 1 from profiles where id = :'C'));
select t.ok('카카오만 떼기: 계정·구글은 남고 providers 정리',
  exists (select 1 from profiles where id = :'A' and nickname = '영자')
  and (select array_agg(provider) = '{google}' from auth.identities where user_id = :'A')
  and (select raw_app_meta_data = '{"provider":"google","providers":["google"]}'::jsonb from auth.users where id = :'A'));
set role service_role;
select t.ok('같은 알림이 다시 와도 괜찮음', public.kakao_unlinked('1001') = 'not_found');
reset role;
-- 카카오만 연결된 운영자 (흉내: E를 운영자로)
update public.profiles set role = 'user' where id = :'A';
update public.profiles set nickname = '이', role = 'admin' where id = :'E';
set role service_role;
select t.ok('카카오만 연결된 운영자는 지우지 않음', public.kakao_unlinked('5005') = 'operator_kept');
reset role;
select t.ok('운영자 그대로', exists (select 1 from auth.users where id = :'E'));

-- ===================================================================
-- 4. DB 오류 문구: 조사는 받침으로, "다시 제출" → "다시 보내기"
-- ===================================================================
select t.ok('josa', public.josa('핵심 아이템', '은/는') = '핵심 아이템은' and public.josa('소환사 주문', '을/를') = '소환사 주문을'
  and public.josa('스킬 순서', '을/를') = '스킬 순서를' and public.josa('케일', '으로/로') = '케일로'
  and public.josa('퀸', '으로/로') = '퀸으로' and public.josa('Q', '을/를') = 'Q을(를)');
select t.fails('빌드 개수 문구', $$select public.check_build_ids(array['1'], '핵심 아이템', 3, 6, true)$$, '핵심 아이템은 3~6개 골라 주세요');
select t.fails('빌드 칸 문구', $$select public.text_array('{}'::jsonb, '시작 아이템')$$, '시작 아이템을 골라 주세요');
select t.ok('함수 오류 문구에 "다시 제출"·조사 자리표시가 없음',
  not exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace
              and prosrc ~ 'raise exception ''[^'']*(다시 제출|을\(를\)|은\(는\))'));
select t.ok('보내기 문구로 바뀜', exists (select 1 from pg_proc where proname = 'resubmit_proposal' and prosrc like '%다시 보낼 수 있어요%'));

-- ===================================================================
-- 5. 019: 화면 이름 "내 활동" → "마이페이지"
-- ===================================================================
select t.ok('019: 함수 문구에 "내 활동"이 없음',
  not exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace and prosrc like '%내 활동%'));
select t.ok('019: 재검토·칭호 문구는 [마이페이지]',
  (select count(*) = 3 from pg_proc where pronamespace = 'public'::regnamespace
     and proname in ('check_new_proposal', 'check_new_build', 'sync_rewards') and prosrc like '%[마이페이지]%'));
