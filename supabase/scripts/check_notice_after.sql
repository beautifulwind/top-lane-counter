-- =====================================================================
-- 051(공지 + 공지 알림) 실행 "후" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 051을 실행한 뒤 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - [지금 값]이 [정상 값]과 맞는지 본다. 다르면 바로 알려 주세요.
--   - 16~18번은 check_notice_before.sql에서 적어 둔 값과 같아야 한다(051은 기존 데이터를 바꾸지 않는다).
--   - 19번(pg_cron 일정)은 일정 등록 SQL을 따로 실행한 뒤에 1이 된다. 등록 뒤 이 파일을 한 번 더 실행해 확인한다.
-- (SQL Editor는 로그인한 회원이 아니라서 함수를 직접 부르는 검사는 못 한다 - 표/함수 정의/권한만 본다)
-- 051을 아직 실행하지 않았어도 오류 없이 돌도록, 새 표/칸을 읽는 곳은 to_regclass/query_to_xml로 감쌌다.
-- =====================================================================
with fn as (
  select p.oid, p.proname, p.prosrc
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
),
con as (
  select pg_get_constraintdef(oid) as def from pg_constraint
  where conname = 'notifications_kind_check' and conrelid = 'public.notifications'::regclass
),
q as (
  select c.oid, c.relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relname = 'notice_notify_queue' and c.relkind = 'r'
),
col as (
  select table_name, column_name, column_default from information_schema.columns
  where table_schema = 'public' and ((table_name = 'posts' and column_name = 'is_notice') or (table_name = 'push_settings' and column_name = 'notice'))
)
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '글의 공지 칸 posts.is_notice (기본값)' as what,
    coalesce((select column_default from col where table_name = 'posts'), '칸 없음') as now_value, 'false' as ok_value, '' as memo
  union all select 2, '공지 수 (실행 직후)',
    case when not exists (select 1 from col where table_name = 'posts') then '칸 없음'
         else (xpath('/row/c/text()', query_to_xml('select count(*) as c from public.posts where is_notice', false, true, '')))[1]::text end,
    '0', '화면에서 공지를 올리면 늘어남'
  union all select 3, '대기 줄 표 notice_notify_queue / RLS 켜짐 / 정책 수',
    coalesce((select 'true / ' || relrowsecurity::text || ' / ' || (select count(*) from pg_policy where polrelid = q.oid)::text from q), '표 없음'),
    'true / true / 0', '정책 없음 = 직접 읽기/쓰기 불가, 함수로만'
  union all select 4, '대기 줄을 로그인 사용자/비로그인이 직접 읽거나 쓸 수 있나',
    coalesce((select bool_or(has_table_privilege(r, q.oid, p))::text
                from q, unnest(array['anon', 'authenticated']) r, unnest(array['select', 'insert', 'update', 'delete']) p), '표 없음'),
    'false', ''
  union all select 5, '알림 종류 notice_posted / 있던 종류(followed_build_created, link_removed, post_created) 그대로',
    (select (def like '%notice_posted%')::text || ' / '
            || (def like '%followed_build_created%' and def like '%link_removed%' and def like '%post_created%')::text from con),
    'true / true', ''
  union all select 6, '같은 공지 알림은 한 사람에게 한 개 (부분 유일 인덱스 notifications_notice_once)',
    (to_regclass('public.notifications_notice_once') is not null)::text, 'true', ''
  union all select 7, '푸시 설정 칸 notice (기본값) / 본인이 바꿀 수 있나',
    coalesce((select column_default || ' / ' || has_column_privilege('authenticated', 'public.push_settings', 'notice', 'update')::text
                from col where table_name = 'push_settings'), '칸 없음'),
    'true / true', '기본 켜짐'
  union all select 8, '푸시 묶음: 공지 / 팔로우 새 빌드 / 장인 링크 / 새 글 (뒤 셋은 그대로)',
    coalesce(public.push_group('notice_posted'), '없음') || ' / ' || coalesce(public.push_group('followed_build_created'), '없음')
      || ' / ' || coalesce(public.push_group('link_removed'), '없음') || ' / ' || coalesce(public.push_group('post_created'), '없음'),
    'notice / follow_builds / my_results / staff_new', ''
  union all select 9, '푸시 보낼지 판단(push_wanted)이 notice 칸을 봄 (설정 줄이 없으면 켜짐)',
    coalesce((select (prosrc like '%s.notice from%')::text from fn where proname = 'push_wanted'), '없음'), 'true', ''
  union all select 10, '공지 올리기 create_notice: 비로그인 / 로그인 사용자 실행 권한',
    coalesce((select has_function_privilege('anon', oid, 'execute')::text || ' / ' || has_function_privilege('authenticated', oid, 'execute')::text
                from fn where proname = 'create_notice'), '함수 없음'),
    'false / true', '운영자인지는 함수 안에서'
  union all select 11, 'create_notice가 운영자 전용 확인(require_operator) + [알림 보내기] 끔이면 대기 줄 안 넣음',
    coalesce((select (prosrc like '%require_operator()%' and prosrc like '%p_notify%')::text from fn where proname = 'create_notice'), '함수 없음'),
    'true', '감독관/일반 회원/게스트/운영자 모드 꺼짐 거부'
  union all select 12, '알림 나눠 보내기 notice_notify_dispatch를 로그인 사용자/비로그인이 부를 수 있나',
    coalesce((select (has_function_privilege('anon', oid, 'execute') or has_function_privilege('authenticated', oid, 'execute'))::text
                from fn where proname = 'notice_notify_dispatch'), '함수 없음'),
    'false', 'pg_cron만 부른다'
  union all select 13, '목록 board_page가 공지 칸과 고정 공지(notices)를 줌',
    coalesce((select (prosrc like '%is_notice%' and prosrc like '%''notices''%')::text from fn where proname = 'board_page'), '없음'), 'true', ''
  union all select 14, '읽기 정책 / 모두 읽음이 공지 알림을 운영진 알림으로 가리지 않음',
    coalesce((select (pg_get_expr(polqual, polrelid) not like '%notice_posted%')::text from pg_policy
               where polrelid = 'public.notifications'::regclass and polname = 'notifications: 본인 읽기'), '정책 없음') || ' / '
      || coalesce((select (prosrc not like '%notice_posted%')::text from fn where proname = 'mark_all_notifications_read'), '없음'),
    'true / true', '받는 사람 본인 알림 = 운영자 모드와 관계없이 보이고 모두 읽음에 함께 처리'
  union all select 15, '대기 줄 수 / 공지 알림 수 (실행 직후)',
    case when to_regclass('public.notice_notify_queue') is null then '표 없음'
         else (xpath('/row/c/text()', query_to_xml(
                 'select (select count(*) from public.notice_notify_queue)::text || '' / ''
                      || (select count(*) from public.notifications where kind = ''notice_posted'')::text as c',
                 false, true, '')))[1]::text end,
    '0 / 0', '공지를 올리면 대기 줄 1 -> 1분마다 1000명씩 알림'
  union all select 16, '실행 전과 같아야 함: 가입자 수 (게스트)',
    (select count(*)::text from public.profiles) || ' (게스트 ' || (select count(*)::text from public.profiles where is_guest) || ')',
    'check_notice_before 8번과 같음', ''
  union all select 17, '실행 전과 같아야 함: 알림 수', (select count(*)::text from public.notifications),
    'check_notice_before 9번과 같음', '사이트 사용으로 늘 수 있음'
  union all select 18, '실행 전과 같아야 함: 글 수 (지운 글 제외)', (select count(*)::text from public.posts where deleted_at is null),
    'check_notice_before 10번과 같음', '사이트 사용으로 늘 수 있음'
  union all select 19, 'pg_cron 일정 notice-notify (1분마다 공지 알림 나눠 보내기)',
    case when to_regclass('cron.job') is null then 'pg_cron 없음'
         else (xpath('/row/c/text()', query_to_xml(
                 'select count(*)::text || coalesce('' / '' || min(schedule), '''') as c from cron.job where jobname = ''notice-notify''',
                 false, true, '')))[1]::text end,
    '0 (일정 등록 뒤 1 / * * * * *)', '등록 SQL을 따로 실행하면 1'
  union all select 20, '설정값 수 (xp_rules)', (select count(*)::text from public.xp_rules), '63', '051은 설정값을 더하지 않는다'
) x
order by ord;
