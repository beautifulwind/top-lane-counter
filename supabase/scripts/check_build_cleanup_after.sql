-- =====================================================================
-- 060(빌드 댓글 정리) 실행 "뒤" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 060을 실행한 뒤 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~10번: [지금 값]이 [정상 값]과 모두 맞아야 한다. 하나라도 다르면 알려 주세요.
--   - 11~18번: 실행 전 check_build_cleanup_before.sql의 7~14번에 적어 둔 값과 같아야 한다.
-- =====================================================================
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '빌드 댓글 표 build_comments가 없음' as what,
    coalesce(to_regclass('public.build_comments')::text, '없음') as now_value, '없음' as ok_value, null as memo
  union all select 2, '없어진 칸 (builds.comment_count / reports.build_comment_id)',
    (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'builds' and column_name = 'comment_count')
      || ' / ' || (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'reports' and column_name = 'build_comment_id'),
    '0 / 0', null
  union all select 3, '신고 대상 검사 reports_one_target',
    (select pg_get_constraintdef(oid) from pg_constraint where conname = 'reports_one_target'),
    'CHECK ((num_nonnulls(post_id, comment_id, doc_comment_id) = 1))', null
  union all select 4, '지운 함수 13개가 남은 수',
    (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in (
        'create_build_comment', 'edit_build_comment', 'delete_my_build_comment', 'report_build_comment', 'hide_build_comment',
        'restore_build_comment', 'staff_delete_build_comment', 'notify_build_comment', 'build_comment_for_update',
        'require_moderate_open_build', 'build_label', 'build_comments_after', 'build_open')),
    '0', null
  union all select 5, '함수 모양: dismiss_reports (로그인 / 비로그인)',
    (select string_agg(p.oid::regprocedure::text, ' / ') from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'dismiss_reports')
      || ' (' || has_function_privilege('authenticated', 'public.dismiss_reports(bigint, bigint, text, bigint)', 'execute')::text
      || ' / ' || has_function_privilege('anon', 'public.dismiss_reports(bigint, bigint, text, bigint)', 'execute')::text || ')',
    'dismiss_reports(bigint,bigint,text,bigint) (true / false)', null
  union all select 6, '함수 본문에 빌드 댓글이 남은 수',
    (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and (p.prosrc ilike '%build_comment%' or p.prosrc ilike '%build_open%' or p.prosrc ilike '%build_label%')),
    '0', null
  union all select 7, '종류 목록에 build_comment (숨김 기록 / 처리 기록)',
    (select (pg_get_constraintdef((select oid from pg_constraint where conname = 'hide_log_kind_check')) like '%build_comment%')::text
       || ' / ' || (pg_get_constraintdef((select oid from pg_constraint where conname = 'moderation_log_target_kind_check')) like '%build_comment%')::text),
    'false / false', null
  union all select 8, '알림 종류: 빌드 댓글 4종이 남은 수 / 답글 알림 comment_reply 허용',
    (select count(*) from unnest(array['build_comment', 'build_comment_hidden', 'build_comment_restored', 'build_comment_deleted']) k
      where pg_get_constraintdef((select oid from pg_constraint where conname = 'notifications_kind_check')) like '%''' || k || '''%')
      || ' / ' || (pg_get_constraintdef((select oid from pg_constraint where conname = 'notifications_kind_check')) like '%''comment_reply''%')::text,
    '0 / true', null
  union all select 9, '댓글 트리거 그대로 (문서: 2단계·비회원 답글·경험치·숨김 기록 / 커뮤니티: 비회원·2단계)',
    (select count(*) filter (where tgrelid = 'public.doc_comments'::regclass and tgname in
              ('doc_comments_depth', 'doc_comments_no_guest_reply', 'doc_comments_rewards', 'doc_comments_hide_log'))
            || ' / ' || count(*) filter (where tgrelid = 'public.post_comments'::regclass and tgname in ('post_comments_no_guest', 'post_comments_depth'))
       from pg_trigger where not tgisinternal),
    '4 / 2', null
  union all select 10, '바꾼 함수가 search_path 고정 + 정의자 권한 (빠진 수)',
    (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in ('dismiss_reports', 'begin_edit', 'open_reports_for_moderator', 'notify_staff_new_report',
              'xp_should_have', 'xp_reason', 'has_visible_writing', 'guest_has_records', 'admin_member_info', 'admin_deleted_writings',
              'admin_member_detail_unchecked', 'log_hide', 'check_comment_depth', 'notify_new_comment', 'board_on_profile_delete', 'purge_deleted_writings')
        and not (p.prosecdef and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%')),
    '0', null
  union all select 11, '문서 댓글 수 (전체 / 답글 / 지운 것 / 숨긴 것)',
    (select count(*) || ' / ' || count(*) filter (where parent_id is not null) || ' / ' || count(*) filter (where deleted_at is not null)
            || ' / ' || count(*) filter (where status = 'hidden') from public.doc_comments),
    '(실행 전 7번과 같음)', null
  union all select 12, '탑신병자 커뮤니티 댓글 수 (전체 / 답글 / 지운 것)',
    (select count(*) || ' / ' || count(*) filter (where parent_id is not null) || ' / ' || count(*) filter (where deleted_at is not null)
       from public.post_comments),
    '(실행 전 8번과 같음)', null
  union all select 13, '알림 수 (전체 / comment_reply / doc_comment)',
    (select count(*) || ' / ' || count(*) filter (where kind = 'comment_reply') || ' / ' || count(*) filter (where kind = 'doc_comment')
       from public.notifications),
    '(실행 전 9번과 같음)', null
  union all select 14, '신고 수 (전체 / 처리 전)',
    (select count(*) || ' / ' || count(*) filter (where status = 'open') from public.reports), '(실행 전 10번과 같음)', null
  union all select 15, '숨김 기록 / 처리 기록 수',
    (select (select count(*) from public.hide_log) || ' / ' || (select count(*) from public.moderation_log)), '(실행 전 11번과 같음)', null
  union all select 16, '회원별 경험치·레벨 지문',
    coalesce((select md5(string_agg(id || ':' || xp || ':' || level, ',' order by id)) from public.profiles), '없음'),
    '(실행 전 12번과 같음)', null
  union all select 17, '칭호 지문',
    coalesce((select md5(string_agg(user_id || ':' || title_key, ',' order by user_id, title_key)) from public.user_titles), '없음'),
    '(실행 전 13번과 같음)', null
  union all select 18, '빌드 수 (전체 / 공개)',
    (select count(*) || ' / ' || count(*) filter (where status = 'approved') from public.builds), '(실행 전 14번과 같음)', null
) rows
order by ord;
