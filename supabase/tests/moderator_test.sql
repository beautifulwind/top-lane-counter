-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 030: 감독관. 지정·해제, 할 수 있는 일, 못 하는 일(직접 호출 포함), 처리 기록, 알림 문구, 경험치
\set ON_ERROR_STOP 1
\set QUIET 1
\set OP  '00000000-0000-0000-0000-00000000000a'
\set MOD '00000000-0000-0000-0000-00000000000b'
\set M2  '00000000-0000-0000-0000-00000000000c'
\set U   '00000000-0000-0000-0000-00000000000d'
\set U2  '00000000-0000-0000-0000-00000000000e'
\set GUEST '00000000-0000-0000-0000-00000000000f'
\set doc '{"summary":"요약","level_notes":{"1":"a","2":"b","3":"c","6":"d","9":"e","11":"f"},"lane_cautions":""}'
insert into auth.users (id, email) values
  (:'OP', 'op@x.com'), (:'MOD', 'm@x.com'), (:'M2', 'm2@x.com'), (:'U', 'u@x.com'), (:'U2', 'u2@x.com'), (:'GUEST', 'g@x.com');
update public.profiles set nickname = '영자', role = 'admin' where id = :'OP';
update public.profiles set nickname = '감독' where id = :'MOD';
update public.profiles set nickname = '감독둘' where id = :'M2';
update public.profiles set nickname = '유저' where id = :'U';
update public.profiles set nickname = '유저둘' where id = :'U2';
update public.profiles set nickname = '비회원', is_guest = true where id = :'GUEST';
update public.xp_rules set value = 0 where key in ('post_interval', 'comment_interval');

-- ===== 1. 지정·해제 =====
set role authenticated;
set request.jwt.claim.sub = :'U';
select t.fails('일반 회원은 지정 불가', format('select set_moderator(%L, true, %L)', :'U', '셀프'), '운영자만');
select t.fails('role 직접 수정 불가', format('update profiles set role = %L where id = auth.uid()', 'moderator'), 'permission denied');
set request.jwt.claim.sub = :'OP';
select t.fails('메모 필수', format('select set_moderator(%L, true, %L)', :'MOD', ' '), '메모');
select t.fails('운영자는 대상 아님', format('select set_moderator(%L, true, %L)', :'OP', '메모'), '운영자는');
select t.fails('비회원은 지정 불가', format('select set_moderator(%L, true, %L)', :'GUEST', '메모'), '정식 회원만');
select t.fails('감독관 아닌 사람 해제', format('select set_moderator(%L, false, %L)', :'U', '메모'), '감독관이 아닙니다');
select set_moderator(:'MOD', true, '신고 담당');
select set_moderator(:'M2', true, '신고 담당 2');
select t.fails('이미 감독관', format('select set_moderator(%L, true, %L)', :'MOD', '또'), '이미 감독관');
reset role;
select t.ok('역할이 바뀜, 레벨은 일반 회원처럼', (select role = 'moderator' and level >= 1 from profiles where id = :'MOD'));
select t.ok('지정 알림: 탈퇴 후 기록 안내 포함', exists (
  select 1 from notifications where user_id = :'MOD' and kind = 'moderator_granted'
    and message = '감독관으로 지정됐습니다. 처리 기록은 탈퇴 후에도 남습니다. 메모: 신고 담당'));
select t.ok('지정 기록', exists (
  select 1 from moderation_log where action = 'grant_moderator' and actor_id = :'OP' and actor_role = 'admin'
    and target_id = :'MOD' and target_nickname = '감독' and note = '신고 담당'));

set role authenticated;
set request.jwt.claim.sub = :'MOD';
select t.fails('감독관은 지정 불가', format('select set_moderator(%L, true, %L)', :'U', '메모'), '운영자만');
select t.fails('감독관은 다른 감독관 해제 불가', format('select set_moderator(%L, false, %L)', :'M2', '메모'), '운영자만');
select t.fails('감독관은 role 직접 수정 불가', format('update profiles set role = %L where id = auth.uid()', 'admin'), 'permission denied');
select t.fails('처리 기록 직접 쓰기 불가', $$insert into moderation_log (actor_role, action, target_kind, target_id) values ('admin', 'hide', 'post', '1')$$, 'permission denied');
select t.ok('감독관은 처리 기록을 못 읽음', (select count(*) = 0 from moderation_log));
select t.fails('내부 기록 함수 호출 불가', $$select log_moderation('hide', 'post', '1', 'x')$$, 'permission denied');
reset role;
set role authenticated;
set request.jwt.claim.sub = :'OP';
select t.fails('운영자도 처리 기록을 고치지 못함', 'delete from moderation_log', 'permission denied');
select t.fails('운영자도 처리 기록을 바꾸지 못함', $$update moderation_log set note = 'x'$$, 'permission denied');
select t.ok('운영자는 처리 기록을 읽음', (select count(*) >= 2 from moderation_log));
reset role;

-- ===== 2. 운영자 전용 함수는 감독관이 직접 불러도 전부 거부 =====
create function pg_temp.op_only_calls() returns table (fn text, sql text) language sql as $$
  select p.proname::text, format('select %s.%I(%s)', 'public', p.proname,
           (select string_agg('null', ', ') from generate_series(1, p.pronargs)))
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and (p.prosrc ~ 'require_operator\(\)' or p.prosrc ~ 'not public\.is_admin\(\)')
    and p.proname not in ('require_operator')
    and p.prorettype <> 'trigger'::regtype;
$$;
create temp table op_only as select * from pg_temp.op_only_calls();
grant select on op_only to authenticated;
select t.ok('운영자 전용 함수 목록이 비어 있지 않고 핵심이 들어 있음', (select count(*) >= 20 from op_only)
  and exists (select 1 from op_only where fn = 'approve_build') and exists (select 1 from op_only where fn = 'hide_counter')
  and exists (select 1 from op_only where fn = 'delete_counter') and exists (select 1 from op_only where fn = 'set_item_prices')
  and exists (select 1 from op_only where fn = 'set_moderator') and exists (select 1 from op_only where fn = 'hide_build')
  and exists (select 1 from op_only where fn = 'revert_doc') and exists (select 1 from op_only where fn = 'reorder_counters')
  and not exists (select 1 from op_only where fn in ('hide_post', 'approve_proposal', 'dismiss_reports')));
set role authenticated;
set request.jwt.claim.sub = :'MOD';
do $$
declare
  r record;
  n integer := 0;
begin
  for r in select * from op_only loop
    begin
      execute r.sql;
      raise exception 'FAIL 감독관이 호출 성공: %', r.fn;
    exception when insufficient_privilege then
      n := n + 1;
    end;
  end loop;
  raise notice 'PASS  감독관 직접 호출 %개 모두 거부', n;
end;
$$;
reset role;

-- ===== 3. 준비: 글·댓글 =====
set role authenticated;
set request.jwt.claim.sub = :'U';
select public.create_post('유저 글', '본문') as p_u \gset
select public.create_comment(:p_u, '유저 댓글') as c_u \gset
select public.create_doc_comment((select id from counters where counter_champion = 'Quinn'), '유저 문서 댓글') as d_u \gset
set request.jwt.claim.sub = :'U2';
select public.report_post(:p_u, 'spam', null);
set request.jwt.claim.sub = :'MOD';
select public.create_post('감독 글', '본문') as p_m \gset
select public.create_comment(:p_u, '감독 댓글') as c_m \gset
set request.jwt.claim.sub = :'M2';
select public.create_post('감독둘 글', '본문') as p_m2 \gset
select public.create_comment(:p_u, '감독둘 댓글') as c_m2 \gset
set request.jwt.claim.sub = :'OP';
select public.create_post('운영자 글', '본문') as p_op \gset
select public.create_comment(:p_u, '운영자 댓글') as c_op \gset
set request.jwt.claim.sub = :'U';
select public.report_post(:p_m, 'spam', null);
select public.report_post(:p_op, 'spam', null);
select public.report_comment(:c_m2, 'spam', null);
reset role;

-- ===== 4. 숨김·다시 공개 =====
set role authenticated;
set request.jwt.claim.sub = :'MOD';
select t.fails('본인 글 숨김 불가', format('select hide_post(%s, %L)', :p_m, '메모'), '본인이나 운영진');
select t.fails('다른 감독관 글 숨김 불가', format('select hide_post(%s, %L)', :p_m2, '메모'), '본인이나 운영진');
select t.fails('운영자 글 숨김 불가', format('select hide_post(%s, %L)', :p_op, '메모'), '본인이나 운영진');
select t.fails('다른 감독관 댓글 숨김 불가', format('select hide_comment(%s, %L)', :c_m2, '메모'), '본인이나 운영진');
select t.fails('운영자 댓글 숨김 불가', format('select hide_comment(%s, %L)', :c_op, '메모'), '본인이나 운영진');
select t.fails('메모 필수', format('select hide_post(%s, %L)', :p_u, ' '), '숨기는 이유');
select hide_post(:p_u, '광고');
select hide_comment(:c_u, '욕설');
select hide_doc_comment(:d_u, '욕설');
select t.ok('숨긴 일반 회원 글·댓글을 읽음', exists (select 1 from posts where id = :p_u) and exists (select 1 from post_comments where id = :c_u) and exists (select 1 from doc_comments where id = :d_u));
reset role;
select t.ok('글 숨김 알림은 운영진', (select message = '내 글 「유저 글」을 운영진이 숨겼습니다. 메모: 광고' from notifications where user_id = :'U' and kind = 'post_hidden'));
select t.ok('댓글 숨김 알림은 운영진', (select message like '%내 댓글을 운영진이 숨겼습니다%' from notifications where user_id = :'U' and kind = 'comment_hidden'));
select t.ok('문서 댓글 숨김 알림은 운영진', (select message like '%운영진이 숨겼습니다%' from notifications where user_id = :'U' and kind = 'doc_comment_hidden'));
select t.ok('어느 알림에도 처리자·감독관 글자 없음', not exists (select 1 from notifications where user_id = :'U' and (message like '%감독%' or message like '%운영자가%')));
select t.ok('처리 기록에 누가 남음', (select count(*) = 3 from moderation_log where action = 'hide' and actor_id = :'MOD' and actor_nickname = '감독' and actor_role = 'moderator'));
select t.ok('숨기면 신고는 처리됨', (select status = 'resolved' from reports where post_id = :p_u));

set role authenticated;
set request.jwt.claim.sub = :'U2';
select t.ok('일반 회원은 숨긴 글을 못 읽음', not exists (select 1 from posts where id = :p_u));
set request.jwt.claim.sub = :'M2';
select t.ok('다른 감독관도 숨긴 일반 회원 글을 읽음', exists (select 1 from posts where id = :p_u));
select restore_post(:p_u, '오해였음');
select t.ok('다른 감독관이 숨긴 글은 다시 공개 가능', (select status = 'visible' from posts where id = :p_u));
reset role;
select t.ok('다시 공개 기록', exists (select 1 from moderation_log where action = 'restore' and target_kind = 'post' and actor_id = :'M2' and note = '오해였음'));

-- 운영자가 숨긴 것
set role authenticated;
set request.jwt.claim.sub = :'OP';
select hide_post(:p_u, '운영자 판단');
select hide_post(:p_m, '감독관 글도 운영자는 숨김');
set request.jwt.claim.sub = :'MOD';
select t.fails('운영자가 숨긴 일반 회원 글은 다시 공개 불가', format('select restore_post(%s, %L)', :p_u, '메모'), '운영자가 숨긴');
select t.fails('숨겨진 본인 글을 직접 다시 공개 불가', format('select restore_post(%s, %L)', :p_m, '메모'), '본인이나 운영진');
select t.ok('숨겨진 본인 글은 읽지도 못함', not exists (select 1 from posts where id = :p_m));
set request.jwt.claim.sub = :'OP';
select restore_post(:p_u, '운영자 복구');
select restore_post(:p_m, '운영자 복구');
reset role;

-- ===== 5. 신고 =====
set role authenticated;
set request.jwt.claim.sub = :'OP';
select t.ok('운영자는 신고 표를 그대로 읽음', (select count(*) >= 3 from reports));
set request.jwt.claim.sub = :'U';
select public.report_post(:p_m2, 'spam', '감독둘 글 신고');
set request.jwt.claim.sub = :'MOD';
select t.ok('감독관은 신고 표를 직접 못 읽음', (select count(*) = 0 from reports));
select t.ok('목록에 운영진 대상 신고 없음', not exists (
  select 1 from jsonb_array_elements(open_reports_for_moderator()) e
  where (e -> 'post' ->> 'id')::bigint in (:p_m, :p_m2, :p_op) or (e -> 'comment' ->> 'id')::bigint in (:c_m2, :c_op)));
select t.fails('본인 대상 신고 기각 불가', format('select dismiss_reports(%s, null, %L)', :p_m, '메모'), '본인이나 운영진');
select t.fails('운영자 대상 신고 기각 불가', format('select dismiss_reports(%s, null, %L)', :p_op, '메모'), '본인이나 운영진');
select t.fails('다른 감독관 대상 신고 기각 불가', format('select dismiss_reports(null, %s, %L)', :c_m2, '메모'), '본인이나 운영진');
reset role;
-- 일반 회원 글에 새 신고 → 감독관이 목록에서 보고 기각
set role authenticated;
set request.jwt.claim.sub = :'U';
select public.create_post('두번째 글', '본문') as p_u2 \gset
set request.jwt.claim.sub = :'U2';
select public.report_post(:p_u2, 'spam', '광고 같아요');
set request.jwt.claim.sub = :'MOD';
select t.ok('목록에 일반 회원 글 신고가 보이고 신고자는 없음', (
  select e -> 'reporter' = 'null'::jsonb and e ->> 'detail' = '광고 같아요' and e -> 'post' -> 'author' ->> 'nickname' = '유저'
  from jsonb_array_elements(open_reports_for_moderator()) e where (e ->> 'post_id')::bigint = :p_u2));
select t.ok('숨김 횟수는 감독관도 봄', (hide_counts(array[:'U']::uuid[]) ? 'counts'));
select dismiss_reports(:p_u2, null, '문제없음');
reset role;
select t.ok('신고 기각 기록', exists (select 1 from moderation_log where action = 'dismiss_reports' and target_id = :'p_u2' and actor_id = :'MOD' and note = '문제없음'));
set role authenticated;
set request.jwt.claim.sub = :'U';
select t.fails('일반 회원은 감독관 신고 목록 불가', 'select open_reports_for_moderator()', '감독관만');
select t.fails('일반 회원은 숨김 불가', format('select hide_post(%s, %L)', :p_m, '메모'), '운영자만');
select t.fails('일반 회원은 숨김 횟수 불가', format('select hide_counts(array[%L]::uuid[])', :'U'), '운영자만');
reset role;

-- ===== 6. 새 카운터 제안 승인·반려 + 경험치 =====
set role authenticated;
set request.jwt.claim.sub = :'U';
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Garen', auth.uid(), :'doc', t.build()) returning id as np \gset
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Teemo', auth.uid(), :'doc', t.build()) returning id as np_reject \gset
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Vayne', auth.uid(), :'doc', t.build()) returning id as np_rev \gset
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Ornn', auth.uid(), :'doc', t.build()) returning id as np_edit \gset
insert into edit_proposals (type, counter_id, target_champion, counter_champion, proposer_id, content)
values ('doc_edit', (select id from counters where counter_champion = 'Quinn'), 'Darius', 'Quinn', auth.uid(),
  '{"summary":"문서 수정","level_notes":{"1":"a","2":"b","3":"c","6":"d","9":"e","11":"f"},"lane_cautions":""}') returning id as de \gset
set request.jwt.claim.sub = :'MOD';
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Malphite', auth.uid(), :'doc', t.build()) returning id as np_self \gset
set request.jwt.claim.sub = :'M2';
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Kayle', auth.uid(), :'doc', t.build()) returning id as np_m2 \gset
reset role;
select xp as mod_xp_before from profiles where id = :'MOD' \gset

set role authenticated;
set request.jwt.claim.sub = :'MOD';
select t.fails('본인 제안 승인 불가', format('select approve_proposal(%s, %L, null, null, t.pv(%s))', :np_self, '셀프', :np_self), '처리할 수 없는 제안');
select t.fails('본인 제안 반려 불가', format('select reject_proposal(%s, %L, t.pv(%s))', :np_self, '셀프', :np_self), '처리할 수 없는 제안');
select t.fails('다른 감독관 제안 승인 불가', format('select approve_proposal(%s, %L, null, null, t.pv(%s))', :np_m2, '메모', :np_m2), '처리할 수 없는 제안');
select t.fails('문서 수정 제안 승인 불가', format('select approve_proposal(%s, %L, null, null, t.pv(%s))', :de, '메모', :de), '처리할 수 없는 제안');
select t.fails('문서 수정 제안 반려 불가', format('select reject_proposal(%s, %L, t.pv(%s))', :de, '메모', :de), '처리할 수 없는 제안');
select t.fails('승인 메모 필수', format('select approve_proposal(%s, %L, null, null, t.pv(%s))', :np, ' ', :np), '승인 메모');
select t.fails('반려 사유 필수', format('select reject_proposal(%s, %L, t.pv(%s))', :np_reject, ' ', :np_reject), '거절 사유');
-- 고쳐서 승인: 033부터, 재검토 요청: 036부터 감독관도 가능하다 (admin_convenience_test.sql, member_info_test.sql)
select t.ok('읽기: 대기 중인 새 카운터는 보임', exists (select 1 from edit_proposals where id = :np));
select t.ok('읽기: 문서 수정 제안은 안 보임', not exists (select 1 from edit_proposals where id = :de));
select t.ok('읽기: 다른 감독관 제안은 안 보임', not exists (select 1 from edit_proposals where id = :np_m2));
select approve_proposal(:np, '좋은 카운터입니다', null, null, t.pv(:np)) as garen \gset
select reject_proposal(:np_reject, '근거가 부족합니다', t.pv(:np_reject));
reset role;

select t.ok('승인: 카운터가 공개되고 첫 빌드도 공개', (select status = 'approved' from counters where id = :garen)
  and exists (select 1 from builds where counter_id = :garen and status = 'approved' and proposal_id = :np));
select t.ok('경험치: 제안자에게 +100', exists (select 1 from xp_events where user_id = :'U' and source_key = 'proposal:' || :np and amount = 100));
select t.ok('경험치: 첫 빌드는 따로 없음', not exists (select 1 from xp_events where user_id = :'U' and type = 'build'));
select t.ok('경험치: 승인한 감독관은 그대로', (select xp = :mod_xp_before from profiles where id = :'MOD')
  and not exists (select 1 from xp_events where user_id = :'MOD' and ref_id = :np::text));
select t.ok('처리자는 제안자·공개 빌드에서 읽는 칸에 남지 않음', (select reviewed_by is null and reviewed_at is not null from edit_proposals where id = :np)
  and (select reviewed_by is null from edit_proposals where id = :np_reject)
  and not exists (select 1 from builds where proposal_id = :np and reviewed_by is not null));
select t.ok('승인·반려 기록은 처리 기록에', exists (select 1 from moderation_log where action = 'approve_proposal' and target_id = :np::text and actor_id = :'MOD' and note = '좋은 카운터입니다')
  and exists (select 1 from moderation_log where action = 'reject_proposal' and target_id = :np_reject::text and actor_id = :'MOD' and note = '근거가 부족합니다'));
select t.ok('제안자 알림', exists (select 1 from notifications where user_id = :'U' and kind = 'proposal_approved' and proposal_id = :np and message = '좋은 카운터입니다'));

-- 운영자가 숨긴 카운터 재검토 제안은 감독관이 처리 못 함 + 운영자는 그대로 처리자가 남음
set role authenticated;
set request.jwt.claim.sub = :'OP';
select approve_proposal(:np_rev, '운영자 승인', null, null, t.pv(:np_rev)) as vayne \gset
reset role;
select t.ok('운영자가 처리하면 reviewed_by 그대로', (select reviewed_by = :'OP' from edit_proposals where id = :np_rev));
select t.ok('운영자 처리도 기록', exists (select 1 from moderation_log where action = 'approve_proposal' and target_id = :np_rev::text and actor_role = 'admin'));
set role authenticated;
set request.jwt.claim.sub = :'OP';
select hide_counter(:vayne, '숨김');
select request_revision(:vayne, '고쳐 주세요');
set request.jwt.claim.sub = :'U';
select resubmit_proposal(:np_rev, :'doc'::jsonb || '{"summary":"고침"}', t.build(array['6631','3047','3071']));
set request.jwt.claim.sub = :'MOD';
select t.ok('숨긴 카운터 재검토 제안은 안 보임', not exists (select 1 from edit_proposals where id = :np_rev));
select t.fails('숨긴 카운터 재검토 제안 승인 불가', format('select approve_proposal(%s, %L, null, null, t.pv(%s))', :np_rev, '메모', :np_rev), '처리할 수 없는 제안');
select t.fails('숨긴 카운터 재검토 제안 반려 불가', format('select reject_proposal(%s, %L, t.pv(%s))', :np_rev, '메모', :np_rev), '처리할 수 없는 제안');
select t.fails('숨긴 카운터 재검토 제안 재검토 요청 불가', format('select request_proposal_revision(%s, %L, t.pv(%s))', :np_rev, '메모', :np_rev), '처리할 수 없는 제안');
reset role;

-- 숨긴 카운터의 문서 댓글은 운영자만
set role authenticated;
set request.jwt.claim.sub = :'U';
select public.create_doc_comment(:garen, '가렌 문서 댓글') as d_g \gset
set request.jwt.claim.sub = :'OP';
select hide_counter(:garen, '숨김');
set request.jwt.claim.sub = :'MOD';
select t.ok('숨긴 카운터의 문서 댓글은 안 보임', not exists (select 1 from doc_comments where id = :d_g));
select t.fails('숨긴 카운터의 문서 댓글 숨김 불가', format('select hide_doc_comment(%s, %L)', :d_g, '메모'), '숨긴 상대법');
reset role;
select t.ok('카운터를 숨기면 제안자 +100 회수 (운영자의 되돌리기)', (select coalesce(sum(amount), 0) = 0 from xp_events where user_id = :'U' and source_key = 'proposal:' || :np));

-- 감독관 자신의 경험치·칭호는 일반 회원처럼
set role authenticated;
set request.jwt.claim.sub = :'OP';
select approve_proposal(:np_self, '운영자가 처리', null, null, t.pv(:np_self));
reset role;
select t.ok('감독관도 본인 기여 경험치를 받음', (select xp >= 100 and level >= 1 from profiles where id = :'MOD'));

-- ===== 7. 해제하면 바로 권한이 사라짐 =====
set role authenticated;
set request.jwt.claim.sub = :'U';
select public.create_post('세번째 글', '본문') as p_u3 \gset
set request.jwt.claim.sub = :'OP';
select set_moderator(:'M2', false, '담당 종료');
set request.jwt.claim.sub = :'M2';
select t.fails('해제 후 숨김 불가', format('select hide_post(%s, %L)', :p_u3, '메모'), '운영자만');
select t.fails('해제 후 신고 목록 불가', 'select open_reports_for_moderator()', '감독관만');
select t.ok('해제 후 대기 제안 안 보임', not exists (select 1 from edit_proposals where id = :np_edit));
reset role;
select t.ok('해제 알림과 기록', exists (select 1 from notifications where user_id = :'M2' and kind = 'moderator_revoked')
  and exists (select 1 from moderation_log where action = 'revoke_moderator' and target_id = :'M2' and note = '담당 종료'));

-- ===== 8. 탈퇴해도 처리 기록은 남음 =====
delete from auth.users where id = :'MOD';
select t.ok('탈퇴 후에도 처리자 id·닉네임이 남음', (select count(*) >= 3 from moderation_log where actor_id = :'MOD' and actor_nickname = '감독'));

-- ===== 9. 자유게시판 목록의 작성자에도 role =====
select t.ok('board_page 작성자에 role', exists (
  select 1 from jsonb_array_elements(board_page(null, 1, 50) -> 'rows') e where e -> 'author' ->> 'role' = 'admin'));

-- ===== 10. 닉네임 금지는 그대로 =====
set role authenticated;
set request.jwt.claim.sub = :'U2';
select t.fails('(운) 금지', format('update profiles set nickname = %L where id = auth.uid()', '유저(운)'), '쓸 수 없습니다');
select t.fails('(감) 금지', format('update profiles set nickname = %L where id = auth.uid()', '유저(감)'), '쓸 수 없습니다');
reset role;
