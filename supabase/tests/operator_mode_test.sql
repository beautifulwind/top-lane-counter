-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 034: 제안자 알림 보강(숨긴 카운터 재검토 요청은 본인 제외, [다시 공개] 알림) + 운영자 모드 켜기/끄기
\set ON_ERROR_STOP 1
\set QUIET 1
\set OP  '00000000-0000-0000-0000-00000000000a'
\set MOD '00000000-0000-0000-0000-00000000000b'
\set U   '00000000-0000-0000-0000-00000000000d'
\set U2  '00000000-0000-0000-0000-00000000000e'
\set doc '{"summary":"요약","level_notes":{"1":"a","2":"b","3":"c","6":"d","9":"e","11":"f"},"lane_cautions":""}'
insert into auth.users (id, email) values (:'OP', 'op@x.com'), (:'MOD', 'm@x.com'), (:'U', 'u@x.com'), (:'U2', 'u2@x.com');
update public.profiles set nickname = '영자', role = 'admin' where id = :'OP';
update public.profiles set nickname = '감독', role = 'moderator' where id = :'MOD';
update public.profiles set nickname = '유저' where id = :'U';
update public.profiles set nickname = '유저둘' where id = :'U2';

-- ===== 1. 칸·함수 권한 =====
select t.ok('운영자 모드 칸: 기본 켜짐', (select bool_and(operator_mode) from profiles));
select t.ok('알림 종류 counter_restored 추가', (select pg_get_constraintdef(oid) like '%counter_restored%' and pg_get_constraintdef(oid) like '%inquiry_received%'
  from pg_constraint where conname = 'notifications_kind_check' and conrelid = 'public.notifications'::regclass));
set role anon;
select t.fails('비로그인은 모드 못 바꿈', 'select set_operator_mode(false)', 'permission denied');
reset role;
set role authenticated;
set request.jwt.claim.sub = :'U';
select t.fails('일반 회원: 모드 함수로 운영자 못 됨', 'select set_operator_mode(true)', '운영자 계정만');
select t.fails('일반 회원: 끄기도 불가', 'select set_operator_mode(false)', '운영자 계정만');
select t.fails('일반 회원: 칸을 직접 못 고침', $$update profiles set operator_mode = true where id = auth.uid()$$, 'permission denied');
select t.fails('일반 회원: role도 그대로 못 고침', $$update profiles set role = 'admin' where id = auth.uid()$$, 'permission denied');
select t.ok('일반 회원: 칸이 켜져 있어도 운영자 아님', not is_admin() and not is_staff());
set request.jwt.claim.sub = :'MOD';
select t.fails('감독관도 모드 못 바꿈', 'select set_operator_mode(false)', '운영자 계정만');
select t.ok('감독관은 그대로 운영진', is_staff() and not is_admin());
set request.jwt.claim.sub = :'OP';
select t.fails('운영자도 칸을 직접 못 고침', $$update profiles set operator_mode = false where id = auth.uid()$$, 'permission denied');
select t.fails('켜기/끄기 값 없음', 'select set_operator_mode(null)', '골라 주세요');
reset role;

-- ===== 2. 제안자 알림: 숨긴 카운터 재검토 요청 / [다시 공개] =====
-- 유저 제안(가렌), 운영자 본인 제안(오른) 승인 → 둘 다 숨김
set role authenticated;
set request.jwt.claim.sub = :'U';
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Garen', auth.uid(), :'doc', t.build()) returning id as gp \gset
set request.jwt.claim.sub = :'OP';
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Ornn', auth.uid(), :'doc', t.build()) returning id as op_p \gset
select approve_proposal(:gp, '좋습니다', null, null, t.pv(:gp)) as garen \gset
select approve_proposal(:op_p, '내 것', null, null, t.pv(:op_p)) as ornn \gset
select hide_counter(:garen, '확인 필요');
select hide_counter(:ornn, '확인 필요');
select request_revision(:garen, '9레벨을 고쳐 주세요');
select request_revision(:ornn, '내 것도 고침');
reset role;
select t.ok('숨긴 카운터 재검토 요청: 제안자에게 알림 (문장·종류 그대로)',
  exists (select 1 from notifications where user_id = :'U' and kind = 'revision_request' and proposal_id = :gp and message = '9레벨을 고쳐 주세요'));
select t.ok('숨긴 카운터 재검토 요청: 처리한 본인(운영자 자기 제안)에게는 안 감',
  not exists (select 1 from notifications where user_id = :'OP' and kind = 'revision_request'));
select t.ok('운영자 자기 제안이라도 재검토 요청 상태는 바뀜', (select status = 'revision_requested' from edit_proposals where id = :op_p));

set role authenticated;
set request.jwt.claim.sub = :'OP';
select restore_counter(:garen, '그대로 공개합니다');
select restore_counter(:ornn, '내 것 공개');
reset role;
select t.ok('[다시 공개]: 제안자에게 counter_restored (메모·제안 연결)',
  exists (select 1 from notifications where user_id = :'U' and kind = 'counter_restored' and proposal_id = :gp and message = '그대로 공개합니다'));
select t.ok('[다시 공개]: 진행 중이던 재검토 요청 알림은 읽음 처리 (기존 동작 그대로)',
  (select read_at is not null from notifications where user_id = :'U' and kind = 'revision_request' and proposal_id = :gp));
select t.ok('[다시 공개]: 처리한 본인에게는 안 감', not exists (select 1 from notifications where user_id = :'OP' and kind = 'counter_restored'));

-- 제안 없이 생긴 카운터(퀸)를 다시 공개: 알림 없음, 오류 없음
set role authenticated;
set request.jwt.claim.sub = :'OP';
select hide_counter((select id from counters where counter_champion = 'Quinn'), '테스트');
select restore_counter((select id from counters where counter_champion = 'Quinn'), '테스트 끝');
reset role;
select t.ok('제안 없는 카운터 다시 공개: 알림 없음', (select count(*) = 1 from notifications where kind = 'counter_restored'));

-- 기존 승인·반려·재검토 알림 그대로 (본인 제외 포함)
set role authenticated;
set request.jwt.claim.sub = :'U2';
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Teemo', auth.uid(), :'doc', t.build()) returning id as tp \gset
set request.jwt.claim.sub = :'OP';
select request_proposal_revision(:tp, '근거를 적어 주세요', t.pv(:tp));
select reject_proposal(:tp, '중복입니다', t.pv(:tp));
reset role;
select t.ok('대기 중 제안 재검토 요청·반려 알림 그대로',
  exists (select 1 from notifications where user_id = :'U2' and kind = 'revision_request' and proposal_id = :tp)
  and exists (select 1 from notifications where user_id = :'U2' and kind = 'proposal_rejected' and proposal_id = :tp and message = '중복입니다'));
select t.ok('승인 알림: 운영자 자기 제안은 안 감, 유저 제안은 감',
  exists (select 1 from notifications where user_id = :'U' and kind = 'proposal_approved' and proposal_id = :gp)
  and not exists (select 1 from notifications where user_id = :'OP' and kind in ('proposal_approved', 'proposal_rejected', 'revision_request', 'counter_restored')));

-- ===== 3. 운영자 모드 끄기: 일반 회원과 같은 길 =====
-- 준비: 유저의 대기 중 제안 1개 + 운영자에게 운영진 알림 1개(안 읽음)
set role authenticated;
set request.jwt.claim.sub = :'U';
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Malphite', auth.uid(), :'doc', t.build()) returning id as mp \gset
reset role;
select t.ok('준비: 운영자에게 새 제안 알림', exists (select 1 from notifications where user_id = :'OP' and kind = 'proposal_submitted' and proposal_id = :mp and read_at is null));

set role authenticated;
set request.jwt.claim.sub = :'OP';
select t.ok('끄기 전: 남의 대기 제안이 보임', exists (select 1 from edit_proposals where id = :mp));
select t.ok('끄기 → false를 돌려줌', set_operator_mode(false) = false);
select t.ok('끈 뒤: is_admin·is_staff 모두 false', not is_admin() and not is_staff());
select t.ok('끈 뒤: 남의 대기 제안이 안 보임 (내 제안만)', not exists (select 1 from edit_proposals where id = :mp)
  and exists (select 1 from edit_proposals where id = :op_p));
select t.fails('끈 뒤: 승인 불가', format($$select approve_proposal(%s, '메모', null, null, 1)$$, :mp), '운영자만');
select t.fails('끈 뒤: 반려 불가', format($$select reject_proposal(%s, '메모', 1)$$, :mp), '운영자만');
select t.fails('끈 뒤: 처리 대기 건수 불가', 'select admin_pending_counts()', '운영자만');
select t.fails('끈 뒤: 카운터 숨기기 불가', format($$select hide_counter(%s, '사유')$$, :garen), '운영자만');
select t.fails('끈 뒤: 감독관 지정 불가', format($$select set_moderator(%L, true, '메모')$$, :'U2'), '운영자만');
select t.ok('끈 뒤: 운영진 알림이 목록에서 빠짐', not exists (select 1 from notifications where kind = 'proposal_submitted'));
select t.ok('끈 뒤: 내 다른 알림은 보임 (예: 없음이어도 오류 없음)', (select count(*) >= 0 from notifications));
-- 일반 회원처럼 제안을 낸다 → 승인 대기, 운영진에게 알림 (본인 제외)
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Kayle', auth.uid(), :'doc', t.build()) returning id as kp \gset
select t.ok('끈 뒤 낸 제안: 승인 대기', (select status = 'pending' from edit_proposals where id = :kp));
select t.fails('끈 뒤: 자기 제안도 승인 불가', format($$select approve_proposal(%s, '메모', null, null, 1)$$, :kp), '운영자만');
-- [모두 읽음]은 숨긴 운영진 알림을 건드리지 않는다
select mark_all_notifications_read(999999999);
reset role;
select t.ok('끈 동안 [모두 읽음]: 운영진 알림은 안 읽음 그대로',
  (select read_at is null from notifications where user_id = :'OP' and kind = 'proposal_submitted' and proposal_id = :mp));
select t.ok('끈 뒤 낸 제안: 본인에게 운영진 알림 안 감', not exists (select 1 from notifications where user_id = :'OP' and proposal_id = :kp));
-- 끈 동안 들어온 새 제안: 알림은 쌓인다 (다시 켜면 보임)
set role authenticated;
set request.jwt.claim.sub = :'U2';
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Vayne', auth.uid(), :'doc', t.build()) returning id as vp \gset
reset role;
select t.ok('끈 동안 들어온 새 제안: 알림은 쌓임', exists (select 1 from notifications where user_id = :'OP' and proposal_id = :vp and kind = 'proposal_submitted'));
select t.ok('끈 동안: (운) 표시용 role은 그대로 admin', (select role = 'admin' and level = 0 from profiles where id = :'OP'));

-- 다른 사람은 운영자 모드에 영향 없음: 유저는 여전히 운영자 아님, 감독관은 그대로
set role authenticated;
set request.jwt.claim.sub = :'U';
select t.ok('운영자가 꺼도 유저 권한 그대로', not is_admin() and not is_staff());
set request.jwt.claim.sub = :'MOD';
select t.ok('운영자가 꺼도 감독관 그대로', is_staff() and exists (select 1 from edit_proposals where id = :mp));

-- ===== 4. 같은 자리에서 다시 켜기 =====
set request.jwt.claim.sub = :'OP';
select t.ok('다시 켜기 → true', set_operator_mode(true));
select t.ok('켠 뒤: 운영자 권한 돌아옴', is_admin() and is_staff() and exists (select 1 from edit_proposals where id = :mp));
select t.ok('켠 뒤: 운영진 알림 다시 보임 (안 읽음)',
  (select count(*) = 2 from notifications where kind = 'proposal_submitted' and proposal_id in (:mp, :vp) and read_at is null));
select approve_proposal(:kp, '켜고 내 것 승인', null, null, t.pv(:kp));
reset role;
select t.ok('켠 뒤 자기 제안 승인: 본인에게 승인 알림 안 감', not exists (select 1 from notifications where user_id = :'OP' and kind = 'proposal_approved'));
select 'operator_mode_test 통과' as result;
