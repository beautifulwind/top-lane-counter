-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 013: 제안자가 승인 대기 중인 제안·빌드를 직접 고친다 + 운영자 처리 함수의 버전 확인
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
grant all on ids to authenticated;
insert into ids select 'quinn', id from counters where counter_champion = 'Quinn';

\set doc '{"summary":"가렌 요약","level_notes":{"1":"a","2":"b","3":"c","6":"d"},"lane_cautions":""}'
\set doc2 '{"summary":"가렌 요약 (제안자가 고침)","level_notes":{"1":"a","2":"b","3":"c","6":"d"},"lane_cautions":"새 팁"}'

create function pg_temp.add_build(core text[]) returns void language sql as $$
  insert into public.builds (counter_id, author_id, runes, summoner_spells, starting_items, core_items, max_skill, patch)
  select (select v from ids where k = 'quinn'), auth.uid(), b -> 'runes',
         array(select jsonb_array_elements_text(b -> 'summoner_spells')), array(select jsonb_array_elements_text(b -> 'starting_items')),
         array(select jsonb_array_elements_text(b -> 'core_items')), b ->> 'max_skill', b ->> 'patch'
  from (select t.build(core) as b) x;
$$;
grant execute on function pg_temp.add_build(text[]) to authenticated;

-- ===================================================================
-- 1. 승인 대기 중인 새 카운터 제안 고치기
-- ===================================================================
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Garen', auth.uid(), :'doc', t.build());
insert into ids select 'p', id from edit_proposals where counter_champion = 'Garen';
create temp table before_edit as select created_at from edit_proposals where id = (select v from ids where k = 'p');
grant all on before_edit to authenticated;

select t.ok('처음 버전 1, 고친 때 없음',
  (select version = 1 and edited_at is null from edit_proposals where id = (select v from ids where k = 'p')));
select t.fails('그대로는 고칠 수 없음',
  format($$select edit_my_proposal(%s, %L, %L)$$, (select v from ids where k = 'p'), :'doc', t.build(array['6631','3047','3053'], '99.1.1')), '고친 내용이 없습니다');
select t.fails('고친 글도 같은 규칙으로 검사',
  format($$select edit_my_proposal(%s, '{"summary":"x","level_notes":{"1":"a","2":"b","3":"c"}}', %L)$$, (select v from ids where k = 'p'), t.build()), '6레벨 딜교법은 꼭');
select t.fails('새 카운터 제안은 빌드 필수',
  format($$select edit_my_proposal(%s, %L, null)$$, (select v from ids where k = 'p'), :'doc2'), '빌드도 함께');
select t.fails('고친 빌드도 같은 규칙으로 검사',
  format($$select edit_my_proposal(%s, %L, %L)$$, (select v from ids where k = 'p'), :'doc2', t.build(array['6631','3047'])), '3~6개');

set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000d';
select t.fails('남의 제안은 고칠 수 없음',
  format($$select edit_my_proposal(%s, %L, %L)$$, (select v from ids where k = 'p'), :'doc2', t.build()), '제안을 찾지 못했습니다');
select v as pid from ids where k = 'p' \gset
reset role;
set role anon;
select t.fails('로그인 안 하면 못 부름', format($$select edit_my_proposal(%s, '{}', null)$$, :pid), 'permission denied');
reset role;
set role authenticated;

-- 운영자가 화면을 열어 둔 상태 (버전 1을 봄)
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select edit_my_proposal((select v from ids where k = 'p'), :'doc2', t.build(array['6631','3047','3053','3065'], '99.1.1'));
select t.ok('고친 내용 저장 + 버전 2 + 고친 때 기록, 제출 때(순서)는 그대로, 빌드는 지금 패치',
  (select content ->> 'summary' = '가렌 요약 (제안자가 고침)' and content ->> 'lane_cautions' = '새 팁'
      and build -> 'core_items' = '["6631","3047","3053","3065"]' and build ->> 'patch' = '99.1.1'
      and version = 2 and edited_at is not null and status = 'pending'
      and created_at = (select created_at from before_edit)
   from edit_proposals where id = (select v from ids where k = 'p')));

set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select t.fails('옛 버전을 보고 승인 불가',
  format($$select approve_proposal(%s, '메모', null, null, 1)$$, (select v from ids where k = 'p')), '제안자가 방금 고쳤습니다');
select t.fails('옛 버전을 보고 거절 불가',
  format($$select reject_proposal(%s, '이유', 1)$$, (select v from ids where k = 'p')), '제안자가 방금 고쳤습니다');
select t.fails('옛 버전을 보고 재검토 요청 불가',
  format($$select request_proposal_revision(%s, '고쳐', 1)$$, (select v from ids where k = 'p')), '제안자가 방금 고쳤습니다');
select t.fails('버전 없이 처리 불가',
  format($$select approve_proposal(%s, '메모', null, null, null)$$, (select v from ids where k = 'p')), '제안자가 방금 고쳤습니다');
select t.fails('옛 4인자 승인 함수는 못 부름',
  format($$select approve_proposal(%s::bigint, '메모'::text, null::jsonb, null::jsonb)$$, (select v from ids where k = 'p')), 'does not exist');
select t.fails('안쪽 함수는 직접 못 부름',
  format($$select approve_proposal_unchecked(%s, '메모', null, null)$$, (select v from ids where k = 'p')), 'permission denied');
select t.ok('막힌 뒤에도 제안은 그대로 승인 대기',
  (select status = 'pending' from edit_proposals where id = (select v from ids where k = 'p')));

-- 새 버전으로 재검토 요청 → 제안자는 [고치기] 대신 [고쳐서 다시 제출]
select request_proposal_revision((select v from ids where k = 'p'), '6레벨을 더 자세히', 2);
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select t.fails('재검토 중에는 고치기 대신 다시 제출',
  format($$select edit_my_proposal(%s, %L, %L)$$, (select v from ids where k = 'p'), :'doc', t.build()), '[고쳐서 다시 보내기]');
select resubmit_proposal((select v from ids where k = 'p'), :'doc', t.build(array['6631','3047','3053','3065'], '99.1.1'));
select t.ok('다시 제출도 버전 +1 (3)', (select version = 3 and status = 'pending' from edit_proposals where id = (select v from ids where k = 'p')));

set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select t.fails('다시 제출 전 버전을 보고 승인 불가',
  format($$select approve_proposal(%s, '메모', null, null, 2)$$, (select v from ids where k = 'p')), '제안자가 방금 고쳤습니다');
select approve_proposal((select v from ids where k = 'p'), '좋습니다', null, null, 3) as garen \gset
insert into ids values ('garen', :garen);
select t.ok('최신 버전으로 승인 → 고친 내용이 공개',
  (select summary = '가렌 요약' from matchup_docs where counter_id = :garen));

set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select t.fails('승인된 제안은 고칠 수 없음',
  format($$select edit_my_proposal(%s, %L, %L)$$, (select v from ids where k = 'p'), :'doc2', t.build()), '승인 대기 중인 제안만');

-- ===================================================================
-- 2. 문서 수정 제안 고치기 (글만)
-- ===================================================================
insert into edit_proposals (type, counter_id, proposer_id, content)
values ('doc_edit', :garen, auth.uid(), :'doc2');
insert into ids select 'e', max(id) from edit_proposals where type = 'doc_edit';
select t.fails('문서 수정 제안에 빌드 못 넣음',
  format($$select edit_my_proposal(%s, %L, %L)$$, (select v from ids where k = 'e'), :'doc', t.build()), '빌드를 넣지 않습니다');
select t.fails('지금 문서와 같게 고칠 수 없음',
  format($$select edit_my_proposal(%s, %L, null)$$, (select v from ids where k = 'e'), :'doc'), '지금 문서와 달라진 내용이 없습니다');
select edit_my_proposal((select v from ids where k = 'e'),
  '{"summary":"가렌 요약 v3","level_notes":{"1":"a","2":"b","3":"c","6":"d"},"lane_cautions":""}', null);
select t.ok('문서 수정 제안도 고쳐짐 (버전 2)',
  (select version = 2 and content ->> 'summary' = '가렌 요약 v3' and build is null from edit_proposals where id = (select v from ids where k = 'e')));
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select reject_proposal((select v from ids where k = 'e'), '이미 있는 내용입니다', 2);
select t.ok('최신 버전으로 거절', (select status = 'rejected' from edit_proposals where id = (select v from ids where k = 'e')));
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select t.fails('거절된 제안은 고칠 수 없음',
  format($$select edit_my_proposal(%s, %L, null)$$, (select v from ids where k = 'e'), :'doc2'), '승인 대기 중인 제안만');

-- ===================================================================
-- 3. 승인 대기 중인 빌드 고치기
-- ===================================================================
select pg_temp.add_build(array['3071','3047','3053']);
insert into ids select 'b', max(id) from builds where author_id = auth.uid() and status = 'pending';
select t.ok('빌드도 처음 버전 1', (select version = 1 and edited_at is null from builds where id = (select v from ids where k = 'b')));
select t.fails('그대로는 고칠 수 없음',
  format($$select edit_my_build(%s, %L)$$, (select v from ids where k = 'b'), t.build(array['3071','3047','3053'], '99.1.1')), '고친 내용이 없습니다');
select t.fails('같은 규칙으로 검사',
  format($$select edit_my_build(%s, %L)$$, (select v from ids where k = 'b'), t.build(array['3071'])), '3~6개');
-- 유저2의 빌드가 먼저 공개됨
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000d';
select pg_temp.add_build(array['6632','3047','3053']);
insert into ids select 'b2', max(id) from builds where author_id = auth.uid();
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select approve_build((select v from ids where k = 'b2'), '좋습니다', null, 1);
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select t.fails('공개된 빌드와 똑같이 고칠 수 없음',
  format($$select edit_my_build(%s, %L)$$, (select v from ids where k = 'b'), t.build(array['6632','3047','3053'])), '똑같은 빌드가 이미 공개');
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000d';
select t.fails('남의 빌드는 고칠 수 없음',
  format($$select edit_my_build(%s, %L)$$, (select v from ids where k = 'b'), t.build(array['3071','3111','3053'])), '빌드를 찾지 못했습니다');

set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select edit_my_build((select v from ids where k = 'b'), t.build(array['3071','3111','3053'], '99.1.1'));
select t.ok('빌드 고침: 내용 + 지금 패치 + 버전 2 + 고친 때',
  (select core_items = array['3071','3111','3053'] and patch = '99.1.1' and version = 2 and edited_at is not null and status = 'pending'
   from builds where id = (select v from ids where k = 'b')));

set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select t.fails('옛 버전을 보고 빌드 승인 불가',
  format($$select approve_build(%s, '메모', null, 1)$$, (select v from ids where k = 'b')), '작성자가 방금 고쳤습니다');
select t.fails('옛 버전을 보고 빌드 거절 불가',
  format($$select reject_build(%s, '이유', 1)$$, (select v from ids where k = 'b')), '작성자가 방금 고쳤습니다');
select t.fails('옛 버전을 보고 빌드 재검토 요청 불가',
  format($$select request_build_revision(%s, '고쳐', 1)$$, (select v from ids where k = 'b')), '작성자가 방금 고쳤습니다');
select t.fails('안쪽 빌드 함수는 직접 못 부름',
  format($$select approve_build_unchecked(%s, '메모', null)$$, (select v from ids where k = 'b')), 'permission denied');

select request_build_revision((select v from ids where k = 'b'), '신발을 다시', 2);
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select t.fails('재검토 중인 빌드는 고치기 대신 다시 제출',
  format($$select edit_my_build(%s, %L)$$, (select v from ids where k = 'b'), t.build(array['3071','3047','3053'])), '[고쳐서 다시 보내기]');
select resubmit_build((select v from ids where k = 'b'), t.build(array['3071','3020','3053'], '99.1.1'));
select t.ok('빌드 다시 제출도 버전 +1 (3)', (select version = 3 and status = 'pending' from builds where id = (select v from ids where k = 'b')));

set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select approve_build((select v from ids where k = 'b'), '좋습니다', null, 3);
select t.ok('최신 버전으로 빌드 승인', (select status = 'approved' from builds where id = (select v from ids where k = 'b')));
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select t.fails('공개된 빌드는 고칠 수 없음',
  format($$select edit_my_build(%s, %L)$$, (select v from ids where k = 'b'), t.build(array['3071','3047','3053'])), '승인 대기 중인 빌드만');

-- 운영자가 직접 바꾼 빌드(승인 때 고침)는 버전을 올리지 않는다 (제안자가 고친 것만)
select t.ok('운영자 처리로는 버전이 안 오름', (select version = 3 from builds where id = (select v from ids where k = 'b')));
