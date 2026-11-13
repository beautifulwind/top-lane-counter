-- =====================================================================
-- 052(장인 새 팔로워 알림 - 하루 묶음) 실행 "후" 확인 조회 (읽기만 - 아무것도 바꾸지 않는다).
-- 052를 실행한 뒤 SQL Editor에 통째로 붙여넣어 실행하면 표 하나가 나온다 (맨 끝의 조회가 그 표다).
--   - [지금 값]이 [정상 값]과 맞는지 본다. 다르면 바로 알려 주세요.
--   - 14~16번은 check_new_followers_before.sql에서 적어 둔 값과 같아야 한다(052는 기존 데이터를 바꾸지 않는다).
--   - 17번(pg_cron 일정)은 일정 등록 SQL을 따로 실행한 뒤에 1이 된다(03:00 UTC = 한국 시간 낮 12시).
-- (SQL Editor는 로그인한 회원이 아니라서 함수를 직접 부르는 검사는 못 한다 - 표/함수 정의/권한만 본다)
-- 052를 아직 실행하지 않았어도 오류 없이 돌도록, 새 표/칸을 읽는 곳은 to_regclass/query_to_xml로 감쌌다.
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
tb as (
  select c.oid, c.relrowsecurity from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public' and c.relname = 'new_follower_counted' and c.relkind = 'r'
),
col as (
  select column_default from information_schema.columns
  where table_schema = 'public' and table_name = 'push_settings' and column_name = 'new_followers'
)
select ord as "순서", what as "항목", now_value as "지금 값", ok_value as "정상 값", memo as "메모"
from (
  select 1 as ord, '센 기록 표 new_follower_counted / RLS 켜짐 / 정책 수' as what,
    coalesce((select 'true / ' || relrowsecurity::text || ' / ' || (select count(*) from pg_policy where polrelid = tb.oid)::text from tb), '표 없음') as now_value,
    'true / true / 0' as ok_value, '정책 없음 = 직접 읽기/쓰기 불가' as memo
  union all select 2, '센 기록 표를 로그인 사용자/비로그인이 직접 읽거나 쓸 수 있나',
    coalesce((select bool_or(has_table_privilege(r, tb.oid, p))::text
                from tb, unnest(array['anon', 'authenticated']) r, unnest(array['select', 'insert', 'update', 'delete']) p), '표 없음'),
    'false', ''
  union all select 3, '센 기록 수 (실행 직후)',
    case when to_regclass('public.new_follower_counted') is null then '표 없음'
         else (xpath('/row/c/text()', query_to_xml('select count(*) as c from public.new_follower_counted', false, true, '')))[1]::text end,
    '0', '하루 묶음이 돌면 늘어남, 30일 뒤 지워짐'
  union all select 4, '알림 종류 new_followers / 있던 종류(notice_posted, followed_build_created, link_removed) 그대로',
    (select (def like '%new_followers%')::text || ' / '
            || (def like '%notice_posted%' and def like '%followed_build_created%' and def like '%link_removed%')::text from con),
    'true / true', ''
  union all select 5, '푸시 설정 칸 new_followers (기본값) / 본인이 바꿀 수 있나',
    coalesce((select column_default || ' / ' || has_column_privilege('authenticated', 'public.push_settings', 'new_followers', 'update')::text from col), '칸 없음'),
    'false / true', '기본 꺼짐'
  union all select 6, '푸시 묶음: 새 팔로워 / 공지 / 팔로우 새 빌드 / 장인 링크 (뒤 셋은 그대로)',
    coalesce(public.push_group('new_followers'), '없음') || ' / ' || coalesce(public.push_group('notice_posted'), '없음')
      || ' / ' || coalesce(public.push_group('followed_build_created'), '없음') || ' / ' || coalesce(public.push_group('link_removed'), '없음'),
    'new_followers / notice / follow_builds / my_results', ''
  union all select 7, '푸시 보낼지 판단(push_wanted): 설정 줄이 없으면 새 팔로워는 꺼짐',
    coalesce((select (prosrc like '%s.new_followers from public.push_settings s where s.user_id = p_user), false)%')::text
                from fn where proname = 'push_wanted'), '없음'), 'true', ''
  union all select 8, '하루 묶음 new_follower_digest를 로그인 사용자/비로그인이 부를 수 있나',
    coalesce((select (has_function_privilege('anon', oid, 'execute') or has_function_privilege('authenticated', oid, 'execute'))::text
                from fn where proname = 'new_follower_digest'), '함수 없음'),
    'false', 'pg_cron만 부른다'
  union all select 9, '하루 묶음 규칙: 25시간 창 / 30일 기록 / 장인만',
    coalesce((select (prosrc like '%25 hours%')::text || ' / ' || (prosrc like '%30 days%')::text || ' / ' || (prosrc like '%influencer is not null%')::text
                from fn where proname = 'new_follower_digest'), '함수 없음'),
    'true / true / true', ''
  union all select 10, '트리거: 장인 해제 -> 센 기록 삭제(052) / 팔로우 삭제(050, 그대로)',
    exists (select 1 from pg_trigger where tgname = 'new_follower_counted_on_influencer_end')::text || ' / '
      || exists (select 1 from pg_trigger where tgname = 'follows_on_influencer_end')::text,
    'true / true', ''
  union all select 11, '트리거 함수를 로그인 사용자/비로그인이 부를 수 있나',
    coalesce((select (has_function_privilege('anon', oid, 'execute') or has_function_privilege('authenticated', oid, 'execute'))::text
                from fn where proname = 'new_follower_counted_on_influencer_end'), '함수 없음'),
    'false', ''
  union all select 12, '읽기 정책 / 모두 읽음이 새 팔로워 알림을 운영진 알림으로 가리지 않음',
    coalesce((select (pg_get_expr(polqual, polrelid) not like '%new_followers%')::text from pg_policy
               where polrelid = 'public.notifications'::regclass and polname = 'notifications: 본인 읽기'), '정책 없음') || ' / '
      || coalesce((select (prosrc not like '%new_followers%')::text from fn where proname = 'mark_all_notifications_read'), '없음'),
    'true / true', '받는 사람 본인 알림'
  union all select 13, '새 팔로워 알림 수 (실행 직후)', (select count(*)::text from public.notifications where kind = 'new_followers'),
    '0', '첫 하루 묶음(한국 시간 낮 12시) 뒤 늘어남'
  union all select 14, '실행 전과 같아야 함: 인증된 장인 수 / 팔로우 수',
    (select count(*)::text from public.profiles where influencer is not null) || ' / ' || (select count(*)::text from public.influencer_follows),
    'check_new_followers_before 8번과 같음', '사이트 사용으로 늘 수 있음'
  union all select 15, '실행 전과 같아야 함: 알림 수', (select count(*)::text from public.notifications),
    'check_new_followers_before 9번과 같음', '사이트 사용으로 늘 수 있음'
  union all select 16, '실행 전과 같아야 함: 푸시 설정 줄 수', (select count(*)::text from public.push_settings),
    'check_new_followers_before 10번과 같음', '있던 줄은 모두 새 팔로워 꺼짐으로 시작'
  union all select 17, 'pg_cron 일정 new-follower-digest (하루 한 번)',
    case when to_regclass('cron.job') is null then 'pg_cron 없음'
         else (xpath('/row/c/text()', query_to_xml(
                 'select count(*)::text || coalesce('' / '' || min(schedule), '''') as c from cron.job where jobname = ''new-follower-digest''',
                 false, true, '')))[1]::text end,
    '0 (일정 등록 뒤 1 / 0 3 * * *)', '03:00 UTC = 한국 시간 낮 12:00'
  union all select 18, '설정값 수 (xp_rules)', (select count(*)::text from public.xp_rules), '63', '052는 설정값을 더하지 않는다'
) x
order by ord;
