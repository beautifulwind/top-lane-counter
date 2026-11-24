-- =====================================================================
-- 074(댓글·답글 푸시 묶음 comments) 실행 "전" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 074를 실행하기 전에 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~3번: [지금 값]이 [정상 값]과 맞으면 074를 실행해도 된다. 다르면 실행하지 말고 알려 주세요.
--   - 4~15번은 "적어 둘 값"이다. 074 실행 뒤 check_comment_push_after.sql의 「비교」 줄과 비교한다
--     (074는 push_settings 칸 comments 하나와 push_group·push_wanted 본문에 줄 하나씩만 더한다 - 그 밖은 그대로여야 한다).
--   - 함수 본문 지문은 줄바꿈 CR을 뺀 값으로 계산한다(SQL Editor가 CRLF로 붙여 넣어도 같은 값).
--   - 14번은 지금 모든 사람 × 모든 알림 종류(댓글 3종 뺌)의 푸시 판정 지문이다(읽기만 하는 push_wanted를 부른다).
--   - 토큰·endpoint 같은 값 자체는 출력하지 않는다(개수·지문만).
--   - 사이트 활동(알림·웹/앱 알림 켜기·끄기·설정 저장)이 있으면 12~14번은 달라질 수 있다 - 사람이 적은 시간에 이어서 실행해 주세요.
-- =====================================================================
with
-- 일반 사용자(로그인·비로그인)가 부를 수 있는 쓰기 함수 (068 빠뜨림 방지 검사와 같은 대상: volatile, 트리거 아님)
wf as (
  select p.oid, p.proname || '(' || oidvectortypes(p.proargtypes) || ')' as sig, p.prosrc
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f' and p.provolatile = 'v' and p.prorettype <> 'trigger'::regtype
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))
),
-- 일반 사용자가 부를 수 있는 읽기 함수 (stable·immutable, 트리거 아님) - push_group은 074가 고치므로 뺀다
rf as (
  select p.proname || '(' || oidvectortypes(p.proargtypes) || ')' as sig
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f' and p.provolatile in ('s', 'i') and p.prorettype <> 'trigger'::regtype
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))
     and p.proname <> 'push_group'
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
changed as (select unnest(array['push_group(text)', 'push_wanted(uuid, text)']) as sig),
-- 푸시와 관계있는 표 4개
pt as (select unnest(array['public.notifications', 'public.push_subscriptions', 'public.push_settings', 'public.device_push_tokens']::regclass[]) as rel),
-- 알림 종류 전체 (notifications_kind_check에서 읽음) + 없는 종류 하나, 댓글 3종은 뺌
kinds as (
  select k from (select (regexp_matches(pg_get_constraintdef(oid), '''([a-z_]+)''', 'g'))[1] as k
                   from pg_constraint where conname = 'notifications_kind_check' and conrelid = 'public.notifications'::regclass) x
  union select 'no_such_kind'
),
other_kinds as (select k from kinds where k not in ('post_comment', 'doc_comment', 'comment_reply'))
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '073까지 실행됨 (push_wanted 본문)' as what,
    coalesce((select case md5(replace(prosrc, E'\r', ''))
                       when 'e6f1723ae3a6b0126ece4b51488a067c' then '073 본문'
                       when 'fa8eb83cd5786a7155e5f2439917b04e' then '074 이미 실행'
                       when 'bfb8e95016ca726a7dade1b76bb56fce' then '067 본문 (073 전)'
                       else '다름 ' || md5(replace(prosrc, E'\r', '')) end
                from pg_proc where oid = to_regprocedure('public.push_wanted(uuid, text)')), '함수 없음') as now_value,
    '073 본문' as ok_value, '「067 본문」이면 073부터. 「074 이미 실행」이면 다시 실행하지 마세요' as memo
  union all select 2, 'push_group 본문',
    coalesce((select case md5(replace(prosrc, E'\r', ''))
                       when 'ba44f97f41cc99cbb3590c8528ace024' then '069 본문'
                       when '2be75ed999aa158e20557beda4db0814' then '074 이미 실행'
                       else '다름 ' || md5(replace(prosrc, E'\r', '')) end
                from pg_proc where oid = to_regprocedure('public.push_group(text)')), '함수 없음'),
    '069 본문', '「다름」이면 실행하지 말고 알려 주세요'
  union all select 3, 'push_settings.comments 칸 수 / 댓글 3종의 지금 묶음 (post_comment·doc_comment·comment_reply)',
    (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'push_settings' and column_name = 'comments')
      || ' / ' || coalesce(public.push_group('post_comment'), '없음') || '·' || coalesce(public.push_group('doc_comment'), '없음')
      || '·' || coalesce(public.push_group('comment_reply'), '없음'),
    '0 / 없음·없음·없음', '1이면 074를 이미 실행한 것'
  union all select 4, '적어 둘 값: 쓰기 함수 수 (전체 / 첫 줄에 assert_can_write 검사 / 허용 목록)',
    (select count(*) from wf) || ' / '
      || (select count(*) from wf where wf.prosrc ~ '^\s*declare\s*\n\s*_can_write constant boolean := public\.assert_can_write\(\);'
                                     or wf.prosrc ~ '^\s*begin\s*\n\s*perform public\.assert_can_write\(\);')
      || ' / ' || (select count(*) from wf where exists (select 1 from public.restriction_exemptions e where e.kind = 'function' and e.name = wf.sig)),
    '103 / 30 / 73 (예상)', '074 뒤에도 103 / 30 / 73이어야 한다. 예상과 다르면 그대로 적어 두고 알려 주세요'
  union all select 5, '적어 둘 값: 쓰기 함수의 이름·본문·보안·search_path·권한 지문 (CR 뺌)',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a join wf on wf.sig = a.sig),
    '(이 값을 적어 둠)', '실행 뒤: 같은 수·같은 지문 (두 함수는 쓰기 함수가 아님)'
  union all select 6, '적어 둘 값: push_group·push_wanted를 뺀 public의 모든 함수 수 / 지문 (CR 뺌)',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a where a.sig not in (select sig from changed)),
    '(이 값을 적어 둠)', '실행 뒤: 같은 수·같은 지문'
  union all select 7, '적어 둘 값: 발송·댓글 알림 함수 지문 (push_on_notification·push_targets·push_forget·notify_new_comment)',
    (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a
      where split_part(a.sig, '(', 1) in ('push_on_notification', 'push_targets', 'push_forget', 'notify_new_comment')),
    '(이 값을 적어 둠)', '074는 이 함수들을 고치지 않는다'
  union all select 8, '적어 둘 값: push_group·push_wanted의 본문 밖 속성 (인자 · 반환 · volatile · security definer · search_path · 권한 · 소유자)',
    (select string_agg(oid::regprocedure::text || ' · ' || pg_get_function_result(oid) || ' · ' || provolatile::text || ' · ' || prosecdef::text
                     || ' · ' || coalesce(array_to_string(proconfig, ','), '없음') || ' · ' || coalesce(array_to_string(proacl, ','), '기본')
                     || ' · ' || pg_get_userbyid(proowner), ' | ' order by proname)
       from pg_proc where oid in (to_regprocedure('public.push_group(text)'), to_regprocedure('public.push_wanted(uuid, text)'))),
    '(이 값을 적어 둠)', '실행 뒤: 본문만 바뀌고 이 줄은 같아야 한다'
  union all select 9, '적어 둘 값: 표 4개의 칸(push_settings.comments 뺌)·제약 지문',
    (select left(md5(string_agg(c.table_name || ':' || c.column_name || ':' || c.data_type || ':' || c.is_nullable || ':' || coalesce(c.column_default, ''), ',' order by c.table_name, c.ordinal_position)), 12)
       from information_schema.columns c where c.table_schema = 'public' and c.table_name in ('notifications', 'push_subscriptions', 'push_settings', 'device_push_tokens')
        and not (c.table_name = 'push_settings' and c.column_name = 'comments'))
      || ' · ' || (select count(*) || ' / ' || left(md5(string_agg(conrelid::regclass::text || ':' || conname || ':' || pg_get_constraintdef(oid), ',' order by conrelid::regclass::text, conname)), 12)
       from pg_constraint where conrelid in (select rel from pt)),
    '(이 값을 적어 둠)', null
  union all select 10, '적어 둘 값: 같은 4개 표의 트리거 · 정책 · 표 권한 · RLS · push_settings 칸 권한(comments 뺌)',
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
    '(이 값을 적어 둠)', '074는 push_settings에 칸 하나와 그 칸 권한만 더한다'
  union all select 11, '적어 둘 값: 허용 목록(restriction_exemptions) 줄 수 / 지문',
    (select count(*) || ' / ' || left(md5(string_agg(kind || ':' || name || ':' || reason, ',' order by kind, name)), 12) from public.restriction_exemptions),
    '(이 값을 적어 둠)', '074는 허용 목록을 바꾸지 않는다'
  union all select 12, '적어 둘 값: 웹 푸시 기기 수 · 가장 큰 id · 지문 앞 12자리 / 앱 기기 토큰 수 · 가장 큰 id / 알림 설정 줄 수 · 지문(기존 칸만)',
    (select count(*) || ' · ' || coalesce(max(id), 0) || ' · ' || left(md5(coalesce(string_agg(s::text, '|' order by s.id), '')), 12) from public.push_subscriptions s)
      || ' / ' || (select count(*) || ' · ' || coalesce(max(id), 0) from public.device_push_tokens)
      || ' / ' || (select count(*) || ' · ' || left(md5(coalesce(string_agg(concat_ws(',', s.user_id, s.staff_new, s.my_results, s.follow_builds, s.notice, s.new_followers, s.build_edits, s.updated_at), '|' order by s.user_id), '')), 12)
                     from public.push_settings s),
    '(이 값을 적어 둠)', '그 사이 누가 알림을 켜고 끄거나 설정을 저장하면 달라질 수 있음'
  union all select 13, '적어 둘 값: 알림 전체 수 · 가장 큰 id / 댓글 3종 알림 수 (안 읽음) / push_group을 뺀 읽기 함수 수 / 지문',
    (select count(*) || ' · ' || coalesce(max(id), 0) from public.notifications)
      || ' / ' || (select count(*) || ' (' || count(*) filter (where read_at is null) || ')' from public.notifications where kind in ('post_comment', 'doc_comment', 'comment_reply'))
      || ' / ' || (select count(*) || ' / ' || md5(string_agg(a.body, '|' order by a.sig)) from allf a join rf on rf.sig = a.sig),
    '(이 값을 적어 둠)', '074는 알림 줄·읽기 함수를 더하지 않는다 (알림 수는 사이트 활동으로 달라질 수 있음)'
  union all select 14, '적어 둘 값: 기존 판정 지문 - 모든 사람 × 모든 알림 종류(댓글 3종 뺌)의 push_wanted 결과 · 종류별 push_group',
    (select count(*) || ' / ' || md5(string_agg(p.id::text || ':' || k.k || ':' || public.push_wanted(p.id, k.k)::text, ',' order by p.id, k.k))
       from public.profiles p cross join other_kinds k)
      || ' · ' || (select count(*) || ' / ' || md5(string_agg(k || ':' || coalesce(public.push_group(k), '-'), ',' order by k)) from other_kinds),
    '(이 값을 적어 둠)', '실행 뒤: 같은 값 = 기존 묶음의 판정이 하나도 바뀌지 않음'
  union all select 15, '참고: 댓글 3종을 지금 푸시로 보낼 사람 수 (웹 구독 또는 앱 토큰이 있는 사람)',
    (select count(*)::text from public.profiles p where exists (select 1 from public.push_subscriptions s where s.user_id = p.id)
                                              or exists (select 1 from public.device_push_tokens d where d.user_id = p.id)),
    '(참고)', '074 뒤 이 사람들이 댓글·답글 휴대폰 알림을 받는다 (설정에서 끌 때까지)'
) x
order by ord;
