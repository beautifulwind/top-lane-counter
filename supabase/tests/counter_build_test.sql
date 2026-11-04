-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 009: 새 카운터 제안 = 글 + 빌드 / 승인하면 첫 빌드 공개 / 재검토 때 같이 고침 / 마지막 공개 빌드 보호
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
select id as quinn from counters where counter_champion = 'Quinn' \gset

\set doc '{"summary":"가렌 요약","level_notes":{"1":"a","2":"b","3":"c","6":"d","9":"e","11":"f"},"lane_cautions":""}'
\set doc2 '{"summary":"가렌 고친 요약","level_notes":{"1":"a","2":"b","3":"c","6":"d","9":"e","11":"f"},"lane_cautions":""}'

create function pg_temp.propose(champ text, b jsonb) returns void language sql as $$
  insert into public.edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
  values ('new_counter', 'Darius', champ, auth.uid(),
          '{"summary":"요약","level_notes":{"1":"a","2":"b","3":"c","6":"d","9":"e","11":"f"},"lane_cautions":""}', b);
$$;
grant execute on function pg_temp.propose(text, jsonb) to authenticated;

-- ===== 1. 새 카운터 제안에는 빌드 필수 =====
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select t.fails('빌드 없는 새 카운터 제안 불가', $$select pg_temp.propose('Garen', null)$$, '빌드가 꼭 있어야');
select t.fails('빌드 칸이 객체가 아님', $$select pg_temp.propose('Garen', '[]')$$, '빌드(룬·주문·아이템·스킬)를 채워');
select t.fails('빌드 룬이 틀림', $$select pg_temp.propose('Garen', t.build() || '{"runes":{}}')$$, '특성(룬)을 모두');
select t.fails('빌드 핵심 템트리 2개', $$select pg_temp.propose('Garen', t.build(array['6631','3047']))$$, '3~6개');
select t.fails('빌드 주문 문자 아님', $$select pg_temp.propose('Garen', t.build() || '{"summoner_spells":[1,2]}')$$, '소환사 주문 형식');
select t.fails('빌드 선마 없음', $$select pg_temp.propose('Garen', t.build() - 'max_skill')$$, '선마(첫 번째로 마스터할 스킬)');
select t.fails('빌드 선마 R', $$select pg_temp.propose('Garen', t.build() || '{"max_skill":"R"}')$$, '선마(첫 번째로 마스터할 스킬)');
select t.fails('018: 빌드 시작템 합계 초과', $$select pg_temp.propose('Garen', t.build() || '{"starting_items":["1055","1054"]}')$$, '합계 500골드까지');
select t.fails('018: 빌드 시작템 가격 모름', $$select pg_temp.propose('Garen', t.build() || '{"starting_items":["999999"]}')$$, '가격을 모르는 시작 아이템');
select t.fails('빌드 패치 없음', $$select pg_temp.propose('Garen', t.build() - 'patch')$$, '패치 버전 형식');
select t.fails('문서 수정 제안에는 빌드 불가',
  format($$insert into edit_proposals (type, counter_id, proposer_id, content, build) values ('doc_edit', %s, auth.uid(), %L, t.build())$$, :quinn, :'doc'),
  '문서 수정 제안에는 빌드를 넣지 않아요');
select pg_temp.propose('Garen', t.build() || '{"runes":{"primaryPath":8000,"keystone":8010,"primary":["9111",9104,8299],"secondaryPath":8400,"secondary":[8444,8242],"shards":[5005,5008,5011]}}');
insert into ids select 'garen_p', id from edit_proposals where counter_champion = 'Garen';
select t.ok('제안의 빌드는 정리돼 저장됨 (룬 숫자)',
  (select build -> 'runes' -> 'primary' = '[9111,9104,8299]'::jsonb and build ->> 'patch' = '16.21.1'
   from edit_proposals where id = (select v from ids where k = 'garen_p')));
select t.fails('빌드 칸도 직접 상태를 못 넣음 (status 권한 없음)',
  $$insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build, status)
    values ('new_counter','Darius','Teemo',auth.uid(),'{}',t.build(),'approved')$$, 'permission denied');

-- ===== 2. 승인 → 카운터 + 첫 빌드 공개 =====
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select approve_proposal((select v from ids where k = 'garen_p'), '좋은 매치업', null, null, t.pv((select v from ids where k = 'garen_p'))) as garen \gset
insert into ids values ('garen', :garen);
select t.ok('승인: 첫 빌드 1개 공개 (작성자 = 제안자, 제안 연결, 승인 메모·처리자)',
  (select count(*) = 1 and bool_and(status = 'approved' and author_id = '00000000-0000-0000-0000-00000000000b'
     and proposal_id = (select v from ids where k = 'garen_p') and approve_note = '좋은 매치업' and reviewed_by = auth.uid()
     and core_items = array['6631','3047','3053'] and max_skill = 'Q' and patch = '16.21.1')
   from builds where counter_id = :garen));
insert into ids select 'g1', id from builds where counter_id = :garen;
select t.ok('첫 빌드 처리 기록 (승인)', (select count(*) = 1 from build_status_log where build_id = (select v from ids where k = 'g1') and action = 'approve' and reason = '좋은 매치업'));
set role anon;
set request.jwt.claim.sub = '';
select t.ok('비로그인에게 새 카운터와 첫 빌드가 보임',
  (select count(*) = 1 from counters where id = :garen) and (select count(*) = 1 from builds where counter_id = :garen));
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select t.ok('알림은 제안 승인 하나만 (빌드 승인 알림 따로 없음)',
  (select array_agg(kind) = array['proposal_approved'] from notifications where kind not in ('level_up', 'title_earned')));
select t.ok('/me: 첫 빌드가 내 빌드로 보임', (select count(*) = 1 from builds where author_id = auth.uid()));

-- ===== 3. 거절 → 빌드도 같이 거절 (빌드 표에는 안 들어감) =====
select pg_temp.propose('Teemo', t.build(array['3071','3047','3053']));
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select reject_proposal((select id from edit_proposals where counter_champion = 'Teemo'), '근거 부족', t.pv((select id from edit_proposals where counter_champion = 'Teemo')));
select t.ok('거절: 카운터·빌드 없음, 제안에 빌드는 남음 (/me에서 봄)',
  not exists (select 1 from counters where counter_champion = 'Teemo')
  and (select status = 'rejected' and build is not null from edit_proposals where counter_champion = 'Teemo'));

-- ===== 4. 마지막 공개 빌드는 숨길 수 없음 =====
select t.fails('마지막 공개 빌드 숨기기 불가', format($$select hide_build(%s, '별로')$$, (select v from ids where k = 'g1')), '마지막 공개 빌드라');
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000d';
insert into builds (counter_id, author_id, runes, summoner_spells, starting_items, core_items, max_skill, patch)
select :garen, auth.uid(), b -> 'runes', array['SummonerFlash','SummonerDot'], array['1055'], array['3071','3047','3053'], 'E', '16.21.1'
from (select t.build() b) x;
insert into ids select 'g2', id from builds where author_id = auth.uid();
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select approve_build((select v from ids where k = 'g2'), '좋아요', null, t.bv((select v from ids where k = 'g2')));
select hide_build((select v from ids where k = 'g1'), '다른 빌드가 더 좋음');
select t.ok('공개 빌드가 2개면 하나는 숨길 수 있음', (select status = 'hidden' from builds where id = (select v from ids where k = 'g1')));
select t.fails('남은 하나는 숨기기 불가', format($$select hide_build(%s, '별로')$$, (select v from ids where k = 'g2')), '마지막 공개 빌드라');
select restore_build((select v from ids where k = 'g1'), '다시');

-- ===== 5. 재검토: 글 + 빌드를 같이 고쳐 다시 제출 =====
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000d';
select vote_build((select v from ids where k = 'g1'), 1::smallint);
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select hide_counter(:garen, '빌드가 이상해요');
select request_revision(:garen, '빌드를 고쳐 주세요');
reset role;
select t.ok('재검토 시작값: 제안의 빌드 = 지금 첫 빌드 내용',
  (select build = (select build_json(b) from builds b where b.id = (select v from ids where k = 'g1'))
   from edit_proposals where id = (select v from ids where k = 'garen_p')));
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select t.fails('빌드 없이 다시 제출 불가', format($$select resubmit_proposal(%s, %L, null)$$, (select v from ids where k = 'garen_p'), :'doc2'), '빌드도 함께');
select t.fails('글·빌드 둘 다 그대로면 불가 (패치만 달라도)',
  format($$select resubmit_proposal(%s, (select content from edit_proposals where id = %1$s), t.build(patch => '16.22.1'))$$, (select v from ids where k = 'garen_p')), '고친 내용이 없어요');
select t.fails('다시 제출 빌드도 검사', format($$select resubmit_proposal(%s, %L, t.build(array['1']))$$, (select v from ids where k = 'garen_p'), :'doc'), '3~6개');
-- 빌드만 고침
select resubmit_proposal((select v from ids where k = 'garen_p'), (select content from edit_proposals where id = (select v from ids where k = 'garen_p')), t.build(array['6631','3047','3075']));
select t.ok('다시 제출: 대기 + 고친 빌드 저장',
  (select status = 'pending' and build -> 'core_items' = '["6631","3047","3075"]'::jsonb from edit_proposals where id = (select v from ids where k = 'garen_p')));
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select approve_proposal((select v from ids where k = 'garen_p'), '고친 빌드 좋아요', null, null, t.pv((select v from ids where k = 'garen_p')));
select t.ok('다시 승인: 카운터 공개', (select status = 'approved' from counters where id = :garen));
select t.ok('원래 첫 빌드는 숨김 (재검토로 교체), 추천 수는 그대로',
  (select status = 'hidden' and hide_reason = '재검토로 교체: 고친 빌드 좋아요' and up_count = 1 from builds where id = (select v from ids where k = 'g1')));
select t.ok('고친 빌드가 새 첫 빌드로 공개',
  (select count(*) = 1 from builds where proposal_id = (select v from ids where k = 'garen_p') and status = 'approved'
     and core_items = array['6631','3047','3075'] and approve_note = '고친 빌드 좋아요'));
select t.ok('다른 사람 빌드는 그대로 공개', (select status = 'approved' from builds where id = (select v from ids where k = 'g2')));
select t.ok('교체 기록 (숨김)', (select count(*) = 1 from build_status_log where build_id = (select v from ids where k = 'g1') and reason = '재검토로 교체: 고친 빌드 좋아요'));
insert into ids select 'g3', id from builds where proposal_id = (select v from ids where k = 'garen_p') and status = 'approved';

-- 글만 고치면 첫 빌드는 그대로
select hide_counter(:garen, '글이 이상해요');
select request_revision(:garen, '글을 고쳐 주세요');
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select resubmit_proposal((select v from ids where k = 'garen_p'), :'doc2',
  (select build from edit_proposals where id = (select v from ids where k = 'garen_p')));
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select approve_proposal((select v from ids where k = 'garen_p'), '글 좋아요', null, null, t.pv((select v from ids where k = 'garen_p')));
select t.ok('글만 고침: 첫 빌드 그대로 (새로 안 만듦)',
  (select status = 'approved' from builds where id = (select v from ids where k = 'g3'))
  and (select count(*) = 1 from builds where proposal_id = (select v from ids where k = 'garen_p') and status = 'approved')
  and (select count(*) = 3 from builds where counter_id = :garen));

-- 고친 빌드가 다른 사람의 공개 빌드와 똑같으면: 새로 안 만들고 원래 첫 빌드만 숨김 (공개 빌드는 남음)
select hide_counter(:garen, '또');
select request_revision(:garen, '다시');
reset role;
select build_json(b) as g2build from builds b where b.id = (select v from ids where k = 'g2') \gset
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select t.fails('도우미 함수는 직접 못 부름', 'select build_json(b) from builds b', 'permission denied');
select resubmit_proposal((select v from ids where k = 'garen_p'), :'doc2', :'g2build');
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select approve_proposal((select v from ids where k = 'garen_p'), '그 빌드면 충분', null, null, t.pv((select v from ids where k = 'garen_p')));
select t.ok('똑같은 공개 빌드가 있으면: 새 빌드 없음, 원래 첫 빌드 숨김, 공개 빌드 1개 이상',
  (select count(*) = 3 from builds where counter_id = :garen)
  and (select status = 'hidden' from builds where id = (select v from ids where k = 'g3'))
  and (select count(*) >= 1 from builds where counter_id = :garen and status = 'approved'));

-- ===== 6. 공개 빌드가 없는 숨긴 카운터는 다시 공개 불가 =====
select hide_counter(:garen, '마지막');
reset role;
update builds set status = 'hidden', hide_reason = '예전 데이터 흉내' where counter_id = :garen;
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select t.fails('공개 빌드 없으면 다시 공개 불가', format($$select restore_counter(%s, '다시')$$, :garen), '공개 빌드가 없어서');
select restore_build((select v from ids where k = 'g2'), '살림');
select restore_counter(:garen, '다시');
select t.ok('공개 빌드를 살리면 다시 공개 가능', (select status = 'approved' from counters where id = :garen));

-- ===== 7. 탈퇴: 제안은 지워져도 첫 빌드는 남음 (작성자·제안 연결만 비움) =====
reset role;
delete from auth.users where id = '00000000-0000-0000-0000-00000000000b';
select t.ok('탈퇴: 첫 빌드 남음, author_id·proposal_id 비움',
  (select count(*) = 2 and bool_and(author_id is null and proposal_id is null) from builds where id in (select v from ids where k in ('g1', 'g3'))));
