-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 010: 레벨별 딜교법 필수 레벨 = 1/2/3/6 (9·11은 선택, 이미 있는 9·11 내용은 그대로)
\set ON_ERROR_STOP 1
\set QUIET 1
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'op@x.com'),
  ('00000000-0000-0000-0000-00000000000b', 'u@x.com');
update public.profiles set nickname = '영자', role = 'admin' where id = '00000000-0000-0000-0000-00000000000a';
update public.profiles set nickname = '유저' where id = '00000000-0000-0000-0000-00000000000b';
create temp table ids (k text primary key, v bigint);
grant all on ids to authenticated;
select id as quinn from counters where counter_champion = 'Quinn' \gset

select t.ok('표 제약은 하나만, 필수 1/2/3/6',
  (select count(*) = 1 and bool_and(pg_get_constraintdef(oid) like '%ARRAY[''1''::text, ''2''::text, ''3''::text, ''6''::text]%')
   from pg_constraint where conrelid = 'public.matchup_docs'::regclass and contype = 'c' and pg_get_constraintdef(oid) ~ 'level_notes \?&'));
select t.ok('예전 문서(퀸)의 9·11레벨 내용은 그대로', (select level_notes ?& array['9', '11'] from matchup_docs where counter_id = :quinn));

-- ===== 1. 제안: 9·11 없이 보낼 수 있다 =====
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Garen', auth.uid(), '{"summary":"가렌","level_notes":{"1":"a","2":"b","3":"c","6":"d"}}', t.build());
insert into ids select 'garen_p', id from edit_proposals where counter_champion = 'Garen';
select t.ok('9·11 없는 새 카운터 제안이 들어감',
  (select content -> 'level_notes' = '{"1":"a","2":"b","3":"c","6":"d"}'::jsonb from edit_proposals where id = (select v from ids where k = 'garen_p')));
select t.fails('6레벨은 여전히 필수',
  $$insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
    values ('new_counter','Darius','Teemo',auth.uid(),'{"summary":"x","level_notes":{"1":"a","2":"b","3":"c","9":"e","11":"f"}}', t.build())$$,
  '6레벨 딜교법은 꼭');
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Teemo', auth.uid(), '{"summary":"티모","level_notes":{"1":"a","2":"b","3":"c","6":"d","9":" ","11":"f"}}', t.build());
select t.ok('9·11은 추가 레벨: 빈 9는 빠지고 11은 남음',
  (select content -> 'level_notes' = '{"1":"a","2":"b","3":"c","6":"d","11":"f"}'::jsonb from edit_proposals where counter_champion = 'Teemo'));

-- 퀸 문서에서 9·11을 빼는 수정 제안
insert into edit_proposals (type, counter_id, proposer_id, content)
select 'doc_edit', :quinn, auth.uid(),
       jsonb_build_object('summary', summary, 'level_notes', level_notes - '9' - '11', 'lane_cautions', lane_cautions)
from matchup_docs where counter_id = :quinn;
insert into ids select 'quinn_p', id from edit_proposals where type = 'doc_edit';

-- ===== 2. 승인: 9·11 없는 문서도 표 제약을 통과 =====
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select approve_proposal((select v from ids where k = 'garen_p'), '승인', null, null) as garen \gset
select t.ok('9·11 없는 새 카운터 문서가 생김',
  (select level_notes = '{"1":"a","2":"b","3":"c","6":"d"}'::jsonb from matchup_docs where counter_id = :garen));
select approve_proposal((select v from ids where k = 'quinn_p'), '9·11 정리', null, null);
select t.ok('수정 제안으로 퀸 문서의 9·11을 뺄 수 있음',
  (select not (level_notes ? '9') and not (level_notes ? '11') and level_notes ?& array['1', '2', '3', '6'] from matchup_docs where counter_id = :quinn));
select t.ok('뺀 9·11 내용은 수정 기록에 남음',
  (select count(*) >= 1 from doc_revisions where counter_id = :quinn and content -> 'level_notes' ?& array['9', '11']));

-- ===== 3. 표 제약: 1/2/3/6 중 하나라도 없으면 거부 =====
reset role;
select t.fails('표에 직접 넣어도 6레벨 없으면 거부',
  format($$update matchup_docs set level_notes = level_notes - '6' where counter_id = %s$$, :garen), 'matchup_docs_level_notes_check');

