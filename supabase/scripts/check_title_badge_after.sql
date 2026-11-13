-- =====================================================================
-- 054(한정판 대표 칭호 + 닉네임 옆 배지) 실행 "뒤" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 054를 실행한 뒤 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~8번: [지금 값]이 [정상 값]과 모두 맞아야 한다. 하나라도 다르면 알려 주세요.
--   - 9~13번: 실행 전 check_title_badge_before.sql의 7~11번에 적어 둔 값과 같아야 한다.
--     (054는 회원의 칭호와 대표 칭호를 바꾸지 않는다. 그 사이 사이트 사용으로 바뀌었을 수는 있다.)
-- =====================================================================
with info as (
  select public.public_title_info() as j
),
expect as (
  -- 054 함수와 따로 계산한 "들어가야 하는 칭호" (활동 + 한정판, 숨김 빼고, 비밀은 누군가 대표로 단 것만)
  select coalesce(string_agg(c.key, ',' order by case c.kind when 'activity' then 1 else 3 end, c.sort_order, c.key), '') as keys
  from public.title_catalog c
  where c.kind <> 'influencer' and not c.hidden
    and (not c.secret or c.key in (select main_title from public.profiles where main_title is not null))
)
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '함수 public_title_info / 트리거 title_catalog_unequip' as what,
    (to_regprocedure('public.public_title_info()') is not null)::text || ' / '
      || exists (select 1 from pg_trigger where tgname = 'title_catalog_unequip'
                  and tgrelid = 'public.title_catalog'::regclass)::text as now_value,
    'true / true' as ok_value, '' as memo
  union all select 2, '도감 표 제약: 053 것(활동만 장착) 있음 / 054 것(장인만 불가) 있음',
    exists (select 1 from pg_constraint where conname = 'title_catalog_equip_activity_only'
             and conrelid = 'public.title_catalog'::regclass)::text || ' / '
      || exists (select 1 from pg_constraint where conname = 'title_catalog_equip_kind'
                  and conrelid = 'public.title_catalog'::regclass)::text,
    'false / true', '이제 한정판도 칭호마다 장착 가능으로 바꿀 수 있다'
  union all select 3, '부를 수 있음: 비로그인 / 회원 (public_title_info)',
    has_function_privilege('anon', 'public.public_title_info()', 'execute')::text || ' / '
      || has_function_privilege('authenticated', 'public.public_title_info()', 'execute')::text,
    'true / true', '게시판은 비로그인에게도 배지가 보인다'
  union all select 4, '못 부름: 비로그인 / 회원 (title_catalog_unequip, check_main_title_equippable)',
    has_function_privilege('anon', 'public.title_catalog_unequip()', 'execute')::text || ' / '
      || has_function_privilege('authenticated', 'public.title_catalog_unequip()', 'execute')::text || ' / '
      || has_function_privilege('anon', 'public.check_main_title_equippable()', 'execute')::text || ' / '
      || has_function_privilege('authenticated', 'public.check_main_title_equippable()', 'execute')::text,
    'false / false / false / false', ''
  union all select 5, '도감 표는 여전히 직접 못 읽음: 비로그인 / 회원',
    has_table_privilege('anon', 'public.title_catalog', 'select')::text || ' / '
      || has_table_privilege('authenticated', 'public.title_catalog', 'select')::text,
    'false / false', '배지는 public_title_info로만'
  union all select 6, 'public_title_info 칭호 키 = 따로 계산한 값',
    (select (coalesce((select string_agg(e ->> 'key', ',' order by n) from jsonb_array_elements(j) with ordinality a(e, n)), '')
             = (select keys from expect))::text from info),
    'true', '활동 + 한정판, 숨김 제외, 비밀은 누군가 대표로 단 것만'
  union all select 7, 'public_title_info 칸: 이름/그림/색만 (소개/얻는 방법/기간 없음) / 활동 칭호 수',
    (select (not exists (select 1 from jsonb_array_elements(j) e
                         where (select array_agg(k order by k) from jsonb_object_keys(e) k) <> array['color', 'icon', 'key', 'kind', 'name']))::text
            || ' / ' || (select count(*) from jsonb_array_elements(j) e where e ->> 'kind' = 'activity')::text from info),
    'true / 6', ''
  union all select 8, '대표 칭호 트리거에 054 숨김 조건 / 장착 가능 칭호 수 (활동 / 한정판 / 장인)',
    (pg_get_functiondef('public.check_main_title_equippable'::regproc) like '%054: 숨김 칭호도 불가%')::text || ' / '
      || (select count(*)::text from public.title_catalog where equippable and kind = 'activity') || ' / '
      || (select count(*)::text from public.title_catalog where equippable and kind = 'limited') || ' / '
      || (select count(*)::text from public.title_catalog where equippable and kind = 'influencer'),
    'true / 6 / 0 / 0', '한정판은 054 뒤에 운영자가 칭호마다 update로 켠다 (켰으면 그 수)'
  union all select 9, '같아야 함 (실행 전 7번): 회원 칭호 줄 수', (select count(*)::text from public.user_titles),
    '(실행 전 7번과 같음)', ''
  union all select 10, '같아야 함 (실행 전 8번): 종류별 칭호 줄 수 (활동 / 한정판)',
    (select count(*)::text from public.user_titles t join public.title_catalog c on c.key = t.title_key where c.kind = 'activity') || ' / '
      || (select count(*)::text from public.user_titles t join public.title_catalog c on c.key = t.title_key where c.kind = 'limited'),
    '(실행 전 8번과 같음)', ''
  union all select 11, '같아야 함 (실행 전 9번): 대표 칭호를 고른 회원 수', (select count(*)::text from public.profiles where main_title is not null),
    '(실행 전 9번과 같음)', ''
  union all select 12, '같아야 함 (실행 전 10번): 대표 칭호별 회원 수',
    coalesce((select string_agg(main_title || '=' || n, ' / ' order by main_title)
                from (select main_title, count(*) as n from public.profiles where main_title is not null group by main_title) g), '없음'),
    '(실행 전 10번과 같음)', ''
  union all select 13, '같아야 함 (실행 전 11번): 도감 줄 수 (전체 / 한정판 / 숨김 / 비밀)',
    (select count(*)::text from public.title_catalog) || ' / '
      || (select count(*)::text from public.title_catalog where kind = 'limited') || ' / '
      || (select count(*)::text from public.title_catalog where hidden) || ' / '
      || (select count(*)::text from public.title_catalog where secret),
    '(실행 전 11번과 같음)', ''
) rows
order by ord;
