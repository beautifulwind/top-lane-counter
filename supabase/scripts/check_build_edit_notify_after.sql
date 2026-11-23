-- =====================================================================
-- 067(빌드 수정 알림) 실행 "뒤" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 067을 실행한 "직후"(사이트에서 누가 빌드를 고치기 전) SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - 1~9번: [지금 값]이 [정상 값]과 모두 맞아야 한다. 하나라도 다르면 알려 주세요. (웹 push는 그다음)
--   - 10~13번: 실행 전 check_build_edit_notify_before.sql의 7~10번에 적어 둔 값과 같아야 한다 (067은 기존 데이터를 바꾸지 않는다).
--   - 14번(알림 전체)은 "실행 직후 기준"이다: 실행 전 11번과 같아야 하지만, 그 사이 누가 빌드를 고쳤다면 그만큼 늘어난 것이 정상이다.
--     15번(build_edited를 뺀 알림)은 언제 실행해도 실행 전 11번과 같아야 한다(그 사이 다른 알림이 생기지 않았다면).
-- =====================================================================
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '새 표 build_edit_notices (칸)' as what,
    coalesce((select string_agg(column_name || ':' || data_type, ', ' order by ordinal_position) from information_schema.columns
               where table_schema = 'public' and table_name = 'build_edit_notices'), '없음') as now_value,
    'notification_id:bigint, user_id:uuid, build_id:bigint, editor_id:uuid, author_id:uuid, audience:text, edits:integer, last_kind:text, last_at:timestamp with time zone' as ok_value, null as memo
  union all select 2, '연결 (알림·받는 사람·빌드는 함께 지움 cascade 3개 / 수정한 사람·작성자는 탈퇴 때 비움 set null 2개)',
    (select count(*) filter (where confdeltype = 'c') || ' / ' || count(*) filter (where confdeltype = 'n')
       from pg_constraint where conrelid = to_regclass('public.build_edit_notices') and contype = 'f'),
    '3 / 2', null
  union all select 3, 'RLS 켬 / 정책 수 / 로그인·비로그인 읽기 권한',
    case when to_regclass('public.build_edit_notices') is null then '없음' else
      (select relrowsecurity::text from pg_class where oid = 'public.build_edit_notices'::regclass)
      || ' / ' || (select count(*) from pg_policy where polrelid = 'public.build_edit_notices'::regclass)
      || ' / ' || (has_table_privilege('authenticated', 'public.build_edit_notices', 'select') or has_table_privilege('anon', 'public.build_edit_notices', 'select'))::text end,
    'true / 0 / false', '아무도 직접 못 읽음 (알림 문장만 보임)'
  union all select 4, '새 함수 (4개)',
    (select string_agg(p.oid::regprocedure::text, ' / ' order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public' and p.proname in ('notify_build_edit', 'build_edit_message', 'build_revisions_notify', 'build_edit_notices_rerender')),
    'build_edit_message(text,uuid,uuid,integer,text) / build_edit_notices_rerender() / build_revisions_notify() / notify_build_edit(bigint,uuid,text)', null
  union all select 5, '함수를 로그인·비로그인이 직접 부를 수 있음 (하나라도)',
    case when to_regprocedure('public.notify_build_edit(bigint,uuid,text)') is null then '없음' else
      (has_function_privilege('authenticated', 'public.notify_build_edit(bigint,uuid,text)', 'execute')
        or has_function_privilege('anon', 'public.notify_build_edit(bigint,uuid,text)', 'execute')
        or has_function_privilege('authenticated', 'public.build_edit_message(text,uuid,uuid,integer,text)', 'execute'))::text end,
    'false', null
  union all select 6, '트리거 (수정 기록 edit·revert 뒤 / 탈퇴 때 문장 다시 만들기)',
    coalesce((select string_agg(tgname || ':' || tgrelid::regclass::text, ' / ' order by tgname) from pg_trigger
               where tgname in ('build_revisions_notify', 'build_edit_notices_rerender')), '없음'),
    'build_edit_notices_rerender:build_edit_notices / build_revisions_notify:build_revisions', null
  union all select 7, '알림 종류 목록에 build_edited / 푸시 묶음',
    (pg_get_constraintdef((select oid from pg_constraint where conrelid = 'public.notifications'::regclass and conname = 'notifications_kind_check')) like '%build_edited%')::text
      || ' / ' || coalesce(public.push_group('build_edited'), '없음'),
    'true / build_edits', null
  union all select 8, '알림 설정 새 칸 build_edits (기본값 / 꺼 둔 사람 수 / 로그인이 고칠 수 있음)',
    coalesce((select column_default || ' / ' from information_schema.columns where table_schema = 'public' and table_name = 'push_settings' and column_name = 'build_edits'), '없음 / ')
      || case when exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'push_settings' and column_name = 'build_edits')
              then (xpath('/row/c/text()', query_to_xml('select count(*) as c from public.push_settings where not build_edits', false, true, '')))[1]::text
                   || ' / ' || has_column_privilege('authenticated', 'public.push_settings', 'build_edits', 'update')::text else '-' end,
    'true / 0 / true', '실행 직후에는 아무도 끄지 않았으므로 0. 마지막이 false면 설정을 끌 수 없음'
  union all select 9, '빌드 수정 알림 수 / 짝 줄 수',
    (select count(*) from public.notifications where kind = 'build_edited')
      || ' / ' || case when to_regclass('public.build_edit_notices') is null then '없음'
                       else (xpath('/row/c/text()', query_to_xml('select count(*) as c from public.build_edit_notices', false, true, '')))[1]::text end,
    '0 / 0', '실행 직후 기준. 그 뒤 누가 빌드를 고치면 둘이 같이 늘어나는 것이 정상 (두 숫자는 늘 같아야 함)'
  union all select 10, '적어 둘 값: 빌드 (줄 수 / 가장 큰 id / 추천 수 합계 / 비추천 수 합계 / 내용 지문)',
    (select count(*) || ' / ' || coalesce(max(id), 0) || ' / ' || coalesce(sum(up_count), 0) || ' / ' || coalesce(sum(down_count), 0)
       || ' / ' || md5(coalesce(string_agg(b::text, '|' order by b.id), '')) from public.builds b),
    '(이 값을 적어 둠)', '실행 전 값과 같아야 함'
  union all select 11, '적어 둘 값: 빌드 추천·비추천 (줄 수 / 추천 줄 / 비추천 줄 / 내용 지문)',
    (select count(*) || ' / ' || count(*) filter (where value = 1) || ' / ' || count(*) filter (where value = -1)
       || ' / ' || md5(coalesce(string_agg(v::text, '|' order by v.build_id, v.user_id::text), '')) from public.build_votes v),
    '(이 값을 적어 둠)', '실행 전 값과 같아야 함'
  union all select 12, '적어 둘 값: 빌드 수정 기록 (줄 수 / 가장 큰 id / 내용 지문)',
    (select count(*) || ' / ' || coalesce(max(id), 0) || ' / ' || md5(coalesce(string_agg(r::text, '|' order by r.id), '')) from public.build_revisions r),
    '(이 값을 적어 둠)', '실행 전 값과 같아야 함'
  union all select 13, '적어 둘 값: 알림 설정 (줄 수 / 기존 칸 7개만 이름으로 직접 골라 비교: user_id·staff_new·my_results·follow_builds·notice·new_followers·updated_at / 내용 지문)',
    (select count(*) || ' / 비교 칸 ' || (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'push_settings' and column_name in ('user_id','staff_new','my_results','follow_builds','notice','new_followers','updated_at')) || '개 / ' || md5(coalesce(string_agg(concat_ws(',', s.user_id, s.staff_new, s.my_results, s.follow_builds, s.notice, s.new_followers, s.updated_at), '|' order by s.user_id::text), ''))
       from public.push_settings s),
    '(이 값을 적어 둠)', '실행 전 값과 같아야 함'
  union all select 14, '적어 둘 값: 알림 전체 (줄 수 / 가장 큰 id / 내용 지문 - 읽음 표시는 빼고)',
    (select count(*) || ' / ' || coalesce(max(id), 0) || ' / '
       || md5(coalesce(string_agg(concat_ws(',', n.id, n.user_id, n.kind, n.message, n.created_at, n.proposal_id, n.build_id, n.post_id, n.counter_id), '|' order by n.id), ''))
       from public.notifications n),
    '(이 값을 적어 둠)', '실행 직후 기준: 실행 전 11번과 같아야 함 (그 사이 빌드 수정이 있었다면 늘어난 것이 정상 - 15번을 보세요)'
  union all select 15, '알림 중 build_edited를 뺀 것 (줄 수 / 가장 큰 id / 내용 지문)',
    (select count(*) || ' / ' || coalesce(max(id), 0) || ' / '
       || md5(coalesce(string_agg(concat_ws(',', n.id, n.user_id, n.kind, n.message, n.created_at, n.proposal_id, n.build_id, n.post_id, n.counter_id), '|' order by n.id), ''))
       from public.notifications n where n.kind <> 'build_edited'),
    '실행 전 11번과 같음', '067은 기존 알림을 바꾸지 않는다 (그 사이 다른 종류의 알림이 생겼다면 달라질 수 있음)'
) x
order by ord;
