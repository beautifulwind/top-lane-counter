-- =====================================================================
-- 감독관(030) 확인 조회 (읽기만 — 아무것도 바꾸지 않는다). 030 실행 "전"과 "후"에 한 번씩 돌려 본다.
-- SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다. [지금 값]이 [실행 전 정상]·[실행 후 정상]과 맞는지 본다.
-- =====================================================================
with c as (
  select
    exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'nickname_reserved') as has_029,
    to_regclass('public.moderation_log') is not null as has_030,
    (select pg_get_constraintdef(oid) like '%moderator%' from pg_constraint where conname = 'profiles_role_check' and conrelid = 'public.profiles'::regclass) as role_ok,
    (select pg_get_constraintdef(oid) like '%moderator_granted%' from pg_constraint where conname = 'notifications_kind_check' and conrelid = 'public.notifications'::regclass) as kind_ok
)
select ord as "순서", what as "항목", now_value as "지금 값", before_ok as "실행 전 정상", after_ok as "실행 후 정상"
from (
  select 1 as ord, '029 실행됨 (030의 전제)' as what, c.has_029::text as now_value, 'true' as before_ok, 'true' as after_ok from c
  union all select 2, 'moderation_log 표', c.has_030::text, 'false', 'true' from c
  union all select 3, 'role에 moderator 허용', c.role_ok::text, 'false', 'true' from c
  union all select 4, '알림 종류에 지정·해제', c.kind_ok::text, 'false', 'true' from c
  union all select 5, '운영자 수 (1명이어야 함)', (select count(*)::text from public.profiles where role = 'admin'), '1', '1'
  union all select 6, '감독관 수', (select count(*)::text from public.profiles where role = 'moderator'), '0', '0 (지정 전)'
  union all select 7, '일반 회원 수 (실행 전후 같아야 함)', (select count(*)::text from public.profiles where role = 'user'), '-', '실행 전과 같음'
  union all select 8, '새 함수 수 (is_moderator 등 10개 + set_moderator·open_reports_for_moderator)',
    (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in (
      'is_moderator', 'is_staff', 'require_staff', 'moderatable_author', 'can_see_hidden', 'require_moderate_target',
      'require_moderate_doc_counter', 'require_restore_allowed', 'require_review_allowed', 'log_moderation',
      'set_moderator', 'open_reports_for_moderator')), '0', '12'
  union all select 9, '일반 사용자가 못 부르는 내부 함수 중 열린 것',
    (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in (
      'require_staff', 'require_moderate_target', 'require_moderate_doc_counter', 'require_restore_allowed', 'require_review_allowed', 'log_moderation')
      and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))), '0', '0'
  union all select 10, '비로그인이 set_moderator를 부를 수 있나',
    coalesce((select has_function_privilege('anon', p.oid, 'execute')::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'set_moderator'), '함수 없음'), '함수 없음', 'false'
  union all select 11, 'moderation_log에 일반 사용자 쓰기 권한',
    case when c.has_030 then (has_table_privilege('authenticated', 'public.moderation_log', 'insert') or has_table_privilege('authenticated', 'public.moderation_log', 'update') or has_table_privilege('authenticated', 'public.moderation_log', 'delete'))::text else '표 없음' end, '표 없음', 'false' from c
  union all select 12, '감독관에게 넓힌 읽기 정책 수',
    (select count(*)::text from pg_policies where schemaname = 'public' and policyname in (
      'posts: 읽기 (숨긴 글은 운영진만)', 'post_comments: 읽기 (숨긴 것은 운영진만)', 'doc_comments: 읽기 (숨긴 것은 운영진만)', 'edit_proposals: 본인·운영진 읽기')), '0', '4'
  union all select 13, '신고 표는 운영자만 (정책에 is_admin)',
    (select (qual like '%is_admin%')::text from pg_policies where schemaname = 'public' and tablename = 'reports' and cmd = 'SELECT'), 'true', 'true'
  union all select 14, '자유게시판 목록에 role 포함',
    (select (pg_get_functiondef('public.board_page'::regproc) like '%''role'', a.role%')::text), 'false', 'true'
) x
order by ord;
