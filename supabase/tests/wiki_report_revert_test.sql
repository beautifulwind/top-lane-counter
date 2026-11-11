-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 043: 오류 신고(정식 회원만·남발 막기·운영진 알림·처리), 운영자 빌드 수정 기록·되돌리기(기여자 정리·TL412),
--      감독관 빌드 숨기기·다시 공개, build_edit_check(빌드 수정 규칙 그대로)
\set ON_ERROR_STOP 1
\set QUIET 1
\set OP  '00000000-0000-0000-0000-00000000000a'
\set MOD '00000000-0000-0000-0000-00000000000b'
\set U   '00000000-0000-0000-0000-00000000000d'
\set V   '00000000-0000-0000-0000-00000000000c'
\set W   '00000000-0000-0000-0000-00000000000f'
\set GU  '00000000-0000-0000-0000-000000000010'
\set doc '{"summary":"요약","level_notes":{"1":"a","2":"b","3":"c","6":"d"},"lane_cautions":""}'
insert into auth.users (id, email) values (:'OP', 'op@x.com'), (:'MOD', 'm@x.com'), (:'U', 'u@x.com'), (:'V', 'v@x.com'), (:'W', 'w@x.com');
insert into auth.users (id, email, is_anonymous) values (:'GU', null, true);
update public.profiles set nickname = '영자', role = 'admin' where id = :'OP';
update public.profiles set nickname = '감독', role = 'moderator' where id = :'MOD';
update public.profiles set nickname = '유저' where id = :'U';
update public.profiles set nickname = '브이' where id = :'V';
update public.profiles set nickname = '더블유' where id = :'W';
update public.profiles set nickname = '손님' where id = :'GU';
create temp table ids (k text primary key, v bigint);
grant all on ids to authenticated, anon;
create function pg_temp.id(p text) returns bigint language sql stable as $$ select v from ids where k = p $$;
insert into ids select 'quinn', id from counters where counter_champion = 'Quinn';
insert into ids select 'qb', min(id) from builds where counter_id = (select v from ids where k = 'quinn');

-- ===== 0. 준비: 유저가 상대법(+첫 빌드), 브이가 둘째 빌드, 감독이 셋째, 영자가 넷째 =====
set role authenticated;
set request.jwt.claim.sub = :'U';
select create_matchup('Darius', 'Garen', t.build() || :'doc'::jsonb) as m \gset
insert into ids values ('m1', (:'m'::jsonb ->> 'counter_id')::bigint), ('b1', (:'m'::jsonb ->> 'build_id')::bigint);
set request.jwt.claim.sub = :'V';
insert into ids values ('b2', create_build(pg_temp.id('m1'), t.build(array['6631','3047','3071']) || :'doc'::jsonb));
set request.jwt.claim.sub = :'MOD';
insert into ids values ('b3', create_build(pg_temp.id('m1'), t.build(array['6631','3047','3742']) || :'doc'::jsonb));
set request.jwt.claim.sub = :'OP';
insert into ids values ('b4', create_build(pg_temp.id('m1'), t.build(array['6631','3053','3071']) || :'doc'::jsonb));
reset role;
delete from wiki_last_write;
delete from notifications;
select t.ok('준비: 빌드 4개 공개', (select count(*) from builds where counter_id = pg_temp.id('m1') and status = 'approved') = 4);

-- ===== 1. 오류 신고: 누가 낼 수 있나 =====
set role anon;
reset request.jwt.claim.sub;
select t.fails('비로그인: 신고 불가', format($$select report_wiki(%s, %s, 'wrong')$$, pg_temp.id('m1'), pg_temp.id('b2')), 'permission denied');
select t.fails('비로그인: 목록 불가', 'select staff_wiki_reports()', 'permission denied');
reset role;
set role authenticated;
set request.jwt.claim.sub = :'GU';
select t.fails('비회원: 신고 불가', format($$select report_wiki(%s, %s, 'wrong')$$, pg_temp.id('m1'), pg_temp.id('b2')), '구글·카카오로 로그인한 회원만');
set request.jwt.claim.sub = :'U';
select t.fails('회원: 신고 표 직접 못 읽음', 'select * from wiki_reports', 'permission denied');
select t.fails('회원: 신고 표 직접 못 씀', format($$insert into wiki_reports (counter_id, reason) values (%s, 'wrong')$$, pg_temp.id('m1')), 'permission denied');
select t.fails('이유 없음', format('select report_wiki(%s, %s, null)', pg_temp.id('m1'), pg_temp.id('b2')), '신고 이유');
select t.fails('모르는 이유', format($$select report_wiki(%s, %s, 'spam')$$, pg_temp.id('m1'), pg_temp.id('b2')), '신고 이유');
select t.fails('기타는 메모 필수', format($$select report_wiki(%s, %s, 'other', '  ')$$, pg_temp.id('m1'), pg_temp.id('b2')), '기타 이유');
select t.fails('메모 200자 넘으면 불가', format($$select report_wiki(%s, %s, 'wrong', %L)$$, pg_temp.id('m1'), pg_temp.id('b2'), repeat('가', 201)), '200자');
select t.fails('상대법 전체 신고에는 패치·중복 이유 불가', format($$select report_wiki(%s, null, 'duplicate')$$, pg_temp.id('m1')), '신고 이유');
select t.fails('다른 상대법의 빌드 불가', format($$select report_wiki(%s, %s, 'wrong')$$, pg_temp.id('quinn'), pg_temp.id('b2')), '빌드를 찾지 못했습니다');
select t.fails('없는 상대법 불가', $$select report_wiki(999999, null, 'wrong')$$, '상대법을 찾지 못했습니다');
select report_wiki(pg_temp.id('m1'), pg_temp.id('b2'), 'wrong', '  룬이 틀렸어요  ') as r \gset
insert into ids values ('r1', :r);
reset role;
select t.ok('신고 저장 (상대법·빌드·신고자·메모 앞뒤 공백 정리·처리 전)',
  (select counter_id = pg_temp.id('m1') and build_id = pg_temp.id('b2') and reporter_id = :'U' and memo = '룬이 틀렸어요' and status = 'open'
     from wiki_reports where id = pg_temp.id('r1')));
select t.ok('운영진 알림: 운영자·감독관에게 error_reported (상대법·빌드 연결, 이유 문구)',
  (select count(*) from notifications where kind = 'error_reported' and user_id in (:'OP', :'MOD')
     and counter_id = pg_temp.id('m1') and build_id = pg_temp.id('b2') and message = '새 오류 신고가 들어왔습니다. (내용이 틀림)') = 2);
select t.ok('운영진 알림은 신고자·다른 회원에게 안 감', not exists (select 1 from notifications where kind = 'error_reported' and user_id not in (:'OP', :'MOD')));

set role authenticated;
set request.jwt.claim.sub = :'U';
select t.fails('같은 대상에 처리 전 신고 2번 불가', format($$select report_wiki(%s, %s, 'outdated')$$, pg_temp.id('m1'), pg_temp.id('b2')), '이미 신고한');
select t.fails('상대법 번호 없이 빌드만 줘도 같은 대상', format($$select report_wiki(null, %s, 'outdated')$$, pg_temp.id('b2')), '이미 신고한');
set request.jwt.claim.sub = :'V';
insert into ids values ('r2', report_wiki(null, pg_temp.id('b2'), 'outdated'));
insert into ids values ('r3', report_wiki(pg_temp.id('m1'), null, 'vandal', '장난 상대법'));
reset role;
select t.ok('같은 대상의 두 번째 신고는 운영진 알림 없음, 새 대상(상대법 전체)은 알림',
  (select count(*) from notifications where kind = 'error_reported' and build_id = pg_temp.id('b2')) = 2
  and (select count(*) from notifications where kind = 'error_reported' and build_id is null and counter_id = pg_temp.id('m1')) = 2);
select t.ok('빌드 없이 낸 신고는 상대법 전체', (select build_id is null and counter_id = pg_temp.id('m1') from wiki_reports where id = pg_temp.id('r3')));

-- 감독관이 낸 신고: 운영자에게만 알림 (본인 제외)
set role authenticated;
set request.jwt.claim.sub = :'MOD';
insert into ids values ('rm', report_wiki(pg_temp.id('quinn'), null, 'wrong'));
reset role;
select t.ok('감독관이 낸 신고: 운영자에게만 알림', (select array_agg(user_id) from notifications where kind = 'error_reported' and counter_id = pg_temp.id('quinn')) = array[:'OP'::uuid]);

-- 하루 상한 (검사에서는 3건으로 줄여 본다)
update xp_rules set value = 3 where key = 'error_report_daily_cap';
set role authenticated;
set request.jwt.claim.sub = :'W';
select report_wiki(null, pg_temp.id('b1'), 'wrong');
select report_wiki(null, pg_temp.id('b3'), 'wrong');
select report_wiki(pg_temp.id('m1'), null, 'wrong');
select t.fails('하루 상한', format($$select report_wiki(%s, null, 'wrong')$$, pg_temp.id('quinn')), '하루에 3건까지');
reset role;
update wiki_reports set created_at = now() - interval '1 day' where reporter_id = :'W';
set role authenticated;
set request.jwt.claim.sub = :'W';
insert into ids values ('rw', report_wiki(pg_temp.id('quinn'), null, 'wrong'));
reset role;
select t.ok('어제 낸 신고는 오늘 상한에 안 셈', pg_temp.id('rw') is not null);
update xp_rules set value = 10 where key = 'error_report_daily_cap';

-- 숨긴 빌드·숨긴 상대법은 신고 불가
set role authenticated;
set request.jwt.claim.sub = :'OP';
select hide_build(pg_temp.id('b4'), '검사용 숨김');
set request.jwt.claim.sub = :'U';
select t.fails('숨긴 빌드 신고 불가', format($$select report_wiki(null, %s, 'wrong')$$, pg_temp.id('b4')), '빌드를 찾지 못했습니다');
set request.jwt.claim.sub = :'OP';
select restore_build(pg_temp.id('b4'), '다시 공개');
reset role;

-- ===== 2. 목록 (운영진만, 신고자는 운영자에게만) =====
set role authenticated;
set request.jwt.claim.sub = :'U';
select t.fails('회원: 목록 불가', 'select staff_wiki_reports()', '운영자만');
select t.fails('회원: 처리 불가', format($$select handle_wiki_report(%s, 'resolved', '메모')$$, pg_temp.id('r1')), '운영자만');
reset role;
insert into ids select 'oldest', id from wiki_reports where status = 'open' order by created_at, id limit 1;
set role authenticated;
set request.jwt.claim.sub = :'MOD';
select staff_wiki_reports() as l \gset
select t.ok('감독관: 처리 전 8건, 오래된 순', (:'l'::jsonb ->> 'total')::int = 8
  and (:'l'::jsonb -> 'reports' -> 0 ->> 'id')::bigint = pg_temp.id('oldest'));
select t.ok('감독관에게는 신고자가 안 보임', (select bool_and(r -> 'reporter' = 'null'::jsonb) from jsonb_array_elements(:'l'::jsonb -> 'reports') r));
select t.ok('감독관 목록 어디에도 신고자 닉네임이 없음', :'l' !~ '(유저|브이|더블유)');
select t.ok('내가 낸 신고는 mine', (select bool_and((r ->> 'mine')::boolean = ((r ->> 'id')::bigint = pg_temp.id('rm'))) from jsonb_array_elements(:'l'::jsonb -> 'reports') r));
select t.ok('같은 대상의 처리 전 신고 수 (빌드 2 = 2건)', (select (r ->> 'same_open')::int from jsonb_array_elements(:'l'::jsonb -> 'reports') r where (r ->> 'id')::bigint = pg_temp.id('r1')) = 2);
select t.ok('목록에 상대법·빌드 정보', (select r ->> 'target_champion' = 'Darius' and r ->> 'counter_champion' = 'Garen' and (r ->> 'build_seq')::int = 2
  and r ->> 'reason' = 'wrong' and r ->> 'memo' = '룬이 틀렸어요' from jsonb_array_elements(:'l'::jsonb -> 'reports') r where (r ->> 'id')::bigint = pg_temp.id('r1')));
select t.ok('처리 대기 건수 (감독관: 자기가 낸 것 제외 7)', (admin_pending_counts() ->> 'wiki_reports')::int = 7);
select t.fails('모르는 목록 종류', $$select staff_wiki_reports('all')$$, '목록 종류');
select t.ok('쪽 크기 2', jsonb_array_length(staff_wiki_reports('open', 2, 2) -> 'reports') = 2);
set request.jwt.claim.sub = :'OP';
select staff_wiki_reports() as l \gset
select t.ok('운영자에게는 신고자가 보임', (select r -> 'reporter' ->> 'nickname' from jsonb_array_elements(:'l'::jsonb -> 'reports') r where (r ->> 'id')::bigint = pg_temp.id('r1')) = '유저');
select t.ok('처리 대기 건수 (운영자 8, 있던 키도 그대로)', (admin_pending_counts() ->> 'wiki_reports')::int = 8 and admin_pending_counts() ?& array['proposals', 'builds', 'inquiries']);
select t.ok('운영자: 오류 신고 알림이 보임 (대상 5곳)', (select count(*) from notifications where kind = 'error_reported') = 5);
select set_operator_mode(false);
select t.fails('운영자 모드 끔: 목록 불가', 'select staff_wiki_reports()', '운영자만');
select t.fails('운영자 모드 끔: 처리 불가', format($$select handle_wiki_report(%s, 'resolved', '메모')$$, pg_temp.id('r1')), '운영자만');
select t.ok('운영자 모드 끔: 오류 신고 알림이 안 보임', (select count(*) from notifications where kind = 'error_reported') = 0);
select mark_all_notifications_read(9999999);
select set_operator_mode(true);
select t.ok('운영자 모드 끔 동안 [모두 읽음]은 오류 신고 알림을 건드리지 않음',
  (select count(*) from notifications where kind = 'error_reported' and read_at is null) = 5);
reset role;
select t.ok('푸시 묶음: 새 오류 신고 = 운영진 알림, 처리 결과 = 푸시 없음',
  push_group('error_reported') = 'staff_new' and push_group('error_report_handled') is null);

-- ===== 3. 처리 =====
set role authenticated;
set request.jwt.claim.sub = :'MOD';
select t.fails('감독관: 자기가 낸 신고 처리 불가', format($$select handle_wiki_report(%s, 'resolved', '메모')$$, pg_temp.id('rm')), '다른 운영진이');
select t.fails('메모 필수', format($$select handle_wiki_report(%s, 'resolved', '  ')$$, pg_temp.id('r1')), '처리 메모');
select t.fails('처리 결과 필수', format($$select handle_wiki_report(%s, 'open', '메모')$$, pg_temp.id('r1')), '처리 결과');
select t.fails('없는 신고', $$select handle_wiki_report(999999, 'resolved', '메모')$$, '신고를 찾지 못했습니다');
select t.ok('같은 대상 함께 처리: 2건', handle_wiki_report(pg_temp.id('r1'), 'resolved', '룬 고침', true) = 2);
select t.fails('이미 처리된 신고', format($$select handle_wiki_report(%s, 'dismissed', '메모')$$, pg_temp.id('r2')), '이미 처리된');
reset role;
select t.ok('처리 결과 저장 (처리자·시각·메모)', (select bool_and(status = 'resolved' and handled_by = :'MOD' and handled_at is not null and handled_note = '룬 고침')
  from wiki_reports where id in (pg_temp.id('r1'), pg_temp.id('r2'))));
select t.ok('처리 기록 2줄 (resolve_report, 감독관)', (select count(*) from moderation_log
  where action = 'resolve_report' and target_kind = 'wiki_report' and actor_id = :'MOD' and actor_role = 'moderator' and note = '룬 고침'
    and target_id in (pg_temp.id('r1')::text, pg_temp.id('r2')::text)) = 2);
select t.ok('신고자에게 처리 알림 (메모 없이, 빌드 연결)', (select count(*) from notifications where kind = 'error_report_handled'
  and user_id in (:'U', :'V') and build_id = pg_temp.id('b2') and message = '보내 주신 오류 신고를 처리했습니다. 고맙습니다.' and message !~ '룬 고침') = 2);
set role authenticated;
set request.jwt.claim.sub = :'OP';
select t.ok('운영자: 하나만 기각', handle_wiki_report(pg_temp.id('r3'), 'dismissed', '문제 없음') = 1);
select t.ok('운영자는 감독관이 낸 신고도 처리', handle_wiki_report(pg_temp.id('rm'), 'resolved', '고침') = 1);
reset role;
select t.ok('기각 알림 (상대법 전체 → 빌드 없음)', exists (select 1 from notifications where kind = 'error_report_handled' and user_id = :'V'
  and build_id is null and counter_id = pg_temp.id('m1') and message = '보내 주신 오류 신고를 검토했지만 고칠 내용이 없어 기각했습니다.'));
select t.ok('같은 대상이라도 함께 처리를 안 고르면 그 신고만 (W의 상대법 전체 신고는 남음)',
  (select status from wiki_reports where reporter_id = :'W' and counter_id = pg_temp.id('m1') and build_id is null) = 'open');
set role authenticated;
set request.jwt.claim.sub = :'U';
insert into ids values ('r1b', report_wiki(null, pg_temp.id('b2'), 'wrong'));
set request.jwt.claim.sub = :'OP';
select staff_wiki_reports('handled') as l \gset
reset role;
select t.ok('처리된 뒤에는 같은 대상에 다시 신고 가능 + 새 처리 전 신고라 운영진 알림', pg_temp.id('r1b') is not null
  and (select count(*) from notifications where kind = 'error_reported' and build_id = pg_temp.id('b2')) = 4);
select t.ok('처리된 목록: 처리자 표시', (:'l'::jsonb ->> 'total')::int = 4
  and (select r -> 'handler' ->> 'nickname' from jsonb_array_elements(:'l'::jsonb -> 'reports') r where (r ->> 'id')::bigint = pg_temp.id('r1')) = '감독');

-- 1년 정리 (처리 전 신고는 남김)
update wiki_reports set handled_at = now() - interval '366 days' where id in (pg_temp.id('r1'), pg_temp.id('r2'));
update wiki_reports set created_at = now() - interval '400 days' where id = pg_temp.id('rw');
select purge_wiki_reports() as purged \gset
select t.ok('정리: 처리하고 1년 지난 2건만', :purged = 2
  and not exists (select 1 from wiki_reports where id in (pg_temp.id('r1'), pg_temp.id('r2')))
  and exists (select 1 from wiki_reports where id = pg_temp.id('rw')));
set role authenticated;
set request.jwt.claim.sub = :'OP';
select t.fails('정리 함수는 사람이 못 부름', 'select purge_wiki_reports()', 'permission denied');
reset role;

-- ===== 4. 운영자 빌드 수정 기록 =====
-- 브이·더블유가 유저의 빌드 1을 차례로 고친다 (기여자)
set role authenticated;
set request.jwt.claim.sub = :'V';
select edit_build(pg_temp.id('b1'), 1, t.build() || '{"summary":"훼손1","level_notes":{"1":"a","2":"b","3":"c","6":"d"}}'::jsonb);
set request.jwt.claim.sub = :'W';
select edit_build(pg_temp.id('b1'), 2, t.build() || '{"summary":"훼손2","level_notes":{"1":"a","2":"b","3":"c","6":"d"}}'::jsonb);
reset role;
delete from wiki_last_write;
select xp as uxp from profiles where id = :'U' \gset
select t.ok('준비: 기여자 2명', (select count(*) from build_editors where build_id = pg_temp.id('b1')) = 2);

set role anon;
select t.fails('비로그인: 기록 불가', format('select admin_build_revisions(%s)', pg_temp.id('b1')), 'permission denied');
reset role;
set role authenticated;
set request.jwt.claim.sub = :'U';
select t.fails('회원(작성자): 기록 불가', format('select admin_build_revisions(%s)', pg_temp.id('b1')), '운영자만');
select t.fails('회원: 안쪽 함수 못 부름', format('select admin_build_revisions_unchecked(%s, null, 20)', pg_temp.id('b1')), 'permission denied');
set request.jwt.claim.sub = :'MOD';
select t.fails('감독관: 기록 불가', format('select admin_build_revisions(%s)', pg_temp.id('b1')), '운영자만');
set request.jwt.claim.sub = :'OP';
select admin_build_revisions(pg_temp.id('b1')) as h \gset
select t.ok('기록 3줄, 최신 순 (edit·edit·create)', (select array_agg(r ->> 'kind' order by o) from jsonb_array_elements(:'h'::jsonb -> 'revisions') with ordinality x(r, o))
  = array['edit', 'edit', 'create']);
select t.ok('수정자 닉네임·전후 내용', (:'h'::jsonb -> 'revisions' -> 0 -> 'editor' ->> 'nickname') = '더블유'
  and (:'h'::jsonb -> 'revisions' -> 0 -> 'before' ->> 'summary') = '훼손1' and (:'h'::jsonb -> 'revisions' -> 0 -> 'after' ->> 'summary') = '훼손2');
select t.ok('빌드 머리: 버전 3, 작성자 유저, 첫 빌드, 지금 내용', (:'h'::jsonb -> 'build' ->> 'version')::int = 3
  and (:'h'::jsonb -> 'build' -> 'author' ->> 'nickname') = '유저' and (:'h'::jsonb -> 'build' ->> 'is_first')::boolean
  and (:'h'::jsonb -> 'build' -> 'current' ->> 'summary') = '훼손2' and (:'h'::jsonb ->> 'has_more')::boolean = false);
select t.ok('기록에 이메일 글자가 없음', :'h' !~ '@x\.com');
select t.ok('쪽 나누기: 2개 + 더 있음, 다음 쪽 1개', (admin_build_revisions(pg_temp.id('b1'), null, 2) ->> 'has_more')::boolean
  and jsonb_array_length(admin_build_revisions(pg_temp.id('b1'), (admin_build_revisions(pg_temp.id('b1'), null, 2) -> 'revisions' -> 1 ->> 'id')::bigint) -> 'revisions') = 1);
select t.fails('없는 빌드', 'select admin_build_revisions(999999)', '빌드를 찾지 못했습니다');
select set_operator_mode(false);
select t.fails('운영자 모드 끔: 기록 불가', format('select admin_build_revisions(%s)', pg_temp.id('b1')), '운영자만');
select set_operator_mode(true);
reset role;
insert into ids select 'rv_create', id from build_revisions where build_id = pg_temp.id('b1') and kind = 'create';

-- ===== 5. 되돌리기 =====
set role authenticated;
set request.jwt.claim.sub = :'MOD';
select t.fails('감독관: 되돌리기 불가', format($$select revert_build(%s, %s, 3, '훼손')$$, pg_temp.id('b1'), pg_temp.id('rv_create')), '운영자만');
set request.jwt.claim.sub = :'U';
select t.fails('회원: 안쪽 함수 못 부름', format($$select revert_build_unchecked(%s, %s, 3, '훼손')$$, pg_temp.id('b1'), pg_temp.id('rv_create')), 'permission denied');
set request.jwt.claim.sub = :'OP';
select set_operator_mode(false);
select t.fails('운영자 모드 끔: 되돌리기 불가', format($$select revert_build(%s, %s, 3, '훼손')$$, pg_temp.id('b1'), pg_temp.id('rv_create')), '운영자만');
select set_operator_mode(true);
select t.fails('사유 필수', format($$select revert_build(%s, %s, 3, ' ')$$, pg_temp.id('b1'), pg_temp.id('rv_create')), '되돌리는 사유');
select t.fails('본 버전이 옛것이면 TL412', format($$select revert_build(%s, %s, 2, '훼손')$$, pg_temp.id('b1'), pg_temp.id('rv_create')), '먼저 수정했습니다');
select t.fails('다른 빌드의 기록 불가', format($$select revert_build(%s, %s, %s, '훼손')$$, pg_temp.id('b2'), pg_temp.id('rv_create'), t.bv(pg_temp.id('b2'))), '수정 기록을 찾지 못했습니다');
select revert_build(pg_temp.id('b1'), pg_temp.id('rv_create'), 3, '장난 수정 되돌림') as rr \gset
reset role;
select t.ok('되돌리기 결과: 버전 4, 기여자 2명 뺌', (:'rr'::jsonb ->> 'version')::int = 4 and (:'rr'::jsonb ->> 'removed_contributors')::int = 2);
select t.ok('빌드 내용이 처음으로 + 시초·작성자 그대로 + 마지막 수정자 = 운영자',
  (select summary = '요약' and version = 4 and author_id = :'U' and updated_by = :'OP' and status = 'approved' from builds where id = pg_temp.id('b1')));
select t.ok('revert 기록 (전 = 훼손2, 후 = 처음, 기준 기록 번호)', (select count(*) from build_revisions
  where build_id = pg_temp.id('b1') and kind = 'revert' and editor_id = :'OP' and revert_of = pg_temp.id('rv_create')
    and before ->> 'summary' = '훼손2' and after ->> 'summary' = '요약' and version = 4) = 1);
select t.ok('기여자: 되돌린 범위만 고친 두 사람 빠짐, 운영자는 안 들어감', not exists (select 1 from build_editors where build_id = pg_temp.id('b1')));
select t.ok('처리 기록 revert (운영자, 메모)', exists (select 1 from moderation_log
  where action = 'revert' and target_kind = 'build' and target_id = pg_temp.id('b1')::text and actor_id = :'OP' and note = '장난 수정 되돌림'));
select t.ok('경험치 그대로', (select xp from profiles where id = :'U') = :uxp);
select t.ok('되돌려도 작성자·수정자에게 알림 없음', not exists (select 1 from notifications where user_id in (:'U', :'V', :'W')
  and created_at >= (select max(created_at) from build_revisions where kind = 'revert')));
set role authenticated;
set request.jwt.claim.sub = :'W';
select t.fails('편집 중이던 사람(버전 3)은 TL412', format('select edit_build(%s, 3, %L)', pg_temp.id('b1'),
  t.build() || '{"summary":"훼손3","level_notes":{"1":"a","2":"b","3":"c","6":"d"}}'::jsonb), '먼저 수정했습니다');
set request.jwt.claim.sub = :'OP';
select t.fails('지금 내용과 같으면 불가', format($$select revert_build(%s, %s, 4, '같음')$$, pg_temp.id('b1'), pg_temp.id('rv_create')), '지금 내용과 같습니다');
reset role;

-- 일부만 되돌리기: 브이(5) → 더블유(6) → 브이 수정 시점으로 되돌림 = 더블유만 빠짐
set role authenticated;
set request.jwt.claim.sub = :'V';
select edit_build(pg_temp.id('b1'), 4, t.build() || '{"summary":"좋은 수정","level_notes":{"1":"a","2":"b","3":"c","6":"d"}}'::jsonb);
set request.jwt.claim.sub = :'W';
select edit_build(pg_temp.id('b1'), 5, t.build() || '{"summary":"나쁜 수정","level_notes":{"1":"a","2":"b","3":"c","6":"d"}}'::jsonb);
reset role;
delete from wiki_last_write;
insert into ids select 'rv_v5', id from build_revisions where build_id = pg_temp.id('b1') and version = 5;
set role authenticated;
set request.jwt.claim.sub = :'OP';
select t.ok('브이 시점으로 되돌림: 1명(더블유) 뺌', (revert_build(pg_temp.id('b1'), pg_temp.id('rv_v5'), 6, '나쁜 수정') ->> 'removed_contributors')::int = 1);
reset role;
select t.ok('브이는 기여자로 남고 더블유는 빠짐', (select array_agg(user_id) from build_editors where build_id = pg_temp.id('b1')) = array[:'V'::uuid]);
select t.ok('내용 = 좋은 수정', (select summary from builds where id = pg_temp.id('b1')) = '좋은 수정');

-- 그 전에도 고친 사람은 횟수만 준다: 더블유(8) → 브이(9) → 7(되돌리기) 시점으로
--   브이는 5에서 고친 것이 남아 있어 횟수만 2 → 1, 더블유는 그 전 수정(6)이 이미 되돌려져 빠진 상태라 다시 빠짐
set role authenticated;
set request.jwt.claim.sub = :'W';
select edit_build(pg_temp.id('b1'), 7, t.build() || '{"summary":"더블유 둘째","level_notes":{"1":"a","2":"b","3":"c","6":"d"}}'::jsonb);
set request.jwt.claim.sub = :'V';
select edit_build(pg_temp.id('b1'), 8, t.build() || '{"summary":"브이 둘째","level_notes":{"1":"a","2":"b","3":"c","6":"d"}}'::jsonb);
reset role;
delete from wiki_last_write;
insert into ids select 'rv_7', id from build_revisions where build_id = pg_temp.id('b1') and version = 7;
set role authenticated;
set request.jwt.claim.sub = :'OP';
select t.ok('7 시점으로: 1명(더블유) 뺌', (revert_build(pg_temp.id('b1'), pg_temp.id('rv_7'), 9, '되돌림') ->> 'removed_contributors')::int = 1);
reset role;
select t.ok('브이는 남고 횟수만 2 → 1', (select array_agg(user_id::text || ':' || edits) from build_editors where build_id = pg_temp.id('b1')) = array[:'V' || ':1']);

-- 되돌리면 다른 공개 빌드와 같아지는 경우: 빌드 2를 바꾸고, 빌드 1을 빌드 2의 처음 모양으로 → 빌드 2를 처음으로 되돌리기 불가
set role authenticated;
set request.jwt.claim.sub = :'V';
select edit_build(pg_temp.id('b2'), t.bv(pg_temp.id('b2')), t.build(array['6631','3053','3742']) || :'doc'::jsonb);
reset role;
delete from wiki_last_write;
insert into ids select 'rv_b2c', id from build_revisions where build_id = pg_temp.id('b2') and kind = 'create';
insert into ids select 'rv_b4c', id from build_revisions where build_id = pg_temp.id('b4') and kind = 'create';
set role authenticated;
set request.jwt.claim.sub = :'U';
select edit_build(pg_temp.id('b1'), t.bv(pg_temp.id('b1')), t.build(array['6631','3047','3071']) || :'doc'::jsonb);
set request.jwt.claim.sub = :'OP';
select t.fails('되돌리면 다른 공개 빌드와 똑같아지면 불가', format($$select revert_build(%s, %s, %s, '되돌림')$$, pg_temp.id('b2'),
  pg_temp.id('rv_b2c'), t.bv(pg_temp.id('b2'))), '똑같아집니다');
-- 숨긴 빌드도 되돌릴 수 있다
select hide_build(pg_temp.id('b4'), '훼손돼서 숨김');
reset role;
delete from wiki_last_write;
set role authenticated;
set request.jwt.claim.sub = :'OP';
select t.fails('숨긴 빌드: 지금 내용과 같으면 불가 (= 숨긴 빌드도 되돌리기 대상)', format($$select revert_build(%s, %s, %s, '되돌림')$$, pg_temp.id('b4'),
  pg_temp.id('rv_b4c'), t.bv(pg_temp.id('b4'))), '지금 내용과 같습니다');
select restore_build(pg_temp.id('b4'), '다시 공개');
reset role;

-- ===== 6. 감독관의 빌드 숨기기·다시 공개 =====
delete from notifications;
set role authenticated;
set request.jwt.claim.sub = :'U';
select t.fails('회원: 빌드 숨기기 불가', format($$select hide_build(%s, '사유')$$, pg_temp.id('b2')), '운영자만');
set request.jwt.claim.sub = :'MOD';
select t.fails('감독관: 본인이 등록한 빌드 불가', format($$select hide_build(%s, '사유')$$, pg_temp.id('b3')), '감독관이 처리할 수 없습니다');
select t.fails('감독관: 운영자가 등록한 빌드 불가', format($$select hide_build(%s, '사유')$$, pg_temp.id('b4')), '감독관이 처리할 수 없습니다');
select t.fails('감독관: 사유 필수', format($$select hide_build(%s, ' ')$$, pg_temp.id('b2')), '숨기는 사유');
select hide_build(pg_temp.id('b2'), '틀린 룬');
select t.ok('감독관: 자기가 처리할 수 있는 숨긴 빌드를 읽음', (select count(*) from builds where id = pg_temp.id('b2')) = 1);
reset role;
select t.ok('숨김 + 상태 기록 + 처리 기록(감독관) + 작성자 알림',
  (select status from builds where id = pg_temp.id('b2')) = 'hidden'
  and exists (select 1 from build_status_log where build_id = pg_temp.id('b2') and action = 'hide' and actor = :'MOD')
  and exists (select 1 from moderation_log where action = 'hide' and target_kind = 'build' and target_id = pg_temp.id('b2')::text and actor_id = :'MOD' and note = '틀린 룬')
  and exists (select 1 from notifications where user_id = :'V' and kind = 'build_hidden' and build_id = pg_temp.id('b2')));
set role authenticated;
set request.jwt.claim.sub = :'U';
select t.ok('다른 회원은 숨긴 빌드를 못 읽음', (select count(*) from builds where id = pg_temp.id('b2')) = 0);
set request.jwt.claim.sub = :'MOD';
select t.fails('감독관: 다시 공개 메모 필수', format($$select restore_build(%s, ' ')$$, pg_temp.id('b2')), '다시 공개 메모');
select restore_build(pg_temp.id('b2'), '고쳐짐');
reset role;
select t.ok('감독관이 숨긴 것은 감독관이 다시 공개 (처리 기록 restore)', (select status from builds where id = pg_temp.id('b2')) = 'approved'
  and exists (select 1 from moderation_log where action = 'restore' and target_kind = 'build' and target_id = pg_temp.id('b2')::text and actor_id = :'MOD'));
set role authenticated;
set request.jwt.claim.sub = :'OP';
select hide_build(pg_temp.id('b2'), '운영자 숨김');
set request.jwt.claim.sub = :'MOD';
select t.fails('감독관: 운영자가 숨긴 빌드는 다시 공개 불가', format($$select restore_build(%s, '메모')$$, pg_temp.id('b2')), '운영자가 숨긴 것은');
set request.jwt.claim.sub = :'OP';
select restore_build(pg_temp.id('b2'), '다시 공개');
select set_operator_mode(false);
select t.fails('운영자 모드 끔: 빌드 숨기기 불가', format($$select hide_build(%s, '사유')$$, pg_temp.id('b2')), '운영자만');
select set_operator_mode(true);
select t.ok('운영자: 처리 기록에도 남음', exists (select 1 from moderation_log where action = 'hide' and target_kind = 'build' and actor_id = :'OP' and note = '운영자 숨김'));
-- 숨긴 상대법의 빌드는 운영자만 (퀸 상대법: 시초 없음 = 감독관 범위)
select hide_counter(pg_temp.id('quinn'), '상대법 숨김');
set request.jwt.claim.sub = :'MOD';
select t.fails('감독관: 숨긴 상대법의 빌드 불가', format($$select hide_build(%s, '사유')$$, pg_temp.id('qb')), '숨긴 상대법의 빌드는 운영자만');
select t.fails('감독관: 상대법 숨기기는 운영자만 그대로', format($$select restore_counter(%s, '메모')$$, pg_temp.id('quinn')), '운영자만');
reset role;

-- ===== 7. build_edit_check: 빌드 수정 규칙 그대로 =====
set role authenticated;
set request.jwt.claim.sub = :'U';
select t.fails('회원: 수정 권한 도우미 직접 못 부름', format('select build_edit_check(b, %L) from builds b where id = %s', :'U', pg_temp.id('b1')), 'permission denied');
select t.fails('회원: 감독관 범위 도우미 직접 못 부름', format('select require_moderate_build(b) from builds b where id = %s', pg_temp.id('b1')), 'permission denied');
set request.jwt.claim.sub = :'GU';
select t.fails('비회원: 남의 빌드 수정 불가 (그대로)', format('select edit_build(%s, %s, %L)', pg_temp.id('b1'), t.bv(pg_temp.id('b1')),
  t.build() || '{"summary":"손님","level_notes":{"1":"a","2":"b","3":"c","6":"d"}}'::jsonb), '구글·카카오로 로그인한 회원만');
set request.jwt.claim.sub = :'OP';
select hide_build(pg_temp.id('b4'), '숨김');
select t.fails('숨긴 빌드 수정 불가 (그대로)', format('select edit_build(%s, %s, %L)', pg_temp.id('b4'), t.bv(pg_temp.id('b4')),
  t.build(array['6631','3053','3071']) || '{"summary":"고침","level_notes":{"1":"a","2":"b","3":"c","6":"d"}}'::jsonb), '공개된 빌드만');
reset role;

-- ===== 8. 실행 권한 정리 =====
select t.ok('안쪽 함수는 로그인 사용자·비로그인 모두 못 부름', not (
  select bool_or(has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))
    from pg_proc p where p.pronamespace = 'public'::regnamespace
     and p.proname in ('build_edit_check', 'wiki_report_reason_label', 'purge_wiki_reports', 'admin_build_revisions_unchecked',
                       'revert_build_unchecked', 'require_moderate_build')));
select t.ok('바깥 함수: 비로그인 불가, 로그인 사용자 가능', (
  select bool_and(not has_function_privilege('anon', p.oid, 'execute') and has_function_privilege('authenticated', p.oid, 'execute'))
    from pg_proc p where p.pronamespace = 'public'::regnamespace
     and p.proname in ('report_wiki', 'staff_wiki_reports', 'handle_wiki_report', 'admin_build_revisions', 'revert_build')));

\echo 043 오류 신고·되돌리기 검사 끝
