-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 028: 아이템 가격표 종류. 056: 핵심 템트리는 가격표에 있는 아이템이면 종류 상관없이 1~10칸, 중복 허용 (전설 1개 이상 규칙 없음)
\set ON_ERROR_STOP 1
\set QUIET 1
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'op@x.com'),
  ('00000000-0000-0000-0000-00000000000b', 'u@x.com');
update public.profiles set nickname = '영자', role = 'admin' where id = '00000000-0000-0000-0000-00000000000a';
update public.profiles set nickname = '유저' where id = '00000000-0000-0000-0000-00000000000b';
create temp table ids (k text primary key, v bigint);
grant all on ids to authenticated, anon;
insert into ids select 'quinn', id from counters where counter_champion = 'Quinn';

create function pg_temp.add(core text[]) returns void language sql as $$
  insert into public.builds (counter_id, author_id, runes, summoner_spells, starting_items, core_items, max_skill, patch)
  select (select v from ids where k = 'quinn'), auth.uid(), b -> 'runes', array['SummonerFlash','SummonerTeleport'], array['1055','2003'], core, 'E', '16.21.1'
  from (select t.build() as b) x;
$$;
grant execute on function pg_temp.add(text[]) to authenticated;

-- ===== 1. 가격표 종류 =====
select t.ok('가격표: 모든 줄에 종류', not exists (select 1 from item_prices where kind is null));
select t.ok('덤불 조끼·티아맷은 서사, 가시 갑옷은 전설, 판금 장화·건메탈 군화는 신발, 도란의 검은 기본, 물약은 소모품',
  (select kind = 'epic' from item_prices where id = '3076') and (select kind = 'epic' from item_prices where id = '3077')
  and (select kind = 'legendary' from item_prices where id = '3075') and (select kind = 'boots' from item_prices where id = '3047')
  and (select kind = 'boots' from item_prices where id = '3172') and (select kind = 'basic' from item_prices where id = '1055')
  and (select kind = 'consumable' from item_prices where id = '2003'));

set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';

-- ===== 2. 빌드 등록 (056: 가격표에 있으면 종류 상관없이, 1~10칸, 중복 횟수 제한 없음) =====
select t.fails('가격표에 없는 아이템', $$select pg_temp.add(array['999999','3181','3075'])$$, '종류를 모르는 핵심 템트리 아이템');
select t.fails('11칸은 안 됨', $$select pg_temp.add(array['6653','6653','6653','6653','6653','6653','6653','6653','6653','6653','6653'])$$, '핵심 템트리는 1~10개');
select t.fails('0칸은 안 됨', $$select pg_temp.add('{}')$$, '핵심 템트리는 1~10개');
-- 도란의 방패(기본) > 여신의 눈물(기본) > 물약(소모품) > 장신구 > 서포터템 > 신발 > 같은 전설 3번 > 전설 = 10칸
select pg_temp.add(array['1054','3070','2003','3340','3865','3047','6653','6653','6653','3053']);
select t.ok('기본템/소모품/장신구/서포터템 + 같은 아이템 3번, 10칸이 순서 그대로 등록됨',
  (select core_items = array['1054','3070','2003','3340','3865','3047','6653','6653','6653','3053'] and status = 'pending'
     from builds where author_id = auth.uid()));
insert into ids select 'b', id from builds where author_id = auth.uid();

-- 고치기: 핵심 템트리를 바꿀 때도 같은 규칙
select t.fails('고치기: 가격표에 없는 아이템',
  format($$select edit_my_build(%s, %L)$$, (select v from ids where k = 'b'), t.build(array['3076','999999'])), '종류를 모르는 핵심 템트리 아이템');
select t.fails('고치기: 11칸',
  format($$select edit_my_build(%s, %L)$$, (select v from ids where k = 'b'), t.build(array['1036','1036','1036','1036','1036','1036','1036','1036','1036','1036','1036'])), '1~10개');
select edit_my_build((select v from ids where k = 'b'), t.build(array['3070']));
select t.ok('고치기: 기본템 1칸(전설 없음)도 됨', (select core_items = array['3070'] from builds where id = (select v from ids where k = 'b')));
select edit_my_build((select v from ids where k = 'b'), t.build(array['6653','6653']));
select t.ok('고치기: 같은 아이템 2칸도 됨', (select core_items = array['6653','6653'] from builds where id = (select v from ids where k = 'b')));

-- ===== 3. 예전 빌드는 그대로 승인됨 (핵심 템트리를 안 바꾸면 검사 안 함, 데이터도 그대로) =====
reset role;
alter table public.builds disable trigger builds_core_items;
insert into public.builds (counter_id, author_id, runes, summoner_spells, starting_items, core_items, max_skill, patch)
select (select v from ids where k = 'quinn'), null, b -> 'runes', array['SummonerFlash','SummonerTeleport'],
       array['1055'], array['2003','3047','3053'], 'Q', '16.21.1'
from (select t.build() as b) x;
alter table public.builds enable trigger builds_core_items;
insert into ids select 'old', max(id) from builds where core_items = array['2003','3047','3053'];
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select approve_build((select v from ids where k = 'old'), '예전 빌드', null, t.bv((select v from ids where k = 'old')));
select t.ok('예전 빌드를 그대로 승인, 핵심 템트리도 그대로',
  (select status = 'approved' and core_items = array['2003','3047','3053'] from builds where id = (select v from ids where k = 'old')));

-- ===== 4. 새 카운터 제안의 빌드 =====
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select t.fails('제안: 가격표에 없는 아이템',
  $$insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
    values ('new_counter','Darius','Garen',auth.uid(),'{"summary":"s","level_notes":{"1":"a","2":"b","3":"c","6":"d"},"lane_cautions":""}',
            t.build(array['999999','3047','3053']))$$,
  '종류를 모르는 핵심 템트리 아이템');
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter','Darius','Garen',auth.uid(),'{"summary":"s","level_notes":{"1":"a","2":"b","3":"c","6":"d"},"lane_cautions":""}',
        t.build(array['1054','2003','2003']));
select t.ok('제안: 기본템 + 물약 2개도 됨',
  (select build -> 'core_items' = '["1054","2003","2003"]'::jsonb from edit_proposals where proposer_id = auth.uid() and type = 'new_counter'));
insert into ids select 'p', id from edit_proposals where proposer_id = auth.uid() and type = 'new_counter';

-- 운영자가 빌드를 고쳐서 승인할 때도 검사
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select t.fails('고쳐서 승인: 11칸',
  format($$select approve_proposal(%s, '메모', null, %L, t.pv(%1$s))$$, (select v from ids where k = 'p'),
    t.build(array['3070','3070','3070','3070','3070','3070','3070','3070','3070','3070','3070'])),
  '1~10개');
select approve_proposal((select v from ids where k = 'p'), '템트리 고침', null,
  t.build(array['1054','3070','3070','3070','3070','3070','3070','3070','3070','3075']), t.pv((select v from ids where k = 'p')));
select t.ok('고쳐서 승인: 같은 아이템 8번 든 10칸도 됨',
  (select status = 'approved' from edit_proposals where id = (select v from ids where k = 'p'))
  and exists (select 1 from builds where core_items = array['1054','3070','3070','3070','3070','3070','3070','3070','3070','3075']));

-- ===== 4-1. 위키 빌드 등록(038 create_build -> wiki_insert_build)도 같은 규칙 =====
reset role;
update xp_rules set value = 0 where key = 'approval_on';
delete from wiki_last_write;
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select t.fails('위키 등록: 가격표에 없는 아이템',
  format('select create_build(%s, %L)', (select v from ids where k = 'quinn'),
    t.build(array['999999']) || '{"summary":"요약","level_notes":{"1":"a","2":"b","3":"c","6":"d"},"lane_cautions":""}'::jsonb),
  '종류를 모르는 핵심 템트리 아이템');
select create_build((select v from ids where k = 'quinn'),
  t.build(array['1054','6653','6653']) || '{"summary":"요약","level_notes":{"1":"a","2":"b","3":"c","6":"d"},"lane_cautions":""}'::jsonb) as wb \gset
select t.ok('위키 등록: 도란의 방패 + 같은 전설 2번 됨', (select core_items = array['1054','6653','6653'] and status = 'approved' from builds where id = :wb));
reset role;
update xp_rules set value = 1 where key = 'approval_on';
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';

-- ===== 5. 가격 갱신은 종류도 받는다 =====
select t.fails('종류가 빠진 아이템',
  $$select set_item_prices('16.22.1', (select jsonb_object_agg(id, gold) from item_prices), (select jsonb_object_agg(id, kind) from item_prices where id <> '3076'))$$,
  '아이템 종류 형식');
select t.fails('모르는 종류',
  $$select set_item_prices('16.22.1', (select jsonb_object_agg(id, gold) from item_prices), (select jsonb_object_agg(id, kind) from item_prices) || '{"3076": "mythic"}')$$,
  '아이템 종류 형식');
select t.ok('갱신: 아이템 수를 돌려줌',
  (select set_item_prices('16.22.1', (select jsonb_object_agg(id, gold) from item_prices), (select jsonb_object_agg(id, kind) from item_prices) || '{"3076": "legendary"}') > 100));
select t.ok('갱신: 종류도 바뀜', (select kind = 'legendary' from item_prices where id = '3076'));
