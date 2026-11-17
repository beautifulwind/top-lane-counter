-- =====================================================================
-- 060(빌드 댓글 정리) 실행 "전" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 새 화면(빌드 댓글 칸이 없는 화면)이 배포된 것을 확인한 뒤, SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다.
--   - 1~6번: [지금 값]이 [정상 값]과 모두 맞으면 060을 실행해도 된다. 하나라도 다르면 실행하지 말고 알려 주세요.
--     (3번이 0이 아니면 060의 안전장치가 어차피 멈춘다 - 그 사이 옛 화면에서 빌드 댓글이 생긴 것이다)
--   - 7~14번은 "적어 둘 값"이다. 060 실행 뒤 check_build_cleanup_after.sql의 같은 이름 줄과 비교한다(같아야 한다).
--     (그 사이 사이트에서 누가 댓글을 쓰거나 신고하면 달라질 수 있다 - 사람이 적은 시간에 이어서 실행해 주세요.)
-- =====================================================================
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '059 실행됨 (문서 댓글 답글 칸 parent_id)' as what,
    (select count(*)::text from information_schema.columns
      where table_schema = 'public' and table_name = 'doc_comments' and column_name = 'parent_id') as now_value,
    '1' as ok_value, '0이면 059부터 실행' as memo
  union all select 2, '빌드 댓글 표 build_comments가 아직 있음',
    coalesce(to_regclass('public.build_comments')::text, '없음'), 'build_comments', '없음이면 060을 이미 실행한 것 - 다시 실행하지 말 것'
  union all select 3, '빌드 댓글 관련 행 (댓글 / 신고 / 숨김 기록 / 처리 기록 / 알림 / 경험치 기록)',
    (select (select count(*) from public.build_comments)
            || ' / ' || (select count(*) from public.reports where build_comment_id is not null)
            || ' / ' || (select count(*) from public.hide_log where kind = 'build_comment')
            || ' / ' || (select count(*) from public.moderation_log where target_kind = 'build_comment')
            || ' / ' || (select count(*) from public.notifications
                          where kind in ('build_comment', 'build_comment_hidden', 'build_comment_restored', 'build_comment_deleted')
                             or (kind = 'comment_reply' and build_id is not null))
            || ' / ' || (select count(*) from public.xp_events where type = 'build_comment')),
    '0 / 0 / 0 / 0 / 0 / 0', '060 안전장치가 세는 것과 같다'
  union all select 4, '빌드 댓글 수 칸 builds.comment_count (칸 있음 / 0이 아닌 빌드 수)',
    (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'builds' and column_name = 'comment_count')
      || ' / ' || (select count(*) from public.builds where comment_count <> 0),
    '1 / 0', null
  union all select 5, '지금 함수 모양: dismiss_reports',
    (select string_agg(p.oid::regprocedure::text, ' / ') from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'dismiss_reports'),
    'dismiss_reports(bigint,bigint,text,bigint,bigint)', '060이 인자 4개로 되돌린다'
  union all select 6, '060이 지울 함수 13개가 있는 수',
    (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in (
        'create_build_comment', 'edit_build_comment', 'delete_my_build_comment', 'report_build_comment', 'hide_build_comment',
        'restore_build_comment', 'staff_delete_build_comment', 'notify_build_comment', 'build_comment_for_update',
        'require_moderate_open_build', 'build_label', 'build_comments_after', 'build_open')),
    '13', null
  union all select 7, '적어 둘 값: 문서 댓글 수 (전체 / 답글 / 지운 것 / 숨긴 것)',
    (select count(*) || ' / ' || count(*) filter (where parent_id is not null) || ' / ' || count(*) filter (where deleted_at is not null)
            || ' / ' || count(*) filter (where status = 'hidden') from public.doc_comments),
    '(이 값을 적어 둠)', '060 뒤 같아야 함'
  union all select 8, '적어 둘 값: 탑신병자 커뮤니티 댓글 수 (전체 / 답글 / 지운 것)',
    (select count(*) || ' / ' || count(*) filter (where parent_id is not null) || ' / ' || count(*) filter (where deleted_at is not null)
       from public.post_comments),
    '(이 값을 적어 둠)', '060 뒤 같아야 함'
  union all select 9, '적어 둘 값: 알림 수 (전체 / comment_reply / doc_comment)',
    (select count(*) || ' / ' || count(*) filter (where kind = 'comment_reply') || ' / ' || count(*) filter (where kind = 'doc_comment')
       from public.notifications),
    '(이 값을 적어 둠)', '060 뒤 같아야 함 (060은 알림을 지우지도 만들지도 않는다)'
  union all select 10, '적어 둘 값: 신고 수 (전체 / 처리 전)',
    (select count(*) || ' / ' || count(*) filter (where status = 'open') from public.reports), '(이 값을 적어 둠)', '060 뒤 같아야 함'
  union all select 11, '적어 둘 값: 숨김 기록 / 처리 기록 수',
    (select (select count(*) from public.hide_log) || ' / ' || (select count(*) from public.moderation_log)),
    '(이 값을 적어 둠)', '060 뒤 같아야 함'
  union all select 12, '적어 둘 값: 회원별 경험치·레벨 지문',
    coalesce((select md5(string_agg(id || ':' || xp || ':' || level, ',' order by id)) from public.profiles), '없음'),
    '(이 값을 적어 둠)', '060 뒤 같아야 함 (빌드 댓글 경험치는 0이었다)'
  union all select 13, '적어 둘 값: 칭호 지문',
    coalesce((select md5(string_agg(user_id || ':' || title_key, ',' order by user_id, title_key)) from public.user_titles), '없음'),
    '(이 값을 적어 둠)', '060 뒤 같아야 함'
  union all select 14, '적어 둘 값: 빌드 수 (전체 / 공개)',
    (select count(*) || ' / ' || count(*) filter (where status = 'approved') from public.builds),
    '(이 값을 적어 둠)', '060 뒤 같아야 함 (빌드는 건드리지 않는다)'
) rows
order by ord;
