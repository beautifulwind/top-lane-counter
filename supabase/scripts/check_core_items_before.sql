-- =====================================================================
-- 056(핵심 템트리 규칙 완화) 실행 "전" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 056을 실행하기 전에 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~3번: [지금 값]이 [정상 값]과 모두 맞으면 056을 실행해도 된다. 하나라도 다르면 실행하지 말고 알려 주세요.
--   - 4~8번: 적어 둘 값. 056은 데이터를 바꾸지 않는다 (실행 직후 check_core_items_after.sql의 같은 이름 줄과 같아야 함.
--     그 사이 사이트에서 누가 빌드를 등록하거나 고치면 달라질 수 있다 - 그때는 알려 주세요).
-- =====================================================================
with fn as (
  select
    (select prosrc from pg_proc where oid = to_regprocedure('public.clean_build(jsonb)')) as clean_src,
    (select prosrc from pg_proc where oid = to_regprocedure('public.check_core_items(text[])')) as core_src
)
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '055까지 실행됨 (표 nickname_holds)' as what,
    (to_regclass('public.nickname_holds') is not null)::text as now_value,
    'true' as ok_value, 'false면 055부터 실행' as memo
  union all select 2, '056 아직 안 함: 빌드 검사의 핵심 템트리 3~6개, 중복 불가 / 종류 검사에 전설 규칙 있음',
    (select (clean_src like '%''핵심 템트리'', 3, 6, true)%')::text from fn) || ' / '
      || (select (core_src like '%legendary%')::text from fn),
    'true / true', 'false가 있으면 이미 실행한 것 - 다시 실행하지 말 것'
  union all select 3, '가격표: 종류 빈 줄 / 기본템(basic) 줄 수가 0보다 큼',
    (select count(*)::text from public.item_prices where kind is null) || ' / '
      || (select (count(*) > 0)::text from public.item_prices where kind = 'basic'),
    '0 / true', 'true가 아니면 운영자 페이지에서 아이템 가격표를 먼저 갱신 (기본템이 없으면 핵심 템트리에 못 넣음)'
  union all select 4, '적어 둠: 빌드 줄 수 (전체 / 공개 / 승인 대기 / 재검토 요청)',
    (select count(*)::text from public.builds) || ' / '
      || (select count(*)::text from public.builds where status = 'approved') || ' / '
      || (select count(*)::text from public.builds where status = 'pending') || ' / '
      || (select count(*)::text from public.builds where status = 'revision_requested'),
    '(이 값을 적어 둠)', 'after 4번과 같아야 함'
  union all select 5, '적어 둠: 빌드 핵심 템트리 지문 (md5 앞 12자리)',
    (select left(md5(coalesce(string_agg(id::text || ':' || array_to_string(core_items, ','), ';' order by id), '')), 12) from public.builds),
    '(이 값을 적어 둠)', 'after 5번과 같아야 함 (모든 빌드의 핵심 템트리가 그대로라는 뜻)'
  union all select 6, '적어 둠: 제안의 빌드 핵심 템트리 지문 (제안 빌드 / 고쳐서 승인한 빌드)',
    (select left(md5(coalesce(string_agg(id::text || ':' || coalesce(build -> 'core_items', 'null'::jsonb)::text, ';' order by id), '')), 12) from public.edit_proposals) || ' / '
      || (select left(md5(coalesce(string_agg(id::text || ':' || coalesce(approved_build -> 'core_items', 'null'::jsonb)::text, ';' order by id), '')), 12) from public.edit_proposals),
    '(이 값을 적어 둠)', 'after 6번과 같아야 함'
  union all select 7, '적어 둠: 빌드 수정 기록 줄 수 / 지문',
    (select count(*)::text from public.build_revisions) || ' / '
      || (select left(md5(coalesce(string_agg(id::text || ':' || coalesce(before, 'null'::jsonb)::text || '>' || coalesce(after, 'null'::jsonb)::text, ';' order by id), '')), 12) from public.build_revisions),
    '(이 값을 적어 둠)', 'after 7번과 같아야 함'
  union all select 8, '참고: 핵심 템트리 가장 긴 칸 수 / 중복이 든 빌드 수',
    (select coalesce(max(cardinality(core_items)), 0)::text from public.builds) || ' / '
      || (select count(*)::text from public.builds where cardinality(core_items) <> (select count(distinct x) from unnest(core_items) x)),
    '6 이하 / 0', '056 전에는 7칸 이상, 중복이 들어갈 수 없다'
) rows
order by ord;
