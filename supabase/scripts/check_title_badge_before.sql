-- =====================================================================
-- 054(한정판 대표 칭호 + 닉네임 옆 배지) 실행 "전" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 054를 실행하기 전에 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~6번: [지금 값]이 [정상 값]과 모두 맞으면 054를 실행해도 된다. 하나라도 다르면 실행하지 말고 알려 주세요.
--   - 7~11번은 "적어 둘 값"이다. 054 실행 뒤 check_title_badge_after.sql의 같은 이름 줄과 비교한다.
--     054는 회원의 칭호와 대표 칭호를 바꾸지 않으므로 실행 직후에는 같아야 한다
--     (그 사이 사이트에서 누가 칭호를 얻거나 대표 칭호를 바꾸면 달라질 수 있다 - 그때는 알려 주세요).
-- 054가 만드는 함수/트리거가 아직 없어도 오류 없이 돌도록 to_regprocedure/pg_trigger만 쓴다.
-- =====================================================================
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '053까지 실행됨 (도감 표 title_catalog / 함수 my_title_book)' as what,
    (to_regclass('public.title_catalog') is not null)::text || ' / '
      || (to_regprocedure('public.my_title_book()') is not null)::text as now_value,
    'true / true' as ok_value, 'false면 053부터 실행' as memo
  union all select 2, '054 아직 안 함: 함수 public_title_info / 트리거 title_catalog_unequip',
    (to_regprocedure('public.public_title_info()') is not null)::text || ' / '
      || exists (select 1 from pg_trigger where tgname = 'title_catalog_unequip')::text,
    'false / false', 'true면 이미 실행한 것 - 다시 실행하지 말 것'
  union all select 3, '도감 표 제약: 053 것(활동만 장착) 있음 / 054 것(장인만 불가) 있음',
    exists (select 1 from pg_constraint where conname = 'title_catalog_equip_activity_only'
             and conrelid = 'public.title_catalog'::regclass)::text || ' / '
      || exists (select 1 from pg_constraint where conname = 'title_catalog_equip_kind'
                  and conrelid = 'public.title_catalog'::regclass)::text,
    'true / false', '053 것이 없으면 054가 멈춘다'
  union all select 4, '장착 가능한 칭호 수: 활동 / 한정판 / 장인',
    (select count(*)::text from public.title_catalog where equippable and kind = 'activity') || ' / '
      || (select count(*)::text from public.title_catalog where equippable and kind = 'limited') || ' / '
      || (select count(*)::text from public.title_catalog where equippable and kind = 'influencer'),
    '6 / 0 / 0', '053 제약 때문에 한정판/장인은 0'
  union all select 5, '대표 칭호가 장착 불가 칭호인 회원 수 / 숨김 칭호인 회원 수',
    (select count(*)::text from public.profiles p join public.title_catalog c on c.key = p.main_title where not c.equippable) || ' / '
      || (select count(*)::text from public.profiles p join public.title_catalog c on c.key = p.main_title where c.hidden),
    '0 / 0', '숨김 쪽이 0이 아니어도 054는 돈다(그 회원의 배지만 안 보임) - 알려 주세요'
  union all select 6, '대표 칭호인데 가진 칭호가 아닌 회원 수 / 운영자 계정의 대표 칭호',
    (select count(*)::text from public.profiles p
      where p.main_title is not null
        and not exists (select 1 from public.user_titles t where t.user_id = p.id and t.title_key = p.main_title)) || ' / '
      || coalesce((select string_agg(coalesce(main_title, '없음'), ',') from public.profiles where role = 'admin'), '운영자 없음'),
    '0 / 없음', '외래 키와 운영자 규칙이 있어 늘 이 값 (운영자 계정이 아예 없으면 "운영자 없음")'
  union all select 7, '적어 둘 값: 회원 칭호 줄 수 (user_titles)', (select count(*)::text from public.user_titles),
    '(이 값을 적어 둠)', '054 뒤 같아야 함'
  union all select 8, '적어 둘 값: 종류별 칭호 줄 수 (활동 / 한정판)',
    (select count(*)::text from public.user_titles t join public.title_catalog c on c.key = t.title_key where c.kind = 'activity') || ' / '
      || (select count(*)::text from public.user_titles t join public.title_catalog c on c.key = t.title_key where c.kind = 'limited'),
    '(이 값을 적어 둠)', '054 뒤 같아야 함'
  union all select 9, '적어 둘 값: 대표 칭호를 고른 회원 수', (select count(*)::text from public.profiles where main_title is not null),
    '(이 값을 적어 둠)', '054 뒤 같아야 함'
  union all select 10, '적어 둘 값: 대표 칭호별 회원 수',
    coalesce((select string_agg(main_title || '=' || n, ' / ' order by main_title)
                from (select main_title, count(*) as n from public.profiles where main_title is not null group by main_title) g), '없음'),
    '(이 값을 적어 둠)', '054 뒤 같아야 함'
  union all select 11, '적어 둘 값: 도감 줄 수 (전체 / 한정판 / 숨김 / 비밀)',
    (select count(*)::text from public.title_catalog) || ' / '
      || (select count(*)::text from public.title_catalog where kind = 'limited') || ' / '
      || (select count(*)::text from public.title_catalog where hidden) || ' / '
      || (select count(*)::text from public.title_catalog where secret),
    '(이 값을 적어 둠)', '054는 도감 줄을 넣거나 지우지 않는다'
) rows
order by ord;
