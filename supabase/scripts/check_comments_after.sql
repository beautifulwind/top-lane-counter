-- =====================================================================
-- 058(댓글 답글 + 빌드 댓글) 실행 "뒤" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 058을 실행한 뒤 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~16번: [지금 값]이 [정상 값]과 모두 맞아야 한다. 하나라도 다르면 알려 주세요.
--   - 17~24번: 실행 전 check_comments_before.sql의 10~17번에 적어 둔 값과 같아야 한다.
--     (그 사이 사이트에서 누가 글·댓글을 쓰거나 신고하면 달라질 수 있다 - 그때는 알려 주세요.)
-- =====================================================================
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '빌드 댓글 표 build_comments가 있고 비어 있음 (줄 수)' as what,
    (select count(*)::text from public.build_comments) as now_value, '0' as ok_value, null as memo
  union all select 2, 'build_comments: RLS 켬 / 정책 수',
    (select relrowsecurity::text from pg_class where oid = 'public.build_comments'::regclass)
      || ' / ' || (select count(*) from pg_policies where schemaname = 'public' and tablename = 'build_comments'),
    'true / 1', '정책은 읽기 하나뿐 (쓰기는 함수로만)'
  union all select 3, 'build_comments 권한 (비로그인 / 로그인)',
    (select string_agg(privilege_type, ',' order by privilege_type) from information_schema.role_table_grants
      where table_schema = 'public' and table_name = 'build_comments' and grantee = 'anon')
      || ' / ' || (select string_agg(privilege_type, ',' order by privilege_type) from information_schema.role_table_grants
      where table_schema = 'public' and table_name = 'build_comments' and grantee = 'authenticated'),
    'SELECT / SELECT', '읽기만 (insert/update/delete 없음)'
  union all select 4, '댓글 표의 답글 칸 + 같은 글 안의 부모 (외래 키 / 삭제 규칙)',
    (select count(*)::text from information_schema.columns
      where table_schema = 'public' and table_name = 'post_comments' and column_name = 'parent_id')
      || ' / ' || coalesce((select r.delete_rule from information_schema.referential_constraints r
                             where r.constraint_schema = 'public' and r.constraint_name = 'post_comments_parent_fkey'), '없음'),
    '1 / CASCADE', null
  union all select 5, '댓글 작성자 칸: 빈칸 허용 + 탈퇴하면 비움',
    (select c.is_nullable || ' / ' || r.delete_rule
       from information_schema.columns c
       join information_schema.referential_constraints r on r.constraint_schema = 'public' and r.constraint_name = 'post_comments_author_id_fkey'
      where c.table_schema = 'public' and c.table_name = 'post_comments' and c.column_name = 'author_id'),
    'YES / SET NULL', '지우지 않은 댓글은 작성자가 꼭 있어야 함 (6번)'
  union all select 6, '검사: 작성자가 비면 지운 댓글만 (댓글 / 빌드 댓글)',
    (select count(*)::text from pg_constraint where conname in ('post_comments_author_or_deleted', 'build_comments_author_or_deleted')),
    '2', null
  union all select 7, '트리거 (비회원 막기 2 / 2단계 막기 2 / 빌드 댓글 수·경험치·숨김 기록 3)',
    (select count(*) filter (where tgname in ('post_comments_no_guest', 'build_comments_no_guest'))
            || ' / ' || count(*) filter (where tgname in ('post_comments_depth', 'build_comments_depth'))
            || ' / ' || count(*) filter (where tgname in ('build_comments_after', 'build_comments_rewards', 'build_comments_hide_log'))
       from pg_trigger where not tgisinternal and tgrelid in ('public.post_comments'::regclass, 'public.build_comments'::regclass)),
    '2 / 2 / 3', null
  union all select 8, '함수 모양: create_comment / dismiss_reports (옛 모양은 없어짐)',
    (select string_agg(p.oid::regprocedure::text, ' / ' order by p.proname)
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in ('create_comment', 'dismiss_reports')),
    'create_comment(bigint,text,text[],bigint) / dismiss_reports(bigint,bigint,text,bigint,bigint)', null
  union all select 9, '빌드 댓글 화면 함수 8개: 로그인한 사람만 부를 수 있음 (로그인 가능 수 / 비로그인 가능 수)',
    (select count(*) filter (where has_function_privilege('authenticated', p.oid, 'execute'))
            || ' / ' || count(*) filter (where has_function_privilege('anon', p.oid, 'execute'))
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in ('create_build_comment', 'edit_build_comment', 'delete_my_build_comment', 'report_build_comment',
                                                   'hide_build_comment', 'restore_build_comment', 'staff_delete_build_comment', 'create_comment')),
    '8 / 0', null
  union all select 10, '안쪽 도우미 5개: 아무도 직접 못 부름 (로그인 가능 수)',
    (select count(*) filter (where has_function_privilege('authenticated', p.oid, 'execute'))::text
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in ('notify_new_comment', 'notify_build_comment', 'build_comment_for_update', 'require_moderate_open_build', 'build_label')),
    '0', null
  union all select 11, '새 알림 종류 5개가 허용 목록에 있음',
    (select count(*)::text from unnest(array['build_comment', 'comment_reply', 'build_comment_hidden', 'build_comment_restored', 'build_comment_deleted']) k
      where pg_get_constraintdef((select oid from pg_constraint where conname = 'notifications_kind_check')) like '%''' || k || '''%'),
    '5', null
  union all select 12, '새 알림 종류는 휴대폰 알림 없음 (push_group이 비어 있는 수)',
    (select count(*)::text from unnest(array['build_comment', 'comment_reply', 'build_comment_hidden', 'build_comment_restored', 'build_comment_deleted']) k
      where public.push_group(k) is null),
    '5', '기존 댓글 알림(post_comment)과 같음'
  union all select 13, '신고 대상 검사 reports_one_target',
    (select pg_get_constraintdef(oid) from pg_constraint where conname = 'reports_one_target'),
    'CHECK ((num_nonnulls(post_id, comment_id, doc_comment_id, build_comment_id) = 1))', null
  union all select 14, '숨김 기록 / 처리 기록에 build_comment 허용',
    (select (pg_get_constraintdef((select oid from pg_constraint where conname = 'hide_log_kind_check')) like '%build_comment%')::text
       || ' / ' || (pg_get_constraintdef((select oid from pg_constraint where conname = 'moderation_log_target_kind_check')) like '%build_comment%')::text),
    'true / true', null
  union all select 15, '빌드 댓글 수 칸: 모든 빌드가 0',
    (select count(*) filter (where comment_count <> 0)::text from public.builds), '0', '0이 아닌 빌드 수'
  union all select 16, '새 함수가 search_path 고정 + 정의자 권한 (빠진 수)',
    (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in ('create_build_comment', 'edit_build_comment', 'delete_my_build_comment', 'report_build_comment',
              'hide_build_comment', 'restore_build_comment', 'staff_delete_build_comment', 'notify_new_comment', 'build_open', 'block_guest_comment', 'check_comment_depth')
        and not (p.prosecdef and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%')),
    '0', null
  union all select 17, '탑신병자 커뮤니티 댓글 수 (전체 / 지운 것 / 비회원이 쓴 것)',
    (select count(*) || ' / ' || count(*) filter (where c.deleted_at is not null) || ' / ' || count(*) filter (where p.is_guest)
       from public.post_comments c left join public.profiles p on p.id = c.author_id),
    '(실행 전 10번과 같음)', null
  union all select 18, '글별 댓글 수 지문 (posts.comment_count)',
    coalesce((select md5(string_agg(id || ':' || comment_count, ',' order by id)) from public.posts), '없음'),
    '(실행 전 11번과 같음)', null
  union all select 19, '빌드 수 (전체 / 공개)',
    (select count(*) || ' / ' || count(*) filter (where status = 'approved') from public.builds), '(실행 전 12번과 같음)', null
  union all select 20, '신고 수 (전체 / 처리 전)',
    (select count(*) || ' / ' || count(*) filter (where status = 'open') from public.reports), '(실행 전 13번과 같음)', null
  union all select 21, '알림 수',
    (select count(*)::text from public.notifications), '(실행 전 14번과 같음)', null
  union all select 22, '숨김 기록 / 처리 기록 수',
    (select (select count(*) from public.hide_log) || ' / ' || (select count(*) from public.moderation_log)), '(실행 전 15번과 같음)', null
  union all select 23, '회원별 경험치·레벨 지문',
    coalesce((select md5(string_agg(id || ':' || xp || ':' || level, ',' order by id)) from public.profiles), '없음'),
    '(실행 전 16번과 같음)', null
  union all select 24, '칭호 지문',
    coalesce((select md5(string_agg(user_id || ':' || title_key, ',' order by user_id, title_key)) from public.user_titles), '없음'),
    '(실행 전 17번과 같음)', null
) rows
order by ord;
