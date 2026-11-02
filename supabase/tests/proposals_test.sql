-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
\set ON_ERROR_STOP 1
\set QUIET 1
set client_min_messages = notice;
-- 유저 준비 (postgres로)
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'op@x.com'),
  ('00000000-0000-0000-0000-00000000000b', 'u@x.com'),
  ('00000000-0000-0000-0000-00000000000c', 'nonick@x.com'),
  ('00000000-0000-0000-0000-00000000000d', 'u2@x.com');
update public.profiles set nickname = '영자' where id = '00000000-0000-0000-0000-00000000000a';
update public.profiles set role = 'admin' where id = '00000000-0000-0000-0000-00000000000a';
update public.profiles set nickname = '유저' where id = '00000000-0000-0000-0000-00000000000b';
update public.profiles set nickname = '유저2' where id = '00000000-0000-0000-0000-00000000000d';

select t.ok('초기 문서에 처음 버전 기록이 생김',
  (select count(*) = 1 from doc_revisions r join matchup_docs d on d.revision_id = r.id where r.kind = 'create'));

create temp table ids (k text primary key, v bigint);
grant all on ids to authenticated;
insert into ids values ('quinn', (select id from counters where counter_champion = 'Quinn'));

\set full '{"summary":"가렌 요약","level_notes":{"1":"a","2":"b","3":"c","6":"d","9":"e","11":"f","5":"  ","07":"칠"},"lane_cautions":" 주의 "}'

-- ===== 일반 유저 =====
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';

insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Garen', auth.uid(), :'full', t.build());
insert into ids select 'garen_p', id from edit_proposals where counter_champion = 'Garen';
select t.ok('새 카운터 제안: 빈 추가 레벨은 빠지고 "07"은 "7"로, 공백 정리',
  (select content = '{"summary":"가렌 요약","level_notes":{"1":"a","2":"b","3":"c","6":"d","7":"칠","9":"e","11":"f"},"lane_cautions":"주의"}'::jsonb
   from edit_proposals where id = (select v from ids where k = 'garen_p')));

select t.fails('같은 매치업에 대기 중인 내 제안 중복',
  $$insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
    values ('new_counter','Darius','Garen',auth.uid(),'{"summary":"x","level_notes":{"1":"a","2":"b","3":"c","6":"d","9":"e","11":"f"}}', t.build())$$,
  '이미 대기 중인 내 제안');
select t.fails('필수 레벨(6) 빠짐',
  $$insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
    values ('new_counter','Darius','Teemo',auth.uid(),'{"summary":"x","level_notes":{"1":"a","2":"b","3":"c","6":" ","9":"e","11":"f"}}', t.build())$$,
  '6레벨 딜교법은 꼭');
select t.fails('요약 없음',
  $$insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
    values ('new_counter','Darius','Teemo',auth.uid(),'{"summary":"","level_notes":{}}', t.build())$$, '한 줄 요약');
select t.fails('레벨 19',
  $$insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
    values ('new_counter','Darius','Teemo',auth.uid(),'{"summary":"x","level_notes":{"19":"a"}}', t.build())$$, '1~18');
select t.fails('특이사항 3001자 (011: 문구는 "특이사항")',
  format($$insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
    values ('new_counter','Darius','Teemo',auth.uid(),jsonb_build_object('summary','x','level_notes','{"1":"a","2":"b","3":"c","6":"d"}'::jsonb,'lane_cautions',%L), t.build())$$, repeat('x', 3000) || E'\n'),
  '특이사항은 3000자 이하로');
select t.fails('이미 있는 카운터(퀸)',
  $$insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
    values ('new_counter','Darius','Quinn',auth.uid(),'{"summary":"x","level_notes":{"1":"a","2":"b","3":"c","6":"d","9":"e","11":"f"}}', t.build())$$,
  '이미 등록된 카운터');
select t.fails('자기 자신 카운터',
  $$insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
    values ('new_counter','Darius','Darius',auth.uid(),'{"summary":"x","level_notes":{"1":"a","2":"b","3":"c","6":"d","9":"e","11":"f"}}', t.build())$$,
  '같은 챔피언끼리');
select t.fails('남의 이름으로 제안',
  $$insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
    values ('new_counter','Darius','Teemo','00000000-0000-0000-0000-00000000000d','{"summary":"x","level_notes":{"1":"a","2":"b","3":"c","6":"d","9":"e","11":"f"}}', t.build())$$,
  'row-level security');
select t.fails('처음부터 승인 상태로 넣기',
  $$insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, status, build)
    values ('new_counter','Darius','Teemo',auth.uid(),'{"summary":"x","level_notes":{"1":"a","2":"b","3":"c","6":"d","9":"e","11":"f"}}','approved', t.build())$$,
  'permission denied');
select t.fails('문서 수정: 바뀐 게 없음',
  format($$insert into edit_proposals (type, target_champion, counter_champion, counter_id, proposer_id, content)
    select 'doc_edit','x','y',%s,auth.uid(), jsonb_build_object('summary',summary,'level_notes',level_notes,'lane_cautions',lane_cautions)
    from matchup_docs where counter_id = %s$$, (select v from ids where k='quinn'), (select v from ids where k='quinn')),
  '달라진 내용이 없어요');

insert into edit_proposals (type, target_champion, counter_champion, counter_id, proposer_id, content, base_revision_id)
select 'doc_edit', 'Fake', 'Wrong', counter_id, auth.uid(),
  jsonb_build_object('summary', '고친 요약', 'level_notes', level_notes, 'lane_cautions', lane_cautions), revision_id
from matchup_docs where counter_id = (select v from ids where k = 'quinn');
insert into ids select 'edit_p', id from edit_proposals where type = 'doc_edit';
select t.ok('문서 수정 제안: 대상 챔피언은 카운터에서 가져옴 (보낸 Fake/Wrong 무시)',
  (select target_champion = 'Darius' and counter_champion = 'Quinn' and status = 'pending'
   from edit_proposals where id = (select v from ids where k = 'edit_p')));

select t.fails('일반 유저 승인', format($$select approve_proposal(%s, '좋아요', null, null, t.pv(%1$s))$$, (select v from ids where k='garen_p')), '운영자만');
select t.fails('일반 유저 거절', format($$select reject_proposal(%s, '싫음', t.pv(%1$s))$$, (select v from ids where k='garen_p')), '운영자만');
select t.fails('일반 유저 순서 변경', format($$select reorder_counters('Darius', array[%s]::bigint[])$$, (select v from ids where k='quinn')), '운영자만');
select t.fails('일반 유저 되돌리기', $$select revert_doc(1, '되돌림')$$, '운영자만');
select t.fails('일반 유저 제안 상태 직접 변경', 'update edit_proposals set status = ''approved''', 'permission denied');
select t.fails('일반 유저 순서 직접 변경', 'update counters set sort_order = 9', 'permission denied');
select t.fails('일반 유저 문서 직접 변경', 'update matchup_docs set summary = ''x''', 'permission denied');
select t.ok('일반 유저는 문서 기록을 못 봄', (select count(*) = 0 from doc_revisions));
select t.ok('내 제안 2개가 보임', (select count(*) = 2 from edit_proposals));

-- 다른 유저: 남의 제안 안 보임
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000d';
select t.ok('남의 제안은 안 보임', (select count(*) = 0 from edit_proposals));

-- 닉네임 없는 유저
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';
select t.fails('닉네임 없으면 제안 불가',
  $$insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
    values ('new_counter','Darius','Teemo',auth.uid(),'{"summary":"x","level_notes":{"1":"a","2":"b","3":"c","6":"d","9":"e","11":"f"}}', t.build())$$,
  'row-level security');

-- 로그인 안 한 사람
reset role;
set role anon;
set request.jwt.claim.sub = '';  -- 비로그인: 로그인 정보 없음
select t.fails('비로그인 승인 함수 호출', $$select approve_proposal(1, '좋아요', null, null, t.pv(1))$$, 'permission denied');
select t.ok('비로그인도 공개 문서는 읽음', (select count(*) = 1 from matchup_docs));

-- ===== 운영자 =====
reset role;
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select t.fails('운영자도 순서 직접 변경 불가', 'update counters set sort_order = 9', 'permission denied');
select t.fails('운영자도 문서 직접 변경 불가', 'update matchup_docs set summary = ''x''', 'permission denied');
select t.fails('운영자도 제안 상태 직접 변경 불가', 'update edit_proposals set status = ''approved''', 'permission denied');
select t.ok('운영자는 모든 제안을 봄', (select count(*) = 2 from edit_proposals));

select approve_proposal((select v from ids where k = 'garen_p'), '좋아요', null, null, t.pv((select v from ids where k = 'garen_p'))) as garen \gset
insert into ids values ('garen', :garen);
select t.ok('새 카운터 승인: 카운터 공개 + 맨 뒤 순서',
  (select status = 'approved' and sort_order = 2 and proposed_by = '00000000-0000-0000-0000-00000000000b' from counters where id = :garen));
select t.ok('새 카운터 승인: 문서 + 첫 기록(create) + 제안에 카운터 id',
  (select d.summary = '가렌 요약' and r.kind = 'create' and r.edited_by = '00000000-0000-0000-0000-00000000000b'
          and r.approved_by = auth.uid() and p.status = 'approved' and p.counter_id = :garen and p.reviewed_at is not null
   from matchup_docs d join doc_revisions r on r.id = d.revision_id join edit_proposals p on p.id = r.proposal_id
   where d.counter_id = :garen));
select t.fails('같은 제안 두 번 승인', format($$select approve_proposal(%s, '좋아요', null, null, t.pv(%1$s))$$, (select v from ids where k='garen_p')), '이미 처리된');
select t.fails('처리된 제안 거절', format($$select reject_proposal(%s, '사유', t.pv(%1$s))$$, (select v from ids where k='garen_p')), '이미 처리된');

-- 거절
reset role;
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000d';
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Teemo', auth.uid(), '{"summary":"티모","level_notes":{"1":"a","2":"b","3":"c","6":"d","9":"e","11":"f"}}', t.build());
insert into ids select 'teemo_p', id from edit_proposals where counter_champion = 'Teemo';
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select t.fails('거절 사유 없음', format($$select reject_proposal(%s, '   ', t.pv(%1$s))$$, (select v from ids where k='teemo_p')), '거절 사유를');
select t.fails('거절 사유 null', format($$select reject_proposal(%s, null, t.pv(%1$s))$$, (select v from ids where k='teemo_p')), '거절 사유를');
select reject_proposal((select v from ids where k = 'teemo_p'), '  근거가 부족해요 ', t.pv((select v from ids where k = 'teemo_p')));
select t.ok('거절: 상태·사유(공백 정리)·처리자', (select status = 'rejected' and reject_reason = '근거가 부족해요' and reviewed_by = auth.uid()
  from edit_proposals where id = (select v from ids where k = 'teemo_p')));
select t.ok('거절된 카운터는 생기지 않음', (select count(*) = 0 from counters where counter_champion = 'Teemo'));
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000d';
select t.ok('제안자는 거절 사유를 봄', (select reject_reason = '근거가 부족해요' from edit_proposals where id = (select v from ids where k = 'teemo_p')));
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';

-- 문서 수정 승인
select approve_proposal((select v from ids where k = 'edit_p'), '좋아요', null, null, t.pv((select v from ids where k = 'edit_p')));
select t.ok('문서 수정 승인: 문서 교체 + edit 기록 + 버전 갱신',
  (select d.summary = '고친 요약' and r.kind = 'edit' and r.proposal_id = (select v from ids where k = 'edit_p')
   from matchup_docs d join doc_revisions r on r.id = d.revision_id where d.counter_id = (select v from ids where k = 'quinn')));
select t.ok('퀸 문서 기록 2개', (select count(*) = 2 from doc_revisions where counter_id = (select v from ids where k = 'quinn')));

-- 순서 변경
select t.fails('순서: 하나 빠짐', format($$select reorder_counters('Darius', array[%s]::bigint[])$$, :garen), '목록이 바뀌었어요');
select t.fails('순서: 중복', format($$select reorder_counters('Darius', array[%s,%s,%s]::bigint[])$$, :garen, :garen, (select v from ids where k='quinn')), '목록이 바뀌었어요');
select t.fails('순서: 다른 챔피언 것 섞음', format($$select reorder_counters('Garen', array[%s]::bigint[])$$, :garen), '목록이 바뀌었어요');
select reorder_counters('Darius', array[:garen, (select v from ids where k = 'quinn')]::bigint[]);
select t.ok('순서 변경 저장', (select array_agg(counter_champion order by sort_order) = array['Garen','Quinn'] from counters where target_champion = 'Darius'));

-- 되돌리기
select t.fails('지금 버전으로 되돌리기', format($$select revert_doc(%s, '되돌림')$$, (select revision_id from matchup_docs where counter_id = (select v from ids where k='quinn'))), '이미 지금');
select revert_doc((select id from doc_revisions where counter_id = (select v from ids where k = 'quinn') and kind = 'create'), '처음 버전이 더 정확해요');
select t.ok('되돌리기: 처음 요약으로 돌아오고 revert 기록이 새로 생김',
  (select d.summary like '사거리로 일방적인 견제%' and r.kind = 'revert' and r.reverted_from is not null and r.edited_by = auth.uid()
   from matchup_docs d join doc_revisions r on r.id = d.revision_id where d.counter_id = (select v from ids where k = 'quinn')));
select t.ok('기록은 지워지지 않음 (3개)', (select count(*) = 3 from doc_revisions where counter_id = (select v from ids where k = 'quinn')));
select t.fails('없는 버전', $$select revert_doc(999999, '되돌림')$$, '찾지 못했어요');

reset role;
\echo ALL DONE
