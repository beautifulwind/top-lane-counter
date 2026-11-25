-- =====================================================================
-- 080(내 챔피언) 실행 "뒤" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~8번과 16번은 [정상 값]과 같아야 한다(7번 N은 사람 수). 9~15번 「비교」는 전 2~9번과 같아야 한다.
--   - 7번은 챔피언을 등록한 사람마다 이 조회 안에서만 그 사람으로 새 함수를 불러(request.jwt.claim.sub, 조회가 끝나면 사라짐)
--     기대값과 개수만 비교한다. 바로 실행했다면 등록한 사람이 없어 「0 / 0 / 0 / 0」이 정상이다.
--   - 이메일·토큰·닉네임·챔피언 값은 출력하지 않는다(개수·지문만). 함수 본문 지문은 줄바꿈 CR을 뺀 값.
-- =====================================================================
with
wf as (
  select p.oid, p.proname || '(' || oidvectortypes(p.proargtypes) || ')' as sig, p.prosrc
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f' and p.provolatile = 'v' and p.prorettype <> 'trigger'::regtype
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))
),
rf as (
  select p.proname || '(' || oidvectortypes(p.proargtypes) || ')' as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f' and p.provolatile in ('s', 'i') and p.prorettype <> 'trigger'::regtype
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))
),
allf as (
  select p.proname || '(' || oidvectortypes(p.proargtypes) || ')' as sig,
         p.proname || '(' || oidvectortypes(p.proargtypes) || ')' || pg_get_function_result(p.oid) || p.provolatile::text
           || replace(p.prosrc, E'\r', '') || p.prosecdef::text || coalesce(array_to_string(p.proconfig, ','), '')
           || coalesce(array_to_string(p.proacl, ','), '') as body
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind in ('f', 'p')
),
newf as (select unnest(array['set_my_champion(text, boolean)', 'my_champions()', 'my_champion_builds(text, integer)']) as sig),
kinds as (
  select (regexp_matches(pg_get_constraintdef(oid), '''([a-z_]+)''', 'g'))[1] as k
    from pg_constraint where conname = 'notifications_kind_check' and conrelid = 'public.notifications'::regclass
  union select 'no_such_kind'
),
-- 등록한 사람마다 기대값: 공개 빌드 · 등록 챔피언이 내 챔피언 쪽 · 차단한 사람 제외, /builds 추천순 1쪽 20개
per as (
  select u.uid,
         (select count(*) from public.user_champions m where m.user_id = u.uid) as want_n,
         (select count(*) from public.builds b join public.counters c on c.id = b.counter_id
           where b.status = 'approved' and c.status = 'approved'
             and c.counter_champion in (select m.champion from public.user_champions m where m.user_id = u.uid)
             and not exists (select 1 from public.user_blocks k where k.blocker_id = u.uid and k.blocked_id = b.author_id)) as want_total,
         (select coalesce(string_agg(x.id::text, ',' order by x.o), '') from (
            select b.id, row_number() over (order by (a.influencer is not null) desc, b.up_count desc, b.created_at desc, b.id desc) as o
              from public.builds b join public.counters c on c.id = b.counter_id left join public.profiles a on a.id = b.author_id
             where b.status = 'approved' and c.status = 'approved'
               and c.counter_champion in (select m.champion from public.user_champions m where m.user_id = u.uid)
               and not exists (select 1 from public.user_blocks k where k.blocker_id = u.uid and k.blocked_id = b.author_id)) x where x.o <= 20) as want_ids,
         r.mc, r.mb
    from (select distinct user_id as uid from public.user_champions) u
    cross join lateral (select set_config('request.jwt.claim.sub', u.uid::text, true) as s) s
    cross join lateral (select public.my_champions() as mc, public.my_champion_builds(null, 1) as mb where s.s is not null) r
)
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '표: user_champions RLS · 기본 키 · 외래 키 / champion_catalog RLS · 챔피언 수' as what,
    coalesce((select relrowsecurity::text from pg_class where oid = to_regclass('public.user_champions')), '없음')
      || ' · ' || coalesce((select pg_get_constraintdef(oid) from pg_constraint where conrelid = to_regclass('public.user_champions') and contype = 'p'), '-')
      || ' · ' || coalesce((select pg_get_constraintdef(oid) from pg_constraint where conrelid = to_regclass('public.user_champions') and contype = 'f'), '-')
      || ' / ' || coalesce((select relrowsecurity::text from pg_class where oid = to_regclass('public.champion_catalog')), '없음')
      || ' · ' || (select count(*) from public.champion_catalog) as now_value,
    'true · PRIMARY KEY (user_id, champion) · FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE / true · 173' as ok_value,
    '탈퇴·비회원 정리 때 함께 지워짐' as memo
  union all select 2, '표 권한: user_champions 로그인 읽기 / 쓰기(넣기·고치기·지우기) / 비로그인 읽기 · 정책 (수 · 종류 · 식)',
    has_table_privilege('authenticated', 'public.user_champions', 'select')::text
      || ' / ' || (has_table_privilege('authenticated', 'public.user_champions', 'insert') or has_table_privilege('authenticated', 'public.user_champions', 'update')
                   or has_table_privilege('authenticated', 'public.user_champions', 'delete'))::text
      || ' / ' || has_table_privilege('anon', 'public.user_champions', 'select')::text
      || ' · ' || (select count(*) || ' · ' || string_agg(polcmd::text || ' · ' || pg_get_expr(polqual, polrelid), ',') from pg_policy where polrelid = 'public.user_champions'::regclass),
    'true / false / false · 1 · r · (user_id = ( SELECT auth.uid() AS uid))', '본인 줄만 읽음, 다른 사람의 등록을 보는 길 없음'
  union all select 3, '표 권한: champion_catalog 로그인 읽기 / 비로그인 읽기 / 정책 수',
    has_table_privilege('authenticated', 'public.champion_catalog', 'select')::text || ' / ' || has_table_privilege('anon', 'public.champion_catalog', 'select')::text
      || ' / ' || (select count(*) from pg_policy where polrelid = 'public.champion_catalog'::regclass),
    'false / false / 0', '함수만 읽음'
  union all select 4, '함수 모양: set_my_champion (인자 · 반환 · 종류 · security definer · search_path)',
    coalesce((select pg_get_function_arguments(oid) || ' · ' || pg_get_function_result(oid) || ' · ' || provolatile::text || ' · ' || prosecdef::text
            || ' · ' || coalesce(array_to_string(proconfig, ','), '없음') from pg_proc where oid = to_regprocedure('public.set_my_champion(text, boolean)')), '없음'),
    'p_champion text, p_selected boolean · jsonb · v · true · search_path=""', null
  union all select 5, '함수 모양: my_champions / my_champion_builds',
    coalesce((select '(' || pg_get_function_arguments(oid) || ') · ' || pg_get_function_result(oid) || ' · ' || provolatile::text || ' · ' || prosecdef::text
            || ' · ' || coalesce(array_to_string(proconfig, ','), '없음') from pg_proc where oid = to_regprocedure('public.my_champions()')), '없음')
      || ' / ' || coalesce((select '(' || pg_get_function_arguments(oid) || ') · ' || pg_get_function_result(oid) || ' · ' || provolatile::text || ' · ' || prosecdef::text
            || ' · ' || coalesce(array_to_string(proconfig, ','), '없음') from pg_proc where oid = to_regprocedure('public.my_champion_builds(text, integer)')), '없음'),
    '() · jsonb · s · true · search_path="" / (p_champion text DEFAULT NULL::text, p_page integer DEFAULT 1) · jsonb · s · true · search_path=""', null
  union all select 6, '실행 권한 (세 함수 모두): 로그인(authenticated) / 비로그인(anon) / public · set_my_champion 첫 줄 검사 · 허용 목록에 있음',
    (select bool_and(has_function_privilege('authenticated', to_regprocedure('public.' || sig), 'execute'))::text
            || ' / ' || bool_or(has_function_privilege('anon', to_regprocedure('public.' || sig), 'execute'))::text
            || ' / ' || bool_or(exists (select 1 from pg_proc p, unnest(p.proacl) a where p.oid = to_regprocedure('public.' || sig) and a::text like '=%'))::text from newf)
      || ' · ' || (select (prosrc ~ '^\s*declare\s*\n\s*_can_write constant boolean := public\.assert_can_write\(\);')::text from pg_proc where oid = to_regprocedure('public.set_my_champion(text, boolean)'))
      || ' · ' || exists (select 1 from public.restriction_exemptions where name like '%champion%')::text,
    'true / false / false · true · false', '비로그인은 부를 수 없음, 활동 제한 검사 있음, 허용 목록은 그대로'
  union all select 7, '등록한 사람마다 불러 본 결과: 확인한 사람 수 / 등록 수가 다른 사람 / total이 다른 사람 / 1쪽 빌드·순서가 다른 사람',
    (select count(*) || ' / ' || count(*) filter (where jsonb_array_length(mc -> 'items') <> want_n)
            || ' / ' || count(*) filter (where (mb ->> 'total')::bigint <> want_total)
            || ' / ' || count(*) filter (where coalesce((select string_agg(e ->> 'id', ',' order by o) from jsonb_array_elements(mb -> 'items') with ordinality e(e, o)), '') <> want_ids)
       from per),
    'N / 0 / 0 / 0', '자기 등록분만, /builds 추천순, 차단한 사람 제외 (바로 실행했으면 0 / 0 / 0 / 0)'
  union all select 8, '한도: 10개 넘게 등록한 사람 수 · 형식이 틀린 챔피언 줄 수',
    (select count(*) from (select user_id from public.user_champions group by user_id having count(*) > 10) x)
      || ' · ' || (select count(*) from public.user_champions where champion !~ '^[A-Za-z]{1,30}$'),
    '0 · 0', null
  union all select 9, '비교: 쓰기 함수 수 (전체 / 첫 줄에 assert_can_write 검사 / 허용 목록)',
    (select count(*) from wf) || ' / '
      || (select count(*) from wf where wf.prosrc ~ '^\s*declare\s*\n\s*_can_write constant boolean := public\.assert_can_write\(\);'
                                     or wf.prosrc ~ '^\s*begin\s*\n\s*perform public\.assert_can_write\(\);')
      || ' / ' || (select count(*) from wf where exists (select 1 from public.restriction_exemptions e where e.kind = 'function' and e.name = wf.sig)),
    '104 / 31 / 73', '전 2번(103 / 30 / 73) + set_my_champion'
  union all select 10, '비교: set_my_champion을 뺀 쓰기 함수 지문 (CR 뺌)',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a join wf on wf.sig = a.sig where a.sig not in (select sig from newf)),
    '(전 3번과 같음)', null
  union all select 11, '비교: my_champions·my_champion_builds를 뺀 읽기 함수 수 / 지문 (CR 뺌)',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a join rf on rf.sig = a.sig where a.sig not in (select sig from newf)),
    '(전 4번과 같음)', null
  union all select 12, '비교: 080의 세 함수를 뺀 public의 모든 함수 수 / 지문 (CR 뺌)',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a where a.sig not in (select sig from newf)),
    '(전 5번과 같음)', '기존 함수는 하나도 고치지 않음'
  union all select 13, '비교: 푸시 판정 지문 - 모든 사람 × 모든 알림 종류의 push_wanted · 종류별 push_group',
    (select count(*) || ' / ' || md5(string_agg(p.id::text || ':' || k.k || ':' || public.push_wanted(p.id, k.k)::text, ',' order by p.id, k.k))
       from public.profiles p cross join kinds k)
      || ' · ' || (select count(*) || ' / ' || md5(string_agg(k || ':' || coalesce(public.push_group(k), '-'), ',' order by k)) from kinds),
    '(전 6번과 같음)', null
  union all select 14, '비교: 허용 목록(restriction_exemptions) 줄 수 / 지문 · xp_rules 줄 수 / 지문',
    (select count(*) || ' / ' || left(md5(string_agg(kind || ':' || name || ':' || reason, ',' order by kind, name)), 12) from public.restriction_exemptions)
      || ' · ' || (select count(*) || ' / ' || left(md5(string_agg(key || ':' || value || ':' || note, ',' order by key)), 12) from public.xp_rules),
    '(전 7번과 같음)', null
  union all select 15, '비교: public 트리거 수 / 지문 · user_champions 것을 뺀 정책 수 / 지문',
    (select count(*) || ' / ' || left(md5(string_agg(tgrelid::regclass::text || pg_get_triggerdef(oid) || tgenabled::text, ',' order by tgrelid::regclass::text, tgname)), 12)
       from pg_trigger where not tgisinternal and tgrelid in (select oid from pg_class where relnamespace = 'public'::regnamespace))
      || ' · ' || (select count(*) || ' / ' || left(md5(string_agg(polrelid::regclass::text || polname || polcmd::text || coalesce(pg_get_expr(polqual, polrelid), '') || coalesce(pg_get_expr(polwithcheck, polrelid), ''), ',' order by polrelid::regclass::text, polname)), 12)
       from pg_policy where polrelid in (select oid from pg_class where relnamespace = 'public'::regnamespace) and polrelid <> 'public.user_champions'::regclass),
    '(전 8번과 같음)', null
  union all select 16, '읽기 함수 전체 수 · 공개 빌드 수 / 회원 수',
    (select count(*) from rf)::text || ' · '
      || (select count(*) from public.builds b join public.counters c on c.id = b.counter_id where b.status = 'approved' and c.status = 'approved')
      || ' / ' || (select count(*) from public.profiles),
    '69 · (전 9번과 같음)', '67 + my_champions + my_champion_builds'
) x
order by ord;
