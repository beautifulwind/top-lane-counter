-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 014: 경험치·레벨·칭호 — 지급, 회수(숨김·삭제), 한 번분만, 따봉 상한, 비주류 고정, 규칙 변경 다시 계산, 운영자 제외, 권한
-- (각 문장이 끝나면 커밋 → 그때 경험치 트리거가 돈다)
\set ON_ERROR_STOP 1
\set QUIET 1
\set A '00000000-0000-0000-0000-00000000000a'
\set B '00000000-0000-0000-0000-00000000000b'
\set D '00000000-0000-0000-0000-00000000000d'
insert into auth.users (id, email) values (:'A', 'op@x.com'), (:'B', 'u@x.com'), (:'D', 'u2@x.com');
insert into auth.users (id, email)
select ('00000000-0000-0000-0000-0000000001' || lpad(n::text, 2, '0'))::uuid, 'v' || n || '@x.com' from generate_series(1, 22) n;
update public.profiles set nickname = '영자', role = 'admin' where id = :'A';
update public.profiles set nickname = '유저' where id = :'B';
update public.profiles set nickname = '유저2' where id = :'D';
update public.profiles set nickname = '투표' || right(id::text, 2) where id::text like '00000000-0000-0000-0000-0000000001%';
create temp table ids (k text primary key, v bigint);
grant all on ids to authenticated;
\set doc '{"summary":"가렌 요약","level_notes":{"1":"a","2":"b","3":"c","6":"d"},"lane_cautions":""}'

create function pg_temp.xp(u uuid) returns integer language sql as $$ select xp from public.profiles where id = u $$;
create function pg_temp.lv(u uuid) returns integer language sql as $$ select level from public.profiles where id = u $$;
create function pg_temp.titles(u uuid) returns text[] language sql as $$
  select coalesce(array_agg(title_key order by title_key), '{}') from public.user_titles where user_id = u $$;
create function pg_temp.notes(u uuid, k text) returns integer language sql as $$
  select count(*)::integer from public.notifications where user_id = u and kind = k $$;
create function pg_temp.key_sum(u uuid, k text) returns integer language sql as $$
  select coalesce(sum(amount), 0)::integer from public.xp_events where user_id = u and source_key = k $$;
grant execute on all functions in schema pg_temp to authenticated;

select t.ok('설정: 레벨표 (0→1, 99→1, 100→2, 4500→10, 5499→10, 5500→11)',
  public.level_for(0) = 1 and public.level_for(99) = 1 and public.level_for(100) = 2
  and public.level_for(4500) = 10 and public.level_for(5499) = 10 and public.level_for(5500) = 11);
select t.ok('처음엔 모두 Lv.1 · 0, 운영자는 Lv.0', pg_temp.xp(:'B') = 0 and pg_temp.lv(:'B') = 1 and pg_temp.lv(:'A') = 0);

-- ===================================================================
-- 1. 새 카운터 승인 +100 (첫 빌드는 포함, +30 따로 없음) → Lv.2, 탑신병자, 알림
-- ===================================================================
set role authenticated;
set request.jwt.claim.sub = :'B';
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Garen', auth.uid(), :'doc', t.build());
insert into ids select 'garen_p', id from edit_proposals where counter_champion = 'Garen';
set request.jwt.claim.sub = :'A';
select approve_proposal((select v from ids where k = 'garen_p'), '좋아요', null, null, 1) as garen \gset
insert into ids values ('garen', :garen);
reset role;

select t.ok('새 카운터 +100 → Lv.2', pg_temp.xp(:'B') = 100 and pg_temp.lv(:'B') = 2);
select t.ok('첫 빌드는 +30 따로 없음', (select count(*) = 0 from xp_events where user_id = :'B' and type = 'build'));
select t.ok('내역: 지급 줄 (키·이유 없음·매치업 이름)',
  (select count(*) = 1 from xp_events where user_id = :'B' and source_key = 'proposal:' || (select v from ids where k = 'garen_p')
     and change = 'grant' and amount = 100 and type = 'new_counter' and reason is null
     and target_champion = 'Darius' and counter_champion = 'Garen'));
select t.ok('탑신병자', pg_temp.titles(:'B') = array['top_addict']);
select t.ok('알림: 레벨업 1 + 칭호 1',
  pg_temp.notes(:'B', 'level_up') = 1 and pg_temp.notes(:'B', 'title_earned') = 1
  and (select message = '레벨이 올랐어요: Lv.2' from notifications where user_id = :'B' and kind = 'level_up')
  and (select message like '칭호를 얻었어요: 탑신병자%' from notifications where user_id = :'B' and kind = 'title_earned'));
select t.ok('운영자는 처리해도 경험치·칭호 없음', pg_temp.xp(:'A') = 0 and pg_temp.lv(:'A') = 0 and pg_temp.titles(:'A') = '{}'
  and (select count(*) = 0 from xp_events where user_id = :'A'));

-- 대표 칭호: 내 칭호만
set role authenticated;
set request.jwt.claim.sub = :'B';
update profiles set main_title = 'top_addict' where id = auth.uid();
select t.fails('없는 칭호는 대표로 못 고름', $$update profiles set main_title = 'general' where id = auth.uid()$$, 'profiles_main_title_owned');
select t.fails('경험치는 직접 못 바꿈', $$update profiles set xp = 9999 where id = auth.uid()$$, 'permission denied');
select t.fails('경험치 기록 직접 넣기 불가', $$insert into xp_events (user_id, type, amount) values (auth.uid(), 'x', 1)$$, 'permission denied');
select t.fails('칭호 직접 넣기 불가', $$insert into user_titles (user_id, title_key) values (auth.uid(), 'general')$$, 'permission denied');
select t.ok('내 경험치 내역은 읽힘', (select count(*) = 1 from xp_events));
set request.jwt.claim.sub = :'D';
select t.ok('남의 경험치 내역은 안 보임', (select count(*) = 0 from xp_events));
select t.ok('칭호·레벨은 누구나 봄', (select count(*) = 1 from user_titles where user_id = :'B'));
reset role;

-- ===================================================================
-- 2. 숨김 → 회수, 다시 공개 → 다시 지급 (반복해도 한 번분)
-- ===================================================================
set role authenticated;
set request.jwt.claim.sub = :'A';
select hide_counter(:garen, '확인 필요');
reset role;
select t.ok('숨기면 −100 (이유: 카운터 숨김) → Lv.1, 0 아래로 안 감', pg_temp.xp(:'B') = 0 and pg_temp.lv(:'B') = 1
  and (select count(*) = 1 from xp_events where user_id = :'B' and change = 'revoke' and amount = -100 and reason = '카운터 숨김 (승인 취소)'));
select t.ok('탑신병자 회수 → 대표 칭호도 비워짐', pg_temp.titles(:'B') = '{}' and (select main_title is null from profiles where id = :'B'));
select t.ok('알림: 레벨 내려감 + 칭호 회수', pg_temp.notes(:'B', 'level_down') = 1 and pg_temp.notes(:'B', 'title_revoked') = 1);

set role authenticated;
set request.jwt.claim.sub = :'A';
select restore_counter(:garen, '다시 공개');
select hide_counter(:garen, '또 숨김');
select restore_counter(:garen, '또 공개');
reset role;
select t.ok('숨김↔공개 반복해도 그 키는 100 한 번분',
  pg_temp.xp(:'B') = 100 and pg_temp.key_sum(:'B', 'proposal:' || (select v from ids where k = 'garen_p')) = 100
  and (select count(*) = 5 from xp_events where user_id = :'B')
  and (select reason = '다시 공개·승인' from xp_events where user_id = :'B' order by id desc limit 1));

-- ===================================================================
-- 3. 문서 수정 +50, 빌드 +30 (숨기면 회수), 카운터 숨김은 문서 수정·빌드를 회수하지 않음
-- ===================================================================
set role authenticated;
set request.jwt.claim.sub = :'B';
insert into edit_proposals (type, counter_id, proposer_id, content)
values ('doc_edit', :garen, auth.uid(), '{"summary":"가렌 요약 v2","level_notes":{"1":"a","2":"b","3":"c","6":"d"},"lane_cautions":""}');
insert into ids select 'edit', max(id) from edit_proposals where type = 'doc_edit';
set request.jwt.claim.sub = :'D';
insert into builds (counter_id, author_id, runes, summoner_spells, starting_items, core_items, max_skill, patch)
select :garen, auth.uid(), b -> 'runes', array['SummonerFlash','SummonerTeleport'], array['1055','2003'], array['3071','3047','3053'],
       b ->> 'max_skill', '16.21.1' from (select t.build() as b) x;
insert into ids select 'dbuild', max(id) from builds where author_id = auth.uid();
set request.jwt.claim.sub = :'A';
select approve_proposal((select v from ids where k = 'edit'), '좋아요', null, null, 1);
select approve_build((select v from ids where k = 'dbuild'), '좋아요', null, 1);
reset role;
select t.ok('문서 수정 +50 → 150', pg_temp.xp(:'B') = 150);
select t.ok('빌드 +30, 탑신병자', pg_temp.xp(:'D') = 30 and pg_temp.titles(:'D') = array['top_addict']);

set role authenticated;
set request.jwt.claim.sub = :'A';
select hide_build((select v from ids where k = 'dbuild'), '이상함');
reset role;
select t.ok('빌드 숨기면 −30 (이유: 빌드 숨김), 칭호 회수', pg_temp.xp(:'D') = 0 and pg_temp.titles(:'D') = '{}'
  and (select reason = '빌드 숨김' from xp_events where user_id = :'D' order by id desc limit 1));
set role authenticated;
set request.jwt.claim.sub = :'A';
select restore_build((select v from ids where k = 'dbuild'), '다시');
reset role;
select t.ok('다시 공개 +30', pg_temp.xp(:'D') = 30);

-- ===================================================================
-- 4. 따봉: +2, 처음 누른 것만, 하루 +40 상한, 취소해도 회수 안 함
-- ===================================================================
set role authenticated;
do $$
declare n integer;
begin
  for n in 1..22 loop
    perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000001' || lpad(n::text, 2, '0'), false);
    perform vote_build((select v from ids where k = 'dbuild'), 1::smallint);
  end loop;
end $$;
reset role;
select t.ok('따봉 22개 → 하루 상한 +40 (20개분)', pg_temp.xp(:'D') = 70
  and (select count(*) = 20 from xp_events where user_id = :'D' and type = 'vote'));
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000101';
select vote_build((select v from ids where k = 'dbuild'), null);
select vote_build((select v from ids where k = 'dbuild'), 1::smallint);
select vote_build((select v from ids where k = 'dbuild'), -1::smallint);
reset role;
select t.ok('취소·다시 따봉·비추 반복: 늘지도 줄지도 않음', pg_temp.xp(:'D') = 70
  and (select count(*) = 1 from build_vote_log where voter_id = '00000000-0000-0000-0000-000000000101' and first_up));

-- 장군 (기준을 잠깐 낮춰 확인): 공개 중인 빌드의 지금 따봉 21개
update xp_rules set value = 21 where key = 'title_general';
select public.recalc_all_xp();
select t.ok('장군: 지금 따봉 21 ≥ 21', 'general' = any (pg_temp.titles(:'D')));
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-000000000102';
select vote_build((select v from ids where k = 'dbuild'), null);
reset role;
select t.ok('따봉이 취소돼 20 → 장군 회수 (경험치는 그대로)', not ('general' = any (pg_temp.titles(:'D'))) and pg_temp.xp(:'D') = 70);
update xp_rules set value = 100 where key = 'title_general';

-- ===================================================================
-- 5. 규칙 변경 → 다시 계산 (차이만 "규칙 변경")
-- ===================================================================
update xp_rules set value = 120 where key = 'new_counter';
select t.ok('다시 계산한 사람 수 (운영자 빼고 24명)', public.recalc_all_xp() = 24);
select t.ok('새 카운터 120 → +20 조정 줄', pg_temp.xp(:'B') = 170
  and (select count(*) = 1 from xp_events where user_id = :'B' and change = 'adjust' and amount = 20 and reason = '규칙 변경'));
select t.ok('다시 돌려도 변화 없음', (select count(*) from xp_events) = (select count(*) from xp_events)
  and public.recalc_all_xp() = 24 and pg_temp.xp(:'B') = 170);
update xp_rules set value = 100 where key = 'new_counter';
select public.recalc_all_xp();
select t.ok('되돌리면 다시 150', pg_temp.xp(:'B') = 150);

-- 카운터 관련 칭호 (기준을 잠깐 낮춰 확인): 새 카운터 + 문서 수정 = 2
update xp_rules set value = 2 where key = 'title_tool_hater';
select public.recalc_all_xp();
select t.ok('도구혐오자: 카운터 관련 승인 2 ≥ 2', pg_temp.titles(:'B') = array['tool_hater', 'top_addict']);
update xp_rules set value = 10 where key = 'title_tool_hater';
select public.recalc_all_xp();
select t.ok('기준을 되돌리면 회수', pg_temp.titles(:'B') = array['top_addict']);

-- ===================================================================
-- 6. 완전 삭제: 아직 남은 것 모두 회수 (숨길 때 회수한 새 카운터는 또 회수하지 않음), 내역은 남는다
-- ===================================================================
set role authenticated;
set request.jwt.claim.sub = :'A';
select hide_counter(:garen, '삭제 전');
reset role;
select t.ok('숨김: 새 카운터만 회수, 문서 수정·빌드·따봉은 유지', pg_temp.xp(:'B') = 50 and pg_temp.xp(:'D') = 70);
set role authenticated;
set request.jwt.claim.sub = :'A';
select delete_counter(:garen, 'Garen', '중복');
reset role;
select t.ok('삭제: 문서 수정 −50 → 0 (새 카운터는 이미 회수돼 또 회수 안 함)', pg_temp.xp(:'B') = 0
  and pg_temp.key_sum(:'B', 'proposal:' || (select v from ids where k = 'garen_p')) = 0
  and (select count(*) = 4 from xp_events where user_id = :'B' and change = 'revoke'));  -- 숨김 3번 + 삭제 1
select t.ok('삭제: 빌드 −30·따봉 −40 → 0, 이유 "카운터 삭제"', pg_temp.xp(:'D') = 0
  and (select count(*) = 1 from xp_events where user_id = :'D' and change = 'revoke' and type = 'build' and reason = '카운터 삭제')
  and (select count(*) = 20 from xp_events where user_id = :'D' and change = 'revoke' and type = 'vote' and reason = '빌드 삭제 (카운터 삭제)'));
select t.ok('지워진 카운터의 내역도 매치업 이름과 함께 남음',
  (select bool_and(counter_champion = 'Garen') from xp_events where user_id in (:'B', :'D')));
select t.ok('칭호 모두 회수', pg_temp.titles(:'B') = '{}' and pg_temp.titles(:'D') = '{}');

-- ===================================================================
-- 7. 비주류: 승인할 때 목록에 있었는지로 고정
-- ===================================================================
set role authenticated;
set request.jwt.claim.sub = :'B';
select t.fails('일반 유저는 비주류 목록 못 바꿈', $$select add_offmeta('Teemo')$$, '운영자만');
select t.fails('직접 넣기 불가', $$insert into offmeta_champions (champion_id) values ('Teemo')$$, 'permission denied');
set request.jwt.claim.sub = :'A';
select add_offmeta('Teemo');
select t.fails('같은 챔피언 두 번 불가', $$select add_offmeta('Teemo')$$, '이미 비주류');
reset role;

set role authenticated;
set request.jwt.claim.sub = :'B';
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Teemo', auth.uid(), :'doc', t.build()),
       ('new_counter', 'Darius', 'Akali', auth.uid(), :'doc', t.build());
insert into ids select 'teemo_p', id from edit_proposals where counter_champion = 'Teemo';
insert into ids select 'akali_p', id from edit_proposals where counter_champion = 'Akali';
set request.jwt.claim.sub = :'A';
select approve_proposal((select v from ids where k = 'teemo_p'), '좋아요', null, null, 1);
select remove_offmeta('Teemo');
select add_offmeta('Akali');
select approve_proposal((select v from ids where k = 'akali_p'), '좋아요', null, null, 1);
reset role;
select t.ok('승인할 때 기록: 티모(그때 목록에 있음) = 비주류, 아칼리(승인 때 추가됨) = 비주류',
  (select offmeta from edit_proposals where id = (select v from ids where k = 'teemo_p'))
  and (select offmeta from edit_proposals where id = (select v from ids where k = 'akali_p')));
set role authenticated;
set request.jwt.claim.sub = :'A';
select remove_offmeta('Akali');
reset role;
select t.ok('목록에서 빼도 이미 센 기여는 그대로',
  (select offmeta from edit_proposals where id = (select v from ids where k = 'akali_p')));
update xp_rules set value = 2 where key = 'title_offmeta';
select public.recalc_all_xp();
select t.ok('비주류 칭호 (기준 2 — 목록이 지금 비어 있어도)', 'offmeta' = any (pg_temp.titles(:'B')));
update xp_rules set value = 5 where key = 'title_offmeta';
select public.recalc_all_xp();

-- 숨겼다 다시 공개해도 처음 기록 그대로
set role authenticated;
set request.jwt.claim.sub = :'A';
select hide_counter((select id from counters where counter_champion = 'Teemo'), '잠깐');
select restore_counter((select id from counters where counter_champion = 'Teemo'), '다시');
reset role;
select t.ok('다시 공개해도 비주류 기록 유지', (select offmeta from edit_proposals where id = (select v from ids where k = 'teemo_p')));

-- ===================================================================
-- 8. 기존 데이터 계산 (알림 없음, 지급 날짜 = 실제 승인 날짜)
-- ===================================================================
delete from xp_events where user_id = :'B';
delete from notifications where user_id = :'B';
delete from user_titles where user_id = :'B';
update edit_proposals set reviewed_at = '2026-10-01T00:00:00Z' where id = (select v from ids where k = 'teemo_p');
select public.recalc_all_xp(true);
select t.ok('조용한 계산: 경험치·칭호는 채우고 알림 없음', pg_temp.xp(:'B') = 200 and pg_temp.titles(:'B') = array['top_addict']
  and (select count(*) = 0 from notifications where user_id = :'B'));
select t.ok('지급 줄 날짜 = 실제 승인 날짜',
  (select created_at = '2026-10-01T00:00:00Z' from xp_events where source_key = 'proposal:' || (select v from ids where k = 'teemo_p')));

-- ===================================================================
-- 9. 운영자에서 내려오지 않는 한 운영자는 계속 0 / 탈퇴하면 그 사람 기록만 지워짐
-- ===================================================================
select t.ok('운영자: 끝까지 Lv.0 · 0 · 칭호 없음', pg_temp.xp(:'A') = 0 and pg_temp.lv(:'A') = 0 and pg_temp.titles(:'A') = '{}');
delete from auth.users where id = :'D';
select t.ok('탈퇴: 그 사람 경험치 기록·칭호 삭제, 다른 사람 영향 없음',
  (select count(*) = 0 from xp_events where user_id = :'D') and pg_temp.xp(:'B') = 200);
