-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 022: 강타는 새로 고를 수 없음 (예전 빌드는 그대로), 칭호 알림 문구 "칭호 'OO'"
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

create function pg_temp.add(spells text[]) returns void language sql as $$
  insert into public.builds (counter_id, author_id, runes, summoner_spells, starting_items, core_items, max_skill, patch)
  select (select v from ids where k = 'quinn'), auth.uid(), b -> 'runes', spells, array['1055','2003'], array['6631','3047','3053'], 'Q', '16.21.1'
  from (select t.build() as b) x;
$$;
grant execute on function pg_temp.add(text[]) to authenticated;
create function pg_temp.propose(b jsonb) returns void language sql as $$
  insert into public.edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
  values ('new_counter', 'Darius', 'Garen', auth.uid(),
          '{"summary":"요약","level_notes":{"1":"a","2":"b","3":"c","6":"d"},"lane_cautions":""}', b);
$$;
grant execute on function pg_temp.propose(jsonb) to authenticated;

-- ===== 1. 새로 고를 때는 막힘 =====
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select t.fails('빌드 등록: 강타 불가', $$select pg_temp.add(array['SummonerFlash','SummonerSmite'])$$, '강타는 고를 수 없어요');
select t.fails('새 카운터 제안: 강타 불가', $$select pg_temp.propose(t.build() || '{"summoner_spells":["SummonerSmite","SummonerFlash"]}')$$, '강타는 고를 수 없어요');
select pg_temp.add(array['SummonerFlash','SummonerTeleport']);
insert into ids select 'b', id from builds where author_id = auth.uid();
select t.fails('수정: 주문을 강타로 바꾸기 불가',
  format($$select edit_my_build(%s, %L)$$, (select v from ids where k = 'b'), t.build() || '{"summoner_spells":["SummonerFlash","SummonerSmite"]}'),
  '강타는 고를 수 없어요');
select pg_temp.propose(t.build());
select t.ok('강타 없으면 제안 됨', (select count(*) = 1 from edit_proposals where proposer_id = auth.uid() and status = 'pending'));

-- ===== 2. 예전 빌드는 그대로 =====
reset role;
alter table public.builds disable trigger builds_no_smite;
update builds set summoner_spells = array['SummonerSmite','SummonerFlash'] where id = (select v from ids where k = 'b');
alter table public.builds enable trigger builds_no_smite;
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select approve_build((select v from ids where k = 'b'), '좋아요', null, t.bv((select v from ids where k = 'b')));
select t.ok('강타가 든 예전 대기 빌드도 그대로 승인됨',
  (select status = 'approved' and summoner_spells @> array['SummonerSmite'] from builds where id = (select v from ids where k = 'b')));
select hide_build((select v from ids where k = 'b'), '잠깐 숨김');
select restore_build((select v from ids where k = 'b'), '다시 공개');
select t.ok('숨겼다 다시 공개해도 그대로', (select status = 'approved' from builds where id = (select v from ids where k = 'b')));

-- ===== 3. 칭호 알림 문구 =====
reset role;
select t.ok('조사: 받침 있으면 을, 없으면 를',
  title_josa('단단묵직', '을', '를') = '을' and title_josa('탑신병자', '을', '를') = '를' and title_josa('장군', '이', '가') = '이');
select t.ok('sync_rewards에 옛 문구가 없음',
  not exists (select 1 from pg_proc where proname = 'sync_rewards' and (prosrc like '%칭호를 얻었어요:%' or prosrc like '%칭호가 회수됐어요:%')));
