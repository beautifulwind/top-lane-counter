-- =====================================================================
-- 069(운영자 경고) 실행 "전" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 069를 실행하기 전에 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~5번: [지금 값]이 [정상 값]과 모두 맞으면 069를 실행해도 된다. 하나라도 다르면 실행하지 말고 알려 주세요.
--   - 6~15번은 "적어 둘 값"이다. 069 실행 뒤 check_warnings_after.sql의 11~20번과 차례로 같아야 한다(069는 기존 데이터를 바꾸지 않는다).
--     (그 사이 사이트에서 누가 글을 쓰거나 알림이 생기면 달라질 수 있다 - 사람이 적은 시간에 이어서 실행해 주세요.)
--   - 함수 본문 지문은 줄바꿈 CR을 뺀 값으로 계산한다(SQL Editor가 CRLF로 붙여 넣어도 같은 값 - c5333b1과 같은 방식).
-- =====================================================================
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '068 실행됨 (표 user_restrictions·restriction_exemptions / 허용 목록 함수·정책 줄 수)' as what,
    coalesce(to_regclass('public.user_restrictions')::text, '없음') || ' / ' || coalesce(to_regclass('public.restriction_exemptions')::text, '없음')
      || ' / ' || case when to_regclass('public.restriction_exemptions') is null then '없음' else
           (xpath('/row/c/text()', query_to_xml('select count(*) filter (where kind = ''function'') || ''·'' || count(*) filter (where kind = ''policy'') as c from public.restriction_exemptions', false, true, '')))[1]::text end as now_value,
    'user_restrictions / restriction_exemptions / 69·8' as ok_value, '없음이면 068부터 실행' as memo
  union all select 2, '069 아직 안 함 (표 user_warnings 없음 / 함수 warn_user 없음 / 알림 읽음 트리거 0 / 알림 종류에 warning_received 없음)',
    coalesce(to_regclass('public.user_warnings')::text, '없음') || ' / ' || coalesce(to_regprocedure('public.warn_user(uuid, text)')::text, '없음')
      || ' / ' || (select count(*) from pg_trigger where tgname = 'notifications_warning_read')
      || ' / ' || (select (pg_get_constraintdef(oid) like '%warning_received%')::text from pg_constraint where conname = 'notifications_kind_check' and conrelid = 'public.notifications'::regclass),
    '없음 / 없음 / 0 / false', '하나라도 다르면 069를 이미 실행한 것 - 다시 실행하지 말고 알려 주세요'
  union all select 3, '고칠 제약 2개 / 함수 push_group 1벌 / 067 빌드 수정 알림 종류 있음',
    (select count(*) from pg_constraint where conname in ('notifications_kind_check', 'moderation_log_action_check'))
      || ' / ' || (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'push_group')
      || ' / ' || (select (pg_get_constraintdef(oid) like '%build_edited%')::text from pg_constraint where conname = 'notifications_kind_check' and conrelid = 'public.notifications'::regclass),
    '2 / 1 / true', null
  union all select 4, '운영자(admin) 수',
    (select count(*) from public.profiles where role = 'admin')::text, '1', '경고는 운영자만 보낸다'
  union all select 5, '일반 사용자가 부를 수 있는 쓰기 함수 수 (volatile, 트리거 아님)',
    (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.prokind = 'f' and p.provolatile = 'v' and p.prorettype <> 'trigger'::regtype
        and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute')))::text,
    '98', '069 뒤에는 2개(warn_user·ack_warning)가 늘어 100. 다르면(누가 함수를 더했으면) 알려 주세요'
  union all select 6, '적어 둘 값: 알림 (줄 수 / 가장 큰 id / 내용 지문 - 읽음 표시·경고 알림은 빼고)',
    (select count(*) || ' / ' || coalesce(max(id), 0) || ' / ' || md5(coalesce(string_agg(concat_ws(',', n.id, n.user_id, n.kind, n.message, n.created_at, n.proposal_id, n.build_id, n.post_id, n.counter_id), '|' order by n.id), '')) from public.notifications n where n.kind <> 'warning_received'),
    '(이 값을 적어 둠)', '그 사이 사이트 활동으로 알림이 생겼다면 늘어난 것이 정상'
  union all select 7, '적어 둘 값: 처리 기록 moderation_log (줄 수 / 가장 큰 id / 내용 지문 - 경고 줄은 빼고)',
    (select count(*) || ' / ' || coalesce(max(id), 0) || ' / ' || md5(coalesce(string_agg(m::text, '|' order by m.id), '')) from public.moderation_log m where m.action <> 'warn_user'),
    '(이 값을 적어 둠)', null
  union all select 8, '적어 둘 값: 활동 제한 기록 user_restrictions (줄 수 / 가장 큰 id / 내용 지문)',
    (select count(*) || ' / ' || coalesce(max(id), 0) || ' / ' || md5(coalesce(string_agg(r::text, '|' order by r.id), '')) from public.user_restrictions r),
    '(이 값을 적어 둠)', null
  union all select 9, '적어 둘 값: 068 허용 목록 (줄 수 / 내용 지문 - 069가 더하는 2줄은 빼고)',
    (select count(*) || ' / ' || md5(coalesce(string_agg(e::text, '|' order by e.kind, e.name), '')) from public.restriction_exemptions e where e.name not in ('warn_user(uuid, text)', 'ack_warning(bigint)')),
    '(이 값을 적어 둠)', null
  union all select 10, '적어 둘 값: 프로필 (줄 수 / 내용 지문 - 마지막 접속 시각은 빼고)',
    (select count(*) || ' / ' || md5(coalesce(string_agg((to_jsonb(p) - 'last_seen_at')::text, '|' order by p.id), '')) from public.profiles p),
    '(이 값을 적어 둠)', null
  union all select 11, '적어 둘 값: 빌드 / 추천 / 수정 기록 / 북마크 (각 줄 수 · 내용 지문 앞 12자리)',
    (select count(*) || '·' || left(md5(coalesce(string_agg(b::text, '|' order by b.id), '')), 12) from public.builds b) || ' / ' || (select count(*) || '·' || left(md5(coalesce(string_agg(v::text, '|' order by v.build_id, v.user_id::text), '')), 12) from public.build_votes v) || ' / ' || (select count(*) || '·' || left(md5(coalesce(string_agg(r::text, '|' order by r.id), '')), 12) from public.build_revisions r) || ' / ' || (select count(*) || '·' || left(md5(coalesce(string_agg(k::text, '|' order by k.user_id::text, k.build_id), '')), 12) from public.build_bookmarks k),
    '(이 값을 적어 둠)', null
  union all select 12, '적어 둘 값: 글 / 댓글 / 문서 댓글 / 문의 (각 줄 수 · 내용 지문 앞 12자리)',
    (select count(*) || '·' || left(md5(coalesce(string_agg(p::text, '|' order by p.id), '')), 12) from public.posts p) || ' / ' || (select count(*) || '·' || left(md5(coalesce(string_agg(c::text, '|' order by c.id), '')), 12) from public.post_comments c) || ' / ' || (select count(*) || '·' || left(md5(coalesce(string_agg(d::text, '|' order by d.id), '')), 12) from public.doc_comments d) || ' / ' || (select count(*) || '·' || left(md5(coalesce(string_agg(i::text, '|' order by i.id), '')), 12) from public.inquiries i),
    '(이 값을 적어 둠)', null
  union all select 13, '적어 둘 값: 휴대폰 알림 설정·기기 (설정 줄 수 · 지문 / 기기 수)',
    (select count(*) || '·' || left(md5(coalesce(string_agg(s::text, '|' order by s.user_id::text), '')), 12) from public.push_settings s) || ' / ' || (select count(*) from public.push_subscriptions),
    '(이 값을 적어 둠)', null
  union all select 14, '적어 둘 값: 휴대폰 알림 묶음 push_group (기존 알림 종류 수 / 종류별 묶음 지문)',
    (select count(*) || ' / ' || md5(string_agg(k || '=' || coalesce(public.push_group(k), '-'), ',' order by k)) from (select distinct m[1] as k from pg_constraint c, regexp_matches(pg_get_constraintdef(c.oid), '''([a-z_]+)''', 'g') m where c.conname = 'notifications_kind_check' and c.conrelid = 'public.notifications'::regclass) x where k <> 'warning_received'),
    '(이 값을 적어 둠)', '069는 warning_received 하나만 더한다 - 기존 종류의 묶음은 그대로여야 함'
  union all select 15, '적어 둘 값: 069가 부르거나 알림과 얽힌 기존 함수 7개 (본문·보안·search_path·권한 지문, 본문 줄바꿈 CR은 빼고)',
    (select count(*) || ' / ' || md5(string_agg(p.proname || '(' || oidvectortypes(p.proargtypes) || ')' || replace(p.prosrc, E'\r', '') || p.prosecdef::text || coalesce(array_to_string(p.proconfig, ','), '') || coalesce(p.proacl::text, ''), '|' order by p.proname, oidvectortypes(p.proargtypes))) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('notify', 'push_wanted', 'log_moderation', 'require_operator', 'active_restriction_id', 'mark_notifications_read', 'mark_all_notifications_read')),
    '(이 값을 적어 둠)', '069는 이 함수들을 고치지 않는다'
) x
order by ord;
