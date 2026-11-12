-- =====================================================================
-- 049(운영자가 장인을 직접 지정) 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 049 실행 "전"과 "후"에 같은 파일을 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
-- [지금 값]이 [실행 전 정상]/[실행 후 정상]과 맞는지 본다.
--   - 1~5번(기준값)은 실행 전과 실행 후가 같아야 한다. 049는 칸/검사/함수만 더하고 기존 데이터는 바꾸지 않는다.
--     지금 기준값(2026-11-12): 경험치 129 / 129, 레벨 합계 / 칭호 수 13 / 3, 알림 24, 처리 기록 / 공개 빌드 / 공개 상대법 7 / 2 / 2, 설정값 63.
--     049는 설정값/알림 종류를 더하지 않는다.
--   - 실행 뒤 값이 "실행 후 정상"과 다르면 바로 알려 주세요.
-- (SQL Editor는 운영자 계정이 아니라서 함수를 직접 부르는 검사는 못 한다 - 함수 정의/권한만 본다)
-- direct 칸이 아직 없을 때(실행 전)도 오류 없이 돌도록, 그 칸을 읽는 곳은 query_to_xml로 감쌌다.
-- =====================================================================
with fn as (
  select p.oid, p.proname, p.prosrc
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
),
has_direct as (
  select exists (select 1 from information_schema.columns
                  where table_schema = 'public' and table_name = 'influencer_applications' and column_name = 'direct') as yes
),
con as (
  select conname, pg_get_constraintdef(oid) as def from pg_constraint
  where conrelid in ('public.moderation_log'::regclass, 'public.notifications'::regclass, 'public.influencer_applications'::regclass)
)
select ord as "순서", what as "항목", now_value as "지금 값", before_ok as "실행 전 정상", after_ok as "실행 후 정상", memo as "메모"
from (
  select 1 as ord, '기준값: 경험치 합계 (프로필 xp 합 / 경험치 기록 합)' as what,
    (select coalesce(sum(xp), 0)::text from public.profiles) || ' / ' || (select coalesce(sum(amount), 0)::text from public.xp_events) as now_value,
    '129 / 129' as before_ok, '실행 전과 같음' as after_ok, '' as memo
  union all select 2, '기준값: 레벨 합계 / 칭호 수',
    (select coalesce(sum(level), 0)::text from public.profiles) || ' / ' || (select count(*)::text from public.user_titles), '13 / 3', '실행 전과 같음', ''
  union all select 3, '기준값: 알림 수', (select count(*)::text from public.notifications), '24', '실행 전과 같음',
    '실행 직후 기준. 그 뒤 사이트 사용으로 늘어날 수 있음'
  union all select 4, '기준값: 처리 기록 수 / 공개 빌드 수 / 공개 상대법 수',
    (select count(*)::text from public.moderation_log) || ' / ' || (select count(*)::text from public.builds where status = 'approved')
      || ' / ' || (select count(*)::text from public.counters where status = 'approved'), '7 / 2 / 2', '실행 전과 같음', ''
  union all select 5, '기준값: 설정값 수 (xp_rules)', (select count(*)::text from public.xp_rules), '63', '63', '049는 설정값을 더하지 않는다'
  union all select 6, '048까지 실행됨 (링크 삭제에 감독관 범위 검사)',
    coalesce((select (prosrc like '%moderatable_author%')::text from fn where proname = 'remove_link'), '없음'), 'true', 'true',
    'false/없음이면 048부터 실행'
  union all select 7, '신청 표에 직접 지정 칸 direct', (select yes::text from has_direct), 'false', 'true', ''
  union all select 8, '신청 표 검사(influencer_applications_fields)가 직접 지정 줄을 앎',
    (select (def like '%direct%')::text from con where conname = 'influencer_applications_fields'), 'false', 'true', ''
  union all select 9, '처리 기록 종류: grant_influencer / remove_link (그대로)',
    (select (def like '%grant_influencer%')::text || ' / ' || (def like '%remove_link%')::text from con where conname = 'moderation_log_action_check'),
    'false / true', 'true / true', ''
  union all select 10, '알림 종류: influencer_approved 있음 / link_removed 있음 (049는 종류를 더하지 않음)',
    (select (def like '%influencer_approved%')::text || ' / ' || (def like '%link_removed%')::text from con where conname = 'notifications_kind_check'),
    'true / true', 'true / true', '지정 알림은 influencer_approved 그대로'
  union all select 11, '직접 지정 grant_influencer: 운영자 전용 확인(require_operator)',
    coalesce((select (prosrc like '%require_operator()%')::text from fn where proname = 'grant_influencer'), '없음'), '없음', 'true',
    '감독관 거부, 운영자 모드 꺼짐 거부'
  union all select 12, '직접 지정을 부를 수 있나 (로그인 사용자 / 비로그인)',
    coalesce((select has_function_privilege('authenticated', oid, 'execute')::text || ' / ' || has_function_privilege('anon', oid, 'execute')::text
                from fn where proname = 'grant_influencer'), '없음'), '없음', 'true / false', '운영자인지는 함수 안에서'
  union all select 13, '안쪽 함수 grant_influencer_unchecked를 로그인 사용자/비로그인이 부를 수 있나',
    coalesce((select (has_function_privilege('authenticated', oid, 'execute') or has_function_privilege('anon', oid, 'execute'))::text
                from fn where proname = 'grant_influencer_unchecked'), '없음'), '없음', 'false', ''
  union all select 14, '운영자 신청 목록이 줄마다 direct를 돌려줌',
    coalesce((select (prosrc like '%''direct''%')::text from fn where proname = 'admin_influencer_applications_unchecked'), '없음'), 'false', 'true', ''
  union all select 15, '인증 해제 revoke_influencer: 운영자 전용 그대로 / 링크 삭제 트리거 있음',
    coalesce((select (prosrc like '%require_operator()%')::text from fn where proname = 'revoke_influencer'), '없음') || ' / '
      || exists (select 1 from pg_trigger where tgname = 'ext_links_on_influencer_end')::text, 'true / true', 'true / true', '해제 규칙은 046/047 그대로'
  union all select 16, '장인 수 / 승인된 신청 수 / 처리 전 신청 수',
    (select count(*)::text from public.profiles where influencer is not null) || ' / '
      || (select count(*)::text from public.influencer_applications where status = 'approved') || ' / '
      || (select count(*)::text from public.influencer_applications where status = 'pending'), '-', '실행 전과 같음', ''
  union all select 17, '직접 지정 줄 수',
    case when (select yes from has_direct)
         then (xpath('/row/c/text()', query_to_xml('select count(*) as c from public.influencer_applications where direct', false, true, '')))[1]::text
         else '칸 없음' end, '칸 없음', '0', '실행 직후 기준. 지정하면 늘어남'
) x
order by ord;
