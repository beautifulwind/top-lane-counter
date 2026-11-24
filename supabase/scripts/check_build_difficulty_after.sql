-- =====================================================================
-- 071(빌드 난이도 별점 difficulty + set_build_difficulty + build_difficulties) 실행 "뒤" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다). 운영 DB에서 언제 다시 실행해도 된다.
-- 071을 실행한 "직후" SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~12번·22~26번: [지금 값]이 [정상 값]과 모두 맞아야 한다. 하나라도 다르면 알려 주세요.
--   - 13~21번·27번: 실행 전 check_build_difficulty_before.sql의 3~12번에 적어 둔 값과 비교한다(각 줄의 [정상 값]에 무엇과 같아야 하는지 적었다).
--   - 함수 본문 지문은 줄바꿈 CR을 뺀 값으로 계산한다(SQL Editor가 CRLF로 붙여 넣어도 같은 값 - c5333b1과 같은 방식).
--   - 이 조회는 set_build_difficulty를 부르지 않는다(별점을 바꾸지 않음). build_difficulties는 빈 입력으로만 부른다(읽기 함수).
-- =====================================================================
with
fn as (select to_regprocedure('public.set_build_difficulty(bigint, numeric)') as oid),
rd as (select to_regprocedure('public.build_difficulties(bigint[])') as oid),
-- 일반 사용자(로그인·비로그인)가 부를 수 있는 읽기 함수 (stable·immutable, 트리거 아님) - 실행 전 스크립트와 같은 식
rf as (
  select p.proname || '(' || oidvectortypes(p.proargtypes) || ')' as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f' and p.provolatile in ('s', 'i') and p.prorettype <> 'trigger'::regtype
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))
),
-- 일반 사용자(로그인·비로그인)가 부를 수 있는 쓰기 함수 (068 빠뜨림 방지 검사와 같은 대상)
wf as (
  select p.oid, p.proname || '(' || oidvectortypes(p.proargtypes) || ')' as sig, p.prosrc,
         case
           when p.prosrc ~ '^\s*declare\s*\n\s*_can_write constant boolean := public\.assert_can_write\(\);'
             or p.prosrc ~ '^\s*begin\s*\n\s*perform public\.assert_can_write\(\);' then 'checked'
           when p.prosrc like '%assert_can_write%' then 'NOT_FIRST'
           when exists (select 1 from public.restriction_exemptions e
                         where e.kind = 'function' and e.name = p.proname || '(' || oidvectortypes(p.proargtypes) || ')') then 'exempt'
           else 'MISSING'
         end as state
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f' and p.provolatile = 'v' and p.prorettype <> 'trigger'::regtype
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))
),
-- public의 모든 함수 (실행 전 스크립트와 같은 식)
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
  select 1 as ord, '새 칸 builds.difficulty (자료형 / null 허용 / 기본값)' as what,
    coalesce((select data_type || '(' || numeric_precision || ',' || numeric_scale || ') / ' || is_nullable || ' / ' || coalesce(column_default, '없음')
       from information_schema.columns where table_schema = 'public' and table_name = 'builds' and column_name = 'difficulty'), '칸 없음') as now_value,
    'numeric(2,1) / YES / 없음' as ok_value, null as memo
  union all select 2, '제약 builds_difficulty_check (내용)',
    coalesce((select pg_get_constraintdef(oid) from pg_constraint where conname = 'builds_difficulty_check' and conrelid = 'public.builds'::regclass), '없음'),
    'CHECK (((difficulty IS NULL) OR (((difficulty >= 0.5) AND (difficulty <= 5.0)) AND ((difficulty * (2)::numeric) = trunc((difficulty * (2)::numeric))))))',
    'null 또는 0.5~5.0의 0.5 단위'
  union all select 3, '기존 빌드 별점 (전체 빌드 수 / 별점이 있는 빌드 수)',
    (select count(*) || ' / ' || count(difficulty) from public.builds),
    '(빌드 수) / 0', '실행 직후에는 모두 null(0). 그 뒤 작성자가 정하면 늘어난다 - 직후에만 0을 확인'
  union all select 4, '별점 값이 규칙 밖인 빌드 수',
    (select count(*) from public.builds where difficulty is not null and (difficulty < 0.5 or difficulty > 5.0 or difficulty * 2 <> trunc(difficulty * 2)))::text,
    '0', '제약이 막으므로 늘 0'
  union all select 5, '새 함수 set_build_difficulty (인자 / 같은 이름 함수 수 / 반환형)',
    coalesce((select oid::regprocedure::text from fn), '없음')
      || ' / ' || (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'set_build_difficulty')
      || ' / ' || coalesce((select prorettype::regtype::text from pg_proc where oid = (select oid from fn)), '없음'),
    'set_build_difficulty(bigint,numeric) / 1 / jsonb', null
  union all select 6, '보안 (volatile 종류 / security definer / search_path)',
    coalesce((select provolatile::text || ' / ' || prosecdef::text || ' / ' || coalesce(array_to_string(proconfig, ','), '없음') from pg_proc where oid = (select oid from fn)), '함수 없음'),
    'v / true / search_path=""', 'v = volatile(쓰기 함수)'
  union all select 7, '실행 권한 (비로그인 anon / 로그인 authenticated / public 기본 권한)',
    coalesce((select has_function_privilege('anon', oid, 'execute')::text || ' / ' || has_function_privilege('authenticated', oid, 'execute')::text
            || ' / ' || exists (select 1 from unnest(proacl) a where a::text like '=%')::text
       from pg_proc where oid = (select oid from fn)), '함수 없음'),
    'false / true / false', '로그인 사용자만'
  union all select 8, '함수 본문 지문 (줄바꿈 CR을 뺀 값)',
    coalesce((select md5(replace(prosrc, E'\r', '')) from pg_proc where oid = (select oid from fn)), '함수 없음'),
    '696290e4f359076bba714655023b6c29', '파일 그대로 실행했으면 같음 (CRLF로 붙여 넣어도 같음)'
  union all select 9, '068 활동 제한: 새 함수의 판정 (checked = 첫 줄에 assert_can_write)',
    coalesce((select state from wf where sig = 'set_build_difficulty(bigint, numeric)'), '쓰기 함수 목록에 없음'),
    'checked', '허용 목록에는 넣지 않는다'
  union all select 10, '빠뜨림 방지: 쓰기 함수 중 통과 못 한 것 (검사도 허용 목록도 없음 / 검사가 첫 줄이 아님)',
    coalesce((select string_agg(sig || ' ' || state, ', ' order by sig) from wf where state not in ('checked', 'exempt')), '없음'),
    '없음', '068 check_restrictions_after.sql 5번과 같은 규칙'
  union all select 11, '허용 목록에 있는데 실제로 없는 함수',
    coalesce((select string_agg(e.name, ', ') from public.restriction_exemptions e where e.kind = 'function' and not exists (select 1 from wf where wf.sig = e.name)), '없음'),
    '없음', null
  union all select 12, '별점만 바꾸면 알림이 생기지 않는 구조 (빌드 수정 알림 트리거가 붙은 표 / builds UPDATE 트리거 중 difficulty를 보는 것)',
    coalesce((select string_agg(distinct tgrelid::regclass::text, ',') from pg_trigger where tgname = 'build_revisions_notify'), '없음')
      || ' / ' || coalesce((select string_agg(tgname, ',' order by tgname) from pg_trigger
                             where tgrelid = 'public.builds'::regclass and not tgisinternal
                               and pg_get_triggerdef(oid) ~ 'UPDATE OF [^O]*difficulty'), '없음'),
    'build_revisions / 없음', '알림은 수정 기록 표에 줄이 생길 때만 - 새 함수는 수정 기록을 남기지 않는다'
  -- ===== 실행 전 값과 비교 =====
  union all select 13, '비교: 쓰기 함수 수 (전체 / 첫 줄 검사 / 허용 목록)',
    (select count(*) from wf) || ' / ' || (select count(*) from wf where state = 'checked') || ' / ' || (select count(*) from wf where state = 'exempt'),
    '실행 전 3번 + (1 / 1 / 0) → 101 / 30 / 71', '새 쓰기 함수 1개만 늘었다'
  union all select 14, '비교: 새 함수를 뺀 쓰기 함수의 지문',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a join wf on wf.sig = a.sig where a.sig <> 'set_build_difficulty(bigint, numeric)'),
    '실행 전 4번과 같음', '기존 쓰기 함수 100개 그대로'
  union all select 15, '비교: 빌드를 내보내는 읽기 함수 지문',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a
      where split_part(a.sig, '(', 1) in ('follow_build_card', 'influencer_builds', 'followed_builds', 'followed_builds_unchecked', 'my_saved_builds',
                                          'public_profile', 'build_json', 'build_links', 'build_editor_counts', 'build_contributors', 'wiki_snapshot', 'build_signature')),
    '실행 전 5번과 같음', '옛 앱 1.1·1.2가 쓰는 응답 모양 그대로'
  union all select 16, '비교: public의 모든 함수 (새 함수 2개 뺌) 수 / 지문',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a
      where a.sig not in ('set_build_difficulty(bigint, numeric)', 'build_difficulties(bigint[])')),
    '실행 전 6번과 같음', '기존 함수는 하나도 바뀌지 않았다'
  union all select 17, '비교: builds 칸 (difficulty 뺌) 수 / 지문 · 제약 (새 제약 뺌) 수 / 지문',
    (select count(*) || ' / ' || left(md5(string_agg(column_name || ':' || data_type || ':' || is_nullable || ':' || coalesce(column_default, ''), ',' order by ordinal_position)), 12)
       from information_schema.columns where table_schema = 'public' and table_name = 'builds' and column_name <> 'difficulty')
      || ' · ' || (select count(*) || ' / ' || left(md5(string_agg(conname || ':' || pg_get_constraintdef(oid), ',' order by conname)), 12)
       from pg_constraint where conrelid = 'public.builds'::regclass and conname <> 'builds_difficulty_check'),
    '실행 전 7번과 같음', null
  union all select 18, '비교: builds 트리거 · 정책 · 표·칸 권한 (difficulty는 넣기 권한에 없음)',
    (select count(*) || ' / ' || left(md5(string_agg(pg_get_triggerdef(oid) || tgenabled::text, ',' order by tgname)), 12)
       from pg_trigger where tgrelid = 'public.builds'::regclass and not tgisinternal)
      || ' · ' || (select count(*) || ' / ' || left(md5(string_agg(polname || polcmd::text || coalesce(pg_get_expr(polqual, polrelid), '') || coalesce(pg_get_expr(polwithcheck, polrelid), ''), ',' order by polname)), 12)
       from pg_policy where polrelid = 'public.builds'::regclass)
      || ' · ' || (select left(md5(string_agg(grantee || ':' || privilege_type, ',' order by grantee, privilege_type)), 12)
       from information_schema.role_table_grants where table_schema = 'public' and table_name = 'builds' and grantee in ('anon', 'authenticated'))
      || '·' || (select count(*) || '·' || left(md5(string_agg(grantee || ':' || privilege_type || ':' || column_name, ',' order by grantee, privilege_type, column_name)), 12)
       from information_schema.column_privileges where table_schema = 'public' and table_name = 'builds' and grantee in ('anon', 'authenticated') and privilege_type <> 'SELECT'),
    '실행 전 8번과 같음', '표 단위 읽기 권한이라 difficulty도 읽히지만, 넣기·고치기 칸 권한은 없다'
  union all select 19, '비교: 빌드 수 · 가장 큰 id · 내용 지문 앞 12자리 (difficulty 칸 뺌)',
    (select count(*) || ' · ' || coalesce(max(id), 0) || ' · ' || left(md5(coalesce(string_agg((to_jsonb(b) - 'difficulty')::text, '|' order by b.id), '')), 12) from public.builds b),
    '실행 전 9번과 같음', '071은 기존 빌드를 바꾸지 않는다 (그 사이 사이트 활동이 있으면 다를 수 있음)'
  union all select 20, '비교: 수정 기록 수 · 가장 큰 id / 빌드 수정 알림 수 · 가장 큰 id',
    (select count(*) || ' · ' || coalesce(max(id), 0) from public.build_revisions)
      || ' / ' || (select count(*) || ' · ' || coalesce(max(id), 0) from public.notifications where kind = 'build_edited'),
    '실행 전 10번과 같음', null
  union all select 21, '비교: 알림 전체 수 · 가장 큰 id',
    (select count(*) || ' · ' || coalesce(max(id), 0) from public.notifications),
    '실행 전 11번과 같음', null
  -- ===== 새 읽기 함수 build_difficulties =====
  union all select 22, '새 읽기 함수 build_difficulties (인자 / 같은 이름 함수 수 / 반환형)',
    coalesce((select oid::regprocedure::text from rd), '없음')
      || ' / ' || (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'build_difficulties')
      || ' / ' || coalesce((select prorettype::regtype::text from pg_proc where oid = (select oid from rd)), '없음'),
    'build_difficulties(bigint[]) / 1 / jsonb', null
  union all select 23, '보안 (volatile 종류 / security definer / search_path)',
    coalesce((select provolatile::text || ' / ' || prosecdef::text || ' / ' || coalesce(array_to_string(proconfig, ','), '없음') from pg_proc where oid = (select oid from rd)), '함수 없음'),
    's / false / search_path=""', 's = stable(읽기 함수), false = security invoker → builds 읽기 규칙(RLS) 그대로'
  union all select 24, '실행 권한 (비로그인 anon / 로그인 authenticated / public 기본 권한)',
    coalesce((select has_function_privilege('anon', oid, 'execute')::text || ' / ' || has_function_privilege('authenticated', oid, 'execute')::text
            || ' / ' || exists (select 1 from unnest(proacl) a where a::text like '=%')::text
       from pg_proc where oid = (select oid from rd)), '함수 없음'),
    'true / true / false', '로그아웃 상태의 장인 프로필에서도 부른다'
  union all select 25, '함수 본문 지문 (줄바꿈 CR을 뺀 값)',
    coalesce((select md5(replace(prosrc, E'\r', '')) from pg_proc where oid = (select oid from rd)), '함수 없음'),
    '0a738b0c9a5531826caaa77f238e9f06', '파일 그대로 실행했으면 같음 (CRLF로 붙여 넣어도 같음)'
  union all select 26, '빈 입력 (빈 배열 / null / null만 든 배열) · 쓰기 함수 목록에 있음',
    coalesce((select public.build_difficulties('{}'::bigint[])::text || ' / ' || public.build_difficulties(null)::text || ' / ' || public.build_difficulties(array[null]::bigint[])::text
       where (select oid from rd) is not null), '함수 없음')
      || ' · ' || exists (select 1 from wf where wf.sig = 'build_difficulties(bigint[])')::text,
    '{} / {} / {} · false', '읽기 함수라 쓰기 함수 수(101)에 들어가지 않는다'
  union all select 27, '비교: 읽기 함수 수 / 새 함수를 뺀 지문',
    (select count(*) from rf) || ' / '
      || (select md5(string_agg(a.body, '|' order by a.sig)) from allf a join rf on rf.sig = a.sig where a.sig <> 'build_difficulties(bigint[])'),
    '실행 전 12번 + (1 / 같은 지문)', '읽기 함수는 새 함수 1개만 늘었다'
) x
order by ord;
