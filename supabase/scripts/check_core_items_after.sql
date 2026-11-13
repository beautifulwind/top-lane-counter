-- =====================================================================
-- 056(핵심 템트리 규칙 완화) 실행 "뒤" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 056을 실행한 직후 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~3번: [지금 값]이 [정상 값]과 모두 맞아야 한다.
--   - 4~7번: check_core_items_before.sql의 같은 번호 줄에 적어 둔 값과 같아야 한다 (056은 데이터를 바꾸지 않는다).
--   하나라도 다르면 알려 주세요.
-- =====================================================================
with fn as (
  select
    (select prosrc from pg_proc where oid = to_regprocedure('public.clean_build(jsonb)')) as clean_src,
    (select prosrc from pg_proc where oid = to_regprocedure('public.check_core_items(text[])')) as core_src
)
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '056 실행됨: 빌드 검사의 핵심 템트리 1~10개, 중복 허용 / 시작 아이템 1~4개 그대로' as what,
    (select (clean_src like '%''핵심 템트리'', 1, 10, false)%')::text from fn) || ' / '
      || (select (clean_src like '%''시작 아이템'', 1, 4, false)%')::text from fn) as now_value,
    'true / true' as ok_value, '' as memo
  union all select 2, '056 실행됨: 종류 검사에 전설/서사/신발 규칙 없음 / 가격표에 없는 아이템 검사는 남음',
    (select (core_src not like '%legendary%')::text from fn) || ' / '
      || (select (core_src like '%item_prices%')::text from fn),
    'true / true', ''
  union all select 3, '검사를 부르는 트리거가 그대로 있음 (빌드 등록 / 빌드 핵심 템트리 / 제안 핵심 템트리)',
    exists (select 1 from pg_trigger where tgname = 'builds_check_new' and tgrelid = 'public.builds'::regclass)::text || ' / '
      || exists (select 1 from pg_trigger where tgname = 'builds_core_items' and tgrelid = 'public.builds'::regclass)::text || ' / '
      || exists (select 1 from pg_trigger where tgname = 'edit_proposals_core_items' and tgrelid = 'public.edit_proposals'::regclass)::text,
    'true / true / true', ''
  union all select 4, '비교: 빌드 줄 수 (전체 / 공개 / 승인 대기 / 재검토 요청)',
    (select count(*)::text from public.builds) || ' / '
      || (select count(*)::text from public.builds where status = 'approved') || ' / '
      || (select count(*)::text from public.builds where status = 'pending') || ' / '
      || (select count(*)::text from public.builds where status = 'revision_requested'),
    '(실행 전 4번과 같음)', ''
  union all select 5, '비교: 빌드 핵심 템트리 지문 (md5 앞 12자리)',
    (select left(md5(coalesce(string_agg(id::text || ':' || array_to_string(core_items, ','), ';' order by id), '')), 12) from public.builds),
    '(실행 전 5번과 같음)', '모든 빌드의 핵심 템트리가 그대로'
  union all select 6, '비교: 제안의 빌드 핵심 템트리 지문 (제안 빌드 / 고쳐서 승인한 빌드)',
    (select left(md5(coalesce(string_agg(id::text || ':' || coalesce(build -> 'core_items', 'null'::jsonb)::text, ';' order by id), '')), 12) from public.edit_proposals) || ' / '
      || (select left(md5(coalesce(string_agg(id::text || ':' || coalesce(approved_build -> 'core_items', 'null'::jsonb)::text, ';' order by id), '')), 12) from public.edit_proposals),
    '(실행 전 6번과 같음)', ''
  union all select 7, '비교: 빌드 수정 기록 줄 수 / 지문',
    (select count(*)::text from public.build_revisions) || ' / '
      || (select left(md5(coalesce(string_agg(id::text || ':' || coalesce(before, 'null'::jsonb)::text || '>' || coalesce(after, 'null'::jsonb)::text, ';' order by id), '')), 12) from public.build_revisions),
    '(실행 전 7번과 같음)', ''
) rows
order by ord;
