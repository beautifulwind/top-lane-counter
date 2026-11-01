-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 숨긴 카운터 도구: 미리보기(RLS) / 재검토 요청 → 다시 제출 → 승인·거절 / 완전 삭제
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
\set v1 '{"summary":"가렌 고친 요약","level_notes":{"1":"a","2":"b","3":"c","6":"d","9":"e","11":"f"},"lane_cautions":"주의"}'
\set v2 '{"summary":"가렌 두 번째 고침","level_notes":{"1":"a2","2":"b","3":"c","6":"d","9":"e","11":"f"},"lane_cautions":"주의"}'

-- 준비: 유저가 가렌 제안 → 운영자 승인 → (postgres로) 빌드 1개 + 유저2 따봉 → 유저2 문서 수정 제안(대기) → 운영자가 숨김
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content)
values ('new_counter', 'Darius', 'Garen', auth.uid(), :'doc');
insert into ids select 'garen_p', id from edit_proposals where counter_champion = 'Garen';
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select approve_proposal((select v from ids where k = 'garen_p'), '좋아요') as garen \gset
insert into ids values ('garen', :garen);
reset role;
insert into builds (counter_id, runes, summoner_spells, skill_order, patch, status)
values (:garen, '{}', array['SummonerFlash','SummonerTeleport'], '["Q","E","W"]', '16.1.1', 'approved');
insert into build_votes (build_id, user_id, value)
select id, '00000000-0000-0000-0000-00000000000d', 1 from builds where counter_id = :garen;
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000d';
insert into edit_proposals (type, target_champion, counter_champion, counter_id, proposer_id, content)
values ('doc_edit', 'x', 'y', :garen, auth.uid(), :'v1');
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select hide_counter(:garen, '잘못 승인했어요');

-- ===== 1. 미리보기: 숨긴 문서·빌드는 운영자만 읽는다 =====
select t.ok('운영자: 숨긴 카운터·문서·빌드·수정 기록을 읽음',
  (select (select count(*) from counters where id = :garen) = 1
      and (select count(*) from matchup_docs where counter_id = :garen) = 1
      and (select count(*) from builds where counter_id = :garen) = 1
      and (select count(*) from doc_revisions where counter_id = :garen) = 1));
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select t.ok('제안자도 숨긴 카운터·문서·빌드는 못 읽음 (제안 상태만 보임)',
  (select (select count(*) from counters where id = :garen) = 0
      and (select count(*) from matchup_docs where counter_id = :garen) = 0
      and (select count(*) from builds where counter_id = :garen) = 0
      and (select count(*) from doc_revisions where counter_id = :garen) = 0));
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000d';
select t.ok('다른 유저도 못 읽음',
  (select (select count(*) from matchup_docs where counter_id = :garen) = 0
      and (select count(*) from builds where counter_id = :garen) = 0));
reset role;
set role anon;
set request.jwt.claim.sub = '';
select t.ok('비로그인도 못 읽음',
  (select (select count(*) from counters where id = (select v from ids where k = 'garen')) = 0
      and (select count(*) from matchup_docs where counter_id = (select v from ids where k = 'garen')) = 0
      and (select count(*) from builds where counter_id = (select v from ids where k = 'garen')) = 0));

-- ===== 2. 운영자만 / 본인만 =====
select t.fails('비로그인 재검토 요청', format($$select request_revision(%s, '고쳐 주세요')$$, (select v from ids where k = 'garen')), 'permission denied');
select t.fails('비로그인 다시 제출', format($$select resubmit_proposal(%s, '{}')$$, (select v from ids where k = 'garen_p')), 'permission denied');
select t.fails('비로그인 삭제', format($$select delete_counter(%s, 'Garen', '중복')$$, (select v from ids where k = 'garen')), 'permission denied');
select t.fails('비로그인 삭제 기록 읽기', 'select * from counter_deletions', 'permission denied');
select t.fails('비로그인 도우미 함수', format('select origin_proposal_id(%s)', (select v from ids where k = 'garen')), 'permission denied');
reset role;
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select t.fails('제안자도 재검토 요청은 못 함', format($$select request_revision(%s, '고쳐 주세요')$$, :garen), '운영자만');
select t.fails('일반 유저 삭제', format($$select delete_counter(%s, 'Garen', '중복')$$, :garen), '운영자만');
select t.fails('일반 유저 도우미 함수', format('select origin_proposal_id(%s)', :garen), 'permission denied');
select t.fails('제안을 재검토 요청 상태로 직접 변경', $$update edit_proposals set status = 'revision_requested', revision_note = 'x'$$, 'permission denied');
select t.fails('삭제 기록 직접 쓰기', $$insert into counter_deletions (counter_id, target_champion, counter_champion, reason) values (1, 'a', 'b', 'x')$$, 'permission denied');
select t.ok('일반 유저는 삭제 기록을 못 봄', (select count(*) = 0 from counter_deletions));
select t.fails('재검토 요청 전에는 다시 제출 불가', format($$select resubmit_proposal(%s, %L)$$, (select v from ids where k = 'garen_p'), :'v1'), '재검토 요청을 받은 제안만');

-- ===== 3. 재검토 요청 =====
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select t.fails('재검토 요청: 메모 공백', format($$select request_revision(%s, '  ')$$, :garen), '메모를 적어');
select t.fails('재검토 요청: 메모 501자', format($$select request_revision(%s, %L)$$, :garen, repeat('a', 501)), '500자');
select t.fails('재검토 요청: 공개 중인 카운터', format($$select request_revision(%s, '고쳐 주세요')$$, (select v from ids where k = 'quinn')), '숨긴 카운터만');
select t.fails('재검토 요청: 없는 카운터', $$select request_revision(999999, '고쳐 주세요')$$, '찾지 못했어요');
select request_revision(:garen, '  9레벨 내용을 고쳐 주세요 ');
select t.ok('재검토 요청: 제안 상태·메모(공백 정리)·요청한 운영자',
  (select status = 'revision_requested' and revision_note = '9레벨 내용을 고쳐 주세요'
      and revision_requested_by = auth.uid() and revision_requested_at is not null
   from edit_proposals where id = (select v from ids where k = 'garen_p')));
select t.ok('재검토 요청: 수정 출발점 = 숨긴 시점의 문서 (+ 그 문서 버전)',
  (select p.content = jsonb_build_object('summary', d.summary, 'level_notes', d.level_notes, 'lane_cautions', d.lane_cautions)
      and p.base_revision_id = d.revision_id
   from edit_proposals p, matchup_docs d where p.id = (select v from ids where k = 'garen_p') and d.counter_id = :garen));
select t.ok('재검토 요청: 기록(revision_request, 메모)',
  (select count(*) = 1 from counter_status_log where counter_id = :garen and action = 'revision_request' and reason = '9레벨 내용을 고쳐 주세요'));
select t.ok('재검토 요청 중에도 카운터는 계속 숨김', (select status = 'hidden' from counters where id = :garen));
select t.fails('이미 재검토 요청 중', format($$select request_revision(%s, '또')$$, :garen), '이미 재검토를');

-- ===== 4. 다시 제출 =====
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select t.ok('제안자는 재검토 요청과 메모를 봄 (빨간 점 조건)',
  (select count(*) = 1 from edit_proposals where proposer_id = auth.uid() and status = 'revision_requested' and revision_note = '9레벨 내용을 고쳐 주세요'));
select t.fails('바뀐 게 없으면 거부',
  format($$select resubmit_proposal(%s, (select content from edit_proposals where id = %s))$$, (select v from ids where k = 'garen_p'), (select v from ids where k = 'garen_p')),
  '고친 내용이 없어요');
select t.fails('공백만 다르면 바뀐 게 없는 것',
  format($$select resubmit_proposal(%s, '{"summary":" 가렌 요약 ","level_notes":{"1":"a","2":"b","3":"c","6":"d","9":"e","11":"f","5":" "},"lane_cautions":""}')$$, (select v from ids where k = 'garen_p')),
  '고친 내용이 없어요');
select t.fails('내용 검사는 기존 규칙과 같음 (필수 레벨)',
  format($$select resubmit_proposal(%s, '{"summary":"x","level_notes":{"1":"a","2":"b","3":"c","6":"d","11":"f"}}')$$, (select v from ids where k = 'garen_p')),
  '9레벨 딜교법은 꼭');
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000d';
select t.fails('남의 제안은 다시 제출 불가', format($$select resubmit_proposal(%s, %L)$$, (select v from ids where k = 'garen_p'), :'v1'), '찾지 못했어요');
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select t.fails('운영자도 남의 제안은 다시 제출 불가', format($$select resubmit_proposal(%s, %L)$$, (select v from ids where k = 'garen_p'), :'v1'), '찾지 못했어요');
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select resubmit_proposal((select v from ids where k = 'garen_p'), :'v1');
select t.ok('다시 제출: 승인 대기 + 고친 내용 + 다시 낸 때',
  (select status = 'pending' and content = :'v1'::jsonb and resubmitted_at is not null and reviewed_at is null
   from edit_proposals where id = (select v from ids where k = 'garen_p')));
select t.ok('다시 제출하면 빨간 점 조건이 꺼짐',
  (select count(*) = 0 from edit_proposals where proposer_id = auth.uid() and status = 'revision_requested'));
select t.fails('대기 중엔 또 제출 불가', format($$select resubmit_proposal(%s, %L)$$, (select v from ids where k = 'garen_p'), :'v2'), '재검토 요청을 받은 제안만');

-- ===== 5. 승인 대기 중에는 다시 공개·삭제·재검토 요청을 막는다 =====
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select t.ok('기록(resubmit, 제안자)',
  (select count(*) = 1 from counter_status_log where counter_id = :garen and action = 'resubmit' and actor = '00000000-0000-0000-0000-00000000000b'));
select t.ok('승인 대기 목록에 들어옴', (select count(*) = 1 from edit_proposals where status = 'pending' and id = (select v from ids where k = 'garen_p')));
select t.fails('승인 대기 중 다시 공개', format($$select restore_counter(%s, '공개')$$, :garen), '승인 대기 중');
select t.fails('승인 대기 중 삭제', format($$select delete_counter(%s, 'Garen', '중복')$$, :garen), '승인 대기 중');
select t.fails('승인 대기 중 재검토 요청', format($$select request_revision(%s, '또')$$, :garen), '이미 다시 제출');

-- ===== 6. 거절 → 계속 숨김, 다시 요청 가능 =====
select reject_proposal((select v from ids where k = 'garen_p'), '아직 부족해요');
select t.ok('거절: 카운터는 계속 숨김, 문서는 그대로',
  (select c.status = 'hidden' and d.summary = '가렌 요약' from counters c join matchup_docs d on d.counter_id = c.id where c.id = :garen));
select t.ok('거절: 기록(reject, 사유)',
  (select count(*) = 1 from counter_status_log where counter_id = :garen and action = 'reject' and reason = '아직 부족해요'));
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select t.fails('거절된 뒤엔 다시 제출 불가', format($$select resubmit_proposal(%s, %L)$$, (select v from ids where k = 'garen_p'), :'v2'), '재검토 요청을 받은 제안만');
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select request_revision(:garen, '한 번 더 고쳐 주세요');
select t.ok('거절 뒤 다시 재검토 요청: 출발점은 다시 숨긴 문서, 거절 사유는 지움',
  (select status = 'revision_requested' and reject_reason is null and content = :'doc'::jsonb
   from edit_proposals where id = (select v from ids where k = 'garen_p')));

-- ===== 7. 다시 제출 → 승인 → 고친 내용으로 다시 공개 =====
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select resubmit_proposal((select v from ids where k = 'garen_p'), :'v2');
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select approve_proposal((select v from ids where k = 'garen_p'), ' 고친 내용 확인 ') = :garen as same_counter \gset
select t.ok('승인: 같은 카운터를 살림 (새로 만들지 않음)', :'same_counter'::boolean);
select t.ok('승인: 공개 + 목록 맨 뒤 (퀸 다음)',
  (select status = 'approved' and sort_order = (select sort_order + 1 from counters where id = (select v from ids where k = 'quinn'))
   from counters where id = :garen));
select t.ok('승인: 문서가 고친 내용으로 + 수정 기록(edit, 제안 id)이 지금 버전',
  (select d.summary = '가렌 두 번째 고침' and d.level_notes ->> '1' = 'a2' and d.lane_cautions = '주의'
      and r.kind = 'edit' and r.proposal_id = (select v from ids where k = 'garen_p') and r.content = :'v2'::jsonb
   from matchup_docs d join doc_revisions r on r.id = d.revision_id where d.counter_id = :garen));
select t.ok('승인: 제안은 승인, 취소 사유 지움',
  (select status = 'approved' and revoke_reason is null and reviewed_at is not null
   from edit_proposals where id = (select v from ids where k = 'garen_p')));
select t.ok('승인: 기록(restore)',
  (select reason = '고친 내용 확인' from counter_status_log
   where counter_id = :garen and action = 'restore' order by id desc limit 1));
reset role;
set role anon;
set request.jwt.claim.sub = '';
select t.ok('다시 공개 후 비로그인에게 고친 문서·빌드가 보임',
  (select (select summary from matchup_docs where counter_id = (select v from ids where k = 'garen')) = '가렌 두 번째 고침'
      and (select count(*) from builds where counter_id = (select v from ids where k = 'garen')) = 1));
reset role;
set role authenticated;

-- ===== 8. 재검토 요청 중에 [다시 공개] → 요청 취소, 원래 문서대로 공개 =====
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select hide_counter(:garen, '다시 확인');
select request_revision(:garen, '고쳐 주세요');
select restore_counter(:garen, '그냥 공개');
select t.ok('요청 중 다시 공개: 공개 + 문서는 그대로 + 제안은 다시 승인',
  (select c.status = 'approved' and d.summary = '가렌 두 번째 고침' and p.status = 'approved'
   from counters c join matchup_docs d on d.counter_id = c.id, edit_proposals p
   where c.id = :garen and p.id = (select v from ids where k = 'garen_p')));
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select t.fails('요청이 취소되면 다시 제출 불가', format($$select resubmit_proposal(%s, %L)$$, (select v from ids where k = 'garen_p'), :'v1'), '재검토 요청을 받은 제안만');

-- ===== 9. 초기 데이터(제안 없이 생긴) 카운터는 재검토 요청 불가 =====
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select hide_counter((select v from ids where k = 'quinn'), '테스트');
select t.fails('제안자 없는 카운터 재검토 요청', format($$select request_revision(%s, '고쳐 주세요')$$, (select v from ids where k = 'quinn')), '제안 없이 생긴');
select restore_counter((select v from ids where k = 'quinn'), '테스트 끝');

-- ===== 10. 완전 삭제 =====
select t.fails('공개 중인 카운터 삭제', format($$select delete_counter(%s, 'Garen', '중복')$$, :garen), '숨긴 카운터만');
select hide_counter(:garen, '중복 카운터');
select t.fails('삭제: 사유 공백', format($$select delete_counter(%s, 'Garen', '  ')$$, :garen), '삭제 사유를');
select t.fails('삭제: 확인 챔피언이 다름', format($$select delete_counter(%s, 'Quinn', '중복')$$, :garen), '확인한 챔피언이');
select t.fails('삭제: 확인값 없음', format($$select delete_counter(%s, null, '중복')$$, :garen), '확인한 챔피언이');
select t.fails('삭제: 없는 카운터', $$select delete_counter(999999, 'Garen', '중복')$$, '찾지 못했어요');
select t.fails('운영자도 카운터 직접 삭제 불가', format('delete from counters where id = %s', :garen), 'permission denied');
select delete_counter(:garen, 'Garen', '  같은 매치업이 두 번 등록됨 ') as del \gset
select t.ok('삭제: 카운터·문서·수정 기록·빌드·제안·숨김 기록이 없음',
  (select (select count(*) from counters where id = :garen) = 0
      and (select count(*) from matchup_docs where counter_id = :garen) = 0
      and (select count(*) from doc_revisions where counter_id = :garen) = 0
      and (select count(*) from builds where counter_id = :garen) = 0
      and (select count(*) from edit_proposals where counter_id = :garen) = 0
      and (select count(*) from counter_status_log where counter_id = :garen) = 0));
reset role;
select t.ok('삭제: 따봉도 없음 (postgres로 확인)', (select count(*) = 0 from build_votes));
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select t.ok('삭제 기록: 누가·언제·왜·어떤 매치업·원래 제안자·지운 개수',
  (select counter_id = :garen and target_champion = 'Darius' and counter_champion = 'Garen'
      and reason = '같은 매치업이 두 번 등록됨' and deleted_by = auth.uid() and deleted_at is not null
      and proposer_id = '00000000-0000-0000-0000-00000000000b'
      and proposals_count = 2 and revisions_count = 2 and builds_count = 1 and votes_count = 1
   from counter_deletions where id = :del));
select t.fails('삭제한 카운터 다시 삭제', format($$select delete_counter(%s, 'Garen', '또')$$, :garen), '찾지 못했어요');
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select t.ok('제안자 /me에서도 그 제안이 사라짐', (select count(*) = 0 from edit_proposals where counter_champion = 'Garen'));
select t.ok('일반 유저는 삭제 기록을 못 봄', (select count(*) = 0 from counter_deletions));
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content)
values ('new_counter', 'Darius', 'Garen', auth.uid(), :'doc');
select t.ok('삭제 뒤엔 같은 매치업을 새로 제안할 수 있음', (select count(*) = 1 from edit_proposals where counter_champion = 'Garen' and status = 'pending'));
reset role;
