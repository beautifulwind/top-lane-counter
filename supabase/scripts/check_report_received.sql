-- =====================================================================
-- 045(게시판 신고 → 운영진 알림 report_received) 확인 조회 (읽기만 — 아무것도 바꾸지 않는다).
-- 045 실행 "전"과 "후"에 한 번씩 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
-- [지금 값]이 [실행 전 정상]·[실행 후 정상]과 맞는지 본다.
--   - 11·12번(기존 알림 수·신고 수)은 실행 전 값을 적어 두었다가 실행 후 값과 같은지 본다 (045는 기존 데이터를 바꾸지 않는다).
--     11번은 신고 알림(report_received)을 뺀 수라 실행 뒤 신고가 들어와도 같다 (신고 알림 수는 13·14번).
--   - 5번 오른쪽 값이 false면 예전 알림 종류가 빠진 것이다 (바로 알려 주세요).
--   - 13번: 045 실행 전에 이미 쌓여 있던 처리 전 신고에는 알림을 소급해서 보내지 않는다 (실행 직후 0이 정상).
-- (SQL Editor는 운영자 계정이 아니라서 함수를 직접 부르는 검사는 못 한다 — 아래 사이트 확인으로)
--
-- 사이트에서 눈으로 확인할 것 (045 실행 + web-push 재배포 + 새 화면 push 다음):
--  1) 일반 회원 계정으로 남의 글·댓글·문서 댓글을 신고 → 운영자(운영자 모드 켜짐)·감독관 [알림]에 「새 신고가 들어왔습니다. (글)」
--     신고한 본인은 알림이 없다. 같은 글에 둘째 신고가 와도 알림은 늘지 않는다. 알림을 누르면 신고 화면 "글·댓글 신고" 탭.
--  2) 운영자 모드를 끄면 이 알림이 목록·빨간 점에서 사라지고 [모두 읽음]도 건드리지 않는다. 다시 켜면 그대로.
--  3) 운영진이 쓴 글을 신고하면 운영자에게만 간다 (감독관은 처리할 수 없는 글).
--  4) 휴대폰 알림을 켠 운영진: 새 신고가 잠금 화면에 오고, 누르면 신고 화면 (푸시 설정 "운영진 알림"에 묶임).
-- =====================================================================
with fn as (
  select p.oid, p.proname, p.prosrc
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('notify_staff_new_report', 'mark_all_notifications_read', 'push_group', 'push_targets')
),
kindcheck as (
  select pg_get_constraintdef(oid) as def from pg_constraint
  where conname = 'notifications_kind_check' and conrelid = 'public.notifications'::regclass
),
pol as (
  select coalesce(qual, '') as q from pg_policies
  where schemaname = 'public' and tablename = 'notifications' and policyname = 'notifications: 본인 읽기'
)
select ord as "순서", what as "항목", now_value as "지금 값", before_ok as "실행 전 정상", after_ok as "실행 후 정상"
from (
  select 1 as ord, '043 실행됨 (045의 전제: 오류 신고 표 wiki_reports)' as what,
    (to_regclass('public.wiki_reports') is not null)::text as now_value, 'true' as before_ok, 'true' as after_ok
  union all select 2, '새 신고 알림 트리거 함수 notify_staff_new_report',
    (exists (select 1 from fn where proname = 'notify_staff_new_report'))::text, 'false', 'true'
  union all select 3, '신고 표(reports)에 트리거 reports_notify_staff (insert 뒤)',
    (select count(*)::text from pg_trigger where tgname = 'reports_notify_staff' and tgrelid = 'public.reports'::regclass and not tgisinternal),
    '0', '1'
  union all select 4, '트리거 함수를 누가 부를 수 있나 (false여야 함 — 로그인 사용자·비로그인 모두)',
    coalesce((select bool_or(has_function_privilege('authenticated', oid, 'execute') or has_function_privilege('anon', oid, 'execute'))::text
      from fn where proname = 'notify_staff_new_report'), '함수 없음'), '함수 없음', 'false'
  union all select 5, '알림 종류에 report_received (예전 종류도 그대로)',
    (select (def like '%report_received%')::text from kindcheck) || ' / '
      || (select (def like '%error_reported%' and def like '%error_report_handled%' and def like '%post_created%'
                  and def like '%matchup_created%' and def like '%inquiry_received%' and def like '%doc_comment_deleted%')::text from kindcheck),
    'false / true', 'true / true'
  union all select 6, '운영자 모드를 끄면 신고 알림도 가림 (읽기 정책 · 모두 읽음)',
    (select (q like '%report_received%')::text from pol) || ' / '
      || coalesce((select (prosrc like '%report_received%')::text from fn where proname = 'mark_all_notifications_read'), '-'),
    'false / false', 'true / true'
  union all select 7, '운영자 모드 가림 목록에 있던 종류도 그대로 (오류 신고·새 글·새 문의)',
    (select (q like '%error_reported%' and q like '%post_created%' and q like '%inquiry_received%')::text from pol) || ' / '
      || coalesce((select (prosrc like '%error_reported%' and prosrc like '%post_created%')::text from fn where proname = 'mark_all_notifications_read'), '-'),
    'true / true', 'true / true'
  union all select 8, '푸시 묶음: 새 신고 = staff_new, 오류 신고·새 글 = staff_new (그대로), 오류 신고 처리 결과 = 안 보냄',
    coalesce(public.push_group('report_received'), '안 보냄') || ' / ' || coalesce(public.push_group('error_reported'), '안 보냄')
      || ' / ' || coalesce(public.push_group('post_created'), '안 보냄') || ' / ' || coalesce(public.push_group('error_report_handled'), '안 보냄'),
    '안 보냄 / staff_new / staff_new / 안 보냄', 'staff_new / staff_new / staff_new / 안 보냄'
  union all select 9, '내 제안 결과 묶음은 그대로 (my_results)',
    coalesce(public.push_group('proposal_approved'), '안 보냄') || ' / ' || coalesce(public.push_group('build_restored'), '안 보냄'),
    'my_results / my_results', 'my_results / my_results'
  union all select 10, '푸시 대상 조회 push_targets가 post_id를 돌려줌 (042 — 새 알림은 글 번호를 달고 감)',
    (select (prosrc like '%''post_id'', n.post_id%')::text from fn where proname = 'push_targets'), 'true', 'true'
  union all select 11, '기존 알림 수 — 신고 알림(report_received) 제외 (실행 전후 같아야 함)',
    (select count(*)::text from public.notifications where kind <> 'report_received'), '-', '실행 전과 같음'
  union all select 12, '게시판 신고 수 (전체 / 처리 전) — 실행 전후 같아야 함 (실행 뒤 새 신고만큼만 늘어남)',
    (select count(*)::text from public.reports) || ' / ' || (select count(*)::text from public.reports where status = 'open'), '-', '실행 전과 같음'
  union all select 13, '실행 전에 이미 쌓여 있던 처리 전 신고에는 알림을 소급해서 보내지 않음 (045 실행 직후 신고 알림 수)',
    (select count(*)::text from public.notifications where kind = 'report_received'), '0', '0 (실행 직후)'
  union all select 14, '처리 전 신고 대상 수 (글+댓글+문서 댓글) / 신고 알림이 달린 줄 수(운영진 수만큼 한 대상에 여러 줄)',
    (select count(*)::text from (select distinct post_id, comment_id, doc_comment_id from public.reports where status = 'open') x)
      || ' / ' || (select count(*)::text from public.notifications where kind = 'report_received'),
    '-', '신고가 들어올 때마다 알림 줄이 늘어남'
) x
order by ord;
