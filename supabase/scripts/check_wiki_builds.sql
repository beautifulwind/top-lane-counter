-- =====================================================================
-- 038(상대법 = 빌드 묶음, 위키 방식 준비) 확인 조회 (읽기만 — 아무것도 바꾸지 않는다).
-- 038 실행 "전", 실행 "후", pg_cron 일정 등록 "뒤"에 한 번씩 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다.
-- [지금 값]이 [실행 전 정상]·[실행 후 정상]과 맞는지 본다.
--   - 19번(경험치 합계)은 실행 전 값을 적어 두었다가 실행 후 값과 같은지 본다 (이전으로 경험치가 바뀌지 않아야 함).
--   - 20·21번(승인 대기)은 039 실행 전에 0이어야 한다 (운영자가 승인 화면에서 직접 처리).
--   - 22번은 038 파일 맨 아래의 pg_cron 일정을 등록하면 true가 된다.
-- =====================================================================
with fn as (
  select p.proname, p.oid from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('push_group', 'create_matchup', 'create_build', 'edit_build', 'build_contributors', 'wiki_backfill_matchups',
                      'purge_old_build_revisions', 'approval_on')
),
bcols as (
  select column_name from information_schema.columns
  where table_schema = 'public' and table_name = 'builds'
    and column_name in ('name', 'seq', 'summary', 'level_notes', 'lane_cautions', 'updated_at', 'updated_by', 'wiki')
),
ccols as (
  select column_name from information_schema.columns
  where table_schema = 'public' and table_name = 'counters' and column_name in ('first_build_id', 'wiki')
),
done as (select (select count(*) from bcols) = 8 and (select count(*) from ccols) = 2 as ok),
malph as (
  select c.id, c.proposed_by, public.origin_proposal_id(c.id) as pid
  from public.counters c where c.target_champion = 'Tryndamere' and c.counter_champion = 'Malphite'
),
-- 038 뒤에만 있는 칸을 읽는 조회는 글자로 된 조회(query_to_xml)로 부른다 (실행 전에는 칸이 없어 이름을 직접 쓰면 오류)
q (k, v) as (
  select 'malph', case when (select ok from done) then (xpath('/row/v/text()', query_to_xml($x$
    select count(*) filter (where b.status in ('approved', 'hidden'))::text || ' / '
        || count(*) filter (where b.status in ('approved', 'hidden') and b.summary is not null and b.level_notes ?& array['1','2','3','6'])::text as v
      from public.builds b join public.counters c on c.id = b.counter_id
     where c.target_champion = 'Tryndamere' and c.counter_champion = 'Malphite'
  $x$, false, true, '')))[1]::text else '칸 없음' end
  union all
  select 'same', case when (select ok from done) then (xpath('/row/v/text()', query_to_xml($x$
    select (count(*) filter (where b.summary is distinct from d.summary or b.level_notes is distinct from d.level_notes
                                or b.lane_cautions is distinct from coalesce(d.lane_cautions, ''))
            = 0)::text as v
      from public.builds b join public.counters c on c.id = b.counter_id join public.matchup_docs d on d.counter_id = c.id
     where c.target_champion = 'Tryndamere' and c.counter_champion = 'Malphite' and b.status in ('approved', 'hidden')
  $x$, false, true, '')))[1]::text else '칸 없음' end
  union all
  select 'origin', case when (select ok from done) then (xpath('/row/v/text()', query_to_xml($x$
    select coalesce((
      select (b.proposal_id = public.origin_proposal_id(c.id))::text || ' · '
          || (b.author_id is not distinct from (select p.proposer_id from public.edit_proposals p where p.id = public.origin_proposal_id(c.id)))::text
          || ' · 번호 ' || coalesce(b.seq::text, '없음')
        from public.counters c join public.builds b on b.id = c.first_build_id
       where c.target_champion = 'Tryndamere' and c.counter_champion = 'Malphite'), '첫 빌드 없음') as v
  $x$, false, true, '')))[1]::text else '칸 없음' end
  union all
  select 'revs', case when to_regclass('public.build_revisions') is not null then (xpath('/row/v/text()', query_to_xml($x$
    select (select count(*) from public.build_revisions r where r.kind = 'migrate')::text || ' / '
        || (select count(*) from public.builds where status in ('approved', 'hidden'))::text as v
  $x$, false, true, '')))[1]::text else '표 없음' end
  union all
  select 'editors', case when to_regclass('public.build_editors') is not null then (xpath('/row/v/text()', query_to_xml($x$
    select count(*)::text as v from public.build_editors
  $x$, false, true, '')))[1]::text else '표 없음' end
  union all
  select 'seq', case when (select ok from done) then (xpath('/row/v/text()', query_to_xml($x$
    select ((select count(*) from public.builds where status in ('approved', 'hidden') and seq is null) = 0
        and (select count(*) from public.counters c where c.status in ('approved', 'hidden') and c.first_build_id is null
               and exists (select 1 from public.builds b where b.counter_id = c.id and b.status in ('approved', 'hidden'))) = 0)::text as v
  $x$, false, true, '')))[1]::text else '칸 없음' end
  union all
  select 'push', case when exists (select 1 from fn where proname = 'push_group') then (xpath('/row/v/text()', query_to_xml($x$
    select coalesce(public.push_group('matchup_created'), '안 보냄') || ' / ' || coalesce(public.push_group('build_created'), '안 보냄') as v
  $x$, false, true, '')))[1]::text else '함수 없음' end
  union all
  select 'approval', coalesce((select value::text from public.xp_rules where key = 'approval_on'), '없음')
)
select ord as "순서", what as "항목", now_value as "지금 값", before_ok as "실행 전 정상", after_ok as "실행 후 정상"
from (
  select 1 as ord, '037 실행됨 (038의 전제)' as what,
    (exists (select 1 from fn where proname = 'push_group'))::text as now_value, 'true' as before_ok, 'true' as after_ok
  union all select 2, 'builds 새 칸 (이름·번호·요약·딜교법·특이사항·수정 시각·수정자·wiki)', (select count(*)::text from bcols), '0', '8'
  union all select 3, 'counters 새 칸 (first_build_id·wiki)', (select count(*)::text from ccols), '0', '2'
  union all select 4, '수정 기록 표 build_revisions · RLS 켜짐',
    coalesce((select 'true · ' || relrowsecurity::text from pg_class where oid = to_regclass('public.build_revisions')), '표 없음'), '표 없음', 'true · true'
  union all select 5, '기여자 표 build_editors · RLS 켜짐',
    coalesce((select 'true · ' || relrowsecurity::text from pg_class where oid = to_regclass('public.build_editors')), '표 없음'), '표 없음', 'true · true'
  union all select 6, '간격 표 wiki_last_write · RLS 켜짐',
    coalesce((select 'true · ' || relrowsecurity::text from pg_class where oid = to_regclass('public.wiki_last_write')), '표 없음'), '표 없음', 'true · true'
  union all select 7, '세 표를 로그인 사용자가 직접 읽을 수 있나 (수정 기록은 운영자 함수로만)',
    case when to_regclass('public.build_revisions') is null then '표 없음' else
      (has_table_privilege('authenticated', 'public.build_revisions', 'select')
       or has_table_privilege('authenticated', 'public.build_editors', 'select')
       or has_table_privilege('authenticated', 'public.wiki_last_write', 'select')
       or has_table_privilege('anon', 'public.build_revisions', 'select'))::text end, '표 없음', 'false'
  union all select 8, '등록·수정 함수 create_matchup · create_build · edit_build (로그인 사용자만)',
    case when (select count(*) from fn where proname in ('create_matchup', 'create_build', 'edit_build')) < 3 then '함수 없음' else
      (select bool_and(has_function_privilege('authenticated', oid, 'execute') and not has_function_privilege('anon', oid, 'execute'))::text
         from fn where proname in ('create_matchup', 'create_build', 'edit_build')) end, '함수 없음', 'true'
  union all select 9, '기여자 목록 build_contributors (누구나)',
    coalesce((select has_function_privilege('anon', oid, 'execute')::text from fn where proname = 'build_contributors'), '함수 없음'), '함수 없음', 'true'
  union all select 10, '사람이 못 부르는 함수 (이전·1년 정리)',
    case when (select count(*) from fn where proname in ('wiki_backfill_matchups', 'purge_old_build_revisions')) < 2 then '함수 없음' else
      (select (not bool_or(has_function_privilege('authenticated', oid, 'execute')))::text
         from fn where proname in ('wiki_backfill_matchups', 'purge_old_build_revisions')) end, '함수 없음', 'true'
  union all select 11, '승인 제도 스위치 approval_on (038은 켜짐 그대로 — 039가 0으로)', (select v from q where k = 'approval'), '없음', '1'
  union all select 12, '새 설정값 (하루 상한·등록 간격·수정 간격·신중 안내 추천 수·수정 기록 보관일)',
    coalesce((select string_agg(key || '=' || value, ' · ' order by key) from public.xp_rules
               where key in ('create_daily_cap', 'wiki_create_interval', 'build_edit_interval', 'build_caution_ups', 'build_revision_keep_days')), '없음'),
    '없음', 'build_caution_ups=3 · build_edit_interval=10 · build_revision_keep_days=365 · create_daily_cap=200 · wiki_create_interval=60'
  union all select 13, '알림 종류에 새 상대법·새 빌드',
    (exists (select 1 from pg_constraint where conname = 'notifications_kind_check' and pg_get_constraintdef(oid) like '%matchup_created%build_created%'))::text,
    'false', 'true'
  union all select 14, '푸시 묶음: 새 상대법 / 새 빌드', (select v from q where k = 'push'), '안 보냄 / 안 보냄', 'staff_new / staff_new'
  union all select 15, '말파이트 상대법: 공개(숨김 포함) 빌드 / 내용이 채워진 빌드',
    (select v from q where k = 'malph'), '칸 없음', '두 숫자가 같음 (예: 1 / 1)'
  union all select 16, '말파이트 빌드 내용 = 예전 문서 내용 (요약·딜교법·특이사항)', (select v from q where k = 'same'), '칸 없음', 'true'
  union all select 17, '말파이트 첫 빌드: 처음 제안의 빌드 · 시초(작성자) = 처음 제안자 · 번호',
    (select v from q where k = 'origin'), '칸 없음', 'true · true · 번호 1'
  union all select 18, '이전 기록(migrate) / 공개(숨김 포함) 빌드 · 기여자(승인된 문서 수정 제안자) 수 · 번호·첫 빌드 빠짐 없음',
    (select v from q where k = 'revs') || ' · 기여자 ' || (select v from q where k = 'editors') || ' · ' || (select v from q where k = 'seq'),
    '표 없음 · 기여자 표 없음 · 칸 없음', '두 숫자가 같음 · 기여자 N · true'
  union all select 19, '경험치 합계 (모든 사람) — 실행 전 값과 같아야 함', (select coalesce(sum(xp), 0)::text from public.profiles), '(적어 두기)', '실행 전과 같음'
  union all select 20, '승인 대기·재검토 중 제안 (039 전에 0으로)',
    (select count(*)::text from public.edit_proposals where status in ('pending', 'revision_requested')), '-', '039 전 0'
  union all select 21, '승인 대기·재검토 중 빌드 (039 전에 0으로)',
    (select count(*)::text from public.builds where status in ('pending', 'revision_requested')), '-', '039 전 0'
  union all select 22, 'pg_cron 일정: 수정 기록 1년 정리 (매일 4:55)',
    case when to_regclass('cron.job') is null then 'pg_cron 없음' else
      (xpath('/row/v/text()', query_to_xml($x$select (count(*) > 0)::text as v from cron.job where jobname = 'purge-old-build-revisions'$x$, false, true, '')))[1]::text end,
    'false', 'true (일정 등록 뒤)'
) rows
order by ord;
