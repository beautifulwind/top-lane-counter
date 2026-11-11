-- =====================================================================
-- 039(승인 제도 끄기) 확인 조회 (읽기만 — 아무것도 바꾸지 않는다).
-- 039 실행 "전"과 "후"에 한 번씩 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다.
-- [지금 값]이 [실행 전 정상]·[실행 후 정상]과 맞는지 본다.
--   - 4·5번(승인 대기·재검토)이 실행 전에 0이 아니면 039가 실행되지 않는다 → 운영자 페이지에서 먼저 처리.
--   - 10번(경험치 합계)은 실행 전 값을 적어 두었다가 실행 후 값과 같은지 본다 (039는 경험치를 바꾸지 않는다).
--   - 039에는 따로 등록할 pg_cron 일정이 없다.
-- =====================================================================
select ord as "순서", item as "항목", now_value as "지금 값", before_ok as "실행 전 정상", after_ok as "실행 후 정상"
from (
  select 1 as ord, '038 실행됨 (approval_on 함수 있음)' as item,
    (to_regprocedure('public.approval_on()') is not null)::text as now_value, 'true' as before_ok, 'true' as after_ok
  union all select 2, '승인 스위치 xp_rules.approval_on',
    coalesce((select value::text from public.xp_rules where key = 'approval_on'), '없음'), '1', '0'
  union all select 3, '승인 스위치 설명에 039 기록',
    coalesce((select (note like '%039에서 0으로 끔%')::text from public.xp_rules where key = 'approval_on'), '없음'), 'false', 'true'
  union all select 4, '승인 대기·재검토 중 제안',
    (select count(*)::text from public.edit_proposals where status in ('pending', 'revision_requested')), '0 (아니면 먼저 처리)', '0'
  union all select 5, '승인 대기·재검토 중 빌드',
    (select count(*)::text from public.builds where status in ('pending', 'revision_requested')), '0 (아니면 먼저 처리)', '0'
  union all select 6, '제안 "검토 중" 표시',
    (select count(*)::text from public.proposal_reviewing), '아무 수', '0'
  union all select 7, '공개(숨김 포함) 빌드 중 번호·요약이 빠진 것',
    (select count(*)::text from public.builds where status in ('approved', 'hidden') and (seq is null or summary is null)), '0', '0'
  union all select 8, '옛 길을 막는 함수 (제안·빌드 등록 검사)',
    (to_regprocedure('public.check_new_proposal()') is not null and to_regprocedure('public.check_new_build()') is not null)::text, 'true', 'true'
  union all select 9, '새 상대법·새 빌드 휴대폰 알림 묶음',
    public.push_group('matchup_created') || ' · ' || public.push_group('build_created'), 'staff_new · staff_new', 'staff_new · staff_new'
  union all select 10, '경험치 합계 (모든 사람) — 실행 전 값과 같아야 함',
    (select coalesce(sum(xp), 0)::text from public.profiles), '(적어 두기)', '실행 전과 같음'
) rows
order by ord;
