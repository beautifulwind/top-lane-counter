-- =====================================================================
-- 059(문서 댓글 답글) 실행 "뒤" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 059를 실행한 뒤 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~12번: [지금 값]이 [정상 값]과 모두 맞아야 한다. 하나라도 다르면 알려 주세요.
--   - 13~19번: 실행 전 check_doc_replies_before.sql의 8~14번에 적어 둔 값과 같아야 한다.
--     (그 사이 사이트에서 누가 댓글을 쓰거나 신고하면 달라질 수 있다 - 그때는 알려 주세요.)
-- =====================================================================
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '문서 댓글 표의 답글 칸 + 같은 문서 안의 부모 (외래 키 / 삭제 규칙)' as what,
    (select count(*)::text from information_schema.columns
      where table_schema = 'public' and table_name = 'doc_comments' and column_name = 'parent_id')
      || ' / ' || coalesce((select r.delete_rule from information_schema.referential_constraints r
                             where r.constraint_schema = 'public' and r.constraint_name = 'doc_comments_parent_fkey'), '없음') as now_value,
    '1 / CASCADE' as ok_value, null as memo
  union all select 2, '문서 댓글 작성자 칸: 빈칸 허용 + 탈퇴하면 비움',
    (select c.is_nullable || ' / ' || r.delete_rule
       from information_schema.columns c
       join information_schema.referential_constraints r on r.constraint_schema = 'public' and r.constraint_name = 'doc_comments_author_id_fkey'
      where c.table_schema = 'public' and c.table_name = 'doc_comments' and c.column_name = 'author_id'),
    'YES / SET NULL', '지우지 않은 댓글은 작성자가 꼭 있어야 함 (3번)'
  union all select 3, '검사: 작성자가 비면 지운 댓글만 / 같은 문서 안 (counter_id, id) 유일',
    (select count(*)::text from pg_constraint where conname in ('doc_comments_author_or_deleted', 'doc_comments_counter_id_id_key')),
    '2', null
  union all select 4, '문서 댓글 본문 검사 (지운 것은 빈 본문 허용 - 탈퇴 껍데기)',
    (select pg_get_constraintdef(oid) from pg_constraint where conname = 'doc_comments_body_check'),
    'CHECK (((deleted_at IS NOT NULL) OR ((char_length(btrim(body)) >= 1) AND (char_length(btrim(body)) <= 1000))))', null
  union all select 5, '트리거 (2단계 막기 / 비회원 답글 막기 / 기존 경험치·숨김 기록)',
    (select count(*) filter (where tgname = 'doc_comments_depth')
            || ' / ' || count(*) filter (where tgname = 'doc_comments_no_guest_reply')
            || ' / ' || count(*) filter (where tgname in ('doc_comments_rewards', 'doc_comments_hide_log'))
       from pg_trigger where not tgisinternal and tgrelid = 'public.doc_comments'::regclass),
    '1 / 1 / 2', null
  union all select 6, '함수 모양: create_doc_comment (옛 모양은 없어짐)',
    (select string_agg(p.oid::regprocedure::text, ' / ') from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname = 'create_doc_comment'),
    'create_doc_comment(bigint,text,bigint)', null
  union all select 7, 'create_doc_comment: 로그인한 사람만 (로그인 / 비로그인)',
    (select has_function_privilege('authenticated', 'public.create_doc_comment(bigint, text, bigint)', 'execute')::text
       || ' / ' || has_function_privilege('anon', 'public.create_doc_comment(bigint, text, bigint)', 'execute')::text),
    'true / false', '비회원(익명 로그인)은 로그인한 사람 - 최상위 댓글은 쓰고 답글은 함수·트리거가 막는다'
  union all select 8, '안쪽 함수 block_guest_reply: 아무도 직접 못 부름 (로그인 / 비로그인)',
    (select has_function_privilege('authenticated', 'public.block_guest_reply()', 'execute')::text
       || ' / ' || has_function_privilege('anon', 'public.block_guest_reply()', 'execute')::text),
    'false / false', null
  union all select 9, '바꾼 함수가 search_path 고정 + 정의자 권한 (빠진 수)',
    (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in ('create_doc_comment', 'block_guest_reply', 'check_comment_depth', 'notify_new_comment',
                                                   'board_on_profile_delete', 'purge_deleted_writings')
        and not (p.prosecdef and coalesce(array_to_string(p.proconfig, ','), '') like '%search_path=%')),
    '0', null
  union all select 10, '문서 댓글 답글 수 / 작성자가 빈 문서 댓글 수',
    (select count(*) filter (where parent_id is not null) || ' / ' || count(*) filter (where author_id is null) from public.doc_comments),
    '0 / 0', '059 직후 (화면 push 전)'
  union all select 11, '문서 댓글 답글 알림 (post_id·build_id가 빈 comment_reply) 수',
    (select count(*)::text from public.notifications where kind = 'comment_reply' and post_id is null and build_id is null), '0', null
  union all select 12, '경험치 설정 메모에 "답글" (comment / comment_daily_cap)',
    (select count(*)::text from public.xp_rules where key in ('comment', 'comment_daily_cap') and note like '%문서 댓글·답글%'),
    '2', '값(+1, 하루 10)은 그대로'
  union all select 13, '문서 댓글 수 (전체 / 지운 것 / 숨긴 것 / 비회원이 쓴 것)',
    (select count(*) || ' / ' || count(*) filter (where d.deleted_at is not null) || ' / ' || count(*) filter (where d.status = 'hidden')
            || ' / ' || count(*) filter (where p.is_guest)
       from public.doc_comments d left join public.profiles p on p.id = d.author_id),
    '(실행 전 8번과 같음)', null
  union all select 14, '알림 수 (전체 / doc_comment / comment_reply)',
    (select count(*) || ' / ' || count(*) filter (where kind = 'doc_comment') || ' / ' || count(*) filter (where kind = 'comment_reply')
       from public.notifications),
    '(실행 전 9번과 같음)', null
  union all select 15, '신고 수 (전체 / 처리 전 / 문서 댓글)',
    (select count(*) || ' / ' || count(*) filter (where status = 'open') || ' / ' || count(*) filter (where doc_comment_id is not null)
       from public.reports),
    '(실행 전 10번과 같음)', null
  union all select 16, '숨김 기록 / 처리 기록 수',
    (select (select count(*) from public.hide_log) || ' / ' || (select count(*) from public.moderation_log)), '(실행 전 11번과 같음)', null
  union all select 17, '회원별 경험치·레벨 지문',
    coalesce((select md5(string_agg(id || ':' || xp || ':' || level, ',' order by id)) from public.profiles), '없음'),
    '(실행 전 12번과 같음)', null
  union all select 18, '칭호 지문',
    coalesce((select md5(string_agg(user_id || ':' || title_key, ',' order by user_id, title_key)) from public.user_titles), '없음'),
    '(실행 전 13번과 같음)', null
  union all select 19, '빌드 댓글 수 (058, 059는 건드리지 않음)',
    (select count(*)::text from public.build_comments), '(실행 전 14번과 같음)', null
) rows
order by ord;
