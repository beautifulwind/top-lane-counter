-- =====================================================================
-- 069(운영자 경고) 실행 "뒤" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다). 운영 DB에서 언제 다시 실행해도 된다.
-- 069를 실행한 "직후" SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~10번: [지금 값]이 [정상 값]과 모두 맞아야 한다. 하나라도 다르면 알려 주세요. (웹 push는 그다음)
--     8번은 068 빠뜨림 방지 검사다(068 check_restrictions_after.sql 5번과 같은 규칙) - 069의 새 쓰기 함수 2개가 허용 목록에 있어 "없음"이어야 한다.
--   - 11~20번: 실행 전 check_warnings_before.sql의 6~15번에 적어 둔 값과 차례로 같아야 한다 (069는 기존 데이터를 바꾸지 않는다).
--   - 함수 본문 지문은 줄바꿈 CR을 뺀 값으로 계산한다(SQL Editor가 CRLF로 붙여 넣어도 같은 값 - c5333b1과 같은 방식).
-- =====================================================================
with fn as (
  select p.proname || '(' || oidvectortypes(p.proargtypes) || ')' as sig,
         case
           when p.prosrc ~ '^\s*declare\s*\r?\n\s*_can_write constant boolean := public\.assert_can_write\(\);'
             or p.prosrc ~ '^\s*begin\s*\r?\n\s*perform public\.assert_can_write\(\);' then 'checked'
           when p.prosrc like '%assert_can_write%' then 'NOT_FIRST'
           when exists (select 1 from public.restriction_exemptions e
                         where e.kind = 'function' and e.name = p.proname || '(' || oidvectortypes(p.proargtypes) || ')') then 'exempt'
           else 'MISSING'
         end as state
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prokind = 'f' and p.provolatile = 'v' and p.prorettype <> 'trigger'::regtype
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'))
)
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '새 표 user_warnings (칸)' as what,
    coalesce((select string_agg(column_name || ':' || data_type, ', ' order by ordinal_position) from information_schema.columns
               where table_schema = 'public' and table_name = 'user_warnings'), '없음') as now_value,
    'id:bigint, user_id:uuid, memo:text, created_at:timestamp with time zone, created_by:uuid, restriction_id:bigint, notification_id:bigint, notice_read_at:timestamp with time zone, acked_at:timestamp with time zone' as ok_value, null as memo
  union all select 2, '경고 기록: 탈퇴하면 삭제(cascade 1) / set null 3 / RLS 켬 / 정책 수 / 로그인 읽기·쓰기 / 비로그인 읽기',
    case when to_regclass('public.user_warnings') is null then '없음' else
      (select count(*) filter (where confdeltype = 'c') || ' / ' || count(*) filter (where confdeltype = 'n') from pg_constraint where conrelid = 'public.user_warnings'::regclass and contype = 'f')
      || ' / ' || (select relrowsecurity::text from pg_class where oid = 'public.user_warnings'::regclass)
      || ' / ' || (select count(*) from pg_policy where polrelid = 'public.user_warnings'::regclass)
      || ' / ' || has_table_privilege('authenticated', 'public.user_warnings', 'select')::text
      || '·' || (has_table_privilege('authenticated', 'public.user_warnings', 'insert') or has_table_privilege('authenticated', 'public.user_warnings', 'update')
                 or has_table_privilege('authenticated', 'public.user_warnings', 'delete'))::text
      || ' / ' || has_table_privilege('anon', 'public.user_warnings', 'select')::text end,
    '1 / 3 / true / 1 / true·false / false', '내용은 본인·운영자만 읽고, 쓰기는 함수로만'
  union all select 3, '새 함수 수 / 로그인이 부를 수 있는 것 / 비로그인이 부를 수 있는 것',
    (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'
       and p.proname in ('warn_user', 'ack_warning', 'my_warnings', 'admin_member_warnings', 'warning_notice_read', 'warning_notice_message'))
    || ' / 로그인 ' || coalesce((select string_agg(p.proname, '·' order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'
       and p.proname in ('warn_user', 'ack_warning', 'my_warnings', 'admin_member_warnings', 'warning_notice_read', 'warning_notice_message')
       and has_function_privilege('authenticated', p.oid, 'execute')), '없음')
    || ' / 비로그인 ' || (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'
       and p.proname in ('warn_user', 'ack_warning', 'my_warnings', 'admin_member_warnings', 'warning_notice_read', 'warning_notice_message')
       and has_function_privilege('anon', p.oid, 'execute')),
    '6 / 로그인 ack_warning·admin_member_warnings·my_warnings·warn_user / 비로그인 0', null
  union all select 4, '알림 읽음 트리거 notifications_warning_read (수 / 켜짐)',
    (select count(*) || ' / ' || coalesce(bool_and(tgenabled = 'O')::text, '-') from pg_trigger where tgname = 'notifications_warning_read' and tgrelid = 'public.notifications'::regclass),
    '1 / true', null
  union all select 5, '알림 종류에 warning_received / 휴대폰 알림 묶음',
    (select (pg_get_constraintdef(oid) like '%warning_received%')::text from pg_constraint where conname = 'notifications_kind_check' and conrelid = 'public.notifications'::regclass)
      || ' / ' || coalesce(public.push_group('warning_received'), '없음'),
    'true / my_results', '「내 처리 결과」 설정을 따른다'
  union all select 6, '처리 기록 종류에 warn_user',
    (select (pg_get_constraintdef(oid) like '%warn_user%')::text from pg_constraint where conname = 'moderation_log_action_check'),
    'true', null
  union all select 7, '068 허용 목록 (함수 줄 / 정책 줄 / 069가 더한 2줄)',
    (select count(*) filter (where kind = 'function') || ' / ' || count(*) filter (where kind = 'policy')
            || ' / ' || count(*) filter (where name in ('warn_user(uuid, text)', 'ack_warning(bigint)')) from public.restriction_exemptions),
    '71 / 8 / 2', '068 확인 스크립트의 「69」는 069 뒤에는 71이 정상'
  union all select 8, '빠뜨림 방지: 쓰기 함수 (검사 / 허용 목록 / 통과 못 한 것)',
    (select count(*) filter (where state = 'checked') || ' / ' || count(*) filter (where state = 'exempt') || ' / '
            || coalesce(string_agg(sig || ' ' || state, ', ') filter (where state not in ('checked', 'exempt')), '없음') from fn),
    '29 / 71 / 없음', '"없음"이 아니면 그 함수가 제한 검사도 허용 목록도 없다는 뜻 - 알려 주세요'
  union all select 9, '일반 사용자가 부를 수 있는 쓰기 함수 수',
    (select count(*) from fn)::text, '100', '실행 전 5번(98) + warn_user·ack_warning'
  union all select 10, '경고 기록 수 / 경고 알림 수 / 처리 기록 warn_user 수',
    case when to_regclass('public.user_warnings') is null then '없음' else
      (xpath('/row/c/text()', query_to_xml('select count(*) as c from public.user_warnings', false, true, '')))[1]::text end
      || ' / ' || (select count(*) from public.notifications where kind = 'warning_received')
      || ' / ' || (select count(*) from public.moderation_log where action = 'warn_user'),
    '0 / 0 / 0', '실행 직후 기준. 그 뒤 운영자가 보내면 늘어나는 것이 정상'
  union all select 11, '적어 둘 값: 알림 (줄 수 / 가장 큰 id / 내용 지문 - 읽음 표시·경고 알림은 빼고)',
    (select count(*) || ' / ' || coalesce(max(id), 0) || ' / ' || md5(coalesce(string_agg(concat_ws(',', n.id, n.user_id, n.kind, n.message, n.created_at, n.proposal_id, n.build_id, n.post_id, n.counter_id), '|' order by n.id), '')) from public.notifications n where n.kind <> 'warning_received'),
    '실행 전 6번과 같음', '그 사이 사이트 활동으로 알림이 생겼다면 늘어난 것이 정상'
  union all select 12, '적어 둘 값: 처리 기록 moderation_log (줄 수 / 가장 큰 id / 내용 지문 - 경고 줄은 빼고)',
    (select count(*) || ' / ' || coalesce(max(id), 0) || ' / ' || md5(coalesce(string_agg(m::text, '|' order by m.id), '')) from public.moderation_log m where m.action <> 'warn_user'),
    '실행 전 7번과 같음', null
  union all select 13, '적어 둘 값: 활동 제한 기록 user_restrictions (줄 수 / 가장 큰 id / 내용 지문)',
    (select count(*) || ' / ' || coalesce(max(id), 0) || ' / ' || md5(coalesce(string_agg(r::text, '|' order by r.id), '')) from public.user_restrictions r),
    '실행 전 8번과 같음', null
  union all select 14, '적어 둘 값: 068 허용 목록 (줄 수 / 내용 지문 - 069가 더하는 2줄은 빼고)',
    (select count(*) || ' / ' || md5(coalesce(string_agg(e::text, '|' order by e.kind, e.name), '')) from public.restriction_exemptions e where e.name not in ('warn_user(uuid, text)', 'ack_warning(bigint)')),
    '실행 전 9번과 같음', null
  union all select 15, '적어 둘 값: 프로필 (줄 수 / 내용 지문 - 마지막 접속 시각은 빼고)',
    (select count(*) || ' / ' || md5(coalesce(string_agg((to_jsonb(p) - 'last_seen_at')::text, '|' order by p.id), '')) from public.profiles p),
    '실행 전 10번과 같음', null
  union all select 16, '적어 둘 값: 빌드 / 추천 / 수정 기록 / 북마크 (각 줄 수 · 내용 지문 앞 12자리)',
    (select count(*) || '·' || left(md5(coalesce(string_agg(b::text, '|' order by b.id), '')), 12) from public.builds b) || ' / ' || (select count(*) || '·' || left(md5(coalesce(string_agg(v::text, '|' order by v.build_id, v.user_id::text), '')), 12) from public.build_votes v) || ' / ' || (select count(*) || '·' || left(md5(coalesce(string_agg(r::text, '|' order by r.id), '')), 12) from public.build_revisions r) || ' / ' || (select count(*) || '·' || left(md5(coalesce(string_agg(k::text, '|' order by k.user_id::text, k.build_id), '')), 12) from public.build_bookmarks k),
    '실행 전 11번과 같음', null
  union all select 17, '적어 둘 값: 글 / 댓글 / 문서 댓글 / 문의 (각 줄 수 · 내용 지문 앞 12자리)',
    (select count(*) || '·' || left(md5(coalesce(string_agg(p::text, '|' order by p.id), '')), 12) from public.posts p) || ' / ' || (select count(*) || '·' || left(md5(coalesce(string_agg(c::text, '|' order by c.id), '')), 12) from public.post_comments c) || ' / ' || (select count(*) || '·' || left(md5(coalesce(string_agg(d::text, '|' order by d.id), '')), 12) from public.doc_comments d) || ' / ' || (select count(*) || '·' || left(md5(coalesce(string_agg(i::text, '|' order by i.id), '')), 12) from public.inquiries i),
    '실행 전 12번과 같음', null
  union all select 18, '적어 둘 값: 휴대폰 알림 설정·기기 (설정 줄 수 · 지문 / 기기 수)',
    (select count(*) || '·' || left(md5(coalesce(string_agg(s::text, '|' order by s.user_id::text), '')), 12) from public.push_settings s) || ' / ' || (select count(*) from public.push_subscriptions),
    '실행 전 13번과 같음', null
  union all select 19, '적어 둘 값: 휴대폰 알림 묶음 push_group (기존 알림 종류 수 / 종류별 묶음 지문)',
    (select count(*) || ' / ' || md5(string_agg(k || '=' || coalesce(public.push_group(k), '-'), ',' order by k)) from (select distinct m[1] as k from pg_constraint c, regexp_matches(pg_get_constraintdef(c.oid), '''([a-z_]+)''', 'g') m where c.conname = 'notifications_kind_check' and c.conrelid = 'public.notifications'::regclass) x where k <> 'warning_received'),
    '실행 전 14번과 같음', '069는 warning_received 하나만 더한다 - 기존 종류의 묶음은 그대로여야 함'
  union all select 20, '적어 둘 값: 069가 부르거나 알림과 얽힌 기존 함수 7개 (본문·보안·search_path·권한 지문, 본문 줄바꿈 CR은 빼고)',
    (select count(*) || ' / ' || md5(string_agg(p.proname || '(' || oidvectortypes(p.proargtypes) || ')' || replace(p.prosrc, E'\r', '') || p.prosecdef::text || coalesce(array_to_string(p.proconfig, ','), '') || coalesce(p.proacl::text, ''), '|' order by p.proname, oidvectortypes(p.proargtypes))) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('notify', 'push_wanted', 'log_moderation', 'require_operator', 'active_restriction_id', 'mark_notifications_read', 'mark_all_notifications_read')),
    '실행 전 15번과 같음', '069는 이 함수들을 고치지 않는다'
) x
order by ord;
