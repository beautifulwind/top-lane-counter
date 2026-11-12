-- =====================================================================
-- 048(장인 외부 링크 삭제를 감독관도) 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 048 실행 "전"과 "후"에 같은 파일을 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
-- [지금 값]이 [실행 전 정상]/[실행 후 정상]과 맞는지 본다.
--   - 1~5번(기준값)은 실행 전과 실행 후가 같아야 한다. 048은 함수 하나만 바꾸고 데이터는 건드리지 않는다.
--     지금 기준값(2026-11-12): 경험치 129 / 129, 레벨 합계 / 칭호 수 13 / 3, 알림 24, 처리 기록 / 공개 빌드 / 공개 상대법 7 / 2 / 2, 설정값 63.
--     048은 설정값/알림 종류를 더하지 않는다.
--   - 실행 뒤 값이 "실행 후 정상"과 다르면 바로 알려 주세요.
-- (SQL Editor는 운영자 계정이 아니라서 함수를 직접 부르는 검사는 못 한다 - 함수 정의/권한만 본다)
-- =====================================================================
with fn as (
  select p.oid, p.proname, p.prosrc
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
),
rl as (select prosrc from fn where proname = 'remove_link'),
kindcheck as (
  select pg_get_constraintdef(oid) as def from pg_constraint
  where conname = 'notifications_kind_check' and conrelid = 'public.notifications'::regclass
)
select ord as "순서", what as "항목", now_value as "지금 값", before_ok as "실행 전 정상", after_ok as "실행 후 정상", memo as "메모"
from (
  select 1 as ord, '기준값: 경험치 합계 (프로필 xp 합 / 경험치 기록 합)' as what,
    (select coalesce(sum(xp), 0)::text from public.profiles) || ' / ' || (select coalesce(sum(amount), 0)::text from public.xp_events) as now_value,
    '129 / 129' as before_ok, '실행 전과 같음' as after_ok, '' as memo
  union all select 2, '기준값: 레벨 합계 / 칭호 수',
    (select coalesce(sum(level), 0)::text from public.profiles) || ' / ' || (select count(*)::text from public.user_titles), '13 / 3', '실행 전과 같음', ''
  union all select 3, '기준값: 알림 수', (select count(*)::text from public.notifications), '24', '실행 전과 같음',
    E'실행 직후 기준. 그 뒤 사이트 사용으로 늘어날 수 있음'
  union all select 4, '기준값: 처리 기록 수 / 공개 빌드 수 / 공개 상대법 수',
    (select count(*)::text from public.moderation_log) || ' / ' || (select count(*)::text from public.builds where status = 'approved')
      || ' / ' || (select count(*)::text from public.counters where status = 'approved'), '7 / 2 / 2', '실행 전과 같음', ''
  union all select 5, '기준값: 설정값 수 (xp_rules)', (select count(*)::text from public.xp_rules), '63', '63', E'048은 설정값을 더하지 않는다'
  union all select 6, E'링크 삭제 remove_link: 운영진 확인(require_staff) / 감독관 범위 확인(moderatable_author)',
    coalesce((select (prosrc like '%require_staff()%')::text || ' / ' || (prosrc like '%moderatable_author%')::text from rl), '없음'),
    'false / false', 'true / true', E'감독관은 일반 장인의 링크만'
  union all select 7, E'링크 삭제: 운영자 전용 확인(require_operator)이 빠졌나 (048 뒤 false)',
    coalesce((select (prosrc like '%require_operator()%')::text from rl), '없음'), 'true', 'false', ''
  union all select 8, E'링크 삭제: 안쪽 함수(사유 필수/알림/처리 기록)를 그대로 부름',
    coalesce((select (prosrc like '%remove_link_unchecked%')::text from rl), '없음'), 'true', 'true', E'047 remove_link_unchecked 그대로'
  union all select 9, E'링크 삭제를 부를 수 있나 (로그인 사용자 / 비로그인)',
    coalesce((select has_function_privilege('authenticated', oid, 'execute')::text || ' / ' || has_function_privilege('anon', oid, 'execute')::text
                from fn where proname = 'remove_link'), '없음'),
    'true / false', 'true / false', E'운영진인지는 함수 안에서'
  union all select 10, E'운영자만 그대로 (신고 목록 / 신고 기각 / 사이트 더하기 / 사이트 빼기 - require_operator 있음)',
    (select string_agg(coalesce((select (prosrc like '%require_operator()%')::text from fn where proname = f), '없음'), ' / ' order by o)
       from (values (1, 'admin_link_reports'), (2, 'dismiss_link_reports'), (3, 'admin_add_link_domain'), (4, 'admin_remove_link_domain')) v(o, f)),
    'true / true / true / true', 'true / true / true / true', ''
  union all select 11, E'안쪽 함수 remove_link_unchecked를 로그인 사용자/비로그인이 부를 수 있나 (false여야 함)',
    coalesce((select (has_function_privilege('authenticated', oid, 'execute') or has_function_privilege('anon', oid, 'execute'))::text
                from fn where proname = 'remove_link_unchecked'), '없음'), 'false', 'false', ''
  union all select 12, E'알림 종류: link_removed 있음 (048은 종류를 더하지 않음)',
    (select (def like '%link_removed%')::text from kindcheck), 'true', 'true', ''
  union all select 13, E'처리 기록 종류: remove_link 있음 (그대로)',
    (select (pg_get_constraintdef(oid) like '%remove_link%')::text from pg_constraint
      where conname = 'moderation_log_action_check' and conrelid = 'public.moderation_log'::regclass), 'true', 'true', ''
  union all select 14, E'링크 수 / 링크 신고 수 (그대로)',
    (select count(*)::text from public.ext_links) || ' / ' || (select count(*)::text from public.link_reports), '-', E'실행 전과 같음', ''
) x
order by ord;
