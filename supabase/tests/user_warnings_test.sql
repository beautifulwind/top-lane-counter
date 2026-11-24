-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 069 운영자 경고: 보내기 규칙(운영자만·운영자 모드·자기 자신/운영자 불가·감독관은 됨·내용 1~500자), 알림 warning_received(문장에 내용 없음·휴대폰 묶음),
--   내용은 본인·운영자만 읽기(감독관·남 불가), [확인했습니다](본인만·다시 눌러도 성공·알림도 읽음·제한 중에도 됨),
--   상태 확인함/알림만 읽음/아직(알림이 지워져도 남음), 활동 제한과 함께면 제한 번호, 처리 기록(내용 없음),
--   068 허용 목록·빠뜨림 방지 그대로 통과, 탈퇴하면 기록 삭제, 거절된 시도는 데이터를 바꾸지 않음
\set ON_ERROR_STOP 1
\set QUIET 1
\set OP '00000000-0000-0000-0000-00000000000a'
\set M  '00000000-0000-0000-0000-00000000000b'
\set U  '00000000-0000-0000-0000-00000000000c'
\set X  '00000000-0000-0000-0000-00000000000d'
\set OP2 '00000000-0000-0000-0000-00000000000f'
insert into auth.users (id, email) values (:'OP', 'op@x.com'), (:'M', 'm@x.com'), (:'U', 'u@x.com'), (:'X', 'x@x.com');
update public.profiles set nickname = '영자', role = 'admin' where id = :'OP';
update public.profiles set nickname = '감독', role = 'moderator' where id = :'M';
update public.profiles set nickname = '말썽' where id = :'U';
update public.profiles set nickname = '구경꾼' where id = :'X';
create temp table ids (k text primary key, v bigint);
grant all on ids to authenticated, anon;
create function pg_temp.id(p text) returns bigint language sql stable as $$ select v from ids where k = p $$;
create function pg_temp.err(q text) returns text language plpgsql as $$
begin
  execute q;
  return 'OK';
exception when others then
  return sqlerrm;
end $$;
-- 기존 데이터 지문 (경고 표·경고 알림·warn_user 처리 기록 밖은 그대로여야 한다)
create function pg_temp.fp() returns text language sql stable as $$
  select (select count(*) || '/' || md5(coalesce(string_agg(n::text, '|' order by n.id), '')) from public.notifications n where n.kind <> 'warning_received')
    || '#' || (select count(*) || '/' || md5(coalesce(string_agg(r::text, '|' order by r.id), '')) from public.user_restrictions r)
    || '#' || (select count(*) || '/' || md5(coalesce(string_agg(m::text, '|' order by m.id), '')) from public.moderation_log m where m.action <> 'warn_user')
    || '#' || (select md5(string_agg(p::text, '|' order by p.id)) from public.profiles p) $$;
grant execute on all functions in schema pg_temp to anon, authenticated;

-- ===== 1. 표 / RLS / 권한 =====
select t.ok('경고 표 RLS 켬, 본인·운영자 읽기 정책 하나',
  (select relrowsecurity from pg_class where oid = 'public.user_warnings'::regclass)
  and (select count(*) from pg_policy where polrelid = 'public.user_warnings'::regclass) = 1
  and (select polcmd from pg_policy where polrelid = 'public.user_warnings'::regclass) = 'r');
select t.ok('로그인은 읽기만, 비로그인은 아무 권한 없음',
  has_table_privilege('authenticated', 'public.user_warnings', 'select')
  and not exists (select 1 from unnest(array['insert', 'update', 'delete']) p where has_table_privilege('authenticated', 'public.user_warnings', p))
  and not exists (select 1 from unnest(array['select', 'insert', 'update', 'delete']) p where has_table_privilege('anon', 'public.user_warnings', p)));
select t.ok('함수 권한: 화면 함수 4개는 로그인만, 내부 함수 2개는 아무도',
  (select bool_and(has_function_privilege('authenticated', f, 'execute') and not has_function_privilege('anon', f, 'execute'))
     from unnest(array['public.warn_user(uuid, text)', 'public.ack_warning(bigint)', 'public.my_warnings()',
                       'public.admin_member_warnings(uuid)']::regprocedure[]) f)
  and (select bool_and(not has_function_privilege('authenticated', f, 'execute') and not has_function_privilege('anon', f, 'execute'))
     from unnest(array['public.warning_notice_read()', 'public.warning_notice_message()']::regprocedure[]) f));
select t.ok('대상은 탈퇴하면 cascade, 보낸 사람·제한·알림은 set null',
  (select string_agg(a.attname || ':' || c.confdeltype::text, ',' order by a.attname)
     from pg_constraint c join pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
    where c.conrelid = 'public.user_warnings'::regclass and c.contype = 'f')
  = 'created_by:n,notification_id:n,restriction_id:n,user_id:c');
select t.ok('휴대폰 알림 묶음: warning_received = my_results, 다른 종류는 그대로',
  public.push_group('warning_received') = 'my_results' and public.push_group('build_edited') = 'build_edits'
  and public.push_group('profile_photo_removed') = 'my_results' and public.push_group('level_up') is null);
select t.ok('068 허용 목록에 이유와 함께 2개 추가 (73 / 8 = 069 뒤 71 + 072 기기 토큰 함수 2개)',
  (select count(*) filter (where kind = 'function') || '/' || count(*) filter (where kind = 'policy') from public.restriction_exemptions) = '73/8'
  and exists (select 1 from public.restriction_exemptions where name = 'ack_warning(bigint)' and reason like '%활동 제한 중에도%'));
select pg_temp.fp() as fp0 \gset

-- ===== 2. 보내기 규칙 =====
set role authenticated;
set request.jwt.claim.sub = :'M';
select t.fails('감독관은 못 보냄', format($$select warn_user(%L, '도배')$$, :'U'), '운영자');
set request.jwt.claim.sub = :'U';
select t.fails('일반 회원은 못 보냄', format($$select warn_user(%L, '도배')$$, :'X'), '운영자');
set request.jwt.claim.sub = :'OP';
select t.fails('내용 없음', format($$select warn_user(%L, E'  \n ')$$, :'U'), '경고 내용을 적어 주세요');
select t.fails('500자 넘음', format($$select warn_user(%L, repeat('가', 501))$$, :'U'), '500자까지');
select t.fails('자기 자신', format($$select warn_user(%L, '도배')$$, :'OP'), '자기 자신에게는');
select t.fails('없는 회원', $$select warn_user('00000000-0000-0000-0000-000000000099', '도배')$$, '회원을 찾지 못했습니다');
reset role;
-- 규칙상 운영자는 1명(profiles_one_operator)이라 다른 운영자는 없지만, 막는 줄이 있는지 트랜잭션 안에서 잠깐 만들어 확인하고 되돌린다
begin;
drop index public.profiles_one_operator;
insert into auth.users (id, email) values (:'OP2', 'op2@x.com');
update public.profiles set nickname = '영자둘', role = 'admin' where id = :'OP2';
set local role authenticated;
set local request.jwt.claim.sub = :'OP';
select t.fails('다른 운영자', format($$select warn_user(%L, '도배')$$, :'OP2'), '운영자에게는 경고를 보낼 수 없습니다');
rollback;
select t.ok('검사용 운영자는 되돌려짐 (운영자 1명 규칙 그대로)', not exists (select 1 from public.profiles where id = :'OP2')
  and to_regclass('public.profiles_one_operator') is not null);
update public.profiles set operator_mode = false where id = :'OP';
set role authenticated;
set request.jwt.claim.sub = :'OP';
select t.fails('운영자 모드를 끄면 못 보냄', format($$select warn_user(%L, '도배')$$, :'U'), '운영자');
reset role;
update public.profiles set operator_mode = true where id = :'OP';
select t.ok('거절된 시도는 아무것도 남기지 않음', (select count(*) from public.user_warnings) = 0
  and not exists (select 1 from public.notifications where kind = 'warning_received') and pg_temp.fp() = :'fp0');

set role authenticated;
set request.jwt.claim.sub = :'OP';
insert into ids select 'w1', (warn_user(:'U', E'  욕설을 반복했습니다.\n다음에는 활동 제한입니다.  ') ->> 'id')::bigint;
insert into ids select 'wm', (warn_user(:'M', '감독관 처리 지연') ->> 'id')::bigint;
reset role;
select t.ok('감독관에게도 보낼 수 있음', pg_temp.id('wm') is not null);
select t.ok('내용 앞뒤 공백은 지우고 저장, 보낸 사람 기록, 제한 없음이면 restriction_id 없음',
  (select memo = E'욕설을 반복했습니다.\n다음에는 활동 제한입니다.' and created_by = :'OP' and restriction_id is null and acked_at is null and notice_read_at is null
     from public.user_warnings where id = pg_temp.id('w1')));
select t.ok('알림 warning_received 하나, 문장에 내용(메모)은 없음, 경고와 짝',
  (select count(*) from public.notifications where user_id = :'U' and kind = 'warning_received') = 1
  and (select n.message from public.notifications n join public.user_warnings w on w.notification_id = n.id where w.id = pg_temp.id('w1'))
      = '운영자 경고를 받았습니다. 화면 위 안내에서 내용을 확인해 주세요.'
  and not exists (select 1 from public.notifications where kind = 'warning_received' and message like '%욕설%'));
select t.ok('처리 기록 warn_user (대상 닉네임, 내용 없음)',
  (select count(*) from public.moderation_log where action = 'warn_user') = 2
  and (select note is null and target_kind = 'user' and target_id = :'U' and target_nickname = '말썽'
         from public.moderation_log where action = 'warn_user' and target_id = :'U'));
select t.ok('보내기는 기존 데이터(다른 알림·제한·다른 처리 기록·프로필)를 바꾸지 않음', pg_temp.fp() = :'fp0');

-- ===== 3. 읽기: 본인·운영자만 =====
set role authenticated;
set request.jwt.claim.sub = :'U';
select t.ok('본인: 표에서 내 경고만 보임', (select count(*) from public.user_warnings) = 1);
select t.ok('본인: my_warnings = 안 본 경고 (내용·시각)',
  jsonb_array_length(my_warnings()) = 1 and my_warnings() -> 0 ->> 'memo' like '욕설을 반복했습니다.%'
  and (my_warnings() -> 0 ->> 'id')::bigint = pg_temp.id('w1'));
select t.fails('본인: 운영자 기록 함수는 못 부름', format($$select admin_member_warnings(%L)$$, :'U'), '운영자');
set request.jwt.claim.sub = :'X';
select t.ok('남: 표에서 아무것도 안 보임, my_warnings 빈 목록', (select count(*) from public.user_warnings) = 0 and my_warnings() = '[]'::jsonb);
set request.jwt.claim.sub = :'M';
select t.ok('감독관: 남의 경고는 안 보임 (자기 것만)', (select count(*) from public.user_warnings) = 1
  and (select user_id from public.user_warnings) = :'M');
set request.jwt.claim.sub = :'OP';
select t.ok('운영자: 전부 보임', (select count(*) from public.user_warnings) = 2);
select t.ok('운영자: 기록 함수 = 최근 것부터, 보낸 사람 닉네임, 상태 아직(unread)',
  (select admin_member_warnings(:'U') -> 0 ->> 'state') = 'unread'
  and (select admin_member_warnings(:'U') -> 0 ->> 'created_by') = '영자'
  and jsonb_array_length(admin_member_warnings(:'X')) = 0);
set role anon;
set request.jwt.claim.sub = '';
select t.fails('비로그인은 my_warnings 못 부름', 'select public.my_warnings()', 'permission denied');
reset role;

-- ===== 4. 알림만 읽음 → 확인함 =====
set role authenticated;
set request.jwt.claim.sub = :'U';
select mark_all_notifications_read((select max(id) from notifications)) \gset
reset role;
select t.ok('알림 화면을 열어 읽으면 경고 기록에 읽은 시각 (알림만 읽음)',
  (select notice_read_at is not null and acked_at is null from public.user_warnings where id = pg_temp.id('w1')));
set role authenticated;
set request.jwt.claim.sub = :'OP';
select t.ok('운영자 화면 상태: 알림만 읽음(read)', (admin_member_warnings(:'U') -> 0 ->> 'state') = 'read');
set request.jwt.claim.sub = :'X';
select t.fails('남은 [확인했습니다] 못 함 (없는 것과 같은 문장)', format('select ack_warning(%s)', pg_temp.id('w1')), '경고를 찾지 못했습니다');
set request.jwt.claim.sub = :'OP';
select t.fails('운영자도 대신 확인 못 함', format('select ack_warning(%s)', pg_temp.id('w1')), '경고를 찾지 못했습니다');
set request.jwt.claim.sub = :'U';
select ack_warning(pg_temp.id('w1')) ->> 'acked_at' as ack1 \gset
select t.ok('본인 [확인했습니다] → 확인 시각', :'ack1' <> '');
select t.ok('다시 눌러도 성공, 시각은 처음 그대로', (ack_warning(pg_temp.id('w1')) ->> 'acked_at') = :'ack1');
select t.ok('확인하면 안내 상자에서 빠짐', my_warnings() = '[]'::jsonb);
set request.jwt.claim.sub = :'OP';
select t.ok('운영자 화면 상태: 확인함(acked)', (admin_member_warnings(:'U') -> 0 ->> 'state') = 'acked');
reset role;

-- 알림을 안 읽고 바로 [확인했습니다] → 알림도 읽음
set role authenticated;
set request.jwt.claim.sub = :'OP';
insert into ids select 'w2', (warn_user(:'U', '두 번째 경고') ->> 'id')::bigint;
set request.jwt.claim.sub = :'U';
select ack_warning(pg_temp.id('w2')) \gset
reset role;
select t.ok('바로 확인하면 그 알림도 읽음이 되고 읽은 시각도 남음',
  (select n.read_at is not null and w.notice_read_at is not null and w.acked_at is not null
     from public.user_warnings w join public.notifications n on n.id = w.notification_id where w.id = pg_temp.id('w2')));
-- 알림이 90일 뒤 지워져도 상태는 남는다
delete from public.notifications where id = (select notification_id from public.user_warnings where id = pg_temp.id('w1'));
select t.ok('알림이 지워지면 짝만 비고 기록·상태는 그대로',
  (select notification_id is null and notice_read_at is not null and acked_at is not null from public.user_warnings where id = pg_temp.id('w1')));

-- ===== 5. 활동 제한과 함께 / 제한 중에도 확인 =====
set role authenticated;
set request.jwt.claim.sub = :'OP';
insert into ids select 'r1', (restrict_user(:'U', 3, '욕설') ->> 'id')::bigint;
insert into ids select 'w3', (warn_user(:'U', '욕설로 3일 제한합니다.') ->> 'id')::bigint;
reset role;
select t.ok('제한 중에 보내면 그 제한 번호를 남김', (select restriction_id from public.user_warnings where id = pg_temp.id('w3')) = pg_temp.id('r1'));
select t.ok('처리 기록 메모: 「활동 제한과 함께」',
  (select note from public.moderation_log where action = 'warn_user' order by id desc limit 1) = '활동 제한과 함께');
set role authenticated;
set request.jwt.claim.sub = :'U';
select t.ok('제한 중에도 안 본 경고가 보임', jsonb_array_length(my_warnings()) = 1);
select t.ok('제한 중에도 [확인했습니다] 됨', pg_temp.err(format('select ack_warning(%s)', pg_temp.id('w3'))) = 'OK');
select t.ok('제한 중 쓰기는 여전히 막힘 (068 그대로)', pg_temp.err($$select create_post('제목입니다', '본문입니다', '{}')$$) like '활동이 제한된 상태입니다.%');
reset role;
-- 제한을 지워도 경고는 남는다
delete from public.user_restrictions where id = pg_temp.id('r1');
select t.ok('제한 기록이 지워지면 경고의 제한 번호만 비움', (select restriction_id is null from public.user_warnings where id = pg_temp.id('w3')));

-- ===== 6. 068 빠뜨림 방지: 새 쓰기 함수 2개는 허용 목록, 나머지는 쓰기 함수가 아님 =====
select t.ok('새 쓰기 함수(volatile·로그인 실행)는 허용 목록에 있음, 읽기 함수는 stable',
  not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
               where n.nspname = 'public' and p.proname in ('warn_user', 'ack_warning', 'my_warnings', 'admin_member_warnings')
                 and p.provolatile = 'v'
                 and not exists (select 1 from public.restriction_exemptions e
                                  where e.kind = 'function' and e.name = p.proname || '(' || oidvectortypes(p.proargtypes) || ')'))
  and (select provolatile from pg_proc where oid = 'public.my_warnings()'::regprocedure) = 's'
  and (select provolatile from pg_proc where oid = 'public.admin_member_warnings(uuid)'::regprocedure) = 's');

-- ===== 7. 탈퇴: 기록이 지워진다 =====
select t.ok('탈퇴 전 U의 경고 3개', (select count(*) from public.user_warnings where user_id = :'U') = 3);
set role authenticated;
set request.jwt.claim.sub = :'U';
select t.ok('탈퇴(계정 삭제)', pg_temp.err($$select delete_my_account('말썽')$$) = 'OK');
reset role;
select t.ok('탈퇴하면 경고 기록 삭제, 다른 사람 것은 그대로',
  (select count(*) from public.user_warnings where user_id = :'U') = 0 and (select count(*) from public.user_warnings) = 1);
select t.ok('처리 기록은 대상 칸만 비움 (055 규칙 그대로)', not exists (select 1 from public.moderation_log where target_id = :'U')
  and (select count(*) from public.moderation_log where action = 'warn_user' and target_nickname = '탈퇴한 이용자') = 3);
