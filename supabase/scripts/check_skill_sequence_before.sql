-- =====================================================================
-- 065(빌드 스킬 순서 상세) 실행 "전" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 065를 실행하기 전에 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~6번: [지금 값]이 [정상 값]과 모두 맞으면 065를 실행해도 된다. 하나라도 다르면 실행하지 말고 알려 주세요.
--   - 7~11번은 "적어 둘 값"이다. 065 실행 뒤 check_skill_sequence_after.sql의 같은 이름 줄과 비교한다(같아야 한다).
--     (그 사이 사이트에서 누가 빌드 등록·수정·추천을 하면 달라질 수 있다 - 사람이 적은 시간에 이어서 실행해 주세요.)
-- =====================================================================
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '064 실행됨 (장인 신청 사진 칸 influencer_applications.photo_path 있음)' as what,
    (select count(*)::text from information_schema.columns where table_schema = 'public' and table_name = 'influencer_applications'
      and column_name = 'photo_path') as now_value,
    '1' as ok_value, '0이면 064부터 실행' as memo
  union all select 2, '빌드 스킬 순서 칸 builds.skill_sequence가 아직 없음 (옛 이름 skill_order도 없음)',
    (select count(*)::text from information_schema.columns where table_schema = 'public' and table_name = 'builds'
      and column_name in ('skill_sequence', 'skill_order')),
    '0', '0이 아니면 065를 이미 실행한 것 - 알려 주세요'
  union all select 3, '065가 만들 함수가 이미 있는 수',
    (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in ('skill_sequence_mode', 'skill_sequence_problem', 'check_skill_sequence')),
    '0', null
  union all select 4, '065가 바꿀 함수 모양',
    (select string_agg(p.oid::regprocedure::text, ' / ' order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in ('clean_wiki_build', 'edit_build', 'revert_build_unchecked', 'wiki_insert_build', 'wiki_snapshot')),
    'clean_wiki_build(jsonb) / edit_build(bigint,integer,jsonb) / revert_build_unchecked(bigint,bigint,integer,text) / wiki_insert_build(bigint,uuid,jsonb) / wiki_snapshot(builds)',
    null
  union all select 5, '바꿀 함수가 아직 스킬 순서를 모름 (스냅샷 / 빌드 검사 / 수정 / 되돌리기 / 넣기)',
    (select (p.prosrc like '%skill_sequence%')::text from pg_proc p where p.oid = 'public.wiki_snapshot(public.builds)'::regprocedure)
      || ' / ' || (select (p.prosrc like '%skill_sequence%')::text from pg_proc p where p.oid = 'public.clean_wiki_build(jsonb)'::regprocedure)
      || ' / ' || (select (p.prosrc like '%skill_sequence%')::text from pg_proc p where p.oid = 'public.edit_build(bigint,integer,jsonb)'::regprocedure)
      || ' / ' || (select (p.prosrc like '%skill_sequence%')::text from pg_proc p
                    where p.oid = 'public.revert_build_unchecked(bigint,bigint,integer,text)'::regprocedure)
      || ' / ' || (select (p.prosrc like '%skill_sequence%')::text from pg_proc p where p.oid = 'public.wiki_insert_build(bigint,uuid,jsonb)'::regprocedure),
    'false / false / false / false / false', null
  union all select 6, '로그인 사람이 부를 수 있음 (새 상대법 / 새 빌드 / 빌드 수정 / 되돌리기)',
    has_function_privilege('authenticated', 'public.create_matchup(text,text,jsonb)', 'execute')::text
      || ' / ' || has_function_privilege('authenticated', 'public.create_build(bigint,jsonb)', 'execute')::text
      || ' / ' || has_function_privilege('authenticated', 'public.edit_build(bigint,integer,jsonb)', 'execute')::text
      || ' / ' || has_function_privilege('authenticated', 'public.revert_build(bigint,bigint,integer,text)', 'execute')::text,
    'true / true / true / true', '되돌리기는 안에서 운영자인지 다시 검사한다'
  union all select 7, '적어 둘 값: 빌드 수 (전체 / 공개 / 위키 빌드) / 버전 합계(수정 횟수)',
    (select count(*) || ' / ' || count(*) filter (where status = 'approved') || ' / ' || count(*) filter (where wiki)
            || ' / ' || coalesce(sum(version), 0) from public.builds),
    '(이 값을 적어 둠)', '065 뒤 같아야 함'
  union all select 8, '적어 둘 값: 추천 합계 / 비추천 합계 / 투표 줄 수',
    (select coalesce(sum(up_count), 0) || ' / ' || coalesce(sum(down_count), 0) from public.builds)
      || ' / ' || (select count(*) from public.build_votes),
    '(이 값을 적어 둠)', '065 뒤 같아야 함'
  union all select 9, '적어 둘 값: 수정 기록 수 / 기여자 줄 수 / 기여 횟수 합계',
    (select count(*) from public.build_revisions) || ' / ' || (select count(*) || ' / ' || coalesce(sum(edits), 0) from public.build_editors),
    '(이 값을 적어 둠)', '065 뒤 같아야 함 (1년 지난 기록은 매일 지워지므로 날이 바뀌면 줄 수 있음)'
  union all select 10, '적어 둘 값: 상대법 수 / 선마별 빌드 수 (Q / W / E)',
    (select count(*) from public.counters) || ' / ' ||
      (select count(*) filter (where max_skill = 'Q') || ' / ' || count(*) filter (where max_skill = 'W') || ' / ' || count(*) filter (where max_skill = 'E')
         from public.builds),
    '(이 값을 적어 둠)', '065 뒤 같아야 함 (선마는 그대로)'
  union all select 11, '적어 둘 값: builds 표 보안 규칙(RLS) 수 / 로그인 사람 직접 쓰기 권한 (insert / update)',
    (select count(*) from pg_policies where schemaname = 'public' and tablename = 'builds')
      || ' / ' || has_table_privilege('authenticated', 'public.builds', 'insert')::text
      || ' / ' || has_table_privilege('authenticated', 'public.builds', 'update')::text,
    '(이 값을 적어 둠)', '065 뒤 같아야 함 (065는 RLS·권한을 바꾸지 않는다)'
) rows
order by ord;
