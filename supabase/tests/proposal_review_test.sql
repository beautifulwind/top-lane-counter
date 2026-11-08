-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 031: 이미 처리됨 전용 오류(TL409) + 제안 "검토 중" 표시 (권한·만료·처리하면 삭제·일반 회원 차단)
\set ON_ERROR_STOP 1
\set QUIET 1
\set OP  '00000000-0000-0000-0000-00000000000a'
\set MOD '00000000-0000-0000-0000-00000000000b'
\set M2  '00000000-0000-0000-0000-00000000000c'
\set U   '00000000-0000-0000-0000-00000000000d'
\set doc '{"summary":"요약","level_notes":{"1":"a","2":"b","3":"c","6":"d","9":"e","11":"f"},"lane_cautions":""}'
insert into auth.users (id, email) values (:'OP', 'op@x.com'), (:'MOD', 'm@x.com'), (:'M2', 'm2@x.com'), (:'U', 'u@x.com');
update public.profiles set nickname = '영자', role = 'admin' where id = :'OP';
update public.profiles set nickname = '감독', role = 'moderator' where id = :'MOD';
update public.profiles set nickname = '감독둘', role = 'moderator' where id = :'M2';
update public.profiles set nickname = '유저' where id = :'U';

set role authenticated;
set request.jwt.claim.sub = :'U';
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Garen', auth.uid(), :'doc', t.build()) returning id as a \gset
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Teemo', auth.uid(), :'doc', t.build()) returning id as b \gset
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Vayne', auth.uid(), :'doc', t.build()) returning id as c \gset
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Ornn', auth.uid(), :'doc', t.build()) returning id as d \gset
insert into edit_proposals (type, counter_id, target_champion, counter_champion, proposer_id, content)
values ('doc_edit', (select id from counters where counter_champion = 'Quinn'), 'Darius', 'Quinn', auth.uid(), :'doc') returning id as de \gset

-- ===== 1. 일반 회원은 못 쓰고 못 읽는다 =====
select t.fails('일반 회원: 표시 시작 불가', format('select start_proposal_review(%s)', :a), '운영자만');
select t.fails('일반 회원: 표시 끝내기 불가', format('select end_proposal_review(%s)', :a), '운영자만');
select t.fails('일반 회원: 목록 불가', format('select proposal_reviewers(array[%s]::bigint[])', :a), '운영자만');
select t.fails('일반 회원: 표 직접 읽기 불가', 'select * from proposal_reviewing', 'permission denied');
select t.fails('일반 회원: 표 직접 쓰기 불가', format('insert into proposal_reviewing (proposal_id, user_id, expires_at) values (%s, auth.uid(), now() + interval %L)', :a, '1 hour'), 'permission denied');
reset role;
set role anon;
select t.fails('비로그인: 함수 불가', format('select start_proposal_review(%s)', :a), 'permission denied');
reset role;

-- ===== 2. 운영자·감독관은 서로 보인다 (나는 제외) =====
set role authenticated;
set request.jwt.claim.sub = :'MOD';
select t.ok('감독관이 처음 열면 다른 사람이 없다', start_proposal_review(:a) = '[]'::jsonb);
set request.jwt.claim.sub = :'OP';
select t.ok('운영자가 열면 감독관이 보임', (start_proposal_review(:a) -> 0 ->> 'nickname') = '감독' and (start_proposal_review(:a) -> 0 ->> 'role') = 'moderator');
select t.ok('목록: 나는 제외, 감독관만', (proposal_reviewers(array[:a]::bigint[]) -> (:a)::text -> 0 ->> 'nickname') = '감독'
  and jsonb_array_length(proposal_reviewers(array[:a]::bigint[]) -> (:a)::text) = 1);
set request.jwt.claim.sub = :'MOD';
select t.ok('감독관에게도 운영자가 보임', (proposal_reviewers(array[:a]::bigint[]) -> (:a)::text -> 0 ->> 'nickname') = '영자'
  and (proposal_reviewers(array[:a]::bigint[]) -> (:a)::text -> 0 ->> 'role') = 'admin');
reset role;
select t.ok('표에는 한 사람당 한 줄', (select count(*) = 2 from proposal_reviewing where proposal_id = :a));
select t.ok('만료는 약 10분 뒤', (select bool_and(expires_at between now() + interval '9 minutes' and now() + interval '10 minutes 5 seconds')
  from proposal_reviewing where proposal_id = :a));

-- ===== 3. 닫으면 내 것만 지워짐 =====
set role authenticated;
set request.jwt.claim.sub = :'MOD';
select end_proposal_review(:a);
reset role;
select t.ok('감독관 것만 지워짐', (select array_agg(user_id) = array[:'OP'::uuid] from proposal_reviewing where proposal_id = :a));

-- ===== 4. 만료된 것은 안 보이고 다음 기록 때 지워짐 =====
update proposal_reviewing set expires_at = now() - interval '1 second' where proposal_id = :a;
set role authenticated;
set request.jwt.claim.sub = :'MOD';
select t.ok('만료된 표시는 안 보임', proposal_reviewers(array[:a]::bigint[]) = '{}'::jsonb);
select t.ok('만료돼서 다른 사람 없음', start_proposal_review(:a) = '[]'::jsonb);
reset role;
select t.ok('만료된 줄은 정리됨', (select count(*) = 1 from proposal_reviewing where proposal_id = :a and user_id = :'MOD'));

-- ===== 5. 감독관은 처리할 수 없는 제안에는 표시를 남기지 않음 =====
set role authenticated;
set request.jwt.claim.sub = :'MOD';
select t.ok('문서 수정 제안: 표시 없음', start_proposal_review(:de) = '[]'::jsonb);
reset role;
select t.ok('문서 수정 제안 표시가 안 남음', not exists (select 1 from proposal_reviewing where proposal_id = :de));
set role authenticated;
set request.jwt.claim.sub = :'OP';
select start_proposal_review(:de);
reset role;
select t.ok('운영자는 문서 수정 제안도 표시', exists (select 1 from proposal_reviewing where proposal_id = :de and user_id = :'OP'));

-- ===== 6. 처리하면 표시가 바로 지워지고, 두 번째 처리는 TL409 =====
set role authenticated;
set request.jwt.claim.sub = :'OP';
select start_proposal_review(:b);
set request.jwt.claim.sub = :'MOD';
select start_proposal_review(:b);
reset role;
select t.ok('두 사람이 열어 둠', (select count(*) = 2 from proposal_reviewing where proposal_id = :b));
set role authenticated;
set request.jwt.claim.sub = :'OP';
select approve_proposal(:b, '승인', null, null, t.pv(:b));
reset role;
select t.ok('승인하면 표시가 모두 지워짐', not exists (select 1 from proposal_reviewing where proposal_id = :b));
set role authenticated;
set request.jwt.claim.sub = :'MOD';
select t.fails('이미 승인된 제안을 감독관이 승인 → 전용 안내', format('select approve_proposal(%s, %L, null, null, t.pv(%s))', :b, '메모', :b), '이미 다른 분이 처리했습니다');
select t.fails('이미 승인된 제안을 감독관이 거절 → 전용 안내', format('select reject_proposal(%s, %L, t.pv(%s))', :b, '사유', :b), '이미 다른 분이 처리했습니다');
create function pg_temp.sqlstate_of(q text) returns text language plpgsql as $f$
declare c text;
begin
  execute q;
  return 'none';
exception when others then
  get stacked diagnostics c = returned_sqlstate;
  return c;
end;
$f$;
grant execute on function pg_temp.sqlstate_of(text) to authenticated;
select t.ok('오류 코드는 TL409 (승인)', pg_temp.sqlstate_of(format('select approve_proposal(%s, %L, null, null, t.pv(%s))', :b, '메모', :b)) = 'TL409');
select t.ok('오류 코드는 TL409 (거절)', pg_temp.sqlstate_of(format('select reject_proposal(%s, %L, t.pv(%s))', :b, '사유', :b)) = 'TL409');
set request.jwt.claim.sub = :'OP';
select t.fails('운영자: 이미 승인된 제안 승인', format('select approve_proposal(%s, %L, null, null, t.pv(%s))', :b, '메모', :b), '이미 다른 분이 처리했습니다');
select t.fails('운영자: 이미 승인된 제안 재검토 요청', format('select request_proposal_revision(%s, %L, t.pv(%s))', :b, '메모', :b), '이미 다른 분이 처리했습니다');
select t.fails('운영자: 재검토 중 아닌 제안 요청 취소', format('select cancel_proposal_revision(%s, %L)', :b, '메모'), '이미 다른 분이 처리했습니다');
select reject_proposal(:c, '근거 부족', t.pv(:c));
select t.fails('운영자: 이미 거절된 제안 거절', format('select reject_proposal(%s, %L, t.pv(%s))', :c, '또', :c), '이미 다른 분이 처리했습니다');
select t.fails('운영자: 이미 거절된 제안 승인', format('select approve_proposal(%s, %L, null, null, t.pv(%s))', :c, '또', :c), '이미 다른 분이 처리했습니다');

-- ===== 7. 재검토 요청으로 대기를 벗어나도 표시가 지워진다 =====
select start_proposal_review(:d);
reset role;
select t.ok('열어 둠', exists (select 1 from proposal_reviewing where proposal_id = :d));
set role authenticated;
set request.jwt.claim.sub = :'OP';
select request_proposal_revision(:d, '고쳐 주세요', t.pv(:d));
reset role;
select t.ok('재검토 요청하면 표시가 지워짐', not exists (select 1 from proposal_reviewing where proposal_id = :d));
set role authenticated;
set request.jwt.claim.sub = :'OP';
select t.ok('재검토 중인 제안은 표시하지 않음', start_proposal_review(:d) = '[]'::jsonb);
select t.fails('이미 재검토 요청한 제안에 또 요청', format('select request_proposal_revision(%s, %L, t.pv(%s))', :d, '또', :d), '이미 재검토를 요청');
reset role;

-- ===== 8. 처리된 제안에는 표시가 남지 않는다 =====
select t.ok('처리된 제안에는 표시가 없음', not exists (select 1 from proposal_reviewing where proposal_id in (:b, :c, :d)));
