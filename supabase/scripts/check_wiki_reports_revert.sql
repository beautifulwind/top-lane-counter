-- =====================================================================
-- 043(오류 신고 · 빌드 되돌리기 · 운영자 빌드 수정 기록 · 감독관 빌드 숨기기) 확인 조회 (읽기만 — 아무것도 바꾸지 않는다).
-- 043 실행 "전"과 "후"에 한 번씩 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
-- [지금 값]이 [실행 전 정상]·[실행 후 정상]과 맞는지 본다. (SQL Editor는 운영자 계정이 아니라서 함수를 직접 부르는 검사는 못 한다 — 아래 사이트 확인으로)
--   - 18·19번(기존 알림 수·빌드 수정 기록 수)은 실행 전 값을 적어 두었다가 실행 후 값과 같은지 본다 (043은 기존 데이터를 바꾸지 않는다).
--   - 21번(pg_cron 일정)은 일정을 등록한 뒤 1이 된다.
--
-- 사이트에서 눈으로 확인할 것 (2단계 화면이 나온 다음):
--  1) 정식 회원 계정 → 상대법·빌드 ⋮ → "오류 신고" → 이유·메모 → 운영자·감독관 [알림]에 "새 오류 신고가 들어왔습니다." (비회원은 로그인 안내)
--  2) 운영진 → [관리] → 신고 → "오류 신고" 탭에서 처리됨/기각 + 메모 → 신고자 [알림]에 결과 (휴대폰 알림은 없음)
--  3) 운영자 → 빌드 ⋮ → "수정 기록 자세히" → 전후 비교 → [이 시점으로 되돌리기] → 그 빌드를 편집 중이던 다른 창은 저장할 때
--     「다른 분이 먼저 수정했습니다.」
--  4) 감독관 → 일반 회원이 처음 등록한 빌드 ⋮ → "빌드 숨기기"·"다시 공개". 운영진이 처음 등록한 빌드·숨긴 상대법의 빌드는 거부.
-- =====================================================================
with fn as (
  select p.oid, p.proname, p.prosrc
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in ('report_wiki', 'staff_wiki_reports', 'handle_wiki_report', 'purge_wiki_reports',
                      'admin_build_revisions', 'admin_build_revisions_unchecked', 'revert_build', 'revert_build_unchecked',
                      'build_edit_check', 'require_moderate_build', 'wiki_report_reason_label',
                      'edit_build', 'hide_build', 'restore_build', 'admin_pending_counts', 'admin_member_detail',
                      'mark_all_notifications_read', 'push_group')
),
kindcheck as (
  select pg_get_constraintdef(oid) as def from pg_constraint
  where conname = 'notifications_kind_check' and conrelid = 'public.notifications'::regclass
),
logcheck as (
  select string_agg(pg_get_constraintdef(oid), ' ') as def from pg_constraint
  where conname in ('moderation_log_action_check', 'moderation_log_target_kind_check') and conrelid = 'public.moderation_log'::regclass
),
pol as (
  select coalesce(qual, '') as q from pg_policies
  where schemaname = 'public' and tablename = 'notifications' and policyname = 'notifications: 본인 읽기'
)
select ord as "순서", what as "항목", now_value as "지금 값", before_ok as "실행 전 정상", after_ok as "실행 후 정상"
from (
  select 1 as ord, '042 실행됨 (043의 전제: 회원 정보 admin_member_detail)' as what,
    (exists (select 1 from fn where proname = 'admin_member_detail'))::text as now_value, 'true' as before_ok, 'true' as after_ok
  union all select 2, '오류 신고 표 wiki_reports',
    (to_regclass('public.wiki_reports') is not null)::text, 'false', 'true'
  union all select 3, '오류 신고 표: RLS 켜짐 / 정책 수(0 = 함수로만) / 로그인 사용자 직접 읽기(false)',
    case when to_regclass('public.wiki_reports') is null then '표 없음' else
      (select relrowsecurity::text from pg_class where oid = to_regclass('public.wiki_reports')) || ' / '
      || (select count(*)::text from pg_policies where schemaname = 'public' and tablename = 'wiki_reports') || ' / '
      || (select has_table_privilege('authenticated', oid, 'select')::text from pg_class where oid = to_regclass('public.wiki_reports')) end,
    '표 없음', 'true / 0 / false'
  union all select 4, '빌드 수정 기록에 되돌리기 기준 칸 (build_revisions.revert_of)',
    exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'build_revisions' and column_name = 'revert_of')::text,
    'false', 'true'
  union all select 5, '새 함수 11개 (신고 4 · 기록 2 · 되돌리기 2 · 도우미 3)',
    (select count(*)::text from fn where proname in ('report_wiki', 'staff_wiki_reports', 'handle_wiki_report', 'purge_wiki_reports',
      'admin_build_revisions', 'admin_build_revisions_unchecked', 'revert_build', 'revert_build_unchecked',
      'build_edit_check', 'require_moderate_build', 'wiki_report_reason_label')), '0', '11'
  union all select 6, '운영자 전용(require_operator): 수정 기록·되돌리기 바깥 함수',
    coalesce((select (count(*) filter (where prosrc like '%require_operator()%'))::text || ' / ' || count(*)::text from fn
      where proname in ('admin_build_revisions', 'revert_build')), '-'), '0 / 0', '2 / 2'
  union all select 7, '운영진(require_staff): 신고 목록·처리, 빌드 숨기기·다시 공개 (실행 전에는 숨기기 2개가 운영자 전용)',
    (select (count(*) filter (where prosrc like '%require_staff()%'))::text || ' / ' || count(*)::text from fn
      where proname in ('staff_wiki_reports', 'handle_wiki_report', 'hide_build', 'restore_build')), '0 / 2', '4 / 4'
  union all select 8, '빌드 숨기기·다시 공개에 감독관 범위 검사(require_moderate_build)·처리 기록(log_moderation)',
    (select (count(*) filter (where prosrc like '%require_moderate_build(b)%' and prosrc like '%log_moderation%'))::text from fn
      where proname in ('hide_build', 'restore_build')), '0', '2'
  union all select 9, '안쪽 함수를 누가 부를 수 있나 (false여야 함 — 로그인 사용자·비로그인 모두)',
    coalesce((select bool_or(has_function_privilege('authenticated', oid, 'execute') or has_function_privilege('anon', oid, 'execute'))::text from fn
      where proname in ('admin_build_revisions_unchecked', 'revert_build_unchecked', 'purge_wiki_reports', 'build_edit_check',
                        'require_moderate_build', 'wiki_report_reason_label')), '함수 없음'), '함수 없음', 'false'
  union all select 10, '바깥 함수: 비로그인 실행(false) / 로그인 사용자 실행(true — 권한은 함수 안에서 검사)',
    coalesce((select bool_or(has_function_privilege('anon', oid, 'execute'))::text || ' / ' || bool_and(has_function_privilege('authenticated', oid, 'execute'))::text from fn
      where proname in ('report_wiki', 'staff_wiki_reports', 'handle_wiki_report', 'admin_build_revisions', 'revert_build')), '함수 없음'), '함수 없음', 'false / true'
  union all select 11, '오류 신고는 정식 회원만 (report_wiki가 비회원을 거부)',
    coalesce((select (prosrc like '%is_guest(me)%')::text from fn where proname = 'report_wiki'), '함수 없음'), '함수 없음', 'true'
  union all select 12, '빌드 수정이 권한 도우미(build_edit_check)를 부름 — 비회원 규칙은 그대로',
    (select (prosrc like '%build_edit_check(b, me)%')::text || ' / ' || (prosrc like '%is_guest(me)%')::text from fn where proname = 'edit_build'),
    'false / true', 'true / false'
  union all select 13, '알림 종류에 error_reported·error_report_handled (예전 종류도 그대로)',
    (select (def like '%error_reported%' and def like '%error_report_handled%')::text || ' / '
            || (def like '%post_created%' and def like '%matchup_created%' and def like '%inquiry_received%')::text from kindcheck),
    'false / true', 'true / true'
  union all select 14, '운영자 모드를 끄면 오류 신고 알림도 가림 (읽기 정책 · 모두 읽음)',
    (select (q like '%error_reported%')::text from pol) || ' / '
      || coalesce((select (prosrc like '%error_reported%')::text from fn where proname = 'mark_all_notifications_read'), '-'),
    'false / false', 'true / true'
  union all select 15, '푸시 묶음: 새 오류 신고 = staff_new, 처리 결과 = 안 보냄, 새 글 = staff_new (그대로)',
    coalesce(public.push_group('error_reported'), '안 보냄') || ' / ' || coalesce(public.push_group('error_report_handled'), '안 보냄')
      || ' / ' || coalesce(public.push_group('post_created'), '안 보냄'),
    '안 보냄 / 안 보냄 / staff_new', 'staff_new / 안 보냄 / staff_new'
  union all select 16, '처리 기록 종류: 되돌리기·신고 처리 / 대상: 빌드·오류 신고 (예전 delete·inquiry도 그대로)',
    (select (def like '%revert%' and def like '%resolve_report%' and def like '%dismiss_report''%')::text || ' / '
            || (def like '%''build''%' and def like '%wiki_report%')::text || ' / '
            || (def like '%''delete''%' and def like '%inquiry%')::text from logcheck),
    'false / false / true', 'true / true / true'
  union all select 17, '빌드 읽기 정책 "감독관이 숨긴 빌드 읽기" / 처리 대기 건수에 오류 신고',
    (select count(*)::text from pg_policies where schemaname = 'public' and tablename = 'builds' and policyname = 'builds: 감독관이 숨긴 빌드 읽기')
      || ' / ' || coalesce((select (prosrc like '%wiki_reports%')::text from fn where proname = 'admin_pending_counts'), '-'),
    '0 / false', '1 / true'
  union all select 18, '기존 알림 수 (실행 전후 같아야 함)', (select count(*)::text from public.notifications), '-', '실행 전과 같음'
  union all select 19, '빌드 수정 기록 수 / 기여자 수 (실행 전후 같아야 함)',
    (select count(*)::text from public.build_revisions) || ' / ' || (select count(*)::text from public.build_editors), '-', '실행 전과 같음'
  union all select 20, '설정값: 오류 신고 하루 상한 / 처리한 신고 보관 일수',
    coalesce((select value::text from public.xp_rules where key = 'error_report_daily_cap'), '없음') || ' / '
      || coalesce((select value::text from public.xp_rules where key = 'error_report_keep_days'), '없음'),
    '없음 / 없음', '10 / 365'
  union all select 21, 'pg_cron 일정 purge-wiki-reports (등록한 뒤 1)',
    case when to_regclass('cron.job') is null then 'pg_cron 없음' else
      (xpath('/row/c/text()', query_to_xml($q$select count(*) as c from cron.job where jobname = 'purge-wiki-reports'$q$, false, true, '')))[1]::text end,
    '0', '1 (등록 뒤)'
  union all select 22, '처리 전 오류 신고 수 (실행 직후 0, 그 뒤 신고가 들어올 때마다 늘어남)',
    case when to_regclass('public.wiki_reports') is null then '표 없음' else
      (xpath('/row/c/text()', query_to_xml($q$select count(*) as c from public.wiki_reports where status = 'open'$q$, false, true, '')))[1]::text end,
    '표 없음', '0 이상'
) x
order by ord;
