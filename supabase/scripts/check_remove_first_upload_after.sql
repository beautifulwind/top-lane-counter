-- =====================================================================
-- 077(칭호 「첫 발자국」 first_upload 삭제) 실행 "뒤" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 077을 실행한 뒤 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~4번: [지금 값]이 [정상 값]과 같아야 한다.
--   - 5~17번 「비교」: check_remove_first_upload_before.sql에서 적어 둔 같은 번호와 같아야 한다.
--   - 함수 본문 지문은 CR을 뺀 값. 이메일·토큰·닉네임 같은 값 자체는 출력하지 않는다(개수·지문만).
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
-- 077이 지우는 알림 문장 (076이 만든 문장 그대로 - 이것과 정확히 같은 줄만 지운다)
fm as (select '칭호 ''첫 발자국''을 얻었습니다. [마이페이지]에서 대표 칭호로 고를 수 있습니다.'::text as msg),
-- 다른 칭호 알림 (칭호 얻음·회수 중 위 문장이 아닌 것)
other_notes as (select n.* from public.notifications n, fm where n.kind in ('title_earned', 'title_revoked') and n.message <> fm.msg)
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, 'grant_kept_titles 본문 / sync_rewards 본문' as what,
    coalesce((select case md5(replace(prosrc, E'\r', '')) when '3370625539c7ce4bd794a96b4609b03f' then '077 본문'
                       when '55a61ba9297a02073f7b09756c7d4360' then '076 본문 (077 안 됨)' else '다름 ' || md5(replace(prosrc, E'\r', '')) end
              from pg_proc where oid = to_regprocedure('public.grant_kept_titles(uuid, boolean)')), '함수 없음')
      || ' / ' || coalesce((select case md5(replace(prosrc, E'\r', '')) when 'd31e09d02d8344c09ec4adc3a2a00992' then '076 본문 (그대로)' else '다름' end
              from pg_proc where oid = to_regprocedure('public.sync_rewards(uuid, boolean)')), '함수 없음') as now_value,
    '077 본문 / 076 본문 (그대로)' as ok_value, 'sync_rewards의 유지 칭호 제외 줄은 builder 때문에 그대로' as memo
  union all select 2, 'first_upload 도감 줄 / 받은 줄 / 대표 칭호 / 지울 문장의 알림 / 「첫 발자국」이 들어간 칭호 알림',
    (select count(*) from public.title_catalog where key = 'first_upload') || ' / '
      || (select count(*) from public.user_titles where title_key = 'first_upload') || ' / '
      || (select count(*) from public.profiles where main_title = 'first_upload') || ' / '
      || (select count(*) from public.notifications n, fm where n.kind = 'title_earned' and n.message = fm.msg) || ' / '
      || (select count(*) from public.notifications where kind in ('title_earned', 'title_revoked') and message like '%첫 발자국%'),
    '0 / 0 / 0 / 0 / 0', null
  union all select 3, '트리거: edit_proposals_kept_titles / builds_kept_titles·counters_kept_titles (켜짐)',
    (select count(*) from pg_trigger where tgname = 'edit_proposals_kept_titles' and not tgisinternal) || ' / '
      || (select count(*) from pg_trigger where tgname in ('builds_kept_titles', 'counters_kept_titles') and not tgisinternal and tgenabled = 'O'),
    '0 / 2', '빌드 설계자는 그대로 동작'
  union all select 4, '빌드 설계자: 도감 줄 / title_builder / 조건(공개 빌드 기준 이상)을 채웠는데 없는 사람 수',
    (select count(*) from public.title_catalog where key = 'builder' and permanent) || ' / ' || coalesce((select value::text from public.xp_rules where key = 'title_builder'), '없음')
      || ' / ' || (select count(*) from public.profiles p where p.role <> 'admin'
                    and (select count(*) from public.builds b join public.counters c on c.id = b.counter_id
                          where b.author_id = p.id and b.status = 'approved' and c.status = 'approved') >= public.xp_rule('title_builder')
                    and not exists (select 1 from public.user_titles t where t.user_id = p.id and t.title_key = 'builder')),
    '1 / 10 / 0', null
  union all select 5, '비교: 쓰기 함수 수 (전체 / 첫 줄에 assert_can_write 검사 / 허용 목록)',
    (select count(*) from wf) || ' / '
      || (select count(*) from wf where wf.prosrc ~ '^\s*declare\s*\n\s*_can_write constant boolean := public\.assert_can_write\(\);'
                                     or wf.prosrc ~ '^\s*begin\s*\n\s*perform public\.assert_can_write\(\);')
      || ' / ' || (select count(*) from wf where exists (select 1 from public.restriction_exemptions e where e.kind = 'function' and e.name = wf.sig)),
    '103 / 30 / 73 (전 5번과 같음)', null
  union all select 6, '비교: 쓰기 함수 지문 (CR 뺌)',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a join wf on wf.sig = a.sig),
    '(전 6번과 같음)', null
  union all select 7, '비교: 읽기 함수 수 / 지문 (CR 뺌)',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a join rf on rf.sig = a.sig),
    '66 / (전 7번과 같음)', '66개'
  union all select 8, '비교: grant_kept_titles를 뺀 public의 모든 함수 수 / 지문 (CR 뺌)',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a where a.sig <> 'grant_kept_titles(uuid, boolean)'),
    '(전 8번과 같음)', '같으면 grant_kept_titles 말고는 함수가 하나도 안 바뀐 것 (sync_rewards 포함)'
  union all select 9, '비교: grant_kept_titles 본문 밖 속성 (반환 · volatile · security definer · search_path · 권한 · 소유자)',
    (select pg_get_function_result(oid) || ' · ' || provolatile::text || ' · ' || prosecdef::text || ' · ' || coalesce(array_to_string(proconfig, ','), '없음')
            || ' · ' || coalesce(array_to_string(proacl, ','), '기본') || ' · ' || pg_get_userbyid(proowner)
       from pg_proc where oid = to_regprocedure('public.grant_kept_titles(uuid, boolean)')),
    '(전 9번과 같음)', '본문만 바뀌고 이 줄은 같아야 한다'
  union all select 10, '비교: 푸시 판정 지문 - 모든 사람 × 모든 알림 종류의 push_wanted 결과 · 종류별 push_group',
    (select count(*) || ' / ' || md5(string_agg(p.id::text || ':' || k.k || ':' || public.push_wanted(p.id, k.k)::text, ',' order by p.id, k.k))
       from public.profiles p cross join kinds k)
      || ' · ' || (select count(*) || ' / ' || md5(string_agg(k || ':' || coalesce(public.push_group(k), '-'), ',' order by k)) from kinds),
    '(전 10번과 같음)', null
  union all select 11, '비교: 허용 목록(restriction_exemptions) 줄 수 / 지문 · xp_rules 줄 수 / 지문',
    (select count(*) || ' / ' || left(md5(string_agg(kind || ':' || name || ':' || reason, ',' order by kind, name)), 12) from public.restriction_exemptions)
      || ' · ' || (select count(*) || ' / ' || left(md5(string_agg(key || ':' || value || ':' || note, ',' order by key)), 12) from public.xp_rules),
    '(전 11번과 같음)', '077은 둘 다 바꾸지 않는다 (title_builder 유지)'
  union all select 12, '비교: 다른 칭호 도감 줄 (first_upload 뺌) 수 / 지문',
    (select count(*) || ' / ' || left(md5(string_agg(c.key || ':' || c.name || ':' || c.kind || ':' || c.equippable || ':' || c.permanent || ':' || c.sort_order || ':' || c.secret || ':' || c.hidden || ':' || coalesce(c.icon, '') || ':' || coalesce(c.color, '') || ':' || c.how_to, ',' order by c.key)), 12)
       from public.title_catalog c where c.key <> 'first_upload'),
    '(전 12번과 같음)', null
  union all select 13, '비교: 다른 칭호 받은 줄 (first_upload 뺌) - 칭호별 수 / 지문',
    (select coalesce(string_agg(title_key || ' ' || n, ', ' order by title_key), '없음') from (select title_key, count(*) n from public.user_titles where title_key <> 'first_upload' group by 1) x)
      || ' / ' || (select left(md5(coalesce(string_agg(user_id || ':' || title_key || ':' || earned_at, ',' order by user_id, title_key), '')), 12) from public.user_titles where title_key <> 'first_upload'),
    '(전 13번과 같음)', '기존 6개·builder·한정판 줄이 한 줄도 안 바뀜'
  union all select 14, '비교: first_upload가 아닌 대표 칭호 수 / 지문',
    (select count(*) || ' / ' || left(md5(coalesce(string_agg(id || ':' || main_title, ',' order by id), '')), 12) from public.profiles where main_title is not null and main_title <> 'first_upload'),
    '(전 14번과 같음)', null
  union all select 15, '비교: 다른 칭호 알림 (칭호 얻음·회수 중 첫 발자국 문장이 아닌 것) 수 / 지문',
    (select count(*) || ' / ' || left(md5(coalesce(string_agg(id || ':' || user_id || ':' || kind || ':' || message || ':' || created_at, ',' order by id), '')), 12) from other_notes),
    '(전 15번과 같음)', '다른 칭호 알림은 한 건도 지우지 않는다 (읽음 표시는 지문에 넣지 않음)'
  union all select 16, '비교: 알림 전체 수 (칭호 알림 아닌 것) · 가장 큰 id',
    (select count(*) || ' · ' || coalesce(max(id), 0) from public.notifications where kind not in ('title_earned', 'title_revoked')),
    '(전 16번과 같음)', '077은 칭호 알림 말고는 건드리지 않는다 (사이트 활동으로 늘 수 있음)'
  union all select 17, '비교: public 트리거 (edit_proposals_kept_titles 뺌) 수 / 지문 · 정책 수 / 지문',
    (select count(*) || ' / ' || left(md5(string_agg(tgrelid::regclass::text || pg_get_triggerdef(oid) || tgenabled::text, ',' order by tgrelid::regclass::text, tgname)), 12)
       from pg_trigger where not tgisinternal and tgname <> 'edit_proposals_kept_titles' and tgrelid in (select oid from pg_class where relnamespace = 'public'::regnamespace))
      || ' · ' || (select count(*) || ' / ' || left(md5(string_agg(polrelid::regclass::text || polname || polcmd::text || coalesce(pg_get_expr(polqual, polrelid), '') || coalesce(pg_get_expr(polwithcheck, polrelid), ''), ',' order by polrelid::regclass::text, polname)), 12)
       from pg_policy where polrelid in (select oid from pg_class where relnamespace = 'public'::regnamespace)),
    '(전 17번과 같음)', null
) x
order by ord;
