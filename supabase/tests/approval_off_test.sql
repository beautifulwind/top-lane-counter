-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 039: 승인 제도 끄기. (fixtures.sql이 예전 승인 검사를 위해 다시 켜 두므로, 여기서 039 값으로 되돌려 본다)
\set ON_ERROR_STOP 1
\set QUIET 1
\set U '00000000-0000-0000-0000-00000000000d'
\set doc '{"summary":"요약","level_notes":{"1":"a","2":"b","3":"c","6":"d"},"lane_cautions":""}'
insert into auth.users (id, email) values (:'U', 'u@x.com');
update public.profiles set nickname = '유저' where id = :'U';

select t.ok('039가 승인 스위치를 0으로 바꿈', (select value from t.approval_after_039) = 0);
select t.ok('039: 스위치 설명에 039 기록', (select note like '%039에서 0으로 끔%' from xp_rules where key = 'approval_on'));
select t.ok('039: 검토 중 표시 비움', not exists (select 1 from proposal_reviewing));

update xp_rules set value = (select value from t.approval_after_039) where key = 'approval_on';
select t.ok('approval_on() = false', not public.approval_on());

set role authenticated;
set request.jwt.claim.sub = :'U';
select t.fails('꺼짐: 옛 새 카운터 제안 거부', format($$insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
  values ('new_counter', 'Garen', 'Darius', %L, %L, %L)$$, :'U', :'doc', t.build()), '승인 없이 바로 등록합니다');
select t.fails('꺼짐: 옛 문서 수정 제안 거부', format($$insert into edit_proposals (type, target_champion, counter_champion, counter_id, proposer_id, content)
  select 'doc_edit', 'Darius', 'Quinn', id, %L, %L from counters where counter_champion = 'Quinn'$$, :'U', :'doc'), '승인 없이 바로 등록합니다');
select t.fails('꺼짐: 옛 승인 대기 빌드 거부', format($$insert into builds (counter_id, author_id, runes, summoner_spells, starting_items, core_items, max_skill, patch)
  select c.id, %L, b -> 'runes', array['SummonerFlash','SummonerTeleport'], array['1055','2003'], array['3065','3047','3053'], 'Q', '16.21.1'
  from counters c, (select t.build() b) x where c.counter_champion = 'Quinn'$$, :'U'), '승인 없이 바로 등록합니다');
select create_matchup('Darius', 'Garen', t.build() || :'doc'::jsonb) ->> 'build_id' as bid \gset
select t.ok('꺼짐: 새 상대법은 바로 공개', (select status = 'approved' from builds where id = :bid)
  and (select status = 'approved' from counters where target_champion = 'Darius' and counter_champion = 'Garen'));
reset role;
delete from wiki_last_write;
set role authenticated;
set request.jwt.claim.sub = :'U';
select create_build((select id from counters where counter_champion = 'Quinn'), t.build(array['3065','3047','3053']) || :'doc'::jsonb) as nb \gset
select t.ok('꺼짐: 새 빌드도 바로 공개', (select status = 'approved' from builds where id = :nb));
reset role;
