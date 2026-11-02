-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
\set ON_ERROR_STOP 1
\set QUIET 1
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'op@x.com'),
  ('00000000-0000-0000-0000-00000000000b', 'u@x.com'),
  ('00000000-0000-0000-0000-00000000000d', 'u2@x.com');
update public.profiles set nickname = '영자', role = 'admin' where id = '00000000-0000-0000-0000-00000000000a';
update public.profiles set nickname = '유저' where id = '00000000-0000-0000-0000-00000000000b';
update public.profiles set nickname = '유저2' where id = '00000000-0000-0000-0000-00000000000d';
create temp table ids (k text primary key, v bigint);
grant all on ids to authenticated, anon;
insert into ids values ('quinn', (select id from counters where counter_champion = 'Quinn'));

\set doc '{"summary":"가렌 요약","level_notes":{"1":"a","2":"b","3":"c","6":"d","9":"e","11":"f"},"lane_cautions":""}'

-- 준비: 유저가 가렌 제안 → 운영자 승인 → (postgres로) 승인된 빌드 하나 → 유저2가 가렌 문서 수정 제안(대기)
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Garen', auth.uid(), :'doc', t.build());
insert into ids select 'garen_p', id from edit_proposals where counter_champion = 'Garen';
-- 승인 전에 유저2도 같은 매치업을 제안해 둠 (나중에 숨긴 뒤 이 제안을 승인하려는 경우 검사용)
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000d';
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Garen', auth.uid(), :'doc', t.build());
insert into ids select 'garen_p2', id from edit_proposals where counter_champion = 'Garen' and proposer_id = auth.uid();
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select approve_proposal((select v from ids where k = 'garen_p'), '좋아요', null, null) as garen \gset
insert into ids values ('garen', :garen);
reset role;
-- 009: 가렌 제안의 빌드가 승인과 함께 첫 빌드로 공개돼 있다
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000d';
insert into edit_proposals (type, target_champion, counter_champion, counter_id, proposer_id, content)
values ('doc_edit', 'x', 'y', :garen, auth.uid(), '{"summary":"가렌 고침","level_notes":{"1":"a","2":"b","3":"c","6":"d","9":"e","11":"f"}}');
insert into ids select 'edit_p', id from edit_proposals where type = 'doc_edit';

-- ===== 운영자만 =====
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select t.fails('일반 유저 숨기기', format($$select hide_counter(%s, '실수')$$, :garen), '운영자만');
select t.fails('일반 유저 다시 공개', format($$select restore_counter(%s, '공개')$$, :garen), '운영자만');
select t.fails('일반 유저 카운터 상태 직접 변경', format($$update counters set status = 'hidden' where id = %s$$, :garen), 'permission denied');
select t.fails('일반 유저 제안을 승인 취소로 직접 변경', $$update edit_proposals set status = 'revoked', revoke_reason = 'x'$$, 'permission denied');
select t.fails('일반 유저 기록 직접 쓰기', format($$insert into counter_status_log (counter_id, action, reason) values (%s, 'hide', 'x')$$, :garen), 'permission denied');
reset role;
set role anon;
set request.jwt.claim.sub = '';  -- 비로그인: 로그인 정보 없음
select t.fails('비로그인 숨기기', format($$select hide_counter(%s, '실수')$$, :garen), 'permission denied');
select t.fails('비로그인 다시 공개', format($$select restore_counter(%s, '공개')$$, :garen), 'permission denied');
select t.fails('비로그인 기록 읽기', 'select * from counter_status_log', 'permission denied');
reset role;
set role authenticated;

-- ===== 운영자: 숨기기 =====
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select t.fails('운영자도 상태 직접 변경 불가', format($$update counters set status = 'hidden' where id = %s$$, :garen), 'permission denied');
select t.fails('운영자도 기록 직접 쓰기 불가', format($$insert into counter_status_log (counter_id, action, reason) values (%s, 'hide', 'x')$$, :garen), 'permission denied');
select t.fails('숨기기: 사유 공백', format($$select hide_counter(%s, '   ')$$, :garen), '숨기는 사유를');
select t.fails('숨기기: 사유 null', format($$select hide_counter(%s, null)$$, :garen), '숨기는 사유를');
select t.fails('숨기기: 없는 카운터', $$select hide_counter(999999, '실수')$$, '찾지 못했어요');
select hide_counter(:garen, '  잘못 승인했어요 ');
select t.ok('숨기기: 카운터 hidden', (select status = 'hidden' from counters where id = :garen));
select t.ok('숨기기: 제안은 승인 취소 + 사유(공백 정리) + 취소한 사람',
  (select status = 'revoked' and revoke_reason = '잘못 승인했어요' and revoked_by = auth.uid() and revoked_at is not null
   from edit_proposals where id = (select v from ids where k = 'garen_p')));
select t.ok('숨기기: 기록(hide, 사유, 제안 id, 운영자)',
  (select count(*) = 1 from counter_status_log where counter_id = :garen and action = 'hide' and reason = '잘못 승인했어요'
     and proposal_id = (select v from ids where k = 'garen_p') and actor = auth.uid()));
select t.ok('숨기기: 문서·수정 기록·빌드는 지우지 않음',
  (select (select count(*) from matchup_docs where counter_id = :garen) = 1
      and (select count(*) from doc_revisions where counter_id = :garen) = 1
      and (select count(*) from builds where counter_id = :garen) = 1));
select t.fails('이미 숨긴 카운터 다시 숨기기', format($$select hide_counter(%s, '또')$$, :garen), '이미 숨긴');

-- 숨긴 동안
reset role;
set role anon;
set request.jwt.claim.sub = '';  -- 비로그인: 로그인 정보 없음
select t.ok('비로그인: 숨긴 카운터·문서·빌드 안 보임',
  (select (select count(*) from counters where id = (select v from ids where k = 'garen')) = 0
      and (select count(*) from matchup_docs where counter_id = (select v from ids where k = 'garen')) = 0
      and (select count(*) from builds where counter_id = (select v from ids where k = 'garen')) = 0));
reset role;
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select t.ok('제안자: 숨긴 카운터·문서 안 보임 (내가 쓴 첫 빌드만 /me용으로 보임)',
  (select (select count(*) from counters where id = :garen) = 0
      and (select count(*) from matchup_docs where counter_id = :garen) = 0
      and (select count(*) from builds where counter_id = :garen and author_id is distinct from auth.uid()) = 0));
select t.ok('제안자는 승인 취소와 사유를 봄',
  (select status = 'revoked' and revoke_reason = '잘못 승인했어요' from edit_proposals where id = (select v from ids where k = 'garen_p')));
select t.ok('일반 유저는 숨김 기록을 못 봄', (select count(*) = 0 from counter_status_log));
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000d';
select t.fails('숨긴 동안 같은 매치업 새 카운터 제안 불가',
  format($$insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build) values ('new_counter','Darius','Garen',auth.uid(),%L, t.build())$$, :'doc'),
  '숨긴 카운터라');
select t.fails('숨긴 카운터 문서 수정 제안 불가',
  format($$insert into edit_proposals (type, target_champion, counter_champion, counter_id, proposer_id, content) values ('doc_edit','x','y',%s,auth.uid(),'{"summary":"또 고침","level_notes":{"1":"a","2":"b","3":"c","6":"d","9":"e","11":"f"}}')$$, :garen),
  '찾지 못했어요');

set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select t.fails('숨긴 카운터의 대기 중 수정 제안은 승인 불가', format($$select approve_proposal(%s, '좋아요', null, null)$$, (select v from ids where k = 'edit_p')), '숨긴 카운터의 제안');
select reject_proposal((select v from ids where k = 'edit_p'), '카운터를 숨겼어요');
select t.ok('그 제안은 거절은 됨', (select status = 'rejected' from edit_proposals where id = (select v from ids where k = 'edit_p')));
select t.fails('순서 변경에 숨긴 카운터를 넣으면 거부', format($$select reorder_counters('Darius', array[%s,%s]::bigint[])$$, (select v from ids where k = 'quinn'), :garen), '목록이 바뀌었어요');
select reorder_counters('Darius', array[(select v from ids where k = 'quinn')]::bigint[]);
select t.ok('순서 변경은 숨긴 카운터를 빼고 동작', (select sort_order = 0 from counters where id = (select v from ids where k = 'quinn')));

-- 숨기기 전에 들어와 있던 같은 매치업의 새 카운터 제안 → 승인 불가 (거절해야 함)
select t.fails('숨긴 매치업의 새 카운터 제안 승인 불가', format($$select approve_proposal(%s, '좋아요', null, null)$$, (select v from ids where k = 'garen_p2')), '숨긴 카운터예요');

-- ===== 다시 공개 =====
select t.fails('메모 501자', format($$select restore_counter(%s, %L)$$, :garen, repeat('a', 501)), '500자');
select restore_counter(:garen, '  확인해 보니 맞는 카운터 ');
select t.ok('다시 공개: 공개 + 목록 맨 뒤', (select status = 'approved' and sort_order = 1 from counters where id = :garen));
select t.ok('다시 공개: 제안은 다시 승인, 취소 사유는 지움',
  (select status = 'approved' and revoke_reason is null and revoked_at is null from edit_proposals where id = (select v from ids where k = 'garen_p')));
select t.ok('다시 공개: 기록(restore, 메모)',
  (select count(*) = 1 from counter_status_log where counter_id = :garen and action = 'restore' and reason = '확인해 보니 맞는 카운터'));
select t.ok('숨김 기록은 남아 있음', (select count(*) = 2 from counter_status_log where counter_id = :garen));
select t.fails('숨긴 카운터가 아니면 다시 공개 불가', format($$select restore_counter(%s, '공개')$$, :garen), '숨긴 카운터가 아니에요');
reset role;
set role anon;
set request.jwt.claim.sub = '';  -- 비로그인: 로그인 정보 없음
select t.ok('다시 공개 후 비로그인에게 문서·빌드가 다시 보임',
  (select (select count(*) from matchup_docs where counter_id = (select v from ids where k = 'garen')) = 1
      and (select count(*) from builds where counter_id = (select v from ids where k = 'garen')) = 1));
reset role;
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';

-- 제안 없이 생긴 카운터(초기 데이터 퀸)도 숨기기 가능
select hide_counter((select v from ids where k = 'quinn'), '테스트');
select t.ok('초기 데이터 카운터 숨기기: 기록의 제안 id는 비어 있음',
  (select proposal_id is null from counter_status_log where counter_id = (select v from ids where k = 'quinn') and action = 'hide'));
reset role;
