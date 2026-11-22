-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 067: 빌드 수정 알림 build_edited - 받는 사람(운영자 전원·원 작성자·이전 기여자, 감독관·수정한 본인 제외, 중복 없음),
--      문장(받는 사람별), 10분 묶기(N번 수정), 알림 설정(build_edits)을 끄면 안 받음, 차단(061)·탈퇴 처리, 기여자 50명 상한,
--      되돌리기 포함, 알림이 실패해도 수정 저장은 성공, 푸시 묶음, 표 권한
\set ON_ERROR_STOP 1
\set QUIET 1
\set OP  '00000000-0000-0000-0000-00000000000a'
\set MOD '00000000-0000-0000-0000-0000000000b3'
\set U   '00000000-0000-0000-0000-00000000000d'
\set C1  '00000000-0000-0000-0000-0000000000c1'
\set C2  '00000000-0000-0000-0000-0000000000c2'
\set E   '00000000-0000-0000-0000-0000000000e1'
\set doc '{"summary":"요약","level_notes":{"1":"a","2":"b","3":"c","6":"d"},"lane_cautions":""}'
insert into auth.users (id, email) values (:'OP', 'op@x.com'), (:'MOD', 'mod@x.com'), (:'U', 'u@x.com'),
  (:'C1', 'c1@x.com'), (:'C2', 'c2@x.com'), (:'E', 'e@x.com');
update public.profiles set nickname = '영자', role = 'admin' where id = :'OP';
update public.profiles set nickname = '감독', role = 'moderator' where id = :'MOD';
update public.profiles set nickname = '유저' where id = :'U';
update public.profiles set nickname = '씨원' where id = :'C1';
update public.profiles set nickname = '씨투' where id = :'C2';
update public.profiles set nickname = '고침이' where id = :'E';
update public.xp_rules set value = 0 where key in ('wiki_create_interval', 'build_edit_interval');
create temp table ids (k text primary key, v bigint);
grant all on ids to authenticated, anon;
create function pg_temp.id(p text) returns bigint language sql stable as $$ select v from ids where k = p $$;
select format('create function pg_temp.doc() returns jsonb language sql immutable as %L', format('select %L::jsonb', :'doc')) as mkdoc \gset
:mkdoc;
-- 지금 로그인한 사람으로 b1의 요약을 바꿔 수정 (버전은 지금 값)
create function pg_temp.ed(p_summary text) returns integer language sql volatile as $$
  select public.edit_build(v, (select version from public.builds where id = v), t.build() || pg_temp.doc() || jsonb_build_object('summary', p_summary))
    from ids where k = 'b1' $$;
-- 받는 사람 → 알림 수 / 문장
create function pg_temp.cnt(p uuid) returns bigint language sql volatile as $$
  select count(*) from public.notifications where user_id = p and kind = 'build_edited' $$;
create function pg_temp.msg(p uuid) returns text language sql volatile as $$
  select message from public.notifications where user_id = p and kind = 'build_edited' order by id desc limit 1 $$;
create function pg_temp.total() returns bigint language sql volatile as $$
  select count(*) from public.notifications where kind = 'build_edited' $$;
grant execute on all functions in schema pg_temp to anon, authenticated;

-- ===== 1. 구조·권한 =====
select t.ok('알림 종류 build_edited 허용', pg_get_constraintdef((select oid from pg_constraint where conname = 'notifications_kind_check')) like '%build_edited%');
select t.ok('푸시 묶음: build_edited → build_edits (staff_new·my_results 아님)', push_group('build_edited') = 'build_edits');
select t.ok('설정 칸 build_edits 기본 켜짐', (select column_default from information_schema.columns
  where table_name = 'push_settings' and column_name = 'build_edits') = 'true');
-- 본인이 설정 화면에서 끌 수 있음 (upsert = insert … on conflict update, 칸 권한 + RLS 본인 줄)
set role authenticated;
set request.jwt.claim.sub = :'C2';
insert into push_settings (user_id, staff_new, my_results, build_edits) values (:'C2', true, true, true)
  on conflict (user_id) do update set build_edits = excluded.build_edits;
insert into push_settings (user_id, staff_new, my_results, build_edits) values (:'C2', true, true, false)
  on conflict (user_id) do update set build_edits = excluded.build_edits;
reset role;
select t.ok('본인이 build_edits를 끄고 켤 수 있음 (칸 권한)', (select build_edits from push_settings where user_id = :'C2') = false);
set role authenticated;
set request.jwt.claim.sub = :'C2';
select t.fails('남의 설정은 못 고침', format($$insert into push_settings (user_id, staff_new, my_results, build_edits) values (%L, true, true, false)
  on conflict (user_id) do update set build_edits = excluded.build_edits$$, :'C1'), 'row-level security');
-- 옛 앱(1.1 이하) 저장: build_edits를 보내지 않으면 그대로 남음
insert into push_settings (user_id, staff_new, my_results, follow_builds, notice, new_followers, updated_at) values (:'C2', true, false, true, true, false, now())
  on conflict (user_id) do update set my_results = excluded.my_results, updated_at = excluded.updated_at;
reset role;
select t.ok('옛 앱이 설정을 저장해도 build_edits는 그대로', (select build_edits from push_settings where user_id = :'C2') = false
  and (select my_results from push_settings where user_id = :'C2') = false);
delete from push_settings where user_id = :'C2';
select t.ok('짝 표: RLS 켬 + 정책 없음 + 로그인·비로그인 권한 없음',
  (select relrowsecurity from pg_class where oid = 'public.build_edit_notices'::regclass)
  and not exists (select 1 from pg_policy where polrelid = 'public.build_edit_notices'::regclass)
  and not has_table_privilege('authenticated', 'public.build_edit_notices', 'select')
  and not has_table_privilege('anon', 'public.build_edit_notices', 'select'));
select t.ok('알림 만드는 함수는 직접 못 부름', not has_function_privilege('authenticated', 'public.notify_build_edit(bigint,uuid,text)', 'execute')
  and not has_function_privilege('anon', 'public.notify_build_edit(bigint,uuid,text)', 'execute')
  and not has_function_privilege('authenticated', 'public.build_edit_message(text,uuid,uuid,integer,text)', 'execute'));
select t.ok('트리거는 edit·revert 줄에만', (select pg_get_triggerdef(oid) from pg_trigger where tgname = 'build_revisions_notify')
  like '%AFTER INSERT ON public.build_revisions%kind = ANY (ARRAY[''edit''::text, ''revert''::text])%');

-- ===== 2. 등록은 알리지 않음 =====
set role authenticated;
set request.jwt.claim.sub = :'U';
select create_matchup('Darius', 'Garen', t.build() || pg_temp.doc()) as m \gset
insert into ids values ('m1', (:'m'::jsonb ->> 'counter_id')::bigint), ('b1', (:'m'::jsonb ->> 'build_id')::bigint);
reset role;
select t.ok('새 빌드 등록(create 기록)은 수정 알림 없음', pg_temp.total() = 0);

-- ===== 3. 첫 수정: 운영자 전원 + 원 작성자, 감독관·본인 제외 =====
set role authenticated;
set request.jwt.claim.sub = :'C1';
select pg_temp.ed('씨원이 고침');
reset role;
select t.ok('운영자 받음 (운영자는 한 명만 둘 수 있음 - profiles_one_operator)', pg_temp.cnt(:'OP') = 1);
select t.ok('감독관은 안 받음', pg_temp.cnt(:'MOD') = 0);
select t.ok('원 작성자 받음', pg_temp.cnt(:'U') = 1);
select t.ok('수정한 본인은 안 받음', pg_temp.cnt(:'C1') = 0);
select t.ok('모두 2개', pg_temp.total() = 2);
select t.ok('운영자 문장', pg_temp.msg(:'OP') = '씨원님이 유저님의 빌드를 수정했습니다.');
select t.ok('작성자 문장', pg_temp.msg(:'U') = '씨원님이 회원님의 빌드를 수정했습니다.');
select t.ok('알림에 빌드·상대법 번호', (select bool_and(build_id = pg_temp.id('b1') and counter_id = pg_temp.id('m1'))
  from notifications where kind = 'build_edited'));

-- ===== 4. 다른 사람 수정: 이전 기여자도 받음, 작성자는 기여자이기도 하지만 한 번만 =====
set role authenticated;
set request.jwt.claim.sub = :'E';
select pg_temp.ed('고침이 1');
reset role;
select t.ok('이전 기여자(씨원) 받음 + 기여자 문장', pg_temp.cnt(:'C1') = 1 and pg_temp.msg(:'C1') = '고침이님이 회원님이 참여한 빌드를 수정했습니다.');
select t.ok('작성자는 (기여자 목록에도 있지만) 한 번만, 작성자 문장', pg_temp.cnt(:'U') = 2 and pg_temp.msg(:'U') = '고침이님이 회원님의 빌드를 수정했습니다.');
select t.ok('운영자도 한 번', pg_temp.cnt(:'OP') = 2);
select t.ok('수정한 본인(고침이) 제외', pg_temp.cnt(:'E') = 0);
select t.ok('한 사람에게 이 수정 알림은 한 줄 (중복 없음)', not exists (
  select 1 from notifications n join build_edit_notices x on x.notification_id = n.id
   where x.editor_id = :'E' group by n.user_id having count(*) > 1));

-- ===== 5. 10분 묶기 =====
set role authenticated;
set request.jwt.claim.sub = :'E';
select pg_temp.ed('고침이 2');
reset role;
select t.ok('10분 안 다시 고침: 새 줄 없음', pg_temp.cnt(:'U') = 2 and pg_temp.cnt(:'C1') = 1 and pg_temp.cnt(:'OP') = 2);
select t.ok('받는 사람 모두 「(2번 수정)」', pg_temp.msg(:'U') = '고침이님이 회원님의 빌드를 수정했습니다. (2번 수정)'
  and pg_temp.msg(:'C1') = '고침이님이 회원님이 참여한 빌드를 수정했습니다. (2번 수정)'
  and pg_temp.msg(:'OP') = '고침이님이 유저님의 빌드를 수정했습니다. (2번 수정)');
-- 작성자가 읽음 → 작성자만 새 줄, 나머지는 3번
update notifications set read_at = now() where user_id = :'U' and kind = 'build_edited';
set role authenticated;
set request.jwt.claim.sub = :'E';
select pg_temp.ed('고침이 3');
reset role;
select t.ok('읽은 알림은 묶지 않음: 작성자에게 새 줄', pg_temp.cnt(:'U') = 3 and pg_temp.msg(:'U') = '고침이님이 회원님의 빌드를 수정했습니다.');
select t.ok('안 읽은 사람은 「(3번 수정)」', pg_temp.msg(:'C1') like '%(3번 수정)' and pg_temp.msg(:'OP') like '%(3번 수정)');
-- 10분 지남 → 새 줄
update build_edit_notices set last_at = now() - interval '11 minutes';
set role authenticated;
set request.jwt.claim.sub = :'E';
select pg_temp.ed('고침이 4');
reset role;
select t.ok('10분 지나면 새 줄', pg_temp.cnt(:'C1') = 2 and pg_temp.cnt(:'OP') = 3 and pg_temp.msg(:'C1') not like '%번 수정)');
-- 다른 사람이 10분 안에 고치면 따로
set role authenticated;
set request.jwt.claim.sub = :'C1';
select pg_temp.ed('씨원 다시');
reset role;
select t.ok('다른 사람 수정은 묶지 않음 (따로 한 줄)', pg_temp.cnt(:'OP') = 4 and pg_temp.cnt(:'E') = 1);

-- ===== 6. 알림 설정 끄기 =====
insert into push_settings (user_id, build_edits) values (:'C1', false);
update build_edit_notices set last_at = now() - interval '11 minutes';
set role authenticated;
set request.jwt.claim.sub = :'E';
select pg_temp.ed('고침이 5');
reset role;
select t.ok('설정을 끈 기여자는 새 알림 없음', pg_temp.cnt(:'C1') = 2);
select t.ok('끈 사람 말고는 그대로 받음', pg_temp.cnt(:'OP') = 5);
insert into push_subscriptions (user_id, endpoint, p256dh, auth) values (:'C1', 'https://push.test/c1', 'k', 'a'), (:'U', 'https://push.test/u', 'k', 'a');
select t.ok('휴대폰 알림: 끈 사람 안 감, 기본(설정 줄 없음)은 감', not push_wanted(:'C1', 'build_edited') and push_wanted(:'U', 'build_edited'));
update push_settings set build_edits = true where user_id = :'C1';

-- ===== 7. 차단 (061): 작성자·기여자는 어느 쪽이든 차단이면 없음, 운영자는 그대로 =====
set role authenticated;
set request.jwt.claim.sub = :'C2';
select pg_temp.ed('씨투 참여');
reset role;
insert into user_blocks (blocker_id, blocked_id) values (:'C2', :'E');   -- 기여자가 수정한 사람을 차단
insert into user_blocks (blocker_id, blocked_id) values (:'E', :'U');    -- 수정한 사람이 작성자를 차단
insert into user_blocks (blocker_id, blocked_id) values (:'OP', :'E');   -- 운영자가 차단해도 운영자 알림은 감
update build_edit_notices set last_at = now() - interval '11 minutes';
select pg_temp.cnt(:'C2') as c2_before, pg_temp.cnt(:'U') as u_before, pg_temp.cnt(:'OP') as op_before, pg_temp.cnt(:'C1') as c1_before \gset
set role authenticated;
set request.jwt.claim.sub = :'E';
select pg_temp.ed('고침이 6');
reset role;
select t.ok('내가 차단한 사람의 수정: 기여자 알림 없음', pg_temp.cnt(:'C2') = :c2_before);
select t.ok('나를 차단한 사람의 수정: 작성자 알림 없음', pg_temp.cnt(:'U') = :u_before);
select t.ok('운영자는 차단과 관계없이 받음', pg_temp.cnt(:'OP') = :op_before + 1);
select t.ok('차단과 무관한 기여자는 받음', pg_temp.cnt(:'C1') = :c1_before + 1);
delete from user_blocks;

-- ===== 8. 작성자 본인 수정 / 운영자 수정 / 되돌리기 =====
update build_edit_notices set last_at = now() - interval '11 minutes';
set role authenticated;
set request.jwt.claim.sub = :'U';
select pg_temp.ed('작성자가 고침');
reset role;
select t.ok('작성자가 자기 빌드를 고쳐도 운영자·기여자는 받음 (운영자 문장 「자기 빌드」)',
  pg_temp.msg(:'OP') = '유저님이 자기 빌드를 수정했습니다.' and pg_temp.msg(:'E') = '유저님이 회원님이 참여한 빌드를 수정했습니다.');
update build_edit_notices set last_at = now() - interval '11 minutes';
select pg_temp.cnt(:'OP') as op_b \gset
set role authenticated;
set request.jwt.claim.sub = :'OP';
select pg_temp.ed('운영자가 고침');
reset role;
select t.ok('운영자가 고침: 작성자·기여자 받음, 운영자 본인 제외',
  pg_temp.msg(:'U') = '영자님이 회원님의 빌드를 수정했습니다.' and pg_temp.msg(:'C2') = '영자님이 회원님이 참여한 빌드를 수정했습니다.'
  and pg_temp.cnt(:'OP') = :op_b);
insert into ids values ('rv_create', (select id from build_revisions where build_id = pg_temp.id('b1') and kind = 'create'));
update build_edit_notices set last_at = now() - interval '11 minutes';
set role authenticated;
set request.jwt.claim.sub = :'OP';
select revert_build(pg_temp.id('b1'), pg_temp.id('rv_create'), (select version from builds where id = pg_temp.id('b1')), '처음으로');
reset role;
select t.ok('되돌리기도 알림 (「되돌렸습니다」)', pg_temp.msg(:'U') = '영자님이 회원님의 빌드를 되돌렸습니다.'
  and pg_temp.msg(:'C1') = '영자님이 회원님이 참여한 빌드를 되돌렸습니다.');

-- ===== 9. 운영자 모드를 꺼도 운영자 알림이 보임, 받는 사람만 읽음 =====
update profiles set operator_mode = false where id = :'OP';
set role authenticated;
set request.jwt.claim.sub = :'OP';
select t.ok('운영자 모드 끔: 수정 알림은 그대로 보임', (select count(*) from notifications where kind = 'build_edited') = pg_temp.cnt(:'OP') and pg_temp.cnt(:'OP') > 0);
reset role;
update profiles set operator_mode = true where id = :'OP';
set role authenticated;
set request.jwt.claim.sub = :'C2';
select t.ok('다른 사람 수정 알림은 안 보임', (select count(*) from notifications where kind = 'build_edited' and user_id <> :'C2') = 0);
reset role;

-- ===== 10. 알림이 실패해도 수정 저장은 성공 =====
alter function public.build_edit_message(text, uuid, uuid, integer, text) rename to build_edit_message_off;
select pg_temp.total() as tot_before, (select version from builds where id = pg_temp.id('b1')) as ver_before \gset
update build_edit_notices set last_at = now() - interval '11 minutes';
set role authenticated;
set request.jwt.claim.sub = :'E';
select pg_temp.ed('알림 실패해도 저장');
reset role;
select t.ok('알림 실패: 수정은 저장됨', (select version from builds where id = pg_temp.id('b1')) = :ver_before + 1
  and (select summary from builds where id = pg_temp.id('b1')) = '알림 실패해도 저장'
  and exists (select 1 from build_revisions where build_id = pg_temp.id('b1') and editor_id = :'E' and version = :ver_before + 1));
select t.ok('알림 실패: 알림은 하나도 안 생김 (반쯤 남지 않음)', pg_temp.total() = :tot_before
  and (select count(*) from build_edit_notices) = (select count(*) from notifications where kind = 'build_edited'));
alter function public.build_edit_message_off(text, uuid, uuid, integer, text) rename to build_edit_message;

-- ===== 11. 기여자 50명 상한 (운영자·작성자는 상한과 관계없이) =====
insert into auth.users (id, email) select ('00000000-0000-0000-0001-' || lpad(g::text, 12, '0'))::uuid, 'many' || g || '@x.com' from generate_series(1, 55) g;
update profiles set nickname = '많음' || substr(id::text, 33) where id::text like '00000000-0000-0000-0001-%';
-- 많음1이 가장 오래전, 많음55가 가장 최근에 고친 기여자 (되돌리기로 앞의 기여자는 목록에서 빠졌음)
insert into build_editors (build_id, user_id, first_at, last_at, edits)
  select pg_temp.id('b1'), id, now() - interval '2 days', now() - interval '1 day' + (substr(id::text, 25)::int * interval '1 minute'), 1
    from profiles where id::text like '00000000-0000-0000-0001-%';
update build_edit_notices set last_at = now() - interval '11 minutes';
select pg_temp.total() as tot_b \gset
set role authenticated;
set request.jwt.claim.sub = :'E';
select pg_temp.ed('많은 기여자');
reset role;
select t.ok('기여자 알림은 최근 고친 순 50명까지', (select count(*) from notifications n join build_edit_notices x on x.notification_id = n.id
  where x.audience = 'contributor' and n.id > (select max(id) from notifications) - (pg_temp.total() - :tot_b)) = 50);
select t.ok('운영자·작성자는 상한과 관계없이 받음', (select count(*) from notifications n join build_edit_notices x on x.notification_id = n.id
  where x.audience in ('staff', 'author') and n.id > (select max(id) from notifications) - (pg_temp.total() - :tot_b)) = 2);
select t.ok('가장 오래전에 고친 5명(많음1~5)이 빠짐', (select count(*) from notifications where kind = 'build_edited'
  and user_id in (select ('00000000-0000-0000-0001-' || lpad(g::text, 12, '0'))::uuid from generate_series(1, 5) g)) = 0
  and (select count(*) from notifications where kind = 'build_edited'
  and user_id in (select ('00000000-0000-0000-0001-' || lpad(g::text, 12, '0'))::uuid from generate_series(6, 55) g)) = 50);
delete from auth.users where id::text like '00000000-0000-0000-0001-%';

-- ===== 12. 탈퇴 =====
-- 수정한 사람 탈퇴 → 이미 받은 알림 문장이 「탈퇴한 사용자가」
delete from auth.users where id = :'E';
select t.ok('수정한 사람 탈퇴: 닉네임이 알림에 남지 않음', not exists (select 1 from notifications where kind = 'build_edited' and message like '%고침이%'));
select t.ok('수정한 사람 탈퇴: 「탈퇴한 사용자가 …」 (N번 수정도 그대로)',
  exists (select 1 from notifications where user_id = :'OP' and message = '탈퇴한 사용자가 유저님의 빌드를 수정했습니다.')
  and exists (select 1 from notifications where user_id = :'C1' and message like '탈퇴한 사용자가 회원님이 참여한 빌드를 수정했습니다. (_번 수정)'));
-- 작성자 탈퇴 → 운영자 문장의 작성자 닉네임도
delete from auth.users where id = :'U';
select t.ok('작성자 탈퇴: 운영자 문장에 작성자 닉네임 없음', not exists (select 1 from notifications where kind = 'build_edited' and message like '%유저님%')
  and exists (select 1 from notifications where user_id = :'OP' and message = '탈퇴한 사용자가 탈퇴한 사용자의 빌드를 수정했습니다.'));
select t.ok('받는 사람 탈퇴: 그 사람 알림과 짝 줄 함께 지워짐', pg_temp.cnt(:'U') = 0
  and not exists (select 1 from build_edit_notices where user_id = :'U')
  and (select count(*) from build_edit_notices) = pg_temp.total());
-- 탈퇴한 사람은 받는 사람에서 빠짐 (작성자 없는 빌드를 고쳐도 오류 없음)
set role authenticated;
set request.jwt.claim.sub = :'C1';
select pg_temp.ed('작성자 없는 빌드');
reset role;
select t.ok('작성자·기여자가 탈퇴한 빌드도 오류 없이: 운영자에게 「탈퇴한 사용자의 빌드」, 탈퇴한 사람 몫은 없음',
  pg_temp.msg(:'OP') = '씨원님이 탈퇴한 사용자의 빌드를 수정했습니다.'
  and not exists (select 1 from notifications n where kind = 'build_edited' and not exists (select 1 from profiles p where p.id = n.user_id)));

-- ===== 13. 빌드가 지워지면 짝 줄도 =====
delete from builds where id = pg_temp.id('b1');
select t.ok('빌드 삭제: 짝 줄 함께 지워짐', not exists (select 1 from build_edit_notices));
