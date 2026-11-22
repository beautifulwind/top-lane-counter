-- =====================================================================
-- 066(빌드 저장·북마크) 실행 "뒤" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 066을 실행한 뒤 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~7번: [지금 값]이 [정상 값]과 모두 맞아야 한다. 하나라도 다르면 알려 주세요. (웹 push는 그다음)
--   - 8~11번: 실행 전 check_bookmarks_before.sql의 5~8번에 적어 둔 값과 같아야 한다 (066은 기존 데이터를 바꾸지 않는다).
-- =====================================================================
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '새 표 build_bookmarks (칸)' as what,
    coalesce((select string_agg(column_name || ':' || data_type, ', ' order by ordinal_position) from information_schema.columns
               where table_schema = 'public' and table_name = 'build_bookmarks'), '없음') as now_value,
    'user_id:uuid, build_id:bigint, created_at:timestamp with time zone' as ok_value, null as memo
  union all select 2, '중복 방지 (기본 키) / 탈퇴·빌드 삭제 때 함께 지움 (cascade 2개)',
    coalesce((select pg_get_constraintdef(oid) from pg_constraint where conrelid = to_regclass('public.build_bookmarks') and contype = 'p'), '없음')
      || ' / ' || (select count(*) from pg_constraint where conrelid = to_regclass('public.build_bookmarks') and contype = 'f' and confdeltype = 'c'),
    'PRIMARY KEY (user_id, build_id) / 2', null
  union all select 3, 'RLS 켬 / 정책 (본인 읽기 하나뿐)',
    coalesce((select relrowsecurity::text from pg_class where oid = to_regclass('public.build_bookmarks')), '없음')
      || ' / ' || coalesce((select string_agg(polname || ':' || polcmd::text, ', ') from pg_policy where polrelid = to_regclass('public.build_bookmarks')), '없음'),
    'true / build_bookmarks: 본인 읽기:r', null
  union all select 4, '표 권한 (로그인: 읽기만 / 비로그인: 없음)',
    case when to_regclass('public.build_bookmarks') is null then '없음' else
      (has_table_privilege('authenticated', 'public.build_bookmarks', 'select'))::text || ' '
      || (has_table_privilege('authenticated', 'public.build_bookmarks', 'insert') or has_table_privilege('authenticated', 'public.build_bookmarks', 'update')
          or has_table_privilege('authenticated', 'public.build_bookmarks', 'delete'))::text
      || ' / ' || (has_table_privilege('anon', 'public.build_bookmarks', 'select') or has_table_privilege('anon', 'public.build_bookmarks', 'insert'))::text end,
    'true false / false', '로그인은 읽기 true, 쓰기 false여야 함'
  union all select 5, '새 함수 (4개)',
    (select string_agg(p.oid::regprocedure::text, ' / ' order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in ('save_build', 'unsave_build', 'my_saved_builds', 'save_build_limit')),
    'my_saved_builds() / save_build(bigint) / save_build_limit() / unsave_build(bigint)', null
  union all select 6, '함수 실행 권한 (로그인: 셋 다 / 비로그인: 하나라도)',
    case when to_regprocedure('public.save_build(bigint)') is null then '없음' else
      (has_function_privilege('authenticated', 'public.save_build(bigint)', 'execute')
        and has_function_privilege('authenticated', 'public.unsave_build(bigint)', 'execute')
        and has_function_privilege('authenticated', 'public.my_saved_builds()', 'execute'))::text
      || ' / ' || (has_function_privilege('anon', 'public.save_build(bigint)', 'execute')
        or has_function_privilege('anon', 'public.unsave_build(bigint)', 'execute')
        or has_function_privilege('anon', 'public.my_saved_builds()', 'execute'))::text end,
    'true / false', null
  union all select 7, '저장 한도 / 지금 저장 줄 수',
    case when to_regprocedure('public.save_build_limit()') is null then '없음' else
      public.save_build_limit() || ' / ' || (select count(*) from public.build_bookmarks) end,
    '500 / 0', '실행 직후에는 아직 아무도 저장하지 않았으므로 0'
  union all select 8, '적어 둘 값: 빌드 (줄 수 / 가장 큰 id / 추천 수 합계 / 비추천 수 합계 / 내용 지문)',
    (select count(*) || ' / ' || coalesce(max(id), 0) || ' / ' || coalesce(sum(up_count), 0) || ' / ' || coalesce(sum(down_count), 0)
       || ' / ' || md5(coalesce(string_agg(b::text, '|' order by b.id), '')) from public.builds b),
    '(이 값을 적어 둠)', '실행 전 값과 같아야 함'
  union all select 9, '적어 둘 값: 빌드 추천·비추천 (줄 수 / 추천 줄 / 비추천 줄 / 내용 지문)',
    (select count(*) || ' / ' || count(*) filter (where value = 1) || ' / ' || count(*) filter (where value = -1)
       || ' / ' || md5(coalesce(string_agg(v::text, '|' order by v.build_id, v.user_id::text), '')) from public.build_votes v),
    '(이 값을 적어 둠)', '실행 전 값과 같아야 함'
  union all select 10, '적어 둘 값: 빌드 수정 기록 (줄 수 / 가장 큰 id / 내용 지문)',
    (select count(*) || ' / ' || coalesce(max(id), 0) || ' / ' || md5(coalesce(string_agg(r::text, '|' order by r.id), '')) from public.build_revisions r),
    '(이 값을 적어 둠)', '실행 전 값과 같아야 함'
  union all select 11, '적어 둘 값: 알림 (줄 수 / 가장 큰 id / 내용 지문 - 읽음 표시는 빼고)',
    (select count(*) || ' / ' || coalesce(max(id), 0) || ' / '
       || md5(coalesce(string_agg(concat_ws(',', n.id, n.user_id, n.kind, n.message, n.created_at, n.proposal_id, n.build_id, n.post_id, n.counter_id), '|' order by n.id), ''))
       from public.notifications n),
    '(이 값을 적어 둠)', '실행 전 값과 같아야 함'
) x
order by ord;
