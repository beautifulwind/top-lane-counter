-- =====================================================================
-- 071(빌드 난이도 별점 difficulty + set_build_difficulty) 실행 "전" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 071을 실행하기 전에 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~2번: [지금 값]이 [정상 값]과 맞으면 071을 실행해도 된다. 다르면 실행하지 말고 알려 주세요.
--   - 3~11번은 "적어 둘 값"이다. 071 실행 뒤 check_build_difficulty_after.sql의 같은 이름 줄과 비교한다
--     (071은 칸 하나·제약 하나·쓰기 함수 하나만 더한다 - 기존 함수·트리거·정책·권한·데이터는 그대로여야 한다).
--   - 함수 본문 지문은 줄바꿈 CR을 뺀 값으로 계산한다(SQL Editor가 CRLF로 붙여 넣어도 같은 값 - c5333b1과 같은 방식).
--   - 빌드 내용 지문은 difficulty 칸을 뺀 값이다(실행 뒤에도 같은 식으로 계산 → 기존 빌드가 그대로인지 비교).
--   - 사이트 활동(빌드 수정·추천·알림)이 있으면 9~11번은 달라질 수 있다 - 사람이 적은 시간에 이어서 실행해 주세요.
-- =====================================================================
with
-- 일반 사용자(로그인·비로그인)가 부를 수 있는 쓰기 함수 (068 빠뜨림 방지 검사와 같은 대상: volatile, 트리거 아님)
wf as (
  select p.oid, p.proname || '(' || oidvectortypes(p.proargtypes) || ')' as sig, p.prosrc
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f' and p.provolatile = 'v' and p.prorettype <> 'trigger'::regtype
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))
),
-- public의 모든 함수 (쓰기·읽기·트리거·내부 함수 전부) - 이름·인자·반환·본문·보안·search_path·권한
allf as (
  select p.proname || '(' || oidvectortypes(p.proargtypes) || ')' as sig,
         p.proname || '(' || oidvectortypes(p.proargtypes) || ')' || pg_get_function_result(p.oid) || p.provolatile::text
           || replace(p.prosrc, E'\r', '') || p.prosecdef::text || coalesce(array_to_string(p.proconfig, ','), '')
           || coalesce(array_to_string(p.proacl, ','), '') as body
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind in ('f', 'p')
)
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '070까지 실행됨 (함수 influencer_directory / assert_can_write / 표 restriction_exemptions)' as what,
    coalesce(to_regprocedure('public.influencer_directory(text, text, integer, integer)')::text, '없음')
      || ' / ' || coalesce(to_regprocedure('public.assert_can_write()')::text, '없음')
      || ' / ' || coalesce(to_regclass('public.restriction_exemptions')::text, '없음') as now_value,
    'influencer_directory(text,text,integer,integer) / assert_can_write() / restriction_exemptions' as ok_value, '없음이 있으면 앞 번호부터 실행' as memo
  union all select 2, '071 아직 안 함 (builds.difficulty 칸 수 / 제약 builds_difficulty_check 수 / set_build_difficulty 함수 수)',
    (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'builds' and column_name = 'difficulty')
      || ' / ' || (select count(*) from pg_constraint where conname = 'builds_difficulty_check')
      || ' / ' || (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'set_build_difficulty'),
    '0 / 0 / 0', '하나라도 1이면 071을 이미 실행한 것 - 다시 실행하지 말고 알려 주세요'
  union all select 3, '적어 둘 값: 쓰기 함수 수 (전체 / 첫 줄에 assert_can_write 검사 / 허용 목록)',
    (select count(*) from wf) || ' / '
      || (select count(*) from wf where wf.prosrc ~ '^\s*declare\s*\n\s*_can_write constant boolean := public\.assert_can_write\(\);'
                                     or wf.prosrc ~ '^\s*begin\s*\n\s*perform public\.assert_can_write\(\);')
      || ' / ' || (select count(*) from wf where exists (select 1 from public.restriction_exemptions e where e.kind = 'function' and e.name = wf.sig)),
    '100 / 29 / 71 (예상)', '071 뒤에는 101 / 30 / 71이어야 한다. 예상과 다르면 그대로 적어 두고 알려 주세요'
  union all select 4, '적어 둘 값: 쓰기 함수 100개의 이름·본문·보안·search_path·권한 지문 (CR 뺌)',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a join wf on wf.sig = a.sig),
    '(이 값을 적어 둠)', '실행 뒤: 새 함수 1개를 뺀 100개가 같은 지문'
  union all select 5, '적어 둘 값: 빌드를 내보내는 읽기 함수 지문 (follow_build_card·influencer_builds·followed_builds(_unchecked)·my_saved_builds·public_profile·build_json·build_links·build_editor_counts·build_contributors·wiki_snapshot·build_signature)',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a
      where split_part(a.sig, '(', 1) in ('follow_build_card', 'influencer_builds', 'followed_builds', 'followed_builds_unchecked', 'my_saved_builds',
                                          'public_profile', 'build_json', 'build_links', 'build_editor_counts', 'build_contributors', 'wiki_snapshot', 'build_signature')),
    '(이 값을 적어 둠)', '옛 앱 1.1·1.2가 쓰는 읽기 경로 - 071은 고치지 않는다'
  union all select 6, '적어 둘 값: public의 모든 함수 수 / 지문 (쓰기·읽기·트리거·내부 함수 전부, CR 뺌)',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a),
    '(이 값을 적어 둠)', '실행 뒤: set_build_difficulty를 뺀 나머지가 같은 수·같은 지문'
  union all select 7, '적어 둘 값: builds 칸 수 / 칸 목록 지문 · 제약 수 / 지문',
    (select count(*) || ' / ' || left(md5(string_agg(column_name || ':' || data_type || ':' || is_nullable || ':' || coalesce(column_default, ''), ',' order by ordinal_position)), 12)
       from information_schema.columns where table_schema = 'public' and table_name = 'builds')
      || ' · ' || (select count(*) || ' / ' || left(md5(string_agg(conname || ':' || pg_get_constraintdef(oid), ',' order by conname)), 12)
       from pg_constraint where conrelid = 'public.builds'::regclass),
    '(이 값을 적어 둠)', '실행 뒤: 칸 +1(difficulty)·제약 +1(builds_difficulty_check), 나머지는 같은 지문'
  union all select 8, '적어 둘 값: builds 트리거 수 / 지문 · 정책 수 / 지문 · 비로그인·로그인 표·칸 권한 지문',
    (select count(*) || ' / ' || left(md5(string_agg(pg_get_triggerdef(oid) || tgenabled::text, ',' order by tgname)), 12)
       from pg_trigger where tgrelid = 'public.builds'::regclass and not tgisinternal)
      || ' · ' || (select count(*) || ' / ' || left(md5(string_agg(polname || polcmd::text || coalesce(pg_get_expr(polqual, polrelid), '') || coalesce(pg_get_expr(polwithcheck, polrelid), ''), ',' order by polname)), 12)
       from pg_policy where polrelid = 'public.builds'::regclass)
      || ' · ' || (select left(md5(string_agg(grantee || ':' || privilege_type, ',' order by grantee, privilege_type)), 12)
       from information_schema.role_table_grants where table_schema = 'public' and table_name = 'builds' and grantee in ('anon', 'authenticated'))
      || '·' || (select count(*) || '·' || left(md5(string_agg(grantee || ':' || privilege_type || ':' || column_name, ',' order by grantee, privilege_type, column_name)), 12)
       from information_schema.column_privileges where table_schema = 'public' and table_name = 'builds' and grantee in ('anon', 'authenticated') and privilege_type <> 'SELECT'),
    '(이 값을 적어 둠)', '071은 트리거·정책·넣기 칸 권한을 바꾸지 않는다'
  union all select 9, '적어 둘 값: 빌드 수 · 가장 큰 id · 내용 지문 앞 12자리 (difficulty 칸 뺌)',
    (select count(*) || ' · ' || coalesce(max(id), 0) || ' · ' || left(md5(coalesce(string_agg((to_jsonb(b) - 'difficulty')::text, '|' order by b.id), '')), 12) from public.builds b),
    '(이 값을 적어 둠)', '그 사이 빌드 수정·추천이 있으면 달라질 수 있음'
  union all select 10, '적어 둘 값: 수정 기록(build_revisions) 수 · 가장 큰 id / 빌드 수정 알림(build_edited) 수 · 가장 큰 id',
    (select count(*) || ' · ' || coalesce(max(id), 0) from public.build_revisions)
      || ' / ' || (select count(*) || ' · ' || coalesce(max(id), 0) from public.notifications where kind = 'build_edited'),
    '(이 값을 적어 둠)', '071 실행 자체는 수정 기록·알림을 만들지 않는다'
  union all select 11, '적어 둘 값: 알림 전체 수 · 가장 큰 id',
    (select count(*) || ' · ' || coalesce(max(id), 0) from public.notifications),
    '(이 값을 적어 둠)', '그 사이 사이트 활동이 있으면 달라질 수 있음'
) x
order by ord;
