-- =====================================================================
-- 072(앱 푸시 기기 토큰 device_push_tokens + register/unregister_device_push_token) 실행 "뒤" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다). 운영 DB에서 언제 다시 실행해도 된다.
-- 072를 실행한 "직후" SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~18번: [지금 값]이 [정상 값]과 모두 맞아야 한다. 하나라도 다르면 알려 주세요.
--   - 19~27번: 실행 전 check_device_push_tokens_before.sql의 3~11번에 적어 둔 값과 비교한다(각 줄의 [정상 값]에 무엇과 같아야 하는지 적었다).
--   - 함수 본문 지문은 줄바꿈 CR을 뺀 값으로 계산한다(SQL Editor가 CRLF로 붙여 넣어도 같은 값 - c5333b1과 같은 방식).
--   - 이 조회는 새 함수를 부르지 않는다. 토큰 값 자체는 출력하지 않는다(개수만).
-- =====================================================================
with
reg as (select to_regprocedure('public.register_device_push_token(text, text, text)') as oid),
unr as (select to_regprocedure('public.unregister_device_push_token(text)') as oid),
tb as (select to_regclass('public.device_push_tokens') as oid),
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
-- 일반 사용자(로그인·비로그인)가 부를 수 있는 읽기 함수 - 실행 전 스크립트와 같은 식
rf as (
  select p.proname || '(' || oidvectortypes(p.proargtypes) || ')' as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f' and p.provolatile in ('s', 'i') and p.prorettype <> 'trigger'::regtype
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
),
pt as (select unnest(array['public.notifications', 'public.push_subscriptions', 'public.push_settings']::regclass[]) as rel),
newfn as (select unnest(array['register_device_push_token(text, text, text)', 'unregister_device_push_token(text)']) as sig)
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '새 표 device_push_tokens 칸 (이름:자료형:null 허용, 순서대로)' as what,
    coalesce((select string_agg(column_name || ':' || data_type || ':' || is_nullable, ', ' order by ordinal_position)
       from information_schema.columns where table_schema = 'public' and table_name = 'device_push_tokens'), '표 없음') as now_value,
    'id:bigint:NO, user_id:uuid:NO, platform:text:NO, token:text:NO, app_version:text:YES, created_at:timestamp with time zone:NO, last_seen_at:timestamp with time zone:NO' as ok_value, null as memo
  union all select 2, '제약 (이름 = 내용)',
    coalesce((select string_agg(conname || ' = ' || pg_get_constraintdef(oid), ' | ' order by conname) from pg_constraint where conrelid = (select oid from tb)), '없음'),
    'device_push_tokens_app_version_check = CHECK (((app_version IS NULL) OR (((length(app_version) >= 1) AND (length(app_version) <= 32)) AND (app_version ~ ''^[A-Za-z0-9.+_-]+$''::text)))) | device_push_tokens_pkey = PRIMARY KEY (id) | device_push_tokens_platform_check = CHECK ((platform = ANY (ARRAY[''ios''::text, ''android''::text]))) | device_push_tokens_platform_token_key = UNIQUE (platform, token) | device_push_tokens_token_check = CHECK ((((length(token) >= 32) AND (length(token) <= 1000)) AND (token ~ ''^[A-Za-z0-9:_.-]+$''::text))) | device_push_tokens_user_id_fkey = FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE',
    '같은 (platform, token)은 한 줄, 탈퇴하면 함께 삭제'
  union all select 3, 'RLS 켬 / 정책 수 / 트리거 수 / 색인 device_push_tokens_user',
    coalesce((select relrowsecurity::text from pg_class where oid = (select oid from tb)), '표 없음')
      || ' / ' || (select count(*) from pg_policy where polrelid = (select oid from tb))
      || ' / ' || (select count(*) from pg_trigger where tgrelid = (select oid from tb) and not tgisinternal)
      || ' / ' || coalesce((select pg_get_indexdef(i.indexrelid) from pg_index i join pg_class c on c.oid = i.indexrelid
                             where i.indrelid = (select oid from tb) and c.relname = 'device_push_tokens_user'), '없음'),
    'true / 0 / 0 / CREATE INDEX device_push_tokens_user ON public.device_push_tokens USING btree (user_id, last_seen_at DESC)',
    '정책 없음 = 앱은 표를 직접 못 읽고 못 씀 (함수로만)'
  union all select 4, '표 권한 (비로그인 anon / 로그인 authenticated / service_role / public)',
    coalesce((select coalesce(nullif(concat_ws(',', case when has_table_privilege('anon', oid, 'select') then 'select' end, case when has_table_privilege('anon', oid, 'insert') then 'insert' end,
                                     case when has_table_privilege('anon', oid, 'update') then 'update' end, case when has_table_privilege('anon', oid, 'delete') then 'delete' end), ''), '없음')
       || ' / ' || coalesce(nullif(concat_ws(',', case when has_table_privilege('authenticated', oid, 'select') then 'select' end, case when has_table_privilege('authenticated', oid, 'insert') then 'insert' end,
                                     case when has_table_privilege('authenticated', oid, 'update') then 'update' end, case when has_table_privilege('authenticated', oid, 'delete') then 'delete' end), ''), '없음')
       || ' / ' || coalesce(nullif(concat_ws(',', case when has_table_privilege('service_role', oid, 'select') then 'select' end, case when has_table_privilege('service_role', oid, 'insert') then 'insert' end,
                                     case when has_table_privilege('service_role', oid, 'update') then 'update' end, case when has_table_privilege('service_role', oid, 'delete') then 'delete' end), ''), '없음')
       || ' / ' || exists (select 1 from unnest(relacl) a where a::text like '=%')::text
       from pg_class where oid = (select oid from tb)), '표 없음'),
    '없음 / 없음 / select,delete / false', '발송 Edge Function(service_role)은 읽기·무효 토큰 지우기만'
  union all select 5, '저장된 토큰 수 (전체 / ios / android) · 한 사람 최대 기기 수',
    coalesce((select count(*) || ' / ' || count(*) filter (where platform = 'ios') || ' / ' || count(*) filter (where platform = 'android')
                || ' · ' || coalesce((select max(c) from (select count(*) c from public.device_push_tokens group by user_id) x), 0)
       from public.device_push_tokens), '표 없음'),
    '0 / 0 / 0 · 0 (실행 직후)', '그 뒤 새 앱이 등록하면 늘어난다. 최대 기기 수는 늘 10 이하'
  union all select 6, '새 함수 register_device_push_token (인자 / 같은 이름 함수 수 / 반환형)',
    coalesce((select oid::regprocedure::text from reg), '없음')
      || ' / ' || (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'register_device_push_token')
      || ' / ' || coalesce((select prorettype::regtype::text from pg_proc where oid = (select oid from reg)), '없음'),
    'register_device_push_token(text,text,text) / 1 / jsonb', null
  union all select 7, '  보안 (volatile 종류 / security definer / search_path) · 실행 권한 (anon / authenticated / public 기본 권한)',
    coalesce((select provolatile::text || ' / ' || prosecdef::text || ' / ' || coalesce(array_to_string(proconfig, ','), '없음')
            || ' · ' || has_function_privilege('anon', oid, 'execute')::text || ' / ' || has_function_privilege('authenticated', oid, 'execute')::text
            || ' / ' || exists (select 1 from unnest(proacl) a where a::text like '=%')::text
       from pg_proc where oid = (select oid from reg)), '함수 없음'),
    'v / true / search_path="" · false / true / false', '로그인 사용자만'
  union all select 8, '  함수 본문 지문 (줄바꿈 CR을 뺀 값)',
    coalesce((select md5(replace(prosrc, E'\r', '')) from pg_proc where oid = (select oid from reg)), '함수 없음'),
    '8a26ed307b78a7e240edc69480ad85e6', '파일 그대로 실행했으면 같음 (CRLF로 붙여 넣어도 같음)'
  union all select 9, '새 함수 unregister_device_push_token (인자 / 같은 이름 함수 수 / 반환형)',
    coalesce((select oid::regprocedure::text from unr), '없음')
      || ' / ' || (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'unregister_device_push_token')
      || ' / ' || coalesce((select prorettype::regtype::text from pg_proc where oid = (select oid from unr)), '없음'),
    'unregister_device_push_token(text) / 1 / boolean', null
  union all select 10, '  보안 (volatile 종류 / security definer / search_path) · 실행 권한 (anon / authenticated / public 기본 권한)',
    coalesce((select provolatile::text || ' / ' || prosecdef::text || ' / ' || coalesce(array_to_string(proconfig, ','), '없음')
            || ' · ' || has_function_privilege('anon', oid, 'execute')::text || ' / ' || has_function_privilege('authenticated', oid, 'execute')::text
            || ' / ' || exists (select 1 from unnest(proacl) a where a::text like '=%')::text
       from pg_proc where oid = (select oid from unr)), '함수 없음'),
    'v / true / search_path="" · false / true / false', '로그인 사용자만'
  union all select 11, '  함수 본문 지문 (줄바꿈 CR을 뺀 값)',
    coalesce((select md5(replace(prosrc, E'\r', '')) from pg_proc where oid = (select oid from unr)), '함수 없음'),
    'a35d9ece436c79b59c76a704164580ce', '파일 그대로 실행했으면 같음 (CRLF로 붙여 넣어도 같음)'
  union all select 12, '068 활동 제한: 새 함수 2개의 판정 (exempt = 허용 목록, checked = 첫 줄 검사)',
    coalesce((select string_agg(nf.sig || '=' || coalesce(wf.state, '쓰기 함수 목록에 없음'), ', ' order by nf.sig) from newfn nf left join wf on wf.sig = nf.sig), '없음'),
    'register_device_push_token(text, text, text)=exempt, unregister_device_push_token(text)=exempt',
    '활동 제한 중에도 알림을 받을 수 있게 (웹 푸시 켜기·끄기 정책과 같음)'
  union all select 13, '  허용 목록에 넣은 두 줄의 이유',
    coalesce((select string_agg(name || ': ' || reason, ' | ' order by name) from public.restriction_exemptions where kind = 'function' and name in (select sig from newfn)), '없음'),
    'register_device_push_token(text, text, text): 072 앱 휴대폰 알림 켜기 - 활동 제한 중에도 알림을 받아야 함 (웹 푸시 켜기와 같음) | unregister_device_push_token(text): 072 앱 휴대폰 알림 끄기·로그아웃 (웹 푸시 끄기와 같음)', null
  union all select 14, '빠뜨림 방지: 쓰기 함수 중 통과 못 한 것 (검사도 허용 목록도 없음 / 검사가 첫 줄이 아님)',
    coalesce((select string_agg(sig || ' ' || state, ', ' order by sig) from wf where state not in ('checked', 'exempt')), '없음'),
    '없음', '068 check_restrictions_after.sql 5번과 같은 규칙'
  union all select 15, '허용 목록에 있는데 실제로 없는 함수',
    coalesce((select string_agg(e.name, ', ') from public.restriction_exemptions e where e.kind = 'function' and not exists (select 1 from wf where wf.sig = e.name)), '없음'),
    '없음', null
  union all select 16, '탈퇴·계정 삭제 때 함께 지워짐 (외래 키 on delete 규칙 / 가리키는 표)',
    coalesce((select confdeltype::text || ' / ' || confrelid::regclass::text from pg_constraint where conname = 'device_push_tokens_user_id_fkey' and conrelid = (select oid from tb)), '없음'),
    'c / profiles', 'c = cascade. push_subscriptions와 같음 (탈퇴 함수는 auth.users를 지우고 profiles가 cascade로 지워진다)'
  union all select 17, '웹 푸시 발송 구조 그대로 (notifications_push 트리거가 부르는 함수 / 켜짐)',
    coalesce((select tgfoid::regprocedure::text || ' / ' || tgenabled::text from pg_trigger where tgname = 'notifications_push' and tgrelid = 'public.notifications'::regclass), '없음'),
    'push_on_notification() / O', '072는 트리거·발송 함수를 고치지 않는다'
  union all select 18, '새 표를 가리키는 다른 객체 (트리거·외래 키·뷰)',
    (select count(*) from pg_trigger where tgrelid = (select oid from tb) and not tgisinternal)
      || ' / ' || (select count(*) from pg_constraint where confrelid = (select oid from tb))
      || ' / ' || (select count(*) from pg_depend d join pg_rewrite r on r.oid = d.objid where d.refobjid = (select oid from tb)),
    '0 / 0 / 0', null
  -- ===== 실행 전 값과 비교 =====
  union all select 19, '비교: 쓰기 함수 수 (전체 / 첫 줄 검사 / 허용 목록)',
    (select count(*) from wf) || ' / ' || (select count(*) from wf where state = 'checked') || ' / ' || (select count(*) from wf where state = 'exempt'),
    '실행 전 3번 + (2 / 0 / 2) → 103 / 30 / 73', '새 쓰기 함수 2개는 허용 목록 쪽'
  union all select 20, '비교: 새 함수 2개를 뺀 쓰기 함수의 지문',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a join wf on wf.sig = a.sig where a.sig not in (select sig from newfn)),
    '실행 전 4번과 같음', '기존 쓰기 함수 101개 그대로'
  union all select 21, '비교: public의 모든 함수 (새 함수 2개 뺌) 수 / 지문',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a where a.sig not in (select sig from newfn)),
    '실행 전 5번과 같음', '기존 함수는 하나도 바뀌지 않았다'
  union all select 22, '비교: 웹 푸시 발송 함수 지문',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a
      where split_part(a.sig, '(', 1) in ('push_on_notification', 'push_targets', 'push_wanted', 'push_forget', 'push_group')),
    '실행 전 6번과 같음', null
  union all select 23, '비교: 표 notifications·push_subscriptions·push_settings의 칸·제약 지문',
    (select left(md5(string_agg(c.table_name || ':' || c.column_name || ':' || c.data_type || ':' || c.is_nullable || ':' || coalesce(c.column_default, ''), ',' order by c.table_name, c.ordinal_position)), 12)
       from information_schema.columns c where c.table_schema = 'public' and c.table_name in ('notifications', 'push_subscriptions', 'push_settings'))
      || ' · ' || (select count(*) || ' / ' || left(md5(string_agg(conrelid::regclass::text || ':' || conname || ':' || pg_get_constraintdef(oid), ',' order by conrelid::regclass::text, conname)), 12)
       from pg_constraint where conrelid in (select rel from pt)),
    '실행 전 7번과 같음', null
  union all select 24, '비교: 같은 3개 표의 트리거 · 정책 · 권한 · RLS',
    (select count(*) || ' / ' || left(md5(string_agg(tgrelid::regclass::text || pg_get_triggerdef(oid) || tgenabled::text, ',' order by tgrelid::regclass::text, tgname)), 12)
       from pg_trigger where tgrelid in (select rel from pt) and not tgisinternal)
      || ' · ' || (select count(*) || ' / ' || left(md5(string_agg(polrelid::regclass::text || polname || polcmd::text || coalesce(pg_get_expr(polqual, polrelid), '') || coalesce(pg_get_expr(polwithcheck, polrelid), ''), ',' order by polrelid::regclass::text, polname)), 12)
       from pg_policy where polrelid in (select rel from pt))
      || ' · ' || (select left(md5(string_agg(table_name || ':' || grantee || ':' || privilege_type, ',' order by table_name, grantee, privilege_type)), 12)
       from information_schema.role_table_grants where table_schema = 'public' and table_name in ('notifications', 'push_subscriptions', 'push_settings')
        and grantee in ('anon', 'authenticated', 'service_role'))
      || ' · ' || (select string_agg(relrowsecurity::text, ',' order by relname) from pg_class where oid in (select rel from pt)),
    '실행 전 8번과 같음', null
  union all select 25, '비교: 허용 목록 (새 두 줄 뺌) 줄 수 / 지문 · profiles를 가리키는 외래 키 (새 표 뺌) 수 / 지문',
    (select count(*) || ' / ' || left(md5(string_agg(kind || ':' || name || ':' || reason, ',' order by kind, name)), 12)
       from public.restriction_exemptions where not (kind = 'function' and name in (select sig from newfn)))
      || ' · ' || (select count(*) || ' / ' || left(md5(string_agg(conrelid::regclass::text || ':' || conname || ':' || confdeltype::text, ',' order by conrelid::regclass::text, conname)), 12)
       from pg_constraint where contype = 'f' and confrelid = 'public.profiles'::regclass and conrelid is distinct from (select oid from tb)),
    '실행 전 9번과 같음', '허용 목록은 2줄, 외래 키는 1개만 늘었다'
  union all select 26, '비교: 웹 푸시 기기 수 · 가장 큰 id · 지문 앞 12자리 / 알림 종류 설정 줄 수',
    (select count(*) || ' · ' || coalesce(max(id), 0) || ' · ' || left(md5(coalesce(string_agg(s::text, '|' order by s.id), '')), 12) from public.push_subscriptions s)
      || ' / ' || (select count(*) from public.push_settings),
    '실행 전 10번과 같음', '072는 웹 푸시 데이터를 바꾸지 않는다 (그 사이 사이트 활동이 있으면 다를 수 있음)'
  union all select 27, '비교: 알림 전체 수 · 가장 큰 id / 읽기 함수 수 / 지문',
    (select count(*) || ' · ' || coalesce(max(id), 0) from public.notifications)
      || ' / ' || (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a join rf on rf.sig = a.sig),
    '실행 전 11번과 같음', '읽기 함수는 늘지 않았다'
) x
order by ord;
