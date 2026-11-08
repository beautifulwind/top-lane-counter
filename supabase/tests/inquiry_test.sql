-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 032: 문의하기. 보내기(하루 3건·글자 수·비회원·닉네임 전), 읽기 범위(RLS), 답변·알림, 감독관 제한, 분류 옮기기, 지우기, 보관, 탈퇴
\set ON_ERROR_STOP 1
\set QUIET 1
\set OP  '00000000-0000-0000-0000-00000000000a'
\set MOD '00000000-0000-0000-0000-00000000000b'
\set U   '00000000-0000-0000-0000-00000000000d'
\set U2  '00000000-0000-0000-0000-00000000000e'
\set GUEST '00000000-0000-0000-0000-00000000000f'
\set NONICK '00000000-0000-0000-0000-000000000010'
insert into auth.users (id, email) values
  (:'OP', 'op@x.com'), (:'MOD', 'm@x.com'), (:'U', 'u@x.com'), (:'U2', 'u2@x.com'), (:'GUEST', 'g@x.com'), (:'NONICK', 'n@x.com');
update public.profiles set nickname = '영자', role = 'admin' where id = :'OP';
update public.profiles set nickname = '유저' where id = :'U';
update public.profiles set nickname = '유저둘' where id = :'U2';
update public.profiles set nickname = '비회원', is_guest = true where id = :'GUEST';
update public.profiles set nickname = '감독' where id = :'MOD';
update public.profiles set role = 'moderator' where id = :'MOD';

-- ===== 1. 보내기 =====
set role authenticated;
set request.jwt.claim.sub = '';
select t.fails('로그인 없이 보내기 불가', $$select create_inquiry('bug', '내용이 충분히 깁니다')$$, '로그인해 주세요');
set request.jwt.claim.sub = :'U';
select t.fails('분류 필수', $$select create_inquiry(null, '내용이 충분히 깁니다')$$, '분류를 골라');
select t.fails('모르는 분류', $$select create_inquiry('x', '내용이 충분히 깁니다')$$, '분류를 골라');
select t.fails('너무 짧음(공백 제외)', $$select create_inquiry('bug', '  짧음  ')$$, '5자 이상');
select t.fails('너무 김', format('select create_inquiry(%L, %L)', 'bug', repeat('가', 1001)), '1000자까지');
select t.fails('직접 insert 불가', $$insert into inquiries (user_id, category, body) values (auth.uid(), 'bug', 'hello world')$$, 'permission denied');
select t.fails('하루 개수 표는 직접 못 봄', $$select * from inquiry_quota$$, 'permission denied');
select create_inquiry('other', repeat('가', 1000)) as q_long \gset
select create_inquiry('bug', '  오류가 납니다 1  ') as q_bug \gset
select create_inquiry('account', '계정 문의입니다 계정') as q_acc \gset
select t.ok('앞뒤 공백은 지우고 저장', (select body = '오류가 납니다 1' from inquiries where id = :q_bug));
select t.fails('하루 4번째는 거부', $$select create_inquiry('idea', '네 번째 문의입니다')$$, '하루에 3건');
set request.jwt.claim.sub = :'U2';
select t.fails('남의 문의 지우기 불가', format('select delete_my_inquiry(%s)', :q_bug), '찾지 못했습니다');
select t.ok('일반 회원은 남의 문의를 못 봄', (select count(*) = 0 from inquiries));
set request.jwt.claim.sub = :'U';
select t.ok('본인 문의는 보임', (select count(*) = 3 from inquiries));
select delete_my_inquiry(:q_long);
select t.fails('보낸 문의를 지워도 4번째는 거부(개수는 따로 셈)', $$select create_inquiry('idea', '네 번째 문의입니다')$$, '하루에 3건');
reset role;
-- 다음 날이 되면 다시 보낼 수 있다
update inquiry_quota set day = day - 1 where user_id = :'U';
set role authenticated;
set request.jwt.claim.sub = :'U';
select t.ok('다음 날은 다시 보낼 수 있음', (select create_inquiry('idea', '다음 날 건의입니다') > 0));
reset role;
select t.ok('하루 개수는 한국 시간 날짜로 셈', (select day = (now() at time zone 'Asia/Seoul')::date and sent = 1 from inquiry_quota where user_id = :'U'));

-- 비회원·닉네임 전도 보낼 수 있다
set role authenticated;
set request.jwt.claim.sub = :'GUEST';
select t.ok('비회원도 보냄', (select create_inquiry('bug', '비회원이 보냅니다') > 0));
select t.ok('비회원은 자기 것만 봄', (select count(*) = 1 from inquiries));
reset role;
update public.profiles set nickname = null where id = :'NONICK';
set role authenticated;
set request.jwt.claim.sub = :'NONICK';
select t.ok('닉네임 전에도 보냄', (select create_inquiry('account', '닉네임 정하기 전 문의') > 0));
reset role;

-- ===== 2. 읽기 범위 (RLS) =====
set role authenticated;
set request.jwt.claim.sub = :'MOD';
select t.ok('감독관은 계정·탈퇴 분류를 못 봄', (select count(*) = 0 from inquiries where category = 'account'));
select t.ok('감독관은 나머지 분류를 봄', (select count(*) >= 3 from inquiries where category <> 'account'));
select t.fails('감독관의 직접 수정 불가', $$update inquiries set category = 'other'$$, 'permission denied');
select t.fails('감독관의 직접 삭제 불가', $$delete from inquiries$$, 'permission denied');
set request.jwt.claim.sub = :'OP';
select t.ok('운영자는 전부 봄', (select count(*) = (select count(*) from inquiries where category = 'account') + (select count(*) from inquiries where category <> 'account') from inquiries));
select t.ok('운영자는 계정·탈퇴도 봄', (select count(*) = 2 from inquiries where category = 'account'));
select t.fails('운영자도 직접 수정 불가', $$update inquiries set answer = 'x'$$, 'permission denied');
reset role;
-- 정책 이름 기준이 아니라 실제로 일반 회원이 비회원 것을 못 보는지
set role authenticated;
set request.jwt.claim.sub = :'U2';
select t.ok('다른 일반 회원은 아무것도 못 봄', (select count(*) = 0 from inquiries));
reset role;

-- ===== 3. 답변 =====
set role authenticated;
set request.jwt.claim.sub = :'U';
select t.fails('일반 회원은 답변 불가', format('select answer_inquiry(%s, %L)', :q_bug, '답'), '운영자만');
set request.jwt.claim.sub = :'MOD';
select t.fails('감독관은 계정·탈퇴에 답변 불가', format('select answer_inquiry(%s, %L)', :q_acc, '답'), '운영자만 답변');
select t.fails('답변 필수', format('select answer_inquiry(%s, %L)', :q_bug, '  '), '답변을 적어');
select t.fails('답변 길이 제한', format('select answer_inquiry(%s, %L)', :q_bug, repeat('가', 2001)), '2000자까지');
select answer_inquiry(:q_bug, '확인했습니다. 곧 고치겠습니다.');
select t.fails('두 번째 답변은 이미 처리됨(TL409)', format('select answer_inquiry(%s, %L)', :q_bug, '또'), '이미 다른 분이 처리했습니다');
reset role;
select t.ok('답변이 저장됨', (select answer = '확인했습니다. 곧 고치겠습니다.' and answered_at is not null from inquiries where id = :q_bug));
select t.ok('보낸 사람에게 알림: 분류만 쓰고 처리자·감독 글자 없음', (select count(*) = 1 and bool_and(message = '"오류 신고" 문의에 답변이 도착했습니다.')
  from notifications where user_id = :'U' and kind = 'inquiry_answered'));
select t.ok('처리 기록: 번호만, 내용 없음', exists (
  select 1 from moderation_log where action = 'answer_inquiry' and target_kind = 'inquiry' and target_id = :q_bug::text
    and actor_id = :'MOD' and actor_role = 'moderator' and note is null));
select t.ok('답변은 보낸 사람이 봄', (select count(*) = 1 from (
  select 1 from inquiries where id = :q_bug and answer is not null) x));

-- 운영자: 계정·탈퇴 답변 가능, 본인 문의 답변 불가
set role authenticated;
set request.jwt.claim.sub = :'OP';
select answer_inquiry(:q_acc, '탈퇴는 계정 설정에서 할 수 있습니다.');
select create_inquiry('other', '운영자가 쓴 문의입니다') as q_op \gset
select t.fails('본인 문의에는 답변 불가', format('select answer_inquiry(%s, %L)', :q_op, '셀프'), '본인이 보낸');
select t.fails('없는 문의', $$select answer_inquiry(999999, '답')$$, '찾지 못했습니다');
reset role;

-- ===== 4. 분류 옮기기 (운영자만) =====
set role authenticated;
set request.jwt.claim.sub = :'U2';
select create_inquiry('other', '계정 문제를 기타로 보냄') as q_mv \gset
set request.jwt.claim.sub = :'MOD';
select t.ok('옮기기 전에는 감독관에게 보임', (select count(*) = 1 from inquiries where id = :q_mv));
select t.fails('감독관은 옮기기 불가', format('select set_inquiry_category(%s, %L)', :q_mv, 'account'), '운영자만');
set request.jwt.claim.sub = :'U2';
select t.fails('일반 회원은 옮기기 불가', format('select set_inquiry_category(%s, %L)', :q_mv, 'account'), '운영자만');
set request.jwt.claim.sub = :'OP';
select t.fails('같은 분류', format('select set_inquiry_category(%s, %L)', :q_mv, 'other'), '이미 같은 분류');
select t.fails('모르는 분류', format('select set_inquiry_category(%s, %L)', :q_mv, 'zzz'), '분류를 골라');
select set_inquiry_category(:q_mv, 'account');
set request.jwt.claim.sub = :'MOD';
select t.ok('옮기면 감독관에게 안 보임', (select count(*) = 0 from inquiries where id = :q_mv));
select t.fails('감독관은 옮긴 문의에 답변 불가', format('select answer_inquiry(%s, %L)', :q_mv, '답'), '운영자만 답변');
reset role;
select t.ok('옮긴 기록: 분류 이름만', exists (
  select 1 from moderation_log where action = 'move_inquiry' and target_id = :q_mv::text and note = '기타 → 계정·탈퇴'));
-- 감독관이 직접 호출해도 거부되는 운영자 전용 함수 목록(moderator_test)에 들어간다는 뜻: require_operator 사용
select t.ok('set_inquiry_category는 운영자 검사를 함', (select prosrc like '%require_operator()%' from pg_proc where proname = 'set_inquiry_category'));

-- ===== 5. 지우기·내부 함수 =====
set role authenticated;
set request.jwt.claim.sub = :'U2';
select delete_my_inquiry(:q_mv);
select t.fails('이미 지움', format('select delete_my_inquiry(%s)', :q_mv), '찾지 못했습니다');
select t.fails('보관 삭제 함수는 사람이 못 부름', $$select purge_old_inquiries()$$, 'permission denied');
select t.fails('분류 이름 함수는 사람이 못 부름', $$select inquiry_category_label('bug')$$, 'permission denied');
reset role;
select t.ok('anon은 함수를 못 부름', not has_function_privilege('anon', 'public.create_inquiry(text,text)', 'execute')
  and not has_function_privilege('anon', 'public.answer_inquiry(bigint,text)', 'execute')
  and not has_function_privilege('anon', 'public.delete_my_inquiry(bigint)', 'execute')
  and not has_function_privilege('anon', 'public.set_inquiry_category(bigint,text)', 'execute'));
select t.ok('anon은 표를 못 읽음', not has_table_privilege('anon', 'public.inquiries', 'select'));

-- ===== 6. 보관 기간 (마지막 활동 = 답변 시각, 없으면 접수 시각) =====
insert into inquiries (user_id, category, body, created_at) values
  (:'U2', 'bug', '오래된 미답변 문의', now() - interval '181 days'),
  (:'U2', 'bug', '179일 된 미답변 문의', now() - interval '179 days');
insert into inquiries (user_id, category, body, created_at, answer, answered_at) values
  (:'U2', 'bug', '오래 전 접수, 최근 답변', now() - interval '400 days', '답변', now() - interval '10 days'),
  (:'U2', 'bug', '오래 전 답변', now() - interval '400 days', '답변', now() - interval '181 days');
select t.ok('보관 기간이 지난 2건만 지움', (select public.purge_old_inquiries() = 2));
select t.ok('남은 것은 179일 된 것과 최근 답변', (select count(*) = 2 from inquiries where user_id = :'U2'));
update public.xp_rules set value = 30 where key = 'inquiry_keep_days';
select t.ok('보관 기간은 설정값을 따름: 10일 된 답변만 남김', (select public.purge_old_inquiries() = 1));
select t.ok('남은 것은 1건', (select count(*) = 1 from inquiries where user_id = :'U2'));
update public.xp_rules set value = 180 where key = 'inquiry_keep_days';

-- ===== 7. 탈퇴하면 함께 지움 =====
select t.ok('탈퇴 전 문의가 있음', (select count(*) >= 1 from inquiries where user_id = :'U'));
delete from auth.users where id = :'U';
select t.ok('탈퇴하면 문의·답변·하루 개수 모두 삭제', not exists (select 1 from inquiries where user_id = :'U')
  and not exists (select 1 from inquiry_quota where user_id = :'U'));
select t.ok('처리 기록은 남음(번호만)', exists (select 1 from moderation_log where action = 'answer_inquiry'));
