-- =====================================================================
-- 075(일반 사용자 개인 페이지 member_page) 실행 "전" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 075를 실행하기 전에 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~2번: [지금 값]이 [정상 값]과 맞으면 075를 실행해도 된다. 다르면 실행하지 말고 알려 주세요.
--   - 3~12번은 "적어 둘 값"이다. 075 실행 뒤 check_member_page_after.sql의 「비교」 줄과 비교한다
--     (075는 xp_rules 한 줄과 읽기 함수 member_page 하나만 더한다 - 기존 함수·표·데이터는 그대로여야 한다).
--   - 함수 본문 지문은 줄바꿈 CR을 뺀 값으로 계산한다(SQL Editor가 CRLF로 붙여 넣어도 같은 값).
--   - 이메일·토큰·닉네임 같은 값 자체는 출력하지 않는다(개수·지문만).
--   - 사이트 활동(빌드 등록·숨김, 알림 설정 등)이 있으면 9~12번은 달라질 수 있다 - 사람이 적은 시간에 이어서 실행해 주세요.
-- =====================================================================
with
-- 일반 사용자(로그인·비로그인)가 부를 수 있는 쓰기 함수 (068 빠뜨림 방지 검사와 같은 대상: volatile, 트리거 아님)
wf as (
  select p.oid, p.proname || '(' || oidvectortypes(p.proargtypes) || ')' as sig, p.prosrc
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f' and p.provolatile = 'v' and p.prorettype <> 'trigger'::regtype
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))
),
-- 일반 사용자가 부를 수 있는 읽기 함수 (stable·immutable, 트리거 아님)
rf as (
  select p.proname || '(' || oidvectortypes(p.proargtypes) || ')' as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f' and p.provolatile in ('s', 'i') and p.prorettype <> 'trigger'::regtype
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))
),
-- public의 모든 함수 - 이름·인자·반환·본문·보안·search_path·권한
allf as (
  select p.proname || '(' || oidvectortypes(p.proargtypes) || ')' as sig,
         p.proname || '(' || oidvectortypes(p.proargtypes) || ')' || pg_get_function_result(p.oid) || p.provolatile::text
           || replace(p.prosrc, E'\r', '') || p.prosecdef::text || coalesce(array_to_string(p.proconfig, ','), '')
           || coalesce(array_to_string(p.proacl, ','), '') as body
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind in ('f', 'p')
),
-- 알림 종류 전체 (notifications_kind_check에서 읽음) + 없는 종류 하나
kinds as (
  select (regexp_matches(pg_get_constraintdef(oid), '''([a-z_]+)''', 'g'))[1] as k
    from pg_constraint where conname = 'notifications_kind_check' and conrelid = 'public.notifications'::regclass
  union select 'no_such_kind'
),
-- 사람마다 공개 빌드 수 (승인 빌드 + 승인 상대법 = builds 읽기 정책의 "누구나 보는 빌드")
pb as (
  select b.author_id as uid, count(*) as n
    from public.builds b join public.counters c on c.id = b.counter_id
   where b.status = 'approved' and c.status = 'approved' and b.author_id is not null
   group by b.author_id
)
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '074까지 실행됨 (push_settings.comments 칸 / push_wanted 본문)' as what,
    (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'push_settings' and column_name = 'comments')
      || ' / ' || coalesce((select case md5(replace(prosrc, E'\r', '')) when 'fa8eb83cd5786a7155e5f2439917b04e' then '074 본문'
                                     else '다름 ' || md5(replace(prosrc, E'\r', '')) end
                              from pg_proc where oid = to_regprocedure('public.push_wanted(uuid, text)')), '함수 없음') as now_value,
    '1 / 074 본문' as ok_value, '0이면 074부터 실행' as memo
  union all select 2, 'member_page 함수 / 설정값 member_page_min_builds',
    case when to_regprocedure('public.member_page(text, integer)') is null then '없음' else '있음' end
      || ' / ' || coalesce((select value::text from public.xp_rules where key = 'member_page_min_builds'), '없음'),
    '없음 / 없음', '「있음」이면 075를 이미 실행한 것 - 다시 실행하지 마세요'
  union all select 3, '적어 둘 값: 쓰기 함수 수 (전체 / 첫 줄에 assert_can_write 검사 / 허용 목록)',
    (select count(*) from wf) || ' / '
      || (select count(*) from wf where wf.prosrc ~ '^\s*declare\s*\n\s*_can_write constant boolean := public\.assert_can_write\(\);'
                                     or wf.prosrc ~ '^\s*begin\s*\n\s*perform public\.assert_can_write\(\);')
      || ' / ' || (select count(*) from wf where exists (select 1 from public.restriction_exemptions e where e.kind = 'function' and e.name = wf.sig)),
    '103 / 30 / 73 (예상)', '075 뒤에도 103 / 30 / 73이어야 한다 (member_page는 읽기 함수)'
  union all select 4, '적어 둘 값: 쓰기 함수의 이름·본문·보안·search_path·권한 지문 (CR 뺌)',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a join wf on wf.sig = a.sig),
    '(이 값을 적어 둠)', '실행 뒤: 같은 수·같은 지문'
  union all select 5, '적어 둘 값: 읽기 함수 수 / 지문 (CR 뺌)',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a join rf on rf.sig = a.sig),
    '65 / (이 값을 적어 둠)', '실행 뒤: 66개, member_page를 빼면 같은 지문'
  union all select 6, '적어 둘 값: public의 모든 함수 수 / 지문 (CR 뺌)',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a),
    '(이 값을 적어 둠)', '실행 뒤: member_page를 빼면 같은 수·같은 지문 (기존 함수 본문이 하나도 안 바뀜)'
  union all select 7, '적어 둘 값: public 트리거 수 / 지문 · 정책 수 / 지문',
    (select count(*) || ' / ' || left(md5(string_agg(tgrelid::regclass::text || pg_get_triggerdef(oid) || tgenabled::text, ',' order by tgrelid::regclass::text, tgname)), 12)
       from pg_trigger where not tgisinternal and tgrelid in (select oid from pg_class where relnamespace = 'public'::regnamespace))
      || ' · ' || (select count(*) || ' / ' || left(md5(string_agg(polrelid::regclass::text || polname || polcmd::text || coalesce(pg_get_expr(polqual, polrelid), '') || coalesce(pg_get_expr(polwithcheck, polrelid), ''), ',' order by polrelid::regclass::text, polname)), 12)
       from pg_policy where polrelid in (select oid from pg_class where relnamespace = 'public'::regnamespace)),
    '(이 값을 적어 둠)', '075는 트리거·정책을 바꾸지 않는다'
  union all select 8, '적어 둘 값: 허용 목록(restriction_exemptions) 줄 수 / 지문 · xp_rules 줄 수 / 지문',
    (select count(*) || ' / ' || left(md5(string_agg(kind || ':' || name || ':' || reason, ',' order by kind, name)), 12) from public.restriction_exemptions)
      || ' · ' || (select count(*) || ' / ' || left(md5(string_agg(key || ':' || value || ':' || note, ',' order by key)), 12) from public.xp_rules),
    '(이 값을 적어 둠)', '실행 뒤: 허용 목록 같음, xp_rules는 member_page_min_builds 줄을 빼면 같음'
  union all select 9, '적어 둘 값: 기존 푸시 판정 지문 - 모든 사람 × 모든 알림 종류의 push_wanted 결과 · 종류별 push_group',
    (select count(*) || ' / ' || md5(string_agg(p.id::text || ':' || k.k || ':' || public.push_wanted(p.id, k.k)::text, ',' order by p.id, k.k))
       from public.profiles p cross join kinds k)
      || ' · ' || (select count(*) || ' / ' || md5(string_agg(k || ':' || coalesce(public.push_group(k), '-'), ',' order by k)) from kinds),
    '(이 값을 적어 둠)', '실행 뒤: 같은 값'
  union all select 10, '적어 둘 값: 프로필 수 · 지문 / 빌드 수 · 가장 큰 id · 지문 / 상대법 수 · 지문',
    (select count(*) || ' · ' || left(md5(coalesce(string_agg(p::text, '|' order by p.id), '')), 12) from public.profiles p)
      || ' / ' || (select count(*) || ' · ' || coalesce(max(id), 0) || ' · ' || left(md5(coalesce(string_agg(b.id || ':' || b.status || ':' || coalesce(b.author_id::text, '-'), '|' order by b.id), '')), 12) from public.builds b)
      || ' / ' || (select count(*) || ' · ' || left(md5(coalesce(string_agg(c.id || ':' || c.status, '|' order by c.id), '')), 12) from public.counters c),
    '(이 값을 적어 둠)', '075는 데이터를 바꾸지 않는다 (사이트 활동으로 달라질 수 있음)'
  union all select 11, '예상: 개인 페이지가 열릴 사람 수 (일반 사용자·닉네임 있음·비회원 아님·운영자 아님·지금 정지 아님·공개 빌드 5개 이상)',
    (select count(*)::text from public.profiles p join pb on pb.uid = p.id
      where p.nickname is not null and not p.is_guest and p.role <> 'admin' and p.influencer is null
        and pb.n >= 5 and public.active_restriction_id(p.id) is null),
    '(이 값을 적어 둠)', '실행 뒤: member_page가 null이 아닌 사람 수와 같아야 한다'
  union all select 12, '참고: 공개 빌드 5개 이상인데 닫히는 사람 수 (장인 / 정지 중 / 운영자·비회원·닉네임 없음)',
    (select count(*) filter (where p.influencer is not null) || ' / '
            || count(*) filter (where p.influencer is null and public.active_restriction_id(p.id) is not null) || ' / '
            || count(*) filter (where p.role = 'admin' or p.is_guest or p.nickname is null)
       from public.profiles p join pb on pb.uid = p.id where pb.n >= 5),
    '(참고)', '장인은 기존 장인 페이지(/u/:id)로 열린다'
) x
order by ord;
