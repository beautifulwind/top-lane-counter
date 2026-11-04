-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 028: 핵심 템트리 종류(전설·서사·신발, 전설 1개 이상)와 자주 쓰는 아이템(frequent_items)
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

-- ===== 2. 빌드 등록 =====
select t.fails('물약은 핵심 템트리에 못 넣음', $$select pg_temp.add(array['2003','3181','3075'])$$, '전설·서사·신발 아이템만');
select t.fails('기본템(롱소드)도 못 넣음', $$select pg_temp.add(array['1036','3181','3075'])$$, '전설·서사·신발 아이템만');
select t.fails('가격표에 없는 아이템', $$select pg_temp.add(array['999999','3181','3075'])$$, '종류를 모르는 핵심 템트리 아이템');
select t.fails('전설 0개 (서사·신발만)', $$select pg_temp.add(array['3076','3077','3047'])$$, '전설 아이템을 1개 이상');
select pg_temp.add(array['3076','3181','3075']);
select t.ok('덤불 조끼 → 선체파괴자 → 가시 갑옷은 등록됨', (select count(*) = 1 from builds where author_id = auth.uid() and status = 'pending'));
insert into ids select 'b', id from builds where author_id = auth.uid();

-- 고치기: 핵심 템트리를 바꿀 때도 검사
select t.fails('고치기: 전설 0개',
  format($$select edit_my_build(%s, %L)$$, (select v from ids where k = 'b'), t.build(array['3076','3044','3047'])), '전설 아이템을 1개 이상');
select edit_my_build((select v from ids where k = 'b'), t.build(array['3076','3047','3075']));
select t.ok('고치기: 서사 + 신발 + 전설은 됨', (select core_items = array['3076','3047','3075'] from builds where id = (select v from ids where k = 'b')));

-- ===== 3. 예전 빌드는 그대로 승인됨 (핵심 템트리를 안 바꾸면 검사 안 함) =====
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
select t.ok('예전 빌드(물약 포함)를 그대로 승인', (select status = 'approved' from builds where id = (select v from ids where k = 'old')));

-- ===== 4. 새 카운터 제안의 빌드 =====
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select t.fails('제안: 물약이 든 핵심 템트리',
  $$insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
    values ('new_counter','Darius','Garen',auth.uid(),'{"summary":"s","level_notes":{"1":"a","2":"b","3":"c","6":"d"},"lane_cautions":""}',
            t.build(array['2003','3047','3053']))$$,
  '전설·서사·신발 아이템만');
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter','Darius','Garen',auth.uid(),'{"summary":"s","level_notes":{"1":"a","2":"b","3":"c","6":"d"},"lane_cautions":""}',
        t.build(array['3076','3181','3075']));
select t.ok('제안: 서사가 든 핵심 템트리는 됨', (select count(*) = 1 from edit_proposals where proposer_id = auth.uid() and type = 'new_counter'));
insert into ids select 'p', id from edit_proposals where proposer_id = auth.uid() and type = 'new_counter';

-- 운영자가 빌드를 고쳐서 승인할 때도 검사
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select t.fails('고쳐서 승인: 전설 0개',
  format($$select approve_proposal(%s, '메모', null, %L, t.pv(%1$s))$$, (select v from ids where k = 'p'), t.build(array['3076','3077','3047'])),
  '전설 아이템을 1개 이상');
select approve_proposal((select v from ids where k = 'p'), '서사 하나 바꿈', null, t.build(array['3077','3181','3075']), t.pv((select v from ids where k = 'p')));
select t.ok('고쳐서 승인: 서사 + 전설은 됨', (select status = 'approved' from edit_proposals where id = (select v from ids where k = 'p')));

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

-- ===== 6. 자주 쓰는 아이템 =====
select t.ok('처음 목록: 핵심 19개, 시작 9개',
  (select count(*) = 19 from frequent_items where slot = 'core') and (select count(*) = 9 from frequent_items where slot = 'starting'));
set role anon;
set request.jwt.claim.sub = '';
select t.ok('비로그인도 읽음', (select count(*) = 28 from frequent_items));
select t.fails('비로그인은 못 바꿈', $$select add_frequent_item('core', '3742')$$, 'permission denied');
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select t.fails('일반 유저는 추가 불가', $$select add_frequent_item('core', '3742')$$, '운영자만');
select t.fails('일반 유저는 빼기 불가', $$select remove_frequent_item('core', '3071')$$, '운영자만');
select t.fails('표 직접 수정 불가', $$insert into frequent_items (slot, item_id) values ('core', '3742')$$, 'permission denied');
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select add_frequent_item('core', '3742');
select t.ok('운영자: 망자의 갑옷 추가', exists (select 1 from frequent_items where slot = 'core' and item_id = '3742'));
select t.fails('이미 있는 아이템', $$select add_frequent_item('core', '3742')$$, '이미 자주 쓰는 아이템에');
select t.fails('핵심에 기본템', $$select add_frequent_item('core', '1036')$$, '전설·서사·신발 아이템만');
select t.fails('시작에 비싼 아이템', $$select add_frequent_item('starting', '3071')$$, '500골드 이하만');
select t.fails('가격표에 없는 아이템', $$select add_frequent_item('core', '999999')$$, '아이템 가격표에 없는');
select t.fails('모르는 칸', $$select add_frequent_item('boots', '3047')$$, '칸은');
select remove_frequent_item('core', '3742');
select t.ok('운영자: 빼기', not exists (select 1 from frequent_items where slot = 'core' and item_id = '3742'));
select t.fails('없는 것 빼기', $$select remove_frequent_item('core', '3742')$$, '자주 쓰는 아이템에 없는');
