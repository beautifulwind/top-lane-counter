-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 007: 운영자 메모 필수(승인·다시 공개·되돌리기) + 알림(확인하면 꺼짐)
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
\set v1 '{"summary":"가렌 고친 요약","level_notes":{"1":"a","2":"b","3":"c","6":"d","9":"e","11":"f"},"lane_cautions":""}'

set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Garen', auth.uid(), :'doc', t.build());
insert into ids select 'garen_p', id from edit_proposals where counter_champion = 'Garen';

-- ===== 1. 메모 없는 예전 함수는 없다 =====
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select t.fails('메모 없는 승인 함수 없음', format('select approve_proposal(%s::bigint)', (select v from ids where k = 'garen_p')), 'does not exist');
select t.fails('옛 2인자 승인 함수 없음 (012)', format($$select approve_proposal(%s::bigint, 'x'::text)$$, (select v from ids where k = 'garen_p')), 'does not exist');
select t.fails('메모 없는 다시 공개 함수 없음', format('select restore_counter(%s::bigint)', (select v from ids where k = 'quinn')), 'does not exist');
select t.fails('메모 없는 되돌리기 함수 없음', 'select revert_doc(1::bigint)', 'does not exist');
select t.fails('메모 검사 도우미는 직접 못 부름', $$select require_note('a', 'b')$$, 'permission denied');

-- ===== 2. 승인 메모 필수, 제안자에게 보임 =====
select t.fails('승인: 메모 공백', format($$select approve_proposal(%s, '   ', null, null, t.pv(%1$s))$$, (select v from ids where k = 'garen_p')), '승인 메모를 적어');
select t.fails('승인: 메모 null', format('select approve_proposal(%s, null, null, null, t.pv(%1$s))', (select v from ids where k = 'garen_p')), '승인 메모를 적어');
select t.fails('승인: 메모 501자', format('select approve_proposal(%s, %L, null, null, t.pv(%1$s))', (select v from ids where k = 'garen_p'), repeat('a', 501)), '500자');
select t.ok('메모가 없으면 제안은 그대로 대기', (select status = 'pending' from edit_proposals where id = (select v from ids where k = 'garen_p')));
select approve_proposal((select v from ids where k = 'garen_p'), '  좋은 공략이에요 ', null, null, t.pv((select v from ids where k = 'garen_p'))) as garen \gset
insert into ids values ('garen', :garen);
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select t.ok('제안자는 승인 메모(공백 정리)를 봄',
  (select status = 'approved' and approve_note = '좋은 공략이에요' from edit_proposals where id = (select v from ids where k = 'garen_p')));
select t.fails('제안자가 승인 메모 직접 변경', $$update edit_proposals set approve_note = 'x'$$, 'permission denied');

-- ===== 3. 다시 공개 메모 필수 =====
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select hide_counter(:garen, '확인 필요');
select t.fails('다시 공개: 메모 공백', format($$select restore_counter(%s, ' ')$$, :garen), '다시 공개 메모를 적어');
select t.fails('다시 공개: 메모 null', format('select restore_counter(%s, null)', :garen), '다시 공개 메모를 적어');
select t.ok('메모가 없으면 계속 숨김', (select status = 'hidden' from counters where id = :garen));
select restore_counter(:garen, ' 확인했어요 ');
select t.ok('다시 공개: 기록에 메모',
  (select reason = '확인했어요' from counter_status_log where counter_id = :garen and action = 'restore'));

-- ===== 4. 되돌리기 메모 필수, 수정 기록에 남음 =====
select t.fails('되돌리기: 메모 공백',
  format($$select revert_doc(%s, ' ')$$, (select id from doc_revisions where counter_id = (select v from ids where k = 'quinn'))), '되돌리기 메모를 적어');
-- 퀸 문서를 한 번 바꿔 두고(수정 제안 → 승인) 처음 버전으로 되돌린다
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000d';
insert into edit_proposals (type, target_champion, counter_champion, counter_id, proposer_id, content)
values ('doc_edit', 'x', 'y', (select v from ids where k = 'quinn'), auth.uid(), :'v1');
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select approve_proposal((select id from edit_proposals where type = 'doc_edit'), '반영', null, null, t.pv((select id from edit_proposals where type = 'doc_edit')));
select revert_doc((select id from doc_revisions where counter_id = (select v from ids where k = 'quinn') and kind = 'create'), ' 원래가 맞아요 ');
select t.ok('되돌리기: 기록(revert)에 메모(공백 정리)',
  (select r.kind = 'revert' and r.note = '원래가 맞아요'
   from matchup_docs d join doc_revisions r on r.id = d.revision_id where d.counter_id = (select v from ids where k = 'quinn')));

-- ===== 5. 알림: 재검토 요청하면 생기고, 본인만 보고, 본인만 읽음 처리 =====
select hide_counter(:garen, '다시 확인');
select request_revision(:garen, '9레벨을 고쳐 주세요');
select t.ok('운영자는 남의 알림을 못 봄', (select count(*) = 0 from notifications));
select t.fails('운영자도 알림 직접 만들기 불가',
  $$insert into notifications (user_id, kind) values ('00000000-0000-0000-0000-00000000000b', 'revision_request')$$, 'permission denied');
reset role;
insert into ids select 'b_note', id from notifications where kind = 'revision_request';
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000d';
select t.ok('다른 유저는 그 알림을 못 봄', (select count(*) = 0 from notifications where kind = 'revision_request'));
select t.ok('남의 알림 읽음 처리는 무시됨 (0개)',
  (select mark_notifications_read(array[(select v from ids where k = 'b_note')]) = 0));
reset role;
select t.ok('남이 읽음 처리해도 그대로 안 읽음 (postgres로 확인)',
  (select read_at is null from notifications where id = (select v from ids where k = 'b_note')));
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select t.ok('제안자: 안 읽은 재검토 요청 알림 1개 (메모·제안 포함)',
  (select count(*) = 1 from notifications
   where read_at is null and kind = 'revision_request' and message = '9레벨을 고쳐 주세요'
     and proposal_id = (select v from ids where k = 'garen_p')));
select t.fails('제안자도 알림 직접 수정 불가', $$update notifications set read_at = now()$$, 'permission denied');
select t.fails('제안자도 알림 직접 삭제 불가', $$delete from notifications$$, 'permission denied');
select t.ok('008: 가렌 승인 알림도 받음 (메모 포함)',
  (select count(*) = 1 from notifications where kind = 'proposal_approved' and message = '좋은 공략이에요'
     and proposal_id = (select v from ids where k = 'garen_p')));
select t.ok('/me에서 확인 → 2개 읽음 처리 (승인 + 재검토 요청)', (select mark_notifications_read(array(select id from notifications)) = 2));
select t.ok('빨간 점 조건이 꺼짐', (select count(*) = 0 from notifications where read_at is null));
select t.ok('다시 확인해도 0개', (select mark_notifications_read(array(select id from notifications)) = 0));
select t.ok('확인해도 재검토 요청 상태와 메모는 남음 (다시 제출 가능)',
  (select status = 'revision_requested' and revision_note = '9레벨을 고쳐 주세요' from edit_proposals where id = (select v from ids where k = 'garen_p')));
reset role;
set role anon;
set request.jwt.claim.sub = '';
select t.fails('비로그인 알림 읽기', 'select * from notifications', 'permission denied');
select t.fails('비로그인 읽음 처리', 'select mark_notifications_read(array[1::bigint])', 'permission denied');
reset role;
set role authenticated;

-- ===== 6. 확인 안 한 알림도 다시 제출하면 자동 읽음 처리 =====
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select resubmit_proposal((select v from ids where k = 'garen_p'), :'v1', t.build());
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select reject_proposal((select v from ids where k = 'garen_p'), '아직 부족해요', t.pv((select v from ids where k = 'garen_p')));
select request_revision(:garen, '한 번 더 고쳐 주세요');
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select t.ok('두 번째 요청: 새 알림 1개', (select count(*) = 1 from notifications where read_at is null and message = '한 번 더 고쳐 주세요'));
select resubmit_proposal((select v from ids where k = 'garen_p'), :'v1', t.build());
select t.ok('다시 제출하면 확인 안 한 재검토 요청 알림도 읽음 처리', (select count(*) = 0 from notifications where read_at is null and kind = 'revision_request'));
select t.ok('008: 거절 알림은 직접 확인할 때까지 남음', (select count(*) = 1 from notifications where read_at is null and kind = 'proposal_rejected' and message = '아직 부족해요'));

-- ===== 7. 재검토 요청 중 [다시 공개]로 취소하면 알림도 읽음 처리 =====
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select reject_proposal((select v from ids where k = 'garen_p'), '그래도 부족', t.pv((select v from ids where k = 'garen_p')));
select request_revision(:garen, '세 번째');
select restore_counter(:garen, '그냥 공개할게요');
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select t.ok('취소된 요청 알림은 빨간 점에 남지 않음', (select count(*) = 0 from notifications where read_at is null and kind = 'revision_request'));
select t.ok('알림 기록 자체는 남음 (재검토 요청 3개)', (select count(*) = 3 from notifications where kind = 'revision_request'));

-- ===== 8. 카운터를 완전 삭제하면 그 제안의 알림도 지워짐 =====
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select hide_counter(:garen, '중복');
select request_revision(:garen, '네 번째');
select delete_counter(:garen, 'Garen', '중복 카운터');
reset role;
select t.ok('삭제: 그 제안의 알림도 함께 지워짐', (select count(*) = 0 from notifications where user_id = '00000000-0000-0000-0000-00000000000b'));
