-- 로컬 검사 전용 (supabase/tests/run.sh). 실제 Supabase SQL Editor에서 실행하지 말 것.
-- 012: [승인] = 고쳐서 승인 가능 / 승인 대기 제안·빌드에도 [재검토 요청] / [요청 취소] / 재검토 중 [거절]
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
select id as quinn from counters where counter_champion = 'Quinn' \gset

\set doc '{"summary":"가렌 요약","level_notes":{"1":"a","2":"b","3":"c","6":"d"},"lane_cautions":"원래 특이사항"}'
\set fixed '{"summary":"가렌 요약 (운영자 다듬음)","level_notes":{"1":"a","2":"b","3":"c","6":"d 보충"},"lane_cautions":"원래 특이사항"}'

create function pg_temp.add_build(core text[]) returns void language sql as $$
  insert into public.builds (counter_id, author_id, runes, summoner_spells, starting_items, core_items, max_skill, patch)
  select (select v from ids where k = 'quinn'), auth.uid(), b -> 'runes',
         array(select jsonb_array_elements_text(b -> 'summoner_spells')), array(select jsonb_array_elements_text(b -> 'starting_items')),
         array(select jsonb_array_elements_text(b -> 'core_items')), b ->> 'max_skill', b ->> 'patch'
  from (select t.build(core) as b) x;
$$;
grant execute on function pg_temp.add_build(text[]) to authenticated;
insert into ids values ('quinn', :quinn);

-- ===================================================================
-- 1. 새 카운터 제안을 고쳐서 승인
-- ===================================================================
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Garen', auth.uid(), :'doc', t.build());
insert into ids select 'garen_p', id from edit_proposals where counter_champion = 'Garen';

set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select t.fails('메모 없이 고쳐서 승인 불가',
  format($$select approve_proposal(%s, ' ', %L, null, t.pv(%1$s))$$, (select v from ids where k = 'garen_p'), :'fixed'), '승인 메모를 적어');
select t.fails('고친 글도 같은 규칙으로 검사 (6레벨 빠짐)',
  format($$select approve_proposal(%s, '메모', '{"summary":"x","level_notes":{"1":"a","2":"b","3":"c"}}', null, t.pv(%1$s))$$, (select v from ids where k = 'garen_p')),
  '6레벨 딜교법은 꼭');
select t.fails('고친 빌드도 같은 규칙으로 검사',
  format($$select approve_proposal(%s, '메모', null, %L, t.pv(%1$s))$$, (select v from ids where k = 'garen_p'), t.build(array['6631','3047'])), '3~6개');
select approve_proposal((select v from ids where k = 'garen_p'), '오타와 6레벨을 보충했습니다', :'fixed',
                        t.build(array['6631','3047','3053','3065'], '99.1.1'), t.pv((select v from ids where k = 'garen_p'))) as garen \gset
insert into ids values ('garen', :garen);

select t.ok('문서는 고친 내용으로 공개',
  (select summary = '가렌 요약 (운영자 다듬음)' and level_notes ->> '6' = 'd 보충' from matchup_docs where counter_id = :garen));
select t.ok('제안의 원래 글은 그대로, 고친 글·빌드는 approved_*에',
  (select content ->> 'summary' = '가렌 요약' and approved_content ->> 'summary' = '가렌 요약 (운영자 다듬음)'
      and build -> 'core_items' = '["6631","3047","3053"]' and approved_build -> 'core_items' = '["6631","3047","3053","3065"]'
   from edit_proposals where id = (select v from ids where k = 'garen_p')));
select t.ok('수정 기록 두 줄: 제안 원본(제안자) → 운영자 수정(운영자, 메모), 문서는 운영자 수정 줄',
  (select array_agg(kind || ':' || coalesce(edited_by::text, '-') || ':' || coalesce(note, '-') order by id) =
          array['create:00000000-0000-0000-0000-00000000000b:-',
                'admin_edit:00000000-0000-0000-0000-00000000000a:오타와 6레벨을 보충했습니다']
      and (array_agg(content order by id))[1] ->> 'summary' = '가렌 요약'
      and max(id) = (select revision_id from matchup_docs where counter_id = :garen)
   from doc_revisions where counter_id = :garen));
select t.ok('첫 빌드: 고친 빌드 + 지금 패치, 작성자 = 제안자, 원래 빌드는 original_build',
  (select count(*) = 1 and bool_and(author_id = '00000000-0000-0000-0000-00000000000b' and core_items = array['6631','3047','3053','3065']
     and patch = '99.1.1' and original_build -> 'core_items' = '["6631","3047","3053"]' and original_build ->> 'patch' = '16.21.1')
   from builds where counter_id = :garen));
select t.ok('카운터 제안자 = 제안자 (경험치 기준)', (select proposed_by = '00000000-0000-0000-0000-00000000000b' from counters where id = :garen));

set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select t.ok('제안자: 승인 알림(메모) + 원래 제안·고친 내용을 볼 수 있음',
  (select count(*) = 1 from notifications where kind = 'proposal_approved' and message = '오타와 6레벨을 보충했습니다')
  and (select approved_content is not null from edit_proposals where id = (select v from ids where k = 'garen_p')));

-- 공백만 다르게 보내면 안 고친 것
insert into edit_proposals (type, counter_id, proposer_id, content)
values ('doc_edit', :garen, auth.uid(), '{"summary":"가렌 요약 v2","level_notes":{"1":"a","2":"b","3":"c","6":"d"},"lane_cautions":""}');
insert into ids select 'edit1', max(id) from edit_proposals where type = 'doc_edit';
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select t.fails('문서 수정 제안에는 빌드 못 넣음',
  format($$select approve_proposal(%s, '메모', null, %L, t.pv(%1$s))$$, (select v from ids where k = 'edit1'), t.build()), '문서 수정 제안에는 빌드가 없습니다');
select t.fails('고친 내용이 지금 문서와 같으면 불가',
  format($$select approve_proposal(%s, '메모', %L, null, t.pv(%1$s))$$, (select v from ids where k = 'edit1'), :'fixed'), '고친 내용이 지금 문서와 같습니다');
select approve_proposal((select v from ids where k = 'edit1'), '그대로 좋습니다',
  '{"summary":"  가렌 요약 v2 ","level_notes":{"1":"a","2":"b","3":"c","6":"d","5":"  "},"lane_cautions":" "}', null, t.pv((select v from ids where k = 'edit1')));
select t.ok('공백만 다르면 안 고친 것: 기록 한 줄, approved_content 없음',
  (select approved_content is null from edit_proposals where id = (select v from ids where k = 'edit1'))
  and (select count(*) = 1 from doc_revisions where proposal_id = (select v from ids where k = 'edit1')));

-- ===================================================================
-- 2. 빌드를 고쳐서 승인
-- ===================================================================
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select pg_temp.add_build(array['3071','3047','3053']);
insert into ids select 'b1', max(id) from builds where author_id = auth.uid() and status = 'pending';
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select t.fails('옛 2인자 빌드 승인 함수 없음', format($$select approve_build(%s::bigint, 'x'::text)$$, (select v from ids where k = 'b1')), 'does not exist');
select t.fails('고친 빌드가 공개 빌드와 똑같으면 불가',
  format($$select approve_build(%s, '메모', %L, t.bv(%1$s))$$, (select v from ids where k = 'b1'),
         (select jsonb_build_object('runes', runes, 'summoner_spells', to_jsonb(summoner_spells), 'starting_items', to_jsonb(starting_items),
                 'core_items', to_jsonb(core_items), 'max_skill', max_skill, 'patch', '99.1.1')
          from builds where counter_id = :quinn and status = 'approved' order by id limit 1)),
  '똑같은 빌드가 이미 공개');
select t.ok('실패하면 빌드는 그대로', (select status = 'pending' and original_build is null and core_items = array['3071','3047','3053'] from builds where id = (select v from ids where k = 'b1')));
select approve_build((select v from ids where k = 'b1'), '신발을 바꿨습니다', t.build(array['3071','3111','3053'], '99.1.1'), t.bv((select v from ids where k = 'b1')));
select t.ok('고친 빌드로 공개 + 지금 패치, 원래 빌드는 original_build, 작성자 그대로',
  (select status = 'approved' and core_items = array['3071','3111','3053'] and patch = '99.1.1'
      and original_build -> 'core_items' = '["3071","3047","3053"]' and original_build ->> 'patch' = '16.21.1'
      and author_id = '00000000-0000-0000-0000-00000000000b' and approve_note = '신발을 바꿨습니다'
   from builds where id = (select v from ids where k = 'b1')));

set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select pg_temp.add_build(array['3071','3047','3065']);
insert into ids select 'b2', max(id) from builds where author_id = auth.uid() and status = 'pending';
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select approve_build((select v from ids where k = 'b2'), '그대로 좋습니다', t.build(array['3071','3047','3065'], '99.1.1'), t.bv((select v from ids where k = 'b2')));
select t.ok('같은 빌드를 보내면 안 고친 것 (원래 패치 유지)',
  (select original_build is null and patch = '16.21.1' from builds where id = (select v from ids where k = 'b2')));

-- ===================================================================
-- 3. 승인 대기 제안에 재검토 요청 → 다시 제출 / 요청 취소 / 거절
-- ===================================================================
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
insert into edit_proposals (type, counter_id, proposer_id, content)
values ('doc_edit', :garen, auth.uid(), '{"summary":"가렌 요약 v3","level_notes":{"1":"a","2":"b","3":"c","6":"d"},"lane_cautions":""}');
insert into ids select 'edit2', max(id) from edit_proposals where type = 'doc_edit';
select t.fails('일반 유저는 재검토 요청 불가', format($$select request_proposal_revision(%s, '고쳐', t.pv(%1$s))$$, (select v from ids where k = 'edit2')), '운영자만');

set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select t.fails('재검토 요청: 메모 필수', format($$select request_proposal_revision(%s, ' ', t.pv(%1$s))$$, (select v from ids where k = 'edit2')), '재검토 요청 메모를 적어');
select t.fails('처리된 제안은 재검토 요청 불가', format($$select request_proposal_revision(%s, '고쳐', t.pv(%1$s))$$, (select v from ids where k = 'edit1')), '이미 다른 분이 처리했습니다');
select request_proposal_revision((select v from ids where k = 'edit2'), ' 근거를 더 적어 주세요 ', t.pv((select v from ids where k = 'edit2')));
select t.ok('재검토 요청: 상태·메모(공백 정리)·요청한 사람',
  (select status = 'revision_requested' and revision_note = '근거를 더 적어 주세요' and revision_requested_by = auth.uid()
   from edit_proposals where id = (select v from ids where k = 'edit2')));
select t.fails('두 번 요청 불가', format($$select request_proposal_revision(%s, '또', t.pv(%1$s))$$, (select v from ids where k = 'edit2')), '이미 재검토를 요청');
select t.fails('재검토 중에는 승인 불가', format($$select approve_proposal(%s, '메모', null, null, t.pv(%1$s))$$, (select v from ids where k = 'edit2')), '이미 다른 분이 처리했습니다');

set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select t.ok('제안자에게 재검토 알림 (메모)',
  (select count(*) = 1 from notifications where kind = 'revision_request' and proposal_id = (select v from ids where k = 'edit2')
     and message = '근거를 더 적어 주세요' and read_at is null));
select t.fails('재검토 중에 같은 매치업 새 제안 불가',
  format($$insert into edit_proposals (type, counter_id, proposer_id, content) values ('doc_edit', %s, auth.uid(), '{"summary":"다른","level_notes":{"1":"a","2":"b","3":"c","6":"d"}}')$$, :garen),
  '재검토 요청을 받은 내 제안');
select t.fails('그대로 다시 제출 불가',
  format($$select resubmit_proposal(%s, '{"summary":"가렌 요약 v3","level_notes":{"1":"a","2":"b","3":"c","6":"d"}}', null)$$, (select v from ids where k = 'edit2')),
  '고친 내용이 없습니다');
select t.fails('문서 수정 제안에 빌드를 넣어 다시 제출 불가',
  format($$select resubmit_proposal(%s, '{"summary":"v4","level_notes":{"1":"a","2":"b","3":"c","6":"d"}}', %L)$$, (select v from ids where k = 'edit2'), t.build()),
  '문서 수정 제안에는 빌드를 넣지 않습니다');
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000d';
select t.fails('남의 제안은 다시 제출 불가',
  format($$select resubmit_proposal(%s, '{"summary":"v4","level_notes":{"1":"a","2":"b","3":"c","6":"d"}}', null)$$, (select v from ids where k = 'edit2')),
  '제안을 찾지 못했습니다');
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select resubmit_proposal((select v from ids where k = 'edit2'), '{"summary":"가렌 요약 v4","level_notes":{"1":"a","2":"b","3":"c","6":"d 근거"}}', null);
select t.ok('다시 제출: 다시 승인 대기 + 고친 글 + 다시 낸 때, 재검토 알림은 읽음',
  (select status = 'pending' and content ->> 'summary' = '가렌 요약 v4' and resubmitted_at is not null
   from edit_proposals where id = (select v from ids where k = 'edit2'))
  and (select bool_and(read_at is not null) from notifications where proposal_id = (select v from ids where k = 'edit2') and kind = 'revision_request'));

-- 요청 취소
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select request_proposal_revision((select v from ids where k = 'edit2'), '한 번 더 봐 주세요', t.pv((select v from ids where k = 'edit2')));
select t.fails('요청 취소: 메모 필수', format($$select cancel_proposal_revision(%s, '')$$, (select v from ids where k = 'edit2')), '요청 취소 메모를 적어');
select cancel_proposal_revision((select v from ids where k = 'edit2'), '제가 잘못 봤습니다');
select t.ok('요청 취소: 원래대로 승인 대기, 재검토 칸 비움',
  (select status = 'pending' and revision_note is null and revision_requested_at is null and content ->> 'summary' = '가렌 요약 v4'
   from edit_proposals where id = (select v from ids where k = 'edit2')));
select t.fails('대기 중이면 요청 취소 불가', format($$select cancel_proposal_revision(%s, '또')$$, (select v from ids where k = 'edit2')), '이미 다른 분이 처리했습니다');
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select t.ok('요청 취소: 재검토 알림은 읽음 + 취소 알림(메모)',
  (select bool_and(read_at is not null) from notifications where proposal_id = (select v from ids where k = 'edit2') and kind = 'revision_request')
  and (select count(*) = 1 from notifications where proposal_id = (select v from ids where k = 'edit2') and kind = 'revision_cancelled' and message = '제가 잘못 봤습니다'));
select t.fails('제안자는 요청 취소 불가', format($$select cancel_proposal_revision(%s, 'x')$$, (select v from ids where k = 'edit2')), '운영자만');

-- 재검토 중 거절
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select request_proposal_revision((select v from ids where k = 'edit2'), '세 번째', t.pv((select v from ids where k = 'edit2')));
select reject_proposal((select v from ids where k = 'edit2'), '오래 기다려서 닫습니다', t.pv((select v from ids where k = 'edit2')));
select t.ok('재검토 중 거절: 거절 + 사유',
  (select status = 'rejected' and reject_reason = '오래 기다려서 닫습니다' from edit_proposals where id = (select v from ids where k = 'edit2')));
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select t.ok('재검토 중 거절: 재검토 알림은 읽음 + 거절 알림',
  (select bool_and(read_at is not null) from notifications where proposal_id = (select v from ids where k = 'edit2') and kind = 'revision_request')
  and (select count(*) = 1 from notifications where proposal_id = (select v from ids where k = 'edit2') and kind = 'proposal_rejected'));

-- 새 카운터 제안(아직 카운터 없음)의 재검토: 글·빌드를 같이 고침
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
insert into edit_proposals (type, target_champion, counter_champion, proposer_id, content, build)
values ('new_counter', 'Darius', 'Teemo', auth.uid(), '{"summary":"티모","level_notes":{"1":"a","2":"b","3":"c","6":"d"}}', t.build());
insert into ids select 'teemo_p', id from edit_proposals where counter_champion = 'Teemo';
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select request_proposal_revision((select v from ids where k = 'teemo_p'), '빌드가 이상합니다', t.pv((select v from ids where k = 'teemo_p')));
select t.ok('새 카운터 제안 재검토: 카운터 기록 없음 (카운터가 아직 없음)',
  (select counter_id is null and status = 'revision_requested' from edit_proposals where id = (select v from ids where k = 'teemo_p')));
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select t.fails('새 카운터 제안은 빌드 없이 다시 제출 불가',
  format($$select resubmit_proposal(%s, '{"summary":"티모","level_notes":{"1":"a","2":"b","3":"c","6":"d"}}', null)$$, (select v from ids where k = 'teemo_p')),
  '빌드도 함께 채워');
select resubmit_proposal((select v from ids where k = 'teemo_p'), '{"summary":"티모","level_notes":{"1":"a","2":"b","3":"c","6":"d"}}',
                         t.build(array['3071','3047','3053']));
select t.ok('빌드만 고쳐도 다시 제출됨',
  (select status = 'pending' and build -> 'core_items' = '["3071","3047","3053"]' from edit_proposals where id = (select v from ids where k = 'teemo_p')));
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select approve_proposal((select v from ids where k = 'teemo_p'), '좋습니다', null, null, t.pv((select v from ids where k = 'teemo_p'))) as teemo \gset
select t.ok('다시 낸 새 카운터 제안 승인: 고친 빌드가 첫 빌드',
  (select count(*) = 1 and bool_and(core_items = array['3071','3047','3053'] and original_build is null) from builds where counter_id = :teemo));

-- 숨긴 카운터 흐름은 [다시 공개]로 취소 (요청 취소 함수는 거부)
select hide_counter(:teemo, '잠깐 숨김');
select request_revision(:teemo, '숨긴 카운터 재검토');
select t.fails('숨긴 카운터 재검토는 요청 취소 함수로 못 취소',
  format($$select cancel_proposal_revision(%s, '취소')$$, (select v from ids where k = 'teemo_p')), '[다시 공개]로 취소');

-- ===================================================================
-- 4. 승인 대기 빌드에 재검토 요청 → 다시 제출 / 요청 취소 / 거절
-- ===================================================================
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select pg_temp.add_build(array['6333','3047','3053']);
insert into ids select 'b3', max(id) from builds where author_id = auth.uid() and status = 'pending';
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select t.fails('빌드 재검토: 메모 필수', format($$select request_build_revision(%s, '  ', t.bv(%1$s))$$, (select v from ids where k = 'b3')), '재검토 요청 메모를 적어');
select t.fails('공개된 빌드는 재검토 요청 불가', format($$select request_build_revision(%s, '고쳐', t.bv(%1$s))$$, (select v from ids where k = 'b1')), '승인 대기 중인 빌드만');
select request_build_revision((select v from ids where k = 'b3'), '핵심 템을 하나 더', t.bv((select v from ids where k = 'b3')));
select t.ok('빌드 재검토: 상태·메모·기록',
  (select status = 'revision_requested' and revision_note = '핵심 템을 하나 더' from builds where id = (select v from ids where k = 'b3'))
  and (select count(*) = 1 from build_status_log where build_id = (select v from ids where k = 'b3') and action = 'revision_request'));
select t.fails('재검토 중인 빌드는 승인 불가', format($$select approve_build(%s, '메모', null, t.bv(%1$s))$$, (select v from ids where k = 'b3')), '이미 처리된');

set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select t.ok('작성자에게 재검토 알림 (빌드 연결)',
  (select count(*) = 1 from notifications where kind = 'revision_request' and build_id = (select v from ids where k = 'b3') and message = '핵심 템을 하나 더'));
select t.ok('작성자는 재검토 중인 내 빌드를 봄', (select count(*) = 1 from builds where id = (select v from ids where k = 'b3')));
select t.fails('재검토 중에 같은 매치업 새 빌드 불가', $$select pg_temp.add_build(array['6333','3047','3065'])$$, '재검토 요청을 받은 내 빌드');
select t.fails('그대로 다시 제출 불가', format($$select resubmit_build(%s, %L)$$, (select v from ids where k = 'b3'), t.build(array['6333','3047','3053'], '99.1.1')), '고친 내용이 없습니다');
select t.fails('공개 빌드와 똑같이 다시 제출 불가', format($$select resubmit_build(%s, %L)$$, (select v from ids where k = 'b3'), t.build(array['3071','3111','3053'])), '똑같은 빌드가 이미 공개');
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000d';
select t.fails('남의 빌드는 다시 제출 불가', format($$select resubmit_build(%s, %L)$$, (select v from ids where k = 'b3'), t.build(array['6333','3047','3053','3065'])), '빌드를 찾지 못했습니다');
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select resubmit_build((select v from ids where k = 'b3'), t.build(array['6333','3047','3053','3065'], '99.1.1'));
select t.ok('빌드 다시 제출: 승인 대기 + 고친 내용 + 지금 패치, 재검토 알림 읽음',
  (select status = 'pending' and core_items = array['6333','3047','3053','3065'] and patch = '99.1.1' and resubmitted_at is not null
   from builds where id = (select v from ids where k = 'b3'))
  and (select bool_and(read_at is not null) from notifications where build_id = (select v from ids where k = 'b3') and kind = 'revision_request'));

set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select t.ok('빌드 기록: 재검토 요청 → 다시 제출',
  (select array_agg(action order by id) = array['revision_request', 'resubmit'] from build_status_log where build_id = (select v from ids where k = 'b3')));
select request_build_revision((select v from ids where k = 'b3'), '한 번 더', t.bv((select v from ids where k = 'b3')));
select cancel_build_revision((select v from ids where k = 'b3'), '아닙니다, 괜찮아요');
select t.ok('빌드 요청 취소: 승인 대기로, 기록',
  (select status = 'pending' and revision_note is null from builds where id = (select v from ids where k = 'b3'))
  and (select count(*) = 1 from build_status_log where build_id = (select v from ids where k = 'b3') and action = 'revision_cancel' and reason = '아닙니다, 괜찮아요'));
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';
select t.ok('빌드 요청 취소: 작성자에게 취소 알림',
  (select count(*) = 1 from notifications where build_id = (select v from ids where k = 'b3') and kind = 'revision_cancelled' and message = '아닙니다, 괜찮아요'));
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select request_build_revision((select v from ids where k = 'b3'), '세 번째', t.bv((select v from ids where k = 'b3')));
select reject_build((select v from ids where k = 'b3'), '닫습니다', t.bv((select v from ids where k = 'b3')));
select t.ok('재검토 중 빌드 거절',
  (select status = 'rejected' and reject_reason = '닫습니다' from builds where id = (select v from ids where k = 'b3')));

-- 탈퇴하면 재검토 중인 내 빌드도 지워진다
reset role;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
set role authenticated;
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000d';
select pg_temp.add_build(array['6333','3111','3053']);
insert into ids select 'b4', max(id) from builds where author_id = auth.uid();
set request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';
select request_build_revision((select v from ids where k = 'b4'), '고쳐 주세요', t.bv((select v from ids where k = 'b4')));
reset role;
delete from auth.users where id = '00000000-0000-0000-0000-00000000000d';
select t.ok('탈퇴: 재검토 중인 빌드도 지워짐', not exists (select 1 from builds where id = (select v from ids where k = 'b4')));
