-- =====================================================================
-- 075(일반 사용자 개인 페이지 member_page) 실행 "뒤" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 075를 실행한 뒤 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~9번: [지금 값]이 [정상 값]과 같아야 한다.
--   - 10~17번 「비교」: check_member_page_before.sql에서 적어 둔 같은 항목(3~11번)과 같아야 한다.
--   - member_page는 읽기 함수라 여기서 사람마다 불러 본다(아무것도 바꾸지 않음). 이메일·닉네임·id 값은 출력하지 않는다(개수·지문만).
--   - 함수 본문 지문은 줄바꿈 CR을 뺀 값으로 계산한다.
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
pb as (
  select b.author_id as uid, count(*) as n
    from public.builds b join public.counters c on c.id = b.counter_id
   where b.status = 'approved' and c.status = 'approved' and b.author_id is not null
   group by b.author_id
),
-- 모든 사람의 개인 페이지 (비로그인과 같은 결과 - 함수가 부른 사람을 보지 않는다)
mp as (select p.id, p.role, p.is_guest, p.nickname, p.influencer, coalesce(pb.n, 0) as n, public.member_page(p.id::text) as j
         from public.profiles p left join pb on pb.uid = p.id),
fn as (select oid from pg_proc where oid = to_regprocedure('public.member_page(text, integer)'))
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, 'member_page 함수 / 설정값' as what,
    case when (select count(*) from fn) = 1 then '있음' else '없음' end
      || ' / ' || coalesce((select value::text from public.xp_rules where key = 'member_page_min_builds'), '없음') as now_value,
    '있음 / 5' as ok_value, null as memo
  union all select 2, 'member_page 모양 (반환 · volatile · security definer · search_path · 소유자)',
    (select pg_get_function_result(oid) || ' · ' || provolatile::text || ' · ' || prosecdef::text || ' · '
            || coalesce(array_to_string(proconfig, ','), '없음') || ' · ' || pg_get_userbyid(proowner) from pg_proc where oid = (select oid from fn)),
    'jsonb · s · true · search_path="" · postgres', null
  union all select 3, 'member_page 실행 권한 (비로그인 / 로그인 / public 기본 권한)',
    (select has_function_privilege('anon', oid, 'execute')::text || ' / ' || has_function_privilege('authenticated', oid, 'execute')::text
            || ' / ' || exists (select 1 from unnest(proacl) a where a::text like '=%')::text from pg_proc where oid = (select oid from fn)),
    'true / true / false', null
  union all select 4, '쓰기 함수 수 (전체 / 첫 줄 검사 / 허용 목록)',
    (select count(*) from wf) || ' / '
      || (select count(*) from wf where wf.prosrc ~ '^\s*declare\s*\n\s*_can_write constant boolean := public\.assert_can_write\(\);'
                                     or wf.prosrc ~ '^\s*begin\s*\n\s*perform public\.assert_can_write\(\);')
      || ' / ' || (select count(*) from wf where exists (select 1 from public.restriction_exemptions e where e.kind = 'function' and e.name = wf.sig)),
    '103 / 30 / 73', 'member_page는 읽기 함수라 그대로'
  union all select 5, '빠뜨림 방지: 검사도 허용 목록도 없는 쓰기 함수 수',
    (select count(*)::text from wf where not (wf.prosrc ~ '^\s*declare\s*\n\s*_can_write constant boolean := public\.assert_can_write\(\);'
                                             or wf.prosrc ~ '^\s*begin\s*\n\s*perform public\.assert_can_write\(\);')
                                     and not exists (select 1 from public.restriction_exemptions e where e.kind = 'function' and e.name = wf.sig)),
    '0', null
  union all select 6, '읽기 함수 수 (member_page 포함)', (select count(*)::text from rf), '66', '074까지 65 + member_page'
  union all select 7, '열린 페이지가 모두 일반 사용자·공개 빌드 5개 이상 (어긋난 수: 장인·운영자·비회원·닉네임 없음·5개 미만·정지 중)',
    (select count(*)::text from mp where j is not null
       and (influencer is not null or role = 'admin' or is_guest or nickname is null or n < 5 or public.active_restriction_id(id) is not null)),
    '0', null
  union all select 8, '열린 페이지의 칸 (맨 위 칸 / member 칸이 다른 페이지 수)',
    (select count(*) filter (where (select array_agg(k order by k) from jsonb_object_keys(j) k) <> array['items', 'member', 'page', 'size', 'total'])
            || ' / ' || count(*) filter (where (select array_agg(k order by k) from jsonb_object_keys(j -> 'member') k) <> array['id', 'main_title', 'nickname', 'photo_path', 'titles'])
       from mp where j is not null),
    '0 / 0', '이메일·가입일시·역할·레벨·운영 정보는 칸 자체가 없다'
  union all select 9, '열린 페이지의 빌드 수 = 공개 빌드 수 (다른 수 / 1쪽 빌드가 공개 빌드가 아닌 수)',
    (select count(*) filter (where (j ->> 'total')::bigint <> n) from mp where j is not null)
      || ' / ' || (select count(*) from mp, jsonb_array_elements(mp.j -> 'items') e
                    join public.builds b on b.id = (e ->> 'id')::bigint join public.counters c on c.id = b.counter_id
                   where mp.j is not null and (b.status <> 'approved' or c.status <> 'approved' or b.author_id <> mp.id)),
    '0 / 0', null
  union all select 10, '비교: 쓰기 함수 수 (전 3번)',
    (select count(*) from wf) || ' / '
      || (select count(*) from wf where wf.prosrc ~ '^\s*declare\s*\n\s*_can_write constant boolean := public\.assert_can_write\(\);'
                                     or wf.prosrc ~ '^\s*begin\s*\n\s*perform public\.assert_can_write\(\);')
      || ' / ' || (select count(*) from wf where exists (select 1 from public.restriction_exemptions e where e.kind = 'function' and e.name = wf.sig)),
    '(전 3번과 같음)', null
  union all select 11, '비교: 쓰기 함수 지문 (전 4번)',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a join wf on wf.sig = a.sig),
    '(전 4번과 같음)', null
  union all select 12, '비교: member_page를 뺀 읽기 함수 수 / 지문 (전 5번)',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a join rf on rf.sig = a.sig where a.sig <> 'member_page(text, integer)'),
    '(전 5번과 같음)', null
  union all select 13, '비교: member_page를 뺀 public의 모든 함수 수 / 지문 (전 6번)',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a where a.sig <> 'member_page(text, integer)'),
    '(전 6번과 같음)', '같으면 기존 함수는 하나도 안 바뀐 것'
  union all select 14, '비교: public 트리거 · 정책 (전 7번)',
    (select count(*) || ' / ' || left(md5(string_agg(tgrelid::regclass::text || pg_get_triggerdef(oid) || tgenabled::text, ',' order by tgrelid::regclass::text, tgname)), 12)
       from pg_trigger where not tgisinternal and tgrelid in (select oid from pg_class where relnamespace = 'public'::regnamespace))
      || ' · ' || (select count(*) || ' / ' || left(md5(string_agg(polrelid::regclass::text || polname || polcmd::text || coalesce(pg_get_expr(polqual, polrelid), '') || coalesce(pg_get_expr(polwithcheck, polrelid), ''), ',' order by polrelid::regclass::text, polname)), 12)
       from pg_policy where polrelid in (select oid from pg_class where relnamespace = 'public'::regnamespace)),
    '(전 7번과 같음)', null
  union all select 15, '비교: 허용 목록 · xp_rules(member_page_min_builds 뺌) (전 8번)',
    (select count(*) || ' / ' || left(md5(string_agg(kind || ':' || name || ':' || reason, ',' order by kind, name)), 12) from public.restriction_exemptions)
      || ' · ' || (select count(*) || ' / ' || left(md5(string_agg(key || ':' || value || ':' || note, ',' order by key)), 12) from public.xp_rules where key <> 'member_page_min_builds'),
    '(전 8번과 같음)', null
  union all select 16, '비교: 기존 푸시 판정 지문 (전 9번)',
    (select count(*) || ' / ' || md5(string_agg(p.id::text || ':' || k.k || ':' || public.push_wanted(p.id, k.k)::text, ',' order by p.id, k.k))
       from public.profiles p cross join kinds k)
      || ' · ' || (select count(*) || ' / ' || md5(string_agg(k || ':' || coalesce(public.push_group(k), '-'), ',' order by k)) from kinds),
    '(전 9번과 같음)', null
  union all select 17, '비교: 프로필 · 빌드 · 상대법 (전 10번)',
    (select count(*) || ' · ' || left(md5(coalesce(string_agg(p::text, '|' order by p.id), '')), 12) from public.profiles p)
      || ' / ' || (select count(*) || ' · ' || coalesce(max(id), 0) || ' · ' || left(md5(coalesce(string_agg(b.id || ':' || b.status || ':' || coalesce(b.author_id::text, '-'), '|' order by b.id), '')), 12) from public.builds b)
      || ' / ' || (select count(*) || ' · ' || left(md5(coalesce(string_agg(c.id || ':' || c.status, '|' order by c.id), '')), 12) from public.counters c),
    '(전 10번과 같음)', '사이트 활동이 있었으면 달라질 수 있음'
  union all select 18, '비교: 개인 페이지가 열린 사람 수 (전 11번 예상)',
    (select count(*)::text from mp where j is not null),
    '(전 11번과 같음)', '다르면 그 사이 빌드 등록·숨김·정지가 있었는지 확인'
) x
order by ord;
