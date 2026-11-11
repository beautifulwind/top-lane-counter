-- =====================================================================
-- 040(글·댓글 삭제 방식 변경) 확인 조회 (읽기만 — 아무것도 바꾸지 않는다).
-- 040 실행 "전", 실행 "후", pg_cron 일정 등록 "뒤"에 한 번씩 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다.
-- [지금 값]이 [실행 전 정상]·[실행 후 정상]과 맞는지 본다.
--   - 1~4번: 기존 "삭제된 글" 껍데기(제목·본문이 비워진 글)와 그 아래 댓글. 040 뒤로 이 글과 댓글이 모두 안 보이게 된다.
--     실행 전 숫자를 적어 두고, 실행 후에도 같은지 본다 (행은 지우지 않고 안 보이게만 한다).
--   - 13번(경험치 합계)은 실행 전 값을 적어 두었다가 실행 후 값과 같은지 본다 (040은 경험치를 바꾸지 않는다).
--   - 14번은 따로 안내한 pg_cron 일정을 등록하면 true가 된다.
-- =====================================================================
with
-- 040 뒤에만 있는 칸
cols as (
  select count(*) as n from information_schema.columns
  where table_schema = 'public'
    and ((table_name = 'posts' and column_name in ('delete_kind', 'deleted_by', 'delete_note'))
      or (table_name in ('post_comments', 'doc_comments') and column_name in ('deleted_at', 'delete_kind', 'deleted_by', 'delete_note')))
),
done as (select (select n from cols) = 11 as ok),
shells as (
  select p.id, p.deleted_at from public.posts p
  where p.deleted_at is not null and p.title = '' and p.body = ''
),
under as (
  select c.id, c.author_id from public.post_comments c join shells s on s.id = c.post_id where c.status = 'visible'
),
-- 040 뒤에만 있는 칸을 읽는 조회는 글자로 된 조회(query_to_xml)로 부른다 (실행 전에는 칸이 없어 이름을 직접 쓰면 오류)
q (k, v) as (
  select 'nokind', case when (select ok from done) then (xpath('/row/v/text()', query_to_xml($x$
    select count(*)::text as v from public.posts where deleted_at is not null and delete_kind is null
  $x$, false, true, '')))[1]::text else '칸 없음' end
  union all
  select 'purge', case when (select ok from done) then (xpath('/row/v/text()', query_to_xml($x$
    select (select count(*) from public.posts where deleted_at < now() - make_interval(days => coalesce(public.xp_rule('deleted_writing_keep_days'), 365)))::text
        || ' · ' || (select count(*) from public.post_comments where deleted_at < now() - make_interval(days => coalesce(public.xp_rule('deleted_writing_keep_days'), 365)))::text
        || ' · ' || (select count(*) from public.doc_comments where deleted_at < now() - make_interval(days => coalesce(public.xp_rule('deleted_writing_keep_days'), 365)))::text as v
  $x$, false, true, '')))[1]::text else '칸 없음' end
)
select ord as "순서", item as "항목", now_value as "지금 값", before_ok as "실행 전 정상", after_ok as "실행 후 정상"
from (
  select 1 as ord, '기존 "삭제된 글" 껍데기 — 040 뒤 안 보이게 됨' as item,
    (select count(*)::text from shells) as now_value, '(적어 두기)' as before_ok, '실행 전과 같음' as after_ok
  union all select 2, '그 아래 댓글(숨기지 않은 것) — 글과 함께 안 보이게 됨',
    (select count(*)::text from under), '(적어 두기)', '실행 전과 같음'
  union all select 3, '그 댓글을 쓴 사람 수 (경험치는 그대로)',
    (select count(distinct author_id)::text from under), '(적어 두기)', '실행 전과 같음'
  union all select 4, '가장 오래된 껍데기를 지운 날 (1년 뒤부터 정리)',
    coalesce((select (min(deleted_at) at time zone 'Asia/Seoul')::date::text from shells), '없음'), '-', '-'
  union all select 5, '040 칸 (글 3개 + 댓글·문서 댓글 각 4개)',
    (select n::text from cols), '0', '11'
  union all select 6, '지운 글 중 지움 종류가 빈 것',
    (select v from q where k = 'nokind'), '칸 없음', '0'
  union all select 7, '새 함수 (운영진 삭제 3·운영자 조회·1년 정리·post_live)',
    (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in ('staff_delete_post', 'staff_delete_comment', 'staff_delete_doc_comment',
                                                   'admin_deleted_writings', 'purge_deleted_writings', 'post_live')),
    '0', '6'
  union all select 8, '읽기 정책이 지운 것을 빼는 표 (글·댓글·문서 댓글)',
    (select count(distinct tablename)::text from pg_policies
      where schemaname = 'public' and tablename in ('posts', 'post_comments', 'doc_comments') and cmd = 'SELECT' and qual like '%deleted_at IS NULL%'),
    '0', '3'
  union all select 9, '설정: 지운 글·댓글 보관 일수',
    coalesce((select value::text from public.xp_rules where key = 'deleted_writing_keep_days'), '없음'), '없음', '365'
  union all select 10, '알림 종류: 운영진 삭제 (post_deleted 등)',
    (select (pg_get_constraintdef(oid) like '%doc_comment_deleted%')::text from pg_constraint where conname = 'notifications_kind_check'),
    'false', 'true'
  union all select 11, '처리 기록 종류: delete',
    (select (pg_get_constraintdef(oid) like '%''delete''%')::text from pg_constraint where conname = 'moderation_log_action_check'),
    'false', 'true'
  union all select 12, '다음 정리에서 지울 것 (글 · 댓글 · 문서 댓글)',
    (select v from q where k = 'purge'), '칸 없음', '숫자 3개 (1번 껍데기 중 1년 지난 것 포함)'
  union all select 13, '경험치 합계 (모든 사람) — 실행 전 값과 같아야 함',
    (select coalesce(sum(xp), 0)::text from public.profiles), '(적어 두기)', '실행 전과 같음'
  union all select 14, 'pg_cron 일정: 지운 글·댓글 1년 정리 (매일 4:50)',
    case when to_regclass('cron.job') is null then 'pg_cron 없음' else
      (xpath('/row/v/text()', query_to_xml($x$select (count(*) > 0)::text as v from cron.job where jobname = 'purge-deleted-writings'$x$, false, true, '')))[1]::text end,
    'false', 'true (일정 등록 뒤)'
) rows
order by ord;
