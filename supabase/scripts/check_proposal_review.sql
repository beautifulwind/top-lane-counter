-- =====================================================================
-- 031(이미 처리됨 안내 + 제안 "검토 중" 표시) 확인 조회 (읽기만 — 아무것도 바꾸지 않는다).
-- 031 실행 "전"과 "후"에 한 번씩 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다.
-- [지금 값]이 [실행 전 정상]·[실행 후 정상]과 맞는지 본다.
-- =====================================================================
with c as (
  select
    to_regclass('public.proposal_reviewing') is not null as has_table,
    exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'start_proposal_review') as has_fn
)
select ord as "순서", what as "항목", now_value as "지금 값", before_ok as "실행 전 정상", after_ok as "실행 후 정상"
from (
  select 1 as ord, '030 실행됨 (031의 전제: moderation_log 표)' as what, (to_regclass('public.moderation_log') is not null)::text as now_value, 'true' as before_ok, 'true' as after_ok
  union all select 2, 'proposal_reviewing 표', c.has_table::text, 'false', 'true' from c
  union all select 3, '표의 행 보안(RLS) 켜짐',
    case when c.has_table then (select relrowsecurity::text from pg_class k join pg_namespace n on n.oid = k.relnamespace where n.nspname = 'public' and k.relname = 'proposal_reviewing') else '표 없음' end, '표 없음', 'true' from c
  union all select 4, '표에 일반 사용자·비로그인 직접 권한이 있나 (모두 false여야 함)',
    case when c.has_table then (
      has_table_privilege('authenticated', 'public.proposal_reviewing', 'select,insert,update,delete')
      or has_table_privilege('anon', 'public.proposal_reviewing', 'select,insert,update,delete'))::text else '표 없음' end, '표 없음', 'false' from c
  union all select 5, '표에 붙은 정책 수 (0이어야 함 — 함수로만 접근)',
    case when c.has_table then (select count(*)::text from pg_policies where schemaname = 'public' and tablename = 'proposal_reviewing') else '표 없음' end, '표 없음', '0' from c
  union all select 6, '새 함수 3개 (start·end·reviewers)',
    (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('start_proposal_review', 'end_proposal_review', 'proposal_reviewers')), '0', '3'
  union all select 7, '비로그인이 세 함수를 부를 수 있나 (false여야 함)',
    case when c.has_fn then (select bool_or(has_function_privilege('anon', p.oid, 'execute'))::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('start_proposal_review', 'end_proposal_review', 'proposal_reviewers')) else '함수 없음' end, '함수 없음', 'false' from c
  union all select 8, '로그인한 사람이 세 함수를 부를 수 있나 (true — 운영진인지는 함수 안에서 DB가 검사)',
    case when c.has_fn then (select bool_and(has_function_privilege('authenticated', p.oid, 'execute'))::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('start_proposal_review', 'end_proposal_review', 'proposal_reviewers')) else '함수 없음' end, '함수 없음', 'true' from c
  union all select 9, '세 함수가 운영진 검사(require_staff)를 하나',
    case when c.has_fn then (select bool_and(p.prosrc like '%require_staff%')::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('start_proposal_review', 'end_proposal_review', 'proposal_reviewers')) else '함수 없음' end, '함수 없음', 'true' from c
  union all select 10, '처리하면 표시를 지우는 트리거',
    (select count(*)::text from pg_trigger where tgname = 'edit_proposals_clear_reviewing' and not tgisinternal), '0', '1'
  union all select 11, '내부 트리거 함수를 일반 사용자가 부를 수 있나 (false여야 함)',
    coalesce((select (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'clear_proposal_reviewing'), '함수 없음'), '함수 없음', 'false'
  union all select 12, '"이미 다른 분이 처리했습니다"(TL409)로 바뀐 함수 수 (승인·거절·재검토 요청·요청 취소 4개 + 권한 검사 1개)',
    (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'
      and p.proname in ('approve_proposal_unchecked', 'reject_proposal_unchecked', 'request_proposal_revision_unchecked', 'cancel_proposal_revision', 'require_review_allowed')
      and p.prosrc like '%TL409%'), '0', '5'
  union all select 13, '지금 남아 있는 "검토 중" 표시 수 (만료된 것 포함, 화면은 10분 안의 것만 보여 줌)',
    case when c.has_table then (xpath('/row/c/text()', query_to_xml('select count(*) as c from public.proposal_reviewing', false, true, '')))[1]::text else '표 없음' end, '표 없음', '0 이상 (처리된 제안의 것은 없어야 함)' from c
  union all select 14, '처리된 제안에 남은 표시 수 (0이어야 함)',
    case when c.has_table then (xpath('/row/c/text()', query_to_xml('select count(*) as c from public.proposal_reviewing r join public.edit_proposals e on e.id = r.proposal_id where e.status <> ''pending''', false, true, '')))[1]::text else '표 없음' end, '표 없음', '0' from c
  union all select 15, '승인 대기 제안 수 (실행 전후 같아야 함)',
    (select count(*)::text from public.edit_proposals where status = 'pending'), '-', '실행 전과 같음'
) x
order by ord;
