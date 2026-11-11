-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 038: 상대법 = 빌드 묶음, 위키 방식(무승인) 등록·수정, 수정 기록·기여자, 경험치·칭호, 알림·푸시, 기존 데이터 이전
\set ON_ERROR_STOP 1
\set QUIET 1
\set OP '00000000-0000-0000-0000-00000000000a'
\set U  '00000000-0000-0000-0000-00000000000d'
\set V  '00000000-0000-0000-0000-00000000000c'
\set W  '00000000-0000-0000-0000-00000000000f'
\set GU '00000000-0000-0000-0000-000000000010'
\set doc '{"summary":"요약","level_notes":{"1":"a","2":"b","3":"c","6":"d"},"lane_cautions":""}'
insert into auth.users (id, email) values (:'OP', 'op@x.com'), (:'U', 'u@x.com'), (:'V', 'v@x.com'), (:'W', 'w@x.com');
insert into auth.users (id, email, is_anonymous) values (:'GU', null, true);
update public.profiles set nickname = '영자', role = 'admin' where id = :'OP';
update public.profiles set nickname = '유저' where id = :'U';
update public.profiles set nickname = '브이' where id = :'V';
update public.profiles set nickname = '더블유' where id = :'W';
update public.profiles set nickname = '손님' where id = :'GU';
create temp table ids (k text primary key, v bigint);
grant all on ids to authenticated, anon;

-- ===== 0. 기존 데이터 이전 (fixtures의 다리우스 상대 퀸: 문서 1 + 공개 빌드 2) =====
select t.ok('승인 제도는 아직 켜짐 (038은 끄지 않음)', public.approval_on());
select public.wiki_backfill_matchups() as filled \gset
select t.ok('이전: 문서 내용이 공개 빌드 2개에 복사됨',
  (select count(*) from builds b join counters c on c.id = b.counter_id join matchup_docs d on d.counter_id = c.id
    where c.counter_champion = 'Quinn' and b.summary = d.summary and b.level_notes = d.level_notes and b.lane_cautions = d.lane_cautions) = 2);
select t.ok('이전: 번호 1·2', (select array_agg(b.seq order by b.id) from builds b join counters c on c.id = b.counter_id where c.counter_champion = 'Quinn') = array[1, 2]);
select t.ok('이전: 첫 빌드 지정', (select first_build_id = (select min(id) from builds where counter_id = c.id) from counters c where counter_champion = 'Quinn'));
select t.ok('이전: migrate 기록 빌드마다 1줄 (전 = 없음)',
  (select count(*) from build_revisions r join counters c on c.id = r.counter_id where c.counter_champion = 'Quinn' and r.kind = 'migrate' and r.before is null) = 2);
select public.wiki_backfill_matchups() as again \gset
select t.ok('이전을 다시 불러도 같은 결과', :again = 0 and (select count(*) from build_revisions) = 2);

-- ===== 1. 권한 =====
set role anon;
reset request.jwt.claim.sub;
select t.fails('비로그인: 새 상대법 불가', format($$select create_matchup('Darius', 'Garen', %L)$$, t.build() || :'doc'::jsonb), 'permission denied');
select t.fails('비로그인: 빌드 수정 불가', 'select edit_build(1, 1, null)', 'permission denied');
select t.fails('비로그인: 수정 기록 못 읽음', 'select * from build_revisions', 'permission denied');
reset role;
set role authenticated;
set request.jwt.claim.sub = :'U';
select t.fails('회원: 수정 기록 직접 못 읽음', 'select * from build_revisions', 'permission denied');
select t.fails('회원: 기여자 표 직접 못 읽음', 'select * from build_editors', 'permission denied');
select t.fails('회원: 간격 표 직접 못 읽음', 'select * from wiki_last_write', 'permission denied');
select t.fails('회원: 정리 함수 못 부름', 'select purge_old_build_revisions()', 'permission denied');
select t.fails('회원: 이전 함수 못 부름', 'select wiki_backfill_matchups()', 'permission denied');
reset role;

-- ===== 2. 새 상대법 (승인 없이 바로 공개) =====
set role authenticated;
set request.jwt.claim.sub = :'U';
select t.fails('같은 챔피언끼리 불가', format($$select create_matchup('Darius', 'Darius', %L)$$, t.build() || :'doc'::jsonb), '같은 챔피언끼리');
select t.fails('이미 있는 상대법 불가', format($$select create_matchup('Darius', 'Quinn', %L)$$, t.build() || :'doc'::jsonb), '이미 있는 상대법');
select t.fails('요약 없으면 불가', format($$select create_matchup('Darius', 'Garen', %L)$$, t.build() || '{"summary":" ","level_notes":{}}'::jsonb), '한 줄 요약');
select t.fails('6레벨 빠지면 불가', format($$select create_matchup('Darius', 'Garen', %L)$$,
  t.build() || '{"summary":"s","level_notes":{"1":"a","2":"b","3":"c"}}'::jsonb), '6레벨');
select t.fails('이름 21자 불가', format($$select create_matchup('Darius', 'Garen', %L)$$,
  t.build() || :'doc'::jsonb || jsonb_build_object('name', repeat('가', 21))), '20자');
select t.fails('핵심 템트리 검사 (전설 없음)', format($$select create_matchup('Darius', 'Garen', %L)$$, t.build(array['3047','1055','2003']) || :'doc'::jsonb), '');
select create_matchup('Darius', 'Garen', t.build() || :'doc'::jsonb || '{"name":"  "}'::jsonb) as m \gset
insert into ids values ('m1', (:'m'::jsonb ->> 'counter_id')::bigint), ('b1', (:'m'::jsonb ->> 'build_id')::bigint);
reset role;
select t.ok('상대법 바로 공개 + 시초 = 등록한 사람 + 위키 표시',
  (select status = 'approved' and proposed_by = :'U' and wiki and first_build_id = (select v from ids where k = 'b1') from counters where id = (select v from ids where k = 'm1')));
select t.ok('순서는 맨 뒤 (다리우스의 퀸 다음)', (select sort_order from counters where id = (select v from ids where k = 'm1')) = 2);
select t.ok('첫 빌드 바로 공개 · 번호 1 · 이름 공백은 비움 · 내용 저장',
  (select status = 'approved' and seq = 1 and name is null and summary = '요약' and level_notes ? '6' and wiki and updated_by = :'U'
     from builds where id = (select v from ids where k = 'b1')));
select t.ok('옛 화면용 문서 사본', exists (select 1 from matchup_docs where counter_id = (select v from ids where k = 'm1') and summary = '요약'));
select t.ok('create 수정 기록 (수정자·후 내용)', (select count(*) from build_revisions
  where build_id = (select v from ids where k = 'b1') and kind = 'create' and editor_id = :'U' and before is null and after ->> 'summary' = '요약') = 1);
select t.ok('운영자에게 matchup_created 알림 (상대법·빌드 연결)', (select count(*) from notifications
  where user_id = :'OP' and kind = 'matchup_created' and counter_id = (select v from ids where k = 'm1') and build_id = (select v from ids where k = 'b1')) = 1);
select t.ok('운영진 알림은 등록자·다른 회원에게 안 감', not exists (select 1 from notifications where user_id <> :'OP' and kind in ('matchup_created', 'build_created')));
select t.ok('새 상대법 경험치 +100 (첫 빌드 +30 따로 없음)', (select xp from profiles where id = :'U') = 100);
select t.ok('경험치 기록 키 matchup:<id>', exists (select 1 from xp_events where user_id = :'U' and source_key = 'matchup:' || (select v from ids where k = 'm1') and amount = 100));
select t.ok('푸시 묶음: 새 상대법·새 빌드 = 운영진 알림', push_group('matchup_created') = 'staff_new' and push_group('build_created') = 'staff_new');

-- ===== 3. 간격 · 새 빌드 =====
set role authenticated;
set request.jwt.claim.sub = :'U';
select t.fails('등록 간격 60초', format('select create_build(%s, %L)', (select v from ids where k = 'm1'), t.build(array['3071','3047','3053']) || :'doc'::jsonb), '초 뒤에');
reset role;
delete from wiki_last_write;
set role authenticated;
set request.jwt.claim.sub = :'U';
select t.fails('똑같은 공개 빌드 불가', format('select create_build(%s, %L)', (select v from ids where k = 'm1'), t.build() || :'doc'::jsonb), '똑같은 빌드');
reset role;
delete from wiki_last_write;
set role authenticated;
set request.jwt.claim.sub = :'U';
insert into ids select 'b2', create_build((select v from ids where k = 'm1'), t.build(array['3071','3047','3053']) || :'doc'::jsonb || '{"name":"라인전 빌드"}'::jsonb);
reset role;
select t.ok('새 빌드 바로 공개 · 번호 2 · 이름', (select status = 'approved' and seq = 2 and name = '라인전 빌드' from builds where id = (select v from ids where k = 'b2')));
select t.ok('새 빌드 경험치 +30', (select xp from profiles where id = :'U') = 130);
select t.ok('운영자에게 build_created 알림', exists (select 1 from notifications where user_id = :'OP' and kind = 'build_created' and build_id = (select v from ids where k = 'b2')));
select t.ok('예전 승인 대기 알림(build_submitted)은 안 생김', not exists (select 1 from notifications where kind = 'build_submitted'));

-- 비회원: 새 빌드·내 빌드 수정 가능, 남의 빌드 수정 불가
set role authenticated;
set request.jwt.claim.sub = :'GU';
insert into ids select 'bg', create_build((select v from ids where k = 'm1'), t.build(array['3074','3047','3053']) || :'doc'::jsonb);
select t.ok('비회원 내 빌드 수정 가능', edit_build((select v from ids where k = 'bg'), t.bv((select v from ids where k = 'bg')),
  t.build(array['3074','3047','3053']) || '{"summary":"비회원 요약","level_notes":{"1":"a","2":"b","3":"c","6":"d"}}'::jsonb) = 2);
reset role;
delete from wiki_last_write;
set role authenticated;
set request.jwt.claim.sub = :'GU';
select t.fails('비회원은 남의 빌드 수정 불가', format('select edit_build(%s, %s, %L)', (select v from ids where k = 'b1'), t.bv((select v from ids where k = 'b1')),
  t.build() || '{"summary":"훼손","level_notes":{"1":"a","2":"b","3":"c","6":"d"}}'::jsonb), '구글·카카오로 로그인한 회원만');
reset role;

-- ===== 4. 위키 수정 =====
set role authenticated;
set request.jwt.claim.sub = :'V';
select edit_build((select v from ids where k = 'b1'), 1,
  t.build() || '{"summary":"고친 요약","level_notes":{"1":"a","2":"b","3":"c","6":"d"},"lane_cautions":"주의"}'::jsonb) as v1 \gset
select t.ok('남의 빌드 수정 → 새 버전 2', :v1 = 2);
reset role;
select t.ok('수정 반영 · 마지막 수정자 · 글만 고쳐서 패치 그대로',
  (select summary = '고친 요약' and lane_cautions = '주의' and updated_by = :'V' and patch = '16.21.1' and author_id = :'U' from builds where id = (select v from ids where k = 'b1')));
select t.ok('edit 수정 기록: 수정자·전후 내용', (select count(*) from build_revisions where build_id = (select v from ids where k = 'b1') and kind = 'edit'
  and editor_id = :'V' and before ->> 'summary' = '요약' and after ->> 'summary' = '고친 요약' and version = 2) = 1);
select t.ok('기여자에 수정한 사람', exists (select 1 from build_editors where build_id = (select v from ids where k = 'b1') and user_id = :'V' and edits = 1));
select t.ok('수정에는 경험치 없음', (select xp from profiles where id = :'V') = 0);
select t.ok('수정에는 알림 없음 (운영자 알림 3개 그대로: 상대법 1 + 빌드 2)',
  (select count(*) from notifications where user_id = :'OP' and kind in ('matchup_created', 'build_created')) = 3);
set role authenticated;
set request.jwt.claim.sub = :'W';
select t.fails('본 버전이 옛것이면 TL412', format('select edit_build(%s, 1, %L)', (select v from ids where k = 'b1'),
  t.build() || '{"summary":"동시에","level_notes":{"1":"a","2":"b","3":"c","6":"d"}}'::jsonb), '다른 분이 먼저 수정했습니다. 최신 내용을 확인해 주세요.');
do $$ begin
  perform edit_build((select v from ids where k = 'b1'), 1, t.build() || '{"summary":"동시에","level_notes":{"1":"a","2":"b","3":"c","6":"d"}}'::jsonb);
  raise exception 'FAIL  TL412가 나야 함';
exception when sqlstate 'TL412' then raise notice 'PASS  오류 코드 TL412';
end $$;
select t.fails('바뀐 내용 없음', format('select edit_build(%s, 2, %L)', (select v from ids where k = 'b1'),
  t.build() || '{"summary":"고친 요약","level_notes":{"1":"a","2":"b","3":"c","6":"d"},"lane_cautions":"주의"}'::jsonb), '바뀐 내용이 없습니다');
select t.fails('다른 공개 빌드와 똑같게 고치기 불가', format('select edit_build(%s, 2, %L)', (select v from ids where k = 'b1'),
  t.build(array['3071','3047','3053']) || :'doc'::jsonb), '똑같은 빌드');
select t.fails('핵심 템트리 검사', format('select edit_build(%s, 2, %L)', (select v from ids where k = 'b1'),
  t.build(array['3047','1055','2003']) || :'doc'::jsonb), '');
select t.ok('아이템을 고치면 지금 패치로', edit_build((select v from ids where k = 'b1'), 2,
  t.build(array['6610','3047','3053'], '16.22.1') || '{"summary":"고친 요약","level_notes":{"1":"a","2":"b","3":"c","6":"d"},"lane_cautions":"주의"}'::jsonb) = 3);
select t.fails('수정 간격 10초', format('select edit_build(%s, %s, %L)', (select v from ids where k = 'b2'), t.bv((select v from ids where k = 'b2')),
  t.build(array['3071','3047','3053']) || '{"summary":"또","level_notes":{"1":"a","2":"b","3":"c","6":"d"}}'::jsonb), '초 뒤에');
reset role;
select t.ok('패치 16.22.1', (select patch from builds where id = (select v from ids where k = 'b1')) = '16.22.1');

-- 기여자 목록
set role anon;
reset request.jwt.claim.sub;
select build_contributors((select v from ids where k = 'b1')) as cs \gset
reset role;
select t.ok('기여자: 시초가 맨 앞 + 고친 순서', (select array_agg(e ->> 'nickname' order by o) from jsonb_array_elements(:'cs'::jsonb) with ordinality x(e, o)) = array['유저', '브이', '더블유']);
select t.ok('시초 표시는 별도 칸 (닉네임과 따로)', (select array_agg((e ->> 'is_origin')::boolean order by o) from jsonb_array_elements(:'cs'::jsonb) with ordinality x(e, o)) = array[true, false, false]);
-- 시초 본인이 고쳐도 기여자 줄이 늘지 않음
reset role;
delete from wiki_last_write;
set role authenticated;
set request.jwt.claim.sub = :'U';
select edit_build((select v from ids where k = 'b1'), 3,
  t.build(array['6610','3047','3053'], '16.22.1') || '{"summary":"시초가 다시","level_notes":{"1":"a","2":"b","3":"c","6":"d"}}'::jsonb) as v5 \gset
reset role;
select t.ok('시초 본인 수정은 기여자 표에 안 들어감', not exists (select 1 from build_editors where build_id = (select v from ids where k = 'b1') and user_id = :'U'));

-- ===== 5. 숨김 · 회수 · 숨긴 것 수정 불가 =====
set role authenticated;
set request.jwt.claim.sub = :'OP';
select hide_build((select v from ids where k = 'b2'), '테스트 숨김');
reset role;
select t.ok('빌드 숨기면 +30 회수', (select xp from profiles where id = :'U') = 100);
set role anon;
reset request.jwt.claim.sub;
select t.fails('숨긴 빌드의 기여자는 못 봄', format('select build_contributors(%s)', (select v from ids where k = 'b2')), '빌드를 찾지 못했습니다');
reset role;
delete from wiki_last_write;
set role authenticated;
set request.jwt.claim.sub = :'V';
select t.fails('숨긴 빌드 수정 불가', format('select edit_build(%s, %s, %L)', (select v from ids where k = 'b2'), t.bv((select v from ids where k = 'b2')),
  t.build(array['3071','3047','3053']) || '{"summary":"x","level_notes":{"1":"a","2":"b","3":"c","6":"d"}}'::jsonb), '공개된 빌드만');
set request.jwt.claim.sub = :'OP';
select hide_counter((select v from ids where k = 'm1'), '테스트 상대법 숨김');
reset role;
select t.ok('상대법 숨기면 +100 회수 (이유: 상대법 숨김)', (select xp from profiles where id = :'U') = 0
  and exists (select 1 from xp_events where user_id = :'U' and source_key = 'matchup:' || (select v from ids where k = 'm1') and reason = '상대법 숨김'));
set role authenticated;
set request.jwt.claim.sub = :'W';
select t.fails('숨긴 상대법에 새 빌드 불가', format('select create_build(%s, %L)', (select v from ids where k = 'm1'), t.build(array['3065','3047','3053']) || :'doc'::jsonb), '상대법을 찾지 못했습니다');
select t.fails('숨긴 상대법은 새로 등록 불가', format($$select create_matchup('Darius', 'Garen', %L)$$, t.build() || :'doc'::jsonb), '운영진이 숨긴 상대법');
set request.jwt.claim.sub = :'OP';
select restore_counter((select v from ids where k = 'm1'), '다시 공개');
reset role;
select t.ok('다시 공개하면 +100 다시', (select xp from profiles where id = :'U') = 100);

-- ===== 6. 하루 상한 (위키 등록만) =====
reset role;
update xp_rules set value = 150 where key = 'create_daily_cap';
delete from wiki_last_write;
set role authenticated;
set request.jwt.claim.sub = :'W';
select create_matchup('Garen', 'Teemo', t.build() || :'doc'::jsonb) as m2 \gset
reset role;
delete from wiki_last_write;
set role authenticated;
set request.jwt.claim.sub = :'W';
select create_build((:'m2'::jsonb ->> 'counter_id')::bigint, t.build(array['3071','3047','3053']) || :'doc'::jsonb);
reset role;
delete from wiki_last_write;
set role authenticated;
set request.jwt.claim.sub = :'W';
select create_build((:'m2'::jsonb ->> 'counter_id')::bigint, t.build(array['3074','3047','3053']) || :'doc'::jsonb) as b3 \gset
reset role;
select t.ok('하루 상한 150: 100 + 30만, 세 번째(30)는 상한 밖', (select xp from profiles where id = :'W') = 130);
update xp_rules set value = 200 where key = 'create_daily_cap';
select recalc_all_xp();
select t.ok('상한을 올리면 들어옴', (select xp from profiles where id = :'W') = 160);

-- ===== 7. 칭호: 상대법 + 빌드를 센다 =====
update xp_rules set value = 2 where key = 'title_tool_hater';
select recalc_all_xp();
select t.ok('도구혐오자(기준 2): 상대법 1 + 빌드 2 → 얻음', exists (select 1 from user_titles where user_id = :'W' and title_key = 'tool_hater'));
select t.ok('탑신병자: 첫 기여', exists (select 1 from user_titles where user_id = :'W' and title_key = 'top_addict'));
update xp_rules set value = 10 where key = 'title_tool_hater';
select recalc_all_xp();

-- ===== 8. 운영자 모드를 끄면 새 상대법·새 빌드 알림이 안 보임 =====
update profiles set operator_mode = false where id = :'OP';
set role authenticated;
set request.jwt.claim.sub = :'OP';
select t.ok('모드 끔: 운영진 알림 안 보임', not exists (select 1 from notifications where kind in ('matchup_created', 'build_created')));
select mark_all_notifications_read(9223372036854775807);
reset role;
select t.ok('모드 끔: 읽음 처리도 안 건드림', not exists (select 1 from notifications where user_id = :'OP' and kind in ('matchup_created', 'build_created') and read_at is not null));
update profiles set operator_mode = true where id = :'OP';

-- ===== 9. 승인 제도 스위치 (039가 끔) =====
update xp_rules set value = 0 where key = 'approval_on';
set role authenticated;
set request.jwt.claim.sub = :'V';
select t.fails('꺼지면 옛 빌드 등록(승인 대기) 거부', format($$insert into builds (counter_id, author_id, runes, summoner_spells, starting_items, core_items, max_skill, patch)
  select %s, %L, b -> 'runes', array['SummonerFlash','SummonerTeleport'], array['1055','2003'], array['3065','3047','3053'], 'Q', '16.21.1' from (select t.build() b) x$$,
  (select v from ids where k = 'm1'), :'V'), '승인 없이 바로 등록합니다');
select t.fails('꺼지면 옛 제안 거부', format($$insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
  values ('new_counter', 'Garen', 'Darius', %L, %L, %L)$$, :'V', :'doc', t.build()), '승인 없이 바로 등록합니다');
reset role;
delete from wiki_last_write;
set role authenticated;
set request.jwt.claim.sub = :'V';
select t.ok('꺼져도 위키 등록은 됨', create_build((select v from ids where k = 'm1'), t.build(array['3065','3047','3053']) || :'doc'::jsonb) > 0);
reset role;
update xp_rules set value = 1 where key = 'approval_on';

-- ===== 10. 038 ~ 039 사이 옛 길: 문서가 바뀌면 같은 내용 빌드에 반영, 승인된 빌드는 문서 내용으로 채움 =====
update matchup_docs set summary = '옛 길로 고친 요약', updated_by = :'V' where counter_id = (select id from counters where counter_champion = 'Quinn');
select t.ok('문서 수정 → 같은 내용 빌드 2개에 반영 + migrate 기록 + 기여자',
  (select count(*) from builds b join counters c on c.id = b.counter_id where c.counter_champion = 'Quinn' and b.summary = '옛 길로 고친 요약') = 2
  and (select count(*) from build_revisions r join counters c on c.id = r.counter_id where c.counter_champion = 'Quinn' and r.kind = 'migrate' and r.editor_id = :'V') = 2
  and (select count(*) from build_editors e join builds b on b.id = e.build_id join counters c on c.id = b.counter_id where c.counter_champion = 'Quinn' and e.user_id = :'V') = 2);
set role authenticated;
set request.jwt.claim.sub = :'V';
with i as (
  insert into builds (counter_id, author_id, runes, summoner_spells, starting_items, core_items, max_skill, patch)
  select c.id, :'V', b -> 'runes', array['SummonerFlash','SummonerTeleport'], array['1055','2003'], array['3065','3047','3053'], 'Q', '16.21.1'
  from counters c, (select t.build() b) x where c.counter_champion = 'Quinn' returning id)
insert into ids select 'pb', id from i;
reset role;
select t.ok('승인 대기 빌드는 번호·내용 없음', (select seq is null and summary is null from builds where id = (select v from ids where k = 'pb')));
set role authenticated;
set request.jwt.claim.sub = :'OP';
select approve_build((select v from ids where k = 'pb'), '승인', null, t.bv((select v from ids where k = 'pb')));
reset role;
select t.ok('옛 길 승인 → 번호 3 + 문서 내용으로 채움', (select seq = 3 and summary = '옛 길로 고친 요약' from builds where id = (select v from ids where k = 'pb')));
select public.wiki_backfill_matchups() as again2 \gset
select t.ok('옛 길 승인 빌드도 이전 함수가 migrate 기록을 남김', :again2 = 0
  and exists (select 1 from build_revisions where build_id = (select v from ids where k = 'pb') and kind = 'migrate'));

-- ===== 11. 탈퇴 · 완전 삭제 =====
delete from auth.users where id = :'V';
select t.ok('탈퇴: 기여자에서 빠지고 수정 기록의 수정자는 비움',
  not exists (select 1 from build_editors where user_id = :'V')
  and exists (select 1 from build_revisions where build_id = (select v from ids where k = 'b1') and kind = 'edit' and editor_id is null));
delete from auth.users where id = :'U';
set role anon;
reset request.jwt.claim.sub;
select t.ok('시초가 탈퇴하면 시초 줄은 이름 없이 남음', (build_contributors((select v from ids where k = 'b1')) -> 0 ->> 'user_id') is null
  and (build_contributors((select v from ids where k = 'b1')) -> 0 ->> 'is_origin')::boolean);
reset role;
set role authenticated;
set request.jwt.claim.sub = :'OP';
select hide_counter((:'m2'::jsonb ->> 'counter_id')::bigint, '삭제 전 숨김');
select delete_counter((:'m2'::jsonb ->> 'counter_id')::bigint, 'Teemo', '테스트 삭제');
reset role;
select t.ok('완전 삭제: 빌드·수정 기록도 함께', not exists (select 1 from build_revisions where counter_id = (:'m2'::jsonb ->> 'counter_id')::bigint)
  and not exists (select 1 from builds where counter_id = (:'m2'::jsonb ->> 'counter_id')::bigint));
select t.ok('완전 삭제: 등록 경험치 회수', (select xp from profiles where id = :'W') = 0);

-- ===== 12. 수정 기록 1년 정리 =====
update build_revisions set created_at = now() - interval '366 days' where id = (select min(id) from build_revisions);
select t.ok('1년 지난 기록만 지움', purge_old_build_revisions() = 1);
