-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 033: 관리자 편의. 새 제안·빌드·문의 알림(운영자/감독관 범위, 계정·탈퇴 제외, 본인 제외),
--      처리 대기 건수(역할별), 감독관도 고쳐서 승인 + 처리 기록(edit_proposal), 검토 중 표시·버전 확인과 함께 동작
\set ON_ERROR_STOP 1
\set QUIET 1
\set OP  '00000000-0000-0000-0000-00000000000a'
\set MOD '00000000-0000-0000-0000-00000000000b'
\set M2  '00000000-0000-0000-0000-00000000000c'
\set U   '00000000-0000-0000-0000-00000000000d'
\set U2  '00000000-0000-0000-0000-00000000000e'
\set doc '{"summary":"요약","level_notes":{"1":"a","2":"b","3":"c","6":"d","9":"e","11":"f"},"lane_cautions":""}'
\set runes '{"primaryPath":8000,"keystone":8010,"primary":[9111,9104,8299],"secondaryPath":8400,"secondary":[8444,8242],"shards":[5005,5008,5011]}'
insert into auth.users (id, email) values
  (:'OP', 'op@x.com'), (:'MOD', 'm@x.com'), (:'M2', 'm2@x.com'), (:'U', 'u@x.com'), (:'U2', 'u2@x.com');
update public.profiles set nickname = '영자', role = 'admin' where id = :'OP';
update public.profiles set nickname = '감독', role = 'moderator' where id = :'MOD';
update public.profiles set nickname = '감독둘', role = 'moderator' where id = :'M2';
update public.profiles set nickname = '유저' where id = :'U';
update public.profiles set nickname = '유저둘' where id = :'U2';
update public.xp_rules set value = 0 where key in ('post_interval', 'comment_interval');

-- ===== 1. 알림 종류와 권한 =====
select t.ok('알림 종류 3개 추가', (select pg_get_constraintdef(oid) like '%proposal_submitted%' and pg_get_constraintdef(oid) like '%build_submitted%'
  and pg_get_constraintdef(oid) like '%inquiry_received%' and pg_get_constraintdef(oid) like '%inquiry_answered%'
  from pg_constraint where conname = 'notifications_kind_check' and conrelid = 'public.notifications'::regclass));
select t.ok('처리 기록 종류 edit_proposal 추가', (select pg_get_constraintdef(oid) like '%edit_proposal%' and pg_get_constraintdef(oid) like '%move_inquiry%'
  from pg_constraint where conname = 'moderation_log_action_check' and conrelid = 'public.moderation_log'::regclass));
set role authenticated;
set request.jwt.claim.sub = :'U';
select t.fails('알림 보내기 도우미는 직접 못 부름', $$select notify_staff('proposal_submitted', 'x', null, null, true)$$, 'permission denied');
select t.fails('고친 곳 설명 함수도 직접 못 부름', $$select describe_proposal_edit('{}', '{}', null, null)$$, 'permission denied');
select t.fails('일반 회원은 처리 대기 건수 불가', 'select admin_pending_counts()', '운영자만');
set role anon;
select t.fails('비로그인은 처리 대기 건수 불가', 'select admin_pending_counts()', 'permission denied');
reset role;

-- ===== 2. 새 제안 알림 =====
set role authenticated;
set request.jwt.claim.sub = :'U';
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Garen', auth.uid(), :'doc', t.build()) returning id as np \gset
insert into edit_proposals (type, counter_id, target_champion, counter_champion, proposer_id, content)
values ('doc_edit', (select id from counters where counter_champion = 'Quinn'), 'Darius', 'Quinn', auth.uid(), :'doc') returning id as de \gset
reset role;
select t.ok('새 카운터 제안: 운영자·감독관 모두에게',
  (select count(*) = 3 from notifications where proposal_id = :np and kind = 'proposal_submitted' and message = '새 상대법 제안이 들어왔습니다.'
     and user_id in (:'OP', :'MOD', :'M2')));
select t.ok('새 제안: 제안자 본인에게는 안 감', not exists (select 1 from notifications where user_id = :'U' and kind = 'proposal_submitted'));
select t.ok('문서 수정 제안: 운영자에게만 (감독관은 처리 못 함)',
  exists (select 1 from notifications where user_id = :'OP' and proposal_id = :de and kind = 'proposal_submitted' and message = '문서 수정 제안이 들어왔습니다.')
  and not exists (select 1 from notifications where user_id in (:'MOD', :'M2') and proposal_id = :de));
select t.ok('일반 회원 U2에게는 안 감', not exists (select 1 from notifications where user_id = :'U2' and kind in ('proposal_submitted', 'build_submitted', 'inquiry_received')));

-- 감독관이 낸 새 카운터 제안: 운영자에게만 (다른 감독관은 운영진 제안을 처리할 수 없다), 낸 본인은 제외
set role authenticated;
set request.jwt.claim.sub = :'MOD';
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Teemo', auth.uid(), :'doc', t.build()) returning id as np_mod \gset
reset role;
select t.ok('감독관의 제안: 운영자에게만', exists (select 1 from notifications where user_id = :'OP' and proposal_id = :np_mod)
  and not exists (select 1 from notifications where user_id in (:'MOD', :'M2') and proposal_id = :np_mod));
-- 운영자가 낸 제안: 감독관은 못 처리하므로 안 감, 본인에게도 안 감
set role authenticated;
set request.jwt.claim.sub = :'OP';
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Ornn', auth.uid(), :'doc', t.build()) returning id as np_op \gset
reset role;
select t.ok('운영자의 제안: 아무에게도 안 감', not exists (select 1 from notifications where proposal_id = :np_op));

-- 재검토 요청 → 제안자가 고쳐서 다시 냄: 운영자에게 알림 (재검토 중에는 다시 안 울림)
set role authenticated;
set request.jwt.claim.sub = :'OP';
select request_proposal_revision(:de, '근거를 적어 주세요', t.pv(:de));
reset role;
select count(*) as before_resubmit from notifications where kind = 'proposal_submitted' \gset
set role authenticated;
set request.jwt.claim.sub = :'U';
select resubmit_proposal(:de, '{"summary":"다시","level_notes":{"1":"a","2":"b","3":"c","6":"d"}}', null);
reset role;
select t.ok('다시 낸 제안: 운영자에게 한 번', (select count(*) = :before_resubmit + 1 from notifications where kind = 'proposal_submitted')
  and exists (select 1 from notifications where user_id = :'OP' and proposal_id = :de and message = '재검토 후 다시 낸 제안이 들어왔습니다.'));
-- 요청 취소(원래대로 대기)는 새 제안이 아니다
set role authenticated;
set request.jwt.claim.sub = :'U';
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Yone', auth.uid(), :'doc', t.build()) returning id as np_cancel \gset
set request.jwt.claim.sub = :'OP';
select request_proposal_revision(:np_cancel, '확인', t.pv(:np_cancel));
reset role;
select count(*) as before_cancel from notifications where kind = 'proposal_submitted' \gset
set role authenticated;
set request.jwt.claim.sub = :'OP';
select cancel_proposal_revision(:np_cancel, '취소');
reset role;
select t.ok('재검토 요청 취소는 새 제안 알림 아님', (select count(*) = :before_cancel from notifications where kind = 'proposal_submitted'));

-- ===== 3. 새 빌드 알림 (운영자만) =====
set role authenticated;
set request.jwt.claim.sub = :'U';
insert into builds (counter_id, author_id, runes, summoner_spells, starting_items, core_items, max_skill, patch)
select id, auth.uid(), :'runes', array['SummonerFlash','SummonerTeleport'], array['1055','2003'], array['6631','3047','3053'], 'Q', '16.21.1'
from counters where counter_champion = 'Quinn' returning id as bd \gset
reset role;
select t.ok('새 빌드: 운영자에게만', exists (select 1 from notifications where user_id = :'OP' and build_id = :bd and kind = 'build_submitted' and message = '새 빌드 제안이 들어왔습니다.')
  and not exists (select 1 from notifications where user_id in (:'MOD', :'M2', :'U') and build_id = :bd));

-- ===== 4. 새 문의 알림 =====
set role authenticated;
set request.jwt.claim.sub = :'U';
select create_inquiry('bug', '오류가 납니다 확인해 주세요') as q_bug \gset
select create_inquiry('account', '계정 문의입니다 계정') as q_acc \gset
reset role;
select t.ok('일반 문의: 운영자·감독관 모두에게, 문장에 분류', (select count(*) = 3 from notifications where kind = 'inquiry_received'
  and message = '새 문의가 들어왔습니다. (분류: 오류 신고)' and user_id in (:'OP', :'MOD', :'M2')));
select t.ok('계정·탈퇴 문의: 운영자에게만', exists (select 1 from notifications where user_id = :'OP' and message = '새 문의가 들어왔습니다. (분류: 계정·탈퇴)')
  and not exists (select 1 from notifications where user_id in (:'MOD', :'M2') and message like '%계정·탈퇴%'));
select t.ok('보낸 사람에게는 안 감', not exists (select 1 from notifications where user_id = :'U' and kind = 'inquiry_received'));
-- 분류 옮기기: 계정·탈퇴 → 다른 분류면 감독관에게 새로 알림, 반대로 옮기는 것은 알리지 않는다
select count(*) as before_move from notifications where kind = 'inquiry_received' \gset
set role authenticated;
set request.jwt.claim.sub = :'OP';
select set_inquiry_category(:q_acc, 'other');
reset role;
select t.ok('계정·탈퇴 → 기타: 감독관 둘에게 알림', (select count(*) = :before_move + 2 from notifications where kind = 'inquiry_received')
  and (select count(*) = 2 from notifications where kind = 'inquiry_received' and message = '새 문의가 들어왔습니다. (분류: 기타)' and user_id in (:'MOD', :'M2')));
select count(*) as before_back from notifications where kind = 'inquiry_received' \gset
set role authenticated;
set request.jwt.claim.sub = :'OP';
select set_inquiry_category(:q_acc, 'account');
select set_inquiry_category(:q_bug, 'idea');
reset role;
select t.ok('기타 → 계정·탈퇴, 건의로 옮기기는 알림 없음', (select count(*) = :before_back from notifications where kind = 'inquiry_received'));

-- ===== 5. 처리 대기 건수 =====
-- 지금: 대기 제안 = np(U) · de(U, 다시 냄) · np_mod · np_op · np_cancel(요청 취소됨=대기) 5개, 대기 빌드 1개
--       답변 대기 문의 2개(U): 건의 1, 계정·탈퇴 1
set role authenticated;
set request.jwt.claim.sub = :'OP';
select t.ok('운영자: 제안 5 · 빌드 1 · 문의 2', admin_pending_counts() = '{"proposals":5,"builds":1,"inquiries":2,"wiki_reports":0,"influencers":0}'::jsonb);  -- 043: 오류 신고 건수 키 · 046: 장인 신청 건수 키
set request.jwt.claim.sub = :'MOD';
-- 감독관(MOD): 다른 일반 회원의 새 카운터만 = np · np_cancel (본인 제안 np_mod, 운영자 제안 np_op, 문서 수정 de 제외), 계정·탈퇴 문의 제외
select t.ok('감독관: 제안 2 · 빌드 0 · 문의 1', admin_pending_counts() = '{"proposals":2,"builds":0,"inquiries":1,"wiki_reports":0,"influencers":0}'::jsonb);  -- 043: 오류 신고 건수 키 · 046: 장인 신청 건수 키(감독관은 늘 0)
reset role;

-- ===== 6. 감독관도 고쳐서 승인 + 처리 기록 =====
set role authenticated;
set request.jwt.claim.sub = :'MOD';
select jsonb_typeof(start_proposal_review(:np)) as seen \gset
reset role;
select t.ok('감독관: 검토 중 표시를 남길 수 있음', exists (select 1 from proposal_reviewing where proposal_id = :np and user_id = :'MOD'));
set role authenticated;
set request.jwt.claim.sub = :'MOD';
select t.fails('남의 제안이 아닌 것(문서 수정)은 고쳐도 승인 불가', format('select approve_proposal(%s, %L, %L::jsonb, null, t.pv(%s))', :de, '메모', :'doc', :de), '처리할 수 없는 제안');
select t.fails('본인 제안은 고쳐도 승인 불가', format('select approve_proposal(%s, %L, %L::jsonb, null, t.pv(%s))', :np_mod, '메모', :'doc', :np_mod), '처리할 수 없는 제안');
select t.fails('고친 글이 규칙에 어긋나면 거부', format('select approve_proposal(%s, %L, %L::jsonb, null, t.pv(%s))', :np, '메모',
  '{"summary":"","level_notes":{"1":"a"},"lane_cautions":""}', :np), '한 줄 요약');
-- 제안자가 방금 고친 경우(버전 불일치)에는 고친 내용도 거부 (덮어쓰지 않는다)
select t.fails('버전이 다르면 거부', format('select approve_proposal(%s, %L, %L::jsonb, null, %s)', :np, '메모',
  '{"summary":"감독관이 바꾼 글","level_notes":{"1":"a","2":"b","3":"c","6":"새 내용","9":"e","11":"f"},"lane_cautions":"조심"}', t.pv(:np) + 1), '방금 고쳤');
select t.ok('거부되면 처리 기록도 안 남음', not exists (select 1 from moderation_log where action = 'edit_proposal'));
select approve_proposal(:np, '조금 고쳐서 승인합니다', '{"summary":"감독관이 바꾼 글","level_notes":{"1":"a","2":"b","3":"c","6":"새 내용","9":"e","11":"f","12":"추가"},"lane_cautions":"조심"}'::jsonb,
  (t.build(array['6631','3047','3071']) - 'patch') || '{"patch":"16.21.1"}', t.pv(:np)) as garen \gset
reset role;
select t.ok('고친 내용으로 공개 + 원래 제안은 그대로, 고친 내용은 approved_content에', (select status = 'approved' and content ->> 'summary' = '요약'
  and approved_content ->> 'summary' = '감독관이 바꾼 글' and approved_build is not null and reviewed_by is null from edit_proposals where id = :np)
  and (select summary = '감독관이 바꾼 글' and lane_cautions = '조심' from matchup_docs where counter_id = :garen));
select t.ok('처리 기록 edit_proposal: 누가 · 어느 제안 · 무엇을', exists (select 1 from moderation_log where action = 'edit_proposal' and target_kind = 'proposal'
  and target_id = :np::text and actor_id = :'MOD' and actor_role = 'moderator'
  and note = '고친 곳: 한 줄 요약, 6·12레벨 딜교법, 특이사항, 핵심 템트리'));
select t.ok('승인 기록도 따로 있음', exists (select 1 from moderation_log where action = 'approve_proposal' and target_id = :np::text and actor_id = :'MOD'));
select t.ok('처리하면 검토 중 표시가 지워짐', not exists (select 1 from proposal_reviewing where proposal_id = :np));
select t.ok('제안자에게 승인 알림', exists (select 1 from notifications where user_id = :'U' and kind = 'proposal_approved' and proposal_id = :np));
select t.ok('알림 문장은 운영자와 감독관을 구분하지 않음', not exists (select 1 from notifications where user_id = :'U' and (message like '%감독%')));

-- 안 고치고 승인하면 edit_proposal 기록 없음 (정리했더니 원래와 같으면 안 고친 것)
set role authenticated;
set request.jwt.claim.sub = :'MOD';
select approve_proposal(:np_cancel, '그대로 승인', :'doc', null, t.pv(:np_cancel)) as yone \gset
reset role;
select t.ok('고친 곳이 없으면 edit_proposal 기록 없음', not exists (select 1 from moderation_log where action = 'edit_proposal' and target_id = :np_cancel::text)
  and exists (select 1 from moderation_log where action = 'approve_proposal' and target_id = :np_cancel::text));

-- 운영자가 문서 수정 제안을 고쳐서 승인해도 기록 (역할 admin)
set role authenticated;
set request.jwt.claim.sub = :'OP';
select approve_proposal(:de, '운영자가 다듬었습니다', '{"summary":"다듬은 요약","level_notes":{"1":"a","2":"b","3":"c","6":"d"},"lane_cautions":""}'::jsonb, null, t.pv(:de));
reset role;
select t.ok('운영자의 수정도 기록 (요약만 고침)', exists (select 1 from moderation_log where action = 'edit_proposal' and target_id = :de::text
  and actor_id = :'OP' and actor_role = 'admin' and note = '고친 곳: 한 줄 요약'));

-- 처리 기록은 운영자만 읽는다 (감독관은 못 읽음) — 누가 무엇을 고쳤는지는 운영자만 본다
set role authenticated;
set request.jwt.claim.sub = :'MOD';
select t.ok('감독관은 처리 기록을 못 읽음', (select count(*) = 0 from moderation_log));
set request.jwt.claim.sub = :'OP';
select t.ok('운영자는 edit_proposal 기록을 읽음', (select count(*) = 2 from moderation_log where action = 'edit_proposal'));
reset role;

-- ===== 7. 검토 중 표시(031)는 그대로 =====
set role authenticated;
set request.jwt.claim.sub = :'M2';
select t.ok('감독관: 대기 중인 새 카운터에 표시 가능', jsonb_typeof(start_proposal_review(:np_cancel)) = 'array');
reset role;
select t.ok('처리된 제안에는 표시를 남기지 않음', not exists (select 1 from proposal_reviewing where proposal_id in (:np, :np_cancel)));
set role authenticated;
set request.jwt.claim.sub = :'M2';
select t.fails('다른 분이 먼저 처리한 제안', format('select approve_proposal(%s, %L, %L::jsonb, null, t.pv(%s))', :np, '메모', :'doc', :np), '이미 다른 분이 처리했습니다');
reset role;
