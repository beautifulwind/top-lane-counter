-- =====================================================================
-- 076(칭호 개편 - 유지 칭호 「첫 발자국」·「빌드 설계자」) 실행 "뒤" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 076을 실행한 뒤 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~11번: [지금 값]이 [정상 값]과 같아야 한다.
--   - 12~21번 「비교」: check_kept_titles_before.sql에서 적어 둔 같은 항목(4~14번)과 같아야 한다.
--   - 22~24번 「소급 결과」: 실행 전 15~17번 「소급 예상」과 같아야 한다.
--   - 이메일·토큰·닉네임 같은 값 자체는 출력하지 않는다(개수·지문만). 함수 본문 지문은 CR을 뺀 값.
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
newf as (select unnest(array['sync_rewards(uuid, boolean)', 'grant_kept_titles(uuid, boolean)', 'kept_titles_on_change()']) as sig),
newfn as (select oid from pg_proc where oid in (to_regprocedure('public.grant_kept_titles(uuid, boolean)'), to_regprocedure('public.kept_titles_on_change()'))),
newtg as (select unnest(array['builds_kept_titles', 'counters_kept_titles', 'edit_proposals_kept_titles']) as tgname),
kinds as (
  select (regexp_matches(pg_get_constraintdef(oid), '''([a-z_]+)''', 'g'))[1] as k
    from pg_constraint where conname = 'notifications_kind_check' and conrelid = 'public.notifications'::regclass
  union select 'no_such_kind'
),
-- 지금 조건 (076과 같은 식, 운영자 제외)
cand as (
  select p.id,
         (exists (select 1 from public.builds b where b.author_id = p.id and b.status <> 'hidden')
          or exists (select 1 from public.counters c where c.proposed_by = p.id and c.status <> 'hidden')
          or exists (select 1 from public.edit_proposals ep where ep.proposer_id = p.id and ep.type = 'new_counter' and ep.status <> 'revoked')) as first_upload,
         (select count(*) from public.builds b join public.counters c on c.id = b.counter_id
           where b.author_id = p.id and b.status = 'approved' and c.status = 'approved') >= public.xp_rule('title_builder') as builder
    from public.profiles p where p.role <> 'admin'
),
sr as (select replace(prosrc, E'\r', '') as src from pg_proc where oid = to_regprocedure('public.sync_rewards(uuid, boolean)'))
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, 'sync_rewards 본문 / 076 줄을 되돌린 지문' as what,
    (select case md5(src) when 'd31e09d02d8344c09ec4adc3a2a00992' then '076 본문' else '다름 ' || md5(src) end
            || ' / ' || md5(replace(src,
                 $s$and c.kind = 'activity' and not c.permanent and not (ut.title_key = any (want)) loop  -- 053: 활동 칭호만 회수, 076: 유지 칭호 제외$s$,
                 $s$and c.kind = 'activity' and not (ut.title_key = any (want)) loop  -- 053: 활동 칭호만 회수$s$))
       from sr) as now_value,
    '076 본문 / c405f7913721afcaf02a560d0427dd40' as ok_value, '뒤 값이 076 전 지문 = 바뀐 곳은 그 한 줄뿐' as memo
  union all select 2, '도감 새 2줄 (키:이름:종류:장착:유지:순서)',
    (select string_agg(key || ':' || name || ':' || kind || ':' || equippable || ':' || permanent || ':' || sort_order, ' | ' order by sort_order)
       from public.title_catalog where key in ('first_upload', 'builder')),
    'first_upload:첫 발자국:activity:true:true:5 | builder:빌드 설계자:activity:true:true:65', null
  union all select 3, '유지 칭호(permanent) 수 / 칸 기본값 / 설정값 title_builder',
    (select count(*) from public.title_catalog where permanent)
      || ' / ' || (select column_default || ' ' || is_nullable from information_schema.columns
                    where table_schema = 'public' and table_name = 'title_catalog' and column_name = 'permanent')
      || ' / ' || coalesce((select value::text from public.xp_rules where key = 'title_builder'), '없음'),
    '2 / false NO / 10', null
  union all select 4, '새 함수 2개: 수 / 비로그인·로그인 실행 가능 수 / public 기본 권한 / security definer·search_path',
    (select count(*) || ' / ' || count(*) filter (where has_function_privilege('anon', oid, 'execute') or has_function_privilege('authenticated', oid, 'execute'))
            || ' / ' || count(*) filter (where exists (select 1 from unnest(proacl) a where a::text like '=%'))
            || ' / ' || bool_and(prosecdef and proconfig = array['search_path=""'])::text
       from pg_proc where oid in (select oid from newfn)),
    '2 / 0 / 0 / true', '내부 함수 - 클라이언트가 부를 수 없다'
  union all select 5, '새 트리거 3개: 수 / deferrable initially deferred / 켜짐',
    (select count(*) || ' / ' || bool_and(tgdeferrable and tginitdeferred)::text || ' / ' || bool_and(tgenabled = 'O')::text
       from pg_trigger where tgname in (select tgname from newtg) and not tgisinternal),
    '3 / true / true', null
  union all select 6, '쓰기 함수 수 (전체 / 첫 줄 검사 / 허용 목록)',
    (select count(*) from wf) || ' / '
      || (select count(*) from wf where wf.prosrc ~ '^\s*declare\s*\n\s*_can_write constant boolean := public\.assert_can_write\(\);'
                                     or wf.prosrc ~ '^\s*begin\s*\n\s*perform public\.assert_can_write\(\);')
      || ' / ' || (select count(*) from wf where exists (select 1 from public.restriction_exemptions e where e.kind = 'function' and e.name = wf.sig)),
    '103 / 30 / 73', null
  union all select 7, '빠뜨림 방지: 검사도 허용 목록도 없는 쓰기 함수 수',
    (select count(*)::text from wf where not (wf.prosrc ~ '^\s*declare\s*\n\s*_can_write constant boolean := public\.assert_can_write\(\);'
                                             or wf.prosrc ~ '^\s*begin\s*\n\s*perform public\.assert_can_write\(\);')
                                     and not exists (select 1 from public.restriction_exemptions e where e.kind = 'function' and e.name = wf.sig)),
    '0', null
  union all select 8, '칭호 알림 묶음 (title_earned / title_revoked) / 칭호 알림을 휴대폰으로 받을 사람 수',
    coalesce(public.push_group('title_earned'), '없음') || ' · ' || coalesce(public.push_group('title_revoked'), '없음')
      || ' / ' || (select count(*) from public.profiles p where public.push_wanted(p.id, 'title_earned') or public.push_wanted(p.id, 'title_revoked')),
    '없음 · 없음 / 0', '칭호 알림은 앱 안 알림 목록에만'
  union all select 9, '조건을 채웠는데 칭호가 없는 사람 수 (첫 발자국 / 빌드 설계자)',
    (select count(*) filter (where first_upload and not exists (select 1 from public.user_titles t where t.user_id = cand.id and t.title_key = 'first_upload'))
            || ' / ' || count(*) filter (where builder and not exists (select 1 from public.user_titles t where t.user_id = cand.id and t.title_key = 'builder'))
       from cand),
    '0 / 0', null
  union all select 10, '운영자가 가진 새 칭호 수 / 같은 사람·같은 칭호 중복 수',
    (select count(*) from public.user_titles t join public.profiles p on p.id = t.user_id where p.role = 'admin' and t.title_key in ('first_upload', 'builder'))
      || ' / ' || (select count(*) from (select user_id, title_key from public.user_titles group by 1, 2 having count(*) > 1) d),
    '0 / 0', '중복은 기본 키가 막는다'
  union all select 11, '새 칭호 알림 수 = 새 칭호 줄 수 (알림 / 칭호 줄)',
    (select count(*) from public.notifications where kind = 'title_earned' and (message like '칭호 ''첫 발자국''%' or message like '칭호 ''빌드 설계자''%'))
      || ' / ' || (select count(*) from public.user_titles where title_key in ('first_upload', 'builder')),
    '(두 수가 같음)', '사람이 알림을 지우면 알림 쪽이 작을 수 있음'
  union all select 12, '비교: 쓰기 함수 수 (전 4번)',
    (select count(*) from wf) || ' / '
      || (select count(*) from wf where wf.prosrc ~ '^\s*declare\s*\n\s*_can_write constant boolean := public\.assert_can_write\(\);'
                                     or wf.prosrc ~ '^\s*begin\s*\n\s*perform public\.assert_can_write\(\);')
      || ' / ' || (select count(*) from wf where exists (select 1 from public.restriction_exemptions e where e.kind = 'function' and e.name = wf.sig)),
    '(전 4번과 같음)', null
  union all select 13, '비교: 쓰기 함수 지문 (전 5번)',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a join wf on wf.sig = a.sig),
    '(전 5번과 같음)', null
  union all select 14, '비교: 읽기 함수 수 / 지문 (전 6번)',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a join rf on rf.sig = a.sig),
    '(전 6번과 같음)', null
  union all select 15, '비교: sync_rewards·새 함수 2개를 뺀 public의 모든 함수 수 / 지문 (전 7번)',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a where a.sig not in (select sig from newf)),
    '(전 7번과 같음)', '같으면 sync_rewards 말고는 기존 함수가 하나도 안 바뀐 것'
  union all select 16, '비교: sync_rewards 본문 밖 속성 (전 8번)',
    (select pg_get_function_result(oid) || ' · ' || provolatile::text || ' · ' || prosecdef::text || ' · ' || coalesce(array_to_string(proconfig, ','), '없음')
            || ' · ' || coalesce(array_to_string(proacl, ','), '기본') || ' · ' || pg_get_userbyid(proowner)
       from pg_proc where oid = to_regprocedure('public.sync_rewards(uuid, boolean)')),
    '(전 8번과 같음)', null
  union all select 17, '비교: 기존 푸시 판정 지문 (전 9번)',
    (select count(*) || ' / ' || md5(string_agg(p.id::text || ':' || k.k || ':' || public.push_wanted(p.id, k.k)::text, ',' order by p.id, k.k))
       from public.profiles p cross join kinds k)
      || ' · ' || (select count(*) || ' / ' || md5(string_agg(k || ':' || coalesce(public.push_group(k), '-'), ',' order by k)) from kinds),
    '(전 9번과 같음)', '같으면 모든 사람 × 모든 종류의 푸시 판정이 한 건도 안 바뀐 것'
  union all select 18, '비교: push_group · push_wanted 본문 지문 / title_earned 묶음 (전 10번)',
    (select md5(replace(prosrc, E'\r', '')) from pg_proc where oid = to_regprocedure('public.push_group(text)'))
      || ' · ' || (select md5(replace(prosrc, E'\r', '')) from pg_proc where oid = to_regprocedure('public.push_wanted(uuid, text)'))
      || ' / ' || coalesce(public.push_group('title_earned'), '없음'),
    '(전 10번과 같음)', null
  union all select 19, '비교: 도감(새 2줄 뺌, permanent 칸 뺌) · xp_rules(title_builder 뺌) · 허용 목록 (전 11번)',
    (select count(*) || ' / ' || left(md5(string_agg(c.key || ':' || c.name || ':' || c.kind || ':' || c.equippable || ':' || c.sort_order || ':' || c.secret || ':' || c.hidden || ':' || coalesce(c.icon, '') || ':' || coalesce(c.color, '') || ':' || c.how_to, ',' order by c.key)), 12)
       from public.title_catalog c where c.key not in ('first_upload', 'builder'))
      || ' · ' || (select count(*) || ' / ' || left(md5(string_agg(key || ':' || value || ':' || note, ',' order by key)), 12) from public.xp_rules where key <> 'title_builder')
      || ' · ' || (select count(*) || ' / ' || left(md5(string_agg(kind || ':' || name || ':' || reason, ',' order by kind, name)), 12) from public.restriction_exemptions),
    '(전 11번과 같음)', null
  union all select 20, '비교: 받은 칭호(새 2개 키 뺌) · 대표 칭호 (전 12번)',
    (select count(*) || ' / ' || left(md5(coalesce(string_agg(user_id || ':' || title_key || ':' || earned_at, ',' order by user_id, title_key), '')), 12)
       from public.user_titles where title_key not in ('first_upload', 'builder'))
      || ' · ' || (select left(md5(coalesce(string_agg(id || ':' || coalesce(main_title, '-'), ',' order by id), '')), 12) from public.profiles),
    '(전 12번과 같음)', '이미 준 칭호·대표 칭호를 지우지 않았다 (사이트 활동으로 기존 칭호가 바뀌면 달라질 수 있음)'
  union all select 21, '비교: 새 트리거 3개를 뺀 public 트리거 · 정책 (전 13번)',
    (select count(*) || ' / ' || left(md5(string_agg(tgrelid::regclass::text || pg_get_triggerdef(oid) || tgenabled::text, ',' order by tgrelid::regclass::text, tgname)), 12)
       from pg_trigger where not tgisinternal and tgrelid in (select oid from pg_class where relnamespace = 'public'::regnamespace)
        and tgname not in (select tgname from newtg))
      || ' · ' || (select count(*) || ' / ' || left(md5(string_agg(polrelid::regclass::text || polname || polcmd::text || coalesce(pg_get_expr(polqual, polrelid), '') || coalesce(pg_get_expr(polwithcheck, polrelid), ''), ',' order by polrelid::regclass::text, polname)), 12)
       from pg_policy where polrelid in (select oid from pg_class where relnamespace = 'public'::regnamespace)),
    '(전 13번과 같음)', null
  union all select 22, '소급 결과: 「첫 발자국」 가진 사람 수 (전 15번)',
    (select count(*)::text from public.user_titles where title_key = 'first_upload'), '(전 15번과 같음)', '그 사이 새로 올린 사람이 있으면 그만큼 많을 수 있음'
  union all select 23, '소급 결과: 「빌드 설계자」 가진 사람 수 (전 16번)',
    (select count(*)::text from public.user_titles where title_key = 'builder'), '(전 16번과 같음)', null
  union all select 24, '소급 결과: 칭호 얻음 알림 수 (전체) / 새 칭호 줄 합계',
    (select count(*) from public.notifications where kind = 'title_earned')
      || ' / ' || (select count(*) from public.user_titles where title_key in ('first_upload', 'builder')),
    '(전 14번 뒤 값 + 전 17번) / (전 17번)', '알림은 앱 안 목록에만 - 휴대폰 알림은 8번에서 0명'
) x
order by ord;
