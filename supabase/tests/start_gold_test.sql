-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 018: 시작 아이템 합계 상한(xp_rules.starting_gold_max)과 아이템 가격표(item_prices), 선마 하나(max_skill)
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

create function pg_temp.add(starting text[], core text[] default array['6631','3047','3053']) returns void language sql as $$
  insert into public.builds (counter_id, author_id, runes, summoner_spells, starting_items, core_items, max_skill, patch)
  select (select v from ids where k = 'quinn'), auth.uid(), b -> 'runes', array['SummonerFlash','SummonerTeleport'], starting, core, 'E', '16.21.1'
  from (select t.build() as b) x;
$$;
grant execute on function pg_temp.add(text[], text[]) to authenticated;

-- ===== 1. 가격표·기준 금액은 누구나 읽음 =====
select t.ok('기준 금액 500', (select value = 500 from xp_rules where key = 'starting_gold_max'));
select t.ok('가격표: 처음 값 16.21.1, 도란의 검 450', (select gold = 450 and patch = '16.21.1' from item_prices where id = '1055'));
set role anon;
set request.jwt.claim.sub = '';
select t.ok('비로그인도 가격표를 읽음', (select count(*) > 100 from item_prices));
select t.fails('비로그인은 가격표를 못 바꿈', $$select set_item_prices('16.22.1', '{"1055": 1}')$$, 'permission denied');
set role authenticated;

-- ===== 2. 일반 유저는 가격표를 못 바꿈 =====
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select t.fails('일반 유저는 가격 갱신 불가', $$select set_item_prices('16.22.1', '{"1055": 1}')$$, '운영자만');
select t.fails('가격표 직접 수정 불가', $$update item_prices set gold = 1 where id = '1055'$$, 'permission denied');

-- ===== 3. 등록: 합계 500까지 (딱 500은 됨) =====
select pg_temp.add(array['1055','2003']);
select t.ok('도란의 검 + 물약 = 500골드는 등록됨', (select count(*) = 1 from builds where author_id = auth.uid() and status = 'pending' and max_skill = 'E'));
insert into ids select 'b', id from builds where author_id = auth.uid();

-- 고치기: 시작템이 합계를 넘으면 막힘
select t.fails('고치기: 합계 초과',
  format($$select edit_my_build(%s, %L)$$, (select v from ids where k = 'b'), t.build() || '{"starting_items":["1055","1054"]}'),
  '합계 500골드까지');
select t.ok('막히면 그대로', (select starting_items = array['1055','2003'] from builds where id = (select v from ids where k = 'b')));

-- ===== 4. 기준 금액을 바꾸면 바로 적용 =====
reset role;
update xp_rules set value = 1000 where key = 'starting_gold_max';
set role authenticated;
select edit_my_build((select v from ids where k = 'b'), t.build() || '{"starting_items":["1055","1054"]}');
select t.ok('기준 1000이면 900골드도 됨', (select starting_items = array['1055','1054'] from builds where id = (select v from ids where k = 'b')));
reset role;
update xp_rules set value = 500 where key = 'starting_gold_max';
set role authenticated;

-- ===== 5. 승인 대기 → 공개 때 다시 검사 (운영자가 고쳐서 승인하면 됨) =====
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select t.fails('합계를 넘는 대기 빌드는 그대로 승인 불가',
  format($$select approve_build(%s, '좋습니다', null, t.bv(%1$s))$$, (select v from ids where k = 'b')), '합계 500골드까지');
select approve_build((select v from ids where k = 'b'), '시작템을 줄였어요', t.build(), t.bv((select v from ids where k = 'b')));
select t.ok('고쳐서 승인하면 공개 (원래 빌드는 original_build에 선마와 함께)',
  (select status = 'approved' and starting_items = array['1055','2003'] and original_build -> 'starting_items' = '["1055","1054"]'::jsonb
          and original_build ->> 'max_skill' = 'Q' and not original_build ? 'skill_order'
   from builds where id = (select v from ids where k = 'b')));

-- ===== 6. 이미 공개된 빌드는 기준이 낮아져도 그대로 (숨겼다가 다시 공개해도) =====
reset role;
update xp_rules set value = 100 where key = 'starting_gold_max';
set role authenticated;
select hide_build((select v from ids where k = 'b'), '잠깐 숨김');
select restore_build((select v from ids where k = 'b'), '다시 공개');
select t.ok('숨겼다 다시 공개해도 검사하지 않음', (select status = 'approved' from builds where id = (select v from ids where k = 'b')));
reset role;
update xp_rules set value = 500 where key = 'starting_gold_max';
set role authenticated;

-- ===== 7. 운영자 가격 갱신 =====
select t.fails('패치 형식', $$select set_item_prices('latest', '{"1055": 450}')$$, '패치 버전 형식');
select t.fails('너무 적은 아이템', $$select set_item_prices('16.22.1', '{"1055": 450}')$$, '아이템이 너무 적습니다');
select t.fails('가격이 숫자가 아님',
  $$select set_item_prices('16.22.1', (select jsonb_object_agg(id, gold) from item_prices) || '{"1055": "450"}')$$, '가격표 형식');
select t.fails('가격이 음수',
  $$select set_item_prices('16.22.1', (select jsonb_object_agg(id, gold) from item_prices) || '{"1055": -1}')$$, '가격표 형식');
select t.ok('갱신: 아이템 수를 돌려줌',
  (select set_item_prices('16.22.1', (select jsonb_object_agg(id, gold) from item_prices where id <> '1036') || '{"1055": 600}')
   = (select count(*) - 1 from item_prices)));
select t.ok('갱신: 통째로 바뀜 (패치·가격, 빠진 아이템은 사라짐)',
  (select bool_and(patch = '16.22.1') from item_prices)
  and (select gold = 600 from item_prices where id = '1055')
  and not exists (select 1 from item_prices where id = '1036'));

set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select t.fails('새 가격으로 검사 (도란의 검 600 > 500)', $$select pg_temp.add(array['1055'], array['3071','3047','3053'])$$, '(지금 600골드)');
select t.fails('가격표에서 빠진 아이템은 못 고름', $$select pg_temp.add(array['1036'], array['3071','3047','3053'])$$, '가격을 모르는 시작 아이템');

-- ===== 8. 새 카운터 제안: 넣을 때와 고칠 때 =====
select t.fails('제안 넣을 때 합계 초과',
  $$insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
    values ('new_counter','Darius','Garen',auth.uid(),'{"summary":"s","level_notes":{"1":"a","2":"b","3":"c","6":"d"},"lane_cautions":""}',
            t.build() || '{"starting_items":["1054","2003","2003"]}')$$,
  '(지금 550골드)');
