-- =====================================================================
-- 058(댓글 답글 + 빌드 댓글) 실행 "전" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 058을 실행하기 전에 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~9번: [지금 값]이 [정상 값]과 모두 맞으면 058을 실행해도 된다. 하나라도 다르면 실행하지 말고 알려 주세요.
--   - 10~17번은 "적어 둘 값"이다. 058 실행 뒤 check_comments_after.sql의 같은 이름 줄과 비교한다(같아야 한다).
--     (그 사이 사이트에서 누가 글·댓글을 쓰거나 신고하면 달라질 수 있다 - 사람이 적은 시간에 이어서 실행해 주세요.)
-- =====================================================================
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '057 실행됨 (xp_rules 메모에 "탑신병자 커뮤니티"가 든 줄 수)' as what,
    (select count(*)::text from public.xp_rules where note like '%탑신병자 커뮤니티%') as now_value,
    '11 이상' as ok_value, '0이면 057부터 실행' as memo
  union all select 2, '빌드 댓글 표 build_comments가 아직 없음',
    coalesce(to_regclass('public.build_comments')::text, '없음'), '없음', '있으면 058을 이미 실행한 것 - 다시 실행하지 말 것'
  union all select 3, '댓글 표에 답글 칸(parent_id)이 아직 없음',
    (select count(*)::text from information_schema.columns
      where table_schema = 'public' and table_name = 'post_comments' and column_name = 'parent_id'), '0', null
  union all select 4, '빌드 표에 댓글 수 칸(comment_count)이 아직 없음',
    (select count(*)::text from information_schema.columns
      where table_schema = 'public' and table_name = 'builds' and column_name = 'comment_count'), '0', null
  union all select 5, '지금 함수 모양: create_comment / dismiss_reports',
    (select string_agg(p.oid::regprocedure::text, ' / ' order by p.proname)
       from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in ('create_comment', 'dismiss_reports')),
    'create_comment(bigint,text,text[]) / dismiss_reports(bigint,bigint,text,bigint)', '다르면 알려 주세요 (058이 이 모양을 지우고 새로 만든다)'
  union all select 6, '058이 만들 함수 이름이 이미 있는 수',
    (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in (
        'build_open', 'build_comments_after', 'block_guest_comment', 'check_comment_depth', 'build_label', 'require_moderate_open_build',
        'build_comment_for_update', 'notify_new_comment', 'notify_build_comment', 'create_build_comment', 'edit_build_comment',
        'delete_my_build_comment', 'report_build_comment', 'hide_build_comment', 'restore_build_comment', 'staff_delete_build_comment')),
    '0', null
  union all select 7, '댓글 작성자 칸: 빈칸 불가 + 탈퇴하면 함께 삭제 (058이 빈칸 허용 + 비움으로 바꾼다)',
    (select c.is_nullable || ' / ' || r.delete_rule
       from information_schema.columns c
       join information_schema.referential_constraints r on r.constraint_schema = 'public' and r.constraint_name = 'post_comments_author_id_fkey'
      where c.table_schema = 'public' and c.table_name = 'post_comments' and c.column_name = 'author_id'),
    'NO / CASCADE', null
  union all select 8, '작성자가 빈 댓글 수 (058 뒤 생길 수 있는 탈퇴 껍데기)',
    (select count(*)::text from public.post_comments where author_id is null), '0', null
  union all select 9, '신고 대상 검사 reports_one_target',
    (select pg_get_constraintdef(oid) from pg_constraint where conname = 'reports_one_target'),
    'CHECK ((num_nonnulls(post_id, comment_id, doc_comment_id) = 1))', null
  union all select 10, '적어 둘 값: 탑신병자 커뮤니티 댓글 수 (전체 / 지운 것 / 비회원이 쓴 것)',
    (select count(*) || ' / ' || count(*) filter (where c.deleted_at is not null) || ' / ' || count(*) filter (where p.is_guest)
       from public.post_comments c left join public.profiles p on p.id = c.author_id),
    '(이 값을 적어 둠)', '058 뒤 같아야 함 (비회원이 이미 쓴 댓글은 그대로 남는다)'
  union all select 11, '적어 둘 값: 글별 댓글 수 지문 (posts.comment_count)',
    coalesce((select md5(string_agg(id || ':' || comment_count, ',' order by id)) from public.posts), '없음'),
    '(이 값을 적어 둠)', '058 뒤 같아야 함'
  union all select 12, '적어 둘 값: 빌드 수 (전체 / 공개)',
    (select count(*) || ' / ' || count(*) filter (where status = 'approved') from public.builds),
    '(이 값을 적어 둠)', '058 뒤 같아야 함'
  union all select 13, '적어 둘 값: 신고 수 (전체 / 처리 전)',
    (select count(*) || ' / ' || count(*) filter (where status = 'open') from public.reports),
    '(이 값을 적어 둠)', '058 뒤 같아야 함'
  union all select 14, '적어 둘 값: 알림 수',
    (select count(*)::text from public.notifications), '(이 값을 적어 둠)', '058 뒤 같아야 함 (058은 알림을 만들지 않는다)'
  union all select 15, '적어 둘 값: 숨김 기록 / 처리 기록 수',
    (select (select count(*) from public.hide_log) || ' / ' || (select count(*) from public.moderation_log)),
    '(이 값을 적어 둠)', '058 뒤 같아야 함'
  union all select 16, '적어 둘 값: 회원별 경험치·레벨 지문',
    coalesce((select md5(string_agg(id || ':' || xp || ':' || level, ',' order by id)) from public.profiles), '없음'),
    '(이 값을 적어 둠)', '058 뒤 같아야 함 (경험치 규칙은 빌드 댓글을 더할 뿐 - 아직 빌드 댓글이 없다)'
  union all select 17, '적어 둘 값: 칭호 지문',
    coalesce((select md5(string_agg(user_id || ':' || title_key, ',' order by user_id, title_key)) from public.user_titles), '없음'),
    '(이 값을 적어 둠)', '058 뒤 같아야 함'
) rows
order by ord;
