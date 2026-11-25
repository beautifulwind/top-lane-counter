-- =====================================================================
-- 076(칭호 개편 - 유지 칭호 「첫 발자국」·「빌드 설계자」) 실행 "전" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 076을 실행하기 전에 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~3번: [지금 값]이 [정상 값]과 맞으면 076을 실행해도 된다. 다르면 실행하지 말고 알려 주세요.
--   - 4~14번은 "적어 둘 값"이다. 076 실행 뒤 check_kept_titles_after.sql의 「비교」 줄과 비교한다.
--   - 15~17번은 "소급 예상"이다. 076이 끝에서 조건을 이미 채운 사람에게 칭호를 주는데, 그 사람 수를 미리 센다.
--     실행 뒤 check_kept_titles_after.sql의 「소급 결과」가 이 수와 같아야 한다.
--   - 함수 본문 지문은 줄바꿈 CR을 뺀 값으로 계산한다(SQL Editor가 CRLF로 붙여 넣어도 같은 값).
--   - 이메일·토큰·닉네임 같은 값 자체는 출력하지 않는다(개수·지문만).
--   - 사이트 활동(빌드 등록·숨김, 알림 설정 등)이 있으면 9~17번은 달라질 수 있다 - 사람이 적은 시간에 이어서 실행해 주세요.
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
-- 076 소급과 같은 조건 (운영자 제외)
cand as (
  select p.id,
         (exists (select 1 from public.builds b where b.author_id = p.id and b.status <> 'hidden')
          or exists (select 1 from public.counters c where c.proposed_by = p.id and c.status <> 'hidden')
          or exists (select 1 from public.edit_proposals ep where ep.proposer_id = p.id and ep.type = 'new_counter' and ep.status <> 'revoked')) as first_upload,
         (select count(*) from public.builds b join public.counters c on c.id = b.counter_id
           where b.author_id = p.id and b.status = 'approved' and c.status = 'approved') >= 10 as builder
    from public.profiles p where p.role <> 'admin'
)
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '075까지 실행됨 (member_page 함수)' as what,
    case when to_regprocedure('public.member_page(text, integer)') is null then '없음' else '있음' end as now_value,
    '있음' as ok_value, '「없음」이면 075부터 실행' as memo
  union all select 2, 'sync_rewards 본문',
    coalesce((select case md5(replace(prosrc, E'\r', ''))
                       when 'c405f7913721afcaf02a560d0427dd40' then '076 전 본문'
                       when 'd31e09d02d8344c09ec4adc3a2a00992' then '076 이미 실행'
                       else '다름 ' || md5(replace(prosrc, E'\r', '')) end
                from pg_proc where oid = to_regprocedure('public.sync_rewards(uuid, boolean)')), '함수 없음'),
    '076 전 본문', '「다름」이면 실행하지 말고 알려 주세요 (076이 멈춘다)'
  union all select 3, 'title_catalog.permanent 칸 수 / 새 칭호 키 수 (first_upload·builder) / 설정값 title_builder / 그 키를 가진 사람 수',
    (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'title_catalog' and column_name = 'permanent')
      || ' / ' || (select count(*) from public.title_catalog where key in ('first_upload', 'builder'))
      || ' / ' || coalesce((select value::text from public.xp_rules where key = 'title_builder'), '없음')
      || ' / ' || (select count(*) from public.user_titles where title_key in ('first_upload', 'builder')),
    '0 / 0 / 없음 / 0', '0이 아니면 076을 이미 실행한 것'
  union all select 4, '적어 둘 값: 쓰기 함수 수 (전체 / 첫 줄에 assert_can_write 검사 / 허용 목록)',
    (select count(*) from wf) || ' / '
      || (select count(*) from wf where wf.prosrc ~ '^\s*declare\s*\n\s*_can_write constant boolean := public\.assert_can_write\(\);'
                                     or wf.prosrc ~ '^\s*begin\s*\n\s*perform public\.assert_can_write\(\);')
      || ' / ' || (select count(*) from wf where exists (select 1 from public.restriction_exemptions e where e.kind = 'function' and e.name = wf.sig)),
    '103 / 30 / 73 (예상)', '076 뒤에도 같아야 한다 (새 함수 2개는 실행 권한이 없다)'
  union all select 5, '적어 둘 값: 쓰기 함수 지문 (CR 뺌)',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a join wf on wf.sig = a.sig),
    '(이 값을 적어 둠)', null
  union all select 6, '적어 둘 값: 읽기 함수 수 / 지문 (CR 뺌)',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a join rf on rf.sig = a.sig),
    '66 / (이 값을 적어 둠)', '실행 뒤: 같은 수·같은 지문'
  union all select 7, '적어 둘 값: sync_rewards를 뺀 public의 모든 함수 수 / 지문 (CR 뺌)',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a where a.sig <> 'sync_rewards(uuid, boolean)'),
    '(이 값을 적어 둠)', '실행 뒤: 새 함수 2개(grant_kept_titles·kept_titles_on_change)를 빼면 같아야 한다'
  union all select 8, '적어 둘 값: sync_rewards 본문 밖 속성 (반환 · volatile · security definer · search_path · 권한 · 소유자)',
    (select pg_get_function_result(oid) || ' · ' || provolatile::text || ' · ' || prosecdef::text || ' · ' || coalesce(array_to_string(proconfig, ','), '없음')
            || ' · ' || coalesce(array_to_string(proacl, ','), '기본') || ' · ' || pg_get_userbyid(proowner)
       from pg_proc where oid = to_regprocedure('public.sync_rewards(uuid, boolean)')),
    '(이 값을 적어 둠)', '실행 뒤: 본문만 바뀌고 이 줄은 같아야 한다'
  union all select 9, '적어 둘 값: 기존 푸시 판정 지문 - 모든 사람 × 모든 알림 종류의 push_wanted 결과 · 종류별 push_group',
    (select count(*) || ' / ' || md5(string_agg(p.id::text || ':' || k.k || ':' || public.push_wanted(p.id, k.k)::text, ',' order by p.id, k.k))
       from public.profiles p cross join kinds k)
      || ' · ' || (select count(*) || ' / ' || md5(string_agg(k || ':' || coalesce(public.push_group(k), '-'), ',' order by k)) from kinds),
    '(이 값을 적어 둠)', '실행 뒤: 같은 값 (076은 푸시 함수를 고치지 않는다)'
  union all select 10, '적어 둘 값: push_group · push_wanted 본문 지문 / title_earned 묶음',
    (select md5(replace(prosrc, E'\r', '')) from pg_proc where oid = to_regprocedure('public.push_group(text)'))
      || ' · ' || (select md5(replace(prosrc, E'\r', '')) from pg_proc where oid = to_regprocedure('public.push_wanted(uuid, text)'))
      || ' / ' || coalesce(public.push_group('title_earned'), '없음'),
    '2be75ed999aa158e20557beda4db0814 · fa8eb83cd5786a7155e5f2439917b04e / 없음', '「없음」 = 칭호 알림은 휴대폰 알림이 나가지 않는다'
  union all select 11, '적어 둘 값: 도감(title_catalog) 줄 수 / 지문 · xp_rules 줄 수 / 지문 · 허용 목록 줄 수 / 지문',
    (select count(*) || ' / ' || left(md5(string_agg(c.key || ':' || c.name || ':' || c.kind || ':' || c.equippable || ':' || c.sort_order || ':' || c.secret || ':' || c.hidden || ':' || coalesce(c.icon, '') || ':' || coalesce(c.color, '') || ':' || c.how_to, ',' order by c.key)), 12) from public.title_catalog c)
      || ' · ' || (select count(*) || ' / ' || left(md5(string_agg(key || ':' || value || ':' || note, ',' order by key)), 12) from public.xp_rules)
      || ' · ' || (select count(*) || ' / ' || left(md5(string_agg(kind || ':' || name || ':' || reason, ',' order by kind, name)), 12) from public.restriction_exemptions),
    '(이 값을 적어 둠)', '실행 뒤: 새 2줄·title_builder를 빼면 같음, 허용 목록 같음'
  union all select 12, '적어 둘 값: 받은 칭호(user_titles) 줄 수 / 지문 · 대표 칭호 지문',
    (select count(*) || ' / ' || left(md5(coalesce(string_agg(user_id || ':' || title_key || ':' || earned_at, ',' order by user_id, title_key), '')), 12) from public.user_titles)
      || ' · ' || (select left(md5(coalesce(string_agg(id || ':' || coalesce(main_title, '-'), ',' order by id), '')), 12) from public.profiles),
    '(이 값을 적어 둠)', '실행 뒤: 새 2개 키를 빼면 같음 (이미 준 칭호·대표 칭호를 지우지 않음)'
  union all select 13, '적어 둘 값: public 트리거 수 / 지문 · 정책 수 / 지문',
    (select count(*) || ' / ' || left(md5(string_agg(tgrelid::regclass::text || pg_get_triggerdef(oid) || tgenabled::text, ',' order by tgrelid::regclass::text, tgname)), 12)
       from pg_trigger where not tgisinternal and tgrelid in (select oid from pg_class where relnamespace = 'public'::regnamespace))
      || ' · ' || (select count(*) || ' / ' || left(md5(string_agg(polrelid::regclass::text || polname || polcmd::text || coalesce(pg_get_expr(polqual, polrelid), '') || coalesce(pg_get_expr(polwithcheck, polrelid), ''), ',' order by polrelid::regclass::text, polname)), 12)
       from pg_policy where polrelid in (select oid from pg_class where relnamespace = 'public'::regnamespace)),
    '(이 값을 적어 둠)', '실행 뒤: 새 트리거 3개를 빼면 같음, 정책 같음'
  union all select 14, '적어 둘 값: 알림 전체 수 · 가장 큰 id / 칭호 얻음 알림 수',
    (select count(*) || ' · ' || coalesce(max(id), 0) from public.notifications)
      || ' / ' || (select count(*) from public.notifications where kind = 'title_earned'),
    '(이 값을 적어 둠)', '실행 뒤: 칭호 얻음 알림이 17번 수만큼 늘어난다'
  union all select 15, '소급 예상: 「첫 발자국」 받을 사람 수 (운영자 제외, 숨김 처리된 것만 올린 사람 제외)',
    (select count(*)::text from cand where first_upload), '(이 값을 적어 둠)', '실행 뒤 「소급 결과」와 같아야 한다'
  union all select 16, '소급 예상: 「빌드 설계자」 받을 사람 수 (공개 빌드 10개 이상)',
    (select count(*)::text from cand where builder), '(이 값을 적어 둠)', '실행 뒤 「소급 결과」와 같아야 한다'
  union all select 17, '소급 예상: 줄 칭호 합계 = 새 알림 줄 수',
    (select (count(*) filter (where first_upload) + count(*) filter (where builder))::text from cand), '(이 값을 적어 둠)', '휴대폰 알림은 0건'
) x
order by ord;
