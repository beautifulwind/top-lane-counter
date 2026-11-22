-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 065: 빌드 스킬 순서 상세 입력 (builds.skill_sequence) — 규칙·예외 챔피언, 화면 우회(RPC 직접) 거부,
--      옛 앱(칸 없이 수정) 원래 순서 유지, null로 지우기, 순서만 고쳐도 수정 기록·되돌리기, 순서만 다른 빌드는 같은 빌드
\set ON_ERROR_STOP 1
\set QUIET 1
\set OP  '00000000-0000-0000-0000-00000000000a'
\set U   '00000000-0000-0000-0000-00000000000d'
\set V   '00000000-0000-0000-0000-00000000000c'
\set doc '{"summary":"요약","level_notes":{"1":"a","2":"b","3":"c","6":"d"},"lane_cautions":""}'
insert into auth.users (id, email) values (:'OP', 'op@x.com'), (:'U', 'u@x.com'), (:'V', 'v@x.com');
update public.profiles set nickname = '영자', role = 'admin' where id = :'OP';
update public.profiles set nickname = '유저' where id = :'U';
update public.profiles set nickname = '브이' where id = :'V';
update public.xp_rules set value = 0 where key in ('wiki_create_interval', 'build_edit_interval');
create temp table ids (k text primary key, v bigint);
grant all on ids to authenticated, anon;
create function pg_temp.id(p text) returns bigint language sql stable as $$ select v from ids where k = p $$;
select format('create function pg_temp.doc() returns jsonb language sql immutable as %L', format('select %L::jsonb', :'doc')) as mkdoc \gset
:mkdoc;

-- ===== 1. 규칙 (기본: Q·W·E 5번, R 3번 6·11·16렙부터, Q·W·E는 레벨/2 올림까지) =====
select t.ok('칸 있음 + 형식 검사 있음',
  exists (select 1 from information_schema.columns where table_name = 'builds' and column_name = 'skill_sequence')
  and exists (select 1 from pg_constraint where conname = 'builds_skill_sequence_format'));
select t.ok('옛 이름 skill_order 칸은 여전히 없음',
  not exists (select 1 from information_schema.columns where table_name = 'builds' and column_name = 'skill_order'));
select t.ok('null은 문제없음', skill_sequence_problem(null, 'Garen') is null);
select t.ok('18렙까지 정상 (Q5·W5·E5·R3)', skill_sequence_problem('QWEQQRQEQERWWEERWW', 'Garen') is null);
select t.ok('7렙까지만 정상', skill_sequence_problem('QWEQQRQ', 'Garen') is null);
select t.ok('1칸만 정상', skill_sequence_problem('E', 'Garen') is null);
select t.ok('R 5렙 거부', skill_sequence_problem('QWEQR', 'Garen') = '스킬 순서 5렙: R은 6렙부터 찍을 수 있습니다.');
select t.ok('R 1렙 거부', skill_sequence_problem('R', 'Garen') = '스킬 순서 1렙: R은 6렙부터 찍을 수 있습니다.');
select t.ok('두 번째 R 10렙 거부', skill_sequence_problem('QWEQQRQEQR', 'Garen') = '스킬 순서 10렙: 두 번째 R은 11렙부터 찍을 수 있습니다.');
select t.ok('세 번째 R 15렙 거부', skill_sequence_problem('QWEQQRQEQERWWER', 'Garen') = '스킬 순서 15렙: 세 번째 R은 16렙부터 찍을 수 있습니다.');
select t.ok('R 4번 거부', skill_sequence_problem('QWEQQRQEQERWWEERWR', 'Garen') = '스킬 순서 18렙: R은 3번까지 찍을 수 있습니다.');
select t.ok('2렙 Q 두 번 거부', skill_sequence_problem('QQ', 'Garen') = '스킬 순서 2렙: 2렙에는 Q를 1번까지 찍을 수 있습니다.');
select t.ok('3렙 Q 세 번 거부', skill_sequence_problem('QQQ', 'Garen') ~ '^스킬 순서 2렙');
select t.ok('6렙 Q 네 번 거부', skill_sequence_problem('QWQEQQ', 'Garen') = '스킬 순서 6렙: 6렙에는 Q를 3번까지 찍을 수 있습니다.');
select t.ok('Q 6번 거부', skill_sequence_problem('QWQEQRQEQQ', 'Garen') = '스킬 순서 10렙: Q는 5번까지 찍을 수 있습니다.');
select t.ok('소문자 거부', skill_sequence_problem('qwe', 'Garen') like '스킬 순서는 Q%R만 1~18칸까지%');
select t.ok('다른 글자 거부', skill_sequence_problem('QWX', 'Garen') like '스킬 순서는%');
select t.ok('19칸 거부', skill_sequence_problem('QWEQQRQEQERWWEERWWQ', 'Garen') like '스킬 순서는%');
select t.ok('빈 글자 거부 (화면은 null로 보냄)', skill_sequence_problem('', 'Garen') like '스킬 순서는%');
-- 예외 챔피언: 형식만 (loose) / 상세 순서 없음 (hidden)
select t.ok('예외 표', skill_sequence_mode('Udyr') = 'loose' and skill_sequence_mode('Jayce') = 'loose' and skill_sequence_mode('Elise') = 'loose'
  and skill_sequence_mode('Nidalee') = 'loose' and skill_sequence_mode('Karma') = 'loose' and skill_sequence_mode('Aphelios') = 'hidden'
  and skill_sequence_mode('Garen') = 'strict' and skill_sequence_mode(null) = 'strict');
select t.ok('우디르: 레벨 규칙 없이 통과', skill_sequence_problem('RRRRRRQQ', 'Udyr') is null);
select t.ok('카르마·제이스: 1렙 R 통과', skill_sequence_problem('RQWE', 'Karma') is null and skill_sequence_problem('RQ', 'Jayce') is null);
select t.ok('예외도 형식은 검사', skill_sequence_problem('RX', 'Udyr') like '스킬 순서는%'
  and skill_sequence_problem(repeat('Q', 19), 'Nidalee') like '스킬 순서는%');
select t.ok('아펠리오스: 상세 순서 불가', skill_sequence_problem('QWE', 'Aphelios') = '이 챔피언은 스킬을 직접 찍지 않아 상세 순서를 적을 수 없습니다.'
  and skill_sequence_problem(null, 'Aphelios') is null);

-- ===== 2. 권한: 새 함수는 아무도 직접 못 부름 =====
set role authenticated;
set request.jwt.claim.sub = :'U';
select t.fails('회원: 규칙 함수 직접 불가', $$select skill_sequence_problem('Q', 'Garen')$$, 'permission denied');
select t.fails('회원: 검사 함수 직접 불가', $$select check_skill_sequence('Q', 1)$$, 'permission denied');
select t.fails('회원: 예외 표 함수 직접 불가', $$select skill_sequence_mode('Udyr')$$, 'permission denied');
select t.fails('회원: 빌드 직접 고치기 불가', $$update builds set skill_sequence = 'Q'$$, 'permission denied');

-- ===== 3. 등록 (화면 우회 = RPC 직접 호출도 같은 검사) =====
select t.fails('등록: 6렙 전 R 거부', $$select create_matchup('Darius', 'Garen', t.build() || pg_temp.doc() || '{"skill_sequence":"QWEQR"}')$$,
  'R은 6렙부터');
select t.fails('등록: 숫자 거부', $$select create_matchup('Darius', 'Garen', t.build() || pg_temp.doc() || '{"skill_sequence":123}')$$,
  '스킬 순서 형식이 잘못됐습니다');
select t.fails('등록: 소문자 거부', $$select create_matchup('Darius', 'Garen', t.build() || pg_temp.doc() || '{"skill_sequence":"qwe"}')$$,
  '1~18칸까지');
select t.fails('등록: 19칸 거부', format($$select create_matchup('Darius', 'Garen', t.build() || pg_temp.doc() || '{"skill_sequence":%s}')$$,
  to_jsonb(repeat('Q', 19))), '1~18칸까지');
select t.fails('등록: 아펠리오스는 상세 순서 불가', $$select create_matchup('Darius', 'Aphelios', t.build() || pg_temp.doc() || '{"skill_sequence":"QWE"}')$$,
  '직접 찍지 않아');
select t.ok('거부된 등록은 상대법도 남기지 않음', not exists (select 1 from counters where target_champion = 'Darius' and counter_champion in ('Garen', 'Aphelios')));
select create_matchup('Darius', 'Garen', t.build() || pg_temp.doc() || '{"skill_sequence":"QWEQQR"}') as m \gset
insert into ids values ('m1', (:'m'::jsonb ->> 'counter_id')::bigint), ('b1', (:'m'::jsonb ->> 'build_id')::bigint);
select create_matchup('Darius', 'Udyr', t.build() || pg_temp.doc() || '{"skill_sequence":"RRRR"}') as mu \gset
insert into ids values ('bu', (:'mu'::jsonb ->> 'build_id')::bigint);
select create_matchup('Darius', 'Aphelios', t.build() || pg_temp.doc() || '{"skill_sequence":null}') as ma \gset
insert into ids values ('ba', (:'ma'::jsonb ->> 'build_id')::bigint);
-- 옛 앱: 칸 없이 등록 → null / 빈 글자 → null
insert into ids values ('b2', create_build(pg_temp.id('m1'), t.build(array['6631','3047','3071']) || pg_temp.doc()));
insert into ids values ('b3', create_build(pg_temp.id('m1'), t.build(array['6631','3053','3071']) || pg_temp.doc() || '{"skill_sequence":""}'));
select t.fails('새 빌드: 규칙 거부', format($$select create_build(%s, t.build(array['3071','3047','3053']) || pg_temp.doc() || '{"skill_sequence":"QQ"}')$$,
  pg_temp.id('m1')), '2렙에는 Q를 1번까지');
select t.fails('순서만 다른 빌드는 같은 빌드로 막음', format($$select create_build(%s, t.build() || pg_temp.doc() || '{"skill_sequence":"EWQEER"}')$$,
  pg_temp.id('m1')), '똑같은');
reset role;
select t.ok('등록: 순서 저장', (select skill_sequence from builds where id = pg_temp.id('b1')) = 'QWEQQR');
select t.ok('등록: 우디르 형식만 검사', (select skill_sequence from builds where id = pg_temp.id('bu')) = 'RRRR');
select t.ok('등록: 아펠리오스 null 통과', (select skill_sequence is null from builds where id = pg_temp.id('ba')));
select t.ok('등록: 칸 없음·빈 글자 = null', (select count(*) from builds where id in (pg_temp.id('b2'), pg_temp.id('b3')) and skill_sequence is null) = 2);
select t.ok('등록 기록(create)에 순서', (select after ->> 'skill_sequence' from build_revisions where build_id = pg_temp.id('b1') and kind = 'create') = 'QWEQQR'
  and (select after ? 'skill_sequence' and after -> 'skill_sequence' = 'null'::jsonb from build_revisions where build_id = pg_temp.id('b2') and kind = 'create'));
select t.fails('표 규칙: 직접 넣어도 형식 검사 (관리자 SQL)', format($$update builds set skill_sequence = 'QX' where id = %s$$, pg_temp.id('b1')), 'builds_skill_sequence_format');
select t.fails('표 규칙: 빈 글자 불가', format($$update builds set skill_sequence = '' where id = %s$$, pg_temp.id('b1')), 'builds_skill_sequence_format');

-- ===== 4. 수정 =====
select patch as p1 from builds where id = pg_temp.id('b1') \gset
set role authenticated;
set request.jwt.claim.sub = :'V';
-- 옛 앱: 칸 없이 글만 고침 → 순서 그대로
select edit_build(pg_temp.id('b1'), 1, t.build() || pg_temp.doc() || '{"summary":"옛 앱이 고침"}');
reset role;
select t.ok('옛 앱(칸 없음) 수정: 순서 그대로', (select skill_sequence = 'QWEQQR' and summary = '옛 앱이 고침' and version = 2 from builds where id = pg_temp.id('b1')));
set role authenticated;
set request.jwt.claim.sub = :'V';
select t.fails('같은 순서를 보내고 다른 것도 같으면 바뀐 것 없음',
  format($$select edit_build(%s, 2, t.build() || pg_temp.doc() || '{"summary":"옛 앱이 고침","skill_sequence":"QWEQQR"}')$$, pg_temp.id('b1')), '바뀐 내용이 없습니다');
select t.fails('칸 없이 보내고 다른 것도 같으면 바뀐 것 없음',
  format($$select edit_build(%s, 2, t.build() || pg_temp.doc() || '{"summary":"옛 앱이 고침"}')$$, pg_temp.id('b1')), '바뀐 내용이 없습니다');
select t.fails('수정: 규칙 거부 (RPC 직접)',
  format($$select edit_build(%s, 2, t.build() || pg_temp.doc() || '{"summary":"옛 앱이 고침","skill_sequence":"QWEQQRR"}')$$, pg_temp.id('b1')),
  '두 번째 R은 11렙부터');
-- 순서만 고침 → 패치 그대로, 기록 남음
select edit_build(pg_temp.id('b1'), 2, t.build(array['6631','3047','3053'], '99.9.9') || pg_temp.doc()
  || '{"summary":"옛 앱이 고침","skill_sequence":"QWEQQRQEQER"}');
reset role;
select t.ok('순서만 수정: 저장 + 패치 그대로 (글만 고친 것과 같음)',
  (select skill_sequence = 'QWEQQRQEQER' and patch = :'p1' and version = 3 from builds where id = pg_temp.id('b1')));
select t.ok('순서만 수정: 수정 기록 전후', (select before ->> 'skill_sequence' = 'QWEQQR' and after ->> 'skill_sequence' = 'QWEQQRQEQER'
  from build_revisions where build_id = pg_temp.id('b1') and kind = 'edit' and version = 3));
select t.ok('기여자: 브이 2번 (순서 수정도 한 번의 수정)', (select edits from build_editors where build_id = pg_temp.id('b1') and user_id = :'V') = 2);
insert into ids select 'rv3', id from build_revisions where build_id = pg_temp.id('b1') and version = 3;
-- 게임 규칙이 바뀌어 지금 규칙에 안 맞는 옛 순서여도, 순서를 안 바꾸면 다른 칸 수정은 됨
update builds set skill_sequence = 'RRR' where id = pg_temp.id('b2');
set role authenticated;
set request.jwt.claim.sub = :'U';
select edit_build(pg_temp.id('b2'), 1, t.build(array['6631','3047','3071']) || pg_temp.doc() || '{"summary":"다른 칸만","skill_sequence":"RRR"}');
select edit_build(pg_temp.id('b2'), 2, t.build(array['6631','3047','3071']) || pg_temp.doc() || '{"summary":"다른 칸만 2"}');
select t.fails('옛 순서를 바꾸면 지금 규칙으로 검사',
  format($$select edit_build(%s, 3, t.build(array['6631','3047','3071']) || pg_temp.doc() || '{"summary":"다른 칸만 2","skill_sequence":"RR"}')$$, pg_temp.id('b2')),
  'R은 6렙부터');
-- null로 지우기
select edit_build(pg_temp.id('b2'), 3, t.build(array['6631','3047','3071']) || pg_temp.doc() || '{"summary":"다른 칸만 2","skill_sequence":null}');
reset role;
select t.ok('null을 보내면 지움 + 기록', (select skill_sequence is null and version = 4 from builds where id = pg_temp.id('b2'))
  and (select before ->> 'skill_sequence' = 'RRR' and after -> 'skill_sequence' = 'null'::jsonb from build_revisions
         where build_id = pg_temp.id('b2') and version = 4));
set role authenticated;
set request.jwt.claim.sub = :'U';
select t.fails('수정으로 다른 빌드와 같아지면 막음 (순서가 달라도)',
  format($$select edit_build(%s, 4, t.build() || pg_temp.doc() || '{"skill_sequence":"EWQEER"}')$$, pg_temp.id('b2')), '똑같은 빌드가 이미 공개돼');
select t.fails('아펠리오스 빌드에 순서 넣기 불가',
  format($$select edit_build(%s, 1, t.build() || pg_temp.doc() || '{"skill_sequence":"QWE"}')$$, pg_temp.id('ba')), '직접 찍지 않아');

-- ===== 5. 되돌리기 (운영자) =====
set request.jwt.claim.sub = :'U';
select edit_build(pg_temp.id('b1'), 3, t.build() || pg_temp.doc() || '{"summary":"옛 앱이 고침","skill_sequence":"EWQEER"}');
set request.jwt.claim.sub = :'OP';
select revert_build(pg_temp.id('b1'), pg_temp.id('rv3'), 4, '순서 되돌림');
reset role;
select t.ok('되돌리기: 그 기록의 순서로', (select skill_sequence = 'QWEQQRQEQER' and version = 5 from builds where id = pg_temp.id('b1')));
select t.ok('되돌리기 기록 (전후 순서)', (select before ->> 'skill_sequence' = 'EWQEER' and after ->> 'skill_sequence' = 'QWEQQRQEQER'
  from build_revisions where build_id = pg_temp.id('b1') and kind = 'revert'));
-- 065 전 기록(키 없음)으로 되돌리면 순서 없음
update build_revisions set after = after - 'skill_sequence'
 where build_id = pg_temp.id('b1') and kind = 'create';
insert into ids select 'rv1', id from build_revisions where build_id = pg_temp.id('b1') and kind = 'create';
set role authenticated;
set request.jwt.claim.sub = :'OP';
select revert_build(pg_temp.id('b1'), pg_temp.id('rv1'), 5, '처음으로');
reset role;
select t.ok('065 전 기록으로 되돌리면 순서 없음(null)', (select skill_sequence is null and summary = '요약' and version = 6 from builds where id = pg_temp.id('b1')));
-- 지금 규칙에 안 맞는 순서로는 되돌릴 수 없음
update build_revisions set after = jsonb_set(after, '{skill_sequence}', '"RQ"') where id = pg_temp.id('rv3');
set role authenticated;
set request.jwt.claim.sub = :'OP';
select t.fails('되돌리기도 바뀌는 순서는 지금 규칙으로 검사',
  format($$select revert_build(%s, %s, 6, '다시')$$, pg_temp.id('b1'), pg_temp.id('rv3')), 'R은 6렙부터');
reset role;
select t.ok('admin_build_revisions의 지금 내용에도 순서 칸', (select public.wiki_snapshot(b) ? 'skill_sequence' from builds b where id = pg_temp.id('b1')));
