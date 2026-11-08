-- =====================================================================
-- 033(관리자 편의: 운영진 알림·처리 대기 건수·감독관도 고쳐서 승인) 확인 조회 (읽기만 — 아무것도 바꾸지 않는다).
-- 033 실행 "전"과 "후"에 한 번씩 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다.
-- [지금 값]이 [실행 전 정상]·[실행 후 정상]과 맞는지 본다.
-- =====================================================================
with fn as (
  select p.oid, p.proname, p.prosrc from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('notify_staff', 'notify_staff_new_proposal', 'notify_staff_new_build', 'notify_staff_new_inquiry', 'admin_pending_counts', 'describe_proposal_edit')
), trg as (
  select tgname, tgrelid::regclass::text as tbl from pg_trigger
  where not tgisinternal and tgname in (
    'edit_proposals_notify_staff_insert', 'edit_proposals_notify_staff_resubmit', 'builds_notify_staff_insert',
    'builds_notify_staff_resubmit', 'inquiries_notify_staff_insert', 'inquiries_notify_staff_move')
)
select ord as "순서", what as "항목", now_value as "지금 값", before_ok as "실행 전 정상", after_ok as "실행 후 정상"
from (
  select 1 as ord, '032 실행됨 (033의 전제: inquiries 표)' as what, (to_regclass('public.inquiries') is not null)::text as now_value, 'true' as before_ok, 'true' as after_ok
  union all select 2, '알림 종류에 proposal_submitted·build_submitted·inquiry_received 포함',
    (select (pg_get_constraintdef(oid) like '%proposal_submitted%' and pg_get_constraintdef(oid) like '%build_submitted%' and pg_get_constraintdef(oid) like '%inquiry_received%')::text
       from pg_constraint where conname = 'notifications_kind_check' and conrelid = 'public.notifications'::regclass), 'false', 'true'
  union all select 3, '알림 종류에 예전 종류(inquiry_answered 등)도 그대로',
    (select (pg_get_constraintdef(oid) like '%inquiry_answered%' and pg_get_constraintdef(oid) like '%moderator_granted%' and pg_get_constraintdef(oid) like '%doc_comment_restored%')::text
       from pg_constraint where conname = 'notifications_kind_check' and conrelid = 'public.notifications'::regclass), 'true', 'true'
  union all select 4, '처리 기록 종류에 edit_proposal 포함 (예전 answer_inquiry·move_inquiry도 그대로)',
    (select (pg_get_constraintdef(oid) like '%edit_proposal%' and pg_get_constraintdef(oid) like '%answer_inquiry%' and pg_get_constraintdef(oid) like '%move_inquiry%')::text
       from pg_constraint where conname = 'moderation_log_action_check' and conrelid = 'public.moderation_log'::regclass), 'false', 'true'
  union all select 5, '새 함수 6개 (알림 4 · 대기 건수 1 · 고친 곳 설명 1)', (select count(*)::text from fn), '0', '6'
  union all select 6, '새 트리거 6개 (제안 2 · 빌드 2 · 문의 2)', (select count(*)::text from trg), '0', '6'
  union all select 7, '트리거가 붙은 표 (edit_proposals 2 · builds 2 · inquiries 2)',
    coalesce((select string_agg(tbl || ' ' || n, ' · ' order by tbl) from (select tbl, count(*) as n from trg group by tbl) x), '없음'), '없음',
    'builds 2 · edit_proposals 2 · inquiries 2'
  union all select 8, '안쪽 함수 5개를 일반 사용자·비로그인이 부를 수 있나 (false여야 함)',
    coalesce((select bool_or(has_function_privilege('authenticated', oid, 'execute') or has_function_privilege('anon', oid, 'execute'))::text from fn where proname <> 'admin_pending_counts'), '함수 없음'), '함수 없음', 'false'
  union all select 9, '대기 건수 함수: 비로그인 호출 불가(false) / 로그인 호출 가능(true — 운영진인지는 함수 안에서 검사)',
    coalesce((select has_function_privilege('anon', oid, 'execute')::text || ' / ' || has_function_privilege('authenticated', oid, 'execute')::text from fn where proname = 'admin_pending_counts'), '함수 없음'), '함수 없음', 'false / true'
  union all select 10, '대기 건수 함수가 운영진 검사(require_staff)를 하나',
    coalesce((select (prosrc like '%require_staff%')::text from fn where proname = 'admin_pending_counts'), '함수 없음'), '함수 없음', 'true'
  union all select 11, '승인 함수에서 "감독관은 고쳐서 승인 불가" 제한이 빠지고 처리 기록(edit_proposal)이 들어갔나',
    (select (prosrc not like '%감독관은 내용을 고쳐서 승인할 수 없습니다%' and prosrc like '%edit_proposal%')::text
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'approve_proposal_unchecked'), 'false', 'true'
  union all select 12, '승인 함수가 여전히 버전 확인·처리 중 확인·감독관 범위 제한을 하나 (031 유지)',
    (select (prosrc like '%require_review_allowed%' and prosrc like '%require_staff%')::text
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'approve_proposal_unchecked'), 'true', 'true'
  union all select 13, '버전 확인을 하는 승인 함수(approve_proposal, 5개 인자)가 그대로 있나',
    (select (count(*) = 1)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public' and p.proname = 'approve_proposal' and p.pronargs = 5 and p.prosrc like '%require_proposal_version%'), 'true', 'true'
  union all select 14, '"검토 중" 표시(031)가 그대로: 표 + 함수 3개',
    (to_regclass('public.proposal_reviewing') is not null)::text || ' + ' ||
    (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('start_proposal_review', 'end_proposal_review', 'proposal_reviewers')), 'true + 3', 'true + 3'
  union all select 15, '지금 승인 대기 제안 · 빌드 · 답변 대기 문의 (읽기: 이 화면은 운영자 권한이라 전체가 보임)',
    (select count(*)::text from public.edit_proposals where status = 'pending') || ' · ' ||
    (select count(*)::text from public.builds where status = 'pending') || ' · ' ||
    (select count(*)::text from public.inquiries where answer is null), '-', '-'
  union all select 16, '기존 알림 수 (실행 전후 같아야 함)', (select count(*)::text from public.notifications), '-', '실행 전과 같음'
  union all select 17, '기존 처리 기록 수 (실행 전후 같아야 함)', (select count(*)::text from public.moderation_log), '-', '실행 전과 같음'
) x
order by ord;

-- ---------------------------------------------------------------------
-- 실제로 알림이 가는지 눈으로 확인 (033 실행 뒤, 사이트에서):
--  1) 일반 계정으로 문의를 하나 보낸다 → 운영자 계정의 [알림]에 "새 문의가 들어왔습니다. (분류: …)"가 생긴다
--     ("계정·탈퇴"로 보내면 감독관 계정에는 알림이 없다)
--  2) 일반 계정으로 새 카운터 제안을 낸다 → 운영자·감독관 계정 둘 다 "새 카운터 제안이 들어왔습니다."
--  3) 운영자 계정으로 ☰ 메뉴를 연다 → [관리] 옆에 대기 건수 숫자
-- 알림 읽기 (운영자 권한 SQL Editor에서):
-- select u.nickname, n.kind, n.message, n.created_at from public.notifications n join public.profiles u on u.id = n.user_id
--  where n.kind in ('proposal_submitted', 'build_submitted', 'inquiry_received') order by n.id desc limit 20;
-- 처리 기록에서 "누가 무엇을 고쳤는지":
-- select created_at, actor_nickname, actor_role, target_id, note from public.moderation_log where action = 'edit_proposal' order by id desc limit 20;
-- ---------------------------------------------------------------------
