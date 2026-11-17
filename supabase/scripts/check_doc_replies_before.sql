-- =====================================================================
-- 059(문서 댓글 답글) 실행 "전" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 059를 실행하기 전에 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~7번: [지금 값]이 [정상 값]과 모두 맞으면 059를 실행해도 된다. 하나라도 다르면 실행하지 말고 알려 주세요.
--   - 8~14번은 "적어 둘 값"이다. 059 실행 뒤 check_doc_replies_after.sql의 같은 이름 줄과 비교한다(같아야 한다).
--     (그 사이 사이트에서 누가 댓글을 쓰거나 신고하면 달라질 수 있다 - 사람이 적은 시간에 이어서 실행해 주세요.)
-- =====================================================================
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '058 실행됨 (빌드 댓글 표 build_comments가 있음)' as what,
    coalesce(to_regclass('public.build_comments')::text, '없음') as now_value,
    'build_comments' as ok_value, '없음이면 058부터 실행' as memo
  union all select 2, '문서 댓글 표에 답글 칸(parent_id)이 아직 없음',
    (select count(*)::text from information_schema.columns
      where table_schema = 'public' and table_name = 'doc_comments' and column_name = 'parent_id'),
    '0', '1이면 059를 이미 실행한 것 - 다시 실행하지 말 것'
  union all select 3, '지금 함수 모양: create_doc_comment',
    (select string_agg(p.oid::regprocedure::text, ' / ') from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'create_doc_comment'),
    'create_doc_comment(bigint,text)', '059가 이 모양을 지우고 인자 3개로 새로 만든다'
  union all select 4, '059가 만들 함수 block_guest_reply가 이미 있는 수',
    (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'block_guest_reply'), '0', null
  union all select 5, '문서 댓글 작성자 칸: 빈칸 불가 + 탈퇴하면 함께 삭제 (059가 빈칸 허용 + 비움으로 바꾼다)',
    (select c.is_nullable || ' / ' || r.delete_rule
       from information_schema.columns c
       join information_schema.referential_constraints r on r.constraint_schema = 'public' and r.constraint_name = 'doc_comments_author_id_fkey'
      where c.table_schema = 'public' and c.table_name = 'doc_comments' and c.column_name = 'author_id'),
    'NO / CASCADE', null
  union all select 6, '문서 댓글 본문 검사 doc_comments_body_check',
    (select pg_get_constraintdef(oid) from pg_constraint where conname = 'doc_comments_body_check'),
    'CHECK (((char_length(btrim(body)) >= 1) AND (char_length(btrim(body)) <= 1000)))', null
  union all select 7, '문서 댓글 답글 알림 (post_id·build_id가 빈 comment_reply) 수',
    (select count(*)::text from public.notifications where kind = 'comment_reply' and post_id is null and build_id is null), '0', null
  union all select 8, '적어 둘 값: 문서 댓글 수 (전체 / 지운 것 / 숨긴 것 / 비회원이 쓴 것)',
    (select count(*) || ' / ' || count(*) filter (where d.deleted_at is not null) || ' / ' || count(*) filter (where d.status = 'hidden')
            || ' / ' || count(*) filter (where p.is_guest)
       from public.doc_comments d left join public.profiles p on p.id = d.author_id),
    '(이 값을 적어 둠)', '059 뒤 같아야 함 (기존 댓글은 모두 최상위 댓글이 된다)'
  union all select 9, '적어 둘 값: 알림 수 (전체 / doc_comment / comment_reply)',
    (select count(*) || ' / ' || count(*) filter (where kind = 'doc_comment') || ' / ' || count(*) filter (where kind = 'comment_reply')
       from public.notifications),
    '(이 값을 적어 둠)', '059 뒤 같아야 함 (059는 알림을 만들지 않는다)'
  union all select 10, '적어 둘 값: 신고 수 (전체 / 처리 전 / 문서 댓글)',
    (select count(*) || ' / ' || count(*) filter (where status = 'open') || ' / ' || count(*) filter (where doc_comment_id is not null)
       from public.reports),
    '(이 값을 적어 둠)', '059 뒤 같아야 함'
  union all select 11, '적어 둘 값: 숨김 기록 / 처리 기록 수',
    (select (select count(*) from public.hide_log) || ' / ' || (select count(*) from public.moderation_log)),
    '(이 값을 적어 둠)', '059 뒤 같아야 함'
  union all select 12, '적어 둘 값: 회원별 경험치·레벨 지문',
    coalesce((select md5(string_agg(id || ':' || xp || ':' || level, ',' order by id)) from public.profiles), '없음'),
    '(이 값을 적어 둠)', '059 뒤 같아야 함 (경험치 규칙은 그대로 - 답글은 아직 없다)'
  union all select 13, '적어 둘 값: 칭호 지문',
    coalesce((select md5(string_agg(user_id || ':' || title_key, ',' order by user_id, title_key)) from public.user_titles), '없음'),
    '(이 값을 적어 둠)', '059 뒤 같아야 함'
  union all select 14, '적어 둘 값: 빌드 댓글 수 (058, 059는 건드리지 않음)',
    (select count(*)::text from public.build_comments), '(이 값을 적어 둠)', '059 뒤 같아야 함'
) rows
order by ord;
