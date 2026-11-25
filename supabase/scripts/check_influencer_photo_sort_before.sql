-- =====================================================================
-- 078(장인 목록 정렬에 프로필 사진 유무 반영) 실행 "전" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1번이 「070 본문」이면 실행해도 된다. 2~12번은 적어 둔다(078 뒤 check_influencer_photo_sort_after.sql과 비교).
--   - 순서는 influencer_directory(공개 함수)를 쪽마다 불러 id로만 비교한다. 이메일·토큰·닉네임 값은 출력하지 않는다(개수·지문만).
--   - 함수 본문 지문은 줄바꿈 CR을 뺀 값. 사이트 활동(팔로우·빌드·사진)이 있으면 순서 지문이 달라질 수 있다 - 이어서 바로 실행해 주세요.
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
kinds as (
  select (regexp_matches(pg_get_constraintdef(oid), '''([a-z_]+)''', 'g'))[1] as k
    from pg_constraint where conname = 'notifications_kind_check' and conrelid = 'public.notifications'::regclass
  union select 'no_such_kind'
),
-- 목록 대상 장인 (influencer_directory와 같은 조건)과 사진 유무
inf as (
  select p.id, (p.photo_path is not null and btrim(p.photo_path) <> '') as photo,
         (select count(*) from public.influencer_follows f where f.influencer_id = p.id) as followers
    from public.profiles p where p.influencer is not null and p.nickname is not null
),
-- influencer_directory를 쪽마다 불러 이은 순서 (정렬 2가지 × 쪽 크기 50·10·7). 이메일·닉네임 값은 출력하지 않는다(id 지문만)
sizes as (select s.srt, z.sz from (values ('followers'), ('recent')) s(srt) cross join (values (50), (10), (7)) z(sz)),
walk as (
  select sizes.srt, sizes.sz, (pg.n - 1) * sizes.sz + e.o as pos, (e.x ->> 'id')::uuid as id
    from sizes
    cross join lateral generate_series(1, greatest(1, ceil((select count(*) from inf)::numeric / sizes.sz)::integer)) pg(n)
    cross join lateral jsonb_array_elements(public.influencer_directory(null, sizes.srt, pg.n, sizes.sz) -> 'items') with ordinality e(x, o)
),
ord as (select w.*, inf.photo, inf.followers from walk w join inf on inf.id = w.id),
fp as (select srt, sz, count(*) as n, count(distinct id) as nd, md5(string_agg(id::text, ',' order by pos)) as f,
              -- 지금 순서에서 사진 있는 장인을 (순서를 지킨 채) 앞으로 모은 순서 = 078 뒤에 나올 순서
              md5(string_agg(id::text, ',' order by (not photo), pos)) as f_photo
         from ord group by srt, sz)
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '실행 가능: influencer_directory 본문' as what,
    coalesce((select case md5(replace(prosrc, E'\r', '')) when '7955c630a2b304baf7628375ca3f3940' then '070 본문'
                       when 'ef21f41e761c3785defccdf6a8bcbf42' then '078 본문' else '다름 ' || md5(replace(prosrc, E'\r', '')) end
              from pg_proc where oid = to_regprocedure('public.influencer_directory(text, text, integer, integer)')), '함수 없음') as now_value,
    '070 본문' as ok_value, '「078 본문」이면 이미 실행함, 「다름」이면 실행하지 말고 알려 주세요' as memo
  union all select 2, '장인 수(목록 대상) / 사진 있는 장인 수 / 50명 초과 여부',
    (select count(*) from inf) || ' / ' || (select count(*) filter (where photo) from inf)
      || case when (select count(*) from inf) > 50 then ' / !! 50명 초과 - 웹은 서버 쪽 나누기(쪽마다 따로 받기)로 동작 중' else ' / 50명 이하' end,
    '(이 값을 적어 둠)', '50명을 넘으면 웹의 사진 먼저 규칙이 쪽마다 따로 적용되던 상태'
  union all select 3, '지금 순서 지문 (팔로워 순 · 최신순, 50명씩 이어 붙임)',
    (select string_agg(srt || ' ' || n || '명 ' || left(f, 12), ' · ' order by srt) from fp where sz = 50),
    '(이 값을 적어 둠)', null
  union all select 4, '078 뒤 예상 순서 지문 (지금 순서에서 사진 있는 장인만 순서대로 앞으로)',
    (select string_agg(srt || ' ' || left(f_photo, 12), ' · ' order by srt) from fp where sz = 50),
    '(이 값을 적어 둠)', '078 뒤 확인 5번과 같아야 한다. 3번과 같으면 순서가 바뀌는 장인이 없음'
  union all select 5, '적어 둘 값: 쓰기 함수 수 (전체 / 첫 줄에 assert_can_write 검사 / 허용 목록)',
    (select count(*) from wf) || ' / '
      || (select count(*) from wf where wf.prosrc ~ '^\s*declare\s*\n\s*_can_write constant boolean := public\.assert_can_write\(\);'
                                     or wf.prosrc ~ '^\s*begin\s*\n\s*perform public\.assert_can_write\(\);')
      || ' / ' || (select count(*) from wf where exists (select 1 from public.restriction_exemptions e where e.kind = 'function' and e.name = wf.sig)),
    '103 / 30 / 73', null
  union all select 6, '적어 둘 값: 쓰기 함수 지문 (CR 뺌)',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a join wf on wf.sig = a.sig),
    '(이 값을 적어 둠)', null
  union all select 7, '적어 둘 값: influencer_directory를 뺀 읽기 함수 수 / 지문 (CR 뺌)',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a join rf on rf.sig = a.sig where a.sig <> 'influencer_directory(text, text, integer, integer)'),
    '(이 값을 적어 둠)', '읽기 함수 전체는 66개 (이 줄은 그 함수를 빼서 65)'
  union all select 8, '적어 둘 값: influencer_directory를 뺀 public의 모든 함수 수 / 지문 (CR 뺌)',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a where a.sig <> 'influencer_directory(text, text, integer, integer)'),
    '(이 값을 적어 둠)', '같으면 이 함수 말고는 하나도 안 바뀐 것'
  union all select 9, '적어 둘 값: influencer_directory 본문 밖 속성 (인자 · 반환 · volatile · security definer · search_path · 권한 · 소유자 · 설명 앞 20자)',
    (select pg_get_function_arguments(oid) || ' · ' || pg_get_function_result(oid) || ' · ' || provolatile::text || ' · ' || prosecdef::text
            || ' · ' || coalesce(array_to_string(proconfig, ','), '없음') || ' · ' || coalesce(array_to_string(proacl, ','), '기본')
            || ' · ' || pg_get_userbyid(proowner) || ' · ' || left(coalesce(obj_description(oid, 'pg_proc'), '없음'), 20)
       from pg_proc where oid = to_regprocedure('public.influencer_directory(text, text, integer, integer)')),
    '(이 값을 적어 둠)', '본문(정렬 한 줄)만 바뀌고 이 줄은 같아야 한다'
  union all select 10, '적어 둘 값: 푸시 판정 지문 - 모든 사람 × 모든 알림 종류의 push_wanted · 종류별 push_group',
    (select count(*) || ' / ' || md5(string_agg(p.id::text || ':' || k.k || ':' || public.push_wanted(p.id, k.k)::text, ',' order by p.id, k.k))
       from public.profiles p cross join kinds k)
      || ' · ' || (select count(*) || ' / ' || md5(string_agg(k || ':' || coalesce(public.push_group(k), '-'), ',' order by k)) from kinds),
    '(이 값을 적어 둠)', null
  union all select 11, '적어 둘 값: 허용 목록(restriction_exemptions) 줄 수 / 지문 · xp_rules 줄 수 / 지문',
    (select count(*) || ' / ' || left(md5(string_agg(kind || ':' || name || ':' || reason, ',' order by kind, name)), 12) from public.restriction_exemptions)
      || ' · ' || (select count(*) || ' / ' || left(md5(string_agg(key || ':' || value || ':' || note, ',' order by key)), 12) from public.xp_rules),
    '(이 값을 적어 둠)', null
  union all select 12, '적어 둘 값: public 트리거 수 / 지문 · 정책 수 / 지문',
    (select count(*) || ' / ' || left(md5(string_agg(tgrelid::regclass::text || pg_get_triggerdef(oid) || tgenabled::text, ',' order by tgrelid::regclass::text, tgname)), 12)
       from pg_trigger where not tgisinternal and tgrelid in (select oid from pg_class where relnamespace = 'public'::regnamespace))
      || ' · ' || (select count(*) || ' / ' || left(md5(string_agg(polrelid::regclass::text || polname || polcmd::text || coalesce(pg_get_expr(polqual, polrelid), '') || coalesce(pg_get_expr(polwithcheck, polrelid), ''), ',' order by polrelid::regclass::text, polname)), 12)
       from pg_policy where polrelid in (select oid from pg_class where relnamespace = 'public'::regnamespace)),
    '(이 값을 적어 둠)', null
) x
order by ord;
