-- =====================================================================
-- 074(댓글·답글 푸시 묶음 comments) 실행 "뒤" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다). 운영 DB에서 언제 다시 실행해도 된다.
-- 074를 실행한 "직후" SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~10번: [지금 값]이 [정상 값]과 모두 맞아야 한다. 하나라도 다르면 알려 주세요.
--   - 11~22번: 실행 전 check_comment_push_before.sql의 4~15번에 적어 둔 값과 비교한다(각 줄의 [정상 값]에 무엇과 같아야 하는지 적었다).
--   - 함수 본문 지문은 줄바꿈 CR을 뺀 값으로 계산한다(SQL Editor가 CRLF로 붙여 넣어도 같은 값).
--   - 토큰·endpoint 값 자체는 출력하지 않는다(개수·지문만).
-- =====================================================================
with
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
rf as (
  select p.proname || '(' || oidvectortypes(p.proargtypes) || ')' as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f' and p.provolatile in ('s', 'i') and p.prorettype <> 'trigger'::regtype
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))
     and p.proname <> 'push_group'
),
allf as (
  select p.proname || '(' || oidvectortypes(p.proargtypes) || ')' as sig,
         p.proname || '(' || oidvectortypes(p.proargtypes) || ')' || pg_get_function_result(p.oid) || p.provolatile::text
           || replace(p.prosrc, E'\r', '') || p.prosecdef::text || coalesce(array_to_string(p.proconfig, ','), '')
           || coalesce(array_to_string(p.proacl, ','), '') as body
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind in ('f', 'p')
),
changed as (select unnest(array['push_group(text)', 'push_wanted(uuid, text)']) as sig),
pt as (select unnest(array['public.notifications', 'public.push_subscriptions', 'public.push_settings', 'public.device_push_tokens']::regclass[]) as rel),
kinds as (
  select k from (select (regexp_matches(pg_get_constraintdef(oid), '''([a-z_]+)''', 'g'))[1] as k
                   from pg_constraint where conname = 'notifications_kind_check' and conrelid = 'public.notifications'::regclass) x
  union select 'no_such_kind'
),
other_kinds as (select k from kinds where k not in ('post_comment', 'doc_comment', 'comment_reply')),
g as (select replace(prosrc, E'\r', '') as src from pg_proc where oid = to_regprocedure('public.push_group(text)')),
w as (select replace(prosrc, E'\r', '') as src from pg_proc where oid = to_regprocedure('public.push_wanted(uuid, text)'))
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '본문 지문 (push_group / push_wanted, CR 뺀 값)' as what,
    coalesce((select md5(src) from g), '함수 없음') || ' / ' || coalesce((select md5(src) from w), '함수 없음') as now_value,
    '2be75ed999aa158e20557beda4db0814 / fa8eb83cd5786a7155e5f2439917b04e' as ok_value, '파일 그대로 실행했으면 같음 (CRLF로 붙여 넣어도 같음)' as memo
  union all select 2, '더한 줄만 빼면 이전 본문 지문 (push_group → 069 / push_wanted → 073)',
    coalesce((select md5(replace(src, E'\n    when p_kind in (''post_comment'', ''doc_comment'', ''comment_reply'') then ''comments''  -- 074 댓글·답글', '')) from g), '함수 없음')
      || ' / ' || coalesce((select md5(replace(src, E'\n    when ''comments'' then\n      coalesce((select s.comments from public.push_settings s where s.user_id = p_user), true)  -- 074 댓글·답글', '')) from w), '함수 없음'),
    'ba44f97f41cc99cbb3590c8528ace024 / e6f1723ae3a6b0126ece4b51488a067c', '= 기존 묶음·운영자 모드·설정·기기 조건은 한 글자도 안 바뀜'
  union all select 3, '댓글 3종의 묶음 (post_comment · doc_comment · comment_reply)',
    coalesce(public.push_group('post_comment'), '없음') || ' · ' || coalesce(public.push_group('doc_comment'), '없음') || ' · ' || coalesce(public.push_group('comment_reply'), '없음'),
    'comments · comments · comments', null
  union all select 4, 'comments 묶음을 쓰는 종류 (전체)',
    coalesce((select string_agg(k, ', ' order by k) from kinds where public.push_group(k) = 'comments'), '없음'),
    'comment_reply, doc_comment, post_comment', '다른 종류가 이 묶음으로 오지 않음'
  union all select 5, '새 칸 push_settings.comments (자료형:null 허용:기본값 / 칸 설명 있음)',
    coalesce((select data_type || ':' || is_nullable || ':' || coalesce(column_default, '') from information_schema.columns
               where table_schema = 'public' and table_name = 'push_settings' and column_name = 'comments'), '칸 없음')
      || ' / ' || (col_description('public.push_settings'::regclass,
                     (select attnum from pg_attribute where attrelid = 'public.push_settings'::regclass and attname = 'comments')) is not null)::text,
    'boolean:NO:true / true', '기존 줄은 모두 켜짐으로 시작'
  union all select 6, '새 칸 권한 (로그인 update / 로그인 select / 비로그인 update) · 끈 사람 수',
    coalesce((select has_column_privilege('authenticated', 'public.push_settings', 'comments', 'update')::text
                     || ' / ' || has_column_privilege('authenticated', 'public.push_settings', 'comments', 'select')::text
                     || ' / ' || has_column_privilege('anon', 'public.push_settings', 'comments', 'update')::text
                where exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'push_settings' and column_name = 'comments')), '칸 없음')
      || ' · ' || coalesce((select count(*)::text from public.push_settings where not comments), '-'),
    'true / true / false · 0 (실행 직후)', '본인 줄만 바꿀 수 있음 (RLS 그대로). 그 뒤 설정에서 끄면 늘어난다'
  union all select 7, '두 함수 모양 (인자 · 반환 · volatile · security definer · search_path) · 같은 이름 함수 수',
    (select string_agg(oid::regprocedure::text || ' · ' || pg_get_function_result(oid) || ' · ' || provolatile::text || ' · ' || prosecdef::text
                     || ' · ' || coalesce(array_to_string(proconfig, ','), '없음'), ' | ' order by proname)
       from pg_proc where oid in (to_regprocedure('public.push_group(text)'), to_regprocedure('public.push_wanted(uuid, text)')))
      || ' · ' || (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('push_group', 'push_wanted')),
    'push_group(text) · text · i · false · search_path="" | push_wanted(uuid,text) · boolean · s · true · search_path="" · 2', null
  union all select 8, '알림 트리거 그대로 (notifications_push가 부르는 함수 / 켜짐) · push_wanted 실행 권한 (anon / authenticated)',
    coalesce((select tgfoid::regprocedure::text || ' / ' || tgenabled::text from pg_trigger where tgname = 'notifications_push' and tgrelid = 'public.notifications'::regclass), '없음')
      || ' · ' || has_function_privilege('anon', 'public.push_wanted(uuid, text)', 'execute')::text || ' / ' || has_function_privilege('authenticated', 'public.push_wanted(uuid, text)', 'execute')::text,
    'push_on_notification() / O · false / false', null
  union all select 9, '쓰기 함수 수 (전체 / 첫 줄 검사 / 허용 목록)',
    (select count(*) from wf) || ' / ' || (select count(*) from wf where state = 'checked') || ' / ' || (select count(*) from wf where state = 'exempt'),
    '103 / 30 / 73', '074는 쓰기 함수를 더하거나 바꾸지 않는다'
  union all select 10, '빠뜨림 방지: 쓰기 함수 중 통과 못 한 것',
    coalesce((select string_agg(sig || ' ' || state, ', ' order by sig) from wf where state not in ('checked', 'exempt')), '없음'),
    '없음', '068 check_restrictions_after.sql 5번과 같은 규칙'
  -- ===== 실행 전 값과 비교 =====
  union all select 11, '비교: 쓰기 함수 수 (전체 / 첫 줄 검사 / 허용 목록)',
    (select count(*) from wf) || ' / ' || (select count(*) from wf where state = 'checked') || ' / ' || (select count(*) from wf where state = 'exempt'),
    '실행 전 4번과 같음', null
  union all select 12, '비교: 쓰기 함수의 이름·본문·보안·search_path·권한 지문',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a join wf on wf.sig = a.sig),
    '실행 전 5번과 같음', null
  union all select 13, '비교: push_group·push_wanted를 뺀 public의 모든 함수 수 / 지문',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a where a.sig not in (select sig from changed)),
    '실행 전 6번과 같음', '다른 함수는 하나도 바뀌지 않았다'
  union all select 14, '비교: 발송·댓글 알림 함수 지문 (push_on_notification·push_targets·push_forget·notify_new_comment)',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a
      where split_part(a.sig, '(', 1) in ('push_on_notification', 'push_targets', 'push_forget', 'notify_new_comment')),
    '실행 전 7번과 같음', '받는 사람·합치기·문장은 그대로'
  union all select 15, '비교: push_group·push_wanted의 본문 밖 속성',
    (select string_agg(oid::regprocedure::text || ' · ' || pg_get_function_result(oid) || ' · ' || provolatile::text || ' · ' || prosecdef::text
                     || ' · ' || coalesce(array_to_string(proconfig, ','), '없음') || ' · ' || coalesce(array_to_string(proacl, ','), '기본')
                     || ' · ' || pg_get_userbyid(proowner), ' | ' order by proname)
       from pg_proc where oid in (to_regprocedure('public.push_group(text)'), to_regprocedure('public.push_wanted(uuid, text)'))),
    '실행 전 8번과 같음', 'create or replace라 소유자·권한이 그대로 남는다'
  union all select 16, '비교: 표 4개의 칸(push_settings.comments 뺌)·제약 지문',
    (select left(md5(string_agg(c.table_name || ':' || c.column_name || ':' || c.data_type || ':' || c.is_nullable || ':' || coalesce(c.column_default, ''), ',' order by c.table_name, c.ordinal_position)), 12)
       from information_schema.columns c where c.table_schema = 'public' and c.table_name in ('notifications', 'push_subscriptions', 'push_settings', 'device_push_tokens')
        and not (c.table_name = 'push_settings' and c.column_name = 'comments'))
      || ' · ' || (select count(*) || ' / ' || left(md5(string_agg(conrelid::regclass::text || ':' || conname || ':' || pg_get_constraintdef(oid), ',' order by conrelid::regclass::text, conname)), 12)
       from pg_constraint where conrelid in (select rel from pt)),
    '실행 전 9번과 같음', '칸은 comments 하나만 늘었다'
  union all select 17, '비교: 같은 4개 표의 트리거 · 정책 · 표 권한 · RLS · push_settings 칸 권한(comments 뺌)',
    (select count(*) || ' / ' || left(md5(string_agg(tgrelid::regclass::text || pg_get_triggerdef(oid) || tgenabled::text, ',' order by tgrelid::regclass::text, tgname)), 12)
       from pg_trigger where tgrelid in (select rel from pt) and not tgisinternal)
      || ' · ' || (select count(*) || ' / ' || left(md5(string_agg(polrelid::regclass::text || polname || polcmd::text || coalesce(pg_get_expr(polqual, polrelid), '') || coalesce(pg_get_expr(polwithcheck, polrelid), ''), ',' order by polrelid::regclass::text, polname)), 12)
       from pg_policy where polrelid in (select rel from pt))
      || ' · ' || (select left(md5(string_agg(table_name || ':' || grantee || ':' || privilege_type, ',' order by table_name, grantee, privilege_type)), 12)
       from information_schema.role_table_grants where table_schema = 'public' and table_name in ('notifications', 'push_subscriptions', 'push_settings', 'device_push_tokens')
        and grantee in ('anon', 'authenticated', 'service_role'))
      || ' · ' || (select string_agg(relrowsecurity::text, ',' order by relname) from pg_class where oid in (select rel from pt))
      || ' · ' || (select count(*) || ' / ' || left(md5(string_agg(column_name || ':' || grantee || ':' || privilege_type, ',' order by column_name, grantee, privilege_type)), 12)
       from information_schema.role_column_grants where table_schema = 'public' and table_name = 'push_settings'
        and grantee in ('anon', 'authenticated', 'service_role') and column_name <> 'comments'),
    '실행 전 10번과 같음', null
  union all select 18, '비교: 허용 목록(restriction_exemptions) 줄 수 / 지문',
    (select count(*) || ' / ' || left(md5(string_agg(kind || ':' || name || ':' || reason, ',' order by kind, name)), 12) from public.restriction_exemptions),
    '실행 전 11번과 같음', null
  union all select 19, '비교: 웹 푸시 기기 / 앱 기기 토큰 / 알림 설정 줄 수 · 지문(기존 칸만)',
    (select count(*) || ' · ' || coalesce(max(id), 0) || ' · ' || left(md5(coalesce(string_agg(s::text, '|' order by s.id), '')), 12) from public.push_subscriptions s)
      || ' / ' || (select count(*) || ' · ' || coalesce(max(id), 0) from public.device_push_tokens)
      || ' / ' || (select count(*) || ' · ' || left(md5(coalesce(string_agg(concat_ws(',', s.user_id, s.staff_new, s.my_results, s.follow_builds, s.notice, s.new_followers, s.build_edits, s.updated_at), '|' order by s.user_id), '')), 12)
                     from public.push_settings s),
    '실행 전 12번과 같음', '074는 기존 설정 값을 바꾸지 않는다 (그 사이 사이트 활동이 있으면 다를 수 있음)'
  union all select 20, '비교: 알림 전체 수 · 가장 큰 id / 댓글 3종 알림 수 (안 읽음) / push_group을 뺀 읽기 함수 수 / 지문',
    (select count(*) || ' · ' || coalesce(max(id), 0) from public.notifications)
      || ' / ' || (select count(*) || ' (' || count(*) filter (where read_at is null) || ')' from public.notifications where kind in ('post_comment', 'doc_comment', 'comment_reply'))
      || ' / ' || (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a join rf on rf.sig = a.sig),
    '실행 전 13번과 같음', '074는 이미 있는 댓글 알림에 푸시를 보내지 않는다 (새로 생기는 알림부터)'
  union all select 21, '비교: 기존 판정 지문 - 모든 사람 × 모든 알림 종류(댓글 3종 뺌)의 push_wanted 결과 · 종류별 push_group',
    (select count(*) || ' / ' || md5(string_agg(p.id::text || ':' || k.k || ':' || public.push_wanted(p.id, k.k)::text, ',' order by p.id, k.k))
       from public.profiles p cross join other_kinds k)
      || ' · ' || (select count(*) || ' / ' || md5(string_agg(k || ':' || coalesce(public.push_group(k), '-'), ',' order by k)) from other_kinds),
    '실행 전 14번과 같음', '기존 묶음(staff_new·my_results·follow_builds·notice·new_followers·build_edits)의 판정이 그대로'
  union all select 22, '참고: 댓글 3종을 푸시로 받을 사람 수 (웹 구독 또는 앱 토큰 있음 · 댓글 알림 켬)',
    (select count(*)::text from public.profiles p where public.push_wanted(p.id, 'post_comment')),
    '(참고) 실행 전 15번과 같음 (직후)', null
) x
order by ord;
