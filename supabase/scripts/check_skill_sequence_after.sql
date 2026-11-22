-- =====================================================================
-- 065(빌드 스킬 순서 상세) 실행 "뒤" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 065를 실행한 뒤 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~10번: [지금 값]이 [정상 값]과 모두 맞아야 한다. 하나라도 다르면 알려 주세요. (웹 push는 그다음)
--   - 11~15번: 실행 전 check_skill_sequence_before.sql의 7~11번에 적어 둔 값과 같아야 한다.
-- =====================================================================
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '새 칸 builds.skill_sequence (종류 / 비어도 됨) / 옛 이름 skill_order 없음' as what,
    coalesce((select data_type || ' / ' || is_nullable from information_schema.columns
               where table_schema = 'public' and table_name = 'builds' and column_name = 'skill_sequence'), '없음')
      || ' / ' || (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'builds'
                    and column_name = 'skill_order') as now_value,
    'text / YES / 0' as ok_value, '비어 있음(null) = 순서 없음. 옛 앱은 이 칸을 모른다' as memo
  union all select 2, '형식 검사 (Q·W·E·R 1~18글자) 있음 / 순서가 적힌 빌드 수',
    (select count(*) from pg_constraint where conrelid = 'public.builds'::regclass and conname = 'builds_skill_sequence_format')
      || ' / ' || (select count(*) from public.builds where skill_sequence is not null),
    '1 / 0', '065 직후 (아직 아무도 순서를 적지 않음)'
  union all select 3, '새 함수 (예외 표 / 규칙 / 검사) 있음',
    (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in ('skill_sequence_mode', 'skill_sequence_problem', 'check_skill_sequence')),
    '3', null
  union all select 4, '새 함수는 아무도 직접 못 부름 (부를 수 있는 수)',
    (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in ('skill_sequence_mode', 'skill_sequence_problem', 'check_skill_sequence')
        and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))),
    '0', '등록·수정·되돌리기 함수 안에서만 쓴다'
  union all select 5, '규칙 확인 (6렙 R 정상 / 5렙 R 거부 / 우디르 형식만 / 아펠리오스 순서 없음)',
    (public.skill_sequence_problem('QWEQQR', 'Garen') is null)::text
      || ' / ' || (public.skill_sequence_problem('QWEQR', 'Garen') = '스킬 순서 5렙: R은 6렙부터 찍을 수 있습니다.')::text
      || ' / ' || (public.skill_sequence_problem('RRRR', 'Udyr') is null)::text
      || ' / ' || (public.skill_sequence_problem('QWE', 'Aphelios') is not null)::text,
    'true / true / true / true', null
  union all select 6, '바꾼 함수가 스킬 순서를 앎 (스냅샷 / 빌드 검사 / 수정 / 되돌리기 / 넣기)',
    (select (p.prosrc like '%skill_sequence%')::text from pg_proc p where p.oid = 'public.wiki_snapshot(public.builds)'::regprocedure)
      || ' / ' || (select (p.prosrc like '%skill_sequence%')::text from pg_proc p where p.oid = 'public.clean_wiki_build(jsonb)'::regprocedure)
      || ' / ' || (select (p.prosrc like '%skill_sequence%')::text from pg_proc p where p.oid = 'public.edit_build(bigint,integer,jsonb)'::regprocedure)
      || ' / ' || (select (p.prosrc like '%skill_sequence%')::text from pg_proc p
                    where p.oid = 'public.revert_build_unchecked(bigint,bigint,integer,text)'::regprocedure)
      || ' / ' || (select (p.prosrc like '%skill_sequence%')::text from pg_proc p where p.oid = 'public.wiki_insert_build(bigint,uuid,jsonb)'::regprocedure),
    'true / true / true / true / true', null
  union all select 7, '옛 앱 호환: 수정에서 칸이 없으면 그대로 둠 / 똑같은 빌드 판정에서 순서를 뺌',
    (select (p.prosrc like '%p_build ? ''skill_sequence''%')::text from pg_proc p where p.oid = 'public.edit_build(bigint,integer,jsonb)'::regprocedure)
      || ' / ' || (select (p.prosrc like '%''lane_cautions'' - ''skill_sequence'' = public.build_signature%')::text from pg_proc p
                    where p.oid = 'public.edit_build(bigint,integer,jsonb)'::regprocedure),
    'true / true', null
  union all select 8, '건드리지 않은 함수 그대로 (옛 빌드 검사 / 빌드 json / 같은 빌드 비교가 순서를 모름)',
    (select (p.prosrc like '%skill_sequence%')::text from pg_proc p where p.oid = 'public.clean_build(jsonb)'::regprocedure)
      || ' / ' || (select (p.prosrc like '%skill_sequence%')::text from pg_proc p where p.oid = 'public.build_json(public.builds)'::regprocedure)
      || ' / ' || (select (p.prosrc like '%skill_sequence%')::text from pg_proc p where p.oid = 'public.build_signature(public.builds)'::regprocedure),
    'false / false / false', null
  union all select 9, '권한 그대로: 로그인 사람 (새 상대법 / 새 빌드 / 수정 / 되돌리기) + 비로그인 수정 불가 + 안쪽 함수 못 부름 수',
    has_function_privilege('authenticated', 'public.create_matchup(text,text,jsonb)', 'execute')::text
      || ' / ' || has_function_privilege('authenticated', 'public.create_build(bigint,jsonb)', 'execute')::text
      || ' / ' || has_function_privilege('authenticated', 'public.edit_build(bigint,integer,jsonb)', 'execute')::text
      || ' / ' || has_function_privilege('authenticated', 'public.revert_build(bigint,bigint,integer,text)', 'execute')::text
      || ' + ' || has_function_privilege('anon', 'public.edit_build(bigint,integer,jsonb)', 'execute')::text
      || ' + ' || (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
                    where n.nspname = 'public' and p.proname in ('wiki_snapshot', 'clean_wiki_build', 'wiki_insert_build', 'revert_build_unchecked')
                      and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))),
    'true / true / true / true + false + 0', null
  union all select 10, '새·바꾼 함수 search_path 고정 (빠진 수)',
    (select count(*)::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname in ('skill_sequence_mode', 'skill_sequence_problem', 'check_skill_sequence', 'wiki_snapshot', 'clean_wiki_build',
                          'wiki_insert_build', 'edit_build', 'revert_build_unchecked')
        and coalesce(array_to_string(p.proconfig, ','), '') not like '%search_path=%'),
    '0', null
  union all select 11, '빌드 수 (전체 / 공개 / 위키 빌드) / 버전 합계(수정 횟수)',
    (select count(*) || ' / ' || count(*) filter (where status = 'approved') || ' / ' || count(*) filter (where wiki)
            || ' / ' || coalesce(sum(version), 0) from public.builds),
    '(실행 전 7번과 같음)', null
  union all select 12, '추천 합계 / 비추천 합계 / 투표 줄 수',
    (select coalesce(sum(up_count), 0) || ' / ' || coalesce(sum(down_count), 0) from public.builds)
      || ' / ' || (select count(*) from public.build_votes),
    '(실행 전 8번과 같음)', null
  union all select 13, '수정 기록 수 / 기여자 줄 수 / 기여 횟수 합계',
    (select count(*) from public.build_revisions) || ' / ' || (select count(*) || ' / ' || coalesce(sum(edits), 0) from public.build_editors),
    '(실행 전 9번과 같음)', null
  union all select 14, '상대법 수 / 선마별 빌드 수 (Q / W / E)',
    (select count(*) from public.counters) || ' / ' ||
      (select count(*) filter (where max_skill = 'Q') || ' / ' || count(*) filter (where max_skill = 'W') || ' / ' || count(*) filter (where max_skill = 'E')
         from public.builds),
    '(실행 전 10번과 같음)', null
  union all select 15, 'builds 표 보안 규칙(RLS) 수 / 로그인 사람 직접 쓰기 권한 (insert / update)',
    (select count(*) from pg_policies where schemaname = 'public' and tablename = 'builds')
      || ' / ' || has_table_privilege('authenticated', 'public.builds', 'insert')::text
      || ' / ' || has_table_privilege('authenticated', 'public.builds', 'update')::text,
    '(실행 전 11번과 같음)', null
) rows
order by ord;
